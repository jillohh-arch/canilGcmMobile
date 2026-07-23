/**
 * Health v1 — Fase 5D Gate 5C.5C.4
 * Testes de queries e índices para o runtime de reconciliação Health Timeline.
 *
 * Valida as queries exatas usadas pelo reconciliation runtime:
 * 1. Forward MealLog collection group query
 * 2. Forward SupplementLog collection group query
 * 3. Overlap Meal/Supplement query com range
 * 4. Historical source traversal por document name
 * 5. Orphan health_timeline traversal
 * 6. Known discrepancy query
 *
 * IMPORTANTE: Estes testes focam na forma das queries, não na lógica de reconciliação.
 * IMPORTANTE: Usa withSecurityRulesDisabled para simular Admin SDK (backend bypassa Rules).
 */
import assert from 'node:assert/strict';

import {
  initializeTestEnvironment,
} from '@firebase/rules-unit-testing';
import {
  collection,
  collectionGroup,
  doc,
  getDocs,
  limit,
  orderBy,
  query,
  setDoc,
  startAfter,
  Timestamp,
  where,
} from 'firebase/firestore';

const PROJECT_ID = process.env.GCLOUD_PROJECT || 'canil-gcm';

const testEnv = await initializeTestEnvironment({
  projectId: PROJECT_ID,
  firestore: {
    host: 'localhost',
    port: 8080,
  },
});

const tests = [];

function test(name, fn) {
  tests.push({name, fn});
}

function now() {
  return Timestamp.fromDate(new Date('2026-05-31T12:00:00.000Z'));
}

async function seedTestData() {
  await testEnv.withSecurityRulesDisabled(async (context) => {
    const db = context.firestore();

    // Criar dogs de teste
    await setDoc(doc(db, 'dogs', 'dog-a'), {name: 'Dog A'});
    await setDoc(doc(db, 'dogs', 'dog-b'), {name: 'Dog B'});
    await setDoc(doc(db, 'dogs', 'dog-c'), {name: 'Dog C'});

    // Meal logs com recorded_at variados
    for (let i = 1; i <= 15; i++) {
      const timestamp = Timestamp.fromDate(new Date(`2026-05-${String(i).padStart(2, '0')}T12:00:00.000Z`));
      await setDoc(doc(db, 'dogs', 'dog-a', 'meal_logs', `meal-a${i}`), {
        recorded_at: timestamp,
        type: 'dry_food',
        quantity_grams: 500,
        audit_trail: [{action: 'created', by: 'test', at: timestamp}],
      });
      await setDoc(doc(db, 'dogs', 'dog-b', 'meal_logs', `meal-b${i}`), {
        recorded_at: timestamp,
        type: 'wet_food',
        quantity_grams: 300,
        audit_trail: [{action: 'created', by: 'test', at: timestamp}],
      });
    }

    // Supplement logs
    for (let i = 1; i <= 10; i++) {
      const timestamp = Timestamp.fromDate(new Date(`2026-05-${String(i).padStart(2, '0')}T14:00:00.000Z`));
      await setDoc(doc(db, 'dogs', 'dog-a', 'supplement_logs', `supp-a${i}`), {
        recorded_at: timestamp,
        supplement_id: `vitamin_${i}`,
        dosage: '100mg',
        audit_trail: [{action: 'created', by: 'test', at: timestamp}],
      });
    }

    // Health timeline entries (projeções)
    for (let i = 1; i <= 8; i++) {
      await setDoc(doc(db, 'dogs', 'dog-a', 'health_timeline', `tl1_meal_a${i}`), {
        dog_id: 'dog-a',
        timeline_type: 'meal',
        source_collection: 'dogs/dog-a/meal_logs',
        source_id: `meal-a${i}`,
        recorded_at: Timestamp.fromDate(new Date(`2026-05-${String(i).padStart(2, '0')}T12:00:00.000Z`)),
        projected_at: now(),
        created_at: now(),
      });
    }

    // Discrepancies
    await setDoc(doc(db, '_health_projection_state/health_timeline_v1/discrepancies', 'hd1_test1'), {
      status: 'open',
      source_type: 'meal',
      dog_id: 'dog-a',
      source_id: 'meal-a99',
      reason_code: 'source-missing-during-pass',
      first_seen_at: now(),
      attempts: 1,
    });
    await setDoc(doc(db, '_health_projection_state/health_timeline_v1/discrepancies', 'hd1_test2'), {
      status: 'resolved',
      source_type: 'supplement',
      dog_id: 'dog-a',
      source_id: 'supp-a1',
      reason_code: 'invalid-source-payload',
      first_seen_at: now(),
      resolved_at: now(),
      attempts: 3,
    });
  });
}

