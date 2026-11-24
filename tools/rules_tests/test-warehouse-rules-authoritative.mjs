/**
 * K9 OPS — CONTROL TOWER III
 * Authoritative Firestore Security Rules Test Suite against Firebase Firestore Emulator
 * Gate: CT3.F60.INVENTORY-AUDIT-ACCESS-LOCAL-R1
 *
 * Mode: Full Authoritative Backend Rules Matrix Verification with Inventory Audit Segregation
 * Target Baseline: 758cb4d72c81edf85a8e852a445de1f85bd0de01 + Audit Access Segregation Patch
 *
 * Verified Security Policy:
 * 1. Operational Warehouse Collections (batches, positions, equipment, custodies, locations):
 *    - Required: hasAccessPermission('inventory', 'view')
 *    - Allowed: Admin, Almoxarifado, Gestor, Operador K9
 *    - Denied: Sem Estoque, Inactive Profile, Missing Profile, Missing/Invalid RA, Unauthenticated
 * 2. Physical Inventory Audit Sessions & Counts (inventory_sessions, counts subcollection):
 *    - Required: hasAccessPermission('inventory', 'view') && hasAccessPermission('inventory', 'audit')
 *    - Allowed: Admin, Almoxarifado, Gestor (with ratified F10 inventory.audit grant)
 *    - Denied: Operador K9 (ratified: view only), Gestor (current deployed profile lacking inventory.audit),
 *              Sem Estoque, Inactive Profile, Missing Profile, Missing/Invalid RA, Unauthenticated
 * 3. Client Mutation Denial:
 *    - All client create, update, delete DENIED across all 7 collections for all callers.
 * 4. Internal Control & Uniqueness Collections:
 *    - warehouse_control, warehouse_equipment_identifiers, warehouse_equipment_codes SEALED from all callers.
 * 5. Cross-Front Regressions:
 *    - Legacy inventory_items, inventory_movements, idempotency_keys, binomials, dogs, clinical_cases.
 */

import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import {
  assertFails,
  assertSucceeds,
  initializeTestEnvironment,
} from '@firebase/rules-unit-testing';
import {
  collection,
  deleteDoc,
  doc,
  getDoc,
  getDocs,
  setDoc,
  updateDoc,
} from 'firebase/firestore';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const rulesPath = path.resolve(__dirname, '..', '..', 'firestore.rules');
const rules = fs.readFileSync(rulesPath, 'utf8');

const PROJECT_ID = 'canil-gcm-audit-segregation-test';

let emuHost = '127.0.0.1';
let emuPort = 8080;
if (process.env.FIRESTORE_EMULATOR_HOST) {
  const parts = process.env.FIRESTORE_EMULATOR_HOST.split(':');
  emuHost = parts[0];
  emuPort = parseInt(parts[1], 10);
}

const testEnv = await initializeTestEnvironment({
  projectId: PROJECT_ID,
  firestore: {
    rules,
    host: emuHost,
    port: emuPort,
  },
});

let testCount = 0;
let passCount = 0;
let failCount = 0;

async function runTestCase(name, fn) {
  testCount++;
  try {
    await fn();
    passCount++;
    console.log(`  ✓ PASS: ${name}`);
  } catch (err) {
    failCount++;
    console.error(`  ✗ FAIL: ${name}`);
    console.error(`    ${err.message || err}`);
  }
}

// Helper to get authenticated or unauthenticated firestore context
function getDb(ra, claims = {}) {
  if (ra === null) {
    return testEnv.unauthenticatedContext().firestore();
  }
  const token = {
    email: `${ra}@gcm.sp.gov.br`,
    ...claims,
  };
  if (ra !== undefined) {
    token.ra = ra;
  }
  return testEnv.authenticatedContext(`uid-${ra || 'no-ra'}`, token).firestore();
}

