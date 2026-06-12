import assert from 'node:assert/strict';

import {
  assertFails,
  assertSucceeds,
  initializeTestEnvironment,
} from '@firebase/rules-unit-testing';
import {
  doc,
  collection,
  getDocs,
  getDoc,
  query,
  serverTimestamp,
  setDoc,
  updateDoc,
  where,
  writeBatch,
  arrayUnion,
  Timestamp,
} from 'firebase/firestore';
import {
  deleteObject,
  ref,
  uploadString,
} from 'firebase/storage';

const PROJECT_ID = process.env.GCLOUD_PROJECT || 'canil-gcm';
const DOG_ID = 'bono';
const PRIMARY_RA = '691755';
const MEMBER_RA = '691640';
const OUTSIDER_RA = '999999';

const testEnv = await initializeTestEnvironment({
  projectId: PROJECT_ID,
});

const tests = [];

function test(name, fn) {
  tests.push({name, fn});
}

function auth(ra, claims = {}) {
  return testEnv.authenticatedContext(`uid-${ra}`, {
    email: `${ra}@gcm.com.br`,
    ...claims,
  });
}

function dbFor(ra, claims = {}) {
  return auth(ra, claims).firestore();
}

function storageFor(ra) {
  return auth(ra).storage();
}

function now() {
  return Timestamp.fromDate(new Date('2026-05-31T12:00:00.000Z'));
}

function audit(action = 'created', by = PRIMARY_RA) {
  return [{action, by, at: now()}];
}

function trainingPayload(ra = PRIMARY_RA, dogId = DOG_ID) {
  return {
    dogId,
    dog_id: dogId,
    handlerId: ra,
    handler_id: ra,
    performed_by: ra,
    type: 'deteccao',
    result: 'bom',
    created_at: now(),
    audit_trail: audit('created', ra),
  };
}

function trainingProgressPayload({
  status = 'in_formation',
  currentModule = 'modulo_1',
  auditTrail = audit(),
} = {}) {
  return {
    modality: 'busca_captura',
    status,
    current_module: currentModule,
    current_module_id: currentModule,
    program_version: 1,
    completed_module_ids: [],
    completed_modules: [],
    achieved_milestones: {},
    updated_at: now(),
    audit_trail: auditTrail,
  };
}

function promotionRequestPayload(ra = PRIMARY_RA, {directInstructor = false} = {}) {
  return {
    dog_id: DOG_ID,
    dog_name: 'Bono',
    modality: 'busca_captura',
    program_id: 'busca_captura',
    program_version: 1,
    module_id: 'modulo_1',
    module_name: 'Modulo 1',
    module_order: 1,
    status: 'pending',
    direct_instructor: directInstructor,
    requester_ra: ra,
    requester_name: `GCM ${ra}`,
    requested_by_uid: `uid-${ra}`,
    requested_by_email: `${ra}@gcm.com.br`,
    requested_at: now(),
    created_at: now(),
    updated_at: now(),
    marks_snapshot: [
      {
        milestone_id: 'marco_1',
        order: 1,
        label: 'Marco 1',
        required: true,
        achieved: true,
        achieved_at: now(),
        achieved_by: ra,
        program_version: 1,
      },
    ],
    audit_trail: audit('created', ra),
  };
}

function activeShiftPayload(ra = PRIMARY_RA, dogId = DOG_ID) {
  return {
    shiftId: `shift-${ra}`,
    handlerId: ra,
    auth_uid: `uid-${ra}`,
    handler_email: `${ra}@gcm.com.br`,
    dogId,
    service_dog_id: dogId,
    status: 'active',
    startedAt: now(),
    updatedAt: now(),
  };
}

function occurrencePayload({
  id = 'occ-1',
  status = 'in_progress',
  accepted = [PRIMARY_RA],
  pending = [MEMBER_RA],
  signed = [],
  round = 1,
} = {}) {
  return {
    id,
    status,
    title: 'Averiguacao de atitude suspeita',
    primary_handler_id: `uid-${PRIMARY_RA}`,
    primary_handler_ra: PRIMARY_RA,
    created_by: PRIMARY_RA,
    created_by_ra: PRIMARY_RA,
    team_handler_ids: [PRIMARY_RA, MEMBER_RA],
    team_emails: [`${PRIMARY_RA}@gcm.com.br`, `${MEMBER_RA}@gcm.com.br`],
    team_auth_uids: [`uid-${PRIMARY_RA}`, `uid-${MEMBER_RA}`],
    team_auth_keys: [
      `${PRIMARY_RA}:uid-${PRIMARY_RA}`,
      `${MEMBER_RA}:uid-${MEMBER_RA}`,
    ],
    accepted_handler_ids: accepted,
    declined_handler_ids: [],
    pending_handler_ids: pending,
    edit_authorized_handler_ids: accepted,
    edit_authorized_emails: accepted.map((ra) => `${ra}@gcm.com.br`),
    signed_handler_ids: signed,
    signature_round: round,
    participation_revision: 1,
    updated_at: now(),
    audit_trail: audit(),
  };
}

