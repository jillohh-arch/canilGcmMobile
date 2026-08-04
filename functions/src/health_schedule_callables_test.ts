/**
 * Testes de handlers com fake Firestore (transaction + operations subcollection).
 * npm run build && node lib/health_schedule_callables_test.js
 */
import * as assert from "assert";
import * as crypto from "crypto";
import {
  runHealthScheduleCancel,
  runHealthScheduleComplete,
  runHealthScheduleCreateManual,
  runHealthScheduleUpdateOpen,
  HealthScheduleCallableDeps,
  ScheduleCaller,
} from "./health_schedule_callables";
import {
  createIdempotencyMaterial,
  deterministicManualScheduleId,
} from "./health_schedule_logic";

type JsonMap = Record<string, unknown>;

const actor: ScheduleCaller = {
  uid: "uid-op",
  email: "691755@gcm.com.br",
  ra: "691755",
  name: "Operador",
};

const actorB: ScheduleCaller = {
  uid: "uid-op-b",
  email: "691756@gcm.com.br",
  ra: "691756",
  name: "Operador B",
};

const adminActor: ScheduleCaller = {
  uid: "uid-admin",
  email: "1@gcm.com.br",
  ra: "1",
  name: "Admin",
};

function createFakeDb(initial: Record<string, JsonMap> = {}) {
  const store = new Map<string, JsonMap>();
  for (const [k, v] of Object.entries(initial)) {
    store.set(k, {...v});
  }

  function pathOf(parts: string[]): string {
    return parts.join("/");
  }

  function makeDocRef(parts: string[]) {
    const path = pathOf(parts);
    return {
      path,
      id: parts[parts.length - 1],
      collection(c: string) {
        return {
          doc(id: string) {
            return makeDocRef([...parts, c, id]);
          },
        };
      },
      async get() {
        const data = store.get(path);
        return {
          exists: data !== undefined,
          data: () => ({...(data ?? {})}),
        };
      },
    };
  }

  const db = {
    collection(col: string) {
      return {
        doc(id?: string) {
          const docId = id ?? `auto_${store.size + 1}`;
          return makeDocRef([col, docId]);
        },
      };
    },
    async runTransaction<T>(
      fn: (tx: {
        get: (ref: {path: string}) => Promise<{exists: boolean; data: () => JsonMap}>;
        set: (ref: {path: string}, data: JsonMap) => void;
        update: (ref: {path: string}, data: JsonMap) => void;
      }) => Promise<T>,
    ): Promise<T> {
      const pending = new Map<string, JsonMap>();
      const tx = {
        async get(ref: {path: string}) {
          const data = pending.get(ref.path) ?? store.get(ref.path);
          return {
            exists: data !== undefined,
            data: () => ({...(data ?? {})}),
          };
        },
        set(ref: {path: string}, data: JsonMap) {
          pending.set(ref.path, {...data});
        },
        update(ref: {path: string}, data: JsonMap) {
          const base = pending.get(ref.path) ?? store.get(ref.path) ?? {};
          const next = {...base};
          for (const [k, v] of Object.entries(data)) {
            if (v && typeof v === "object") {
              const m =
                (v as {_methodName?: string; methodName?: string})._methodName ??
                (v as {methodName?: string}).methodName;
              if (m && String(m).toLowerCase().includes("delete")) {
                delete next[k];
                continue;
              }
              if (m && String(m).toLowerCase().includes("servertimestamp")) {
                next[k] = {seconds: Date.now() / 1000};
                continue;
              }
            }
            next[k] = v;
          }
          pending.set(ref.path, next);
        },
      };
      const result = await fn(tx);
      for (const [k, v] of pending.entries()) {
        store.set(k, v);
      }
      return result;
    },
    _store: store,
  };

  return db as unknown as FirebaseFirestore.Firestore & {
    _store: Map<string, JsonMap>;
  };
}

// eslint-disable-next-line @typescript-eslint/no-explicit-any
function mockRequest(data: JsonMap, auth: any): any {
  return {data, auth};
}

