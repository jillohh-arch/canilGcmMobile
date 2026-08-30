/**
 * Transporte real do relógio autoritativo:
 * Auth Emulator + Functions Emulator + cliente Firebase httpsCallable.
 *
 * A callable é read-only; o teste compara todos os paths Firestore antes/depois.
 */
import assert from "node:assert/strict";
import {
  initializeApp as initializeAdminApp,
  deleteApp as deleteAdminApp,
  getApps as getAdminApps,
} from "firebase-admin/app";
import {getAuth as getAdminAuth} from "firebase-admin/auth";
import {getFirestore as getAdminFirestore} from "firebase-admin/firestore";
import {initializeApp, deleteApp as deleteClientApp} from "firebase/app";
import {
  connectAuthEmulator,
  getAuth,
  signInWithEmailAndPassword,
  signOut,
} from "firebase/auth";
import {
  connectFunctionsEmulator,
  getFunctions,
  httpsCallable,
} from "firebase/functions";

const PROJECT_ID = process.env.GCLOUD_PROJECT || "canil-gcm";
const REGION = "southamerica-east1";
const AUTH_HOST = process.env.FIREBASE_AUTH_EMULATOR_HOST || "127.0.0.1:9099";
const FUNCTIONS_HOST = process.env.FUNCTIONS_EMULATOR_HOST || "127.0.0.1:5001";
const EMAIL = "authoritative-time-emulator@example.test";
const PASSWORD = "Authoritative-Time-Emulator-Only!";

function hostAndPort(value) {
  const [host, port] = String(value).replace(/^https?:\/\//, "").split(":");
  return {host, port: Number(port)};
}

async function collectCollection(collection, output) {
  const snapshot = await collection.get();
  for (const document of snapshot.docs) {
    output.push(document.ref.path);
    for (const child of await document.ref.listCollections()) {
      await collectCollection(child, output);
    }
  }
}

async function firestoreDocumentPaths(db) {
  const output = [];
  for (const collection of await db.listCollections()) {
    await collectCollection(collection, output);
  }
  return output.sort();
}

assert.ok(process.env.FIREBASE_AUTH_EMULATOR_HOST, "Auth Emulator obrigatório.");
assert.ok(process.env.FIRESTORE_EMULATOR_HOST, "Firestore Emulator obrigatório.");

const adminApp = getAdminApps().length > 0 ? getAdminApps()[0] : initializeAdminApp({projectId: PROJECT_ID});
const adminAuth = getAdminAuth(adminApp);
const adminDb = getAdminFirestore(adminApp);
const beforePaths = await firestoreDocumentPaths(adminDb);

let user;
try {
  user = await adminAuth.createUser({email: EMAIL, password: PASSWORD});
} catch (error) {
  if (error?.code !== "auth/email-already-exists") throw error;
  user = await adminAuth.getUserByEmail(EMAIL);
}

const clientApp = initializeApp(
  {projectId: PROJECT_ID, apiKey: "fake-api-key", appId: "1:fake:web:authoritative-time"},
  "authoritative-time-emulator-client",
);
const auth = getAuth(clientApp);
const authEndpoint = hostAndPort(AUTH_HOST);
connectAuthEmulator(auth, `http://${authEndpoint.host}:${authEndpoint.port}`, {disableWarnings: true});
const functions = getFunctions(clientApp, REGION);
const functionsEndpoint = hostAndPort(FUNCTIONS_HOST);
connectFunctionsEmulator(functions, functionsEndpoint.host, functionsEndpoint.port);
const callable = httpsCallable(functions, "systemAuthoritativeTimeNow");

await assert.rejects(
  () => callable({protocol_version: 1}),
  (error) => String(error?.code).includes("unauthenticated"),
);

await signInWithEmailAndPassword(auth, EMAIL, PASSWORD);
const result = await callable({protocol_version: 1});
const payload = result.data;

assert.deepStrictEqual(Object.keys(payload).sort(), [
  "max_age_ms",
  "protocol_version",
  "request_id",
  "request_received_at_utc_ms",
  "server_sent_at_utc_ms",
]);
assert.equal(payload.protocol_version, 1);
assert.equal(payload.max_age_ms, 900000);
assert.equal(typeof payload.request_id, "string");
assert.ok(payload.request_id.length > 0);
assert.ok(Number.isInteger(payload.request_received_at_utc_ms));
assert.ok(Number.isInteger(payload.server_sent_at_utc_ms));
assert.ok(payload.server_sent_at_utc_ms >= payload.request_received_at_utc_ms);

await assert.rejects(
  () => callable({protocol_version: 2}),
  (error) => String(error?.code).includes("invalid-argument"),
);

const afterPaths = await firestoreDocumentPaths(adminDb);
assert.deepStrictEqual(afterPaths, beforePaths, "Callable não pode criar/alterar documentos Firestore.");

await signOut(auth);
await adminAuth.deleteUser(user.uid);
await deleteClientApp(clientApp);
await deleteAdminApp(adminApp);

console.log("system_authoritative_time_callable_emulator_tests: ok");