function documentPayload({withAudit = true} = {}) {
  return {
    caoId: DOG_ID,
    nome: 'Laudo veterinario',
    descricao: 'Documento de teste',
    tipo: 'laudo',
    url: 'https://example.invalid/laudo.pdf',
    dataUpload: now(),
    ...(withAudit ? {audit_trail: audit()} : {}),
  };
}

function amendmentPayload(ra = PRIMARY_RA) {
  return {
    occurrence_id: 'occ-amendment',
    reason: 'Ajuste posterior justificado',
    corrections: {final_report: 'Texto retificado'},
    created_by: ra,
    created_by_name: `GCM ${ra}`,
    created_by_ra: ra,
    created_at: now(),
    integrity_hash: 'a'.repeat(64),
    sequence_number: 1,
  };
}

function auditLogPayload({spoof = false} = {}) {
  const ra = PRIMARY_RA;
  return {
    action: 'created',
    entity_type: 'training',
    entity_id: 'training-1',
    entity_path: 'training/training-1',
    summary: 'Registro criado',
    actor: {
      uid: spoof ? 'uid-invasor' : `uid-${ra}`,
      email: `${ra}@gcm.com.br`,
      ra,
      name: 'Ragonha',
    },
    source: 'mobile',
    client_time: '2026-05-31T12:00:00.000Z',
    performed_at: now(),
    entityType: 'training',
    entityId: 'training-1',
    entityPath: 'training/training-1',
    createdAt: now(),
  };
}

function notificationPayload(occurrenceId = 'occ-notification', overrides = {}) {
  return {
    type: 'signature_requested',
    occurrence_id: occurrenceId,
    occurrence_title: 'Averiguacao de atitude suspeita',
    created_at: now(),
    read_at: null,
    target_screen: 'occurrence_review',
    action_required: true,
    ...overrides,
  };
}

async function seedFirestore(seedFn) {
  await testEnv.withSecurityRulesDisabled(async (context) => {
    await seedFn(context.firestore());
  });
}

async function clearAll() {
  await testEnv.clearFirestore();
  if (typeof testEnv.clearStorage === 'function') {
    await testEnv.clearStorage();
  }
}

test('treino sem turno ativo e recusado; com turno ativo e aceito', async () => {
  const db = dbFor(PRIMARY_RA);

  await assertFails(
    setDoc(doc(db, 'trainings/no-shift'), trainingPayload()),
  );

  await assertSucceeds(
    setDoc(doc(db, 'active_shifts', PRIMARY_RA), activeShiftPayload()),
  );

  await assertSucceeds(
    setDoc(doc(db, 'trainings/with-shift'), trainingPayload()),
  );
});

test('turno ativo so pode ser gravado pelo proprio RA autenticado', async () => {
  await assertFails(
    setDoc(
      doc(dbFor(PRIMARY_RA), 'active_shifts', MEMBER_RA),
      activeShiftPayload(MEMBER_RA),
    ),
  );

  await assertSucceeds(
    setDoc(
      doc(dbFor(PRIMARY_RA), 'active_shifts', PRIMARY_RA),
      activeShiftPayload(PRIMARY_RA),
    ),
  );
});

test('treino para K9 diferente do turno ativo e recusado', async () => {
  const db = dbFor(PRIMARY_RA);

  await assertSucceeds(
    setDoc(doc(db, 'active_shifts', PRIMARY_RA), activeShiftPayload()),
  );

  await assertFails(
    setDoc(doc(db, 'trainings/wrong-dog'), trainingPayload(PRIMARY_RA, 'rex')),
  );
});

test('curriculo de treino tem leitura autenticada e escrita por claim tecnico', async () => {
  await assertSucceeds(
    getDoc(doc(dbFor(PRIMARY_RA), 'training_programs/busca_captura')),
  );

  await assertFails(
    setDoc(doc(dbFor(PRIMARY_RA), 'training_programs/busca_captura'), {
      name: 'Busca & Captura',
      modality: 'busca_captura',
      version: 1,
      active: true,
    }),
  );

  await assertSucceeds(
    setDoc(
      doc(
        dbFor(PRIMARY_RA, {instrutor: true}),
        'training_programs/busca_captura',
      ),
      {
        name: 'Busca & Captura',
        modality: 'busca_captura',
        version: 1,
        active: true,
        audit_trail: audit('created'),
      },
    ),
  );

  await assertFails(
    updateDoc(
      doc(
        dbFor(PRIMARY_RA, {instrutor: true}),
        'training_programs/busca_captura',
      ),
      {
        version: 2,
      },
    ),
  );

  await assertSucceeds(
    updateDoc(
      doc(
        dbFor(PRIMARY_RA, {instrutor: true}),
        'training_programs/busca_captura',
      ),
      {
        version: 2,
        audit_trail: [...audit('created'), ...audit('updated')],
      },
    ),
  );

  await assertSucceeds(
    setDoc(
      doc(
        dbFor(PRIMARY_RA, {adestrador: true}),
        'training_programs/busca_captura/modules/modulo_1/milestones/marco_1',
      ),
      {
        order: 1,
        label: 'Marco tecnico',
        required: true,
        active: true,
        audit_trail: audit('created'),
      },
    ),
  );
});

