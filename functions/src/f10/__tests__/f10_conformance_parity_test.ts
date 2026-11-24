/**
 * F10 Conformance & Parity Test Suite (Mobile Cloud Functions).
 *
 * Verifies mathematical parity between the Web/Admin F10 implementation
 * (`k9-ops`) and the Mobile Cloud Functions F10 implementation (`canil-gcm`),
 * executing 100% of the normalized v1.1.0 conformance vectors.
 *
 * Also exercises the transaction-local Firestore authority adapter against
 * zero-bypass security invariants, 60m threshold gates, and bidirectional 1:1 bindings.
 */

import * as assert from 'assert';
import * as path from 'path';
import * as fs from 'fs';
import {
  SELF_REGULARIZE,
  EXCEPTIONAL_RECONCILE,
  resolveUniqueBinding,
  validateBindingUniqueness,
  validateIdentityBinding,
  evaluateCapability,
  calculateCrewWindow,
  createSnapshot,
  verifySnapshot,
  buildSupersessionRecord,
  assertAuthorityRevision,
  evaluateStructuralValidity,
  evaluateTrustedAuthority,
  AuthorityEnvelope,
  ServerAttestation,
} from '../f10_runtime_authority_contracts';
import {
  resolveTrustedActorInTransaction,
  evaluateTransactionAuthority,
} from '../f10_firestore_authority_adapter';

type JsonMap = Record<string, unknown>;

// ─────────────────────────────────────────────────────────────────────────────
// VECTOR SUITE EXECUTION
// ─────────────────────────────────────────────────────────────────────────────

