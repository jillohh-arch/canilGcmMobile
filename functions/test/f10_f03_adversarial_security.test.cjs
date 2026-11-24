"use strict";

const { describe, it, beforeEach } = require("node:test");
const assert = require("node:assert/strict");
const path = require("node:path");
const admin = require("firebase-admin");

// In-memory Firestore mock with mutation counter and fault injection
const store = new Map();
let writeCount = 0;
let injectReadError = null;

function docKey(collectionPath, docId) {
  return `${collectionPath}/${docId}`;
}

function makeFakeFirestore() {
  const dbApi = {
    doc(fullPath) {
      const parts = String(fullPath).split("/");
      const docId = parts.pop();
      return dbApi.collection(parts.join("/")).doc(docId);
    },
    collection(colName) {
      return {
        doc(docId) {
          const key = docKey(colName, docId);
          return {
            path: key,
            id: docId,
            async get() {
              if (injectReadError && injectReadError.collection === colName) {
                throw injectReadError.error;
              }
              const data = store.get(key);
              return {
                exists: data !== undefined,
                id: docId,
                data: () => (data !== undefined ? { ...data } : undefined),
              };
            },
            async set(payload, opts) {
              writeCount++;
              const prev = opts && opts.merge ? (store.get(key) || {}) : {};
              store.set(key, { ...prev, ...payload });
            },
            async update(payload) {
              writeCount++;
              const prev = store.get(key) || {};
              store.set(key, { ...prev, ...payload });
            },
            async delete() {
              writeCount++;
              store.delete(key);
            },
          };
        },
        async add(payload) {
          writeCount++;
          const id = `auto_${writeCount}`;
          store.set(docKey(colName, id), { ...payload });
          return { id };
        },
      };
    },
    async runTransaction(fn) {
      const tx = {
        async get(ref) {
          if (injectReadError) throw injectReadError.error;
          const data = store.get(ref.path);
          return {
            exists: data !== undefined,
            id: ref.id,
            data: () => (data !== undefined ? { ...data } : undefined),
          };
        },
        set(ref, payload) {
          writeCount++;
          store.set(ref.path, { ...payload });
        },
        update(ref, payload) {
          writeCount++;
          const prev = store.get(ref.path) || {};
          store.set(ref.path, { ...prev, ...payload });
        },
        delete(ref) {
          writeCount++;
          store.delete(ref.path);
        },
      };
      return await fn(tx);
    },
  };
  return dbApi;
}

const fakeDb = makeFakeFirestore();
if (!admin.apps.length) {
  admin.initializeApp();
}
Object.defineProperty(admin, "firestore", {
  value: Object.assign(() => fakeDb, admin.firestore),
  configurable: true,
});

const libIndex = require(path.resolve(__dirname, "../lib/index.js"));
const { createWarehouseCallables } = require(
  path.resolve(__dirname, "../lib/warehouse/warehouse_callables.js"),
);

const {
  requireAccessPermission,
  accessProfileIdFrom,
  isReconciledAdmin,
  isQualifiedK9Instructor,
  decidePromotionRequest,
} = libIndex;

function makeAuth(ra, claims = {}) {
  return {
    uid: `uid_${ra}`,
    token: {
      uid: `uid_${ra}`,
      email: `${ra}@gcm.com.br`,
      name: `User ${ra}`,
      ...claims,
    },
  };
}

function seedStandardProfiles() {
  store.set("access_profiles/almoxarifado", {
    status: "active",
    scope: "global",
    permissions: {
      inventory: { view: true, create: true, edit: true, archive: true, audit: true },
      k9: { view: true },
    },
  });
  store.set("access_profiles/operador_k9", {
    status: "active",
    scope: "own_records",
    permissions: {
      k9: { view: true },
      inventory: { view: false, create: false, edit: false, archive: false },
      access: { view: false, edit: false },
    },
  });
  store.set("access_profiles/instrutor_k9", {
    status: "active",
    scope: "global",
    permissions: {
      k9: { view: true, create: true, edit: true, approve: true },
      binomials: { view: true, edit: true },
      health: { view: true, create: true, edit: true },
      training: { view: true, create: true, edit: true, approve: true },
      inventory: { view: false, create: false, edit: false, archive: false },
    },
  });
  store.set("access_profiles/administrador", {
    status: "active",
    scope: "global",
    permissions: {
      access: { view: true, create: true, edit: true, archive: true },
      inventory: { view: true, create: true, edit: true, archive: true, audit: true },
    },
  });
}

