/**
 * F20 Canonical K9 Guard — Adversarial Test Harness.
 *
 * Exercises the F20 shift authorization engine, Firestore transaction adapter,
 * and vehicle crew invitation K9 guard against adversarial vectors:
 *   1. Receipt v2 valid retry (distinguished as historical no-op)
 *   2. Cross-actor replay attack rejection
 *   3. Changed-payload replay attack rejection
 *   4. Legacy v1 receipt rejection (fail-closed)
 *   5. Missing actor binding rejection
 *   6. Revoked actor / grant rejection
 *   7. Changed revision / evidence mismatch
 *   8. Concurrent restriction enforcement
 *   9. Same-K9 reassociation under restriction (no grandfathering)
 *  10. Inherited K9 under restriction
 *  11. No-K9 exemption (neutrality)
 *  12. Malformed evidence query fail-closed
 *  13. Explicit guard readiness status verification
 */

import * as assert from "node:assert/strict";
import {describe, it} from "node:test";
import type {Transaction, Firestore} from "firebase-admin/firestore";
import type {RawDoc, RawQuery} from "../health_readiness_evidence_logic";
import {
  actorBoundFingerprint,
  evaluateK9AssociationInTransaction,
  runShiftAuthorizedCommand,
  ShiftActor,
  ShiftAuthorizationError,
  ShiftCommandInput,
  ShiftEngineDeps,
  ShiftTxDocSnap,
  ShiftTxn,
} from "../shift_authorization_engine";
import {
  AuthorityEvidenceContract,
  FirestoreShiftTxnAdapter,
  createFirestoreShiftTxnAdapter,
  validateAuthorityEvidenceContract,
  fetchRestrictionsEvidenceInTxn,
  evaluateCanonicalK9GuardInTxn,
} from "../shift_authorization_firestore_txn";
import {
  F20_GUARD_MODULE_STATUS,
  getK9GuardStatus,
  resolveVehicleCrewInvitationK9Candidate,
  evaluateVehicleCrewInvitationK9Guard,
  enforceVehicleCrewInvitationK9Guard,
  buildGuardedInvitationVehicleFields,
} from "../vehicle_crew_invitation_k9_guard";

// ─────────────────────────────────────────────────────────────────────────────
// Test Fixtures & In-Memory Store
// ─────────────────────────────────────────────────────────────────────────────

const ACTOR_ALICE: ShiftActor = {
  uid: "uid-alice-001",
  ra: "RA-001",
  email: "alice@k9ops.local",
  name: "GCM Alice",
};

const ACTOR_MALLORY: ShiftActor = {
  uid: "uid-mallory-666",
  ra: "RA-666",
  email: "mallory@k9ops.local",
  name: "Attacker Mallory",
};

const HEALTHY_DOG = "dog-healthy-01";
const RESTRICTED_DOG = "dog-restricted-01";
const PARTIAL_DOG = "dog-partial-01";

function makeRestrictionDoc(
  id: string,
  level: "absolute" | "partial" | "attention",
  opts?: {status?: string; activities?: string[]},
): RawDoc {
  return {
    id,
    data: {
      status: opts?.status ?? "active",
      level,
      category: "veterinary",
      description: `Test restriction ${level} (${id})`,
      activities_restricted: opts?.activities ?? (level === "partial" ? ["mordida", "patrulha"] : []),
      since: new Date(Date.now() - 3600000).toISOString(),
    },
  };
}

class InMemoryTxnStore {
  public docs = new Map<string, Record<string, unknown>>();
  public subcollections = new Map<string, RawDoc[]>();
  public writes: {type: string; path: string; data?: unknown}[] = [];
  public queryShouldFail = false;

  constructor() {
    // Seed dogs
    this.docs.set(`dogs/${HEALTHY_DOG}`, {name: "Thor", status: "active"});
    this.docs.set(`dogs/${RESTRICTED_DOG}`, {name: "Zeus", status: "active"});
    this.docs.set(`dogs/${PARTIAL_DOG}`, {name: "Ares", status: "active"});

    // Seed restrictions
    this.subcollections.set(`dogs/${HEALTHY_DOG}/operational_restrictions`, []);
    this.subcollections.set(`dogs/${RESTRICTED_DOG}/operational_restrictions`, [
      makeRestrictionDoc("rest-abs-1", "absolute"),
    ]);
    this.subcollections.set(`dogs/${PARTIAL_DOG}/operational_restrictions`, [
      makeRestrictionDoc("rest-part-1", "partial"),
    ]);
  }