test('progressao canonica de treino exige status valido e auditoria', async () => {
  const db = dbFor(PRIMARY_RA);
  const progressRef = doc(db, 'dogs/bono/training/busca_captura');

  await assertSucceeds(getDoc(progressRef));

  await assertFails(
    setDoc(progressRef, {
      ...trainingProgressPayload(),
      audit_trail: [],
    }),
  );

  await assertFails(
    setDoc(progressRef, {
      ...trainingProgressPayload(),
      status: 'certified',
    }),
  );

  await assertSucceeds(setDoc(progressRef, trainingProgressPayload()));

  await assertSucceeds(
    updateDoc(progressRef, {
      achieved_milestones: {
        modulo_1: {
          marco_1: {
            milestone_id: 'marco_1',
            label: 'Marco 1',
            required: true,
            achieved: true,
            achieved_at: now(),
            achieved_by: PRIMARY_RA,
            program_version: 1,
          },
        },
      },
      program_version: 1,
      updated_at: now(),
      audit_trail: [...audit('created'), ...audit('updated')],
    }),
  );

  await assertFails(
    updateDoc(progressRef, {
      status: 'operational',
      current_module: null,
      current_module_id: null,
      operational_since: now(),
      completed_module_ids: ['modulo_1'],
      completed_modules: [
        {
          module_id: 'modulo_1',
          module_order: 1,
          module_name: 'Modulo 1',
          program_version: 1,
          completed_at: now(),
          completed_by: PRIMARY_RA,
          milestones: [
            {
              milestone_id: 'marco_1',
              label: 'Marco 1',
              required: true,
              achieved: true,
              achieved_at: now(),
              achieved_by: PRIMARY_RA,
              program_version: 1,
            },
          ],
        },
      ],
      updated_at: now(),
      audit_trail: [...audit('created'), ...audit('updated')],
    }),
  );
});

test('modulo concluido e imutavel e correcao exige trilha de instrutor', async () => {
  await seedFirestore(async (seedDb) => {
    await setDoc(doc(seedDb, 'dogs/bono/training/busca_captura'), {
      ...trainingProgressPayload({
        status: 'operational',
        currentModule: null,
        auditTrail: audit('created'),
      }),
      completed_module_ids: ['modulo_1'],
      completed_modules: [
        {
          module_id: 'modulo_1',
          module_name: 'Modulo 1',
          program_version: 1,
        },
      ],
    });
  });

  const progressRef = doc(
    dbFor(MEMBER_RA, {role: 'instrutor_k9'}),
    'dogs/bono/training/busca_captura',
  );
  const correctionRef = doc(
    dbFor(MEMBER_RA, {role: 'instrutor_k9'}),
    'dogs/bono/training/busca_captura/completed_module_corrections/corr-1',
  );

  await assertFails(
    updateDoc(progressRef, {
      completed_modules: [
        {
          module_id: 'modulo_1',
          module_name: 'Modulo 1 corrigido',
          program_version: 1,
        },
      ],
      updated_at: now(),
      audit_trail: [...audit('created'), ...audit('updated', MEMBER_RA)],
    }),
  );

  await assertFails(
    setDoc(
      doc(
        dbFor(PRIMARY_RA),
        'dogs/bono/training/busca_captura/completed_module_corrections/corr-1',
      ),
      {
        module_id: 'modulo_1',
        correction_type: 'observacao',
        reason: 'Ajuste de anotacao feito apos revisao.',
        before_snapshot: {module_id: 'modulo_1', module_name: 'Modulo 1'},
        requested_changes: {note: 'Sem alteracao do snapshot canonico.'},
        corrected_by: PRIMARY_RA,
        created_at: now(),
        updated_at: now(),
        audit_trail: audit('created', PRIMARY_RA),
      },
    ),
  );

  await assertSucceeds(
    setDoc(correctionRef, {
      module_id: 'modulo_1',
      correction_type: 'observacao',
      reason: 'Ajuste de anotacao feito apos revisao.',
      before_snapshot: {module_id: 'modulo_1', module_name: 'Modulo 1'},
      requested_changes: {note: 'Sem alteracao do snapshot canonico.'},
      corrected_by: MEMBER_RA,
      corrected_by_uid: `uid-${MEMBER_RA}`,
      corrected_by_email: `${MEMBER_RA}@gcm.com.br`,
      corrected_by_name: `GCM ${MEMBER_RA}`,
      created_at: now(),
      updated_at: now(),
      audit_trail: audit('created', MEMBER_RA),
    }),
  );

  await assertFails(
    updateDoc(correctionRef, {
      reason: 'Edicao posterior indevida.',
      updated_at: now(),
      audit_trail: [...audit('created', MEMBER_RA), ...audit('updated', MEMBER_RA)],
    }),
  );
});