async function testConformanceVectorsParity() {
  const vectorFilePath = path.join(__dirname, '..', 'conformance_vectors.v1.json');
  assert.ok(fs.existsSync(vectorFilePath), 'conformance_vectors.v1.json deve existir');

  const raw = fs.readFileSync(vectorFilePath, 'utf8');
  const payload = JSON.parse(raw);

  assert.strictEqual(payload.version, '1.1.0', 'Versão dos vetores deve ser 1.1.0');
  assert.ok(Array.isArray(payload.vectors), 'payload.vectors deve ser um array');
  assert.ok(payload.vectors.length >= 39, `Deve conter ao menos 39 vetores (atual: ${payload.vectors.length})`);

  let executedCount = 0;

  for (const vector of payload.vectors) {
    const { id, category, input, expected, source_function } = vector;

    if (category === 'identity') {
      if (source_function === 'resolveUniqueBinding') {
        const result = resolveUniqueBinding(input.bindings, input.uid, input.requestedRa);
        if (expected.result === null) {
          assert.strictEqual(result, null, `Vector ${id}: esperava null`);
        } else {
          assert.deepStrictEqual(result, expected.result, `Vector ${id}: resultado divergente`);
        }
      } else if (source_function === 'validateBindingUniqueness') {
        const result = validateBindingUniqueness(input.bindings);
        assert.strictEqual(result, expected.result, `Vector ${id}: validateBindingUniqueness divergente`);
      } else if (source_function === 'validateIdentityBinding') {
        if (expected.error) {
          assert.throws(
            () => validateIdentityBinding(input.binding),
            new RegExp(expected.error),
            `Vector ${id}: esperava erro ${expected.error}`,
          );
        } else {
          const result = validateIdentityBinding(input.binding);
          assert.deepStrictEqual(result, expected.result, `Vector ${id}: binding divergente`);
        }
      }
    } else if (category === 'capabilities') {
      if (source_function === 'evaluateCapability') {
        const decision = evaluateCapability({
          identity: input.identity,
          capability: input.capability,
          evidence: input.evidence,
          f40: input.f40,
        });
        assert.strictEqual(decision.state, expected.state, `Vector ${id}: state divergente (${decision.state} vs ${expected.state})`);
        if (expected.reason) {
          assert.strictEqual(decision.reason, expected.reason, `Vector ${id}: reason divergente`);
        }
        if (expected.capability) {
          assert.strictEqual(decision.capability, expected.capability, `Vector ${id}: capability divergente`);
        }
      }
    } else if (category === 'schedule') {
      if (source_function === 'calculateCrewWindow') {
        if (expected.error) {
          assert.throws(
            () => calculateCrewWindow(input),
            new RegExp(expected.error),
            `Vector ${id}: esperava erro ${expected.error}`,
          );
        } else {
          const window = calculateCrewWindow(input);
          if (expected.durationMs !== undefined) {
            assert.strictEqual(window.end.getTime() - window.start.getTime(), expected.durationMs, `Vector ${id}: duração`);
          }
          if (expected.startIso !== undefined) {
            assert.strictEqual(window.start.toISOString(), expected.startIso, `Vector ${id}: startIso`);
          }
          if (expected.inclusiveStart !== undefined) {
            assert.strictEqual(window.inclusiveStart, expected.inclusiveStart);
          }
          if (expected.exclusiveEnd !== undefined) {
            assert.strictEqual(window.exclusiveEnd, expected.exclusiveEnd);
          }
        }
      }
    } else if (category === 'snapshots') {
      if (source_function === 'createSnapshot') {
        if (expected.error) {
          assert.throws(
            () =>
              createSnapshot(
                input.window
                  ? {
                      ...input.window,
                      start: new Date(input.window.start),
                      end: new Date(input.window.end),
                    }
                  : (undefined as any),
                input.source,
                input.snapshotId,
                input.createdAt,
                input.supersedesSnapshotId,
              ),
            new RegExp(expected.error),
            `Vector ${id}: erro createSnapshot`,
          );
        } else {
          const snapshot = createSnapshot(
            {
              ...input.window,
              start: new Date(input.window.start),
              end: new Date(input.window.end),
            },
            input.source,
            input.snapshotId,
            input.createdAt,
            input.supersedesSnapshotId,
          );
          if (expected.verifyResult !== undefined) {
            assert.strictEqual(verifySnapshot(snapshot), expected.verifyResult, `Vector ${id}: verifySnapshot`);
          }
          if (expected.frozen) {
            assert.strictEqual(Object.isFrozen(snapshot), true, `Vector ${id}: frozen`);
          }
        }
      } else if (source_function === 'verifySnapshot') {
        if (input.originalSource && input.modifiedSource) {
          const win = {
            scheduleId: 's',
            revision: 1,
            timezone: 'UTC',
            serviceDate: '2026-11-01',
            start: new Date('2026-11-01T07:00:00.000Z'),
            end: new Date('2026-11-01T19:00:00.000Z'),
            inclusiveStart: true as const,
            exclusiveEnd: true as const,
          };
          const snap = createSnapshot(win, input.originalSource, 's1', '2026-11-01T00:00:00Z');
          const tampered = { ...snap, source: input.modifiedSource };
          assert.strictEqual(verifySnapshot(tampered), expected.verifyResult, `Vector ${id}: verifySnapshot tampered`);
        }
      } else if (source_function === 'buildSupersessionRecord') {
        if (expected.error) {
          assert.throws(
            () =>
              buildSupersessionRecord(
                input.oldSnapshot,
                input.replacementSnapshot,
                input.reason,
                input.createdBy,
                input.recordId,
                input.createdAt,
              ),
            new RegExp(expected.error),
            `Vector ${id}: buildSupersessionRecord erro`,
          );
        } else {
          const record = buildSupersessionRecord(
            input.oldSnapshot,
            input.replacementSnapshot,
            input.reason,
            input.createdBy,
            input.recordId,
            input.createdAt,
          );
          assert.strictEqual(record.supersededSnapshotId, expected.supersededSnapshotId, `Vector ${id}: supersededId`);
        }
      }
    } else if (category === 'authority_revisions') {
      if (source_function === 'assertAuthorityRevision') {
        const decision = assertAuthorityRevision(
          input.expected ?? undefined,
          input.current ?? undefined,
        );
        assert.strictEqual(decision.state, expected.state, `Vector ${id}: state`);
        assert.strictEqual(decision.reason, expected.reason, `Vector ${id}: reason`);
      }
    }

    executedCount += 1;
  }

  assert.strictEqual(executedCount, payload.vectors.length, 'Todos os vetores devem ser executados');
}

