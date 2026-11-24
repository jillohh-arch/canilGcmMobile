/**
 * F20 — SEC-02A.2 Adversarial Firestore Rules Test Suite
 * Gate: CT4.WEB-P0.F60-F20-FINAL-CONTRACT-CLOSURE-R1
 *
 * Cobre:
 * 1. Revogacao/rebaixamento de perfil com token antigo (JWT nao amplia nem faz fallback).
 * 2. Claims administrativas antigas (admin: true, role: 'admin', roles: ['administrador'])
 *    rejeitadas quando users/{ra} foi rebaixado, desativado, marcado admin:false ou ausente.
 * 3. Usuarios inativos/arquivados (active: false, deleted_at, archived_at, status: 'Inativo')
 *    rejeitados mesmo com access_profile_id preservado (Human Lifecycle V1).
 * 4. Ausencia de perfil em users/{ra} rejeitada (sem fallback para tokenAccessProfileId / operador_k9).
 * 5. Instructor Role: revogacao imediata via users/{ra}; instrutor sem access_profile_id
 *    nao fabrica Access Profile para warehouse/clinical.
 * 6. Compatibilidade de usuarios legitimamente autorizados (admin, operador_k9, instrutor).
 */
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

import {
  assertFails,
  assertSucceeds,
  initializeTestEnvironment,
} from '@firebase/rules-unit-testing';
import {
  doc,
  getDoc,
  setDoc,
  updateDoc,
  Timestamp,
} from 'firebase/firestore';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);
const RULES_PATH = path.resolve(__dirname, '../../firestore.rules');
const PROJECT_ID = process.env.GCLOUD_PROJECT || 'canil-gcm';

const testEnv = await initializeTestEnvironment({
  projectId: PROJECT_ID,
  firestore: {
    rules: fs.readFileSync(RULES_PATH, 'utf8'),
  },
});

function dbFor(ra, claims = {}) {
  if (ra === null) {
    return testEnv.unauthenticatedContext().firestore();
  }
  const token = { ...claims };
  if (ra !== undefined) {
    token.ra = ra;
    if (typeof ra === 'string' && ra.length > 0 && token.email === undefined) {
      token.email = `${ra}@gcm.com.br`;
    }
  }
  return testEnv.authenticatedContext(ra ? `uid-${ra}` : 'uid-no-ra', token).firestore();
}

function nowTs() {
  return Timestamp.fromDate(new Date('2026-05-31T12:00:00.000Z'));
}

async function assertContractDenied(promise, label = '') {
  const err = await assertFails(promise);
  const msg = String(err?.message ?? '').trim();
  assert.equal(
    err?.code,
    'permission-denied',
    `${label}: expected permission-denied, got ${err?.code} (${msg})`,
  );
  assert.doesNotMatch(
    msg,
    /maximum of 1000 expressions|EvaluationException|Null value error|Property .* is undefined|Function not found|Invalid argument/i,
    `${label}: rejected due to runtime/CEL error instead of contract false: ${msg}`,
  );
  assert.match(
    msg,
    /false for '(?:get|list|create|update|delete)' @ L\d+, false for '(?:get|list|create|update|delete)' @ L\d+$/,
    `${label}: final resolved evaluation did not return explicit false on target rule: ${msg}`,
  );
  return err;
}

function promoPayload(requesterRa = 'RA-OP', directInstructor = false) {
  const ts = nowTs();
  return {
    dog_id: 'DOG-A',
    dog_name: 'Thor',
    modality: 'busca_captura',
    program_id: 'busca_captura',
    program_version: 1,
    module_id: 'modulo_1',
    module_name: 'Modulo 1',
    module_order: 1,
    status: 'pending',
    direct_instructor: directInstructor,
    requester_ra: requesterRa,
    requester_name: `GCM ${requesterRa}`,
    requested_by_uid: `uid-${requesterRa}`,
    requested_by_email: `${requesterRa}@gcm.com.br`,
    requested_at: ts,
    created_at: ts,
    updated_at: ts,
    marks_snapshot: [],
    audit_trail: [{ action: 'create', actor: requesterRa, at: ts }],
  };
}

function correctionPayload(ra) {
  const ts = nowTs();
  return {
    module_id: 'modulo_1',
    correction_type: 'observacao',
    reason: 'Revisao tecnica.',
    before_snapshot: { module_id: 'modulo_1', module_name: 'Modulo 1' },
    requested_changes: { note: 'Sem alteracao.' },
    corrected_by: ra,
    corrected_by_uid: `uid-${ra}`,
    corrected_by_email: `${ra}@gcm.com.br`,
    corrected_by_name: `GCM ${ra}`,
    created_at: ts,
    updated_at: ts,
    audit_trail: [{ action: 'create', actor: ra, at: ts }],
  };
}

function decisionUpdate(ra) {
  const ts = nowTs();
  return {
    status: 'approved',
    decision: 'approved',
    decision_by: ra,
    decision_by_uid: `uid-${ra}`,
    decision_by_email: `${ra}@gcm.com.br`,
    decision_reason: null,
    decided_at: ts,
    updated_at: ts,
    audit_trail: [
      { action: 'create', actor: 'RA-OP', at: ts },
      { action: 'approved', actor: ra, at: ts },
    ],
  };
}

