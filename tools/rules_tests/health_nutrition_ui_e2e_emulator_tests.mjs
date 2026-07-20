import assert from 'node:assert/strict';
import {spawnSync} from 'node:child_process';
import {mkdirSync} from 'node:fs';
import {initializeApp, getApps} from 'firebase-admin/app';
import {getAuth} from 'firebase-admin/auth';
import {getFirestore, Timestamp} from 'firebase-admin/firestore';

const projectId = process.env.GCLOUD_PROJECT || 'canil-gcm';
for (const host of [process.env.FIREBASE_AUTH_EMULATOR_HOST, process.env.FIRESTORE_EMULATOR_HOST, '127.0.0.1:5001']) {
  assert.ok(String(host).includes('127.0.0.1') || String(host).includes('localhost'), `Emulator host obrigatório: ${host}`);
}
if (!getApps().length) initializeApp({projectId});
const db = getFirestore();
const auth = getAuth();
const suffix = Date.now();
const dogId = `dog-gate5c2a-${suffix}`;
const ra = `95${String(suffix).slice(-7)}`;
const email = `${ra}@canilgcm.com`;
const password = 'Gate5C2A-Emulator-Only!';
const uid = `uid-gate5c2a-${suffix}`;

await auth.createUser({uid, email, password, emailVerified: true});
await auth.setCustomUserClaims(uid, {
  ra,
  access_profile_id: 'gate5c2a_health',
  access_scope: 'global',
  role: 'condutor',
  app_access: ['web', 'mobile'],
  mobile_access: true,
});
await db.collection('access_profiles').doc('gate5c2a_health').set({
  status: 'active', scope: 'global', permissions: {health: {view: true, create: true, edit: true}},
});
await db.collection('users').doc(ra).set({
  email, name: 'Operador Gate 5C.2A', access_profile_id: 'gate5c2a_health', accessLevel: 'operador',
});
await db.collection('dogs').doc(dogId).set({name: 'Rex Emulator', conductor_ra: ra, active: true});
await db.collection('dogs').doc(dogId).collection('nutrition_plans').doc('plan-ui').set({
  dog_id: dogId, food_type: 'Ração E2E', amount_grams_per_day: 600, meals_per_day: 2,
  meal_schedule: [
    {id: 'slot-am', period: 'morning', scheduled_time: '08:00', target_grams: 300},
    {id: 'slot-pm', period: 'night', scheduled_time: '20:00', target_grams: 300},
  ],
  valid_from: Timestamp.fromDate(new Date('2020-01-01T00:00:00Z')), timezone: 'America/Sao_Paulo',
  status: 'active', recorded_by: {uid: 'seed', name: 'Seed E2E', internal_role: 'condutor'},
  created_at: Timestamp.now(), schema_version: 1, revision: 1,
});

const device = process.env.HEALTH_NUTRITION_E2E_DEVICE;
assert.ok(device && device !== 'windows', 'HEALTH_NUTRITION_E2E_DEVICE Android explícito é obrigatório');
for (const args of [
  ['shell', 'input', 'keyevent', '224'],
  ['shell', 'wm', 'dismiss-keyguard'],
  ['shell', 'svc', 'power', 'stayon', 'usb'],
]) {
  const wake = spawnSync('adb', ['-s', device, ...args], {stdio: 'inherit', shell: true});
  assert.equal(wake.status, 0, `adb ${args.join(' ')}`);
}
for (const port of [9099, 8080, 5001]) {
  const reverse = spawnSync('adb', ['-s', device, 'reverse', `tcp:${port}`, `tcp:${port}`], {stdio: 'inherit', shell: true});
  assert.equal(reverse.status, 0, `adb reverse ${port}`);
}
// B-01D: cmd.exe interpreta `&` nas entradas PATH do perfil como separador e
// remove os argumentos passados pelo Flutter ao gradlew.bat. O subprocesso E2E
// usa somente entradas executáveis que não contêm esse metacaractere.
const safePath = String(process.env.PATH || '').split(';').filter((entry) => entry && !entry.includes('&')).join(';');
const safeTemp = 'C:\\Temp\\gate5c2a-flutter';
mkdirSync(safeTemp, {recursive: true});
const env = {...process.env, PATH: safePath, Path: safePath, TEMP: safeTemp, TMP: safeTemp, HEALTH_NUTRITION_UI_E2E: '1', HEALTH_NUTRITION_E2E_DOG: dogId,
  HEALTH_NUTRITION_E2E_EMAIL: email, HEALTH_NUTRITION_E2E_PASSWORD: password};
console.log(`PLUGIN_E2E_TOPOLOGY project=${projectId} auth=127.0.0.1:9099 firestore=127.0.0.1:8080 functions=127.0.0.1:5001 device=${device} routing=adb-reverse`);
assert.equal(env.Path.includes('&'), false, 'PATH do runner deve ser cmd-safe');
const run = spawnSync('C:\\flutter\\bin\\cache\\dart-sdk\\bin\\dart.exe', [
  'C:\\flutter\\bin\\cache\\flutter_tools.snapshot', 'drive',
  '--driver=test_driver/integration_test.dart',
  '--target=integration_test/health_nutrition_planned_meal_emulator_test.dart',
  '-d', device, '--no-dds',
  '--dart-define=HEALTH_NUTRITION_UI_E2E=true',
  `--dart-define=HEALTH_NUTRITION_E2E_DOG=${dogId}`,
  `--dart-define=HEALTH_NUTRITION_E2E_EMAIL=${email}`,
  `--dart-define=HEALTH_NUTRITION_E2E_PASSWORD=${password}`,
  '-v',
],
  {cwd: process.cwd(), env, stdio: 'inherit', shell: false});
if (run.error) console.error(run.error);
assert.equal(run.status, 0, 'Flutter plugin E2E deve passar');

const meals = await db.collection('dogs').doc(dogId).collection('meal_logs').get();
const ops = await db.collection('dogs').doc(dogId).collection('nutrition_operations').get();
const audits = await db.collection('auditLogs').where('entity_id', '==', meals.docs[0].id).get();
assert.equal(meals.size, 1); assert.equal(ops.size, 1); assert.equal(audits.size, 1);
assert.equal((await db.collection('dogs').doc(dogId).collection('feeding_events').get()).size, 0);
assert.equal((await db.collection('dogs').doc(dogId).collection('feedings').get()).size, 0);
console.log(`GATE5C2A_PLUGIN_E2E_OK meals=${meals.size} ops=${ops.size} audits=${audits.size} legacy=0`);
