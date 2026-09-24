import * as assert from "assert";
import {HttpsError} from "firebase-functions/v2/https";
import {
  AccessHomologationSnapshotDeps,
  buildAdminGetAccessHomologationSnapshotHandler,
  createAdminAccessHomologationSnapshotDeps,
  evaluateDogAccess,
  maskIdentifier,
  maskRa,
  parseAccessHomologationSnapshotRequest,
  sanitizePermissions,
  SnapshotAuthUser,
  SnapshotDocument,
  snapshotFingerprint,
} from "./admin_access_homologation_snapshot";

type JsonMap = Record<string, unknown>;

const requestData = {
  dogId: "DcUtestREWv",
  excludedRa: "11231640",
  operatorProfileId: "operador_k9",
  targetRa: "61231640",
  temporaryProfileId: "operador_k9_homolog_ux05_weight",
};

const updateTime = "2026-08-05T01:00:00.000Z";

function document(data: JsonMap = {}, exists = true): SnapshotDocument {
  return {data, exists, updateTime: exists ? updateTime : null};
}

function authUser(uid: string, profile = "operador_k9", disabled = false): SnapshotAuthUser {
  return {customClaims: {access_profile_id: profile}, disabled, uid};
}

function fixture() {
  const docs = new Map<string, SnapshotDocument>([
    [`users/${requestData.targetRa}`, document({active: true, access_profile_id: "operador_k9", auth_uid: "uxy123oLx1", role: "condutor"})],
    [`users/${requestData.excludedRa}`, document({active: true, access_profile_id: "operador_k9", auth_uid: "NDM123g4y2", role: "condutor"})],
    [`access_profiles/${requestData.operatorProfileId}`, document({active: true, permissions: {access: {view: true}, health: {view: true}}, scope: "global", status: "active"})],
    [`access_profiles/${requestData.temporaryProfileId}`, document({}, false)],
    [`dogs/${requestData.dogId}`, document({active: true, handler_id: requestData.targetRa, status: "active"})],
  ]);
  const users = [
    {data: {active: true, access_profile_id: "operador_k9", auth_uid: "uxy123oLx1"}, id: requestData.targetRa},
    {data: {active: true, access_profile_id: "operador_k9", auth_uid: "NDM123g4y2"}, id: requestData.excludedRa},
    {data: {active: true, access_profile_id: "operador_k9", auth_uid: "usr333aaaa"}, id: "30000001"},
    {data: {active: true, access_profile_id: "operador_k9", auth_uid: "usr444bbbb"}, id: "40000001"},
  ];
  const auth = new Map<string, SnapshotAuthUser | null>([
    [requestData.targetRa, authUser("uxy123oLx1")],
    [requestData.excludedRa, authUser("NDM123g4y2")],
    ["30000001", authUser("usr333aaaa")],
    ["40000001", authUser("usr444bbbb")],
  ]);
  const logs: JsonMap[] = [];
  const deps: AccessHomologationSnapshotDeps = {
    authorize: async (callAuth) => {
      if (!callAuth) throw new HttpsError("unauthenticated", "Autenticacao obrigatoria.");
      if (callAuth.token.admin !== true) throw new HttpsError("permission-denied", "Administrador obrigatorio.");
      return {ra: "90000001", uid: callAuth.uid};
    },
    correlationId: () => "corr-fixed",
    getAuthUser: async (_user, ra) => auth.get(ra) ?? null,
    getDocuments: async (paths) => paths.map((path) => docs.get(path) ?? document({}, false)),
    hasActiveShift: async () => false,
    listActiveUsers: async (limit) => ({truncated: users.length >= limit, users: users.slice(0, limit)}),
    logInfo: (entry) => logs.push(entry),
    logWarning: (entry) => logs.push(entry),
    now: () => new Date("2026-08-05T02:00:00.000Z"),
    projectId: "canil-gcm",
  };
  return {auth, deps, docs, logs, users};
}

function callableRequest(data: unknown = requestData, admin = true) {
  return {auth: {uid: "admin1234567", token: {admin}}, data};
}

