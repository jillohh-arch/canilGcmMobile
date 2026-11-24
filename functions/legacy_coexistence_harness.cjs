// R2 legacy callables coexistence harness.
// Replaces firebase-admin with an in-memory Firestore and invokes the REAL
// adminUpsertInventoryItem / adminArchiveInventoryItem /
// adminCreateInventoryMovement callables from lib/index.js.
process.env.FUNCTIONS_EMULATOR = "true";
process.env.GCLOUD_PROJECT = "canil-gcm";

const Module = require("module");
const assert = require("assert");

class Timestamp {
  constructor(seconds, nanoseconds) { this.seconds = seconds; this.nanoseconds = nanoseconds; }
  static now() { const ms = Date.now(); return new Timestamp(Math.floor(ms / 1000), (ms % 1000) * 1e6); }
  toDate() { return new Date(this.seconds * 1000); }
}

function docSnapshot(store, key) {
  const data = store.get(key);
  return {
    id: key.split("/").pop(),
    path: key,
    exists: data !== undefined,
    data: () => (data === undefined ? undefined : data),
  };
}

class Query {
  constructor(store, path, filters, limitCount) {
    this.store = store; this.path = path; this.filters = filters || []; this.limitCount = limitCount;
  }
  where(field, op, value) { return new Query(this.store, this.path, this.filters.concat([{ field: field, op: op, value: value }]), this.limitCount); }
  orderBy() { return this; }
  limit(n) { return new Query(this.store, this.path, this.filters, n); }
  async get() {
    const prefix = this.path + "/";
    let entries = Array.from(this.store.entries()).filter(function (e) {
      return e[0].indexOf(prefix) === 0 && e[0].slice(prefix.length).split("/").length === 1;
    });
    for (const f of this.filters) {
      entries = entries.filter(function (e) {
        const doc = e[1];
        const val = doc[f.field];
        if (f.op === "==") return val === f.value;
        if (f.op === ">") return val > f.value;
        if (f.op === "<") return val < f.value;
        if (f.op === ">=") return val >= f.value;
        if (f.op === "<=") return val <= f.value;
        if (f.op === "in") return Array.isArray(f.value) && f.value.indexOf(val) !== -1;
        if (f.op === "array-contains") return Array.isArray(val) && val.indexOf(f.value) !== -1;
        return true;
      });
    }
    if (this.limitCount !== undefined) entries = entries.slice(0, this.limitCount);
    const docs = entries.map(function (e) { return docSnapshot(new Map([e]), e[0]); });
    return { docs: docs, empty: docs.length === 0, size: docs.length };
  }
}

class MemFirestore {
  constructor() { this.store = new Map(); this.counter = 0; }
  doc(path) {
    const parts = String(path).split("/");
    const id = parts.pop();
    return this.collection(parts.join("/")).doc(id);
  }
  collection(path) {
    const self = this;
    return {
      doc(id) {
        const key = id ? path + "/" + id : path + "/auto_" + (++self.counter);
        return {
          id: key.split("/").pop(),
          path: key,
          get: async function () { return docSnapshot(self.store, key); },
          set: async function (data, opts) {
            const prev = self.store.get(key) || {};
            self.store.set(key, opts && opts.merge ? Object.assign({}, prev, data) : Object.assign({}, data));
          },
          update: async function (data) {
            const prev = self.store.get(key);
            if (!prev) throw new Error("doc not found: " + key);
            self.store.set(key, Object.assign({}, prev, data));
          },
          delete: async function () { self.store.delete(key); },
          collection: function (child) { return self.collection(key + "/" + child); },
        };
      },
      where: function (f, op, v) { return new Query(self.store, path, [{ field: f, op: op, value: v }]); },
      orderBy: function () { return new Query(self.store, path, []); },
      limit: function (n) { return new Query(self.store, path, [], n); },
      get: async function () { return new Query(self.store, path, []).get(); },
    };
  }
  _refFromPath(p) {
    const parts = p.split("/");
    const id = parts.pop();
    return this.collection(parts.join("/")).doc(id);
  }
  async runTransaction(fn) {
    const self = this;
    const ops = [];
    const tx = {
      get: async function (ref) { return docSnapshot(self.store, ref.path); },
      set: function (ref, data, opts) { ops.push(function () { return ref.set(data, opts); }); return tx; },
      update: function (ref, data) { ops.push(function () { return ref.update(data); }); return tx; },
      delete: function (ref) { ops.push(function () { return ref.delete(); }); return tx; },
    };
    const result = await fn(tx);
    for (const op of ops) await op();
    return result;
  }
  batch() {
    const ops = [];
    const b = {
      set: function (ref, data, opts) { ops.push(function () { return ref.set(data, opts); }); return b; },
      update: function (ref, data) { ops.push(function () { return ref.update(data); }); return b; },
      delete: function (ref) { ops.push(function () { return ref.delete(); }); return b; },
      commit: async function () { for (const op of ops) await op(); },
    };
    return b;
  }
}