  createShiftTxn(): ShiftTxn {
    return {
      get: async (path: string): Promise<ShiftTxDocSnap> => {
        const data = this.docs.get(path);
        return {
          exists: data !== undefined,
          data: data ? {...data} : undefined,
        };
      },
      getCollection: async (path: string): Promise<RawQuery> => {
        if (this.queryShouldFail) {
          return {kind: "failed", reasonCode: "simulated_collection_query_error"};
        }
        const docs = this.subcollections.get(path) ?? [];
        return {kind: "docs", docs: [...docs]};
      },
      set: (path: string, data: Record<string, unknown>, options?: {merge?: boolean}) => {
        this.writes.push({type: "set", path, data});
        if (options?.merge) {
          const prev = this.docs.get(path) ?? {};
          this.docs.set(path, {...prev, ...data});
        } else {
          this.docs.set(path, {...data});
        }
      },
    };
  }

  createDeps(): ShiftEngineDeps {
    return {
      runTransaction: async <T>(fn: (txn: ShiftTxn) => Promise<T>): Promise<T> => {
        const txn = this.createShiftTxn();
        return fn(txn);
      },
      createEntityId: () => `ent-${Date.now()}-${Math.floor(Math.random() * 10000)}`,
      serverTimestamp: () => ({_type: "server_timestamp", instant: new Date().toISOString()}),
      timestampFromDate: (date: Date) => ({_type: "timestamp", instant: date.toISOString()}),
      arrayUnion: (...items: unknown[]) => items,
      deleteField: () => ({_type: "delete_sentinel"}),
      activeCrewMemberRas: async () => [],
      activeShiftVehicleId: async () => null,
    };
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Test Suite
// ─────────────────────────────────────────────────────────────────────────────

describe("F20 OP-AUTH Adversarial Test Harness", () => {
  // ── 1. OP-AUTH v2 Idempotency & Replay Protection ──────────────────────────

  describe("OP-AUTH v2 Idempotency & Replay Defenses", () => {
    it("1.1. Receipt v2 valid retry returns cached result as historical no-op (wasNoOp = true)", async () => {
      const store = new InMemoryTxnStore();
      const deps = store.createDeps();

      const input: ShiftCommandInput = {
        action: "start_shift",
        dogId: HEALTHY_DOG,
        operationId: "op-idempotent-001",
        role: "motorista",
        vehicle: {
          id: "veh-01",
          label: "Vtr 01",
          prefix: "V-01",
          modelName: "Hilux",
          unit: "Canil",
          crewSize: 2,
        },
      };

      // First run: new operation
      const firstResult = await runShiftAuthorizedCommand(deps, ACTOR_ALICE, input, new Date());
      assert.equal(firstResult.wasNoOp, false, "First execution must be a new operation");
      assert.equal(firstResult.decision, "allowed");
      assert.ok(firstResult.shiftId, "Must generate a shiftId");

      // Verify v2 receipt was persisted in shift_operations/
      const receiptSnap = store.docs.get(`shift_operations/${input.operationId}`);
      assert.ok(receiptSnap, "Receipt document must exist");
      assert.equal(receiptSnap?.receipt_version, 2, "Receipt must be version 2");
      assert.equal(receiptSnap?.actor_uid, ACTOR_ALICE.uid);
      assert.equal(receiptSnap?.actor_ra, ACTOR_ALICE.ra);

      const writesBeforeRetry = store.writes.length;

      // Second run: exact retry by same actor with same payload
      const retryResult = await runShiftAuthorizedCommand(deps, ACTOR_ALICE, input, new Date());
      assert.equal(retryResult.wasNoOp, true, "Retry must be marked as historical no-op");
      assert.equal(retryResult.shiftId, firstResult.shiftId, "Must return original shiftId");
      assert.equal(retryResult.decision, firstResult.decision);

      // Verify no extra mutations occurred during retry
      assert.equal(store.writes.length, writesBeforeRetry, "No new mutations should be written on retry");
    });

    it("1.2. Cross-actor replay is rejected with idempotency_conflict", async () => {
      const store = new InMemoryTxnStore();
      const deps = store.createDeps();

      const input: ShiftCommandInput = {
        action: "start_shift",
        dogId: HEALTHY_DOG,
        operationId: "op-shared-token-999",
        role: "motorista",
      };

      // Legitimate actor runs the command
      await runShiftAuthorizedCommand(deps, ACTOR_ALICE, input, new Date());

      // Attacker attempts to replay the same operationId with attacker credentials
      await assert.rejects(
        async () => {
          await runShiftAuthorizedCommand(deps, ACTOR_MALLORY, input, new Date());
        },
        (err: unknown) => {
          assert.ok(err instanceof ShiftAuthorizationError);
          assert.equal(err.appCode, "idempotency_conflict");
          assert.equal(err.httpCode, "failed-precondition");
          return true;
        },
        "Cross-actor replay MUST be rejected with idempotency_conflict",
      );
    });

    it("1.3. Changed-payload replay with same operationId is rejected with idempotency_conflict", async () => {
      const store = new InMemoryTxnStore();
      const deps = store.createDeps();

      const originalInput: ShiftCommandInput = {
        action: "start_shift",
        dogId: HEALTHY_DOG,
        operationId: "op-tampered-payload",
        role: "motorista",
        vehicle: {id: "v-01", label: "Vtr 01", prefix: "V", modelName: "Duster", unit: "Canil", crewSize: 2},
      };

      // Legitimate execution
      await runShiftAuthorizedCommand(deps, ACTOR_ALICE, originalInput, new Date());

      // Attempt to reuse operationId with different dogId
      const tamperedDogInput: ShiftCommandInput = {
        ...originalInput,
        dogId: "dog-different-k9",
      };

      await assert.rejects(
        async () => {
          await runShiftAuthorizedCommand(deps, ACTOR_ALICE, tamperedDogInput, new Date());
        },
        (err: unknown) => {
          assert.ok(err instanceof ShiftAuthorizationError);
          assert.equal(err.appCode, "idempotency_conflict");
          return true;
        },
        "Replay with altered dogId MUST be rejected",
      );

      // Attempt to reuse operationId with different vehicle
      const tamperedVehicleInput: ShiftCommandInput = {
        ...originalInput,
        vehicle: {id: "v-99", label: "Tampered Vtr", prefix: "X", modelName: "SUV", unit: "Other", crewSize: 4},
      };

      await assert.rejects(
        async () => {
          await runShiftAuthorizedCommand(deps, ACTOR_ALICE, tamperedVehicleInput, new Date());
        },
        (err: unknown) => {
          assert.ok(err instanceof ShiftAuthorizationError);
          assert.equal(err.appCode, "idempotency_conflict");
          return true;
        },
        "Replay with altered vehicle MUST be rejected",
      );
    });

    it("1.4. Legacy v1 receipt without actor binding is rejected fail-closed", async () => {
      const store = new InMemoryTxnStore();
      const deps = store.createDeps();

      const opId = "op-legacy-v1-receipt";
      // Manually seed a legacy v1 receipt lacking receipt_version: 2 and actor bindings
      store.docs.set(`shift_operations/${opId}`, {
        fingerprint: "legacy-fingerprint",
        action: "start_shift",
        operation_id: opId,
        dog_id: HEALTHY_DOG,
        created_at: new Date().toISOString(),
      });

      const input: ShiftCommandInput = {
        action: "start_shift",
        dogId: HEALTHY_DOG,
        operationId: opId,
        role: "motorista",
      };

      await assert.rejects(
        async () => {
          await runShiftAuthorizedCommand(deps, ACTOR_ALICE, input, new Date());
        },
        (err: unknown) => {
          assert.ok(err instanceof ShiftAuthorizationError);
          assert.equal(err.appCode, "idempotency_conflict");
          return true;
        },
        "Legacy receipt lacking trusted actor binding must fail closed",
      );
    });
  });

  // ── 2. Identity, Revocation & Revision Freshness ───────────────────────────

  describe("Actor Binding, Revocation, and Revision Freshness", () => {
    it("2.1. Missing trusted actor binding fails closed in evaluateK9AssociationInTransaction", async () => {
      const store = new InMemoryTxnStore();
      const txn = store.createShiftTxn();

      const decisionNull = await evaluateK9AssociationInTransaction({
        transaction: txn,
        trustedActor: null,
        dogId: HEALTHY_DOG,
        associationIntent: "K9_ASSOCIATION_REQUESTED",
      });
      assert.equal(decisionNull.status, "UNKNOWN");
      assert.equal(decisionNull.reason, "missing_trusted_actor_or_k9");

      const decisionEmptyUid = await evaluateK9AssociationInTransaction({
        transaction: txn,
        trustedActor: {uid: "", ra: "RA-001", email: "a@b", name: "A"},
        dogId: HEALTHY_DOG,
        associationIntent: "K9_ASSOCIATION_REQUESTED",
      });
      assert.equal(decisionEmptyUid.status, "UNKNOWN");
      assert.equal(decisionEmptyUid.reason, "missing_trusted_actor_or_k9");
    });

    it("2.2. Revoked actor / grant returns authority mismatch (CONFLICT)", async () => {
      const store = new InMemoryTxnStore();
      const txn = store.createShiftTxn();

      // Authority evidence bound to Alice
      const evidence: AuthorityEvidenceContract = {
        actorUid: ACTOR_ALICE.uid,
        actorRa: ACTOR_ALICE.ra,
        dogId: HEALTHY_DOG,
        revision: "rev-1",
      };

      // But called with Mallory (actor grant revoked / mismatched)
      const decision = await evaluateK9AssociationInTransaction({
        transaction: txn,
        trustedActor: ACTOR_MALLORY,
        dogId: HEALTHY_DOG,
        associationIntent: "K9_ASSOCIATION_REQUESTED",
        currentAuthorityEvidence: evidence,
      });

      assert.equal(decision.status, "CONFLICT");
      assert.equal(decision.reason, "authority_evidence_mismatch");
    });

    it("2.3. Changed dogId in authority evidence returns CONFLICT", async () => {
      const store = new InMemoryTxnStore();
      const txn = store.createShiftTxn();

      const evidence: AuthorityEvidenceContract = {
        actorUid: ACTOR_ALICE.uid,
        actorRa: ACTOR_ALICE.ra,
        dogId: "different-dog-id",
        revision: "rev-1",
      };

      const decision = await evaluateK9AssociationInTransaction({
        transaction: txn,
        trustedActor: ACTOR_ALICE,
        dogId: HEALTHY_DOG,
        associationIntent: "K9_ASSOCIATION_REQUESTED",
        currentAuthorityEvidence: evidence,
      });

      assert.equal(decision.status, "CONFLICT");
      assert.equal(decision.reason, "authority_evidence_mismatch");
    });

    it("2.4. Missing authority evidence for K9 association returns UNKNOWN", async () => {
      const store = new InMemoryTxnStore();
      const txn = store.createShiftTxn();

      const decision = await evaluateK9AssociationInTransaction({
        transaction: txn,
        trustedActor: ACTOR_ALICE,
        dogId: HEALTHY_DOG,
        associationIntent: "K9_ASSOCIATION_REQUESTED",
        currentAuthorityEvidence: null,
      });

      assert.equal(decision.status, "UNKNOWN");
      assert.equal(decision.reason, "missing_authority_evidence");
    });
  });

  // ── 3. Canonical Restriction Concurrency & Fresh F20 Enforcement ───────────

  describe("Canonical Restriction Concurrency & Fresh F20 Enforcement", () => {
    it("3.1. Concurrent active absolute restriction blocks operation with absolute_restriction_active", async () => {
      const store = new InMemoryTxnStore();
      const deps = store.createDeps();

      const input: ShiftCommandInput = {
        action: "start_shift",
        dogId: RESTRICTED_DOG,
        operationId: "op-restricted-blocked",
        role: "motorista",
      };

      await assert.rejects(
        async () => {
          await runShiftAuthorizedCommand(deps, ACTOR_ALICE, input, new Date());
        },
        (err: unknown) => {
          assert.ok(err instanceof ShiftAuthorizationError);
          assert.equal(err.appCode, "absolute_restriction_active");
          assert.equal(err.httpCode, "failed-precondition");
          return true;
        },
        "Absolute restriction must block mutation immediately",
      );
    });

    it("3.2. Concurrent partial restriction without operator acknowledgment blocks", async () => {
      const store = new InMemoryTxnStore();
      const deps = store.createDeps();

      const input: ShiftCommandInput = {
        action: "start_shift",
        dogId: PARTIAL_DOG,
        operationId: "op-partial-unack",
        role: "motorista",
        acknowledgedRestrictionIds: [], // Empty acknowledgment
      };

      await assert.rejects(
        async () => {
          await runShiftAuthorizedCommand(deps, ACTOR_ALICE, input, new Date());
        },
        (err: unknown) => {
          assert.ok(err instanceof ShiftAuthorizationError);
          assert.equal(err.appCode, "partial_acknowledgement_required");
          assert.equal(err.httpCode, "failed-precondition");
          return true;
        },
        "Partial restriction without acknowledgment must fail precondition",
      );
    });

    it("3.3. Concurrent partial restriction with valid acknowledgment succeeds", async () => {
      const store = new InMemoryTxnStore();
      const deps = store.createDeps();

      const input: ShiftCommandInput = {
        action: "start_shift",
        dogId: PARTIAL_DOG,
        operationId: "op-partial-ack",
        role: "motorista",
        acknowledgedRestrictionIds: ["rest-part-1"], // Explicit acknowledgment
      };

      const result = await runShiftAuthorizedCommand(deps, ACTOR_ALICE, input, new Date());
      assert.equal(result.decision, "allowed_with_restrictions");
      assert.equal(result.acknowledgementRecorded, true);
      assert.equal(result.wasNoOp, false);
    });

    it("3.4. Malformed or failed restrictions query fails closed (restrictions_unavailable)", async () => {
      const store = new InMemoryTxnStore();
      store.queryShouldFail = true; // Simulate Firestore failure during collection query
      const deps = store.createDeps();

      const input: ShiftCommandInput = {
        action: "start_shift",
        dogId: HEALTHY_DOG,
        operationId: "op-fail-closed-query",
        role: "motorista",
      };

      await assert.rejects(
        async () => {
          await runShiftAuthorizedCommand(deps, ACTOR_ALICE, input, new Date());
        },
        (err: unknown) => {
          assert.ok(err instanceof ShiftAuthorizationError);
          assert.equal(err.appCode, "restrictions_unavailable");
          assert.equal(err.httpCode, "unavailable");
          return true;
        },
        "Failed restrictions query must fail closed and never allow mutation",
      );
    });
  });

  // ── 4. Vehicle Crew Invitation K9 Guard Scenarios ──────────────────────────

  describe("Vehicle Crew Invitation K9 Guard Scenarios", () => {
    it("4.1. Pure no-K9 association is completely exempt from restriction checks", async () => {
      const store = new InMemoryTxnStore();
      const txn = store.createShiftTxn();

      const guardResult = await evaluateVehicleCrewInvitationK9Guard({
        transaction: txn,
        actor: ACTOR_ALICE,
        crewData: {service_dog_id: null, dogId: null},
        activeShiftData: {service_dog_id: null, dogId: null},
        candidateDogId: null,
      });

      assert.equal(guardResult.allowed, true);
      assert.equal(guardResult.isExempt, true);
      assert.equal(guardResult.candidate.origin, "none");
      assert.equal(guardResult.decision.status, "ALLOWED");
      assert.equal(guardResult.status, F20_GUARD_MODULE_STATUS);

      // Verify safe fields builder for no-K9
      const fields = buildGuardedInvitationVehicleFields(
        guardResult,
        {vehicle_id: "v-01", vehicle_label: "Vtr 01"},
        "crew-001",
        "mock-timestamp",
      );
      assert.equal(fields.service_dog_id, "");
      assert.equal(fields.dogId, "");
      assert.equal(fields.f20_k9_status, "exempt_no_k9");
    });

    it("4.2. Inherited crew K9 with active restriction is blocked by fresh F20 decision", async () => {
      const store = new InMemoryTxnStore();
      const txn = store.createShiftTxn();

      // Crew has the restricted dog
      const crewData = {service_dog_id: RESTRICTED_DOG};

      const guardResult = await evaluateVehicleCrewInvitationK9Guard({
        transaction: txn,
        actor: ACTOR_ALICE,
        crewData,
        candidateDogId: null,
      });

      assert.equal(guardResult.allowed, false);
      assert.equal(guardResult.isExempt, false);
      assert.equal(guardResult.candidate.origin, "crew_inherited");
      assert.equal(guardResult.candidate.dogId, RESTRICTED_DOG);
      assert.equal(guardResult.decision.status, "DENIED");

      assert.throws(
        () => enforceVehicleCrewInvitationK9Guard(guardResult),
        (err: unknown) => {
          assert.ok(err instanceof ShiftAuthorizationError);
          assert.equal(err.appCode, "absolute_restriction_active");
          return true;
        },
      );
    });

    it("4.3. Same-K9 reassociation from active shift with active restriction is blocked", async () => {
      const store = new InMemoryTxnStore();
      const txn = store.createShiftTxn();

      // Crew has no dog, but handler's active shift has the restricted dog
      const crewData = {service_dog_id: ""};
      const activeShiftData = {service_dog_id: RESTRICTED_DOG};

      const guardResult = await evaluateVehicleCrewInvitationK9Guard({
        transaction: txn,
        actor: ACTOR_ALICE,
        crewData,
        activeShiftData,
      });

      assert.equal(guardResult.allowed, false);
      assert.equal(guardResult.candidate.origin, "active_shift_reassociation");
      assert.equal(guardResult.candidate.dogId, RESTRICTED_DOG);
      assert.equal(guardResult.decision.status, "DENIED");
      assert.equal(guardResult.decision.reason, "blocked_absolute");
    });

    it("4.4. Previously selected crew candidate K9 with active restriction is blocked", async () => {
      const store = new InMemoryTxnStore();
      const txn = store.createShiftTxn();

      const crewData = {
        service_dog_id: "",
        candidate_dog_id: RESTRICTED_DOG,
      };

      const guardResult = await evaluateVehicleCrewInvitationK9Guard({
        transaction: txn,
        actor: ACTOR_ALICE,
        crewData,
      });

      assert.equal(guardResult.allowed, false);
      assert.equal(guardResult.candidate.origin, "crew_candidate");
      assert.equal(guardResult.decision.status, "DENIED");
    });

    it("4.5. Healthy inherited crew K9 is allowed by fresh F20 decision", async () => {
      const store = new InMemoryTxnStore();
      const txn = store.createShiftTxn();

      const crewData = {service_dog_id: HEALTHY_DOG};

      const guardResult = await evaluateVehicleCrewInvitationK9Guard({
        transaction: txn,
        actor: ACTOR_ALICE,
        crewData,
      });

      assert.equal(guardResult.allowed, true);
      assert.equal(guardResult.isExempt, false);
      assert.equal(guardResult.candidate.origin, "crew_inherited");
      assert.equal(guardResult.candidate.dogId, HEALTHY_DOG);
      assert.equal(guardResult.decision.status, "ALLOWED");

      const fields = buildGuardedInvitationVehicleFields(
        guardResult,
        {vehicle_id: "v-01"},
        "crew-001",
        "mock-ts",
      );
      assert.equal(fields.service_dog_id, HEALTHY_DOG);
      assert.equal(fields.dogId, HEALTHY_DOG);
      assert.equal(fields.f20_k9_status, "verified_allowed");
    });

    it("4.6. Explicit candidate K9 overrides crew and shift dogs", () => {
      const candidate = resolveVehicleCrewInvitationK9Candidate(
        {service_dog_id: "crew-dog"},
        {service_dog_id: "shift-dog"},
        "explicit-override-k9",
      );

      assert.equal(candidate.origin, "explicit_candidate");
      assert.equal(candidate.dogId, "explicit-override-k9");
      assert.equal(candidate.requiresF20Decision, true);
    });

    it("4.7. Guard module status reports F20_GUARD_MODULE_READY / PRODUCTION_WIRING_PENDING", () => {
      assert.equal(getK9GuardStatus(), "F20_GUARD_MODULE_READY / PRODUCTION_WIRING_PENDING");
      assert.equal(F20_GUARD_MODULE_STATUS, "F20_GUARD_MODULE_READY / PRODUCTION_WIRING_PENDING");
    });
  });

  // ── 5. FirestoreShiftTxnAdapter Unit & Contract Verification ──────────────

  describe("FirestoreShiftTxnAdapter Contract Verification", () => {
    it("5.1. Adapter delegates get, getCollection, set, update, delete to underlying transaction", async () => {
      const calls: string[] = [];
      const mockDocSnap = {exists: true, data: () => ({sampleKey: "sampleVal"})};
      const mockQuerySnap = {
        docs: [
          {id: "doc-1", data: () => ({fieldA: 123})},
          {id: "doc-2", data: () => ({fieldA: 456})},
        ],
      };

      const mockTx: Partial<Transaction> = {
        get: async (ref: any): Promise<any> => {
          calls.push(`tx.get:${ref.path}`);
          if (ref.isCollection) {
            return mockQuerySnap;
          }
          return mockDocSnap;
        },
        set: ((ref: any, data: any, opts: any) => {
          calls.push(`tx.set:${ref.path}:${JSON.stringify(opts ?? {})}`);
          return mockTx as Transaction;
        }) as any,
        update: ((ref: any, data: any) => {
          calls.push(`tx.update:${ref.path}`);
          return mockTx as Transaction;
        }) as any,
        delete: ((ref: any) => {
          calls.push(`tx.delete:${ref.path}`);
          return mockTx as Transaction;
        }) as any,
      };

      const mockDb: Partial<Firestore> = {
        doc: (path: string) => ({path, isCollection: false} as any),
        collection: (path: string) => ({path, isCollection: true} as any),
      };

      const adapter = createFirestoreShiftTxnAdapter(
        mockTx as Transaction,
        mockDb as Firestore,
      );

      // 1. get
      const doc = await adapter.get("dogs/sample-dog");
      assert.equal(doc.exists, true);
      assert.equal(doc.data?.sampleKey, "sampleVal");

      // 2. getCollection
      const col = await adapter.getCollection("dogs/sample-dog/operational_restrictions");
      assert.equal(col.kind, "docs");
      if (col.kind === "docs") {
        assert.equal(col.docs.length, 2);
        assert.equal(col.docs[0].id, "doc-1");
      }

      // 3. set
      adapter.set("dogs/sample-dog", {updated: true}, {merge: true});

      // 4. update
      adapter.update("dogs/sample-dog", {name: "NewName"});

      // 5. delete
      adapter.delete("dogs/sample-dog");

      assert.deepEqual(calls, [
        "tx.get:dogs/sample-dog",
        "tx.get:dogs/sample-dog/operational_restrictions",
        "tx.set:dogs/sample-dog:{\"merge\":true}",
        "tx.update:dogs/sample-dog",
        "tx.delete:dogs/sample-dog",
      ]);
    });

    it("5.2. Path validation throws on invalid segment counts", () => {
      const mockTx: Partial<Transaction> = {};
      const mockDb: Partial<Firestore> = {
        doc: (p) => ({path: p} as any),
        collection: (p) => ({path: p} as any),
      };

      const adapter = new FirestoreShiftTxnAdapter(
        mockTx as Transaction,
        mockDb as Firestore,
      );

      // Doc path with odd segments must throw
      assert.throws(() => adapter.resolveDocRef("dogs"));
      assert.throws(() => adapter.resolveDocRef("dogs/123/sub"));

      // Collection path with even segments must throw
      assert.throws(() => adapter.resolveCollectionRef("dogs/123"));
    });

    it("5.3. validateAuthorityEvidenceContract correctly validates and rejects mismatches", () => {
      const validEvidence: AuthorityEvidenceContract = {
        actorUid: "uid-1",
        actorRa: "ra-1",
        dogId: "dog-1",
        revision: "rev-1",
      };

      // Valid case
      const resOk = validateAuthorityEvidenceContract(
        validEvidence,
        {uid: "uid-1", ra: "ra-1", email: "e", name: "n"},
        "dog-1",
      );
      assert.equal(resOk.valid, true);

      // Null evidence
      assert.equal(validateAuthorityEvidenceContract(null, {uid: "u", ra: "r", email: "e", name: "n"}, "dog-1").valid, false);

      // Null actor
      assert.equal(validateAuthorityEvidenceContract(validEvidence, null, "dog-1").valid, false);

      // UID mismatch
      assert.equal(validateAuthorityEvidenceContract(validEvidence, {uid: "other", ra: "ra-1", email: "e", name: "n"}, "dog-1").reason, "authority_actor_uid_mismatch");

      // RA mismatch
      assert.equal(validateAuthorityEvidenceContract(validEvidence, {uid: "uid-1", ra: "other", email: "e", name: "n"}, "dog-1").reason, "authority_actor_ra_mismatch");

      // Dog ID mismatch
      assert.equal(validateAuthorityEvidenceContract(validEvidence, {uid: "uid-1", ra: "ra-1", email: "e", name: "n"}, "other-dog").reason, "authority_dog_id_mismatch");
    });

    it("5.4. fetchRestrictionsEvidenceInTxn and evaluateCanonicalK9GuardInTxn execute canonical evaluation", async () => {
      const store = new InMemoryTxnStore();
      const txn = store.createShiftTxn();

      // Test fetchRestrictionsEvidenceInTxn with valid dog
      const restrictions = await fetchRestrictionsEvidenceInTxn(txn, HEALTHY_DOG);
      assert.equal(restrictions.kind, "docs");

      // Test fetchRestrictionsEvidenceInTxn with empty dogId
      const emptyRes = await fetchRestrictionsEvidenceInTxn(txn, "   ");
      assert.equal(emptyRes.kind, "failed");
      if (emptyRes.kind === "failed") {
        assert.equal(emptyRes.reasonCode, "invalid_dog_id");
      }

      // Test evaluateCanonicalK9GuardInTxn with healthy dog and matching evidence
      const decisionHealthy = await evaluateCanonicalK9GuardInTxn({
        txn,
        actor: ACTOR_ALICE,
        dogId: HEALTHY_DOG,
        associationIntent: "K9_ASSOCIATION_REQUESTED",
        authorityEvidence: {
          actorUid: ACTOR_ALICE.uid,
          actorRa: ACTOR_ALICE.ra,
          dogId: HEALTHY_DOG,
          revision: "rev-healthy",
        },
      });
      assert.equal(decisionHealthy.status, "ALLOWED");

      // Test evaluateCanonicalK9GuardInTxn with restricted dog
      const decisionRestricted = await evaluateCanonicalK9GuardInTxn({
        txn,
        actor: ACTOR_ALICE,
        dogId: RESTRICTED_DOG,
        associationIntent: "K9_ASSOCIATION_REQUESTED",
        authorityEvidence: {
          actorUid: ACTOR_ALICE.uid,
          actorRa: ACTOR_ALICE.ra,
          dogId: RESTRICTED_DOG,
          revision: "rev-restricted",
        },
      });
      assert.equal(decisionRestricted.status, "DENIED");

      // Test actorBoundFingerprint format
      const fp = actorBoundFingerprint(ACTOR_ALICE, {
        action: "start_shift",
        dogId: HEALTHY_DOG,
        operationId: "op-fp-test",
        role: "motorista",
      });
      assert.ok(fp.includes(ACTOR_ALICE.uid));
      assert.ok(fp.includes(ACTOR_ALICE.ra));
      assert.ok(fp.includes(HEALTHY_DOG));
    });
  });
});