test('inicializacao B&C cria progressao e specialty espelhada', async () => {
  const db = dbFor(PRIMARY_RA);
  const progressRef = doc(db, 'dogs/bono/training/busca_captura');
  const specialtyRef = doc(db, 'dogs/bono/specialties/busca_captura');

  await assertSucceeds(
    setDoc(progressRef, {
      ...trainingProgressPayload(),
      created_at: now(),
    }),
  );

  await assertSucceeds(
    setDoc(specialtyRef, {
      type: 'busca_captura',
      name: 'Busca & Captura',
      status: 'in_formation',
      state: 'in_formation',
      program_version: 1,
      current_module: 'modulo_1',
      current_phase: 'modulo_1',
      progress_percentage: 0,
      created_at: now(),
      started_at: now(),
      updated_at: now(),
      audit_trail: audit('created'),
    }),
  );
});

test('B&C inicializa e marca marco em batch junto com specialty', async () => {
  const db = dbFor(PRIMARY_RA);
  const progressRef = doc(db, 'dogs/bono/training/busca_captura');
  const specialtyRef = doc(db, 'dogs/bono/specialties/busca_captura');

  const initBatch = writeBatch(db);
  initBatch.set(progressRef, {
    ...trainingProgressPayload(),
    created_at: now(),
  });
  initBatch.set(specialtyRef, {
    type: 'busca_captura',
    name: 'Busca & Captura',
    status: 'in_formation',
    state: 'in_formation',
    program_version: 1,
    current_module: 'modulo_1',
    current_phase: 'modulo_1',
    progress_percentage: 0,
    created_at: now(),
    started_at: now(),
    updated_at: now(),
    audit_trail: audit('created'),
  });
  await assertSucceeds(initBatch.commit());

  const markBatch = writeBatch(db);
  markBatch.update(progressRef, {
    achieved_milestones: {
      modulo_1: {
        marco_1: {
          milestone_id: 'marco_1',
          label: 'Marco 1',
          required: true,
          achieved: true,
          achieved_at: now(),
          achieved_by: PRIMARY_RA,
          program_version: 1,
        },
      },
    },
    program_version: 1,
    updated_at: now(),
    audit_trail: [...audit('created'), ...audit('updated')],
  });
  markBatch.update(specialtyRef, {
    type: 'busca_captura',
    name: 'Busca & Captura',
    status: 'in_formation',
    state: 'in_formation',
    program_version: 1,
    current_module: 'modulo_1',
    current_phase: 'modulo_1',
    progress_percentage: 0,
    updated_at: now(),
    audit_trail: [...audit('created'), ...audit('updated')],
  });
  await assertSucceeds(markBatch.commit());
});

test('B&C inicializa progressao quando specialty legado ja existe', async () => {
  await seedFirestore(async (seedDb) => {
    await setDoc(doc(seedDb, 'dogs/bono/specialties/busca_captura'), {
      type: 'busca_captura',
      status: 'in_formation',
      started_at: now(),
    });
  });

  const db = dbFor(PRIMARY_RA);
  const progressRef = doc(db, 'dogs/bono/training/busca_captura');
  const specialtyRef = doc(db, 'dogs/bono/specialties/busca_captura');

  const initBatch = writeBatch(db);
  initBatch.set(progressRef, {
    modality: 'busca_captura',
    status: 'in_formation',
    current_module: 'modulo_1',
    current_module_id: 'modulo_1',
    program_version: 1,
    completed_module_ids: [],
    completed_modules: [],
    achieved_milestones: {},
    created_at: serverTimestamp(),
    updated_at: serverTimestamp(),
    audit_trail: audit('created'),
  });
  initBatch.set(
    specialtyRef,
    {
      type: 'busca_captura',
      name: 'Busca & Captura',
      status: 'in_formation',
      state: 'in_formation',
      program_version: 1,
      current_module: 'modulo_1',
      current_phase: 'modulo_1',
      progress_percentage: 0,
      updated_at: serverTimestamp(),
      audit_trail: arrayUnion(...audit('created')),
    },
    {merge: true},
  );
  await assertSucceeds(initBatch.commit());
});