const SHARED = new MemFirestore();

const FieldValue = {
  serverTimestamp: function () { return new Timestamp(0, 0); },
  delete: function () { return null; },
  arrayUnion: function () { const items = Array.prototype.slice.call(arguments); return items.length === 1 ? items[0] : items; },
  increment: function (n) { return n; },
};

const fakeAdmin = {
  initializeApp: function () { return {}; },
  app: function () { return { options: { projectId: "canil-gcm" } }; },
  apps: [],
  firestore: function () { return SHARED; },
  auth: function () { return { getUser: async function(){throw new Error("getUser not expected");}, getUserByUid: async function(){throw new Error("getUserByUid not expected");}, listUsers: async function(){throw new Error("listUsers not expected");}, createUser: async function(){throw new Error("createUser not expected");} }; },
  storage: function () { throw new Error("storage() not expected here"); },
  messaging: function () { throw new Error("messaging() not expected here"); },
};

function attach(obj, name, value) {
  Object.defineProperty(obj, name, { value: value, enumerable: true, configurable: true, writable: true });
}
attach(fakeAdmin.firestore, "Timestamp", Timestamp);
attach(fakeAdmin.firestore, "FieldValue", FieldValue);
attach(fakeAdmin.firestore, "QueryDocumentSnapshot", class {});
attach(fakeAdmin.firestore, "DocumentReference", class {});
attach(fakeAdmin.firestore, "Query", class {});
attach(fakeAdmin.firestore, "QuerySnapshot", class {});
attach(fakeAdmin.firestore, "Transaction", class {});
attach(fakeAdmin.firestore, "WriteBatch", class {});
attach(fakeAdmin.firestore, "Firestore", MemFirestore);
attach(fakeAdmin.auth, "DecodedIdToken", class {});
attach(fakeAdmin, "credential", { applicationDefault: function () { return {}; }, cert: function () { return {}; } });

const originalLoad = Module._load;
Module._load = function (request, parent, isMain) {
  if (request === "firebase-admin") return fakeAdmin;
  return originalLoad.call(this, request, parent, isMain);
};

const idx = require("./lib/index.js");

function authFor(rolesAndAdmin) {
  const token = Object.assign({ email: "123@canilgcm.com", name: "Operador" }, rolesAndAdmin || {});
  const raMatch = String(token.email || "").match(/^([^@]+)/);
  const uid = token.uid || ("uid-" + (raMatch ? raMatch[1] : "123"));
  return { uid: uid, token: token };
}