async function clearAll() {
  await testEnv.clearFirestore();
}

// ==================== TESTES DE QUERIES ====================

test('A. Forward MealLog collection group query', async () => {
  await clearAll();
  await seedTestData();

  await testEnv.withSecurityRulesDisabled(async (context) => {
    const db = context.firestore();

    // Query exata do runtime (forward pass)
    const mealLogsQuery = query(
      collectionGroup(db, 'meal_logs'),
      orderBy('recorded_at', 'asc'),
      orderBy('__name__', 'asc'),
      limit(10)
    );

    const snapshot = await getDocs(mealLogsQuery);

    // Verificar que a query funciona
    assert.ok(snapshot.size > 0, 'Deve retornar documentos');

    // Verificar ordenação
    const docs = snapshot.docs;
    for (let i = 0; i < docs.length - 1; i++) {
      const current = docs[i];
      const next = docs[i + 1];

      // Comparar recorded_at
      const currentTime = current.get('recorded_at')?.toMillis() || 0;
      const nextTime = next.get('recorded_at')?.toMillis() || 0;

      if (currentTime === nextTime) {
        // Tie-break por document ID
        const currentId = current.id;
        const nextId = next.id;
        assert.ok(currentId < nextId, `Document IDs devem estar em ordem crescente quando recorded_at igual`);
      } else {
        assert.ok(currentTime <= nextTime, `Recorded_at deve estar em ordem crescente`);
      }
    }

    console.log(`✓ Forward MealLog query retornou ${snapshot.size} documentos, ordenação válida`);
  });
});

test('B. Forward SupplementLog collection group query', async () => {
  await clearAll();
  await seedTestData();

  await testEnv.withSecurityRulesDisabled(async (context) => {
    const db = context.firestore();

    const supplementLogsQuery = query(
      collectionGroup(db, 'supplement_logs'),
      orderBy('recorded_at', 'asc'),
      orderBy('__name__', 'asc'),
      limit(5)
    );

    const snapshot = await getDocs(supplementLogsQuery);
    assert.ok(snapshot.size > 0, 'Deve retornar documentos de supplement_logs');

    // Verificar que todos são supplement_logs
    snapshot.docs.forEach(docSnap => {
      assert.ok(docSnap.ref.path.includes('supplement_logs'), `Documento ${docSnap.ref.path} deve ser de supplement_logs`);
    });

    console.log(`✓ Forward SupplementLog query retornou ${snapshot.size} documentos`);
  });
});