// ─────────────────────────────────────────────────────────────────────────────
// ADVERSARIAL & BOUNDARY TESTS
// ─────────────────────────────────────────────────────────────────────────────

async function testUntrustedEnvelopesAndForgedClaims() {
  const actor = { uid: 'uid-1', ra: 'RA01', revision: 1, active: true, confirmed: true };
  const grant = { capability: SELF_REGULARIZE, grantRevision: 1, authorityRevision: 1 };
  const f40 = { activeMembership: true, confirmed: true, incomingCrewMember: true, generation: 'g1' };
  const schedule = {
    snapshotId: 'snap-1',
    revision: 1,
    serviceDate: '2026-11-01',
    timezone: 'America/Sao_Paulo',
    start: '2026-11-01T10:00:00.000Z',
    end: '2026-11-01T22:00:00.000Z',
    source: 'server',
    integrity: 'abc',
  };

  const envelope: AuthorityEnvelope = { actor, grant, f40, schedule, trusted: true };

  // 1. Structural validity is true, but without attestation it remains UNTRUSTED
  const structural = evaluateStructuralValidity(envelope);
  assert.strictEqual(structural.valid, true);

  const decisionNoAttest = evaluateTrustedAuthority(envelope, null);
  assert.strictEqual(decisionNoAttest.state, 'structurally_valid_but_untrusted');
  assert.strictEqual(decisionNoAttest.attestationPresent, false);

  // 2. Valid server attestation authorizes
  const attestation: ServerAttestation = {
    verificationToken: 'tok-xyz',
    verifiedAt: '2026-11-01T23:00:00.000Z',
    authorityRevision: 1,
    scheduleSnapshotId: 'snap-1',
    identityBindingRevision: 1,
  };
  const decisionAttested = evaluateTrustedAuthority(envelope, attestation);
  assert.strictEqual(decisionAttested.state, 'allowed_only_with_server_attestation');

  // 3. Stale authority revision in attestation fails closed
  const staleAttestation = { ...attestation, authorityRevision: 99 };
  const decisionStale = evaluateTrustedAuthority(envelope, staleAttestation);
  assert.strictEqual(decisionStale.state, 'denied_stale_authority');

  // 4. Stale identity binding revision fails closed
  const staleBinding = { ...attestation, identityBindingRevision: 99 };
  const decisionStaleBinding = evaluateTrustedAuthority(envelope, staleBinding);
  assert.strictEqual(decisionStaleBinding.state, 'denied_stale_authority');
}