async function run() {
  const results = [];
  function record(name, ok, detail) {
    results.push({ name: name, ok: ok, detail: detail });
    console.log((ok ? "ok   - " : "FAIL - ") + name + (detail ? " :: " + detail : ""));
  }

  // ---- Seed authoritative access_profiles and users fixtures (SEC-02A.2).
  await SHARED.collection("access_profiles").doc("administrador").set({
    id: "administrador",
    status: "active",
    scope: "global",
    permissions: {
      inventory: { view: true, create: true, edit: true, archive: true, move: true },
    },
  });
  await SHARED.collection("access_profiles").doc("operador_k9").set({
    id: "operador_k9",
    status: "active",
    scope: "own_records",
    permissions: {
      inventory: { view: true, create: false, edit: false, archive: false, move: false },
    },
  });
  await SHARED.collection("users").doc("123").set({
    ra: "123",
    name: "Admin Legitimo",
    email: "123@canilgcm.com",
    active: true,
    status: "Ativo",
    deleted_at: null,
    access_profile_id: "administrador",
    admin: true,
  });
  await SHARED.collection("users").doc("456").set({
    ra: "456",
    name: "Operador K9",
    email: "456@canilgcm.com",
    active: true,
    status: "Ativo",
    deleted_at: null,
    access_profile_id: "operador_k9",
    admin: false,
  });
  await SHARED.collection("users").doc("789").set({
    ra: "789",
    name: "Admin Inativo",
    email: "789@canilgcm.com",
    active: false,
    status: "Inativo",
    deleted_at: Timestamp.now(),
    access_profile_id: "administrador",
    admin: true,
  });

  // ---- Ensure the material fixture exists as warehouse-managed.
  const materialRef = SHARED.collection("inventory_items").doc("mat-wh");
  await materialRef.set({
    id: "mat-wh", name: "Racao WH", category_id: "alimentacao", category_name: "Alimentacao",
    unit: "kg", current_quantity: 10, minimum_quantity: 1, active: true, warehouse_managed: true,
  });

  // A legacy (non warehouse-managed) ACTIVE item for the movement path.
  await SHARED.collection("inventory_items").doc("mat-legacy-active").set({
    id: "mat-legacy-active", name: "Item Legado Ativo", category_id: "alimentacao",
    category_name: "Alimentacao", unit: "kg", current_quantity: 0, minimum_quantity: 0,
    active: true,
  });

  // ---- 1. Unauthenticated call must be rejected.
  try {
    await idx.adminUpsertInventoryItem.run({
      data: { mode: "create", profile: { name: "X", categoryId: "c", categoryName: "C", unit: "kg" } },
      auth: null,
    });
    record("upsert: unauthenticated rejected", false, "unexpected success");
  } catch (e) { record("upsert: unauthenticated rejected", e && e.code === "unauthenticated", e && e.code); }

  // ---- 2. Authenticated but unauthorized profile must be rejected.
  const operadorAuth = authFor({ email: "456@canilgcm.com", access_profile_id: "operador_k9" });
  try {
    await idx.adminUpsertInventoryItem.run({
      data: { mode: "create", profile: { name: "X", categoryId: "c", categoryName: "C", unit: "kg" } },
      auth: operadorAuth,
    });
    record("upsert: unauthorized profile rejected", false, "unexpected success");
  } catch (e) { record("upsert: unauthorized profile rejected", e && e.code === "permission-denied", e && e.code); }

  // ---- 3. Authorized create works and marks a legacy (non-warehouse) item.
  const adminAuth = authFor({ admin: true });
  try {
    const created = await idx.adminUpsertInventoryItem.run({
      data: {
        mode: "create", id: "mat-legacy",
        profile: { name: "Item Legado", categoryId: "alimentacao", categoryName: "Alimentacao", unit: "kg", initialQuantity: 5 },
      },
      auth: adminAuth,
    });
    const saved = SHARED.store.get("inventory_items/mat-legacy") || {};
    record("upsert: legacy create succeeds", created && created.id === "mat-legacy" && saved.warehouse_managed !== true,
      "warehouse_managed=" + saved.warehouse_managed);
  } catch (e) { record("upsert: legacy create succeeds", false, e && e.message); }

  // ---- 4. Legacy edit cannot change category/unit/deactivate a warehouse-managed item.
  try {
    await idx.adminUpsertInventoryItem.run({
      data: {
        mode: "edit", id: "mat-wh",
        profile: { name: "Racao WH", categoryId: "outra", categoryName: "Outra", unit: "kg" },
      },
      auth: adminAuth,
    });
    record("upsert: legacy edit blocked on warehouse_managed", false, "unexpected success");
  } catch (e) { record("upsert: legacy edit blocked on warehouse_managed", e && e.code === "failed-precondition", e && e.code + " " + e.message); }

  // ---- 5. Legacy edit of a warehouse item that does NOT touch the protected fields still works.
  try {
    await idx.adminUpsertInventoryItem.run({
      data: {
        mode: "edit", id: "mat-wh",
        profile: { name: "Racao WH Renomeada", categoryId: "alimentacao", categoryName: "Alimentacao", unit: "kg" },
      },
      auth: adminAuth,
    });
    const saved = SHARED.store.get("inventory_items/mat-wh") || {};
    record("upsert: benign legacy edit allowed", saved.name === "Racao WH Renomeada" && saved.warehouse_managed === true, "name=" + saved.name);
  } catch (e) { record("upsert: benign legacy edit allowed", false, e && e.message); }

  // ---- 6. Archive of a warehouse-managed item is blocked.
  try {
    await idx.adminArchiveInventoryItem.run({ data: { id: "mat-wh", reason: "teste" }, auth: adminAuth });
    record("archive: warehouse_managed blocked", false, "unexpected success");
  } catch (e) { record("archive: warehouse_managed blocked", e && e.code === "failed-precondition", e && e.code); }

  // ---- 7. Archive of a legacy item succeeds.
  try {
    const archived = await idx.adminArchiveInventoryItem.run({ data: { id: "mat-legacy", reason: "obsoleto" }, auth: adminAuth });
    const saved = SHARED.store.get("inventory_items/mat-legacy") || {};
    record("archive: legacy item archived", archived && archived.archived === true && saved.active === false, "active=" + saved.active);
  } catch (e) { record("archive: legacy item archived", false, e && e.message); }

  // ---- 8. Archive unauthorized.
  try {
    await idx.adminArchiveInventoryItem.run({ data: { id: "mat-wh", reason: "x" }, auth: operadorAuth });
    record("archive: unauthorized rejected", false, "unexpected success");
  } catch (e) { record("archive: unauthorized rejected", e && e.code === "permission-denied", e && e.code); }

  // ---- 9. Movement on a warehouse-managed item is blocked.
  try {
    await idx.adminCreateInventoryMovement.run({
      data: { payload: { itemId: "mat-wh", type: "entrada", quantity: 1, reason: "x", unit: "kg" } },
      auth: adminAuth,
    });
    record("movement: warehouse_managed blocked", false, "unexpected success");
  } catch (e) { record("movement: warehouse_managed blocked", e && e.code === "failed-precondition", e && e.code); }

  // ---- 10. Movement on an active legacy item succeeds.
  try {
    const moved = await idx.adminCreateInventoryMovement.run({
      data: { payload: { itemId: "mat-legacy-active", type: "entrada", quantity: 3, reason: "compra", unit: "kg" } },
      auth: adminAuth,
    });
    const saved = SHARED.store.get("inventory_items/mat-legacy-active") || {};
    record("movement: legacy movement succeeds",
      Boolean(moved && typeof moved.id === "string" && moved.balance_after === 3 && saved.current_quantity === 3),
      "balance_after=" + (moved && moved.balance_after) + " qty=" + saved.current_quantity);
  } catch (e) { record("movement: legacy movement succeeds", false, e && e.message); }

  // ---- 11. Movement unauthorized.
  try {
    await idx.adminCreateInventoryMovement.run({
      data: { payload: { itemId: "mat-legacy-active", type: "entrada", quantity: 1, reason: "x", unit: "kg" } },
      auth: operadorAuth,
    });
    record("movement: unauthorized rejected", false, "unexpected success");
  } catch (e) { record("movement: unauthorized rejected", e && e.code === "permission-denied", e && e.code); }

  // ---- 12. Adversarial: missing user document rejected even with admin claim.
  try {
    await idx.adminUpsertInventoryItem.run({
      data: { mode: "create", profile: { name: "Adv Missing", categoryId: "c", categoryName: "C", unit: "kg" } },
      auth: authFor({ email: "999@canilgcm.com", admin: true }),
    });
    record("adversarial: missing user rejected", false, "unexpected success");
  } catch (e) { record("adversarial: missing user rejected", e && e.code === "permission-denied", e && e.message); }

  // ---- 13. Adversarial: inactive/archived user rejected even with admin claim.
  try {
    await idx.adminArchiveInventoryItem.run({
      data: { id: "mat-legacy-active", reason: "adv-inactive" },
      auth: authFor({ email: "789@canilgcm.com", admin: true }),
    });
    record("adversarial: inactive user rejected", false, "unexpected success");
  } catch (e) { record("adversarial: inactive user rejected", e && e.code === "permission-denied", e && e.message); }

  // ---- 14. Adversarial: downgraded user with stale admin/profile token rejected.
  try {
    await idx.adminCreateInventoryMovement.run({
      data: { payload: { itemId: "mat-legacy-active", type: "entrada", quantity: 1, reason: "adv-stale", unit: "kg" } },
      auth: authFor({ email: "456@canilgcm.com", admin: true, access_profile_id: "administrador" }),
    });
    record("adversarial: downgraded user with stale token rejected", false, "unexpected success");
  } catch (e) { record("adversarial: downgraded user with stale token rejected", e && e.code === "permission-denied", e && e.message); }

  const failed = results.filter(function (r) { return !r.ok; });
  console.log("");
  console.log("legacy coexistence: " + (results.length - failed.length) + "/" + results.length + " checks passed");
  if (failed.length > 0) {
    console.log("FAILED:");
    failed.forEach(function (f) { console.log("  - " + f.name + " :: " + f.detail); });
    process.exitCode = 1;
  }
}

run().catch(function (e) { console.error("HARNESS ERROR:", e && (e.stack || e.message)); process.exitCode = 1; });