test('B&C normaliza progressao legada antes de marcar marco', async () => {
  await seedFirestore(async (seedDb) => {
    await setDoc(doc(seedDb, 'dogs/bono/training/busca_captura'), {
      status: 'em_formacao',
      current_module: 'modulo_1',
      audit_trail: audit('created'),
    });
  });

  const db = dbFor(PRIMARY_RA);
  const progressRef = doc(db, 'dogs/bono/training/busca_captura');

  await assertSucceeds(
    updateDoc(progressRef, {
      modality: 'busca_captura',
      status: 'in_formation',
      current_module: 'modulo_1',
      current_module_id: 'modulo_1',
      program_version: 1,
      completed_module_ids: [],
      completed_modules: [],
      achieved_milestones: {},
      operational_since: null,
      updated_at: now(),
      audit_trail: [...audit('created'), ...audit('updated')],
    }),
  );

  await assertSucceeds(
    updateDoc(progressRef, {
      achieved_milestones: {
        modulo_1: {
          marco_1: {
            milestone_id: 'marco_1',
            label: 'Marco 1',
            required: true,
            achieved: true,
            achieved_at: now(),
            achieved_by: PRIMARY_RA,
            program_version: 1,
          },
        },
      },
      program_version: 1,
      updated_at: now(),
      audit_trail: [
        ...audit('created'),
        ...audit('updated'),
        ...audit('updated'),
      ],
    }),
  );

  await assertFails(
    updateDoc(progressRef, {
      completed_module_ids: ['modulo_1'],
      completed_modules: [{
        module_id: 'modulo_1',
        module_name: 'Modulo 1',
        program_version: 1,
      }],
      updated_at: now(),
      audit_trail: [
        ...audit('created'),
        ...audit('updated'),
        ...audit('updated'),
        ...audit('updated'),
      ],
    }),
  );
});

test('marco-bonus B&C e aditivo apenas para cao operacional', async () => {
  await seedFirestore(async (seedDb) => {
    await setDoc(
      doc(seedDb, 'dogs/bono/training/busca_captura'),
      trainingProgressPayload({
        status: 'operational',
        currentModule: null,
        auditTrail: audit('created'),
      }),
    );
  });

  const db = dbFor(PRIMARY_RA);
  const bonusRef = doc(
    db,
    'dogs/bono/training/busca_captura/bonus_milestones/modulo_3__novo_marco',
  );

  await assertSucceeds(
    setDoc(bonusRef, {
      module_id: 'modulo_3',
      module_order: 3,
      module_name: 'Modulo 3',
      milestone_id: 'novo_marco',
      milestone_order: 5,
      label: 'Novo marco operacional',
      required: true,
      program_version: 2,
      completed_at: serverTimestamp(),
      by: PRIMARY_RA,
      completed_by: PRIMARY_RA,
      created_at: serverTimestamp(),
      updated_at: serverTimestamp(),
      audit_trail: audit('created'),
    }),
  );

  await assertFails(
    updateDoc(bonusRef, {
      label: 'Alterado',
      updated_at: serverTimestamp(),
      audit_trail: [...audit('created'), ...audit('updated')],
    }),
  );

  await seedFirestore(async (seedDb) => {
    await setDoc(
      doc(seedDb, 'dogs/apolo/training/busca_captura'),
      trainingProgressPayload({status: 'in_formation'}),
    );
  });

  await assertFails(
    setDoc(
      doc(
        db,
        'dogs/apolo/training/busca_captura/bonus_milestones/modulo_1__precoce',
      ),
      {
        module_id: 'modulo_1',
        module_order: 1,
        module_name: 'Modulo 1',
        milestone_id: 'precoce',
        milestone_order: 9,
        label: 'Bonus precoce',
        required: true,
        program_version: 2,
        completed_at: serverTimestamp(),
        by: PRIMARY_RA,
        completed_by: PRIMARY_RA,
        created_at: serverTimestamp(),
        updated_at: serverTimestamp(),
        audit_trail: audit('created'),
      },
    ),
  );
});