function depsFor(options: {
  db: FirebaseFirestore.Firestore;
  allowCreate?: boolean;
  allowEdit?: boolean;
  dogAccess?: boolean;
  admin?: boolean;
  caller?: ScheduleCaller;
}): HealthScheduleCallableDeps {
  const caller = options.caller ?? actor;
  // eslint-disable-next-line @typescript-eslint/no-var-requires
  const {HttpsError} = require("firebase-functions/v2/https");
  return {
    db: options.db,
    requireHealthCreate: async (auth) => {
      if (!auth) throw new HttpsError("unauthenticated", "auth");
      if (options.allowCreate === false) {
        throw new HttpsError("permission-denied", "no create", {
          code: "permission-denied",
        });
      }
      return caller;
    },
    requireHealthEdit: async (auth) => {
      if (!auth) throw new HttpsError("unauthenticated", "auth");
      if (options.allowEdit === false) {
        throw new HttpsError("permission-denied", "no edit", {
          code: "permission-denied",
        });
      }
      return caller;
    },
    requireDogAccess: async () => {
      if (options.dogAccess === false) {
        throw new HttpsError("permission-denied", "no dog", {
          code: "permission-denied",
        });
      }
    },
    isAdministrativeAuthority: async () => options.admin === true,
  };
}

function countAudit(store: Map<string, JsonMap>, action: string): number {
  let n = 0;
  for (const [path, doc] of store.entries()) {
    if (path.startsWith("auditLogs/") && doc.action === action) n++;
  }
  return n;
}

function countOps(store: Map<string, JsonMap>, scheduleId: string): number {
  let n = 0;
  const needle = `/health_schedule/${scheduleId}/operations/`;
  for (const path of store.keys()) {
    if (path.includes(needle)) n++;
  }
  return n;
}

async function test(name: string, fn: () => Promise<void>): Promise<void> {
  try {
    await fn();
    console.log(`ok - ${name}`);
  } catch (e) {
    console.error(`FAIL - ${name}`, e);
    throw e;
  }
}

