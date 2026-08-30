/**
 * HEALTH-V1-OP-AUTH — Gate D: prova de bypass e proveniência do dogId operacional.
 *
 * INVARIANTE SOB TESTE (definida pelo usuário):
 *   Nenhum fluxo client-side pode INTRODUZIR ou SUBSTITUIR um `service_dog_id`
 *   não-vazio sem passar pelo Backend e pelo guard canônico de
 *   `operational_restrictions`. Fluxos que apenas MANTÊM ou REMOVEM o dogId
 *   podem continuar client-side.
 *
 * Matriz de proveniência:
 *   dog atual -> dog diferente   BLOQUEAR client-side
 *   sem dog   -> dog novo        BLOQUEAR client-side
 *   dog atual -> mesmo dog       permitir (fluxo legítimo, sem nova decisão)
 *   dog atual -> null/vazio      permitir (remoção legítima: endShift/leaveVehicle)
 *
 * Estes testes avaliam o `firestore.rules` REAL via @firebase/rules-unit-testing.
 * Não simulam hasOnly() em Dart — uma simulação não pode provar que o arquivo
 * publicado fecha o bypass.
 *
 * Execução (a partir de tools/rules_tests):
 *   npm run test:shift-dog-provenance
 */
import assert from 'node:assert/strict';
import {pathToFileURL} from 'node:url';
import {
  assertFails,
  assertSucceeds,
  initializeTestEnvironment,
} from '@firebase/rules-unit-testing';
import {
  deleteField,
  doc,
  setDoc,
  updateDoc,
  Timestamp,
} from 'firebase/firestore';

const PROJECT_ID = process.env.GCLOUD_PROJECT || 'canil-gcm';

const PRIMARY_RA = '691755';
const CREW_MATE_RA = '424242';
const DOG_ASSIGNED = 'dog-assigned';
const DOG_OTHER = 'dog-other';
const VEHICLE_ID = 'VTR-OP-AUTH';

const testEnv = await initializeTestEnvironment({projectId: PROJECT_ID});

const tests = [];
function test(name, fn) {
  tests.push({name, fn});
}

function auth(ra, claims = {}) {
  if (ra === null) return testEnv.unauthenticatedContext();
  return testEnv.authenticatedContext(`uid-${ra}`, {
    email: `${ra}@gcm.com.br`,
    ra,
    access_scope: 'global',
    ...claims,
  });
}

function dbFor(ra, claims = {}) {
  return auth(ra, claims).firestore();
}

function now() {
  return Timestamp.fromDate(new Date('2026-08-13T12:00:00.000Z'));
}

async function seedFirestore(seedFn) {
  await testEnv.withSecurityRulesDisabled(async (context) => {
    await seedFn(context.firestore());
  });
}

/**
 * Estado inicial: turno ativo do PRIMARY_RA com DOG_ASSIGNED, guarnição aberta.
 * Semeado com Rules desabilitadas — representa o estado legítimo produzido pelo
 * backend autoritativo.
 */
async function seedActiveShiftWithDog({dogId = DOG_ASSIGNED} = {}) {
  await seedFirestore(async (db) => {
    await setDoc(doc(db, 'dogs', DOG_ASSIGNED), {
      name: 'Bono',
      handler_ra: PRIMARY_RA,
      conductorRa: PRIMARY_RA,
      status: 'active',
    });
    await setDoc(doc(db, 'dogs', DOG_OTHER), {
      name: 'Zeus',
      handler_ra: PRIMARY_RA,
      conductorRa: PRIMARY_RA,
      status: 'active',
    });
    await setDoc(doc(db, 'active_shifts', PRIMARY_RA), {
      shiftId: 'shift-1',
      handlerId: PRIMARY_RA,
      auth_uid: `uid-${PRIMARY_RA}`,
      handler_email: `${PRIMARY_RA}@gcm.com.br`,
      dogId,
      service_dog_id: dogId,
      status: 'active',
      startedAt: now(),
      updatedAt: now(),
      vehicle_id: VEHICLE_ID,
      vehicle_crew_id: VEHICLE_ID,
      crew_id: VEHICLE_ID,
      crew_role: 'motorista',
      crew_status: 'active',
    });
    await setDoc(doc(db, 'active_shifts', CREW_MATE_RA), {
      shiftId: 'shift-2',
      handlerId: CREW_MATE_RA,
      auth_uid: `uid-${CREW_MATE_RA}`,
      handler_email: `${CREW_MATE_RA}@gcm.com.br`,
      dogId,
      service_dog_id: dogId,
      status: 'active',
      startedAt: now(),
      updatedAt: now(),
      vehicle_id: VEHICLE_ID,
      vehicle_crew_id: VEHICLE_ID,
    });
    await setDoc(doc(db, 'shift_logs', 'shift-1'), {
      id: 'shift-1',
      handlerId: PRIMARY_RA,
      initialDogId: dogId,
      currentDogId: dogId,
      service_dog_id: dogId,
      status: 'active',
      startedAt: now(),
      updatedAt: now(),
    });
    await setDoc(doc(db, 'vehicle_crews', VEHICLE_ID), {
      id: VEHICLE_ID,
      vehicle_id: VEHICLE_ID,
      crew_size: 3,
      service_dog_id: dogId,
      titular_handler_id: PRIMARY_RA,
      active: true,
      created_at: now(),
      updated_at: now(),
    });
    await setDoc(
      doc(db, 'vehicle_crews', VEHICLE_ID, 'members', PRIMARY_RA),
      {
        handler_id: PRIMARY_RA,
        auth_uid: `uid-${PRIMARY_RA}`,
        handler_email: `${PRIMARY_RA}@gcm.com.br`,
        name: 'Condutor',
        role: 'motorista',
        status: 'active',
        dog_id: dogId,
        joined_at: now(),
      },
    );
  });
}