// Seed comprehensive fixture data
async function seedFixtures() {
  await testEnv.withSecurityRulesDisabled(async (context) => {
    const store = context.firestore();

    // 1. Access Profiles
    // Administrador: total access
    await setDoc(doc(store, 'access_profiles', 'profile_admin'), {
      status: 'active',
      scope: 'global',
      name: 'Administrador',
      permissions: {
        inventory: { view: true, create: true, edit: true, delete: true, audit: true },
        health: { view: true, create: true, edit: true },
        clinical: { view: true, create: true, edit: true },
      },
    });

    // Almoxarifado: canonical profile has inventory.audit
    await setDoc(doc(store, 'access_profiles', 'profile_almox'), {
      status: 'active',
      scope: 'global',
      name: 'Almoxarifado',
      permissions: {
        inventory: { view: true, create: true, edit: true, archive: true, export: true, audit: true },
      },
    });

    // Gestor (Ratified F10 Capability Profile): has inventory.audit granted
    await setDoc(doc(store, 'access_profiles', 'profile_gestor_ratified'), {
      status: 'active',
      scope: 'global',
      name: 'Gestor (Ratified F10)',
      permissions: {
        inventory: { view: true, export: true, audit: true },
        reports: { view: true, export: true, audit: true },
      },
    });

    // Gestor (Current Deployed Profile): lacks inventory.audit
    await setDoc(doc(store, 'access_profiles', 'profile_gestor_current'), {
      status: 'active',
      scope: 'global',
      name: 'Gestor (Current Deployed)',
      permissions: {
        inventory: { view: true, export: true },
        reports: { view: true, export: true, audit: true },
      },
    });

    // Operador K9: has inventory.view, STRICTLY lacks inventory.audit
    await setDoc(doc(store, 'access_profiles', 'profile_operador_k9'), {
      status: 'active',
      scope: 'own_records',
      name: 'Operador K9',
      permissions: {
        inventory: { view: true },
        dogs: { view: true },
      },
    });

    // Veterinário
    await setDoc(doc(store, 'access_profiles', 'profile_veterinario'), {
      status: 'active',
      scope: 'global',
      name: 'Veterinário',
      permissions: {
        health: { view: true, create: true, edit: true },
        clinical: { view: true, create: true, edit: true },
      },
    });

    // Sem Estoque (profile lacking inventory permissions)
    await setDoc(doc(store, 'access_profiles', 'profile_sem_estoque'), {
      status: 'active',
      scope: 'own_records',
      name: 'Sem Estoque',
      permissions: { inventory: { view: false }, dogs: { view: true } },
    });

    // Inactive profile
    await setDoc(doc(store, 'access_profiles', 'profile_inativo'), {
      status: 'inactive',
      scope: 'global',
      name: 'Inativo',
      permissions: { inventory: { view: true, audit: true } },
    });

    // 2. Users (referenced by RA claim)
    await setDoc(doc(store, 'users', 'RA-ADMIN'), {
      access_profile_id: 'profile_admin',
      name: 'Admin User',
    });
    await setDoc(doc(store, 'users', 'RA-ALMOX'), {
      access_profile_id: 'profile_almox',
      name: 'Almoxarifado User',
    });
    await setDoc(doc(store, 'users', 'RA-GESTOR-RATIFIED'), {
      access_profile_id: 'profile_gestor_ratified',
      name: 'Gestor Ratified User',
    });
    await setDoc(doc(store, 'users', 'RA-GESTOR-CURRENT'), {
      access_profile_id: 'profile_gestor_current',
      name: 'Gestor Current User',
    });
    await setDoc(doc(store, 'users', 'RA-OPERADOR'), {
      access_profile_id: 'profile_operador_k9',
      name: 'Operador K9 User',
    });
    await setDoc(doc(store, 'users', 'RA-OUTSIDER'), {
      access_profile_id: 'profile_operador_k9',
      name: 'Outsider Operador User',
    });
    await setDoc(doc(store, 'users', 'RA-VET'), {
      access_profile_id: 'profile_veterinario',
      name: 'Veterinário User',
    });
    await setDoc(doc(store, 'users', 'RA-SEMESTOQUE'), {
      access_profile_id: 'profile_sem_estoque',
      name: 'Sem Estoque User',
    });
    await setDoc(doc(store, 'users', 'RA-INATIVO'), {
      access_profile_id: 'profile_inativo',
      name: 'Inactive Profile User',
    });
    await setDoc(doc(store, 'users', 'RA-MISSPROFILE'), {
      access_profile_id: 'profile_non_existent',
      name: 'Missing Profile User',
    });

    // 3. Operational Warehouse Collections fixtures
    await setDoc(doc(store, 'warehouse_batches', 'batch-001'), {
      batch_number: 'B2026-001',
      material_id: 'mat-001',
      quantity: 50,
    });
    await setDoc(doc(store, 'warehouse_positions', 'pos-001'), {
      code: 'A1-R01-P01',
      location_id: 'loc-001',
      status: 'active',
    });
    await setDoc(doc(store, 'warehouse_equipment', 'eq-001'), {
      name: 'Colete Tático K9',
      serial_number: 'SN-COL-001',
      status: 'available',
    });
    await setDoc(doc(store, 'warehouse_custodies', 'cust-001'), {
      equipment_id: 'eq-001',
      operator_ra: 'RA-OPERADOR',
      status: 'open',
    });
    await setDoc(doc(store, 'warehouse_locations', 'loc-001'), {
      name: 'Depósito Central Canil',
      type: 'warehouse',
    });

    // 4. Physical Inventory Audit Sessions & Counts fixtures
    await setDoc(doc(store, 'inventory_sessions', 'sess-001'), {
      status: 'in_progress',
      started_at: '2026-10-27T10:00:00Z',
      title: 'Inventário Físico Anual 2026',
    });
    await setDoc(doc(store, 'inventory_sessions', 'sess-001', 'counts', 'count-001'), {
      position_id: 'pos-001',
      quantity_counted: 48,
    });

    // 5. Internal uniqueness indexes & control tables
    await setDoc(doc(store, 'warehouse_control', 'inventory_lock'), {
      active_session_id: 'sess-001',
      locked: true,
    });
    await setDoc(doc(store, 'warehouse_equipment_identifiers', 'id-001'), {
      equipment_id: 'eq-001',
      identifier: 'SN-COL-001',
    });
    await setDoc(doc(store, 'warehouse_equipment_codes', 'code-001'), {
      equipment_id: 'eq-001',
      patrimony_code: 'PAT-778899',
    });

    // 6. Existing / Legacy collections
    await setDoc(doc(store, 'inventory_items', 'legacy-item-1'), {
      name: 'Ração Especial K9',
      current_quantity: 120,
    });
    await setDoc(doc(store, 'inventory_movements', 'legacy-mov-1'), {
      item_id: 'legacy-item-1',
      delta: 20,
    });
    await setDoc(doc(store, 'idempotency_keys', 'key-sec-001'), {
      response: { payload: 'private' },
    });
    await setDoc(doc(store, 'binomials', 'bin-001'), {
      dog_id: 'apollo',
      handler_ra: 'RA-OPERADOR',
    });

    // 7. Dogs & Clinical cross-front fixtures
    await setDoc(doc(store, 'dogs', 'apollo'), {
      name: 'Apollo',
      status: 'active',
      handler_ra: 'RA-OPERADOR',
      assigned_ras: ['RA-OPERADOR'],
    });
    await setDoc(doc(store, 'dogs', 'apollo', 'clinical_cases', 'case-001'), {
      dog_id: 'apollo',
      title: 'Avaliação Periódica',
      status: 'open',
    });
  });
}

