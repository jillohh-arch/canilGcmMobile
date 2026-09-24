import * as assert from "assert";
import * as admin from "firebase-admin";
import {HttpsError} from "firebase-functions/v2/https";
import {
  buildAdminGetAccessHomologationSnapshotHandler,
  createAdminAccessHomologationSnapshotDeps,
} from "./admin_access_homologation_snapshot";

type JsonMap = Record<string, unknown>;

const projectId = "canil-gcm";
const requestData = {
  dogId: "DcUemulatorK9",
  excludedRa: "11231640",
  operatorProfileId: "operador_k9",
  targetRa: "61231640",
  temporaryProfileId: "operador_k9_homolog_ux05_weight",
};

function assertEmulatorsConfigured(): void {
  assert.ok(process.env.FIRESTORE_EMULATOR_HOST, "FIRESTORE_EMULATOR_HOST ausente");
  assert.ok(process.env.FIREBASE_AUTH_EMULATOR_HOST, "FIREBASE_AUTH_EMULATOR_HOST ausente");
  assert.strictEqual(process.env.GCLOUD_PROJECT, projectId, "GCLOUD_PROJECT inesperado");
}

function stable(value: unknown): unknown {
  if (value instanceof admin.firestore.Timestamp) return value.toDate().toISOString();
  if (Array.isArray(value)) return value.map(stable);
  if (value && typeof value === "object") {
    return Object.fromEntries(
      Object.entries(value as JsonMap)
        .sort(([left], [right]) => left.localeCompare(right))
        .map(([key, nested]) => [key, stable(nested)]),
    );
  }
  return value;
}

async function firestoreState(db: admin.firestore.Firestore): Promise<unknown> {
  const collections = (await db.listCollections())
    .map((collection) => collection.id)
    .sort();
  const state: JsonMap = {};
  for (const collection of collections) {
    const snapshot = await db.collection(collection).get();
    state[collection] = snapshot.docs
      .map((document) => ({
        data: stable(document.data()),
        id: document.id,
        updateTime: document.updateTime.toDate().toISOString(),
      }))
      .sort((left, right) => left.id.localeCompare(right.id));
  }
  return state;
}

async function authState(auth: admin.auth.Auth): Promise<unknown> {
  const result = await auth.listUsers(1000);
  return result.users
    .map((user) => ({
      customClaims: stable(user.customClaims ?? {}),
      disabled: user.disabled,
      email: user.email ?? null,
      uid: user.uid,
    }))
    .sort((left, right) => left.uid.localeCompare(right.uid));
}

async function createFixture(db: admin.firestore.Firestore, auth: admin.auth.Auth): Promise<void> {
  const users = [
    {ra: requestData.targetRa, uid: "emulator-target-uid"},
    {ra: requestData.excludedRa, uid: "emulator-excluded-uid"},
    {ra: "30000001", uid: "emulator-third-uid"},
    {ra: "40000001", uid: "emulator-fourth-uid"},
  ];
  for (const user of users) {
    await auth.createUser({email: `${user.ra}@gcm.com.br`, uid: user.uid});
    await auth.setCustomUserClaims(user.uid, {access_profile_id: requestData.operatorProfileId});
    await db.collection("users").doc(user.ra).set({
      access_profile_id: requestData.operatorProfileId,
      active: true,
      auth_uid: user.uid,
      role: "condutor",
    });
  }
  await db.collection("access_profiles").doc(requestData.operatorProfileId).set({
    active: true,
    permissions: {access: {view: true}, health: {view: true}},
    scope: "global",
    status: "active",
  });
  await db.collection("dogs").doc(requestData.dogId).set({
    active: true,
    handler_id: requestData.targetRa,
    status: "active",
  });
}