async function seedFixtures() {
  await testEnv.clearFirestore();
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    const db = ctx.firestore();

    await setDoc(doc(db, 'access_profiles', 'administrador'), {
      id: 'administrador',
      status: 'active',
      scope: 'global',
      permissions: {
        inventory: { view: true, create: true, edit: true, archive: true, move: true },
        health: { view: true },
        k9: { view: true, create: true, edit: true, archive: true },
      },
    });
    await setDoc(doc(db, 'access_profiles', 'operador_k9'), {
      id: 'operador_k9',
      status: 'active',
      scope: 'own_records',
      permissions: {
        inventory: { view: false, create: false },
        health: { view: true },
        k9: { view: true },
      },
    });
    await setDoc(doc(db, 'access_profiles', 'training_approver'), {
      id: 'training_approver',
      status: 'active',
      scope: 'global',
      permissions: {
        training: { view: true, approve: true },
      },
    });

    // Administrador legitimo
    await setDoc(doc(db, 'users', 'RA-ADMIN'), {
      ra: 'RA-ADMIN',
      active: true,
      status: 'Ativo',
      deleted_at: null,
      archived_at: null,
      access_profile_id: 'administrador',
      admin: true,
    });

    // Operador legitimo vinculado ao DOG-A
    await setDoc(doc(db, 'users', 'RA-OP'), {
      ra: 'RA-OP',
      active: true,
      status: 'Ativo',
      deleted_at: null,
      archived_at: null,
      access_profile_id: 'operador_k9',
      admin: false,
    });

    // Admin rebaixado para operador_k9 (ainda carrega admin: true no JWT antigo)
    await setDoc(doc(db, 'users', 'RA-DOWNGRADED-ADMIN'), {
      ra: 'RA-DOWNGRADED-ADMIN',
      active: true,
      status: 'Ativo',
      deleted_at: null,
      archived_at: null,
      access_profile_id: 'operador_k9',
      admin: false,
    });

    // Admin com perfil administrador mas admin: false explicitamente no doc
    await setDoc(doc(db, 'users', 'RA-ADMIN-FALSE'), {
      ra: 'RA-ADMIN-FALSE',
      active: true,
      status: 'Ativo',
      deleted_at: null,
      archived_at: null,
      access_profile_id: 'operador_k9',
      admin: false,
    });

    // Usuario desativado (Human Lifecycle V1 preserva access_profile_id)
    await setDoc(doc(db, 'users', 'RA-INACTIVE-ACTIVE-FALSE'), {
      ra: 'RA-INACTIVE-ACTIVE-FALSE',
      active: false,
      status: 'Ativo',
      deleted_at: null,
      archived_at: null,
      access_profile_id: 'administrador',
      admin: true,
    });

    // Usuario soft-deleted
    await setDoc(doc(db, 'users', 'RA-DELETED'), {
      ra: 'RA-DELETED',
      active: true,
      status: 'Ativo',
      deleted_at: Timestamp.now(),
      archived_at: null,
      access_profile_id: 'administrador',
      admin: true,
    });

    // Usuario arquivado (archived_at != null)
    await setDoc(doc(db, 'users', 'RA-ARCHIVED'), {
      ra: 'RA-ARCHIVED',
      active: true,
      status: 'Ativo',
      deleted_at: null,
      archived_at: Timestamp.now(),
      access_profile_id: 'administrador',
      admin: true,
    });

    // Usuario status Inativo
    await setDoc(doc(db, 'users', 'RA-STATUS-INATIVO'), {
      ra: 'RA-STATUS-INATIVO',
      active: true,
      status: 'Inativo',
      deleted_at: null,
      archived_at: null,
      access_profile_id: 'administrador',
      admin: true,
    });

    // Usuario sem perfil base (unassigned)
    await setDoc(doc(db, 'users', 'RA-NO-PROFILE'), {
      ra: 'RA-NO-PROFILE',
      active: true,
      status: 'Ativo',
      deleted_at: null,
      archived_at: null,
    });

    // Instrutor K9 ativo SEM access_profile_id
    await setDoc(doc(db, 'users', 'RA-INSTRUCTOR-ONLY'), {
      ra: 'RA-INSTRUCTOR-ONLY',
      active: true,
      status: 'Ativo',
      deleted_at: null,
      archived_at: null,
      is_k9_instructor: true,
      training_role: 'instrutor_k9',
    });

    // Instrutor K9 revogado (tinha claim instrutor_k9: true no JWT)
    await setDoc(doc(db, 'users', 'RA-INSTRUCTOR-REVOKED'), {
      ra: 'RA-INSTRUCTOR-REVOKED',
      active: true,
      status: 'Ativo',
      deleted_at: null,
      archived_at: null,
      is_k9_instructor: false,
      training_instructor: false,
      training_role: null,
      roles: [],
      access_profile_id: 'operador_k9',
    });

    // Instrutor K9 desativado
    await setDoc(doc(db, 'users', 'RA-INSTRUCTOR-INACTIVE'), {
      ra: 'RA-INSTRUCTOR-INACTIVE',
      active: false,
      status: 'Inativo',
      deleted_at: Timestamp.now(),
      is_k9_instructor: true,
      training_role: 'instrutor_k9',
    });

    // IR-01: is_k9_instructor: false com flags/roles legados residuais + operador_k9
    await setDoc(doc(db, 'users', 'RA-INST-REVOKED-FLAGS'), {
      ra: 'RA-INST-REVOKED-FLAGS',
      active: true,
      status: 'Ativo',
      deleted_at: null,
      archived_at: null,
      access_profile_id: 'operador_k9',
      is_k9_instructor: false,
      training_instructor: true,
      instrutor_k9: true,
      instrutor: true,
      adestrador: true,
      training_role: 'instrutor_k9',
      roles: ['instrutor_k9'],
    });

    // IR-02: is_k9_instructor: false com roles e training_role legados
    await setDoc(doc(db, 'users', 'RA-INST-REVOKED-ROLES'), {
      ra: 'RA-INST-REVOKED-ROLES',
      active: true,
      status: 'Ativo',
      deleted_at: null,
      archived_at: null,
      is_k9_instructor: false,
      roles: ['instrutor', 'adestrador', 'instrutor_k9'],
      training_role: 'instrutor_k9',
    });

    // IR-03: operador_k9 ativo + is_k9_instructor: true
    await setDoc(doc(db, 'users', 'RA-OP-INSTRUCTOR'), {
      ra: 'RA-OP-INSTRUCTOR',
      active: true,
      status: 'Ativo',
      deleted_at: null,
      archived_at: null,
      access_profile_id: 'operador_k9',
      is_k9_instructor: true,
    });

    // IR-05: compatibilidade legada ativa sem campo canonico is_k9_instructor e sem access_profile_id
    await setDoc(doc(db, 'users', 'RA-LEGACY-INST-BOOL'), {
      ra: 'RA-LEGACY-INST-BOOL',
      active: true,
      status: 'Ativo',
      deleted_at: null,
      archived_at: null,
      training_instructor: true,
    });
    await setDoc(doc(db, 'users', 'RA-LEGACY-INST-K9FLAG'), {
      ra: 'RA-LEGACY-INST-K9FLAG',
      active: true,
      status: 'Ativo',
      deleted_at: null,
      archived_at: null,
      instrutor_k9: true,
    });
    await setDoc(doc(db, 'users', 'RA-LEGACY-INST-ROLE'), {
      ra: 'RA-LEGACY-INST-ROLE',
      active: true,
      status: 'Ativo',
      deleted_at: null,
      archived_at: null,
      training_role: 'instrutor_k9',
    });
    await setDoc(doc(db, 'users', 'RA-LEGACY-INST-ROLES'), {
      ra: 'RA-LEGACY-INST-ROLES',
      active: true,
      status: 'Ativo',
      deleted_at: null,
      archived_at: null,
      roles: ['adestrador'],
    });

    // IR-07: variantes individuais de ciclo de vida inativo/arquivado com is_k9_instructor: true
    await setDoc(doc(db, 'users', 'RA-INST-ACTIVE-FALSE'), {
      ra: 'RA-INST-ACTIVE-FALSE',
      active: false,
      status: 'Ativo',
      deleted_at: null,
      archived_at: null,
      is_k9_instructor: true,
    });
    await setDoc(doc(db, 'users', 'RA-INST-DELETED'), {
      ra: 'RA-INST-DELETED',
      active: true,
      status: 'Ativo',
      deleted_at: Timestamp.now(),
      archived_at: null,
      is_k9_instructor: true,
    });
    await setDoc(doc(db, 'users', 'RA-INST-ARCHIVED'), {
      ra: 'RA-INST-ARCHIVED',
      active: true,
      status: 'Ativo',
      deleted_at: null,
      archived_at: Timestamp.now(),
      is_k9_instructor: true,
    });
    await setDoc(doc(db, 'users', 'RA-INST-STATUS-INATIVO'), {
      ra: 'RA-INST-STATUS-INATIVO',
      active: true,
      status: 'Inativo',
      deleted_at: null,
      archived_at: null,
      is_k9_instructor: true,
    });

    // Recursos de teste
    await setDoc(doc(db, 'warehouse_batches', 'batch-01'), {
      id: 'batch-01',
      item_id: 'item-01',
      quantity_available: 10,
    });
    await setDoc(doc(db, 'inventory_sessions', 'sess-01'), {
      id: 'sess-01',
      status: 'open',
    });
    await setDoc(doc(db, 'dogs', 'DOG-A'), {
      id: 'DOG-A',
      name: 'Thor',
      conductorRa: 'RA-OP',
    });
    await setDoc(doc(db, 'dogs', 'DOG-B'), {
      id: 'DOG-B',
      name: 'Zeus',
      conductorRa: 'RA-OTHER',
    });
    await setDoc(doc(db, 'dogs', 'DOG-REVOKED-OP'), {
      id: 'DOG-REVOKED-OP',
      name: 'Apollo',
      conductorRa: 'RA-INST-REVOKED-FLAGS',
    });
    await setDoc(doc(db, 'dogs', 'DOG-REVOKED-OP', 'training', 'busca_captura'), {
      modality: 'busca_captura',
      status: 'operational',
      completed_module_ids: ['modulo_1'],
      completed_modules: [{ module_id: 'modulo_1', module_name: 'Modulo 1', program_version: 1 }],
    });
    await setDoc(doc(db, 'dogs', 'DOG-OP-INST'), {
      id: 'DOG-OP-INST',
      name: 'Max',
      conductorRa: 'RA-OP-INSTRUCTOR',
    });
    await setDoc(doc(db, 'dogs', 'DOG-OP-INST', 'training', 'busca_captura'), {
      modality: 'busca_captura',
      status: 'operational',
      completed_module_ids: ['modulo_1'],
      completed_modules: [{ module_id: 'modulo_1', module_name: 'Modulo 1', program_version: 1 }],
    });
    await setDoc(doc(db, 'dogs', 'DOG-OP-INST', 'health_timeline', 'tl-op-inst'), {
      id: 'tl-op-inst',
      dog_id: 'DOG-OP-INST',
    });
    await setDoc(doc(db, 'dogs', 'DOG-A', 'clinical_cases', 'case-01'), {
      id: 'case-01',
      dog_id: 'DOG-A',
    });
    await setDoc(doc(db, 'dogs', 'DOG-B', 'clinical_cases', 'case-02'), {
      id: 'case-02',
      dog_id: 'DOG-B',
    });
    await setDoc(doc(db, 'dogs', 'DOG-A', 'health_timeline', 'tl-01'), {
      id: 'tl-01',
      dog_id: 'DOG-A',
    });
    await setDoc(doc(db, 'dogs', 'DOG-B', 'health_timeline', 'tl-02'), {
      id: 'tl-02',
      dog_id: 'DOG-B',
    });
    await setDoc(doc(db, 'dogs', 'DOG-A', 'training', 'busca_captura'), {
      modality: 'busca_captura',
      status: 'operational',
      completed_module_ids: ['modulo_1'],
      completed_modules: [{ module_id: 'modulo_1', module_name: 'Modulo 1', program_version: 1 }],
    });

    for (const promoId of [
      'promo-ir01',
      'promo-ir02',
      'promo-ir03',
      'promo-ir04',
      'promo-ir05-bool',
      'promo-ir05-k9flag',
      'promo-ir05-role',
      'promo-ir05-roles',
      'promo-ir06',
      'promo-ir07-RA-INST-ACTIVE-FALSE',
      'promo-ir07-RA-INST-DELETED',
      'promo-ir07-RA-INST-ARCHIVED',
      'promo-ir07-RA-INST-STATUS-INATIVO',
    ]) {
      await setDoc(doc(db, 'promotion_requests', promoId), promoPayload('RA-OP', false));
    }

    // F-01: Non-boolean / invalid is_k9_instructor values (standalone and combined with legacy true flags)
    const invalidK9Payloads = [
      { key: 'str-false', label: 'string "false"', value: 'false' },
      { key: 'str-true', label: 'string "true"', value: 'true' },
      { key: 'num-0', label: 'number 0', value: 0 },
      { key: 'num-1', label: 'number 1', value: 1 },
      { key: 'str-invalid', label: 'invalid string', value: 'invalid_k9_flag' },
      { key: 'arr', label: 'array []', value: [] },
      { key: 'map', label: 'map {}', value: {} },
    ];

    for (const item of invalidK9Payloads) {
      const standaloneRa = `RA-F01-BAD-${item.key}`;
      await setDoc(doc(db, 'users', standaloneRa), {
        ra: standaloneRa,
        active: true,
        status: 'Ativo',
        deleted_at: null,
        archived_at: null,
        is_k9_instructor: item.value,
      });
      await setDoc(doc(db, 'promotion_requests', `promo-f01-bad-${item.key}`), promoPayload('RA-OP', false));

      const comboRa = `RA-F01-COMBO-${item.key}`;
      await setDoc(doc(db, 'users', comboRa), {
        ra: comboRa,
        active: true,
        status: 'Ativo',
        deleted_at: null,
        archived_at: null,
        access_profile_id: 'operador_k9',
        is_k9_instructor: item.value,
        training_instructor: true,
        instrutor_k9: true,
        instrutor: true,
        adestrador: true,
        training_role: 'instrutor_k9',
        roles: ['instrutor', 'instrutor_k9'],
      });
      const comboDogId = `DOG-F01-COMBO-${item.key}`;
      await setDoc(doc(db, 'dogs', comboDogId), {
        id: comboDogId,
        name: `Dog ${item.key}`,
        conductorRa: comboRa,
      });
      await setDoc(doc(db, 'dogs', comboDogId, 'training', 'busca_captura'), {
        modality: 'busca_captura',
        status: 'operational',
        completed_module_ids: ['modulo_1'],
        completed_modules: [{ module_id: 'modulo_1', module_name: 'Modulo 1', program_version: 1 }],
      });
      await setDoc(doc(db, 'promotion_requests', `promo-f01-combo-other-${item.key}`), promoPayload('RA-OP', false));
      await setDoc(doc(db, 'promotion_requests', `promo-f01-combo-own-${item.key}`), promoPayload(comboRa, false));
    }

    // F-01: Independent Access Profile preservation when is_k9_instructor is invalid + legacy flags true
    await setDoc(doc(db, 'users', 'RA-F01-APPROVER-BAD-K9'), {
      ra: 'RA-F01-APPROVER-BAD-K9',
      active: true,
      status: 'Ativo',
      deleted_at: null,
      archived_at: null,
      access_profile_id: 'training_approver',
      is_k9_instructor: 'false',
      training_instructor: true,
      instrutor_k9: true,
      training_role: 'instrutor_k9',
      roles: ['instrutor_k9'],
    });
    await setDoc(doc(db, 'promotion_requests', 'promo-f01-approver'), promoPayload('RA-OP', false));

    // F-01: Status whitespace & casing normalization in userIsCurrentlyActive()
    const inactiveStatuses = [
      { key: 'ws-inativo', status: '  Inativo  ' },
      { key: 'ws-inactive', status: '  Inactive  ' },
      { key: 'ws-inativo-upper', status: '  INATIVO  ' },
      { key: 'ws-inactive-upper', status: '  INACTIVE  ' },
    ];
    for (const item of inactiveStatuses) {
      await setDoc(doc(db, 'users', `RA-F01-ADMIN-${item.key}`), {
        ra: `RA-F01-ADMIN-${item.key}`,
        active: true,
        status: item.status,
        deleted_at: null,
        archived_at: null,
        access_profile_id: 'administrador',
        admin: true,
      });
      await setDoc(doc(db, 'users', `RA-F01-INST-${item.key}`), {
        ra: `RA-F01-INST-${item.key}`,
        active: true,
        status: item.status,
        deleted_at: null,
        archived_at: null,
        is_k9_instructor: true,
      });
      await setDoc(doc(db, 'promotion_requests', `promo-f01-status-${item.key}`), promoPayload('RA-OP', false));
    }

    // F-01: Explicit is_k9_instructor: null compatibility & negative case, plus trimmed active status
    await setDoc(doc(db, 'users', 'RA-F01-NULL-LEGACY'), {
      ra: 'RA-F01-NULL-LEGACY',
      active: true,
      status: 'Ativo',
      deleted_at: null,
      archived_at: null,
      is_k9_instructor: null,
      training_instructor: true,
      training_role: 'instrutor_k9',
      roles: ['adestrador'],
    });
    await setDoc(doc(db, 'promotion_requests', 'promo-f01-null-legacy'), promoPayload('RA-OP', false));

    await setDoc(doc(db, 'users', 'RA-F01-NULL-NONE'), {
      ra: 'RA-F01-NULL-NONE',
      active: true,
      status: 'Ativo',
      deleted_at: null,
      archived_at: null,
      is_k9_instructor: null,
    });
    await setDoc(doc(db, 'promotion_requests', 'promo-f01-null-none'), promoPayload('RA-OP', false));

    await setDoc(doc(db, 'users', 'RA-F01-ACTIVE-WS'), {
      ra: 'RA-F01-ACTIVE-WS',
      active: true,
      status: '  Ativo  ',
      deleted_at: null,
      archived_at: null,
      is_k9_instructor: true,
    });
    await setDoc(doc(db, 'promotion_requests', 'promo-f01-active-ws'), promoPayload('RA-OP', false));
  });
}

