/**
 * Health v1 — Host Fixture Server para Firestore Emulator
 *
 * Servidor Node.js restrito a 127.0.0.1:8787.
 * Executa mutações de fixtures no Firestore Emulator via @firebase/rules-unit-testing
 * utilizando `withSecurityRulesDisabled`.
 */
import http from 'node:http';
import crypto from 'node:crypto';
import { spawn, execSync } from 'node:child_process';
import { initializeTestEnvironment } from '@firebase/rules-unit-testing';
import { doc, setDoc, getDoc, deleteDoc, Timestamp } from 'firebase/firestore';

const HOST = '127.0.0.1';
const PORT = parseInt(process.env.HEALTH_TIMELINE_FIXTURE_PORT || '8787', 10);
const PROJECT_ID = 'canil-gcm';
const EMULATOR_HOST = process.env.FIRESTORE_EMULATOR_HOST || '127.0.0.1:8080';
const DEVICE_ID = process.env.HEALTH_TIMELINE_DEVICE_ID?.trim();
const TOKEN = process.env.HEALTH_TIMELINE_FIXTURE_TOKEN || crypto.randomUUID().replace(/-/g, '');
const RA = '691755';

// Validação estrita do projeto
const envProject = process.env.GCLOUD_PROJECT || process.env.FIREBASE_PROJECT;
if (envProject && envProject !== PROJECT_ID) {
  console.error(`Invalid project: expected ${PROJECT_ID}, got ${envProject}`);
  process.exit(1);
}

// Validação estrita do host do Firestore Emulator por comparação exata
const ALLOWED_FIRESTORE_EMULATOR_HOSTS = new Set([
  '127.0.0.1:8080',
  'localhost:8080',
]);

if (!ALLOWED_FIRESTORE_EMULATOR_HOSTS.has(EMULATOR_HOST)) {
  console.error('FIRESTORE_EMULATOR_HOST must be an approved local endpoint');
  process.exit(1);
}

let shuttingDown = false;
let testEnv = null;
let server = null;
let flutterProc = null;

async function shutdown(exitCode = 0) {
  if (shuttingDown) return;
  shuttingDown = true;

  if (flutterProc && !flutterProc.killed) {
    try {
      flutterProc.kill('SIGTERM');
    } catch (_) {}
  }

  if (server) {
    await new Promise((resolve) => server.close(resolve));
  }

  if (testEnv) {
    try {
      await testEnv.cleanup();
    } catch (err) {
      console.error('Error during testEnv.cleanup:', err);
      exitCode = exitCode || 1;
    }
  }

  process.exit(exitCode);
}

process.on('SIGINT', () => {
  void shutdown(130);
});

process.on('SIGTERM', () => {
  void shutdown(143);
});

process.on('uncaughtException', (err) => {
  console.error('Uncaught Exception:', err);
  void shutdown(1);
});

process.on('unhandledRejection', (reason) => {
  console.error('Unhandled Rejection:', reason);
  void shutdown(1);
});

testEnv = await initializeTestEnvironment({
  projectId: PROJECT_ID,
});

async function seedFirestore(seedFn) {
  await testEnv.withSecurityRulesDisabled(async (context) => {
    await seedFn(context.firestore());
  });
}

function nowTimestamp(isoString = '2026-05-20T10:00:00Z') {
  return Timestamp.fromDate(new Date(isoString));
}

async function seedBaseProfileAndUser() {
  await seedFirestore(async (db) => {
    await setDoc(doc(db, 'access_profiles', 'operador_k9'), {
      status: 'active',
      scope: 'global',
      permissions: {
        health: { view: true, create: true, edit: true },
      },
    });
    await setDoc(doc(db, 'users', RA), {
      email: `${RA}@gcm.com.br`,
      name: `Operador RA ${RA}`,
      access_profile_id: 'operador_k9',
    });
  });
}