test('promotion_requests: condutor solicita e Instrutor K9 decide', async () => {
  const requestRef = doc(dbFor(PRIMARY_RA), 'promotion_requests/promo-1');

  await assertSucceeds(setDoc(requestRef, promotionRequestPayload()));

  await assertFails(
    getDocs(
      query(
        collection(dbFor(PRIMARY_RA), 'promotion_requests'),
        where('dog_id', '==', DOG_ID),
        where('modality', '==', 'busca_captura'),
        where('module_id', '==', 'modulo_1'),
        where('status', '==', 'pending'),
      ),
    ),
  );

  await assertSucceeds(
    getDocs(
      query(
        collection(dbFor(PRIMARY_RA), 'promotion_requests'),
        where('dog_id', '==', DOG_ID),
        where('modality', '==', 'busca_captura'),
        where('module_id', '==', 'modulo_1'),
        where('status', '==', 'pending'),
        where('requester_ra', '==', PRIMARY_RA),
      ),
    ),
  );

  await assertFails(
    setDoc(
      doc(dbFor(OUTSIDER_RA), 'promotion_requests/promo-spoof'),
      promotionRequestPayload(PRIMARY_RA),
    ),
  );

  await assertFails(
    setDoc(
      doc(dbFor(PRIMARY_RA), 'promotion_requests/promo-direct-denied'),
      promotionRequestPayload(PRIMARY_RA, {directInstructor: true}),
    ),
  );

  await assertSucceeds(
    setDoc(
      doc(
        dbFor(PRIMARY_RA, {role: 'instrutor_k9'}),
        'promotion_requests/promo-direct-allowed',
      ),
      promotionRequestPayload(PRIMARY_RA, {directInstructor: true}),
    ),
  );

  await assertFails(
    updateDoc(doc(dbFor(MEMBER_RA), 'promotion_requests/promo-1'), {
      status: 'approved',
      decision: 'approved',
      decision_by: MEMBER_RA,
      decision_by_uid: `uid-${MEMBER_RA}`,
      decision_by_email: `${MEMBER_RA}@gcm.com.br`,
      decision_reason: null,
      decided_at: now(),
      updated_at: now(),
      audit_trail: [...audit('created'), ...audit('approved', MEMBER_RA)],
    }),
  );

  await assertFails(
    updateDoc(
      doc(dbFor(MEMBER_RA, {role: 'instrutor_k9'}), 'promotion_requests/promo-1'),
      {
        status: 'rejected',
        decision: 'rejected',
        decision_by: MEMBER_RA,
        decision_by_uid: `uid-${MEMBER_RA}`,
        decision_by_email: `${MEMBER_RA}@gcm.com.br`,
        decision_reason: '',
        decided_at: now(),
        updated_at: now(),
        audit_trail: [...audit('created'), ...audit('rejected', MEMBER_RA)],
      },
    ),
  );

  await assertSucceeds(
    updateDoc(
      doc(dbFor(MEMBER_RA, {role: 'instrutor_k9'}), 'promotion_requests/promo-1'),
      {
        status: 'approved',
        decision: 'approved',
        decision_by: MEMBER_RA,
        decision_by_uid: `uid-${MEMBER_RA}`,
        decision_by_email: `${MEMBER_RA}@gcm.com.br`,
        decision_reason: null,
        decided_at: now(),
        updated_at: now(),
        audit_trail: [...audit('created'), ...audit('approved', MEMBER_RA)],
      },
    ),
  );
});

test('sessao de trilha B&C grava na subcollection do cao com dog coerente', async () => {
  const db = dbFor(PRIMARY_RA);

  await assertSucceeds(
    setDoc(doc(db, 'active_shifts', PRIMARY_RA), activeShiftPayload()),
  );

  await assertSucceeds(
    setDoc(doc(db, 'dogs/bono/training_sessions/bc-track-1'), {
      dogId: DOG_ID,
      dog_id: DOG_ID,
      handlerId: PRIMARY_RA,
      handler_id: PRIMARY_RA,
      trainingType: 'Busca & Captura',
      modality: 'busca_captura',
      phase: 'formation',
      module_id: 'modulo_1',
      milestone_id: 'marco_1',
      result: 'completa',
      date: now(),
      track: {
        distance_m: 120,
        duration_s: 360,
        events: [
          {
            type: 'cao_indicou',
            timestamp: '2026-06-01T09:32:00.000Z',
            lat: -22.56,
            lng: -47.4,
          },
        ],
        path: [],
        offline_synced: true,
      },
      audit_trail: audit(),
    }),
  );

  await assertFails(
    setDoc(doc(db, 'dogs/bono/training_sessions/bc-track-wrong-dog'), {
      dogId: 'thor',
      dog_id: 'thor',
      handlerId: PRIMARY_RA,
      trainingType: 'Busca & Captura',
      modality: 'busca_captura',
      phase: 'formation',
      result: 'parcial',
      date: now(),
      track: {events: [], path: [], offline_synced: true},
      audit_trail: audit(),
    }),
  );
});

test('sessao B&C offline pode sincronizar sem turno ativo pelo proprio condutor', async () => {
  await seedFirestore(async (adminDb) => {
    await setDoc(doc(adminDb, 'dogs/bono'), {
      id: DOG_ID,
      name: 'Bono',
      audit_trail: audit(),
    });
  });

  await assertSucceeds(
    setDoc(doc(dbFor(PRIMARY_RA), 'dogs/bono/training_sessions/bc-offline-1'), {
      dogId: DOG_ID,
      dog_id: DOG_ID,
      handlerId: PRIMARY_RA,
      handler_id: PRIMARY_RA,
      trainingType: 'Busca & Captura',
      training_type: 'Busca & Captura',
      modality: 'busca_captura',
      specialty: 'busca_captura',
      type: 'busca_captura_track',
      phase: 'formation',
      result: 'parcial',
      date: now(),
      track: {events: [], path: [], offline_synced: true},
      audit_trail: audit(),
    }),
  );

  await assertFails(
    setDoc(doc(dbFor(PRIMARY_RA), 'dogs/bono/training_sessions/bc-spoof'), {
      dogId: DOG_ID,
      dog_id: DOG_ID,
      handlerId: MEMBER_RA,
      handler_id: MEMBER_RA,
      trainingType: 'Busca & Captura',
      modality: 'busca_captura',
      phase: 'formation',
      result: 'parcial',
      date: now(),
      track: {events: [], path: [], offline_synced: true},
      audit_trail: audit(),
    }),
  );
});

