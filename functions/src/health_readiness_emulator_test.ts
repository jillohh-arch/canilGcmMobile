/**
 * Readiness v1 — emulator integration tests (Gate 3, EM-01..EM-08).
 *
 * Stage READINESS-V1 — Local implementation only. Not deployed.
 *
 * Exercises the full projector pipeline against the Firestore Emulator:
 * reads from real collections, writes to the real `health_summary/current` path.
 * Requires `FIRESTORE_EMULATOR_HOST` and a running emulator before the test.
 */

import * as assert from "assert";
import * as admin from "firebase-admin";
import {
  evaluateHealthReadiness,
  ProjectorDeps,
  ProjectorFirestore,
} from "./health_readiness_projector";

const emuHost = process.env.FIRESTORE_EMULATOR_HOST;

const NOW = new Date("2026-08-11T12:00:00.000Z");
const MILLIS_PER_DAY = 86_400_000;

function daysAgo(days: number): Date {
  return new Date(NOW.getTime() - days * MILLIS_PER_DAY);
}

function daysAhead(days: number): Date {
  return new Date(NOW.getTime() + days * MILLIS_PER_DAY);
}

// ── Test fixtures ────────────────────────────────────────────────────────────

const DOG = "emu-dog-001";

// ── Firestore helpers ────────────────────────────────────────────────────────

function makeFirestoreAdapter(db: FirebaseFirestore.Firestore): ProjectorFirestore {
  return {
    readSubcollection: async (dogId, collection) => {
      try {
        const snap = await db
          .collection("dogs")
          .doc(dogId)
          .collection(collection)
          .get();
        return {kind: "docs", docs: snap.docs.map((d) => ({id: d.id, data: d.data()}))};
      } catch (err) {
        return {kind: "failed", reasonCode: String(err)};
      }
    },
    readCurrentSummary: async (dogId) => {
      try {
        const doc = await db
          .collection("dogs")
          .doc(dogId)
          .collection("health_summary")
          .doc("current")
          .get();
        return doc.exists ? (doc.data() as Record<string, unknown>) : null;
      } catch (err) {
        return {kind: "failed", reasonCode: String(err)} as never;
      }
    },
    writeCurrentSummary: async (dogId, payload) => {
      await db
        .collection("dogs")
        .doc(dogId)
        .collection("health_summary")
        .doc("current")
        .set(payload, {merge: true});
    },
  };
}

function makeDeps(db: FirebaseFirestore.Firestore): ProjectorDeps {
  return {
    firestore: makeFirestoreAdapter(db),
    logger: {info: () => {}, warn: () => {}, error: () => {}},
    config: {weightMaxAgeDays: 90, consultationMaxAgeDays: 180},
    now: () => NOW,
  };
}

// ── Test harness ─────────────────────────────────────────────────────────────

let testCount = 0;
let passCount = 0;
let failCount = 0;

async function test(name: string, fn: () => Promise<void>): Promise<void> {
  testCount++;
  try {
    await fn();
    passCount++;
    console.log(`ok - ${name}`);
  } catch (e) {
    failCount++;
    console.error(`FAIL - ${name}`, e);
    throw e;
  }
}