async function main(): Promise<void> {
  assertEmulatorsConfigured();
  admin.initializeApp({projectId});
  const db = admin.firestore();
  const auth = admin.auth();
  await createFixture(db, auth);

  const beforeFirestore = await firestoreState(db);
  const beforeAuth = await authState(auth);
  const handler = buildAdminGetAccessHomologationSnapshotHandler(
    createAdminAccessHomologationSnapshotDeps({
      auth,
      authorize: async (callAuth) => {
        if (!callAuth) throw new HttpsError("unauthenticated", "Autenticacao obrigatoria.");
        if (callAuth.token.admin !== true) {
          throw new HttpsError("permission-denied", "Administrador obrigatorio.");
        }
        return {ra: "90000001", uid: callAuth.uid};
      },
      correlationId: () => "emulator-correlation",
      db,
      now: () => new Date("2026-08-05T03:00:00.000Z"),
      projectId,
    }),
  );

  const response = await handler({
    auth: {token: {admin: true}, uid: "emulator-admin-uid"},
    data: requestData,
  });

  assert.strictEqual(response.hardGate.ready, true);
  assert.deepStrictEqual(response.hardGate.blockers, []);
  assert.strictEqual(response.operatorProfile.associationSummary.documentCount, 4);
  assert.strictEqual(response.operatorProfile.associationSummary.authEnabledCount, 4);
  assert.strictEqual(response.operatorProfile.associationSummary.claimCoherentCount, 4);
  assert.strictEqual(response.temporaryProfile.exists, false);
  assert.strictEqual(response.temporaryProfile.documentUpdateTime, null);
  assert.deepStrictEqual(response.targetUser.managedClaims, {
    accessProfileId: requestData.operatorProfileId,
    adminBypass: false,
  });
  assert.strictEqual(response.dogAccessEvaluation.reason, "global_scope");
  assert.ok(response.targetUser.documentUpdateTime);
  assert.ok(response.excludedUser.documentUpdateTime);
  assert.ok(response.operatorProfile.documentUpdateTime);
  assert.ok(response.dog.documentUpdateTime);
  assert.match(response.snapshotFingerprint, /^[A-F0-9]{64}$/);

  const serialized = JSON.stringify(response);
  assert.ok(!serialized.includes(requestData.targetRa));
  assert.ok(!serialized.includes(requestData.excludedRa));
  assert.ok(!serialized.includes("emulator-target-uid"));
  assert.ok(!serialized.includes("emulator-excluded-uid"));
  assert.ok(!serialized.includes("@gcm.com.br"));

  const afterFirestore = await firestoreState(db);
  const afterAuth = await authState(auth);
  assert.deepStrictEqual(afterFirestore, beforeFirestore, "a callable alterou o Firestore");
  assert.deepStrictEqual(afterAuth, beforeAuth, "a callable alterou Auth/claims");

  await db.collection("access_profiles").doc(requestData.temporaryProfileId).set({
    active: true,
    permissions: {health: {record_routine: true}},
    scope: "own_records",
    status: "active",
  });
  const beforeBlockedFirestore = await firestoreState(db);
  const beforeBlockedAuth = await authState(auth);
  const blockedResponse = await handler({
    auth: {token: {admin: true}, uid: "emulator-admin-uid"},
    data: requestData,
  });
  assert.strictEqual(blockedResponse.hardGate.ready, false);
  assert.ok(blockedResponse.hardGate.blockers.includes("temporary_profile_exists"));
  assert.strictEqual(blockedResponse.temporaryProfile.exists, true);
  assert.strictEqual(blockedResponse.temporaryProfile.recordRoutine.value, true);
  assert.deepStrictEqual(blockedResponse.temporaryProfile.permissions, {health: {record_routine: true}});
  assert.ok(blockedResponse.temporaryProfile.documentUpdateTime);
  assert.deepStrictEqual(
    await firestoreState(db),
    beforeBlockedFirestore,
    "a callable bloqueada alterou o Firestore",
  );
  assert.deepStrictEqual(
    await authState(auth),
    beforeBlockedAuth,
    "a callable bloqueada alterou Auth/claims",
  );
  console.log("ok - emulator: respostas pronta/bloqueada, mascaradas e estritamente read-only");
}

main()
  .then(() => process.exit(0))
  .catch((error: unknown) => {
    console.error("FAIL - emulator", error);
    process.exit(1);
  });