const tests = [];
function test(name, fn) {
  tests.push({ name, fn });
}

// 1. Compatibilidade de usuarios legitimamente autorizados
test('ALLOW legitimate admin reads warehouse_batches, inventory_sessions, clinical_cases and health_timeline', async () => {
  const db = dbFor('RA-ADMIN', { admin: true, access_profile_id: 'administrador' });
  await assertSucceeds(getDoc(doc(db, 'warehouse_batches', 'batch-01')));
  await assertSucceeds(getDoc(doc(db, 'inventory_sessions', 'sess-01')));
  await assertSucceeds(getDoc(doc(db, 'dogs', 'DOG-B', 'clinical_cases', 'case-02')));
  await assertSucceeds(getDoc(doc(db, 'dogs', 'DOG-B', 'health_timeline', 'tl-02')));
});

test('ALLOW legitimate operador_k9 reads own dog clinical_cases & health_timeline, DENY outsider dog & warehouse_batches', async () => {
  const db = dbFor('RA-OP', { access_profile_id: 'operador_k9' });
  await assertSucceeds(getDoc(doc(db, 'dogs', 'DOG-A', 'clinical_cases', 'case-01')));
  await assertSucceeds(getDoc(doc(db, 'dogs', 'DOG-A', 'health_timeline', 'tl-01')));
  await assertFails(getDoc(doc(db, 'dogs', 'DOG-B', 'clinical_cases', 'case-02')));
  await assertFails(getDoc(doc(db, 'dogs', 'DOG-B', 'health_timeline', 'tl-02')));
  await assertFails(getDoc(doc(db, 'warehouse_batches', 'batch-01')));
});