// ─────────────────────────────────────────────────────────────────────────────
// BYPASS: substituir o K9 operacional por write direto
// ─────────────────────────────────────────────────────────────────────────────

test('D-01 cliente NÃO substitui service_dog_id em active_shifts', async () => {
  await seedActiveShiftWithDog();
  const db = dbFor(PRIMARY_RA);
  // Exatamente o que switchDog fazia client-side antes da migração.
  await assertFails(
    updateDoc(doc(db, 'active_shifts', PRIMARY_RA), {
      dogId: DOG_OTHER,
      service_dog_id: DOG_OTHER,
      lastDogSwitchAt: now(),
      updatedAt: now(),
    }),
  );
});

test('D-02 cliente NÃO introduz K9 em turno que estava sem cão', async () => {
  await seedActiveShiftWithDog({dogId: ''});
  const db = dbFor(PRIMARY_RA);
  await assertFails(
    updateDoc(doc(db, 'active_shifts', PRIMARY_RA), {
      dogId: DOG_OTHER,
      service_dog_id: DOG_OTHER,
      updatedAt: now(),
    }),
  );
});

test('D-03 cliente NÃO substitui service_dog_id na guarnição', async () => {
  await seedActiveShiftWithDog();
  const db = dbFor(PRIMARY_RA);
  // Este é o buraco que transferToVehicle exploraria: dogId arbitrário do
  // cliente chegando a vehicle_crews.service_dog_id.
  await assertFails(
    updateDoc(doc(db, 'vehicle_crews', VEHICLE_ID), {
      service_dog_id: DOG_OTHER,
      updated_at: now(),
    }),
  );
});

test('D-04 cliente NÃO substitui dog_id no membro da guarnição', async () => {
  await seedActiveShiftWithDog();
  const db = dbFor(PRIMARY_RA);
  await assertFails(
    updateDoc(doc(db, 'vehicle_crews', VEHICLE_ID, 'members', PRIMARY_RA), {
      dog_id: DOG_OTHER,
      updated_at: now(),
    }),
  );
});

test('D-05 cliente NÃO substitui service_dog_id em shift_logs', async () => {
  await seedActiveShiftWithDog();
  const db = dbFor(PRIMARY_RA);
  await assertFails(
    updateDoc(doc(db, 'shift_logs', 'shift-1'), {
      currentDogId: DOG_OTHER,
      service_dog_id: DOG_OTHER,
      updatedAt: now(),
    }),
  );
});

test('D-06 cliente NÃO cria turno novo já com K9 (contorno do startShift)', async () => {
  await seedFirestore(async (db) => {
    await setDoc(doc(db, 'dogs', DOG_OTHER), {
      name: 'Zeus',
      handler_ra: PRIMARY_RA,
      conductorRa: PRIMARY_RA,
      status: 'active',
    });
  });
  const db = dbFor(PRIMARY_RA);
  // Criar active_shifts direto com dogId preenchido burlaria o guard.
  await assertFails(
    setDoc(doc(db, 'active_shifts', PRIMARY_RA), {
      shiftId: 'shift-forged',
      handlerId: PRIMARY_RA,
      auth_uid: `uid-${PRIMARY_RA}`,
      handler_email: `${PRIMARY_RA}@gcm.com.br`,
      dogId: DOG_OTHER,
      service_dog_id: DOG_OTHER,
      status: 'active',
      startedAt: now(),
      updatedAt: now(),
    }),
  );
});

