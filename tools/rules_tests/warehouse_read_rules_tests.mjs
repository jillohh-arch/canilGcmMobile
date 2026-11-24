import assert from 'node:assert/strict';
import {assertFails, assertSucceeds, initializeTestEnvironment} from '@firebase/rules-unit-testing';
import {collection, deleteDoc, doc, getDoc, getDocs, setDoc, updateDoc} from 'firebase/firestore';

// Contrato ratificado (bf4068c / CT3.F60.INVENTORY-AUDIT-ACCESS-LOCAL-R1):
// - leitura de warehouse_batches/positions/equipment/locations/custodies exige
//   inventory.view;
// - leitura de inventory_sessions e inventory_sessions/{id}/counts exige
//   inventory.view && inventory.audit;
// - warehouse_control, warehouse_equipment_identifiers e
//   warehouse_equipment_codes tem match nominal com deny-all.

const env = await initializeTestEnvironment({projectId: process.env.GCLOUD_PROJECT || 'canil-gcm'});

const inventoryReadable = [
  ['warehouse_batches', 'b1'],
  ['warehouse_positions', 'p1'],
  ['warehouse_equipment', 'e1'],
  ['warehouse_locations', 'loc1'],
  ['warehouse_custodies', 'c1'],
];

const auditReadable = [
  ['inventory_sessions', 's1'],
  ['inventory_sessions', 's1', 'counts', 'p1'],
];

const internalSealed = [
  ['warehouse_control', 'inventory_lock'],
  ['warehouse_equipment_identifiers', 'id1'],
  ['warehouse_equipment_codes', 'code1'],
];

const allPaths = [...inventoryReadable, ...auditReadable, ...internalSealed];

const db = (ra, claims = {}) => ra === null ? env.unauthenticatedContext().firestore() :
  env.authenticatedContext('uid-' + ra, {ra, email: ra + '@gcm.com.br', ...claims}).firestore();

const seed = async () => env.withSecurityRulesDisabled(async (context) => {
  const store = context.firestore();
  // 100: inventory.view sem inventory.audit
  // 150: inventory.view && inventory.audit
  // 200: sem inventory.view
  // 300: perfil inativo
  await setDoc(doc(store, 'users', '100'), {access_profile_id: 'warehouse_view'});
  await setDoc(doc(store, 'users', '150'), {access_profile_id: 'warehouse_view_audit'});
  await setDoc(doc(store, 'users', '200'), {access_profile_id: 'warehouse_no_view'});
  await setDoc(doc(store, 'users', '300'), {access_profile_id: 'warehouse_inactive'});
  await setDoc(doc(store, 'access_profiles', 'warehouse_view'), {
    status: 'active', permissions: {inventory: {view: true, audit: false}},
  });
  await setDoc(doc(store, 'access_profiles', 'warehouse_view_audit'), {
    status: 'active', permissions: {inventory: {view: true, audit: true}},
  });
  await setDoc(doc(store, 'access_profiles', 'warehouse_no_view'), {
    status: 'active', permissions: {inventory: {view: false, audit: true}},
  });
  await setDoc(doc(store, 'access_profiles', 'warehouse_inactive'), {
    status: 'inactive', permissions: {inventory: {view: true, audit: true}},
  });
  for (const path of allPaths) await setDoc(doc(store, ...path), {id: path.at(-1), label: 'fixture'});
  await setDoc(doc(store, 'inventory_items', 'legacy'), {current_quantity: 3});
  await setDoc(doc(store, 'inventory_movements', 'legacy'), {delta: 3});
  await setDoc(doc(store, 'idempotency_keys', 'private'), {response: {secret: true}});
  await setDoc(doc(store, 'auditLogs', 'f60-audit'), {action: 'warehouse_entry', actor: {uid: 'uid-100', ra: '100'}});
});

const denyReads = async (reader, path) => {
  await assertFails(getDoc(doc(reader, ...path)));
  await assertFails(getDocs(collection(reader, ...path.slice(0, -1))));
};

try {
  await seed();

  // 1. inventory.view habilita somente os namespaces de inventario.
  for (const path of inventoryReadable) {
    await assertSucceeds(getDoc(doc(db('100'), ...path)));
    await assertSucceeds(getDocs(collection(db('100'), ...path.slice(0, -1))));
    const ref = doc(db('100'), ...path);
    await assertFails(setDoc(ref, {id: 'replacement'}));
    await assertFails(updateDoc(ref, {label: 'changed'}));
    await assertFails(deleteDoc(ref));
    await assertFails(setDoc(doc(db('100'), ...path.slice(0, -1), 'new'), {id: 'new'}));
    await assertFails(setDoc(doc(db('500', {admin: true}), ...path.slice(0, -1), 'admin-new'), {id: 'admin-new'}));
  }

  // 2. Sessoes de inventario exigem view && audit (B1).
  for (const path of auditReadable) {
    await assertSucceeds(getDoc(doc(db('150'), ...path)));
    await assertSucceeds(getDocs(collection(db('150'), ...path.slice(0, -1))));
    await denyReads(db('100'), path); // view sem audit
    await denyReads(db('200'), path); // audit sem view
    await assertFails(setDoc(doc(db('150'), ...path.slice(0, -1), 'client-new'), {id: 'client-new'}));
  }

  // 3. Perfis sem autorizacao e nao autenticados falham fechado.
  for (const path of allPaths) {
    for (const denied of [db(null), db('200'), db('300'), db('400')]) {
      await denyReads(denied, path);
    }
  }

  // 4. Colecoes internas seladas por match nominal (deny-all).
  for (const path of internalSealed) {
    for (const reader of [db('100'), db('150'), db('500', {admin: true}), db(null)]) {
      await assertFails(getDoc(doc(reader, ...path)));
    }
    for (const writer of [db('100'), db('150'), db('500', {admin: true})]) {
      await assertFails(setDoc(doc(writer, ...path), {tampered: true}));
      await assertFails(updateDoc(doc(writer, ...path), {tampered: true}));
      await assertFails(deleteDoc(doc(writer, ...path)));
    }
  }

  // 5. Compatibilidade legada: leitura sem inventory.view, escrita sempre negada.
  for (const path of [['inventory_items', 'legacy'], ['inventory_movements', 'legacy']]) {
    await assertSucceeds(getDoc(doc(db('200'), ...path)));
    await assertFails(setDoc(doc(db('100'), ...path), {current_quantity: 99}));
  }
  for (const path of [['idempotency_keys', 'private']]) {
    await assertFails(getDoc(doc(db('100'), ...path)));
    await assertFails(getDoc(doc(db('500', {admin: true}), ...path)));
    await assertFails(setDoc(doc(db('100'), ...path), {response: null}));
  }

  // 6. auditLogs: sem leitura anonima e sem mutacao direta.
  await assertFails(getDoc(doc(db(null), 'auditLogs', 'f60-audit')));
  await assertFails(updateDoc(doc(db('100'), 'auditLogs', 'f60-audit'), {action: 'tampered'}));
  await assertFails(deleteDoc(doc(db('100'), 'auditLogs', 'f60-audit')));

  assert.equal(inventoryReadable.length, 5);
  assert.equal(auditReadable.length, 2);
  assert.equal(internalSealed.length, 3);
  console.log('F60 warehouse read-only rules: view/audit segregation, sealed internal collections and legacy compatibility OK');
} finally {
  await env.cleanup();
}