test('integrante pendente nao edita ocorrencia; aceito edita', async () => {
  const occId = 'occ-edit';

  await seedFirestore(async (adminDb) => {
    await setDoc(
      doc(adminDb, 'occurrences', occId),
      occurrencePayload({id: occId}),
    );
  });

  await assertFails(
    updateDoc(doc(dbFor(MEMBER_RA), 'occurrences', occId), {
      title: 'Tentativa indevida',
      updated_at: now(),
    }),
  );

  await seedFirestore(async (adminDb) => {
    await setDoc(
      doc(adminDb, 'occurrences', occId),
      occurrencePayload({
        id: occId,
        accepted: [PRIMARY_RA, MEMBER_RA],
        pending: [],
      }),
    );
  });

  await assertSucceeds(
    updateDoc(doc(dbFor(MEMBER_RA), 'occurrences', occId), {
      title: 'Edicao colaborativa autorizada',
      updated_at: now(),
    }),
  );
});

test('ocorrencia finalizada nao aceita edicao nem novo evento', async () => {
  const occId = 'occ-finalized';

  await seedFirestore(async (adminDb) => {
    await setDoc(
      doc(adminDb, 'occurrences', occId),
      occurrencePayload({
        id: occId,
        status: 'finalized',
        accepted: [PRIMARY_RA, MEMBER_RA],
        pending: [],
      }),
    );
  });

  await assertFails(
    updateDoc(doc(dbFor(PRIMARY_RA), 'occurrences', occId), {
      title: 'Edicao indevida apos selo',
      updated_at: now(),
    }),
  );

  await assertFails(
    setDoc(doc(dbFor(PRIMARY_RA), 'occurrences', occId, 'events', 'evt-1'), {
      title: 'Evento indevido',
      audit_trail: audit(),
    }),
  );
});

test('assinatura por usuario fora da equipe e recusada', async () => {
  const occId = 'occ-signature';

  await seedFirestore(async (adminDb) => {
    await setDoc(
      doc(adminDb, 'occurrences', occId),
      occurrencePayload({
        id: occId,
        status: 'awaiting_signatures',
        accepted: [PRIMARY_RA, MEMBER_RA],
        pending: [],
      }),
    );
  });

  await assertFails(
    setDoc(doc(dbFor(OUTSIDER_RA), 'occurrences', occId, 'signatures', MEMBER_RA), {
      handler_id: MEMBER_RA,
      status: 'signed',
      signature_round: 1,
      signed_at: now(),
    }),
  );

  await assertSucceeds(
    setDoc(doc(dbFor(MEMBER_RA), 'occurrences', occId, 'signatures', MEMBER_RA), {
      handler_id: MEMBER_RA,
      status: 'signed',
      signature_round: 1,
      signed_at: now(),
    }),
  );
});

test('aditamento so e aceito para relator ou integrante assinado', async () => {
  const occId = 'occ-amendment';

  await seedFirestore(async (adminDb) => {
    await setDoc(
      doc(adminDb, 'occurrences', occId),
      occurrencePayload({
        id: occId,
        status: 'finalized',
        accepted: [PRIMARY_RA, MEMBER_RA],
        pending: [],
        signed: [],
      }),
    );
  });

  await assertFails(
    setDoc(
      doc(dbFor(MEMBER_RA), 'occurrences', occId, 'amendments', 'am-unsigned'),
      amendmentPayload(MEMBER_RA),
    ),
  );

  await assertSucceeds(
    setDoc(
      doc(dbFor(PRIMARY_RA), 'occurrences', occId, 'amendments', 'am-primary'),
      amendmentPayload(PRIMARY_RA),
    ),
  );

  await seedFirestore(async (adminDb) => {
    await setDoc(
      doc(adminDb, 'occurrences', occId),
      occurrencePayload({
        id: occId,
        status: 'finalized',
        accepted: [PRIMARY_RA, MEMBER_RA],
        pending: [],
        signed: [MEMBER_RA],
      }),
    );
  });

  await assertSucceeds(
    setDoc(
      doc(dbFor(MEMBER_RA), 'occurrences', occId, 'amendments', 'am-signed'),
      amendmentPayload(MEMBER_RA),
    ),
  );
});

test('documento do cao sem audit_trail e recusado', async () => {
  const db = dbFor(PRIMARY_RA);

  await assertFails(
    setDoc(doc(db, 'documentos/doc-sem-auditoria'), documentPayload({withAudit: false})),
  );

  await assertSucceeds(
    setDoc(doc(db, 'documentos/doc-com-auditoria'), documentPayload()),
  );
});

test('generated_pdfs nao aceita escrita direta do client', async () => {
  await assertFails(
    setDoc(doc(dbFor(PRIMARY_RA), 'generated_pdfs/pdf-1'), {
      url: 'https://example.invalid/pdf.pdf',
      created_at: now(),
    }),
  );
});