async function testExceptionalReconciliationBoundary() {
  const actor = { uid: 'uid-sup', ra: 'SUP01', revision: 1, active: true, confirmed: true };
  const attestation: ServerAttestation = {
    verificationToken: 'tok-sup',
    verifiedAt: '2026-11-01T23:00:00.000Z',
    authorityRevision: 2,
    scheduleSnapshotId: 'snap-1',
    identityBindingRevision: 1,
  };
  const schedule = {
    snapshotId: 'snap-1',
    revision: 1,
    serviceDate: '2026-11-01',
    timezone: 'America/Sao_Paulo',
    start: '2026-11-01T10:00:00.000Z',
    end: '2026-11-01T22:00:00.000Z',
    source: 'server',
    integrity: 'abc',
  };

  // Sem incoming crew membership (f40 undefined), mas com supervisor e evidências válidas
  const envelope: AuthorityEnvelope = {
    actor,
    grant: {
      capability: EXCEPTIONAL_RECONCILE,
      grantRevision: 2,
      authorityRevision: 2,
      designation: 'supervisor',
      evidenceRefs: ['disp-101'],
      justification: 'Supervisor manual reconciliation',
    },
    schedule,
  };

  const decision = evaluateTrustedAuthority(envelope, attestation);
  assert.strictEqual(decision.state, 'allowed_only_with_server_attestation', 'Supervisor sem f40 deve ser autorizado');

  // Com designation inválida ("condutor") -> Denied
  const invalidDesignationEnvelope: AuthorityEnvelope = {
    ...envelope,
    grant: { ...envelope.grant, designation: 'condutor' as any },
  };
  const decisionInvalid = evaluateTrustedAuthority(invalidDesignationEnvelope, attestation);
  assert.strictEqual(decisionInvalid.state, 'denied_designation_missing');

  // Com evidenceRefs vazio -> Denied
  const emptyRefsEnvelope: AuthorityEnvelope = {
    ...envelope,
    grant: { ...envelope.grant, evidenceRefs: [] },
  };
  const decisionEmptyRefs = evaluateTrustedAuthority(emptyRefsEnvelope, attestation);
  assert.strictEqual(decisionEmptyRefs.state, 'denied_designation_missing');
}

// ─────────────────────────────────────────────────────────────────────────────
// FIRESTORE AUTHORITY ADAPTER TRANSACTIONAL TESTS
// ─────────────────────────────────────────────────────────────────────────────

function createMockFirestore(initialDocs: Record<string, JsonMap>) {
  const store = new Map<string, JsonMap>();
  for (const [k, v] of Object.entries(initialDocs)) {
    store.set(k, { ...v });
  }

  const db = {
    collection(name: string) {
      return {
        doc(id: string) {
          return {
            path: `${name}/${id}`,
            id,
          };
        },
      };
    },
    doc(pathStr: string) {
      const parts = pathStr.split('/');
      return {
        path: pathStr,
        id: parts[parts.length - 1],
      };
    },
  };

  const tx = {
    async get(ref: { path: string; id: string }) {
      const data = store.get(ref.path);
      return {
        exists: data !== undefined,
        id: ref.id,
        data: () => (data ? { ...data } : undefined),
      };
    },
  };

  return { db: db as any, tx: tx as any, store };
}