async function snapshot(state = fixture(), data: unknown = requestData): Promise<any> {
  return buildAdminGetAccessHomologationSnapshotHandler(state.deps)(callableRequest(data));
}

let passed = 0;
let failed = 0;

async function test(name: string, fn: () => void | Promise<void>) {
  try {
    await fn();
    passed++;
    console.log(`ok - ${name}`);
  } catch (error) {
    failed++;
    console.error(`FAIL - ${name}`, error);
  }
}

function hasBlocker(result: any, code: string): boolean {
  return result.hardGate.blockers.includes(code);
}

async function main() {
  await test("01 nao autenticado", async () => {
    const state = fixture();
    await assert.rejects(buildAdminGetAccessHomologationSnapshotHandler(state.deps)({data: requestData}), (error: unknown) => error instanceof HttpsError && error.code === "unauthenticated");
  });
  await test("02 operador sem autoridade", async () => {
    const state = fixture();
    await assert.rejects(buildAdminGetAccessHomologationSnapshotHandler(state.deps)(callableRequest(requestData, false)), (error: unknown) => error instanceof HttpsError && error.code === "permission-denied");
  });
  await test("03 gestor sem autoridade", async () => {
    const state = fixture();
    await assert.rejects(buildAdminGetAccessHomologationSnapshotHandler(state.deps)({auth: {uid: "manager", token: {role: "gestor"}}, data: requestData}), (error: unknown) => error instanceof HttpsError && error.code === "permission-denied");
  });
  await test("03b usuario comum sem autoridade", async () => {
    const state = fixture();
    await assert.rejects(buildAdminGetAccessHomologationSnapshotHandler(state.deps)({auth: {uid: "common", token: {role: "user"}}, data: requestData}), (error: unknown) => error instanceof HttpsError && error.code === "permission-denied");
  });
  await test("04 administrador autorizado", async () => assert.strictEqual((await snapshot()).projectId, "canil-gcm"));
  await test("05 request nao objeto", () => {
    for (const invalid of [null, [], 1, "request"]) {
      assert.throws(() => parseAccessHomologationSnapshotRequest(invalid), HttpsError);
    }
  });
  await test("06 request estrito rejeita extras, tipos e IDs perigosos", () => {
    const invalidRequests = [
      {...requestData, admin: true},
      {...requestData, dogId: "dogs/target"},
      {...requestData, dogId: ".."},
      {...requestData, dogId: "dog\ncontrol"},
      {...requestData, dogId: ""},
      {...requestData, dogId: "x".repeat(121)},
      {...requestData, dogId: 123},
      {...requestData, operatorProfileId: null},
      {...requestData, targetUid: "forged"},
    ];
    for (const invalid of invalidRequests) {
      assert.throws(() => parseAccessHomologationSnapshotRequest(invalid), HttpsError);
    }
  });
  await test("07 request com campo ausente", () => {
    const {dogId: _dogId, ...missing} = requestData;
    assert.throws(() => parseAccessHomologationSnapshotRequest(missing), HttpsError);
  });
  await test("08 request rejeita email como RA", () => assert.throws(() => parseAccessHomologationSnapshotRequest({...requestData, targetRa: "x@y.com"}), HttpsError));
  await test("09 target e excluded iguais", () => assert.throws(() => parseAccessHomologationSnapshotRequest({...requestData, excludedRa: requestData.targetRa}), HttpsError));
  await test("10 target document ausente", async () => {
    const state = fixture(); state.docs.set(`users/${requestData.targetRa}`, document({}, false));
    assert.ok(hasBlocker(await snapshot(state), "target_user_document_missing"));
  });
  await test("11 target Auth ausente", async () => {
    const state = fixture(); state.auth.set(requestData.targetRa, null);
    assert.ok(hasBlocker(await snapshot(state), "target_auth_user_missing"));
    const unavailableAuth = {
      getUser: async () => Promise.reject({code: "auth/internal-error"}),
      getUserByEmail: async () => Promise.reject({code: "auth/internal-error"}),
    };
    const deps = createAdminAccessHomologationSnapshotDeps({
      auth: unavailableAuth as never,
      authorize: state.deps.authorize,
      db: {} as never,
      projectId: "canil-gcm",
    });
    await assert.rejects(
      deps.getAuthUser({auth_uid: "unavailable-user"}, requestData.targetRa),
      (error: unknown) => error instanceof HttpsError && error.code === "unavailable",
    );
  });
  await test("12 target Auth disabled", async () => {
    const state = fixture(); state.auth.set(requestData.targetRa, authUser("uxy123oLx1", "operador_k9", true));
    assert.ok(hasBlocker(await snapshot(state), "target_auth_disabled"));
  });
  await test("13 target inativo", async () => {
    const state = fixture(); state.docs.set(`users/${requestData.targetRa}`, document({active: false, access_profile_id: "operador_k9", auth_uid: "uxy123oLx1"}));
    assert.ok(hasBlocker(await snapshot(state), "target_user_inactive"));
  });
  await test("14 claim e profile coerentes", async () => assert.strictEqual((await snapshot()).targetUser.profileIdsCoherent, true));
  await test("15 claim e profile divergentes", async () => {
    const state = fixture(); state.auth.set(requestData.targetRa, authUser("uxy123oLx1", "gestor")); state.docs.set(`dogs/${requestData.dogId}`, document({active: true, handler_id: requestData.excludedRa, status: "active"}));
    const result = await snapshot(state);
    assert.ok(hasBlocker(result, "target_profile_claim_mismatch"));
    assert.ok(hasBlocker(result, "target_operator_profile_mismatch"));
    assert.deepStrictEqual(result.dogAccessEvaluation, {allowed: false, internalRole: null, reason: "unknown"});
  });
  await test("16 excluded distinto", async () => assert.strictEqual((await snapshot()).excludedUser.distinctFromTarget, true));
  await test("17 excluded Auth igual ao target bloqueia", async () => {
    const state = fixture(); state.auth.set(requestData.excludedRa, authUser("uxy123oLx1"));
    assert.ok(hasBlocker(await snapshot(state), "excluded_user_not_distinct"));
  });
  await test("18 Operador existente e status estrito", async () => {
    assert.strictEqual((await snapshot()).operatorProfile.exists, true);
    const state = fixture(); state.docs.set(`access_profiles/${requestData.operatorProfileId}`, document({permissions: {}, scope: "global", status: "pending"}));
    const result = await snapshot(state);
    assert.strictEqual(result.operatorProfile.status, "inactive");
    assert.ok(hasBlocker(result, "operator_profile_inactive"));
  });
  await test("19 Operador ausente", async () => {
    const state = fixture(); state.docs.set(`access_profiles/${requestData.operatorProfileId}`, document({}, false));
    assert.ok(hasBlocker(await snapshot(state), "operator_profile_missing"));
  });
  await test("20 scope global", async () => assert.strictEqual((await snapshot()).operatorProfile.scope, "global"));
  await test("21 scope inesperado", async () => {
    for (const scope of ["own_records", "GLOBAL", "legacy", null, 1]) {
      const state = fixture(); state.docs.set(`access_profiles/${requestData.operatorProfileId}`, document({active: true, permissions: {}, scope}));
      const result = await snapshot(state);
      assert.ok(hasBlocker(result, "operator_scope_unexpected"));
      assert.strictEqual(result.operatorProfile.scope, scope === "own_records" ? "own_records" : null);
    }
    const trimmed = fixture(); trimmed.docs.set(`access_profiles/${requestData.operatorProfileId}`, document({active: true, permissions: {}, scope: " global "}));
    assert.strictEqual((await snapshot(trimmed)).operatorProfile.scope, "global");
  });
  await test("22 record_routine ausente", async () => assert.deepStrictEqual((await snapshot()).operatorProfile.recordRoutine, {present: false, value: null}));
  await test("23 record_routine false", async () => {
    const state = fixture(); state.docs.set(`access_profiles/${requestData.operatorProfileId}`, document({active: true, permissions: {health: {record_routine: false}}, scope: "global"}));
    const result = await snapshot(state); assert.deepStrictEqual(result.operatorProfile.recordRoutine, {present: true, value: false}); assert.ok(hasBlocker(result, "record_routine_already_present"));
  });
  await test("24 record_routine true", async () => {
    const state = fixture(); state.docs.set(`access_profiles/${requestData.operatorProfileId}`, document({active: true, permissions: {health: {record_routine: true}}, scope: "global"}));
    const result = await snapshot(state); assert.strictEqual(result.operatorProfile.recordRoutine.value, true); assert.ok(hasBlocker(result, "record_routine_already_present"));
    const invalid = fixture(); invalid.docs.set(`access_profiles/${requestData.operatorProfileId}`, document({active: true, permissions: {health: {record_routine: "true"}}, scope: "global"}));
    const invalidResult = await snapshot(invalid);
    assert.deepStrictEqual(invalidResult.operatorProfile.recordRoutine, {present: true, value: null});
    assert.ok(hasBlocker(invalidResult, "record_routine_invalid"));
    assert.strictEqual(hasBlocker(invalidResult, "record_routine_already_present"), false);
  });
  await test("25 profile temporario ausente", async () => assert.strictEqual((await snapshot()).temporaryProfile.exists, false));
  await test("26 profile temporario existente", async () => {
    const state = fixture(); state.docs.set(`access_profiles/${requestData.temporaryProfileId}`, document({active: true, permissions: {health: {record_routine: true}}, scope: "global"}));
    assert.ok(hasBlocker(await snapshot(state), "temporary_profile_exists"));
  });
  await test("27 permissions sanitizadas e deterministicas", () => {
    const hostile = JSON.parse('{"constructor":{"grant":true},"prototype":{"grant":true},"__proto__":{"grant":true},"Health":{"VIEW":true,"edit":false,"bad":"true"}}');
    assert.deepStrictEqual(sanitizePermissions(hostile), {health: {view: true}});
    assert.deepStrictEqual(
      sanitizePermissions({zeta: {write: true}, Alpha: {VIEW: true}}),
      sanitizePermissions({Alpha: {VIEW: true}, zeta: {write: true}}),
    );
    const inherited = Object.create({health: {record_routine: true}}) as JsonMap;
    inherited.access = {view: true};
    assert.deepStrictEqual(sanitizePermissions(inherited), {access: {view: true}});
  });
  await test("28 quatro usuarios associados e truncamento bloqueado", async () => {
    assert.strictEqual((await snapshot()).operatorProfile.associationSummary.documentCount, 4);
    const state = fixture();
    while (state.users.length < 201) {
      state.users.push({data: {active: true, access_profile_id: "gestor", auth_uid: `scan-${state.users.length}`}, id: String(50000000 + state.users.length)});
    }
    const result = await snapshot(state);
    assert.ok(hasBlocker(result, "association_scan_truncated"));
    assert.ok(result.hardGate.warnings.includes("association_scan_truncated"));
    assert.strictEqual(result.hardGate.ready, false);
  });
  await test("29 Auth enabled count", async () => {
    assert.strictEqual((await snapshot()).operatorProfile.associationSummary.authEnabledCount, 4);
    const state = fixture(); state.auth.set("30000001", authUser("usr333aaaa", "operador_k9", true));
    assert.strictEqual((await snapshot(state)).operatorProfile.associationSummary.authEnabledCount, 3);
  });
  await test("30 claim coherent count", async () => {
    assert.strictEqual((await snapshot()).operatorProfile.associationSummary.claimCoherentCount, 4);
    const state = fixture(); state.auth.set("30000001", authUser("usr333aaaa", "gestor"));
    assert.strictEqual((await snapshot(state)).operatorProfile.associationSummary.claimCoherentCount, 3);
  });
  await test("31 Apolo existente", async () => assert.strictEqual((await snapshot()).dog.exists, true));
  await test("32 Apolo inativo", async () => {
    const state = fixture(); state.docs.set(`dogs/${requestData.dogId}`, document({active: false, handler_id: requestData.targetRa}));
    assert.ok(hasBlocker(await snapshot(state), "dog_inactive"));
  });
  await test("33 aliases de vinculo com target", async () => {
    for (const field of ["conductorRa", "conductor_ra", "handlerId", "handler_id"]) {
      const state = fixture(); state.docs.set(`dogs/${requestData.dogId}`, document({active: true, [field]: requestData.targetRa, status: "active"}));
      assert.strictEqual((await snapshot(state)).dog.linkedToTarget, true);
    }
  });
  await test("34 acesso por global scope", () => assert.deepStrictEqual(evaluateDogAccess({activeShift: false, directLink: false, dogExists: true, scope: "global"}), {allowed: true, reason: "global_scope"}));
  await test("35 acesso por vinculo", () => assert.deepStrictEqual(evaluateDogAccess({activeShift: false, directLink: true, dogExists: true, scope: "own_records"}), {allowed: true, reason: "direct_link"}));
  await test("36 acesso por turno", () => assert.deepStrictEqual(evaluateDogAccess({activeShift: true, directLink: false, dogExists: true, scope: "own_records"}), {allowed: true, reason: "active_shift"}));
  await test("37 acesso negado ou desconhecido", () => {
    assert.deepStrictEqual(evaluateDogAccess({activeShift: false, directLink: false, dogExists: true, scope: "own_records"}), {allowed: false, reason: "denied"});
    assert.deepStrictEqual(evaluateDogAccess({activeShift: false, directLink: false, dogExists: false, scope: "global"}), {allowed: false, reason: "unknown"});
    assert.deepStrictEqual(evaluateDogAccess({activeShift: false, directLink: false, dogExists: true, scope: null}), {allowed: false, reason: "unknown"});
  });
  await test("38 internal role condutor", async () => assert.strictEqual((await snapshot()).targetUser.internalRole, "condutor"));
  await test("39 internal role admin", async () => {
    const state = fixture(); state.docs.set(`users/${requestData.targetRa}`, document({active: true, access_profile_id: "administrador", admin: true, auth_uid: "uxy123oLx1"})); state.auth.set(requestData.targetRa, authUser("uxy123oLx1", "administrador"));
    state.docs.set(`dogs/${requestData.dogId}`, document({active: true, handler_id: requestData.excludedRa, status: "active"}));
    const adminDocumentResult = await snapshot(state);
    assert.strictEqual(adminDocumentResult.targetUser.internalRole, "admin");
    assert.deepStrictEqual(adminDocumentResult.dogAccessEvaluation, {allowed: false, internalRole: "admin", reason: "unknown"});
    const profileNameOnly = fixture(); profileNameOnly.docs.set(`users/${requestData.targetRa}`, document({active: true, access_profile_id: "administrador", auth_uid: "uxy123oLx1"})); profileNameOnly.auth.set(requestData.targetRa, authUser("uxy123oLx1", "administrador"));
    const profileNameOnlyResult = await snapshot(profileNameOnly);
    assert.strictEqual(profileNameOnlyResult.targetUser.managedClaims.adminBypass, false);
    assert.strictEqual(profileNameOnlyResult.targetUser.internalRole, "condutor");
  });
  await test("39b internal role segue admin role claim canonica", async () => {
    const state = fixture();
    state.auth.set(requestData.targetRa, {customClaims: {access_profile_id: "operador_k9", role: "admin"}, disabled: false, uid: "uxy123oLx1"});
    assert.strictEqual((await snapshot(state)).targetUser.internalRole, "admin");
  });
  await test("40 updateTimes reais do adapter", async () => {
    const result = await snapshot(); assert.strictEqual(result.targetUser.documentUpdateTime, updateTime); assert.strictEqual(result.operatorProfile.documentUpdateTime, updateTime); assert.strictEqual(result.dog.documentUpdateTime, updateTime);
  });
  await test("41 fingerprint deterministico e sensivel a preconditions", async () => {
    assert.strictEqual(snapshotFingerprint({b: 2, a: 1}), snapshotFingerprint({a: 1, b: 2}));
    const baseline = await snapshot();
    const changed = fixture(); changed.docs.set(`dogs/${requestData.dogId}`, document({active: true, handler_id: requestData.excludedRa, status: "active"}));
    assert.notStrictEqual((await snapshot(changed)).snapshotFingerprint, baseline.snapshotFingerprint);
  });
  await test("42 fingerprint ignora inspectedAt por contrato", async () => {
    const first = fixture();
    const second = fixture();
    second.deps.now = () => new Date("2030-01-01T00:00:00.000Z");
    second.deps.correlationId = () => "different-correlation";
    const [left, right] = await Promise.all([snapshot(first), snapshot(second)]);
    assert.notStrictEqual(left.inspectedAt, right.inspectedAt);
    assert.strictEqual(left.snapshotFingerprint, right.snapshotFingerprint);
  });
  await test("43 ausencia de dados sensiveis", async () => {
    const state = fixture();
    state.docs.set(`users/${requestData.targetRa}`, document({active: true, access_profile_id: "operador_k9", auth_uid: "uxy123oLx1", email: "secret@example.invalid", passwordHash: "hash-secret", phone: "+5511999999999", role: "condutor"}));
    state.auth.set(requestData.targetRa, {customClaims: {access_profile_id: "operador_k9", arbitrarySecret: "claim-secret"}, disabled: false, uid: "uxy123oLx1"});
    const json = JSON.stringify(await snapshot(state));
    for (const forbidden of ["@gcm", "secret@example", "hash-secret", "+5511", "claim-secret", "passwordHash", "passwordSalt", "refreshToken", "idToken", "providerData", "tokensValidAfterTime", "uxy123oLx1", requestData.targetRa]) assert.strictEqual(json.includes(forbidden), false);
  });
  await test("44 UID e RA mascarados", async () => {
    const result = await snapshot(); assert.strictEqual(result.targetUser.authUidMasked, "uxy…oLx1"); assert.strictEqual(result.targetUser.raMasked, "6…1640");
    for (const short of ["", "a", "ab", "✓"]) assert.strictEqual(maskIdentifier(short), "…");
    for (const shortRa of ["", "1", "1234", "12345"]) assert.strictEqual(maskRa(shortRa), "…");
  });
  await test("45 managed claims minimizadas", async () => assert.deepStrictEqual((await snapshot()).targetUser.managedClaims, {accessProfileId: "operador_k9", adminBypass: false}));
  await test("46 nenhum setCustomUserClaims possivel pelas deps", () => assert.strictEqual("setCustomUserClaims" in fixture().deps, false));
  await test("47 nenhum Firestore write possivel pelas deps", () => {
    const deps = fixture().deps as unknown as JsonMap; for (const name of ["set", "update", "create", "delete", "add"]) assert.strictEqual(name in deps, false);
  });
  await test("48 nenhum audit trail append", async () => {
    const state = fixture(); await snapshot(state); assert.strictEqual(state.logs.length, 1); assert.strictEqual(JSON.stringify(state.logs).includes("audit_trail"), false);
    assert.deepStrictEqual(Object.keys(state.logs[0]).sort(), ["actorUidMasked", "blockerCount", "correlationId", "dogIdMasked", "event", "hardGateReady", "targetRaMasked"]);
    const failing = fixture(); failing.deps.getDocuments = async () => Promise.reject(new Error("secret-email@example.invalid"));
    await assert.rejects(snapshot(failing), (error: unknown) => error instanceof HttpsError && error.code === "internal" && !error.message.includes("secret-email"));
    assert.deepStrictEqual(failing.logs, [{correlationId: "corr-fixed", event: "admin_access_homologation_snapshot_read_failed"}]);
  });
  await test("49 response estavel", async () => assert.deepStrictEqual(await snapshot(), await snapshot()));
  await test("50 hard gate ready baseline", async () => assert.deepStrictEqual((await snapshot()).hardGate, {blockers: [], ready: true, warnings: []}));

  console.log(`\n${passed} passed, ${failed} failed`);
  if (failed) process.exit(1);
}

void main();