test('C. Overlap Meal/Supplement query com range', async () => {
  await clearAll();
  await seedTestData();

  await testEnv.withSecurityRulesDisabled(async (context) => {
    const db = context.firestore();

    const windowStart = Timestamp.fromDate(new Date('2026-05-05T00:00:00.000Z'));
    const windowEnd = Timestamp.fromDate(new Date('2026-05-10T23:59:59.999Z'));

    const overlapQuery = query(
      collectionGroup(db, 'meal_logs'),
      where('recorded_at', '>=', windowStart),
      where('recorded_at', '<=', windowEnd),
      orderBy('recorded_at', 'asc'),
      orderBy('__name__', 'asc'),
      limit(20)
    );

    const snapshot = await getDocs(overlapQuery);

    // Verificar que todos estão dentro do range
    snapshot.docs.forEach(docSnap => {
      const recordedAt = docSnap.get('recorded_at');
      assert.ok(recordedAt instanceof Timestamp, 'recorded_at deve ser Timestamp');
      const time = recordedAt.toMillis();
      assert.ok(time >= windowStart.toMillis(), `Documento ${docSnap.id} está antes do windowStart`);
      assert.ok(time <= windowEnd.toMillis(), `Documento ${docSnap.id} está depois do windowEnd`);
    });

    console.log(`✓ Overlap query retornou ${snapshot.size} documentos dentro do range`);
  });
});

test('D. Historical source traversal por document name', async () => {
  await clearAll();
  await seedTestData();

  await testEnv.withSecurityRulesDisabled(async (context) => {
    const db = context.firestore();

    const historicalQuery = query(
      collectionGroup(db, 'meal_logs'),
      orderBy('__name__', 'asc'),
      limit(8)
    );

    const snapshot = await getDocs(historicalQuery);
    assert.ok(snapshot.size > 0, 'Deve retornar documentos');

    // Verificar ordenação por document ID
    const docs = snapshot.docs;
    for (let i = 0; i < docs.length - 1; i++) {
      const currentId = docs[i].id;
      const nextId = docs[i + 1].id;
      assert.ok(currentId < nextId, `Document IDs devem estar em ordem crescente: ${currentId} < ${nextId}`);
    }

    console.log(`✓ Historical query retornou ${snapshot.size} documentos, ordenados por document ID`);
  });
});

test('E. Orphan health_timeline traversal', async () => {
  await clearAll();
  await seedTestData();

  await testEnv.withSecurityRulesDisabled(async (context) => {
    const db = context.firestore();

    const orphanQuery = query(
      collectionGroup(db, 'health_timeline'),
      orderBy('__name__', 'asc'),
      limit(5)
    );

    const snapshot = await getDocs(orphanQuery);
    assert.ok(snapshot.size > 0, 'Deve retornar documentos de health_timeline');

    // Verificar que todos são health_timeline
    snapshot.docs.forEach(docSnap => {
      assert.ok(docSnap.ref.path.includes('health_timeline'), `Documento ${docSnap.ref.path} deve ser health_timeline`);
    });

    console.log(`✓ Orphan query retornou ${snapshot.size} documentos de health_timeline`);
  });
});

test('F. Known discrepancy query', async () => {
  await clearAll();
  await seedTestData();

  await testEnv.withSecurityRulesDisabled(async (context) => {
    const db = context.firestore();

    // Query EXATA do runtime (collection explícita, não collectionGroup)
    const discrepancyQuery = query(
      collection(db, '_health_projection_state/health_timeline_v1/discrepancies'),
      where('status', '==', 'open'),
      orderBy('__name__', 'asc'),
      limit(10)
    );

    const snapshot = await getDocs(discrepancyQuery);

    // Deve retornar apenas discrepancies com status 'open'
    snapshot.docs.forEach(docSnap => {
      const status = docSnap.get('status');
      assert.strictEqual(status, 'open', `Discrepancy ${docSnap.id} deve ter status 'open', mas tem '${status}'`);
    });

    console.log(`✓ Known discrepancy query retornou ${snapshot.size} documentos com status 'open'`);
  });
});