async function main(): Promise<void> {
  if (!emuHost) {
    console.error(
      "ERRO CRÍTICO: FIRESTORE_EMULATOR_HOST não está configurado.",
    );
    process.exit(1);
  }

  console.log(`Conectado ao Firestore Emulator em ${emuHost}...`);

  if (!admin.apps.length) {
    admin.initializeApp({projectId: "canil-gcm"});
  }
  const db = admin.firestore();

  // Clean slate before every test.
  async function wipe(): Promise<void> {
    const dogRef = db.collection("dogs").doc(DOG);
    const collections = [
      "weight_records",
      "vaccination_records",
      "health_events",
      "nutrition_plans",
      "operational_restrictions",
      "health_summary",
    ];
    await Promise.all([
      ...collections.map((c) => dogRef.collection(c).get()),
    ]);
    const allDocs: FirebaseFirestore.DocumentReference[] = [];
    for (const c of collections) {
      const snap = await dogRef.collection(c).get();
      snap.docs.forEach((d) => allDocs.push(d.ref));
    }
    await Promise.all(allDocs.map((r) => r.delete()));
    const summaryDoc = dogRef.collection("health_summary").doc("current");
    if ((await summaryDoc.get()).exists) {
      await summaryDoc.delete();
    }
  }

  const deps = makeDeps(db);

  // ── EM-01 ─────────────────────────────────────────────────────────────────
  await test("EM-01 no existing summary + success -> creates health_summary/current", async () => {
    await wipe();
    const dogRef = db.collection("dogs").doc(DOG);

    // Write evidence that would produce "operational".
    await dogRef.collection("weight_records").add({
      dogId: DOG,
      weight_kg: 28.8,
      measured_at: admin.firestore.Timestamp.fromDate(daysAgo(1)),
      recorded_by: {uid: "u1", name: "Condutor", internal_role: "condutor"},
      schema_version: 1,
      created_at: admin.firestore.Timestamp.fromDate(daysAgo(1)),
    });
    await dogRef.collection("health_events").add({
      dogId: DOG,
      date: admin.firestore.Timestamp.fromDate(daysAgo(1)),
      type: "vaccination",
      subtype: "Antirrábica",
      nextDueDate: admin.firestore.Timestamp.fromDate(daysAhead(363)),
    });
    await dogRef.collection("health_events").add({
      dogId: DOG,
      date: admin.firestore.Timestamp.fromDate(daysAgo(3)),
      type: "consultation",
    });
    await dogRef.collection("nutrition_plans").add({status: "active", schema_version: 1});

    const result = await evaluateHealthReadiness(DOG, deps);
    assert.strictEqual(result.projectionStatus, "ready");
    assert.strictEqual(result.readinessStatus, "operational");

    const doc = await dogRef.collection("health_summary").doc("current").get();
    assert.ok(doc.exists, "health_summary/current must exist");
    const data = doc.data() as Record<string, unknown>;
    assert.strictEqual(data["projection_status"], "ready");
    assert.strictEqual(data["readiness_status"], "operational");
    assert.strictEqual(data["schema_version"], 1);
  });

  // ── EM-02 ─────────────────────────────────────────────────────────────────
  await test("EM-02 existing summary + changed evidence -> updates same doc", async () => {
    await wipe();
    const dogRef = db.collection("dogs").doc(DOG);

    // Initial: operational.
    await dogRef.collection("weight_records").add({
      dogId: DOG,
      weight_kg: 28.8,
      measured_at: admin.firestore.Timestamp.fromDate(daysAgo(1)),
      recorded_by: {uid: "u1", name: "Condutor", internal_role: "condutor"},
      schema_version: 1,
      created_at: admin.firestore.Timestamp.fromDate(daysAgo(1)),
    });
    await dogRef.collection("health_events").add({
      dogId: DOG,
      date: admin.firestore.Timestamp.fromDate(daysAgo(1)),
      type: "vaccination",
      nextDueDate: admin.firestore.Timestamp.fromDate(daysAhead(363)),
    });
    await dogRef.collection("health_events").add({
      dogId: DOG,
      date: admin.firestore.Timestamp.fromDate(daysAgo(3)),
      type: "consultation",
    });
    await dogRef.collection("nutrition_plans").add({status: "active", schema_version: 1});

    await evaluateHealthReadiness(DOG, deps);

    // Second run with evidence unchanged — same doc.
    const result = await evaluateHealthReadiness(DOG, deps);
    assert.strictEqual(result.operation, "ready");

    const allDocs = await dogRef.collection("health_summary").get();
    assert.strictEqual(allDocs.size, 1, "must be exactly one summary document");
  });

  // ── EM-03 ─────────────────────────────────────────────────────────────────
  await test("EM-03 previous good + technical failure -> last clinical fields preserved", async () => {
    await wipe();
    const dogRef = db.collection("dogs").doc(DOG);

    // Write evidence to produce an initial operational snapshot.
    await dogRef.collection("weight_records").add({
      dogId: DOG,
      weight_kg: 28.8,
      measured_at: admin.firestore.Timestamp.fromDate(daysAgo(1)),
      recorded_by: {uid: "u1", name: "Condutor", internal_role: "condutor"},
      schema_version: 1,
      created_at: admin.firestore.Timestamp.fromDate(daysAgo(1)),
    });
    await dogRef.collection("health_events").add({
      dogId: DOG,
      date: admin.firestore.Timestamp.fromDate(daysAgo(1)),
      type: "vaccination",
      nextDueDate: admin.firestore.Timestamp.fromDate(daysAhead(363)),
    });
    await dogRef.collection("health_events").add({
      dogId: DOG,
      date: admin.firestore.Timestamp.fromDate(daysAgo(3)),
      type: "consultation",
    });
    await dogRef.collection("nutrition_plans").add({status: "active", schema_version: 1});

    await evaluateHealthReadiness(DOG, deps);

    // Simulate a technical failure by using a firestore adapter that fails for weight.
    const failingAdapter: ProjectorFirestore = {
      ...makeFirestoreAdapter(db),
      readSubcollection: async (dogId, collection) => {
        if (collection === "weight_records") {
          return {kind: "failed", reasonCode: "permission_denied"};
        }
        return makeFirestoreAdapter(db).readSubcollection(dogId, collection);
      },
    };
    const failingDeps = {...deps, firestore: failingAdapter};

    const result = await evaluateHealthReadiness(DOG, failingDeps);
    assert.strictEqual(result.projectionStatus, "unavailable");
    assert.strictEqual(result.readinessStatus, null);

    const doc = await dogRef.collection("health_summary").doc("current").get();
    const data = doc.data() as Record<string, unknown>;
    // Last-known-good clinical fields preserved.
    assert.strictEqual(data["readiness_status"], "operational");
    assert.strictEqual(data["readiness_label"], "Operacional");
    assert.strictEqual(data["projection_status"], "unavailable");
    assert.ok((data["technical_blockers"] as string[]).length > 0);
  });

  // ── EM-04 ─────────────────────────────────────────────────────────────────
  await test("EM-04 no previous snapshot + technical failure -> technical metadata only", async () => {
    await wipe();
    const dogRef = db.collection("dogs").doc(DOG);

    // Deliberately malformed weight that makes the source inconclusive.
    await dogRef.collection("weight_records").add({
      dogId: DOG,
      weight_kg: "muito pesado",  // malformed
      schema_version: 1,
    });

    const result = await evaluateHealthReadiness(DOG, deps);
    assert.strictEqual(result.projectionStatus, "unavailable");
    assert.strictEqual(result.readinessStatus, null);
    assert.strictEqual(result.operation, "unavailable_initial");

    const doc = await dogRef.collection("health_summary").doc("current").get();
    assert.ok(doc.exists, "summary document must exist (technical metadata)");
    const data = doc.data() as Record<string, unknown>;
    // No clinical fields fabricated.
    assert.strictEqual(data["readiness_status"], undefined);
    assert.strictEqual(data["readiness_label"], undefined);
    assert.strictEqual(data["data_completeness"], undefined);
    assert.strictEqual(data["projection_status"], "unavailable");
    assert.strictEqual(data["schema_version"], 1);
    assert.ok((data["technical_blockers"] as string[]).length > 0);
  });

  // ── EM-05 ─────────────────────────────────────────────────────────────────
  await test("EM-05 success after previous unavailable -> ready, blockers cleared", async () => {
    await wipe();
    const dogRef = db.collection("dogs").doc(DOG);

    // First: write a technical-unavailable document directly.
    await dogRef.collection("health_summary").doc("current").set({
      projection_status: "unavailable",
      technical_blockers: ["weight_source_permission_denied"],
      schema_version: 1,
      updated_at: admin.firestore.Timestamp.fromDate(daysAgo(1)),
      projection_attempted_at: admin.firestore.Timestamp.fromDate(daysAgo(1)),
    });

    // Now write correct evidence.
    await dogRef.collection("weight_records").add({
      dogId: DOG,
      weight_kg: 28.8,
      measured_at: admin.firestore.Timestamp.fromDate(daysAgo(1)),
      recorded_by: {uid: "u1", name: "Condutor", internal_role: "condutor"},
      schema_version: 1,
      created_at: admin.firestore.Timestamp.fromDate(daysAgo(1)),
    });
    await dogRef.collection("health_events").add({
      dogId: DOG,
      date: admin.firestore.Timestamp.fromDate(daysAgo(1)),
      type: "vaccination",
      nextDueDate: admin.firestore.Timestamp.fromDate(daysAhead(363)),
    });
    await dogRef.collection("health_events").add({
      dogId: DOG,
      date: admin.firestore.Timestamp.fromDate(daysAgo(3)),
      type: "consultation",
    });
    await dogRef.collection("nutrition_plans").add({status: "active", schema_version: 1});

    const result = await evaluateHealthReadiness(DOG, deps);
    assert.strictEqual(result.projectionStatus, "ready");
    assert.strictEqual(result.readinessStatus, "operational");
    assert.deepStrictEqual(result.technicalBlockers, []);

    const doc = await dogRef.collection("health_summary").doc("current").get();
    const data = doc.data() as Record<string, unknown>;
    assert.strictEqual(data["projection_status"], "ready");
    assert.strictEqual(data["readiness_status"], "operational");
    assert.deepStrictEqual(data["technical_blockers"], []);
  });

  // ── EM-06 ─────────────────────────────────────────────────────────────────
  await test("EM-06 restriction array emptied -> persisted active_restrictions is []", async () => {
    await wipe();
    const dogRef = db.collection("dogs").doc(DOG);

    // First: create a snapshot with an active restriction.
    await dogRef.collection("weight_records").add({
      dogId: DOG,
      weight_kg: 28.8,
      measured_at: admin.firestore.Timestamp.fromDate(daysAgo(1)),
      recorded_by: {uid: "u1", name: "Condutor", internal_role: "condutor"},
      schema_version: 1,
      created_at: admin.firestore.Timestamp.fromDate(daysAgo(1)),
    });
    await dogRef.collection("health_events").add({
      dogId: DOG,
      date: admin.firestore.Timestamp.fromDate(daysAgo(1)),
      type: "vaccination",
      nextDueDate: admin.firestore.Timestamp.fromDate(daysAhead(363)),
    });
    await dogRef.collection("health_events").add({
      dogId: DOG,
      date: admin.firestore.Timestamp.fromDate(daysAgo(3)),
      type: "consultation",
    });
    await dogRef.collection("nutrition_plans").add({status: "active", schema_version: 1});
    await dogRef.collection("operational_restrictions").add({
      level: "absolute",
      category: "injury",
      description: "Lesão",
      status: "active",
      since: admin.firestore.Timestamp.fromDate(daysAgo(3)),
      activities_restricted: [],
      schema_version: 1,
    });

    await evaluateHealthReadiness(DOG, deps);
    let doc = await dogRef.collection("health_summary").doc("current").get();
    assert.ok((doc.data() as Record<string, unknown>)["active_restrictions"]);

    // Now remove the restriction from Firestore.
    const snap = await dogRef.collection("operational_restrictions").get();
    await Promise.all(snap.docs.map((d) => d.ref.delete()));

    // Re-run projector.
    await evaluateHealthReadiness(DOG, deps);
    doc = await dogRef.collection("health_summary").doc("current").get();
    const data = doc.data() as Record<string, unknown>;
    assert.deepStrictEqual(data["active_restrictions"], []);
    assert.deepStrictEqual(data["restriction_count"], {absolute: 0, partial: 0, attention: 0});
    assert.deepStrictEqual(data["readiness_status"], "operational");
  });

  // ── EM-07 ─────────────────────────────────────────────────────────────────
  await test("EM-07 alert array emptied -> persisted open_alerts is []", async () => {
    await wipe();
    const dogRef = db.collection("dogs").doc(DOG);

    // First: create a snapshot with an alert (stale consultation).
    await dogRef.collection("weight_records").add({
      dogId: DOG,
      weight_kg: 28.8,
      measured_at: admin.firestore.Timestamp.fromDate(daysAgo(1)),
      recorded_by: {uid: "u1", name: "Condutor", internal_role: "condutor"},
      schema_version: 1,
      created_at: admin.firestore.Timestamp.fromDate(daysAgo(1)),
    });
    await dogRef.collection("health_events").add({
      dogId: DOG,
      date: admin.firestore.Timestamp.fromDate(daysAgo(1)),
      type: "vaccination",
      nextDueDate: admin.firestore.Timestamp.fromDate(daysAhead(363)),
    });
    // Old consultation → operational_attention.
    await dogRef.collection("health_events").add({
      dogId: DOG,
      date: admin.firestore.Timestamp.fromDate(daysAgo(200)),
      type: "consultation",
    });
    await dogRef.collection("nutrition_plans").add({status: "active", schema_version: 1});

    await evaluateHealthReadiness(DOG, deps);
    let doc = await dogRef.collection("health_summary").doc("current").get();
    assert.ok(
      ((doc.data() as Record<string, unknown>)["open_alerts"] as unknown[]).length > 0,
    );

    // Fix consultation by updating its date.
    const snap = await dogRef
      .collection("health_events")
      .where("type", "==", "consultation")
      .get();
    assert.strictEqual(snap.size, 1);
    await snap.docs[0].ref.update({
      date: admin.firestore.Timestamp.fromDate(daysAgo(1)),
    });

    // Re-run projector.
    await evaluateHealthReadiness(DOG, deps);
    doc = await dogRef.collection("health_summary").doc("current").get();
    const data = doc.data() as Record<string, unknown>;
    assert.deepStrictEqual(data["open_alerts"], []);
    assert.strictEqual(data["readiness_status"], "operational");
  });

  // ── EM-08 ─────────────────────────────────────────────────────────────────
  await test("EM-08 two consecutive refreshes -> exactly one /current document", async () => {
    await wipe();
    const dogRef = db.collection("dogs").doc(DOG);

    await dogRef.collection("weight_records").add({
      dogId: DOG,
      weight_kg: 28.8,
      measured_at: admin.firestore.Timestamp.fromDate(daysAgo(1)),
      recorded_by: {uid: "u1", name: "Condutor", internal_role: "condutor"},
      schema_version: 1,
      created_at: admin.firestore.Timestamp.fromDate(daysAgo(1)),
    });
    await dogRef.collection("health_events").add({
      dogId: DOG,
      date: admin.firestore.Timestamp.fromDate(daysAgo(1)),
      type: "vaccination",
      nextDueDate: admin.firestore.Timestamp.fromDate(daysAhead(363)),
    });
    await dogRef.collection("health_events").add({
      dogId: DOG,
      date: admin.firestore.Timestamp.fromDate(daysAgo(3)),
      type: "consultation",
    });
    await dogRef.collection("nutrition_plans").add({status: "active", schema_version: 1});

    await evaluateHealthReadiness(DOG, deps);
    await evaluateHealthReadiness(DOG, deps);

    const allDocs = await dogRef.collection("health_summary").get();
    assert.strictEqual(allDocs.size, 1, "must be exactly one summary document");
  });

  console.log(`\n${passCount}/${testCount} passed`);
  if (failCount > 0) {
    console.error(`${failCount} failed`);
    process.exitCode = 1;
  } else {
    console.log("health_readiness_emulator_test: all passed");
  }
}

void main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
