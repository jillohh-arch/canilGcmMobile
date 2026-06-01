import assert from 'node:assert/strict';

import {
  assertFails,
  assertSucceeds,
  initializeTestEnvironment,
} from '@firebase/rules-unit-testing';
import {
  doc,
  setDoc,
  updateDoc,
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

function auth(ra) {
  return testEnv.authenticatedContext(`uid-${ra}`, {
    email: `${ra}@gcm.com.br`,
  });
}

function dbFor(ra) {
  return auth(ra).firestore();
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

function notificationPayload(occurrenceId = 'occ-notification') {
  return {
    type: 'signature_requested',
    occurrence_id: occurrenceId,
    occurrence_title: 'Averiguacao de atitude suspeita',
    created_at: now(),
    read_at: null,
    target_screen: 'occurrence_review',
    action_required: true,
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

  assert.equal(tests.length, 12);
  console.log(`\n${tests.length} testes de rules concluidos com sucesso.`);
} finally {
  await testEnv.cleanup();
}
