/**
 * Gate 5C.5C.4 — Prova física de requisitos de índices contra Cloud Firestore REAL.
 *
 * Usa Admin SDK para simular comportamento backend (bypassa Rules).
 * READ-ONLY: limit(1) em todas as queries, nenhuma escrita.
 *
 * Executar:
 *   node test_real_firestore_indexes_admin.mjs
 */
import { initializeApp, cert } from 'firebase-admin/app';
import { getFirestore, Timestamp, FieldPath } from 'firebase-admin/firestore';

// Usar Application Default Credentials (gcloud auth application-default login)
// ou Service Account Key via GOOGLE_APPLICATION_CREDENTIALS
try {
  initializeApp({
    projectId: 'canil-gcm'
  });
} catch (error) {
  if (error.code !== 'app/duplicate-app') {
    throw error;
  }
}

const db = getFirestore();

console.log('='.repeat(60));
console.log('Gate 5C.5C.4 — Physical Index Proof');
console.log('Testing against REAL Cloud Firestore: canil-gcm');
console.log('Using Admin SDK (bypasses Rules, simulates backend)');
console.log('All queries use limit(1) for minimal read cost.');
console.log('READ-ONLY: Zero writes to production.');
console.log('='.repeat(60));
console.log('');

async function testQuery(name, queryFn) {
  try {
    const q = queryFn();
    const snapshot = await q.get();
    console.log(`✓ ${name}`);
    console.log(`  Result: SUCCESS (${snapshot.size} docs, no missing index error)`);
    return { name, result: 'SUCCESS', required: false, docCount: snapshot.size };
  } catch (error) {
    if (error.code === 9 && error.message.includes('index')) {
      // gRPC error code 9 = FAILED_PRECONDITION (missing index)
      console.log(`✗ ${name}`);
      console.log(`  Result: MISSING_INDEX`);
      console.log(`  Error: ${error.message.substring(0, 400)}`);
      return { name, result: 'MISSING_INDEX', required: true, error: error.message };
    }
    console.log(`✗ ${name}`);
    console.log(`  Result: ERROR (code ${error.code})`);
    console.log(`  ${error.message.substring(0, 200)}`);
    return { name, result: 'ERROR', required: false, error: error.message };
  }
}

const results = [];

console.log('Query A: meal_logs COLLECTION_GROUP forward pass');
console.log('  Shape: collectionGroup("meal_logs").orderBy("recorded_at", "asc").orderBy("__name__", "asc")');
results.push(await testQuery('A. meal_logs forward', () =>
  db.collectionGroup('meal_logs')
    .orderBy('recorded_at', 'asc')
    .orderBy(FieldPath.documentId(), 'asc')
    .limit(1)
));
console.log('');

console.log('Query B: supplement_logs COLLECTION_GROUP forward pass');
console.log('  Shape: collectionGroup("supplement_logs").orderBy("recorded_at", "asc").orderBy("__name__", "asc")');
results.push(await testQuery('B. supplement_logs forward', () =>
  db.collectionGroup('supplement_logs')
    .orderBy('recorded_at', 'asc')
    .orderBy(FieldPath.documentId(), 'asc')
    .limit(1)
));
console.log('');

console.log('Query C: meal_logs COLLECTION_GROUP overlap (range + order)');
console.log('  Shape: collectionGroup("meal_logs").where("recorded_at", ">=", ...).where("recorded_at", "<=", ...).orderBy("recorded_at").orderBy("__name__")');
const windowStart = Timestamp.fromDate(new Date('2026-01-01'));
const windowEnd = Timestamp.fromDate(new Date('2026-12-31'));
results.push(await testQuery('C. meal_logs overlap', () =>
  db.collectionGroup('meal_logs')
    .where('recorded_at', '>=', windowStart)
    .where('recorded_at', '<=', windowEnd)
    .orderBy('recorded_at', 'asc')
    .orderBy(FieldPath.documentId(), 'asc')
    .limit(1)
));
console.log('');

console.log('Query D: meal_logs COLLECTION_GROUP historical (orderBy __name__ only)');
console.log('  Shape: collectionGroup("meal_logs").orderBy("__name__", "asc")');
results.push(await testQuery('D. meal_logs historical', () =>
  db.collectionGroup('meal_logs')
    .orderBy(FieldPath.documentId(), 'asc')
    .limit(1)
));
console.log('');

console.log('Query E: health_timeline COLLECTION_GROUP orphan pass');
console.log('  Shape: collectionGroup("health_timeline").orderBy("__name__", "asc")');
results.push(await testQuery('E. health_timeline orphan', () =>
  db.collectionGroup('health_timeline')
    .orderBy(FieldPath.documentId(), 'asc')
    .limit(1)
));
console.log('');

console.log('Query F: discrepancies query (COLLECTION explicit path, not collection group)');
console.log('  Shape: collection("_health_projection_state/health_timeline_v1/discrepancies").where("status", "==", "open").orderBy("__name__")');
results.push(await testQuery('F. discrepancies', () =>
  db.collection('_health_projection_state/health_timeline_v1/discrepancies')
    .where('status', '==', 'open')
    .orderBy(FieldPath.documentId(), 'asc')
    .limit(1)
));
console.log('');

console.log('='.repeat(60));
console.log('SUMMARY');
console.log('='.repeat(60));
console.log('');

results.forEach(r => {
  const status = r.result === 'SUCCESS' ? '✓ SUCCESS' : (r.result === 'MISSING_INDEX' ? '✗ MISSING INDEX' : '✗ ERROR');
  console.log(`${status.padEnd(20)} ${r.name}`);
});

console.log('');
const requiredIndexes = results.filter(r => r.required);
const successQueries = results.filter(r => r.result === 'SUCCESS');
console.log(`Total queries tested: ${results.length}`);
console.log(`Queries with missing indexes: ${requiredIndexes.length}`);
console.log(`Queries successful: ${successQueries.length}`);

if (requiredIndexes.length > 0) {
  console.log('');
  console.log('='.repeat(60));
  console.log('PROVEN REQUIRED INDEXES (by real Cloud Firestore errors):');
  console.log('='.repeat(60));
  requiredIndexes.forEach((r, idx) => {
    console.log(`\n${idx + 1}. ${r.name}`);
    console.log(`   Evidence: ${r.error.substring(0, 300)}`);
  });
  console.log('');
  console.log('These indexes must be added to firestore.indexes.json');
  console.log('with queryScope: "COLLECTION_GROUP"');
} else if (successQueries.length === results.length) {
  console.log('');
  console.log('All queries succeeded against real Cloud Firestore.');
  console.log('This means either:');
  console.log('  a) Required indexes already deployed, OR');
  console.log('  b) Queries use only automatic single-field indexes');
}

console.log('');
console.log('='.repeat(60));
console.log('Physical index proof complete.');
console.log('NO WRITES performed. NO INDEXES deployed.');
console.log('='.repeat(60));

process.exit(0);