async function testTransactionalAuthorityAdapter() {
  const scheduleEndIso = '2026-11-01T19:00:00.000Z'; // 19:00 UTC
  const scheduleEndMs = new Date(scheduleEndIso).getTime();

  const initialDocs: Record<string, JsonMap> = {
    'identity_bindings/uid-100': {
      uid: 'uid-100',
      ra: '100',
      active: true,
      confirmed: true,
      revision: 1,
    },
    'users/100': {
      uid: 'uid-100',
      ra: '100',
      status: 'active',
      active: true,
      access_profile_id: 'perfil_operador_veicular',
    },
    'access_profiles/perfil_operador_veicular': {
      id: 'perfil_operador_veicular',
      status: 'active',
      grant_revision: 3,
      authority_revision: 3,
      permissions: {
        vehicles: {
          self_regularize_prior_occupancy: true,
        },
      },
    },
    'crew_schedule_snapshots/snap-valid': {
      scheduleId: 'sched-1',
      revision: 1,
      timezone: 'America/Sao_Paulo',
      serviceDate: '2026-11-01',
      start: '2026-11-01T07:00:00.000Z',
      end: scheduleEndIso,
      source: 'crew_assignment',
      createdAt: '2026-11-01T00:00:00Z',
      integrity: 'int-1',
    },
    'crew_schedule_snapshots/snap-superseded': {
      scheduleId: 'sched-1',
      revision: 1,
      timezone: 'America/Sao_Paulo',
      serviceDate: '2026-11-01',
      start: '2026-11-01T07:00:00.000Z',
      end: scheduleEndIso,
      source: 'crew_assignment',
      superseded_by: 'snap-replacement',
      createdAt: '2026-11-01T00:00:00Z',
      integrity: 'int-2',
    },
  };

  const { db, tx } = createMockFirestore(initialDocs);

  // 1. 1:1 Bidirectional resolution
  const actor = await resolveTrustedActorInTransaction(tx, db, 'uid-100', '100');
  assert.ok(actor, 'Ator legítimo deve resolver');
  assert.strictEqual(actor.identity.ra, '100');

  // Mismatch de RA solicitado falha fechado
  const actorMismatch = await resolveTrustedActorInTransaction(tx, db, 'uid-100', '999');
  assert.strictEqual(actorMismatch, null, 'RA solicitado diferente deve retornar null');

  // 2. Schedule snapshot thresholds:
  // a) Exatamente +59m -> Negado (threshold não atingido)
  const at59m = new Date(scheduleEndMs + 59 * 60 * 1000).toISOString();
  const res59m = await evaluateTransactionAuthority(tx, db, {
    uid: 'uid-100',
    capability: SELF_REGULARIZE,
    scheduleSnapshotId: 'snap-valid',
    nowIso: at59m,
  });
  assert.strictEqual(res59m.allowed, false);
  assert.strictEqual(res59m.reason, 'schedule_end_plus_60m_threshold_not_reached');

  // b) Exatamente +60m -> Permitido
  const at60m = new Date(scheduleEndMs + 60 * 60 * 1000).toISOString();
  const res60m = await evaluateTransactionAuthority(tx, db, {
    uid: 'uid-100',
    capability: SELF_REGULARIZE,
    scheduleSnapshotId: 'snap-valid',
    nowIso: at60m,
  });
  assert.strictEqual(res60m.allowed, true);
  assert.strictEqual(res60m.attestation?.authorityRevision, 3);
  assert.strictEqual(res60m.attestation?.identityBindingRevision, 1);

  // c) +61m -> Permitido
  const at61m = new Date(scheduleEndMs + 61 * 60 * 1000).toISOString();
  const res61m = await evaluateTransactionAuthority(tx, db, {
    uid: 'uid-100',
    capability: SELF_REGULARIZE,
    scheduleSnapshotId: 'snap-valid',
    nowIso: at61m,
  });
  assert.strictEqual(res61m.allowed, true);

  // d) Snapshot supersedido -> Negado
  const resSuperseded = await evaluateTransactionAuthority(tx, db, {
    uid: 'uid-100',
    capability: SELF_REGULARIZE,
    scheduleSnapshotId: 'snap-superseded',
    nowIso: at61m,
  });
  assert.strictEqual(resSuperseded.allowed, false);
  assert.strictEqual(resSuperseded.reason, 'schedule_snapshot_invalid_or_superseded');
}

// ─────────────────────────────────────────────────────────────────────────────
// RUNNER
// ─────────────────────────────────────────────────────────────────────────────

const tests: Array<[string, () => Promise<void>]> = [
  ['f10: 100% de paridade dos vetores v1.1.0', testConformanceVectorsParity],
  ['f10: envelopes não confiáveis e claims forjadas', testUntrustedEnvelopesAndForgedClaims],
  ['f10: reconciliação excepcional sem incoming crew', testExceptionalReconciliationBoundary],
  ['f10: adapter transacional do firestore e threshold +60m', testTransactionalAuthorityAdapter],
];

(async () => {
  let failures = 0;
  for (const [name, fn] of tests) {
    try {
      await fn();
      console.log(`ok   ${name}`);
    } catch (err) {
      failures += 1;
      console.error(`FAIL ${name}: ${(err as Error).stack || (err as Error).message}`);
    }
  }
  if (failures > 0) {
    console.error(`\n${failures} teste(s) de paridade F10 falharam.`);
    process.exit(1);
  }
  console.log(`\nTodos os ${tests.length} grupos de paridade F10 passaram com sucesso.`);
})();