// 5 Operational Warehouse targets (accessible to inventory.view)
const operationalTargets = [
  { collectionName: 'warehouse_batches', docId: 'batch-001' },
  { collectionName: 'warehouse_positions', docId: 'pos-001' },
  { collectionName: 'warehouse_equipment', docId: 'eq-001' },
  { collectionName: 'warehouse_custodies', docId: 'cust-001' },
  { collectionName: 'warehouse_locations', docId: 'loc-001' },
];

// 2 Physical Inventory Audit targets (require inventory.view AND inventory.audit)
const auditSessionTargets = [
  { collectionName: 'inventory_sessions', docId: 'sess-001', isSubcollection: false },
  { collectionName: 'inventory_sessions/sess-001/counts', docId: 'count-001', isSubcollection: true },
];

const allSevenWarehouseTargets = [
  ...operationalTargets.map(t => ({ ...t, isSubcollection: false })),
  ...auditSessionTargets,
];

const internalControlTargets = [
  { collectionName: 'warehouse_control', docId: 'inventory_lock' },
  { collectionName: 'warehouse_equipment_identifiers', docId: 'id-001' },
  { collectionName: 'warehouse_equipment_codes', docId: 'code-001' },
];

try {
  console.log('\n======================================================================');
  console.log('  K9 OPS — INVENTORY AUDIT ACCESS SEGREGATION TEST SUITE (EMULATOR)');
  console.log('  Gate: CT3.F60.INVENTORY-AUDIT-ACCESS-LOCAL-R1');
  console.log('  Owner Decision: Option B — RATIFIED');
  console.log('======================================================================\n');

  console.log('[1/7] Seeding emulator fixture data...');
  await seedFixtures();
  console.log('Fixture data seeded successfully.\n');

  // Contexts
  const dbAdmin = getDb('RA-ADMIN', { admin: true });
  const dbAlmox = getDb('RA-ALMOX');
  const dbGestorRatified = getDb('RA-GESTOR-RATIFIED');
  const dbGestorCurrent = getDb('RA-GESTOR-CURRENT');
  const dbOperador = getDb('RA-OPERADOR');
  const dbVet = getDb('RA-VET');
  const dbSemEstoque = getDb('RA-SEMESTOQUE');
  const dbInativo = getDb('RA-INATIVO');
  const dbMissProfile = getDb('RA-MISSPROFILE');
  const dbNoRa = getDb(undefined); // authenticated, no ra claim
  const dbEmptyRa = getDb(''); // authenticated, empty ra claim
  const dbUnauth = getDb(null); // unauthenticated

  // Helper for audit targets
  const getAuditRefs = (dbInstance, target) => {
    if (target.isSubcollection) {
      return {
        docRef: doc(dbInstance, 'inventory_sessions', 'sess-001', 'counts', target.docId),
        colRef: collection(dbInstance, 'inventory_sessions', 'sess-001', 'counts'),
      };
    }
    return {
      docRef: doc(dbInstance, target.collectionName, target.docId),
      colRef: collection(dbInstance, target.collectionName),
    };
  };

  console.log('[2/7] Running OPERATIONAL Warehouse Collections READ Matrix (inventory.view)...');

  for (const target of operationalTargets) {
    const targetLabel = target.collectionName;
    const docRef = (dbInstance) => doc(dbInstance, target.collectionName, target.docId);
    const colRef = (dbInstance) => collection(dbInstance, target.collectionName);

    // 1. Admin ALLOW
    await runTestCase(`ALLOW Admin getDoc on operational ${targetLabel}`, async () => {
      await assertSucceeds(getDoc(docRef(dbAdmin)));
    });
    await runTestCase(`ALLOW Admin getDocs (list) on operational ${targetLabel}`, async () => {
      await assertSucceeds(getDocs(colRef(dbAdmin)));
    });

    // 2. Almoxarifado ALLOW
    await runTestCase(`ALLOW Almoxarifado getDoc on operational ${targetLabel}`, async () => {
      await assertSucceeds(getDoc(docRef(dbAlmox)));
    });
    await runTestCase(`ALLOW Almoxarifado getDocs (list) on operational ${targetLabel}`, async () => {
      await assertSucceeds(getDocs(colRef(dbAlmox)));
    });

    // 3. Gestor ALLOW
    await runTestCase(`ALLOW Gestor getDoc on operational ${targetLabel}`, async () => {
      await assertSucceeds(getDoc(docRef(dbGestorCurrent)));
    });
    await runTestCase(`ALLOW Gestor getDocs on operational ${targetLabel}`, async () => {
      await assertSucceeds(getDocs(colRef(dbGestorCurrent)));
    });

    // 4. Operador K9 ALLOW (operational warehouse access preserved)
    await runTestCase(`ALLOW Operador K9 getDoc on operational ${targetLabel}`, async () => {
      await assertSucceeds(getDoc(docRef(dbOperador)));
    });
    await runTestCase(`ALLOW Operador K9 getDocs (list) on operational ${targetLabel}`, async () => {
      await assertSucceeds(getDocs(colRef(dbOperador)));
    });

    // 5. Sem Estoque DENY
    await runTestCase(`DENY Sem Estoque getDoc on operational ${targetLabel}`, async () => {
      await assertFails(getDoc(docRef(dbSemEstoque)));
    });
    await runTestCase(`DENY Sem Estoque getDocs on operational ${targetLabel}`, async () => {
      await assertFails(getDocs(colRef(dbSemEstoque)));
    });

    // 6. Inactive Profile DENY
    await runTestCase(`DENY Inactive Profile getDoc on operational ${targetLabel}`, async () => {
      await assertFails(getDoc(docRef(dbInativo)));
    });

    // 7. Missing Profile DENY
    await runTestCase(`DENY Missing Profile getDoc on operational ${targetLabel}`, async () => {
      await assertFails(getDoc(docRef(dbMissProfile)));
    });

    // 8. Missing RA Claim DENY
    await runTestCase(`DENY No RA Claim getDoc on operational ${targetLabel}`, async () => {
      await assertFails(getDoc(docRef(dbNoRa)));
    });

    // 9. Empty RA Claim DENY
    await runTestCase(`DENY Empty RA Claim getDoc on operational ${targetLabel}`, async () => {
      await assertFails(getDoc(docRef(dbEmptyRa)));
    });

    // 10. Unauthenticated DENY
    await runTestCase(`DENY Unauthenticated getDoc on operational ${targetLabel}`, async () => {
      await assertFails(getDoc(docRef(dbUnauth)));
    });
    await runTestCase(`DENY Unauthenticated getDocs on operational ${targetLabel}`, async () => {
      await assertFails(getDocs(colRef(dbUnauth)));
    });
  }

  console.log('\n[3/7] Running PHYSICAL INVENTORY AUDIT SESSIONS & COUNTS Segregation Matrix...');

  for (const target of auditSessionTargets) {
    const targetLabel = target.collectionName;

    // 1. Admin ALLOW (bypass / audit capability)
    await runTestCase(`ALLOW Admin getDoc on audit ${targetLabel}`, async () => {
      const { docRef } = getAuditRefs(dbAdmin, target);
      await assertSucceeds(getDoc(docRef));
    });
    await runTestCase(`ALLOW Admin getDocs (list) on audit ${targetLabel}`, async () => {
      const { colRef } = getAuditRefs(dbAdmin, target);
      await assertSucceeds(getDocs(colRef));
    });

    // 2. Almoxarifado ALLOW (possesses inventory.view AND inventory.audit)
    await runTestCase(`ALLOW Almoxarifado getDoc on audit ${targetLabel}`, async () => {
      const { docRef } = getAuditRefs(dbAlmox, target);
      await assertSucceeds(getDoc(docRef));
    });
    await runTestCase(`ALLOW Almoxarifado getDocs (list) on audit ${targetLabel}`, async () => {
      const { colRef } = getAuditRefs(dbAlmox, target);
      await assertSucceeds(getDocs(colRef));
    });

    // 3. Gestor with Ratified F10 Capability ALLOW
    await runTestCase(`ALLOW Gestor (Ratified F10) getDoc on audit ${targetLabel}`, async () => {
      const { docRef } = getAuditRefs(dbGestorRatified, target);
      await assertSucceeds(getDoc(docRef));
    });
    await runTestCase(`ALLOW Gestor (Ratified F10) getDocs on audit ${targetLabel}`, async () => {
      const { colRef } = getAuditRefs(dbGestorRatified, target);
      await assertSucceeds(getDocs(colRef));
    });

    // 4. Gestor with Current Deployed Profile DENY (lacks inventory.audit)
    await runTestCase(`DENY Gestor (Current Deployed) getDoc on audit ${targetLabel}`, async () => {
      const { docRef } = getAuditRefs(dbGestorCurrent, target);
      await assertFails(getDoc(docRef));
    });
    await runTestCase(`DENY Gestor (Current Deployed) getDocs on audit ${targetLabel}`, async () => {
      const { colRef } = getAuditRefs(dbGestorCurrent, target);
      await assertFails(getDocs(colRef));
    });

    // 5. OPERADOR K9 STRICTLY DENIED (Option B Ratified: view only, lacks audit)
    await runTestCase(`DENY Operador K9 getDoc on audit ${targetLabel}`, async () => {
      const { docRef } = getAuditRefs(dbOperador, target);
      await assertFails(getDoc(docRef));
    });
    await runTestCase(`DENY Operador K9 getDocs (list) on audit ${targetLabel}`, async () => {
      const { colRef } = getAuditRefs(dbOperador, target);
      await assertFails(getDocs(colRef));
    });

    // 6. Sem Estoque DENY
    await runTestCase(`DENY Sem Estoque getDoc on audit ${targetLabel}`, async () => {
      const { docRef } = getAuditRefs(dbSemEstoque, target);
      await assertFails(getDoc(docRef));
    });

    // 7. Inactive Profile DENY
    await runTestCase(`DENY Inactive Profile getDoc on audit ${targetLabel}`, async () => {
      const { docRef } = getAuditRefs(dbInativo, target);
      await assertFails(getDoc(docRef));
    });

    // 8. Missing Profile DENY
    await runTestCase(`DENY Missing Profile getDoc on audit ${targetLabel}`, async () => {
      const { docRef } = getAuditRefs(dbMissProfile, target);
      await assertFails(getDoc(docRef));
    });

    // 9. Missing RA Claim DENY
    await runTestCase(`DENY No RA Claim getDoc on audit ${targetLabel}`, async () => {
      const { docRef } = getAuditRefs(dbNoRa, target);
      await assertFails(getDoc(docRef));
    });

    // 10. Empty RA Claim DENY
    await runTestCase(`DENY Empty RA Claim getDoc on audit ${targetLabel}`, async () => {
      const { docRef } = getAuditRefs(dbEmptyRa, target);
      await assertFails(getDoc(docRef));
    });

    // 11. Unauthenticated DENY
    await runTestCase(`DENY Unauthenticated getDoc on audit ${targetLabel}`, async () => {
      const { docRef } = getAuditRefs(dbUnauth, target);
      await assertFails(getDoc(docRef));
    });
    await runTestCase(`DENY Unauthenticated getDocs on audit ${targetLabel}`, async () => {
      const { colRef } = getAuditRefs(dbUnauth, target);
      await assertFails(getDocs(colRef));
    });
  }

  console.log('\n[4/7] Running Warehouse Collections CLIENT MUTATION DENIAL Matrix...');

  for (const target of allSevenWarehouseTargets) {
    const isSub = target.isSubcollection;
    const targetLabel = target.collectionName;

    const getDocRef = (dbInstance, id) => {
      if (isSub) {
        return doc(dbInstance, 'inventory_sessions', 'sess-001', 'counts', id);
      }
      return doc(dbInstance, target.collectionName, id);
    };

    // Client setDoc (create new) -> DENY for all
    await runTestCase(`DENY Admin setDoc (create) on ${targetLabel}`, async () => {
      await assertFails(setDoc(getDocRef(dbAdmin, 'new-item-by-admin'), { data: 'malicious' }));
    });
    await runTestCase(`DENY Almoxarifado setDoc (create) on ${targetLabel}`, async () => {
      await assertFails(setDoc(getDocRef(dbAlmox, 'new-item-by-almox'), { data: 'malicious' }));
    });
    await runTestCase(`DENY Gestor setDoc (create) on ${targetLabel}`, async () => {
      await assertFails(setDoc(getDocRef(dbGestorRatified, 'new-item-by-gestor'), { data: 'malicious' }));
    });
    await runTestCase(`DENY Operador K9 setDoc (create) on ${targetLabel}`, async () => {
      await assertFails(setDoc(getDocRef(dbOperador, 'new-item-by-op'), { data: 'malicious' }));
    });
    await runTestCase(`DENY Unauthenticated setDoc (create) on ${targetLabel}`, async () => {
      await assertFails(setDoc(getDocRef(dbUnauth, 'new-item-by-anon'), { data: 'malicious' }));
    });

    // Client updateDoc -> DENY for all
    await runTestCase(`DENY Admin updateDoc on ${targetLabel}`, async () => {
      await assertFails(updateDoc(getDocRef(dbAdmin, target.docId), { quantity: 9999 }));
    });
    await runTestCase(`DENY Almoxarifado updateDoc on ${targetLabel}`, async () => {
      await assertFails(updateDoc(getDocRef(dbAlmox, target.docId), { quantity: 9999 }));
    });
    await runTestCase(`DENY Operador K9 updateDoc on ${targetLabel}`, async () => {
      await assertFails(updateDoc(getDocRef(dbOperador, target.docId), { quantity: 9999 }));
    });

    // Client deleteDoc -> DENY for all
    await runTestCase(`DENY Admin deleteDoc on ${targetLabel}`, async () => {
      await assertFails(deleteDoc(getDocRef(dbAdmin, target.docId)));
    });
    await runTestCase(`DENY Almoxarifado deleteDoc on ${targetLabel}`, async () => {
      await assertFails(deleteDoc(getDocRef(dbAlmox, target.docId)));
    });
    await runTestCase(`DENY Operador K9 deleteDoc on ${targetLabel}`, async () => {
      await assertFails(deleteDoc(getDocRef(dbOperador, target.docId)));
    });
  }

  console.log('\n[5/7] Running Internal Uniqueness Indexes & Control Documents DENIAL Matrix...');

  for (const internal of internalControlTargets) {
    const targetLabel = internal.collectionName;

    // Direct Read DENY for ALL clients
    await runTestCase(`DENY Admin getDoc on internal collection ${targetLabel}`, async () => {
      await assertFails(getDoc(doc(dbAdmin, internal.collectionName, internal.docId)));
    });
    await runTestCase(`DENY Almoxarifado getDoc on internal collection ${targetLabel}`, async () => {
      await assertFails(getDoc(doc(dbAlmox, internal.collectionName, internal.docId)));
    });
    await runTestCase(`DENY Gestor getDoc on internal collection ${targetLabel}`, async () => {
      await assertFails(getDoc(doc(dbGestorRatified, internal.collectionName, internal.docId)));
    });
    await runTestCase(`DENY Operador K9 getDoc on internal collection ${targetLabel}`, async () => {
      await assertFails(getDoc(doc(dbOperador, internal.collectionName, internal.docId)));
    });
    await runTestCase(`DENY Unauthenticated getDoc on internal collection ${targetLabel}`, async () => {
      await assertFails(getDoc(doc(dbUnauth, internal.collectionName, internal.docId)));
    });

    // Direct Write DENY for ALL clients
    await runTestCase(`DENY Admin setDoc on internal collection ${targetLabel}`, async () => {
      await assertFails(setDoc(doc(dbAdmin, internal.collectionName, 'bypass'), { hack: true }));
    });
    await runTestCase(`DENY Almoxarifado setDoc on internal collection ${targetLabel}`, async () => {
      await assertFails(setDoc(doc(dbAlmox, internal.collectionName, 'bypass'), { hack: true }));
    });
  }

  console.log('\n[6/7] Running Legacy Inventory & System Collections Matrix...');

  // Legacy inventory collections (inventory_items, inventory_movements)
  await runTestCase('ALLOW signedIn getDoc on inventory_items', async () => {
    await assertSucceeds(getDoc(doc(dbSemEstoque, 'inventory_items', 'legacy-item-1')));
  });
  await runTestCase('DENY client setDoc on inventory_items', async () => {
    await assertFails(setDoc(doc(dbAlmox, 'inventory_items', 'legacy-item-1'), { current_quantity: 999 }));
  });
  await runTestCase('DENY unauthenticated getDoc on inventory_items', async () => {
    await assertFails(getDoc(doc(dbUnauth, 'inventory_items', 'legacy-item-1')));
  });

  await runTestCase('ALLOW signedIn getDoc on inventory_movements', async () => {
    await assertSucceeds(getDoc(doc(dbOperador, 'inventory_movements', 'legacy-mov-1')));
  });
  await runTestCase('DENY client updateDoc on inventory_movements', async () => {
    await assertFails(updateDoc(doc(dbAdmin, 'inventory_movements', 'legacy-mov-1'), { delta: 999 }));
  });

  // Server-only idempotency_keys
  await runTestCase('DENY Admin getDoc on idempotency_keys', async () => {
    await assertFails(getDoc(doc(dbAdmin, 'idempotency_keys', 'key-sec-001')));
  });
  await runTestCase('DENY Almoxarifado setDoc on idempotency_keys', async () => {
    await assertFails(setDoc(doc(dbAlmox, 'idempotency_keys', 'key-sec-002'), { secret: true }));
  });

  // Binomials
  await runTestCase('ALLOW signedIn getDoc on binomials', async () => {
    await assertSucceeds(getDoc(doc(dbAlmox, 'binomials', 'bin-001')));
  });
  await runTestCase('DENY unauthenticated getDoc on binomials', async () => {
    await assertFails(getDoc(doc(dbUnauth, 'binomials', 'bin-001')));
  });

  console.log('\n[7/7] Running Expanded Cross-Front Regressions (F10/F20 Dogs & Clinical)...');

  // Dogs collection: signedIn can read profile, mutations denied, unauthenticated denied
  await runTestCase('ALLOW signedIn Operador K9 getDoc on dogs', async () => {
    await assertSucceeds(getDoc(doc(dbOperador, 'dogs', 'apollo')));
  });
  await runTestCase('ALLOW signedIn Almoxarifado getDoc on dogs', async () => {
    await assertSucceeds(getDoc(doc(dbAlmox, 'dogs', 'apollo')));
  });
  await runTestCase('ALLOW Admin getDoc on dogs', async () => {
    await assertSucceeds(getDoc(doc(dbAdmin, 'dogs', 'apollo')));
  });
  await runTestCase('DENY client setDoc (create/update) on dog record', async () => {
    await assertFails(setDoc(doc(dbAdmin, 'dogs', 'apollo'), { name: 'Tampered' }));
  });
  await runTestCase('DENY unauthenticated getDoc on dogs', async () => {
    await assertFails(getDoc(doc(dbUnauth, 'dogs', 'apollo')));
  });

  // Clinical cases: scoped access requiring hasClinicalReadAuthority + canAccessDogRecord
  await runTestCase('ALLOW Veterinário getDoc on clinical_cases for accessible dog', async () => {
    await assertSucceeds(getDoc(doc(dbVet, 'dogs', 'apollo', 'clinical_cases', 'case-001')));
  });
  await runTestCase('DENY Operador K9 getDoc on clinical_cases without clinical authority', async () => {
    await assertFails(getDoc(doc(dbOperador, 'dogs', 'apollo', 'clinical_cases', 'case-001')));
  });
  await runTestCase('DENY client write on clinical_cases', async () => {
    await assertFails(setDoc(doc(dbVet, 'dogs', 'apollo', 'clinical_cases', 'case-new'), { diagnosis: 'fraud' }));
  });

  console.log('\n======================================================================');
  console.log(`  AUDIT SEGREGATION TEST RESULTS: ${passCount} / ${testCount} PASSED (${failCount} FAILED)`);
  console.log('======================================================================\n');

  if (failCount > 0) {
    process.exit(1);
  }
} finally {
  await testEnv.cleanup();
}