// 2. Claims administrativas antigas / rebaixamento
test('DENY downgraded admin with stale admin:true + access_profile_id:administrador JWT claims', async () => {
  const db = dbFor('RA-DOWNGRADED-ADMIN', {
    admin: true,
    role: 'admin',
    roles: ['administrador'],
    access_profile_id: 'administrador',
  });
  await assertFails(getDoc(doc(db, 'warehouse_batches', 'batch-01')));
  await assertFails(getDoc(doc(db, 'inventory_sessions', 'sess-01')));
  await assertFails(getDoc(doc(db, 'dogs', 'DOG-B', 'clinical_cases', 'case-02')));
  await assertFails(getDoc(doc(db, 'dogs', 'DOG-B', 'health_timeline', 'tl-02')));
});

test('DENY missing users/{ra} document even with admin:true claim', async () => {
  const db = dbFor('RA-MISSING', { admin: true, roles: ['administrador'], access_profile_id: 'administrador' });
  await assertFails(getDoc(doc(db, 'warehouse_batches', 'batch-01')));
  await assertFails(getDoc(doc(db, 'dogs', 'DOG-A', 'health_timeline', 'tl-01')));
});

test('DENY missing ra claim even with admin:true claim', async () => {
  const db = dbFor(undefined, { admin: true, access_profile_id: 'administrador' });
  await assertFails(getDoc(doc(db, 'warehouse_batches', 'batch-01')));
  await assertFails(getDoc(doc(db, 'dogs', 'DOG-A', 'health_timeline', 'tl-01')));
});