describe("F10.F03 SEC-02A.2 Adversarial Security Regression", () => {
  beforeEach(() => {
    store.clear();
    writeCount = 0;
    injectReadError = null;
    seedStandardProfiles();
  });

  it("1. Rebaixamento de almoxarifado para operador_k9 com JWT antigo deve negar inventory.create", async () => {
    store.set("users/1001", {
      ra: "1001",
      active: true,
      deleted_at: null,
      access_profile_id: "operador_k9",
      accessProfileId: "operador_k9",
      admin: false,
      inventory_manager: false,
    });
    const staleJwtAuth = makeAuth("1001", {
      access_profile_id: "almoxarifado",
      inventory_manager: true,
      roles: ["almoxarifado", "inventory_manager"],
    });

    assert.equal(accessProfileIdFrom(staleJwtAuth.token, store.get("users/1001")), "operador_k9");
    await assert.rejects(
      () => requireAccessPermission(staleJwtAuth, "inventory", "create"),
      (err) => err.code === "permission-denied",
    );
    assert.equal(writeCount, 0);
  });

  it("2. Remocao de Access Profile (unassignment) com JWT antigo deve falhar fechado", async () => {
    store.set("users/1002", {
      ra: "1002",
      active: true,
      deleted_at: null,
      // access_profile_id removido por adminUnassignAccessProfile
    });
    const staleJwtAuth = makeAuth("1002", {
      access_profile_id: "almoxarifado",
      roles: ["almoxarifado", "operador_k9"],
    });

    assert.equal(accessProfileIdFrom(staleJwtAuth.token, store.get("users/1002")), "__sec02_no_profile__");
    await assert.rejects(
      () => requireAccessPermission(staleJwtAuth, "k9", "view"),
      (err) => err.code === "permission-denied",
    );
    await assert.rejects(
      () => requireAccessPermission(staleJwtAuth, "inventory", "view"),
      (err) => err.code === "permission-denied",
    );
    assert.equal(writeCount, 0);
  });

  it("3. Usuario active=false deve ser negado mesmo com admin=true no token e no doc", async () => {
    store.set("users/1003", {
      ra: "1003",
      active: false,
      status: "Inativo",
      deleted_at: null,
      access_profile_id: "administrador",
      admin: true,
    });
    const auth = makeAuth("1003", { admin: true, access_profile_id: "administrador" });

    await assert.rejects(
      () => requireAccessPermission(auth, "access", "edit"),
      (err) => err.code === "permission-denied",
    );
    assert.equal(writeCount, 0);
  });

  it("4. Usuario com deleted_at definido deve ser negado mesmo com active=true e admin=true", async () => {
    store.set("users/1004", {
      ra: "1004",
      active: true,
      deleted_at: "2026-11-20T10:00:00Z",
      access_profile_id: "administrador",
      admin: true,
    });
    const auth = makeAuth("1004", { admin: true, access_profile_id: "administrador" });

    await assert.rejects(
      () => requireAccessPermission(auth, "inventory", "create"),
      (err) => err.code === "permission-denied",
    );
    assert.equal(writeCount, 0);
  });

  it("5. Claim administrativa antiga com usuario rebaixado para operador_k9 deve ser negada", async () => {
    store.set("users/1005", {
      ra: "1005",
      active: true,
      deleted_at: null,
      access_profile_id: "operador_k9",
      accessLevel: "Admin", // campo legado residual
      admin: false,
    });
    const staleAdminAuth = makeAuth("1005", {
      admin: true,
      role: "administrador",
      roles: ["admin", "administrador"],
      access_profile_id: "administrador",
    });

    assert.equal(isReconciledAdmin(store.get("users/1005")), false);
    await assert.rejects(
      () => requireAccessPermission(staleAdminAuth, "access", "edit"),
      (err) => err.code === "permission-denied",
    );
    await assert.rejects(
      () => requireAccessPermission(staleAdminAuth, "inventory", "create"),
      (err) => err.code === "permission-denied",
    );
    assert.equal(writeCount, 0);
  });

  it("6. Administrador ativo e legitimamente autorizado deve ser permitido", async () => {
    store.set("users/1006", {
      ra: "1006",
      active: true,
      deleted_at: null,
      access_profile_id: "administrador",
      admin: true,
    });
    const activeAdminAuth = makeAuth("1006", {
      admin: true,
      access_profile_id: "administrador",
      roles: ["administrador", "admin"],
    });

    assert.equal(isReconciledAdmin(store.get("users/1006")), true);
    const caller = await requireAccessPermission(activeAdminAuth, "access", "edit");
    assert.equal(caller.ra, "1006");
  });

  it("7. Instructor Role e ortogonal: apos revogacao de perfil base (unassign), NAO sintetiza perfil instrutor_k9 nem concede k9/health/binomials/inventory", async () => {
    // Caso 7a: operador_k9 + is_k9_instructor=true -> concede training.approve (ortogonal), nega inventory.create e k9.edit
    store.set("users/1007", {
      ra: "1007",
      active: true,
      deleted_at: null,
      access_profile_id: "operador_k9",
      is_k9_instructor: true,
      training_instructor: true,
      training_role: "instrutor_k9",
    });
    const instAuth = makeAuth("1007", {
      access_profile_id: "operador_k9",
      instrutor_k9: true,
      roles: ["operador_k9", "condutor", "instrutor_k9"],
    });
    assert.equal(accessProfileIdFrom(instAuth.token, store.get("users/1007")), "operador_k9");
    await assert.rejects(
      () => requireAccessPermission(instAuth, "inventory", "create"),
      (err) => err.code === "permission-denied",
    );
    await assert.rejects(
      () => requireAccessPermission(instAuth, "k9", "edit"),
      (err) => err.code === "permission-denied",
    );
    const approveCaller7a = await requireAccessPermission(instAuth, "training", "approve");
    assert.equal(approveCaller7a.ra, "1007");

    // Caso 7b: sem perfil base + is_k9_instructor=true (estado exato pos adminUnassignAccessProfile)
    store.set("users/1008", {
      ra: "1008",
      active: true,
      deleted_at: null,
      is_k9_instructor: true,
      training_instructor: true,
      training_role: "instrutor_k9",
      roles: ["instrutor_k9"],
    });
    const instOnlyAuth = makeAuth("1008", {
      instrutor_k9: true,
      training_role: "instrutor_k9",
      training_instructor: true,
      roles: ["instrutor_k9"],
    });
    // CT-I2-03: Perfil base ausente => accessProfileIdFrom retorna __sec02_no_profile__ (nunca instrutor_k9)
    assert.equal(accessProfileIdFrom(instOnlyAuth.token, store.get("users/1008")), "__sec02_no_profile__");
    await assert.rejects(
      () => requireAccessPermission(instOnlyAuth, "inventory", "create"),
      (err) => err.code === "permission-denied",
    );
    // Prova critica Track B.1/B.2: mesmo que access_profiles/instrutor_k9 tenha k9.edit, health.create e binomials.edit,
    // um usuario sem perfil base mas com Instructor Role ativo NAO herda o perfil legado instrutor_k9!
    await assert.rejects(
      () => requireAccessPermission(instOnlyAuth, "k9", "edit"),
      (err) => err.code === "permission-denied",
    );
    await assert.rejects(
      () => requireAccessPermission(instOnlyAuth, "health", "create"),
      (err) => err.code === "permission-denied",
    );
    await assert.rejects(
      () => requireAccessPermission(instOnlyAuth, "binomials", "edit"),
      (err) => err.code === "permission-denied",
    );
    await assert.rejects(
      () => requireAccessPermission(instOnlyAuth, "training", "create"),
      (err) => err.code === "permission-denied",
    );
    // Qualificacao funcional de Instrutor concede apenas training.approve e training.view
    const trainingApproveCaller = await requireAccessPermission(instOnlyAuth, "training", "approve");
    assert.equal(trainingApproveCaller.ra, "1008");
    const trainingViewCaller = await requireAccessPermission(instOnlyAuth, "training", "view");
    assert.equal(trainingViewCaller.ra, "1008");
    assert.equal(writeCount, 0);
  });

  it("8. Documento de usuario ausente deve falhar fechado mesmo com claim admin", async () => {
    const ghostAdminAuth = makeAuth("9999", {
      admin: true,
      access_profile_id: "administrador",
      roles: ["admin"],
    });

    await assert.rejects(
      () => requireAccessPermission(ghostAdminAuth, "k9", "view"),
      (err) => err.code === "permission-denied",
    );
    assert.equal(writeCount, 0);
  });

  it("9. Falha de leitura da autoridade (users ou access_profiles) deve falhar fechado", async () => {
    store.set("users/1009", {
      ra: "1009",
      active: true,
      deleted_at: null,
      access_profile_id: "almoxarifado",
    });
    const auth = makeAuth("1009", { access_profile_id: "almoxarifado" });

    injectReadError = { collection: "users", error: new Error("Firestore users read unavailable") };
    await assert.rejects(
      () => requireAccessPermission(auth, "inventory", "create"),
      /Firestore users read unavailable/,
    );

    injectReadError = { collection: "access_profiles", error: new Error("Firestore profile read unavailable") };
    await assert.rejects(
      () => requireAccessPermission(auth, "inventory", "create"),
      /Firestore profile read unavailable/,
    );
    assert.equal(writeCount, 0);
  });

  it("10. Compatibilidade dos callables consumidores (createWarehouseCallables) e zero mutacoes em rejeicao", async () => {
    const warehouseCallables = createWarehouseCallables(fakeDb, requireAccessPermission);
    assert.ok(typeof warehouseCallables.adminWarehouseUpsertMaterial === "function");
    assert.ok(typeof warehouseCallables.adminWarehouseArchiveMaterial === "function");

    // Rebaixado com JWT antigo tenta criar material -> rejeitado antes de qualquer escrita
    store.set("users/1010", {
      ra: "1010",
      active: true,
      deleted_at: null,
      access_profile_id: "operador_k9",
      admin: false,
    });
    const downgradedAuth = makeAuth("1010", {
      access_profile_id: "almoxarifado",
      admin: true,
    });

    await assert.rejects(
      () =>
        warehouseCallables.adminWarehouseUpsertMaterial.run({
          auth: downgradedAuth,
          data: {
            mode: "create",
            profile: { name: "Racao", categoryId: "alimentacao", categoryName: "Alimentacao", unit: "kg" },
          },
        }),
      (err) => err.code === "permission-denied",
    );
    await assert.rejects(
      () =>
        warehouseCallables.adminWarehouseArchiveMaterial.run({
          auth: downgradedAuth,
          data: { id: "mat-1", reason: "teste" },
        }),
      (err) => err.code === "permission-denied",
    );
    assert.equal(writeCount, 0, "Solicitacao rejeitada nao pode realizar mutacoes");
  });

  it("11. Ausencia de perfil base com flags residuais (accessLevel='Admin', admin=true, inventory_manager=true, role='gestor') apos unassignment deve falhar fechado", async () => {
    // Registro antigo onde adminUnassignAccessProfile removeu access_profile_id,
    // mas restou accessLevel: 'Admin' ou flags residuais
    store.set("users/1011", {
      ra: "1011",
      active: true,
      deleted_at: null,
      accessLevel: "Admin",
      access_level: "administrador",
      admin: true,
      inventory_manager: true,
      role: "gestor",
      claim_role: "admin",
      roles: ["admin", "gestor", "almoxarifado"],
    });
    const staleAuth = makeAuth("1011", {
      admin: true,
      access_profile_id: "administrador",
      roles: ["admin"],
    });

    assert.equal(isReconciledAdmin(store.get("users/1011")), false);
    assert.equal(accessProfileIdFrom(staleAuth.token, store.get("users/1011")), "__sec02_no_profile__");
    await assert.rejects(
      () => requireAccessPermission(staleAuth, "access", "edit"),
      (err) => err.code === "permission-denied",
    );
    await assert.rejects(
      () => requireAccessPermission(staleAuth, "inventory", "create"),
      (err) => err.code === "permission-denied",
    );
    await assert.rejects(
      () => requireAccessPermission(staleAuth, "humans", "edit"),
      (err) => err.code === "permission-denied",
    );
    assert.equal(writeCount, 0);
  });

  it("12. Comportamento de isReconciledAdmin com registros conflitantes (explicit profile vs admin flags)", async () => {
    // Conflito A: access_profile_id = 'administrador', mas admin = false -> NEGADO
    const conflictA = {
      ra: "1012",
      active: true,
      access_profile_id: "administrador",
      admin: false,
    };
    assert.equal(isReconciledAdmin(conflictA), false);

    // Conflito B: access_profile_id = 'gestor', mas admin = true e accessLevel = 'Admin' -> NEGADO (nao e admin)
    const conflictB = {
      ra: "1013",
      active: true,
      access_profile_id: "gestor",
      admin: true,
      accessLevel: "Admin",
    };
    assert.equal(isReconciledAdmin(conflictB), false);

    // Conflito C: sem access_profile_id, mas admin = true e accessLevel = 'Admin' -> NEGADO
    const conflictC = {
      ra: "1014",
      active: true,
      admin: true,
      accessLevel: "Admin",
    };
    assert.equal(isReconciledAdmin(conflictC), false);

    // Caso valido: access_profile_id = 'administrador' e admin !== false -> PERMITIDO
    const validAdmin = {
      ra: "1015",
      active: true,
      access_profile_id: "administrador",
      admin: true,
    };
    assert.equal(isReconciledAdmin(validAdmin), true);
  });

  it("13. IR-01: is_k9_instructor=false tem precedencia absoluta sobre training_instructor=true e flags booleanas legadas", async () => {
    const userDoc = {
      ra: "1016",
      active: true,
      deleted_at: null,
      access_profile_id: "operador_k9",
      is_k9_instructor: false,
      training_instructor: true,
      instrutor_k9: true,
      instrutor: true,
      adestrador: true,
    };
    store.set("users/1016", userDoc);
    store.set("promotion_requests/promo-ir01", { status: "pending", dog_id: "dog-ir01" });

    const auth = makeAuth("1016", { access_profile_id: "operador_k9" });
    assert.equal(isQualifiedK9Instructor(userDoc), false);
    assert.equal(accessProfileIdFrom(auth.token, userDoc), "operador_k9");

    await assert.rejects(
      () => requireAccessPermission(auth, "training", "view"),
      (err) => err.code === "permission-denied",
    );
    await assert.rejects(
      () => requireAccessPermission(auth, "training", "approve"),
      (err) => err.code === "permission-denied",
    );
    await assert.rejects(
      () =>
        decidePromotionRequest.run({
          auth,
          data: { requestId: "promo-ir01", decision: "approved" },
        }),
      (err) => err.code === "permission-denied",
    );

    const k9ViewCaller = await requireAccessPermission(auth, "k9", "view");
    assert.equal(k9ViewCaller.ra, "1016");
    assert.equal(writeCount, 0);
    assert.equal(store.get("promotion_requests/promo-ir01").status, "pending");
  });

  it("14. IR-02: is_k9_instructor=false tem precedencia absoluta sobre roles[] e training_role legados", async () => {
    const userDoc = {
      ra: "1017",
      active: true,
      deleted_at: null,
      access_profile_id: "operador_k9",
      is_k9_instructor: false,
      roles: ["instrutor", "adestrador", "instrutor_k9"],
      training_role: "instrutor_k9",
    };
    store.set("users/1017", userDoc);
    store.set("promotion_requests/promo-ir02", { status: "pending", dog_id: "dog-ir02" });

    const auth = makeAuth("1017", { instrutor_k9: true });
    assert.equal(isQualifiedK9Instructor(userDoc), false);

    await assert.rejects(
      () => requireAccessPermission(auth, "training", "view"),
      (err) => err.code === "permission-denied",
    );
    await assert.rejects(
      () => requireAccessPermission(auth, "training", "approve"),
      (err) => err.code === "permission-denied",
    );
    await assert.rejects(
      () =>
        decidePromotionRequest.run({
          auth,
          data: { requestId: "promo-ir02", decision: "approved" },
        }),
      (err) => err.code === "permission-denied",
    );

    assert.equal(writeCount, 0);
    assert.equal(store.get("promotion_requests/promo-ir02").status, "pending");
  });

  it("15. JWT antigo pre-revogacao de instrutor deve ser negado em decidePromotionRequest sem mutacoes", async () => {
    const userDoc = {
      ra: "1018",
      active: true,
      deleted_at: null,
      access_profile_id: "operador_k9",
      is_k9_instructor: false,
      training_instructor: true,
      instrutor_k9: true,
      instrutor: true,
      adestrador: true,
      training_role: "instrutor_k9",
      roles: ["operador_k9", "instrutor_k9"],
    };
    store.set("users/1018", userDoc);
    store.set("promotion_requests/promo-stale", { status: "pending", dog_id: "dog-stale" });

    const staleInstructorAuth = makeAuth("1018", {
      instrutor_k9: true,
      training_instructor: true,
      role: "instrutor_k9",
      training_role: "instrutor_k9",
      roles: ["instrutor_k9"],
    });

    assert.equal(isQualifiedK9Instructor(userDoc), false);
    await assert.rejects(
      () => requireAccessPermission(staleInstructorAuth, "training", "view"),
      (err) => err.code === "permission-denied",
    );
    await assert.rejects(
      () => requireAccessPermission(staleInstructorAuth, "training", "approve"),
      (err) => err.code === "permission-denied",
    );
    await assert.rejects(
      () =>
        decidePromotionRequest.run({
          auth: staleInstructorAuth,
          data: { requestId: "promo-stale", decision: "rejected", reason: "bypass" },
        }),
      (err) => err.code === "permission-denied",
    );

    assert.equal(writeCount, 0);
    assert.equal(store.get("promotion_requests/promo-stale").status, "pending");
  });

  it("16. IR-03 e IR-05: Instrutor ativo canonico (operador_k9) e compatibilidade legada ratificada quando is_k9_instructor ausente", async () => {
    // 16a (IR-03): Instrutor canonico ativo + operador_k9, sem claims no JWT
    const canonicalInstructor = {
      ra: "1019",
      active: true,
      deleted_at: null,
      access_profile_id: "operador_k9",
      is_k9_instructor: true,
    };
    store.set("users/1019", canonicalInstructor);
    store.set("promotion_requests/promo-ir03", { status: "pending", dog_id: "dog-1" });

    const auth1019 = makeAuth("1019", {});
    assert.equal(isQualifiedK9Instructor(canonicalInstructor), true);
    assert.equal(accessProfileIdFrom(auth1019.token, canonicalInstructor), "operador_k9");

    assert.equal((await requireAccessPermission(auth1019, "training", "view")).ra, "1019");
    assert.equal((await requireAccessPermission(auth1019, "training", "approve")).ra, "1019");
    await assert.rejects(
      () => requireAccessPermission(auth1019, "inventory", "create"),
      (err) => err.code === "permission-denied",
    );
    await assert.rejects(
      () => requireAccessPermission(auth1019, "access", "edit"),
      (err) => err.code === "permission-denied",
    );
    await assert.rejects(
      () => requireAccessPermission(auth1019, "k9", "edit"),
      (err) => err.code === "permission-denied",
    );

    const decisionRes = await decidePromotionRequest.run({
      auth: auth1019,
      data: { requestId: "promo-ir03", decision: "approved" },
    });
    assert.deepEqual(decisionRes, { id: "promo-ir03", status: "approved" });
    assert.equal(writeCount, 1);
    const updatedPromo = store.get("promotion_requests/promo-ir03");
    assert.equal(updatedPromo.status, "approved");
    assert.equal(updatedPromo.dog_id, "dog-1");

    // 16b..16g (IR-05): Compatibilidade legada ratificada apenas quando is_k9_instructor ausente/undefined/null
    const legacyCompatibleCases = [
      { ra: "1020", active: true, training_instructor: true },
      { ra: "1021", active: true, is_k9_instructor: undefined, instrutor_k9: true },
      { ra: "1022", active: true, is_k9_instructor: null, instrutor: true },
      { ra: "1023", active: true, adestrador: true },
      { ra: "1024", active: true, training_role: "instrutor_k9" },
      { ra: "1025", active: true, training_role: "  Instrutor K9  " },
      { ra: "1025b", active: true, training_role: "adestrador" },
      { ra: "1025c", active: true, training_role: "adestrador_k9" },
      { ra: "1025d", active: true, training_role: "k9_instructor" },
      { ra: "1025e", active: true, roles: ["operador_k9", "adestrador"] },
      { ra: "1025f", active: true, roles: ["k9_instructor"] },
    ];
    for (const doc of legacyCompatibleCases) {
      store.set(`users/${doc.ra}`, doc);
      const auth = makeAuth(doc.ra, {});
      assert.equal(isQualifiedK9Instructor(doc), true, `Esperava compatibilidade legada para ${doc.ra}`);
      assert.equal(accessProfileIdFrom(auth.token, doc), "__sec02_no_profile__");
      assert.equal((await requireAccessPermission(auth, "training", "view")).ra, doc.ra);
      assert.equal((await requireAccessPermission(auth, "training", "approve")).ra, doc.ra);
      await assert.rejects(
        () => requireAccessPermission(auth, "k9", "view"),
        (err) => err.code === "permission-denied",
      );
      await assert.rejects(
        () => requireAccessPermission(auth, "inventory", "view"),
        (err) => err.code === "permission-denied",
      );
      await assert.rejects(
        () => requireAccessPermission(auth, "access", "edit"),
        (err) => err.code === "permission-denied",
      );
    }

    // Controle negativo: roles/training_role nao-instrutor e valor canonico nao-booleano (fail-closed)
    const nonInstructor = { ra: "1026", active: true, roles: ["operador_k9"], training_role: "condutor" };
    store.set("users/1026", nonInstructor);
    assert.equal(isQualifiedK9Instructor(nonInstructor), false);
    await assert.rejects(
      () => requireAccessPermission(makeAuth("1026", {}), "training", "approve"),
      (err) => err.code === "permission-denied",
    );

    const malformedCanonical = {
      ra: "1026b",
      active: true,
      is_k9_instructor: "true",
      training_instructor: true,
      roles: ["instrutor_k9"],
    };
    assert.equal(isQualifiedK9Instructor(malformedCanonical), false);
  });

  it("17. IR-04: Instructor Role sem Access Profile concede apenas training.view/approve e nunca fabrica perfil", async () => {
    const userDoc = {
      ra: "1027",
      active: true,
      deleted_at: null,
      is_k9_instructor: true,
    };
    store.set("users/1027", userDoc);
    store.set("promotion_requests/promo-ir04", { status: "pending", dog_id: "dog-ir04" });

    const auth = makeAuth("1027", {});
    assert.equal(accessProfileIdFrom(auth.token, userDoc), "__sec02_no_profile__");
    assert.equal(isQualifiedK9Instructor(userDoc), true);

    assert.equal((await requireAccessPermission(auth, "training", "view")).ra, "1027");
    assert.equal((await requireAccessPermission(auth, "training", "approve")).ra, "1027");

    for (const [mod, act] of [
      ["k9", "view"],
      ["k9", "edit"],
      ["inventory", "view"],
      ["inventory", "create"],
      ["access", "view"],
      ["access", "edit"],
      ["health", "view"],
      ["health", "create"],
      ["binomials", "edit"],
      ["training", "create"],
    ]) {
      await assert.rejects(
        () => requireAccessPermission(auth, mod, act),
        (err) => err.code === "permission-denied",
      );
    }
    assert.equal(writeCount, 0);

    const decisionRes = await decidePromotionRequest.run({
      auth,
      data: { requestId: "promo-ir04", decision: "approved" },
    });
    assert.deepEqual(decisionRes, { id: "promo-ir04", status: "approved" });
    assert.equal(writeCount, 1);
  });

  it("18. IR-07: Usuario inativo ou arquivado com is_k9_instructor=true e JWT de instrutor deve ser negado sem mutacoes", async () => {
    const inactiveVariants = [
      { ra: "1028", active: false, is_k9_instructor: true, access_profile_id: "operador_k9" },
      { ra: "1029", active: true, status: "Inativo", is_k9_instructor: true, access_profile_id: "operador_k9" },
      { ra: "1030", active: true, status: "inactive", is_k9_instructor: true, access_profile_id: "operador_k9" },
      { ra: "1030b", active: true, status: "  Inativo  ", is_k9_instructor: true, access_profile_id: "operador_k9" },
      { ra: "1031", active: true, deleted_at: "2026-11-20T10:00:00Z", is_k9_instructor: true, access_profile_id: "operador_k9" },
      { ra: "1032", active: true, archived_at: "2026-11-20T10:00:00Z", is_k9_instructor: true, access_profile_id: "operador_k9" },
    ];
    store.set("promotion_requests/promo-ir07", { status: "pending", dog_id: "dog-ir07" });

    for (const variant of inactiveVariants) {
      store.set(`users/${variant.ra}`, variant);
      const auth = makeAuth(variant.ra, {
        instrutor_k9: true,
        training_instructor: true,
        role: "instrutor_k9",
        training_role: "instrutor_k9",
        roles: ["instrutor_k9"],
      });

      assert.equal(isQualifiedK9Instructor(variant), false, `Esperava false para variante ${variant.ra}`);
      await assert.rejects(
        () => requireAccessPermission(auth, "training", "view"),
        (err) => err.code === "permission-denied",
      );
      await assert.rejects(
        () => requireAccessPermission(auth, "training", "approve"),
        (err) => err.code === "permission-denied",
      );
      await assert.rejects(
        () =>
          decidePromotionRequest.run({
            auth,
            data: { requestId: "promo-ir07", decision: "approved" },
          }),
        (err) => err.code === "permission-denied",
      );
    }

    assert.equal(writeCount, 0);
    assert.equal(store.get("promotion_requests/promo-ir07").status, "pending");
  });

  it("19. IR-06: Documento users/{ra} ausente com claims de instrutor e admin no JWT deve falhar fechado sem mutacoes", async () => {
    store.set("promotion_requests/promo-ir06", { status: "pending", dog_id: "dog-ir06" });
    const ghostAuth = makeAuth("9998", {
      instrutor_k9: true,
      training_instructor: true,
      role: "instrutor_k9",
      training_role: "instrutor_k9",
      roles: ["instrutor_k9", "admin"],
      admin: true,
      access_profile_id: "instrutor_k9",
    });

    await assert.rejects(
      () => requireAccessPermission(ghostAuth, "training", "view"),
      (err) => err.code === "permission-denied",
    );
    await assert.rejects(
      () => requireAccessPermission(ghostAuth, "training", "approve"),
      (err) => err.code === "permission-denied",
    );
    await assert.rejects(
      () =>
        decidePromotionRequest.run({
          auth: ghostAuth,
          data: { requestId: "promo-ir06", decision: "approved" },
        }),
      (err) => err.code === "permission-denied",
    );

    assert.equal(writeCount, 0);
    assert.equal(store.get("promotion_requests/promo-ir06").status, "pending");
  });
});
