/**
 * FRONT10.ACCESS-CREDENTIALS — CANONICAL ACCESS PROFILE UNASSIGN TESTS.
 *
 * Cobre a matriz de testes exigida pelo Gate F10.1.ACCESS-STG-HEALTH-QA-I1.R1:
 * - T1: Profile only -> Unassign (sem instrutor)
 * - T2: Profile + Instructor -> Unassign (preservacao ortogonal de instrutor)
 * - T3: Target without Auth (unassign apenas no Firestore sem criar Auth)
 * - T4: Idempotencia (alvo ja sem perfil nao sintetiza nada nem duplica auditoria)
 * - T5: Preservacao de claims nao pertencentes a Access/Instructor
 * - T6: Inactive Personnel rejeitado com PERSONNEL_INACTIVE
 * - T7: Target not found falha fechado com not-found
 * - T8: Caller nao autorizado rejeitado
 * - T9: Zero fallback legado (sem operador_k9, condutor, gestor, admin)
 * - T10: Auditoria canonica de unassign_access_profile com previous_access_profile_id
 * - T11: Compensacao de claims em caso de falha de gravacao no Firestore
 * - T12: Falha na compensacao reporta COMPENSATION_FAILED
 * - T13: Export do callable adminUnassignAccessProfile no entrypoint
 */

import * as assert from "node:assert/strict";
import { test } from "node:test";
import { HttpsError } from "firebase-functions/v2/https";
import {
  unassignAccessProfileLogic,
  UnassignAccessProfileCaller,
  UnassignAccessProfileDeps,
} from "../src/admin_access_unassignment";
import { JsonMap } from "../src/access_claims_composition";

const CALLER: UnassignAccessProfileCaller = {
  uid: "caller-admin-01",
  email: "admin@gcm.com.br",
  name: "Gestor Administrador",
  ra: "990000",
};

const TIMESTAMP_SENTINEL = Symbol("serverTimestamp");
const DELETE_SENTINEL = Symbol("deleteField");

interface HarnessOptions {
  caller?: UnassignAccessProfileCaller;
  authorizeError?: HttpsError;
  userData?: JsonMap | null;
  userExists?: boolean;
  profileData?: JsonMap | null;
  profileExists?: boolean;
  authUser?: { uid: string; customClaims?: JsonMap } | null;
  authUidError?: Error;
  authEmailError?: Error;
  setClaimsError?: Error;
  firestoreUpdateError?: Error;
  compensationError?: Error;
}

interface RecordedCalls {
  claimsSet: Array<{ uid: string; claims: JsonMap }>;
  userUpdates: Array<{ ra: string; payload: JsonMap }>;
  auditEntries: JsonMap[];
  profileLookups: string[];
}