// 3. Usuarios inativos e arquivados (preservando access_profile_id: administrador)
for (const inactiveRa of ['RA-INACTIVE-ACTIVE-FALSE', 'RA-DELETED', 'RA-ARCHIVED', 'RA-STATUS-INATIVO']) {
  test(`DENY inactive/archived user (${inactiveRa}) even with admin:true claim and preserved profile`, async () => {
    const db = dbFor(inactiveRa, { admin: true, access_profile_id: 'administrador' });
    await assertFails(getDoc(doc(db, 'warehouse_batches', 'batch-01')));
    await assertFails(getDoc(doc(db, 'inventory_sessions', 'sess-01')));
    await assertFails(getDoc(doc(db, 'dogs', 'DOG-A', 'clinical_cases', 'case-01')));
    await assertFails(getDoc(doc(db, 'dogs', 'DOG-A', 'health_timeline', 'tl-01')));
  });
}

// 4. Ausencia de perfil (sem fallback para JWT ou operador_k9)
test('DENY user with no access_profile_id in users/{ra} even with stale JWT access_profile_id', async () => {
  const db = dbFor('RA-NO-PROFILE', { access_profile_id: 'administrador', access_scope: 'global' });
  await assertFails(getDoc(doc(db, 'warehouse_batches', 'batch-01')));
  await assertFails(getDoc(doc(db, 'dogs', 'DOG-A', 'clinical_cases', 'case-01')));
  await assertFails(getDoc(doc(db, 'dogs', 'DOG-A', 'health_timeline', 'tl-01')));
});

// 5. Instructor Role: autoridade ortogonal + revogacao imediata
test('ALLOW active instructor on training_programs, DENY fabricating access_profile for warehouse/clinical', async () => {
  const db = dbFor('RA-INSTRUCTOR-ONLY', { instrutor_k9: true, access_profile_id: 'administrador' });
  await assertSucceeds(setDoc(doc(db, 'training_programs', 'prog-01'), {
    name: 'Deteccao',
    audit_trail: [{ action: 'create', actor: 'RA-INSTRUCTOR-ONLY', at: Timestamp.now() }],
  }));
  await assertFails(getDoc(doc(db, 'warehouse_batches', 'batch-01')));
  await assertFails(getDoc(doc(db, 'dogs', 'DOG-A', 'clinical_cases', 'case-01')));
});

test('DENY revoked instructor with stale instrutor_k9:true and training_role claims on training_programs', async () => {
  const db = dbFor('RA-INSTRUCTOR-REVOKED', {
    instrutor_k9: true,
    training_instructor: true,
    training_role: 'instrutor_k9',
    roles: ['instrutor_k9'],
  });
  await assertFails(setDoc(doc(db, 'training_programs', 'prog-02'), {
    name: 'Revogado',
    audit_trail: [{ action: 'create', actor: 'RA-INSTRUCTOR-REVOKED', at: Timestamp.now() }],
  }));
});

test('DENY inactive instructor with stale instrutor_k9:true claim on training_programs', async () => {
  const db = dbFor('RA-INSTRUCTOR-INACTIVE', { instrutor_k9: true, training_role: 'instrutor_k9' });
  await assertFails(setDoc(doc(db, 'training_programs', 'prog-03'), {
    name: 'Inativo',
    audit_trail: [{ action: 'create', actor: 'RA-INSTRUCTOR-INACTIVE', at: Timestamp.now() }],
  }));
});

test('IR-01: DENY revoked instructor (is_k9_instructor:false) with residual true legacy flags & roles and stale JWT', async () => {
  const db = dbFor('RA-INST-REVOKED-FLAGS', {
    instrutor_k9: true,
    training_instructor: true,
    role: 'instrutor_k9',
    training_role: 'instrutor_k9',
    roles: ['instrutor_k9'],
  });
  await assertFails(setDoc(doc(db, 'training_programs', 'prog-ir01'), {
    name: 'IR-01',
    audit_trail: [{ action: 'create', actor: 'RA-INST-REVOKED-FLAGS', at: nowTs() }],
  }));
  await assertFails(setDoc(
    doc(db, 'dogs', 'DOG-REVOKED-OP', 'training', 'busca_captura', 'completed_module_corrections', 'corr-ir01'),
    correctionPayload('RA-INST-REVOKED-FLAGS'),
  ));
  await assertFails(setDoc(
    doc(db, 'promotion_requests', 'promo-ir01-direct'),
    promoPayload('RA-INST-REVOKED-FLAGS', true),
  ));
  await assertFails(getDoc(doc(db, 'promotion_requests', 'promo-ir01')));
  await assertFails(updateDoc(
    doc(db, 'promotion_requests', 'promo-ir01'),
    decisionUpdate('RA-INST-REVOKED-FLAGS'),
  ));
  // Base operador_k9 profile remains intact without fabrication or elevation
  await assertSucceeds(getDoc(doc(db, 'dogs', 'DOG-REVOKED-OP')));
  await assertFails(getDoc(doc(db, 'warehouse_batches', 'batch-01')));
});