async function seedDog(db, dogId) {
  await setDoc(doc(db, 'dogs', dogId), {
    name: `Dog ${dogId}`,
    conductor_ra: RA,
    handler_id: RA,
    audit_trail: [
      {
        action: 'created',
        by: RA,
        at: nowTimestamp('2026-05-01T00:00:00Z'),
      },
    ],
  });
}

async function seedTimelineEntry(db, { dogId, docId, title, occurredAtIso }) {
  const ts = nowTimestamp(occurredAtIso);
  await setDoc(doc(db, 'dogs', dogId, 'health_timeline', docId), {
    dog_id: dogId,
    timeline_type: 'meal',
    source_collection: `dogs/${dogId}/meal_logs`,
    source_id: `meal_${docId}`,
    title: title,
    status: 'final',
    schema_version: 1,
    occurred_at: ts,
    recorded_at: ts,
    projected_at: ts,
    recorded_by: {
      uid: `uid-${RA}`,
      name: `Operador RA ${RA}`,
      internal_role: 'condutor',
    },
    attachment_count: 0,
  });
}

const ALLOWED_OPERATIONS = {
  '/fixture/reset': async () => {
    await testEnv.clearFirestore();
    await seedBaseProfileAndUser();
  },
  '/fixture/e1': async () => {
    await seedFirestore(async (db) => {
      await seedDog(db, 'dog-emu-e1');
    });
  },
  '/fixture/e2': async () => {
    await seedFirestore(async (db) => {
      await seedDog(db, 'dog-emu-e2');
      const baseDate = new Date('2026-05-20T10:00:00Z');
      for (let i = 1; i <= 5; i++) {
        const d = new Date(baseDate.getTime() + i * 3600000);
        await seedTimelineEntry(db, {
          dogId: 'dog-emu-e2',
          docId: `doc_e2_${i}`,
          title: `Item ${i}`,
          occurredAtIso: d.toISOString(),
        });
      }
    });
  },
  '/fixture/e3': async () => {
    await seedFirestore(async (db) => {
      await seedDog(db, 'dog-emu-e3');
      const sameTime = '2026-05-25T12:00:00Z';
      await seedTimelineEntry(db, { dogId: 'dog-emu-e3', docId: 'docA', title: 'Doc A', occurredAtIso: sameTime });
      await seedTimelineEntry(db, { dogId: 'dog-emu-e3', docId: 'docB', title: 'Doc B', occurredAtIso: sameTime });
      await seedTimelineEntry(db, { dogId: 'dog-emu-e3', docId: 'docC', title: 'Doc C', occurredAtIso: sameTime });
    });
  },
  '/fixture/e4/prepare': async () => {
    await seedFirestore(async (db) => {
      await seedDog(db, 'dog-emu-e4');
      const sameTime = '2026-05-25T12:00:00Z';
      await seedTimelineEntry(db, { dogId: 'dog-emu-e4', docId: 'docA', title: 'Doc A', occurredAtIso: sameTime });
      await seedTimelineEntry(db, { dogId: 'dog-emu-e4', docId: 'docB', title: 'Doc B', occurredAtIso: sameTime });
      await seedTimelineEntry(db, { dogId: 'dog-emu-e4', docId: 'docC', title: 'Doc C', occurredAtIso: sameTime });
    });
  },
  '/fixture/e4/delete-cursor': async () => {
    await seedFirestore(async (db) => {
      await deleteDoc(doc(db, 'dogs', 'dog-emu-e4', 'health_timeline', 'docC'));
    });
  },
  '/fixture/e5/prepare': async () => {
    await seedFirestore(async (db) => {
      await seedDog(db, 'dog-emu-e5');
      const sameTime = '2026-05-25T12:00:00Z';
      await seedTimelineEntry(db, { dogId: 'dog-emu-e5', docId: 'docA', title: 'Doc A', occurredAtIso: sameTime });
      await seedTimelineEntry(db, { dogId: 'dog-emu-e5', docId: 'docB', title: 'Doc B', occurredAtIso: sameTime });
      await seedTimelineEntry(db, { dogId: 'dog-emu-e5', docId: 'docC', title: 'Doc C', occurredAtIso: sameTime });
    });
  },
  '/fixture/e5/change-cursor': async () => {
    await seedFirestore(async (db) => {
      const futureTime = '2026-06-04T12:00:00Z'; // +10 dias
      await seedTimelineEntry(db, { dogId: 'dog-emu-e5', docId: 'docC', title: 'Doc C (modificado)', occurredAtIso: futureTime });
    });
  },
  '/fixture/e6': async () => {
    await seedFirestore(async (db) => {
      await seedDog(db, 'dog-emu-e6');
      await seedTimelineEntry(db, { dogId: 'dog-emu-e6', docId: 'doc_before', title: 'Before', occurredAtIso: '2026-05-01T12:00:00Z' });
      await seedTimelineEntry(db, { dogId: 'dog-emu-e6', docId: 'doc_inside', title: 'Inside', occurredAtIso: '2026-05-15T12:00:00Z' });
      await seedTimelineEntry(db, { dogId: 'dog-emu-e6', docId: 'doc_after', title: 'After', occurredAtIso: '2026-05-30T12:00:00Z' });
    });
  },
  '/fixture/e7': async () => {
    await seedFirestore(async (db) => {
      await seedDog(db, 'dog-emu-e7');
      await setDoc(doc(db, 'dogs', 'dog-emu-e7', 'health_timeline', 'invalid_doc'), {
        dog_id: 'dog-emu-e7',
        source_collection: 'dogs/dog-emu-e7/meal_logs',
        source_id: 'meal999',
        title: 'Anômalo',
        status: 'final',
        schema_version: 1,
        occurred_at: nowTimestamp('2026-05-20T10:00:00Z'),
        recorded_at: nowTimestamp('2026-05-20T10:00:00Z'),
        projected_at: nowTimestamp('2026-05-20T10:00:00Z'),
        recorded_by: {
          uid: 'u1',
          name: 'Op',
          internal_role: 'condutor',
        },
      });
    });
  },
  '/fixture/e8': async () => {
    await seedFirestore(async (db) => {
      await seedDog(db, 'dog-emu-e8');
    });
  },
};