function createHarness(options: HarnessOptions = {}): {
  deps: UnassignAccessProfileDeps;
  recorded: RecordedCalls;
} {
  const recorded: RecordedCalls = {
    claimsSet: [],
    userUpdates: [],
    auditEntries: [],
    profileLookups: [],
  };

  const deps: UnassignAccessProfileDeps = {
    authorize: async () => {
      if (options.authorizeError) throw options.authorizeError;
      return options.caller ?? CALLER;
    },
    getUser: async (ra: string) => {
      if (options.userExists === false) return { exists: false, data: null };
      return {
        exists: true,
        data: options.userData !== undefined ? options.userData : {
          active: true,
          status: "Ativo",
          ra,
          email: `${ra}@gcm.com.br`,
          access_profile_id: "gestor",
          access_scope: "global",
          role: "gestor",
          roles: ["gestor"],
        },
      };
    },
    getProfile: async (profileId: string) => {
      recorded.profileLookups.push(profileId);
      if (options.profileExists === false) return { exists: false, data: null };
      return {
        exists: true,
        data: options.profileData !== undefined ? options.profileData : {
          id: profileId,
          name: profileId === "gestor" ? "Gestor / Comando" : profileId,
        },
      };
    },
    lookupAuthUserByUid: async (uid: string) => {
      if (options.authUidError) throw options.authUidError;
      if (options.authUser !== undefined) return options.authUser;
      return {
        uid,
        customClaims: {
          ra: "990011",
          access_profile_id: "gestor",
          access_scope: "global",
          role: "gestor",
          roles: ["gestor"],
        },
      };
    },
    lookupAuthUserByEmail: async (email: string) => {
      if (options.authEmailError) throw options.authEmailError;
      if (options.authUser !== undefined) return options.authUser;
      return {
        uid: "uid-from-email",
        customClaims: {
          ra: "990011",
          access_profile_id: "gestor",
          access_scope: "global",
          role: "gestor",
          roles: ["gestor"],
        },
      };
    },
    setCustomUserClaims: async (uid: string, claims: JsonMap) => {
      if (recorded.claimsSet.length > 0 && options.compensationError) {
        throw options.compensationError;
      }
      if (options.setClaimsError) throw options.setClaimsError;
      recorded.claimsSet.push({ uid, claims });
    },
    updateUser: async (ra: string, payload: JsonMap) => {
      if (options.firestoreUpdateError) throw options.firestoreUpdateError;
      recorded.userUpdates.push({ ra, payload });
    },
    serverTimestamp: () => TIMESTAMP_SENTINEL,
    deleteField: () => DELETE_SENTINEL,
    arrayUnion: (value: unknown) => [value],
    auditEntry: (action: string, caller: UnassignAccessProfileCaller) => {
      const entry = {
        action,
        by: caller.uid,
        by_name: caller.name,
        by_ra: caller.ra,
        at: TIMESTAMP_SENTINEL,
      };
      recorded.auditEntries.push(entry);
      return entry;
    },
    canonicalAuthEmail: (user: JsonMap, ra: string) =>
      typeof user.email === "string" ? user.email : `${ra}@gcm.com.br`,
  };

  return { deps, recorded };
}

// ── T1: PROFILE ONLY -> UNASSIGN ─────────────────────────────────────────────
test("T1: Profile only -> unassign removes base access, scope, role, and leaves identity only", async () => {
  const { deps, recorded } = createHarness({
    userData: {
      active: true,
      status: "Ativo",
      ra: "990011",
      auth_uid: "uid-990011",
      access_profile_id: "gestor",
      access_scope: "global",
      role: "gestor",
      roles: ["gestor"],
      is_k9_instructor: false,
    },
    authUser: {
      uid: "uid-990011",
      customClaims: {
        ra: "990011",
        access_profile_id: "gestor",
        access_scope: "global",
        role: "gestor",
        roles: ["gestor"],
        admin: false,
        web_access: true,
      },
    },
  });

  const res = await unassignAccessProfileLogic({ ra: "990011" }, deps);

  assert.equal(res.ra, "990011");
  assert.equal(res.unassigned, true);
  assert.equal(res.previousProfileId, "gestor");

  // Verifica claims escritas no Auth:
  assert.equal(recorded.claimsSet.length, 1);
  const claims = recorded.claimsSet[0].claims;
  assert.equal(claims.ra, "990011");
  assert.equal(claims.access_profile_id, null);
  assert.equal(claims.access_scope, null);
  assert.equal(claims.role, null);
  assert.deepEqual(claims.roles, []);
  assert.equal(claims.admin, false);
  assert.equal(claims.web_access, false);
  assert.equal(claims.mobile_access, false);
  assert.deepEqual(claims.app_access, []);
  assert.equal(claims.instrutor_k9, undefined);

  // Verifica payload escrito no Firestore:
  assert.equal(recorded.userUpdates.length, 1);
  const patch = recorded.userUpdates[0].payload;
  assert.equal(patch.access_profile_id, DELETE_SENTINEL);
  assert.equal(patch.accessProfileId, DELETE_SENTINEL);
  assert.equal(patch.access_scope, DELETE_SENTINEL);
  assert.equal(patch.accessScope, DELETE_SENTINEL);
  assert.equal(patch.role, DELETE_SENTINEL);
  assert.equal(patch.roles, DELETE_SENTINEL);
  assert.equal(patch.admin, DELETE_SENTINEL);
  assert.equal(patch.web_access, DELETE_SENTINEL);
  assert.equal(patch.mobile_access, DELETE_SENTINEL);
  assert.equal(patch.app_access, DELETE_SENTINEL);
  assert.equal(patch.is_k9_instructor, DELETE_SENTINEL);
});

