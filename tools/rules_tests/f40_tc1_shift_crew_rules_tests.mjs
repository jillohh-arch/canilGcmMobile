/**
 * F40.TC1-MULTI-DEVICE-CONSISTENCY-REPAIR-R4
 * Real local Firestore Rules Emulator coverage for Shift & Crew auto-teardown (D5)
 *
 * Scenarios verified:
 * 1. auxiliary/no-K9 endShift while still in crew (updates only member doc, active_shift, shift_logs)
 * 2. titular endShift while crew exists (authorized to update parent vehicle_crews doc)
 * 3. auxiliary must NOT mutate parent vehicle_crews doc (strict permission-denied)
 * 4. member dog_id deletion via deleteField() is accepted by current Rules
 * 5. normal manual leaveVehicle remains authorized
 * 6. denied unauthorized mutation remains denied (e.g. mutating another member doc, dog_id: null)
 */
import assert from 'node:assert/strict';
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

const TITULAR_RA = '990001';
const AUXILIARY_RA = '990002';
const THIRD_PARTY_RA = '990003';
const CREW_ID = 'VTR-F40-TEST';
const DOG_ID = 'dog-k9-f40';

const testEnv = await initializeTestEnvironment({
  projectId: PROJECT_ID,
  firestore: {
    host: '127.0.0.1',
    port: 8080,
  },
});

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
  return Timestamp.fromDate(new Date('2026-09-12T12:00:00.000Z'));
}

async function seedFirestore(seedFn) {
  await testEnv.withSecurityRulesDisabled(async (context) => {
    await seedFn(context.firestore());
  });
}

async function seedActiveCrewState() {
  await seedFirestore(async (db) => {
    // Dog document
    await setDoc(doc(db, 'dogs', DOG_ID), {
      name: 'Thor',
      handler_ra: TITULAR_RA,
      conductorRa: TITULAR_RA,
      status: 'active',
    });

    // Parent vehicle_crews doc (titular is 990001)
    await setDoc(doc(db, 'vehicle_crews', CREW_ID), {
      id: CREW_ID,
      vehicle_id: CREW_ID,
      vehicle_label: 'VTR 01',
      crew_size: 2,
      service_dog_id: DOG_ID,
      titular_handler_id: TITULAR_RA,
      active: true,
      created_at: now(),
      updated_at: now(),
    });

    // Titular member (has dog)
    await setDoc(doc(db, 'vehicle_crews', CREW_ID, 'members', TITULAR_RA), {
      handler_id: TITULAR_RA,
      auth_uid: `uid-${TITULAR_RA}`,
      handler_email: `${TITULAR_RA}@gcm.com.br`,
      name: 'Titular Condutor',
      role: 'titular',
      status: 'active',
      dog_id: DOG_ID,
      joined_at: now(),
      updated_at: now(),
    });

    // Auxiliary member (no dog)
    await setDoc(doc(db, 'vehicle_crews', CREW_ID, 'members', AUXILIARY_RA), {
      handler_id: AUXILIARY_RA,
      auth_uid: `uid-${AUXILIARY_RA}`,
      handler_email: `${AUXILIARY_RA}@gcm.com.br`,
      name: 'Auxiliar Apoio',
      role: 'auxiliar_1',
      status: 'active',
      joined_at: now(),
      updated_at: now(),
    });

    // Active shift for titular
    await setDoc(doc(db, 'active_shifts', TITULAR_RA), {
      shiftId: 'shift-titular-1',
      handlerId: TITULAR_RA,
      auth_uid: `uid-${TITULAR_RA}`,
      handler_email: `${TITULAR_RA}@gcm.com.br`,
      dogId: DOG_ID,
      service_dog_id: DOG_ID,
      status: 'active',
      startedAt: now(),
      updatedAt: now(),
      vehicle_id: CREW_ID,
      vehicle_crew_id: CREW_ID,
      crew_id: CREW_ID,
      crew_role: 'titular',
      crew_status: 'active',
    });

    // Active shift for auxiliary (no dog)
    await setDoc(doc(db, 'active_shifts', AUXILIARY_RA), {
      shiftId: 'shift-aux-1',
      handlerId: AUXILIARY_RA,
      auth_uid: `uid-${AUXILIARY_RA}`,
      handler_email: `${AUXILIARY_RA}@gcm.com.br`,
      dogId: '',
      service_dog_id: '',
      status: 'active',
      startedAt: now(),
      updatedAt: now(),
      vehicle_id: CREW_ID,
      vehicle_crew_id: CREW_ID,
      crew_id: CREW_ID,
      crew_role: 'auxiliar_1',
      crew_status: 'active',
    });

    // Shift logs
    await setDoc(doc(db, 'shift_logs', 'shift-titular-1'), {
      id: 'shift-titular-1',
      handlerId: TITULAR_RA,
      initialDogId: DOG_ID,
      currentDogId: DOG_ID,
      service_dog_id: DOG_ID,
      status: 'active',
      startedAt: now(),
      updatedAt: now(),
      vehicle_crew_id: CREW_ID,
    });
    await setDoc(doc(db, 'shift_logs', 'shift-aux-1'), {
      id: 'shift-aux-1',
      handlerId: AUXILIARY_RA,
      initialDogId: '',
      currentDogId: '',
      service_dog_id: '',
      status: 'active',
      startedAt: now(),
      updatedAt: now(),
      vehicle_crew_id: CREW_ID,
    });
  });
}

console.log('--- Executing F40.TC1 Shift & Crew Rules Tests (D5) ---');