test('IR-02: DENY revoked instructor (is_k9_instructor:false) with roles/training_role and stale {instrutor_k9:true} JWT', async () => {
  const db = dbFor('RA-INST-REVOKED-ROLES', { instrutor_k9: true });
  await assertFails(setDoc(doc(db, 'training_programs', 'prog-ir02'), {
    name: 'IR-02',
    audit_trail: [{ action: 'create', actor: 'RA-INST-REVOKED-ROLES', at: nowTs() }],
  }));
  await assertFails(setDoc(
    doc(db, 'promotion_requests', 'promo-ir02-direct'),
    promoPayload('RA-INST-REVOKED-ROLES', true),
  ));
  await assertFails(getDoc(doc(db, 'promotion_requests', 'promo-ir02')));
  await assertFails(updateDoc(
    doc(db, 'promotion_requests', 'promo-ir02'),
    decisionUpdate('RA-INST-REVOKED-ROLES'),
  ));
});

test('IR-03: ALLOW active operador_k9 + is_k9_instructor:true on training/instructor ops, DENY warehouse & outsider dog', async () => {
  const db = dbFor('RA-OP-INSTRUCTOR', {});
  await assertSucceeds(setDoc(doc(db, 'training_programs', 'prog-ir03'), {
    name: 'IR-03',
    audit_trail: [{ action: 'create', actor: 'RA-OP-INSTRUCTOR', at: nowTs() }],
  }));
  await assertSucceeds(setDoc(
    doc(db, 'dogs', 'DOG-OP-INST', 'training', 'busca_captura', 'completed_module_corrections', 'corr-ir03'),
    correctionPayload('RA-OP-INSTRUCTOR'),
  ));
  await assertSucceeds(setDoc(
    doc(db, 'promotion_requests', 'promo-ir03-direct'),
    promoPayload('RA-OP-INSTRUCTOR', true),
  ));
  await assertSucceeds(getDoc(doc(db, 'promotion_requests', 'promo-ir03')));
  await assertSucceeds(updateDoc(
    doc(db, 'promotion_requests', 'promo-ir03'),
    decisionUpdate('RA-OP-INSTRUCTOR'),
  ));
  await assertSucceeds(getDoc(doc(db, 'dogs', 'DOG-OP-INST', 'health_timeline', 'tl-op-inst')));
  await assertFails(getDoc(doc(db, 'warehouse_batches', 'batch-01')));
  await assertFails(getDoc(doc(db, 'dogs', 'DOG-B', 'clinical_cases', 'case-02')));
  await assertFails(getDoc(doc(db, 'dogs', 'DOG-B', 'health_timeline', 'tl-02')));
});

test('IR-04: ALLOW instructor-only on promotion_requests read/decide/directInstructor, DENY health_timeline/inventory_sessions', async () => {
  const db = dbFor('RA-INSTRUCTOR-ONLY', {});
  await assertSucceeds(setDoc(
    doc(db, 'promotion_requests', 'promo-ir04-direct'),
    promoPayload('RA-INSTRUCTOR-ONLY', true),
  ));
  await assertSucceeds(getDoc(doc(db, 'promotion_requests', 'promo-ir04')));
  await assertSucceeds(updateDoc(
    doc(db, 'promotion_requests', 'promo-ir04'),
    decisionUpdate('RA-INSTRUCTOR-ONLY'),
  ));
  await assertFails(getDoc(doc(db, 'dogs', 'DOG-A', 'health_timeline', 'tl-01')));
  await assertFails(getDoc(doc(db, 'inventory_sessions', 'sess-01')));
});

for (const [ra, suffix] of [
  ['RA-LEGACY-INST-BOOL', 'bool'],
  ['RA-LEGACY-INST-K9FLAG', 'k9flag'],
  ['RA-LEGACY-INST-ROLE', 'role'],
  ['RA-LEGACY-INST-ROLES', 'roles'],
]) {
  test(`IR-05: ALLOW active legacy-without-canonical (${ra}) on training/promotion_requests without fabricating access_profile`, async () => {
    const db = dbFor(ra, {});
    await assertSucceeds(setDoc(doc(db, 'training_programs', `prog-ir05-${suffix}`), {
      name: `IR-05-${suffix}`,
      audit_trail: [{ action: 'create', actor: ra, at: nowTs() }],
    }));
    await assertSucceeds(setDoc(
      doc(db, 'promotion_requests', `promo-ir05-${suffix}-direct`),
      promoPayload(ra, true),
    ));
    await assertSucceeds(getDoc(doc(db, 'promotion_requests', `promo-ir05-${suffix}`)));
    await assertSucceeds(updateDoc(
      doc(db, 'promotion_requests', `promo-ir05-${suffix}`),
      decisionUpdate(ra),
    ));
    await assertFails(getDoc(doc(db, 'warehouse_batches', 'batch-01')));
    await assertFails(getDoc(doc(db, 'dogs', 'DOG-A', 'clinical_cases', 'case-01')));
    await assertFails(getDoc(doc(db, 'dogs', 'DOG-A', 'health_timeline', 'tl-01')));
  });
}

test('IR-06: DENY missing users/{ra} with instructor JWT claims across training_programs, corrections, and promotion_requests', async () => {
  const db = dbFor('RA-MISSING-INSTRUCTOR', {
    instrutor_k9: true,
    training_instructor: true,
    instrutor: true,
    adestrador: true,
    training_role: 'instrutor_k9',
    roles: ['instrutor_k9'],
  });
  await assertFails(setDoc(doc(db, 'training_programs', 'prog-ir06'), {
    name: 'IR-06',
    audit_trail: [{ action: 'create', actor: 'RA-MISSING-INSTRUCTOR', at: nowTs() }],
  }));
  await assertFails(setDoc(
    doc(db, 'dogs', 'DOG-A', 'training', 'busca_captura', 'completed_module_corrections', 'corr-ir06'),
    correctionPayload('RA-MISSING-INSTRUCTOR'),
  ));
  await assertFails(setDoc(
    doc(db, 'promotion_requests', 'promo-ir06-direct'),
    promoPayload('RA-MISSING-INSTRUCTOR', true),
  ));
  await assertFails(getDoc(doc(db, 'promotion_requests', 'promo-ir06')));
  await assertFails(updateDoc(
    doc(db, 'promotion_requests', 'promo-ir06'),
    decisionUpdate('RA-MISSING-INSTRUCTOR'),
  ));
});