async function main(): Promise<void> {
  await test("create sem auth → unauthenticated", async () => {
    const db = createFakeDb({"dogs/dog-1": {name: "Rex"}});
    await assert.rejects(
      () =>
        runHealthScheduleCreateManual(
          mockRequest({dogId: "dog-1"}, null),
          depsFor({db, allowCreate: true}),
        ),
      (e: {code?: string}) => e.code === "unauthenticated",
    );
  });

  await test("create sucesso + retry same key/payload = no-op + 1 audit", async () => {
    const db = createFakeDb({"dogs/dog-1": {name: "Rex"}});
    const deps = depsFor({db, allowCreate: true, dogAccess: true});
    // O handler usa o relógio real; uma hora de margem evita fixture vencido e flakiness.
    const scheduledFor = new Date(Date.now() + 60 * 60 * 1000).toISOString();
    const payload = {
      dogId: "dog-1",
      scheduleType: "vaccination",
      title: "V10",
      scheduledFor,
      timezone: "America/Sao_Paulo",
      idempotencyKey: "create-key-1",
    };
    const auth = {uid: actor.uid, token: {}};
    const r1 = await runHealthScheduleCreateManual(
      mockRequest(payload, auth),
      deps,
    );
    assert.strictEqual(r1.wasNoOp, false);
    assert.strictEqual(r1.revision, 1);
    const r2 = await runHealthScheduleCreateManual(
      mockRequest(payload, auth),
      deps,
    );
    assert.strictEqual(r2.wasNoOp, true);
    assert.strictEqual(r2.scheduleId, r1.scheduleId);
    assert.strictEqual(
      countAudit(db._store, "health_schedule_created"),
      1,
    );
    assert.strictEqual(countOps(db._store, r1.scheduleId as string), 1);
  });

  await test("create same key different payload → idempotency-conflict", async () => {
    const db = createFakeDb({"dogs/dog-1": {name: "Rex"}});
    const deps = depsFor({db, allowCreate: true, dogAccess: true});
    const auth = {uid: actor.uid, token: {}};
    // Ambas as chamadas precisam compartilhar o mesmo instante futuro no fingerprint.
    const scheduledFor = new Date(Date.now() + 60 * 60 * 1000).toISOString();
    await runHealthScheduleCreateManual(
      mockRequest(
        {
          dogId: "dog-1",
          scheduleType: "vaccination",
          title: "V10",
          scheduledFor,
          timezone: "America/Sao_Paulo",
          idempotencyKey: "create-key-2",
        },
        auth,
      ),
      deps,
    );
    await assert.rejects(
      () =>
        runHealthScheduleCreateManual(
          mockRequest(
            {
              dogId: "dog-1",
              scheduleType: "vaccination",
              title: "OUTRO",
              scheduledFor,
              timezone: "America/Sao_Paulo",
              idempotencyKey: "create-key-2",
            },
            auth,
          ),
          deps,
        ),
      (e: {details?: {code?: string}}) =>
        e.details?.code === "idempotency-conflict",
    );
  });

  await test("update A then B then retry A = replay not conflict", async () => {
    const scheduleId = "s-open";
    const db = createFakeDb({
      "dogs/dog-1": {name: "Rex"},
      [`dogs/dog-1/health_schedule/${scheduleId}`]: {
        schedule_type: "vaccination",
        title: "V10",
        lifecycle_status: "open",
        source_type: "manual",
        revision: 1,
        timezone: "America/Sao_Paulo",
        schema_version: 1,
      },
    });
    const deps = depsFor({db, allowEdit: true, dogAccess: true});
    const auth = {uid: actor.uid, token: {}};

    const a = await runHealthScheduleUpdateOpen(
      mockRequest(
        {
          dogId: "dog-1",
          scheduleId,
          expectedRevision: 1,
          operationId: "upd-A",
          title: "A",
        },
        auth,
      ),
      deps,
    );
    assert.strictEqual(a.revision, 2);

    const b = await runHealthScheduleUpdateOpen(
      mockRequest(
        {
          dogId: "dog-1",
          scheduleId,
          expectedRevision: 2,
          operationId: "upd-B",
          notes: "B",
        },
        auth,
      ),
      deps,
    );
    assert.strictEqual(b.revision, 3);

    // Retry A tardio: mesmo operationId + mesmo patch (title A)
    const retryA = await runHealthScheduleUpdateOpen(
      mockRequest(
        {
          dogId: "dog-1",
          scheduleId,
          expectedRevision: 1, // stale revision — receipt deve vencer
          operationId: "upd-A",
          title: "A",
        },
        auth,
      ),
      deps,
    );
    assert.strictEqual(retryA.wasNoOp, true);
    assert.strictEqual(
      countAudit(db._store, "health_schedule_updated"),
      2,
    ); // A e B, não 3
  });

  await test("update same operationId different patch → idempotency-conflict", async () => {
    const scheduleId = "s-patch";
    const db = createFakeDb({
      "dogs/dog-1": {name: "Rex"},
      [`dogs/dog-1/health_schedule/${scheduleId}`]: {
        lifecycle_status: "open",
        source_type: "manual",
        revision: 1,
        title: "V",
        schedule_type: "vaccination",
        timezone: "America/Sao_Paulo",
        schema_version: 1,
      },
    });
    const deps = depsFor({db, allowEdit: true, dogAccess: true});
    const auth = {uid: actor.uid, token: {}};
    await runHealthScheduleUpdateOpen(
      mockRequest(
        {
          dogId: "dog-1",
          scheduleId,
          expectedRevision: 1,
          operationId: "upd-x",
          title: "one",
        },
        auth,
      ),
      deps,
    );
    await assert.rejects(
      () =>
        runHealthScheduleUpdateOpen(
          mockRequest(
            {
              dogId: "dog-1",
              scheduleId,
              expectedRevision: 2,
              operationId: "upd-x",
              title: "two",
            },
            auth,
          ),
          deps,
        ),
      (e: {details?: {code?: string}}) =>
        e.details?.code === "idempotency-conflict",
    );
  });

  await test("complete retry no-op sem re-audit / sem re-revision", async () => {
    const scheduleId = "s-comp";
    const db = createFakeDb({
      "dogs/dog-1": {name: "Rex"},
      [`dogs/dog-1/health_schedule/${scheduleId}`]: {
        lifecycle_status: "open",
        source_type: "manual",
        revision: 1,
        title: "V",
        schedule_type: "vaccination",
        timezone: "America/Sao_Paulo",
        schema_version: 1,
      },
    });
    const deps = depsFor({db, allowEdit: true, dogAccess: true});
    const auth = {uid: actor.uid, token: {}};
    const r1 = await runHealthScheduleComplete(
      mockRequest({dogId: "dog-1", scheduleId, operationId: "comp-1"}, auth),
      deps,
    );
    assert.strictEqual(r1.wasNoOp, false);
    const rev1 = r1.revision;
    const r2 = await runHealthScheduleComplete(
      mockRequest({dogId: "dog-1", scheduleId, operationId: "comp-1"}, auth),
      deps,
    );
    assert.strictEqual(r2.wasNoOp, true);
    assert.strictEqual(r2.revision, rev1);
    assert.strictEqual(
      countAudit(db._store, "health_schedule_completed"),
      1,
    );
  });

  await test("cancel same op+reason noop; same op different reason conflict; other op alreadyCancelled", async () => {
    const scheduleId = "s-cancel";
    const db = createFakeDb({
      "dogs/dog-1": {name: "Rex"},
      [`dogs/dog-1/health_schedule/${scheduleId}`]: {
        lifecycle_status: "open",
        source_type: "manual",
        revision: 1,
        title: "V",
        schedule_type: "vaccination",
        timezone: "America/Sao_Paulo",
        schema_version: 1,
      },
    });
    const deps = depsFor({db, allowEdit: true, dogAccess: true});
    const auth = {uid: actor.uid, token: {}};
    await runHealthScheduleCancel(
      mockRequest(
        {
          dogId: "dog-1",
          scheduleId,
          operationId: "c-op-1",
          cancelReason: "dup",
        },
        auth,
      ),
      deps,
    );
    const replay = await runHealthScheduleCancel(
      mockRequest(
        {
          dogId: "dog-1",
          scheduleId,
          operationId: "c-op-1",
          cancelReason: "dup",
        },
        auth,
      ),
      deps,
    );
    assert.strictEqual(replay.wasNoOp, true);
    assert.strictEqual(
      countAudit(db._store, "health_schedule_cancelled"),
      1,
    );

    await assert.rejects(
      () =>
        runHealthScheduleCancel(
          mockRequest(
            {
              dogId: "dog-1",
              scheduleId,
              operationId: "c-op-1",
              cancelReason: "outro-reason",
            },
            auth,
          ),
          deps,
        ),
      (e: {details?: {code?: string}}) =>
        e.details?.code === "idempotency-conflict",
    );

    await assert.rejects(
      () =>
        runHealthScheduleCancel(
          mockRequest(
            {
              dogId: "dog-1",
              scheduleId,
              operationId: "c-op-2",
              cancelReason: "novo",
            },
            auth,
          ),
          deps,
        ),
      (e: {details?: {code?: string}}) =>
        e.details?.code === "already-cancelled",
    );
  });

  await test("cancel automático: operador denied; admin allowed", async () => {
    const scheduleId = "s-auto-c";
    const db = createFakeDb({
      "dogs/dog-1": {name: "Rex"},
      [`dogs/dog-1/health_schedule/${scheduleId}`]: {
        lifecycle_status: "open",
        source_type: "preventive",
        revision: 1,
        title: "auto",
        schedule_type: "vaccination",
        timezone: "America/Sao_Paulo",
        schema_version: 1,
      },
    });
    await assert.rejects(
      () =>
        runHealthScheduleCancel(
          mockRequest(
            {
              dogId: "dog-1",
              scheduleId,
              operationId: "c-auto-1",
              cancelReason: "admin only",
            },
            {uid: actor.uid, token: {}},
          ),
          depsFor({db, allowEdit: true, dogAccess: true, admin: false}),
        ),
      (e: {code?: string}) => e.code === "permission-denied",
    );

    const ok = await runHealthScheduleCancel(
      mockRequest(
        {
          dogId: "dog-1",
          scheduleId,
          operationId: "c-auto-1",
          cancelReason: "admin only",
        },
        {uid: adminActor.uid, token: {}},
      ),
      depsFor({
        db,
        allowEdit: true,
        dogAccess: true,
        admin: true,
        caller: adminActor,
      }),
    );
    assert.strictEqual(ok.wasNoOp, false);
  });

  await test(
    "cross-actor same operationId + same patch → idempotency-conflict (sem side effects)",
    async () => {
      const scheduleId = "s-cross-actor";
      const opPath =
        `dogs/dog-1/health_schedule/${scheduleId}/operations/shared-op-x`;
      const itemPath = `dogs/dog-1/health_schedule/${scheduleId}`;
      const db = createFakeDb({
        "dogs/dog-1": {name: "Rex"},
        [itemPath]: {
          lifecycle_status: "open",
          source_type: "manual",
          revision: 1,
          title: "Original",
          schedule_type: "vaccination",
          timezone: "America/Sao_Paulo",
          schema_version: 1,
        },
      });
      const depsA = depsFor({
        db,
        allowEdit: true,
        dogAccess: true,
        caller: actor,
      });
      const depsB = depsFor({
        db,
        allowEdit: true,
        dogAccess: true,
        caller: actorB,
      });
      const rA = await runHealthScheduleUpdateOpen(
        mockRequest(
          {
            dogId: "dog-1",
            scheduleId,
            expectedRevision: 1,
            operationId: "shared-op-x",
            title: "Patched",
          },
          {uid: actor.uid, token: {}},
        ),
        depsA,
      );
      assert.strictEqual(rA.wasNoOp, false);
      assert.strictEqual(rA.revision, 2);

      const itemBefore = {...(db._store.get(itemPath) ?? {})};
      const receiptBefore = {...(db._store.get(opPath) ?? {})};
      const auditsBefore = countAudit(db._store, "health_schedule_updated");

      await assert.rejects(
        () =>
          runHealthScheduleUpdateOpen(
            mockRequest(
              {
                dogId: "dog-1",
                scheduleId,
                expectedRevision: 2,
                operationId: "shared-op-x",
                title: "Patched",
              },
              {uid: actorB.uid, token: {}},
            ),
            depsB,
          ),
        (e: {details?: {code?: string}}) =>
          e.details?.code === "idempotency-conflict",
      );

      const itemAfter = db._store.get(itemPath) ?? {};
      const receiptAfter = db._store.get(opPath) ?? {};
      assert.strictEqual(itemAfter.title, itemBefore.title);
      assert.strictEqual(itemAfter.revision, itemBefore.revision);
      assert.strictEqual(itemAfter.lifecycle_status, itemBefore.lifecycle_status);
      assert.strictEqual(receiptAfter.actor_uid, receiptBefore.actor_uid);
      assert.strictEqual(
        receiptAfter.operation_type,
        receiptBefore.operation_type,
      );
      assert.strictEqual(receiptAfter.fingerprint, receiptBefore.fingerprint);
      assert.strictEqual(
        countAudit(db._store, "health_schedule_updated"),
        auditsBefore,
      );
    },
  );

  await test(
    "cross-operation same operationId (update→cancel) → idempotency-conflict (sem side effects)",
    async () => {
      const scheduleId = "s-cross-op";
      const opPath =
        `dogs/dog-1/health_schedule/${scheduleId}/operations/shared-op-y`;
      const itemPath = `dogs/dog-1/health_schedule/${scheduleId}`;
      const db = createFakeDb({
        "dogs/dog-1": {name: "Rex"},
        [itemPath]: {
          lifecycle_status: "open",
          source_type: "manual",
          revision: 1,
          title: "Open item",
          schedule_type: "vaccination",
          timezone: "America/Sao_Paulo",
          schema_version: 1,
        },
      });
      const deps = depsFor({db, allowEdit: true, dogAccess: true});
      const auth = {uid: actor.uid, token: {}};
      await runHealthScheduleUpdateOpen(
        mockRequest(
          {
            dogId: "dog-1",
            scheduleId,
            expectedRevision: 1,
            operationId: "shared-op-y",
            title: "Updated once",
          },
          auth,
        ),
        deps,
      );

      const itemBefore = {...(db._store.get(itemPath) ?? {})};
      const receiptBefore = {...(db._store.get(opPath) ?? {})};
      const cancelAuditsBefore = countAudit(
        db._store,
        "health_schedule_cancelled",
      );
      const updateAuditsBefore = countAudit(
        db._store,
        "health_schedule_updated",
      );

      await assert.rejects(
        () =>
          runHealthScheduleCancel(
            mockRequest(
              {
                dogId: "dog-1",
                scheduleId,
                operationId: "shared-op-y",
                cancelReason: "should not reuse receipt",
              },
              auth,
            ),
            deps,
          ),
        (e: {details?: {code?: string}}) =>
          e.details?.code === "idempotency-conflict",
      );

      const itemAfter = db._store.get(itemPath) ?? {};
      const receiptAfter = db._store.get(opPath) ?? {};
      assert.strictEqual(itemAfter.lifecycle_status, "open");
      assert.strictEqual(itemAfter.revision, itemBefore.revision);
      assert.strictEqual(itemAfter.title, itemBefore.title);
      assert.strictEqual(receiptAfter.operation_type, "update_open");
      assert.strictEqual(receiptAfter.actor_uid, receiptBefore.actor_uid);
      assert.strictEqual(receiptAfter.fingerprint, receiptBefore.fingerprint);
      assert.strictEqual(
        countAudit(db._store, "health_schedule_cancelled"),
        cancelAuditsBefore,
      );
      assert.strictEqual(
        countAudit(db._store, "health_schedule_updated"),
        updateAuditsBefore,
      );
    },
  );

  await test(
    "cross-operation complete→cancel same operationId → idempotency-conflict",
    async () => {
      const scheduleId = "s-cross-comp-cancel";
      const db = createFakeDb({
        "dogs/dog-1": {name: "Rex"},
        [`dogs/dog-1/health_schedule/${scheduleId}`]: {
          lifecycle_status: "open",
          source_type: "manual",
          revision: 1,
          title: "To complete",
          schedule_type: "vaccination",
          timezone: "America/Sao_Paulo",
          schema_version: 1,
        },
      });
      const deps = depsFor({db, allowEdit: true, dogAccess: true});
      const auth = {uid: actor.uid, token: {}};
      const completed = await runHealthScheduleComplete(
        mockRequest(
          {dogId: "dog-1", scheduleId, operationId: "lifecycle-op-z"},
          auth,
        ),
        deps,
      );
      assert.strictEqual(completed.wasNoOp, false);
      assert.strictEqual(completed.lifecycleStatus, "completed");
      const rev = completed.revision;
      const auditsComplete = countAudit(db._store, "health_schedule_completed");

      await assert.rejects(
        () =>
          runHealthScheduleCancel(
            mockRequest(
              {
                dogId: "dog-1",
                scheduleId,
                operationId: "lifecycle-op-z",
                cancelReason: "reuse id",
              },
              auth,
            ),
            deps,
          ),
        (e: {details?: {code?: string}}) =>
          e.details?.code === "idempotency-conflict",
      );

      const item =
        db._store.get(`dogs/dog-1/health_schedule/${scheduleId}`) ?? {};
      assert.strictEqual(item.lifecycle_status, "completed");
      assert.strictEqual(item.revision, rev);
      assert.strictEqual(
        countAudit(db._store, "health_schedule_completed"),
        auditsComplete,
      );
      assert.strictEqual(
        countAudit(db._store, "health_schedule_cancelled"),
        0,
      );
    },
  );

  await test("operationId path-unsafe rejeitado antes de mutar", async () => {
    const scheduleId = "s-path-safe";
    const db = createFakeDb({
      "dogs/dog-1": {name: "Rex"},
      [`dogs/dog-1/health_schedule/${scheduleId}`]: {
        lifecycle_status: "open",
        source_type: "manual",
        revision: 1,
        title: "V",
        schedule_type: "vaccination",
        timezone: "America/Sao_Paulo",
        schema_version: 1,
      },
    });
    const deps = depsFor({db, allowEdit: true, dogAccess: true});
    await assert.rejects(
      () =>
        runHealthScheduleComplete(
          mockRequest(
            {
              dogId: "dog-1",
              scheduleId,
              operationId: "../escape",
            },
            {uid: actor.uid, token: {}},
          ),
          deps,
        ),
      (e: {code?: string; details?: {code?: string}}) =>
        e.code === "invalid-argument" ||
        e.details?.code === "validation",
    );
    const item =
      db._store.get(`dogs/dog-1/health_schedule/${scheduleId}`) ?? {};
    assert.strictEqual(item.lifecycle_status, "open");
    assert.strictEqual(item.revision, 1);
    assert.strictEqual(
      countAudit(db._store, "health_schedule_completed"),
      0,
    );
  });

  await test("payload inject recorded_by rejected", async () => {
    const db = createFakeDb({"dogs/dog-1": {name: "Rex"}});
    await assert.rejects(
      () =>
        runHealthScheduleCreateManual(
          mockRequest(
            {
              dogId: "dog-1",
              scheduleType: "vaccination",
              title: "V10",
              scheduledFor: "2026-08-01T12:00:00.000Z",
              timezone: "America/Sao_Paulo",
              idempotencyKey: "k2",
              recorded_by: {uid: "hacker"},
            },
            {uid: actor.uid, token: {}},
          ),
          depsFor({db, allowCreate: true, dogAccess: true}),
        ),
      (e: {code?: string}) => e.code === "invalid-argument",
    );
  });

  await test("create scheduled_for no passado → validation + zero write", async () => {
    const db = createFakeDb({"dogs/dog-1": {name: "Rex"}});
    const deps = depsFor({db, allowCreate: true, dogAccess: true});
    const auth = {uid: actor.uid, token: {}};
    // Claramente no passado relativo a qualquer "agora" do teste.
    const pastIso = "2020-01-01T12:00:00.000Z";
    await assert.rejects(
      () =>
        runHealthScheduleCreateManual(
          mockRequest(
            {
              dogId: "dog-1",
              scheduleType: "vaccination",
              title: "Vacina passada",
              scheduledFor: pastIso,
              timezone: "America/Sao_Paulo",
              idempotencyKey: "create-past-1",
            },
            auth,
          ),
          deps,
        ),
      (e: {code?: string; details?: {code?: string}}) =>
        e.code === "invalid-argument" && e.details?.code === "validation",
    );
    // ZERO schedule / receipt / audit
    const scheduleKeys = Object.keys(db._store).filter((k) =>
      k.includes("/health_schedule/"),
    );
    assert.strictEqual(scheduleKeys.length, 0, "zero health_schedule");
    assert.strictEqual(
      countAudit(db._store, "health_schedule_created"),
      0,
      "zero audit",
    );
  });

  await test("create scheduled_for minuto corrente e futuro → aceito", async () => {
    const db = createFakeDb({"dogs/dog-1": {name: "Rex"}});
    const deps = depsFor({db, allowCreate: true, dogAccess: true});
    const auth = {uid: actor.uid, token: {}};
    const now = new Date();
    const currentMinute = new Date(Date.UTC(
      now.getUTCFullYear(),
      now.getUTCMonth(),
      now.getUTCDate(),
      now.getUTCHours(),
      now.getUTCMinutes(),
      0,
      0,
    ));
    const future = new Date(now.getTime() + 60 * 60 * 1000);

    const rCurrent = await runHealthScheduleCreateManual(
      mockRequest(
        {
          dogId: "dog-1",
          scheduleType: "weighing",
          title: "Pesagem agora",
          scheduledFor: currentMinute.toISOString(),
          timezone: "America/Sao_Paulo",
          idempotencyKey: "create-now-minute-1",
        },
        auth,
      ),
      deps,
    );
    assert.strictEqual(rCurrent.wasNoOp, false);
    assert.strictEqual(rCurrent.revision, 1);
    assert.strictEqual(rCurrent.lifecycleStatus, "open");

    const rFuture = await runHealthScheduleCreateManual(
      mockRequest(
        {
          dogId: "dog-1",
          scheduleType: "bath",
          title: "Banho futuro",
          scheduledFor: future.toISOString(),
          timezone: "America/Sao_Paulo",
          idempotencyKey: "create-future-1",
        },
        auth,
      ),
      deps,
    );
    assert.strictEqual(rFuture.wasNoOp, false);
    assert.strictEqual(rFuture.revision, 1);
  });

  // sanity deterministic id
  const material = createIdempotencyMaterial("u", "d", "k");
  const hash = crypto.createHash("sha256").update(material).digest("hex");
  assert.ok(deterministicManualScheduleId(hash).startsWith("m_"));

  console.log("\nhealth_schedule_callables_test: all passed");
}

main().catch((e) => {
  console.error(e);
  process.exitCode = 1;
});