test('auditLogs nao aceita ator adulterado', async () => {
  const db = dbFor(PRIMARY_RA);

  await assertFails(
    setDoc(doc(db, 'auditLogs/log-spoof'), auditLogPayload({spoof: true})),
  );

  await assertSucceeds(
    setDoc(doc(db, 'auditLogs/log-valido'), auditLogPayload()),
  );
});

test('notificacao so pode ser lida e marcada pelo proprio destinatario', async () => {
  const occId = 'occ-notification';

  await seedFirestore(async (adminDb) => {
    await setDoc(
      doc(adminDb, 'occurrences', occId),
      occurrencePayload({
        id: occId,
        accepted: [PRIMARY_RA, MEMBER_RA],
        pending: [],
      }),
    );
  });

  await assertSucceeds(
    setDoc(
      doc(dbFor(PRIMARY_RA), 'notifications', MEMBER_RA, 'items', 'n1'),
      notificationPayload(occId),
    ),
  );

  await assertFails(
    updateDoc(doc(dbFor(PRIMARY_RA), 'notifications', MEMBER_RA, 'items', 'n1'), {
      read_at: now(),
    }),
  );

  await assertSucceeds(
    updateDoc(doc(dbFor(MEMBER_RA), 'notifications', MEMBER_RA, 'items', 'n1'), {
      read_at: now(),
    }),
  );
});

test('notificacao permite arquivar avisos mas bloqueia pendencia aberta', async () => {
  const occId = 'occ-notification-archive';

  await seedFirestore(async (adminDb) => {
    await setDoc(
      doc(adminDb, 'occurrences', occId),
      occurrencePayload({
        id: occId,
        accepted: [PRIMARY_RA, MEMBER_RA],
        pending: [],
      }),
    );
    await setDoc(
      doc(adminDb, 'notifications', MEMBER_RA, 'items', 'notice'),
      notificationPayload(occId, {
        type: 'signature_completed',
        action_required: false,
        resolved_at: now(),
      }),
    );
    await setDoc(
      doc(adminDb, 'notifications', MEMBER_RA, 'items', 'open-action'),
      notificationPayload(occId, {
        type: 'signature_requested',
        action_required: true,
        resolved_at: null,
      }),
    );
  });

  await assertSucceeds(
    updateDoc(doc(dbFor(MEMBER_RA), 'notifications', MEMBER_RA, 'items', 'notice'), {
      archived_at: now(),
    }),
  );

  await assertFails(
    updateDoc(
      doc(dbFor(PRIMARY_RA), 'notifications', MEMBER_RA, 'items', 'notice'),
      {
        archived_at: now(),
      },
    ),
  );

  await assertFails(
    updateDoc(
      doc(dbFor(MEMBER_RA), 'notifications', MEMBER_RA, 'items', 'open-action'),
      {
        archived_at: now(),
      },
    ),
  );
});

test('access_profiles tem leitura web autenticada e escrita direta bloqueada', async () => {
  await seedFirestore(async (adminDb) => {
    await setDoc(doc(adminDb, 'access_profiles', 'condutor'), {
      id: 'condutor',
      name: 'Condutor',
      status: 'active',
      permissions: {
        dashboard: {view: true},
      },
      seed_version: 1,
    });
  });

  await assertSucceeds(
    getDoc(doc(dbFor(PRIMARY_RA), 'access_profiles', 'condutor')),
  );

  await assertFails(
    getDoc(doc(dbFor(PRIMARY_RA, {web_access: false}), 'access_profiles', 'condutor')),
  );

  await assertFails(
    setDoc(doc(dbFor(PRIMARY_RA), 'access_profiles', 'novo'), {
      id: 'novo',
      name: 'Novo perfil',
      status: 'active',
      permissions: {},
      seed_version: 1,
      audit_trail: audit(),
    }),
  );

  await assertFails(
    updateDoc(doc(dbFor(PRIMARY_RA), 'access_profiles', 'condutor'), {
      name: 'Condutor alterado',
      audit_trail: audit(),
    }),
  );
});

test('Storage permite upload valido mas recusa exclusao de evidencia', async () => {
  const storage = storageFor(PRIMARY_RA);
  const imageRef = ref(storage, 'occurrences/occ-storage/events/foto.jpg');
  const invalidRef = ref(storage, 'occurrences/occ-storage/events/notas.txt');

  await assertSucceeds(
    uploadString(imageRef, 'imagem-fake', 'raw', {
      contentType: 'image/jpeg',
    }),
  );

  await assertFails(
    uploadString(invalidRef, 'texto-fake', 'raw', {
      contentType: 'text/plain',
    }),
  );

  await assertFails(deleteObject(imageRef));
});

try {
  for (const {name, fn} of tests) {
    await clearAll();
    await fn();
    console.log(`ok - ${name}`);
  }

  assert.equal(tests.length, 25);
  console.log(`\n${tests.length} testes de rules concluidos com sucesso.`);
} finally {
  await testEnv.cleanup();
}