for (const inactiveInstRa of [
  'RA-INST-ACTIVE-FALSE',
  'RA-INST-DELETED',
  'RA-INST-ARCHIVED',
  'RA-INST-STATUS-INATIVO',
]) {
  test(`IR-07: DENY inactive/archived instructor (${inactiveInstRa}) with is_k9_instructor:true and stale JWT`, async () => {
    const db = dbFor(inactiveInstRa, { instrutor_k9: true });
    await assertFails(setDoc(doc(db, 'training_programs', `prog-ir07-${inactiveInstRa}`), {
      name: `IR-07-${inactiveInstRa}`,
      audit_trail: [{ action: 'create', actor: inactiveInstRa, at: nowTs() }],
    }));
    await assertFails(setDoc(
      doc(db, 'promotion_requests', `promo-ir07-${inactiveInstRa}-direct`),
      promoPayload(inactiveInstRa, true),
    ));
    await assertFails(getDoc(doc(db, 'promotion_requests', `promo-ir07-${inactiveInstRa}`)));
    await assertFails(updateDoc(
      doc(db, 'promotion_requests', `promo-ir07-${inactiveInstRa}`),
      decisionUpdate(inactiveInstRa),
    ));
  });
}

// 6. F-01 Fail-Closed Parity & Status Normalization Tests
for (const item of [
  { key: 'str-false', label: 'string "false"' },
  { key: 'str-true', label: 'string "true"' },
  { key: 'num-0', label: 'number 0' },
  { key: 'num-1', label: 'number 1' },
  { key: 'str-invalid', label: 'invalid string' },
  { key: 'arr', label: 'array []' },
  { key: 'map', label: 'map {}' },
]) {
  test(`F01-TYPE-01 (${item.label}): DENY by contract (no evaluation error) standalone invalid is_k9_instructor`, async () => {
    const ra = `RA-F01-BAD-${item.key}`;
    const db = dbFor(ra, { instrutor_k9: true });
    await assertContractDenied(
      setDoc(doc(db, 'training_programs', `prog-f01-bad-${item.key}`), {
        name: `F01-BAD-${item.key}`,
        audit_trail: [{ action: 'create', actor: ra, at: nowTs() }],
      }),
      `${ra} training_programs`,
    );
    await assertContractDenied(
      setDoc(doc(db, 'promotion_requests', `promo-f01-bad-${item.key}-direct`), promoPayload(ra, true)),
      `${ra} direct promo`,
    );
    await assertContractDenied(
      getDoc(doc(db, 'promotion_requests', `promo-f01-bad-${item.key}`)),
      `${ra} read other promo`,
    );
    await assertContractDenied(
      updateDoc(doc(db, 'promotion_requests', `promo-f01-bad-${item.key}`), decisionUpdate(ra)),
      `${ra} decide promo`,
    );
  });

  test(`F01-TYPE-02 (${item.label}): DENY by contract invalid is_k9_instructor combined with legacy true flags while preserving operador_k9`, async () => {
    const ra = `RA-F01-COMBO-${item.key}`;
    const ownDog = `DOG-F01-COMBO-${item.key}`;
    const db = dbFor(ra, {
      instrutor_k9: true,
      training_instructor: true,
      role: 'instrutor_k9',
      training_role: 'instrutor_k9',
      roles: ['instrutor', 'instrutor_k9'],
    });
    await assertContractDenied(
      setDoc(doc(db, 'training_programs', `prog-f01-combo-${item.key}`), {
        name: `F01-COMBO-${item.key}`,
        audit_trail: [{ action: 'create', actor: ra, at: nowTs() }],
      }),
      `${ra} training_programs`,
    );
    await assertContractDenied(
      setDoc(
        doc(db, 'dogs', ownDog, 'training', 'busca_captura', 'completed_module_corrections', `corr-f01-${item.key}`),
        correctionPayload(ra),
      ),
      `${ra} completed_module_corrections`,
    );
    await assertContractDenied(
      setDoc(doc(db, 'promotion_requests', `promo-f01-combo-direct-${item.key}`), promoPayload(ra, true)),
      `${ra} direct promo`,
    );
    await assertContractDenied(
      getDoc(doc(db, 'promotion_requests', `promo-f01-combo-other-${item.key}`)),
      `${ra} read other promo`,
    );
    await assertContractDenied(
      updateDoc(doc(db, 'promotion_requests', `promo-f01-combo-other-${item.key}`), decisionUpdate(ra)),
      `${ra} decide promo`,
    );
    // Clean false evaluation allows independent own-record & base operador_k9 reads to succeed
    await assertSucceeds(getDoc(doc(db, 'promotion_requests', `promo-f01-combo-own-${item.key}`)));
    await assertSucceeds(getDoc(doc(db, 'dogs', ownDog)));
    await assertContractDenied(
      getDoc(doc(db, 'warehouse_batches', 'batch-01')),
      `${ra} warehouse_batches`,
    );
  });
}

test('F01-AP-01: PRESERVE independent Access Profile training.approve permission even when is_k9_instructor is invalid "false"', async () => {
  const ra = 'RA-F01-APPROVER-BAD-K9';
  const db = dbFor(ra, {});
  await assertSucceeds(getDoc(doc(db, 'promotion_requests', 'promo-f01-approver')));
  await assertContractDenied(
    setDoc(doc(db, 'training_programs', 'prog-f01-approver'), {
      name: 'F01-APPROVER',
      audit_trail: [{ action: 'create', actor: ra, at: nowTs() }],
    }),
    `${ra} training_programs`,
  );
});