// 1. Auxiliary/no-K9 endShift while still in crew:
// Updates only vehicle_crews/{crewId}/members/{auxiliaryRa}, active_shifts/{auxiliaryRa}, shift_logs/{shift-aux-1}
{
  await seedActiveCrewState();
  const db = dbFor(AUXILIARY_RA);

  // Member doc: exit with dog_id deletion (deleteField)
  await assertSucceeds(
    updateDoc(doc(db, 'vehicle_crews', CREW_ID, 'members', AUXILIARY_RA), {
      status: 'ended',
      left_at: now(),
      dog_id: deleteField(),
      updated_at: now(),
    })
  );

  // Active shift: mark ended and clear vehicle fields
  await assertSucceeds(
    updateDoc(doc(db, 'active_shifts', AUXILIARY_RA), {
      status: 'ended',
      endedAt: now(),
      vehicle_id: null,
      vehicle_label: null,
      vehicle_prefix: null,
      vehicle_model: null,
      vehicle_unit: null,
      vehicle_crew_id: null,
      crew_role: null,
      crew_status: null,
      vehicle_joined_at: null,
      updatedAt: now(),
    })
  );

  // Shift log: mark ended and clear vehicle fields
  await assertSucceeds(
    updateDoc(doc(db, 'shift_logs', 'shift-aux-1'), {
      status: 'ended',
      endedAt: now(),
      vehicle_id: null,
      vehicle_label: null,
      vehicle_prefix: null,
      vehicle_model: null,
      vehicle_unit: null,
      vehicle_crew_id: null,
      updatedAt: now(),
    })
  );

  console.log('[PASS] Scenario 1: Auxiliary/no-K9 endShift while in crew succeeds without touching parent crew doc');
}

// 2. Titular endShift while crew exists:
// Titular is authorized to close or update the parent vehicle_crews document
{
  await seedActiveCrewState();
  const db = dbFor(TITULAR_RA);

  // Titular member doc update
  await assertSucceeds(
    updateDoc(doc(db, 'vehicle_crews', CREW_ID, 'members', TITULAR_RA), {
      status: 'ended',
      left_at: now(),
      dog_id: deleteField(),
      updated_at: now(),
    })
  );

  // Titular is authorized to update parent crew doc
  await assertSucceeds(
    updateDoc(doc(db, 'vehicle_crews', CREW_ID), {
      active: false,
      ended_at: now(),
      service_dog_id: deleteField(),
      updated_at: now(),
    })
  );

  console.log('[PASS] Scenario 2: Titular endShift authorized to update parent vehicle_crews doc');
}

// 3. Auxiliary must NOT mutate parent vehicle_crews doc:
// Attempting to update parent vehicle_crews doc as auxiliary MUST receive PERMISSION_DENIED
{
  await seedActiveCrewState();
  const db = dbFor(AUXILIARY_RA);

  await assertFails(
    updateDoc(doc(db, 'vehicle_crews', CREW_ID), {
      active: false,
      ended_at: now(),
      service_dog_id: deleteField(),
      updated_at: now(),
    })
  );

  console.log('[PASS] Scenario 3: Auxiliary mutation of parent vehicle_crews doc is STRICTLY DENIED');
}

// 4. Member dog_id deletion via deleteField() is accepted by current Rules
{
  await seedActiveCrewState();
  const db = dbFor(TITULAR_RA);

  await assertSucceeds(
    updateDoc(doc(db, 'vehicle_crews', CREW_ID, 'members', TITULAR_RA), {
      status: 'ended',
      left_at: now(),
      dog_id: deleteField(),
      updated_at: now(),
    })
  );

  console.log('[PASS] Scenario 4: Member dog_id deletion (deleteField) is accepted by current Rules');
}

// 5. Normal manual leaveVehicle remains authorized
{
  await seedActiveCrewState();
  const db = dbFor(AUXILIARY_RA);

  // Auxiliary leaves vehicle manually
  await assertSucceeds(
    updateDoc(doc(db, 'vehicle_crews', CREW_ID, 'members', AUXILIARY_RA), {
      status: 'ended',
      left_at: now(),
      dog_id: deleteField(),
      updated_at: now(),
    })
  );
  await assertSucceeds(
    updateDoc(doc(db, 'active_shifts', AUXILIARY_RA), {
      vehicle_id: null,
      vehicle_label: null,
      vehicle_prefix: null,
      vehicle_model: null,
      vehicle_unit: null,
      vehicle_crew_id: null,
      crew_role: null,
      crew_status: null,
      vehicle_joined_at: null,
      updatedAt: now(),
    })
  );

  console.log('[PASS] Scenario 5: Normal manual leaveVehicle remains authorized');
}

// 6. Denied unauthorized mutations remain denied
{
  await seedActiveCrewState();

  // 6a: Non-member/third party cannot update another member's doc
  const dbThirdParty = dbFor(THIRD_PARTY_RA);
  await assertFails(
    updateDoc(doc(dbThirdParty, 'vehicle_crews', CREW_ID, 'members', AUXILIARY_RA), {
      status: 'ended',
      left_at: now(),
      dog_id: deleteField(),
      updated_at: now(),
    })
  );

  // 6b: Member cannot write dog_id: null (proves regression guard for the null vs deleteField bug)
  const dbAux = dbFor(AUXILIARY_RA);
  await assertFails(
    updateDoc(doc(dbAux, 'vehicle_crews', CREW_ID, 'members', AUXILIARY_RA), {
      status: 'ended',
      left_at: now(),
      dog_id: null,
      updated_at: now(),
    })
  );

  console.log('[PASS] Scenario 6: Unauthorized cross-user mutation and dog_id: null remain STRICTLY DENIED');
}

console.log('--- ALL F40.TC1 Shift & Crew Rules Tests (6/6) PASSED Successfully ---');
await testEnv.cleanup();
process.exit(0);