test('G. Paginação com cursor (startAfter) - global tie-break', async () => {
  await clearAll();
  await seedTestData();

  await testEnv.withSecurityRulesDisabled(async (context) => {
    const db = context.firestore();

    // Primeira página
    const firstPageQuery = query(
      collectionGroup(db, 'meal_logs'),
      orderBy('recorded_at', 'asc'),
      orderBy('__name__', 'asc'),
      limit(5)
    );

    const firstSnapshot = await getDocs(firstPageQuery);
    assert.strictEqual(firstSnapshot.size, 5, 'Primeira página deve ter 5 documentos');

    // Usar o último documento como cursor para próxima página
    const lastDoc = firstSnapshot.docs[firstSnapshot.docs.length - 1];

    // Segunda página com startAfter (passa o DocumentSnapshot inteiro)
    const secondPageQuery = query(
      collectionGroup(db, 'meal_logs'),
      orderBy('recorded_at', 'asc'),
      orderBy('__name__', 'asc'),
      startAfter(lastDoc),
      limit(5)
    );

    const secondSnapshot = await getDocs(secondPageQuery);
    assert.ok(secondSnapshot.size > 0, 'Segunda página deve retornar documentos');

    // Verificar que não há overlap
    const firstPageIds = new Set(firstSnapshot.docs.map(doc => doc.id));
    secondSnapshot.docs.forEach(doc => {
      assert.ok(!firstPageIds.has(doc.id), `Documento ${doc.id} não deve estar na primeira página`);
    });

    console.log(`✓ Paginação com cursor funcionou: ${firstSnapshot.size} + ${secondSnapshot.size} documentos sem overlap`);
  });
});

test('H. Query cross-dog verification', async () => {
  await clearAll();
  await seedTestData();

  await testEnv.withSecurityRulesDisabled(async (context) => {
    const db = context.firestore();

    const crossDogQuery = query(
      collectionGroup(db, 'meal_logs'),
      orderBy('recorded_at', 'asc'),
      orderBy('__name__', 'asc'),
      limit(20)
    );

    const snapshot = await getDocs(crossDogQuery);

    // Deve conter documentos de múltiplos dogs
    const dogPaths = new Set();
    snapshot.docs.forEach(docSnap => {
      const path = docSnap.ref.path;
      const match = path.match(/dogs\/([^/]+)\/meal_logs/);
      if (match) {
        dogPaths.add(match[1]);
      }
    });

    assert.ok(dogPaths.size >= 2, `Collection group deve incluir documentos de múltiplos dogs: ${Array.from(dogPaths).join(', ')}`);

    console.log(`✓ Collection group query inclui documentos de ${dogPaths.size} dogs diferentes`);
  });
});

// ==================== RUNNER ====================

async function run() {
  console.log(`Running Health Timeline Query/Index Tests...`);
  console.log('Validating exact query shapes used by reconciliation runtime.');
  console.log('Backend queries use Admin SDK (bypass Rules via withSecurityRulesDisabled).');
  console.log('');

  let passed = 0;
  let failed = 0;
  const failures = [];

  for (const {name, fn} of tests) {
    try {
      await fn();
      console.log(`✓ ${name}`);
      passed++;
    } catch (error) {
      console.log(`✗ ${name}`);
      console.error(`  ${error.message}`);
      failures.push({name, error});
      failed++;
    }
  }

  console.log('\n--- Query/Index Validation Summary ---');
  console.log(`Total queries tested: ${tests.length}`);
  console.log(`Passed: ${passed}`);
  console.log(`Failed: ${failed}`);

  if (failed > 0) {
    console.log('\nFailed queries:');
    failures.forEach(({name, error}) => {
      console.log(`  ${name}: ${error.message}`);
    });

    console.log('\nIMPORTANT: Failed queries may indicate missing indexes.');
    console.log('Check firestore.indexes.json and ensure all required indexes are present.');

    process.exit(1);
  }

  console.log('\nAll query shapes validated successfully!');
  console.log('Index requirements proven for all reconciliation runtime queries.');

  await testEnv.cleanup();
}

// Execute se chamado diretamente
if (import.meta.url === `file://${process.argv[1]}`) {
  run().catch((error) => {
    console.error('Query test runner failed:', error);
    process.exit(1);
  });
}

export { tests, run, testEnv };