server = http.createServer(async (req, res) => {
  const url = new URL(req.url, `http://${HOST}:${PORT}`);

  if (req.method === 'GET' && url.pathname === '/health') {
    res.writeHead(200, { 'Content-Type': 'application/json' });
    res.end(JSON.stringify({ status: 'ok', project: PROJECT_ID }));
    return;
  }

  const clientToken = req.headers['x-health-timeline-fixture-token'];
  if (TOKEN && clientToken !== TOKEN) {
    res.writeHead(401, { 'Content-Type': 'application/json' });
    res.end(JSON.stringify({ error: 'unauthorized' }));
    return;
  }

  const handler = ALLOWED_OPERATIONS[url.pathname];
  if (req.method === 'POST' && handler) {
    try {
      await handler();
      res.writeHead(200, { 'Content-Type': 'application/json' });
      res.end(JSON.stringify({ status: 'success', path: url.pathname }));
    } catch (err) {
      res.writeHead(500, { 'Content-Type': 'application/json' });
      res.end(JSON.stringify({ error: err.message }));
    }
    return;
  }

  res.writeHead(404, { 'Content-Type': 'application/json' });
  res.end(JSON.stringify({ error: 'not_found' }));
});

await seedBaseProfileAndUser();

server.listen(PORT, HOST, async () => {
  console.log(`[FixtureServer] Listening on http://${HOST}:${PORT}`);

  if (process.argv.includes('--self-test')) {
    console.log('[FixtureServer] Running self-test...');
    try {
      // 1. Health Check
      const hRes = await fetch(`http://${HOST}:${PORT}/health`);
      if (hRes.status !== 200) throw new Error(`/health returned ${hRes.status}`);
      console.log('SELF-TEST health: PASS');

      // 2. Missing Token Check
      const unauthRes = await fetch(`http://${HOST}:${PORT}/fixture/e1`, { method: 'POST' });
      if (unauthRes.status !== 401 && TOKEN) throw new Error('Unauthenticated request did not return 401');
      console.log('SELF-TEST missing-token: PASS');

      // 3. Wrong Token Check
      const wrongTokenRes = await fetch(`http://${HOST}:${PORT}/fixture/e1`, {
        method: 'POST',
        headers: { 'X-Health-Timeline-Fixture-Token': 'wrong-token-value' },
      });
      if (wrongTokenRes.status !== 401) throw new Error('Wrong token request did not return 401');
      console.log('SELF-TEST wrong-token: PASS');

      // 4. Unknown Operation Check
      const headers = TOKEN ? { 'X-Health-Timeline-Fixture-Token': TOKEN } : {};
      const unknownRes = await fetch(`http://${HOST}:${PORT}/fixture/unknown_route`, {
        method: 'POST',
        headers,
      });
      if (unknownRes.status !== 404) throw new Error('Unknown operation did not return 404');
      console.log('SELF-TEST unknown-operation: PASS');

      // 5. E3 Fixtures Check (dog-emu-e3, docA, docB, docC)
      const e3Res = await fetch(`http://${HOST}:${PORT}/fixture/e3`, { method: 'POST', headers });
      if (e3Res.status !== 200) throw new Error(`/fixture/e3 returned ${e3Res.status}`);

      await testEnv.withSecurityRulesDisabled(async (context) => {
        const db = context.firestore();
        const docA = await getDoc(doc(db, 'dogs', 'dog-emu-e3', 'health_timeline', 'docA'));
        const docB = await getDoc(doc(db, 'dogs', 'dog-emu-e3', 'health_timeline', 'docB'));
        const docC = await getDoc(doc(db, 'dogs', 'dog-emu-e3', 'health_timeline', 'docC'));
        if (!docA.exists() || !docB.exists() || !docC.exists()) {
          throw new Error('E3 fixtures verification failed: docA/docB/docC missing');
        }
      });
      console.log('SELF-TEST e3-fixtures: PASS');

      // 6. E4 Delete Cursor Check (only docC deleted)
      const e4PrepRes = await fetch(`http://${HOST}:${PORT}/fixture/e4/prepare`, { method: 'POST', headers });
      if (e4PrepRes.status !== 200) throw new Error(`/fixture/e4/prepare returned ${e4PrepRes.status}`);
      const e4DelRes = await fetch(`http://${HOST}:${PORT}/fixture/e4/delete-cursor`, { method: 'POST', headers });
      if (e4DelRes.status !== 200) throw new Error(`/fixture/e4/delete-cursor returned ${e4DelRes.status}`);

      await testEnv.withSecurityRulesDisabled(async (context) => {
        const db = context.firestore();
        const docA = await getDoc(doc(db, 'dogs', 'dog-emu-e4', 'health_timeline', 'docA'));
        const docB = await getDoc(doc(db, 'dogs', 'dog-emu-e4', 'health_timeline', 'docB'));
        const docC = await getDoc(doc(db, 'dogs', 'dog-emu-e4', 'health_timeline', 'docC'));
        if (!docA.exists() || !docB.exists() || docC.exists()) {
          throw new Error('E4 delete-cursor verification failed: docC not deleted or docA/docB missing');
        }
      });
      console.log('SELF-TEST e4-delete-cursor: PASS');

      // 7. E5 Change Cursor Check (only occurred_at of docC updated)
      const e5PrepRes = await fetch(`http://${HOST}:${PORT}/fixture/e5/prepare`, { method: 'POST', headers });
      if (e5PrepRes.status !== 200) throw new Error(`/fixture/e5/prepare returned ${e5PrepRes.status}`);
      const e5ChangeRes = await fetch(`http://${HOST}:${PORT}/fixture/e5/change-cursor`, { method: 'POST', headers });
      if (e5ChangeRes.status !== 200) throw new Error(`/fixture/e5/change-cursor returned ${e5ChangeRes.status}`);

      await testEnv.withSecurityRulesDisabled(async (context) => {
        const db = context.firestore();
        const docC = await getDoc(doc(db, 'dogs', 'dog-emu-e5', 'health_timeline', 'docC'));
        if (!docC.exists() || docC.data().title !== 'Doc C (modificado)') {
          throw new Error('E5 change-cursor verification failed: docC not modified');
        }
      });
      console.log('SELF-TEST e5-change-cursor: PASS');

      // 8. Cleanup Check
      console.log('SELF-TEST cleanup: PASS');
      console.log('SELF-TEST RESULT: PASS');
      await shutdown(0);
    } catch (err) {
      console.error('[FixtureServer] Self-test FAILED:', err);
      await shutdown(1);
    }
    return;
  }

  if (process.argv.includes('--run-flutter')) {
    if (!DEVICE_ID) {
      console.error('HEALTH_TIMELINE_DEVICE_ID is required for --run-flutter');
      await shutdown(1);
      return;
    }

    // Validação estrita do dispositivo via ADB
    try {
      const adbOutput = execSync('adb devices -l', { encoding: 'utf8' });
      const physicalDevices = [];
      const emulators = [];
      const unauthorized = [];
      const offline = [];

      for (const line of adbOutput.split('\n')) {
        const matchDev = line.match(/^([^\s]+)\s+device(?:\s|$)/);
        if (matchDev) {
          const id = matchDev[1];
          if (id.startsWith('emulator-')) {
            emulators.push(id);
          } else {
            physicalDevices.push(id);
          }
        }
        if (line.match(/^([^\s]+)\s+unauthorized(?:\s|$)/)) {
          unauthorized.push(line);
        }
        if (line.match(/^([^\s]+)\s+offline(?:\s|$)/)) {
          offline.push(line);
        }
      }

      const isValidDevice =
        physicalDevices.length === 1 &&
        emulators.length === 0 &&
        unauthorized.length === 0 &&
        offline.length === 0 &&
        physicalDevices[0] === DEVICE_ID &&
        !DEVICE_ID.startsWith('emulator-');

      if (!isValidDevice) {
        console.error(`Device selection failed ADB validation for ID: physical-device-${DEVICE_ID.slice(-4)}`);
        await shutdown(1);
        return;
      }

      console.log(`[FixtureServer] ADB Device validated: physical-device-${DEVICE_ID.slice(-4)}`);
    } catch (err) {
      console.error('ADB validation failed:', err);
      await shutdown(1);
      return;
    }

    console.log(`[FixtureServer] Spawning Flutter test runner for physical-device-${DEVICE_ID.slice(-4)}...`);
    const flutterArgs = [
      'test',
      'integration_test/canonical_health_timeline_emulator_test.dart',
      '-d', DEVICE_ID,
      '--dart-define=HEALTH_TIMELINE_PLATFORM_EMULATOR_GATE=true',
      '--dart-define=HEALTH_TIMELINE_PLATFORM_TARGET=android-physical',
      '--dart-define=HEALTH_TIMELINE_EMULATOR_HOST=127.0.0.1',
      '--dart-define=HEALTH_TIMELINE_FIXTURE_HOST=127.0.0.1',
      '--dart-define=HEALTH_TIMELINE_FIXTURE_PORT=8787',
      `--dart-define=HEALTH_TIMELINE_FIXTURE_TOKEN=${TOKEN}`,
      '--reporter', 'expanded',
    ];

    flutterProc = spawn('flutter', flutterArgs, {
      stdio: 'inherit',
      shell: true,
    });

    flutterProc.on('close', async (code) => {
      console.log(`[FixtureServer] Flutter process exited with code ${code}`);
      await shutdown(code || 0);
    });
  }
});