// ── T2: PROFILE + INSTRUCTOR -> UNASSIGN ─────────────────────────────────────
test("T2: Profile + Instructor -> unassign removes profile but PRESERVES Instructor dimension", async () => {
  const { deps, recorded } = createHarness({
    userData: {
      active: true,
      status: "Ativo",
      ra: "990011",
      auth_uid: "uid-990011",
      access_profile_id: "gestor",
      access_scope: "global",
      role: "gestor",
      roles: ["gestor", "instrutor_k9"],
      is_k9_instructor: true,
      training_instructor: true,
      training_role: "instrutor_k9",
    },
    authUser: {
      uid: "uid-990011",
      customClaims: {
        ra: "990011",
        access_profile_id: "gestor",
        access_scope: "global",
        role: "gestor",
        roles: ["gestor", "instrutor_k9"],
        instrutor_k9: true,
        training_role: "instrutor_k9",
        training_instructor: true,
      },
    },
  });

  const res = await unassignAccessProfileLogic({ ra: "990011" }, deps);

  assert.equal(res.unassigned, true);
  assert.equal(res.previousProfileId, "gestor");

  // Claims de Auth:
  assert.equal(recorded.claimsSet.length, 1);
  const claims = recorded.claimsSet[0].claims;
  assert.equal(claims.ra, "990011");
  assert.equal(claims.access_profile_id, null);
  assert.equal(claims.access_scope, null);
  assert.equal(claims.role, null);
  // Qualificacao de instrutor preservada ortogonalmente:
  assert.deepEqual(claims.roles, ["instrutor_k9"]);
  assert.equal(claims.instrutor_k9, true);
  assert.equal(claims.training_role, "instrutor_k9");
  assert.equal(claims.training_instructor, true);
  // Sem condutor ou operador fabricados:
  assert.ok(!(claims.roles as string[]).includes("condutor"));
  assert.ok(!(claims.roles as string[]).includes("operador_k9"));

  // Firestore mirrors:
  assert.equal(recorded.userUpdates.length, 1);
  const patch = recorded.userUpdates[0].payload;
  assert.equal(patch.access_profile_id, DELETE_SENTINEL);
  assert.equal(patch.access_scope, DELETE_SENTINEL);
  assert.equal(patch.role, DELETE_SENTINEL);
  assert.equal(patch.is_k9_instructor, true);
  assert.equal(patch.training_instructor, true);
  assert.equal(patch.training_role, "instrutor_k9");
  assert.deepEqual(patch.roles, ["instrutor_k9"]);
});

// ── T3: TARGET WITHOUT AUTH ──────────────────────────────────────────────────
test("T3: Target without Auth account removes Firestore profile and DOES NOT auto-create Auth", async () => {
  const { deps, recorded } = createHarness({
    userData: {
      active: true,
      status: "Ativo",
      ra: "990011",
      access_profile_id: "gestor",
      access_scope: "global",
    },
    authUser: null, // Sem conta no Auth
  });

  const res = await unassignAccessProfileLogic({ ra: "990011" }, deps);

  assert.equal(res.unassigned, true);
  assert.equal(res.previousProfileId, "gestor");
  // Nenhuma chamada a setCustomUserClaims:
  assert.equal(recorded.claimsSet.length, 0);
  // Firestore atualizado com unassign:
  assert.equal(recorded.userUpdates.length, 1);
  assert.equal(recorded.userUpdates[0].payload.access_profile_id, DELETE_SENTINEL);
  assert.equal(recorded.userUpdates[0].payload.claim_refresh_required, false);
});

// ── T4: ALREADY UNASSIGNED (IDEMPOTENCY) ──────────────────────────────────────
test("T4: Already unassigned target is idempotent: no-op, no Auth mutation, no duplicate audit", async () => {
  const { deps, recorded } = createHarness({
    userData: {
      active: true,
      status: "Ativo",
      ra: "990011",
      auth_uid: "uid-990011",
      // Sem access_profile_id
    },
    authUser: {
      uid: "uid-990011",
      customClaims: { ra: "990011" },
    },
  });

  const res = await unassignAccessProfileLogic({ ra: "990011" }, deps);

  assert.equal(res.ra, "990011");
  assert.equal(res.unassigned, false);
  assert.equal(res.previousProfileId, null);

  // Nenhuma escrita:
  assert.equal(recorded.claimsSet.length, 0);
  assert.equal(recorded.userUpdates.length, 0);
  assert.equal(recorded.auditEntries.length, 0);
});