for (const item of [
  { key: 'ws-inativo', label: '  Inativo  ' },
  { key: 'ws-inactive', label: '  Inactive  ' },
  { key: 'ws-inativo-upper', label: '  INATIVO  ' },
  { key: 'ws-inactive-upper', label: '  INACTIVE  ' },
]) {
  test(`F01-STATUS-01 (${item.label}): DENY by contract admin & instructor with whitespace/case status`, async () => {
    const adminRa = `RA-F01-ADMIN-${item.key}`;
    const adminDb = dbFor(adminRa, { admin: true, access_profile_id: 'administrador' });
    await assertContractDenied(getDoc(doc(adminDb, 'warehouse_batches', 'batch-01')), `${adminRa} warehouse`);
    await assertContractDenied(getDoc(doc(adminDb, 'inventory_sessions', 'sess-01')), `${adminRa} inventory_sessions`);
    await assertContractDenied(getDoc(doc(adminDb, 'dogs', 'DOG-A', 'clinical_cases', 'case-01')), `${adminRa} clinical`);
    await assertContractDenied(getDoc(doc(adminDb, 'dogs', 'DOG-A', 'health_timeline', 'tl-01')), `${adminRa} timeline`);
    await assertContractDenied(
      setDoc(doc(adminDb, 'training_programs', `prog-f01-adm-${item.key}`), {
        name: `F01-ADM-${item.key}`,
        audit_trail: [{ action: 'create', actor: adminRa, at: nowTs() }],
      }),
      `${adminRa} training_programs`,
    );

    const instRa = `RA-F01-INST-${item.key}`;
    const instDb = dbFor(instRa, { instrutor_k9: true });
    await assertContractDenied(
      setDoc(doc(instDb, 'training_programs', `prog-f01-inst-${item.key}`), {
        name: `F01-INST-${item.key}`,
        audit_trail: [{ action: 'create', actor: instRa, at: nowTs() }],
      }),
      `${instRa} training_programs`,
    );
    await assertContractDenied(
      setDoc(doc(instDb, 'promotion_requests', `promo-f01-inst-direct-${item.key}`), promoPayload(instRa, true)),
      `${instRa} direct promo`,
    );
    await assertContractDenied(
      getDoc(doc(instDb, 'promotion_requests', `promo-f01-status-${item.key}`)),
      `${instRa} read promo`,
    );
    await assertContractDenied(
      updateDoc(doc(instDb, 'promotion_requests', `promo-f01-status-${item.key}`), decisionUpdate(instRa)),
      `${instRa} decide promo`,
    );
  });
}

test('F01-COMPAT-01: ALLOW active user with explicit is_k9_instructor:null + ratified legacy flags (orthogonal, no profile fabrication)', async () => {
  const ra = 'RA-F01-NULL-LEGACY';
  const db = dbFor(ra, {});
  await assertSucceeds(setDoc(doc(db, 'training_programs', 'prog-f01-null-legacy'), {
    name: 'F01-NULL-LEGACY',
    audit_trail: [{ action: 'create', actor: ra, at: nowTs() }],
  }));
  await assertSucceeds(setDoc(doc(db, 'promotion_requests', 'promo-f01-null-legacy-direct'), promoPayload(ra, true)));
  await assertSucceeds(getDoc(doc(db, 'promotion_requests', 'promo-f01-null-legacy')));
  await assertSucceeds(updateDoc(doc(db, 'promotion_requests', 'promo-f01-null-legacy'), decisionUpdate(ra)));
  await assertContractDenied(getDoc(doc(db, 'warehouse_batches', 'batch-01')), `${ra} warehouse`);
  await assertContractDenied(getDoc(doc(db, 'dogs', 'DOG-A', 'clinical_cases', 'case-01')), `${ra} clinical`);
  await assertContractDenied(getDoc(doc(db, 'dogs', 'DOG-A', 'health_timeline', 'tl-01')), `${ra} timeline`);
});

test('F01-COMPAT-02: DENY by contract active user with is_k9_instructor:null and zero legacy flags', async () => {
  const ra = 'RA-F01-NULL-NONE';
  const db = dbFor(ra, { instrutor_k9: true, training_instructor: true, roles: ['instrutor_k9'] });
  await assertContractDenied(
    setDoc(doc(db, 'training_programs', 'prog-f01-null-none'), {
      name: 'F01-NULL-NONE',
      audit_trail: [{ action: 'create', actor: ra, at: nowTs() }],
    }),
    `${ra} training_programs`,
  );
  await assertContractDenied(
    setDoc(doc(db, 'promotion_requests', 'promo-f01-null-none-direct'), promoPayload(ra, true)),
    `${ra} direct promo`,
  );
  await assertContractDenied(
    getDoc(doc(db, 'promotion_requests', 'promo-f01-null-none')),
    `${ra} read promo`,
  );
  await assertContractDenied(
    updateDoc(doc(db, 'promotion_requests', 'promo-f01-null-none'), decisionUpdate(ra)),
    `${ra} decide promo`,
  );
});

test('F01-POS-01: ALLOW legitimate active instructor with trimmed active status ("  Ativo  ") and is_k9_instructor:true', async () => {
  const ra = 'RA-F01-ACTIVE-WS';
  const db = dbFor(ra, {});
  await assertSucceeds(setDoc(doc(db, 'training_programs', 'prog-f01-active-ws'), {
    name: 'F01-ACTIVE-WS',
    audit_trail: [{ action: 'create', actor: ra, at: nowTs() }],
  }));
  await assertSucceeds(setDoc(doc(db, 'promotion_requests', 'promo-f01-active-ws-direct'), promoPayload(ra, true)));
  await assertSucceeds(getDoc(doc(db, 'promotion_requests', 'promo-f01-active-ws')));
  await assertSucceeds(updateDoc(doc(db, 'promotion_requests', 'promo-f01-active-ws'), decisionUpdate(ra)));
});

let passed = 0;
let failed = 0;
try {
  await seedFixtures();
  for (const t of tests) {
    try {
      await t.fn();
      console.log(`  ✓ PASS: ${t.name}`);
      passed++;
    } catch (err) {
      console.error(`  ✗ FAIL: ${t.name}\n   `, err);
      failed++;
    }
  }
  console.log(`\nF20 SEC-02A.2 Adversarial Rules Results: ${passed}/${tests.length} PASSED (${failed} FAILED)`);
  if (failed > 0) process.exitCode = 1;
} finally {
  await testEnv.cleanup();
}
