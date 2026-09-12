/**
 * F40.TC1-PHYSICAL-OCCURRENCE-INTEGRATION-FIX-R2
 * Rules & Emulator validation for Notification dispatch and Occurrence discovery
 */
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
  setDoc,
  where,
} from 'firebase/firestore';

const PROJECT_ID = process.env.GCLOUD_PROJECT || 'canil-gcm';
const HANDLER_A_RA = '990001'; // Titular / Creator
const HANDLER_B_RA = '990002'; // Integrante / Recipient

const testEnv = await initializeTestEnvironment({
  projectId: PROJECT_ID,
  firestore: {
    host: '127.0.0.1',
    port: 8080,
  },
});

console.log('--- Executing F40.TC1 Notification & Occurrence Rules Tests ---');

// Contexts
const ctxHandlerA = testEnv.authenticatedContext('uid_990001', {
  email: `${HANDLER_A_RA}@gcm.com.br`,
});
const ctxHandlerB = testEnv.authenticatedContext('uid_990002', {
  email: `${HANDLER_B_RA}@gcm.com.br`,
});
const dbA = ctxHandlerA.firestore();
const dbB = ctxHandlerB.firestore();

// Setup occurrence first so canCreateNotification can validate occurrence and participants
const occId = `occ_test_team_query_${Date.now()}`;
{
  const occDocRef = doc(dbA, `occurrences/${occId}`);
  await assertSucceeds(
    setDoc(occDocRef, {
      id: occId,
      shift_id: 'shift_1',
      primary_handler_id: 'uid_990001',
      primary_handler_ra: HANDLER_A_RA,
      dog_id: 'dog_k9',
      status: 'in_progress',
      started_at: new Date().toISOString(),
      created_at: new Date().toISOString(),
      participation_revision: 0,
      team_handler_ids: [HANDLER_A_RA, HANDLER_B_RA],
      accepted_handler_ids: [HANDLER_A_RA],
      pending_handler_ids: [HANDLER_B_RA],
      edit_authorized_handler_ids: [HANDLER_A_RA],
      team: [
        { handler_id: HANDLER_A_RA, role: 'titular' },
        { handler_id: HANDLER_B_RA, role: 'integrante' },
      ],
    })
  );
  console.log('[PASS] Setup: Occurrence created by Handler A with Handler B in team_handler_ids');
}

// Test 1: Cross-user notification pre-read fails with permission-denied (Root cause of Defect 1)
{
  const targetDoc = doc(dbA, `notifications/${HANDLER_B_RA}/items/test_notif_read_probe`);
  await assertFails(getDoc(targetDoc));
  console.log('[PASS] T1.1: Handler A reading Handler B notifications is DENIED by rules');
}

// Test 2: Cross-user notification creation succeeds under existing rules (No rules loosening)
const testNotifId = `opened_${occId}_${HANDLER_B_RA}`;
{
  const targetDoc = doc(dbA, `notifications/${HANDLER_B_RA}/items/${testNotifId}`);
  await assertSucceeds(
    setDoc(targetDoc, {
      type: 'occurrence_participation_requested',
      occurrence_id: occId,
      occurrence_title: 'Ocorrência Geral',
      created_at: new Date(),
      read_at: null,
      action_required: true,
      resolved_at: null,
      target_screen: 'occurrence_active',
      additional_data: HANDLER_A_RA,
    })
  );
  console.log('[PASS] T1.2: Handler A creating notification in Handler B collection SUCCEEDS under existing rules');
}

// Test 3: Handler B (recipient) can read their own notifications
{
  const ownDoc = doc(dbB, `notifications/${HANDLER_B_RA}/items/${testNotifId}`);
  const snap = await assertSucceeds(getDoc(ownDoc));
  assert.strictEqual(snap.exists(), true);
  assert.strictEqual(snap.data().occurrence_id, occId);
  console.log('[PASS] T1.3: Handler B reading own notification SUCCEEDS');
}

// Test 4: Handler A attempting duplicate overwrite of existing notification is DENIED by rules
// (Proves why client-side deduplication must not execute updateDoc or overwrite without permission)
{
  const targetDoc = doc(dbA, `notifications/${HANDLER_B_RA}/items/${testNotifId}`);
  await assertFails(
    setDoc(targetDoc, {
      type: 'occurrence_participation_requested',
      occurrence_id: occId,
      occurrence_title: 'Duplicate Attempt',
      created_at: new Date(),
      read_at: null,
    })
  );
  console.log('[PASS] T1.4: Handler A attempting update/overwrite of existing notification is DENIED');
}

// Test 5: Occurrence query by team_handler_ids succeeds with single-field index
{
  // Handler B discovers occurrence via team_handler_ids
  const q = query(
    collection(dbB, 'occurrences'),
    where('team_handler_ids', 'array-contains', HANDLER_B_RA)
  );
  const snap = await assertSucceeds(getDocs(q));
  assert.strictEqual(snap.empty, false);
  const found = snap.docs.some((d) => d.id === occId);
  assert.strictEqual(found, true);
  console.log('[PASS] T1.5: Occurrence discovery via team_handler_ids SUCCEEDS without new composite index');
}

console.log('--- ALL F40.TC1 Rules Tests PASSED Successfully ---');
await testEnv.cleanup();
process.exit(0);