// ── T5: UNRELATED CLAIM PRESERVATION ─────────────────────────────────────────
test("T5: Unrelated custom claims outside Access/Instructor domain survive recomposition", async () => {
  const { deps, recorded } = createHarness({
    userData: {
      active: true,
      status: "Ativo",
      ra: "990011",
      auth_uid: "uid-990011",
      access_profile_id: "gestor",
    },
    authUser: {
      uid: "uid-990011",
      customClaims: {
        ra: "990011",
        access_profile_id: "gestor",
        roles: ["gestor", "custom_brigade_unit"],
        special_operation_clearance: 7788,
        partner_system_token: "xyz-abc",
      },
    },
  });

  await unassignAccessProfileLogic({ ra: "990011" }, deps);

  assert.equal(recorded.claimsSet.length, 1);
  const claims = recorded.claimsSet[0].claims;
  // Claims unmanaged preservadas:
  assert.equal(claims.special_operation_clearance, 7788);
  assert.equal(claims.partner_system_token, "xyz-abc");
  assert.deepEqual(claims.roles, ["custom_brigade_unit"]);
});

// ── T6: INACTIVE / INVALID PERSONNEL ─────────────────────────────────────────
test("T6: Inactive Personnel is rejected fail-closed with PERSONNEL_INACTIVE before any mutation", async () => {
  const { deps, recorded } = createHarness({
    userData: {
      active: false,
      status: "Inativo",
      ra: "990011",
      access_profile_id: "gestor",
    },
  });

  await assert.rejects(
    async () => unassignAccessProfileLogic({ ra: "990011" }, deps),
    (err: unknown) => {
      assert.ok(err instanceof HttpsError);
      assert.equal(err.code, "failed-precondition");
      assert.equal((err.details as JsonMap)?.reason, "PERSONNEL_INACTIVE");
      return true;
    },
  );

  assert.equal(recorded.claimsSet.length, 0);
  assert.equal(recorded.userUpdates.length, 0);
});

// ── T7: TARGET NOT FOUND ─────────────────────────────────────────────────────
test("T7: Target not found in Firestore fails closed with not-found", async () => {
  const { deps, recorded } = createHarness({
    userExists: false,
  });

  await assert.rejects(
    async () => unassignAccessProfileLogic({ ra: "990099" }, deps),
    (err: unknown) => {
      assert.ok(err instanceof HttpsError);
      assert.equal(err.code, "not-found");
      return true;
    },
  );

  assert.equal(recorded.claimsSet.length, 0);
  assert.equal(recorded.userUpdates.length, 0);
});

// ── T8: UNAUTHORIZED CALLER ──────────────────────────────────────────────────
test("T8: Caller without access.edit permission is rejected with permission-denied", async () => {
  const { deps } = createHarness({
    authorizeError: new HttpsError("permission-denied", "Acesso negado: modulo access, acao edit."),
  });

  await assert.rejects(
    async () => unassignAccessProfileLogic({ ra: "990011" }, deps),
    (err: unknown) => {
      assert.ok(err instanceof HttpsError);
      assert.equal(err.code, "permission-denied");
      return true;
    },
  );
});

// ── T9: NO LEGACY FALLBACK ───────────────────────────────────────────────────
test("T9: Unassign NEVER synthesizes operador_k9, condutor, gestor, or admin", async () => {
  const { deps, recorded } = createHarness({
    userData: {
      active: true,
      status: "Ativo",
      ra: "990011",
      auth_uid: "uid-990011",
      access_profile_id: "operador_k9",
    },
    authUser: {
      uid: "uid-990011",
      customClaims: {
        ra: "990011",
        access_profile_id: "operador_k9",
        role: "condutor",
        roles: ["condutor", "operador_k9"],
      },
    },
  });

  await unassignAccessProfileLogic({ ra: "990011" }, deps);

  const claims = recorded.claimsSet[0].claims;
  assert.equal(claims.role, null);
  assert.deepEqual(claims.roles, []);
  assert.ok(!(claims.roles as string[]).includes("operador_k9"));
  assert.ok(!(claims.roles as string[]).includes("condutor"));
  assert.ok(!(claims.roles as string[]).includes("gestor"));
  assert.ok(!(claims.roles as string[]).includes("admin"));
});