test('D-07 cliente NÃO cria guarnição já com K9 embarcado', async () => {
  await seedActiveShiftWithDog({dogId: ''});
  const db = dbFor(PRIMARY_RA);
  await assertFails(
    setDoc(doc(db, 'vehicle_crews', 'VTR-NOVA'), {
      id: 'VTR-NOVA',
      vehicle_id: 'VTR-NOVA',
      crew_size: 3,
      service_dog_id: DOG_OTHER,
      titular_handler_id: PRIMARY_RA,
      active: true,
      created_at: now(),
      updated_at: now(),
    }),
  );
});

test('D-08 cliente NÃO contamina o crew que respondVehicleCrewInvitation lê', async () => {
  // CADEIA DE PROVENIÊNCIA INDIRETA: respondVehicleCrewInvitation deriva o
  // dogId de vehicle_crews.service_dog_id. Se o cliente pudesse adulterar essa
  // fonte, o backend "confiável" propagaria um dogId injetado — bypass indireto.
  await seedActiveShiftWithDog();
  const db = dbFor(CREW_MATE_RA);
  await assertFails(
    updateDoc(doc(db, 'vehicle_crews', VEHICLE_ID), {
      service_dog_id: DOG_OTHER,
      updated_at: now(),
    }),
  );
});

// ─────────────────────────────────────────────────────────────────────────────
// REMOÇÕES E MANUTENÇÕES LEGÍTIMAS — não podem quebrar
// ─────────────────────────────────────────────────────────────────────────────

test('D-10 endShift: encerrar turno removendo o K9 continua permitido', async () => {
  await seedActiveShiftWithDog();
  const db = dbFor(PRIMARY_RA);
  await assertSucceeds(
    updateDoc(doc(db, 'active_shifts', PRIMARY_RA), {
      status: 'ended',
      endedAt: now(),
      service_dog_id: deleteField(),
      updatedAt: now(),
    }),
  );
});

test('D-11 leaveVehicle: liberar posto mantendo o mesmo K9 é permitido', async () => {
  await seedActiveShiftWithDog();
  const db = dbFor(PRIMARY_RA);
  // Mantém dogId; muda só o vínculo de viatura.
  await assertSucceeds(
    updateDoc(doc(db, 'active_shifts', PRIMARY_RA), {
      vehicle_id: null,
      vehicle_crew_id: null,
      crew_id: null,
      crew_role: null,
      crew_status: null,
      updatedAt: now(),
    }),
  );
});

test('D-12 update que NÃO toca o K9 continua permitido', async () => {
  await seedActiveShiftWithDog();
  const db = dbFor(PRIMARY_RA);
  await assertSucceeds(
    updateDoc(doc(db, 'active_shifts', PRIMARY_RA), {
      updatedAt: now(),
    }),
  );
});

test('D-13 reescrever o MESMO K9 é permitido (idempotência de fluxo)', async () => {
  await seedActiveShiftWithDog();
  const db = dbFor(PRIMARY_RA);
  // dog atual -> mesmo dog: não é nova decisão clínica.
  await assertSucceeds(
    updateDoc(doc(db, 'active_shifts', PRIMARY_RA), {
      dogId: DOG_ASSIGNED,
      service_dog_id: DOG_ASSIGNED,
      updatedAt: now(),
    }),
  );
});

test('D-14 encerrar membro da guarnição mantendo o mesmo dog_id é permitido', async () => {
  await seedActiveShiftWithDog();
  const db = dbFor(PRIMARY_RA);
  await assertSucceeds(
    updateDoc(doc(db, 'vehicle_crews', VEHICLE_ID, 'members', PRIMARY_RA), {
      status: 'ended',
      left_at: now(),
      dog_id: DOG_ASSIGNED,
      updated_at: now(),
    }),
  );
});

// ─────────────────────────────────────────────────────────────────────────────
// REMOÇÃO NO MEMBER DOC — a lacuna que deixou a suíte verde sobre um blocker
//
// D-11 exercita `active_shifts` e D-14 preserva um `dog_id` não-vazio, então
// nenhum dos dois cobria a SAÍDA da guarnição limpando o campo. O `leaveVehicle`
// real escrevia `dog_id: null` e era NEGADO em produção com a suíte verde.
//
// A causa é sutil: `data.get('dog_id', '')` só cai no default quando a chave
// está AUSENTE. Chave presente com `null` devolve `null`, que não é igual a ''
// nem ao valor anterior. Por isso os três casos abaixo são distintos e nenhum
// substitui o outro — remover, esvaziar e "presente como null" são payloads
// diferentes para a mesma intenção.
// ─────────────────────────────────────────────────────────────────────────────