// ── T10: AUDIT CONTRACT ──────────────────────────────────────────────────────
test("T10: Audit appends unassign_access_profile record with previous_access_profile_id and target_ra", async () => {
  const { deps, recorded } = createHarness({
    userData: {
      active: true,
      status: "Ativo",
      ra: "990011",
      auth_uid: "uid-990011",
      access_profile_id: "gestor",
      access_profile: "Gestor / Comando",
    },
  });

  await unassignAccessProfileLogic({ ra: "990011" }, deps);

  assert.equal(recorded.auditEntries.length, 1);
  const audit = recorded.auditEntries[0];
  assert.equal(audit.action, "unassign_access_profile");
  assert.equal(audit.by, CALLER.uid);
  assert.equal(audit.by_ra, CALLER.ra);

  const payload = recorded.userUpdates[0].payload;
  const auditUnion = (payload.audit_trail as JsonMap[])[0];
  assert.equal(auditUnion.previous_access_profile_id, "gestor");
  assert.equal(auditUnion.previous_access_profile_name, "Gestor / Comando");
  assert.equal(auditUnion.target_ra, "990011");
});

// ── T11: COMPENSATION ON FIRESTORE WRITE FAILURE ─────────────────────────────
test("T11: Failure in Firestore update triggers strict claims compensation back to previous state", async () => {
  const previousClaims = {
    ra: "990011",
    access_profile_id: "gestor",
    access_scope: "global",
    role: "gestor",
    roles: ["gestor"],
  };

  const { deps, recorded } = createHarness({
    userData: {
      active: true,
      status: "Ativo",
      ra: "990011",
      auth_uid: "uid-990011",
      access_profile_id: "gestor",
    },
    authUser: {
      uid: "uid-990011",
      customClaims: previousClaims,
    },
    firestoreUpdateError: new Error("Firestore write quota exceeded"),
  });

  await assert.rejects(
    async () => unassignAccessProfileLogic({ ra: "990011" }, deps),
    /Firestore write quota exceeded/,
  );

  // Verifica que houve tentativa de mutacao seguida de reversao para previousClaims:
  assert.equal(recorded.claimsSet.length, 2);
  // 1a chamada: claims sem perfil
  assert.equal(recorded.claimsSet[0].claims.access_profile_id, null);
  // 2a chamada (compensacao): restaura previousClaims
  assert.equal(recorded.claimsSet[1].claims.access_profile_id, "gestor");
  assert.equal(recorded.claimsSet[1].claims.role, "gestor");
});

// ── T12: COMPENSATION FAILURE CLASSIFICATION ─────────────────────────────────
test("T12: If compensation itself fails, raises COMPENSATION_FAILED internal error", async () => {
  const { deps } = createHarness({
    userData: {
      active: true,
      status: "Ativo",
      ra: "990011",
      auth_uid: "uid-990011",
      access_profile_id: "gestor",
    },
    authUser: {
      uid: "uid-990011",
      customClaims: { ra: "990011", access_profile_id: "gestor" },
    },
    firestoreUpdateError: new Error("Firestore unavailable"),
    compensationError: new Error("Auth service unavailable during revert"),
  });

  await assert.rejects(
    async () => unassignAccessProfileLogic({ ra: "990011" }, deps),
    (err: unknown) => {
      assert.ok(err instanceof HttpsError);
      assert.equal(err.code, "internal");
      assert.equal((err.details as JsonMap)?.reason, "COMPENSATION_FAILED");
      assert.equal((err.details as JsonMap)?.operation, "adminUnassignAccessProfile");
      return true;
    },
  );
});

// ── T13: EXPORT OF CALLABLE ──────────────────────────────────────────────────
test("T13: adminUnassignAccessProfile is exported on Functions entrypoint", async () => {
  const entrypoint = await import("../src/index");
  assert.equal(typeof (entrypoint as JsonMap).adminUnassignAccessProfile, "function");
});