test('D-09a saída da guarnição removendo dog_id (FieldValue.delete) é permitida', async () => {
  await seedActiveShiftWithDog();
  const db = dbFor(PRIMARY_RA);
  // Payload REAL do leaveVehicle após a correção do blocker.
  await assertSucceeds(
    updateDoc(doc(db, 'vehicle_crews', VEHICLE_ID, 'members', PRIMARY_RA), {
      status: 'ended',
      left_at: now(),
      dog_id: deleteField(),
      updated_at: now(),
    }),
  );
});

test('D-09b saída da guarnição com dog_id vazio é permitida', async () => {
  await seedActiveShiftWithDog();
  const db = dbFor(PRIMARY_RA);
  await assertSucceeds(
    updateDoc(doc(db, 'vehicle_crews', VEHICLE_ID, 'members', PRIMARY_RA), {
      status: 'ended',
      left_at: now(),
      dog_id: '',
      updated_at: now(),
    }),
  );
});

test('D-09c saída da guarnição com dog_id: null é NEGADA (regressão do blocker)', async () => {
  await seedActiveShiftWithDog();
  const db = dbFor(PRIMARY_RA);
  // Guarda de regressão: este era o payload do leaveVehicle e ele é negado.
  // Se algum dia passar a ser permitido, `null` deixou de ser distinguível de
  // remoção e a comparação de proveniência afrouxou — investigar a Rule antes
  // de "consertar" este teste.
  await assertFails(
    updateDoc(doc(db, 'vehicle_crews', VEHICLE_ID, 'members', PRIMARY_RA), {
      status: 'ended',
      left_at: now(),
      dog_id: null,
      updated_at: now(),
    }),
  );
});

test('D-09d remoção NÃO é brecha: sair substituindo por outro K9 continua negado', async () => {
  await seedActiveShiftWithDog();
  const db = dbFor(PRIMARY_RA);
  // O que a correção NÃO pode ter aberto: usar a saída como veículo para
  // introduzir outro cão. Sem este caso, permitir a remoção seria indistinguível
  // de permitir qualquer escrita no campo durante a saída.
  await assertFails(
    updateDoc(doc(db, 'vehicle_crews', VEHICLE_ID, 'members', PRIMARY_RA), {
      status: 'ended',
      left_at: now(),
      dog_id: DOG_OTHER,
      updated_at: now(),
    }),
  );
});

test('D-15 fechar guarnição removendo o K9 é permitido', async () => {
  await seedActiveShiftWithDog();
  const db = dbFor(PRIMARY_RA);
  await assertSucceeds(
    updateDoc(doc(db, 'vehicle_crews', VEHICLE_ID), {
      active: false,
      ended_at: now(),
      updated_at: now(),
    }),
  );
});

test('D-16 turno SEM K9 continua podendo ser criado pelo cliente', async () => {
  const db = dbFor(PRIMARY_RA);
  // Classificação D: não introduz associação de cão.
  await assertSucceeds(
    setDoc(doc(db, 'active_shifts', PRIMARY_RA), {
      shiftId: 'shift-nodog',
      handlerId: PRIMARY_RA,
      auth_uid: `uid-${PRIMARY_RA}`,
      handler_email: `${PRIMARY_RA}@gcm.com.br`,
      dogId: '',
      service_dog_id: '',
      status: 'active',
      startedAt: now(),
      updatedAt: now(),
    }),
  );
});

async function run() {
  let passed = 0;
  let failed = 0;
  const failures = [];

  for (const {name, fn} of tests) {
    try {
      await testEnv.clearFirestore();
      await fn();
      console.log(`ok - ${name}`);
      passed++;
    } catch (error) {
      console.error(`FAIL - ${name}`);
      console.error(`  ${error.message}`);
      failures.push({name, error});
      failed++;
    }
  }

  console.log(`\nPassed: ${passed}`);
  console.log(`Failed: ${failed}`);

  if (failed > 0) {
    console.log('\nFailures:');
    failures.forEach(({name, error}) => {
      console.log(`  ${name}: ${error.message}`);
    });
    await testEnv.cleanup();
    process.exit(1);
  }

  console.log('\nshift_dog_provenance_rules_tests: all passed');
  await testEnv.cleanup();
}

// Guard de entrypoint robusto em Windows e POSIX (ver nota no harness de
// readiness: comparação naive com `file://${argv[1]}` produz falso verde).
if (import.meta.url === pathToFileURL(process.argv[1]).href) {
  run().catch((error) => {
    console.error('Test runner failed:', error);
    process.exit(1);
  });
}

export {tests, run, testEnv};
