/**
 * GATE-C.B — autoridade explícita do lifecycle de restrição (Option B).
 *
 * Decisão humana da Control Tower: administração técnica NÃO implica autoridade
 * clínica. ISSUE / RELEASE / CANCEL exigem capability explícita para TODOS os
 * atores, inclusive administradores.
 *
 * Duas famílias de prova neste arquivo:
 *
 *  1. COMPORTAMENTAL — `decideRestrictionLifecycleGrant` é função pura, então a
 *     matriz de autoridade é testável sem emulador.
 *  2. ARQUITETURAL — verificações estáticas sobre o texto de `index.ts`, no
 *     mesmo espírito de `shift_authorization_architecture_test.ts`. Elas
 *     impedem a regressão que este gate existe para evitar: alguém "unificar"
 *     o caminho de restrição de volta no helper genérico e reintroduzir o
 *     bypass administrativo sem que nenhum teste comportamental falhe.
 *
 * Stage GATE-C.B — implementação local. Não deployado.
 */
import * as assert from "assert";
import * as fs from "fs";
import * as path from "path";
import {
  decideRestrictionLifecycleGrant,
  isAdminToken,
  isAdminUserRecord,
  profileGrantsPermission,
  type RestrictionGrantDenialReason,
  type RestrictionLifecycleAction,
} from "./index";
import {recordedByPayload} from "./health_restriction_logic";

type JsonMap = Record<string, unknown>;

const SRC_DIR = __dirname.endsWith("lib") ?
  path.join(__dirname, "..", "src") :
  __dirname;

function readSource(relative: string): string {
  return fs.readFileSync(path.join(SRC_DIR, relative), "utf8");
}

/** Remove comentários, para que uma menção explicativa não gere falso positivo. */
function stripComments(source: string): string {
  return source
    .replace(/\/\*[\s\S]*?\*\//g, "")
    .replace(/^\s*\/\/.*$/gm, "");
}

const ALL_ACTIONS: RestrictionLifecycleAction[] = [
  "issue_restriction",
  "release_restriction",
  "cancel_restriction",
];

/** Perfil ativo concedendo exatamente as actions informadas. */
function profileWith(actions: RestrictionLifecycleAction[]): JsonMap {
  const health: JsonMap = {view: true};
  for (const action of actions) health[action] = true;
  return {status: "active", scope: "own_records", permissions: {health}};
}

function decide(
  action: RestrictionLifecycleAction,
  profileDoc: JsonMap | undefined,
  userDoc: JsonMap | undefined = {},
) {
  return decideRestrictionLifecycleGrant({
    authPresent: true,
    ra: "12345",
    userDoc,
    profileDoc,
    action,
  });
}

function assertGranted(
  action: RestrictionLifecycleAction,
  profileDoc: JsonMap,
  label: string,
) {
  assert.deepStrictEqual(
    decide(action, profileDoc),
    {kind: "granted"},
    `${label} deveria conceder ${action}`,
  );
}

function assertDenied(
  action: RestrictionLifecycleAction,
  profileDoc: JsonMap | undefined,
  reason: RestrictionGrantDenialReason,
  label: string,
  userDoc: JsonMap | undefined = {},
) {
  assert.deepStrictEqual(
    decide(action, profileDoc, userDoc),
    {kind: "denied", reason},
    `${label} deveria negar ${action} com motivo ${reason}`,
  );
}

let failed = 0;

async function test(name: string, fn: () => void | Promise<void>): Promise<void> {
  try {
    await fn();
    console.log(`ok - restriction-capability ${name}`);
  } catch (error) {
    failed += 1;
    console.error(`FAIL - restriction-capability ${name}`);
    console.error(error);
  }
}

async function main(): Promise<void> {
  // ───────────────────────────────────────────────────────────────────────────
  // §9 — MATRIZ DE AUTORIDADE: NÃO-ADMIN
  // ───────────────────────────────────────────────────────────────────────────

  await test("operador com issue grant recebe ISSUE", () => {
    assertGranted(
      "issue_restriction",
      profileWith(["issue_restriction", "release_restriction"]),
      "operador_k9",
    );
  });

  await test("operador com release grant recebe RELEASE", () => {
    assertGranted(
      "release_restriction",
      profileWith(["issue_restriction", "release_restriction"]),
      "operador_k9",
    );
  });

  await test("operador sem cancel grant é NEGADO em CANCEL", () => {
    // Núcleo da matriz aprovada: CANCEL é invalidação administrativa sem prova
    // clínica, então issue+release NÃO podem implicá-lo.
    assertDenied(
      "cancel_restriction",
      profileWith(["issue_restriction", "release_restriction"]),
      "capability-not-granted",
      "operador_k9",
    );
  });

  await test("gestor com os três grants recebe os três", () => {
    const gestor = profileWith(ALL_ACTIONS);
    for (const action of ALL_ACTIONS) assertGranted(action, gestor, "gestor");
  });

  await test("instrutor sem grants é NEGADO nos três", () => {
    const instrutor = profileWith([]);
    for (const action of ALL_ACTIONS) {
      assertDenied(
        action,
        instrutor,
        "capability-not-granted",
        "instrutor_k9",
        {},
      );
    }
  });

  await test("health.create/edit NÃO implicam autoridade de restrição", () => {
    const operador = {
      status: "active",
      permissions: {health: {view: true, create: true, edit: true}},
    };
    for (const action of ALL_ACTIONS) {
      assertDenied(action, operador, "capability-not-granted", "health.create+edit");
    }
  });

  // ───────────────────────────────────────────────────────────────────────────
  // §9 — ADMIN TOKEN e MIRROR ADMIN: o bypass não existe mais neste caminho
  // ───────────────────────────────────────────────────────────────────────────

  await test("admin token sem grant explícito é NEGADO nos três", () => {
    // `decideRestrictionLifecycleGrant` não recebe sinal de admin por contrato:
    // a autoridade é o perfil. Um token administrativo cujo perfil resolvido
    // não concede a action é negado como qualquer outro ator.
    const adminProfileSemGrant: JsonMap = {
      status: "active",
      scope: "global",
      permissions: {
        health: {view: true, create: true, edit: true},
        access: {create: true, edit: true, approve: true},
      },
    };
    for (const action of ALL_ACTIONS) {
      assertDenied(
        action,
        adminProfileSemGrant,
        "capability-not-granted",
        "administrador (token)",
        {accessLevel: "administrador", admin: true},
      );
    }
  });

  await test("mirror admin sem grant explícito é NEGADO nos três", () => {
    const adminMirror: JsonMap = {accessLevel: "administrador"};
    const perfilSemGrant = profileWith([]);
    for (const action of ALL_ACTIONS) {
      assertDenied(
        action,
        perfilSemGrant,
        "capability-not-granted",
        "administrador (mirror)",
        adminMirror,
      );
    }
  });

  await test("admin flags no espelho não alteram a decisão", () => {
    // Prova direta de que `user.admin === true` e `accessLevel: "admin"` — os
    // dois gatilhos de `isAdminUserRecord` — não concedem nada aqui.
    assert.strictEqual(isAdminUserRecord({admin: true}), true);
    assert.strictEqual(
      isAdminUserRecord({accessLevel: "administrador"}),
      true,
    );
    for (const userDoc of [{admin: true}, {accessLevel: "administrador"}]) {
      assertDenied(
        "cancel_restriction",
        profileWith([]),
        "capability-not-granted",
        "espelho admin",
        userDoc,
      );
    }
  });

  await test("admin COM grant explícito recebe apenas a action concedida", () => {
    // Política futura permanece expressável: se a Control Tower decidir
    // conceder, a concessão é explícita e granular — não um bypass.
    const adminComIssue = profileWith(["issue_restriction"]);
    assertGranted("issue_restriction", adminComIssue, "administrador+grant");
    assertDenied(
      "release_restriction",
      adminComIssue,
      "capability-not-granted",
      "administrador+grant",
    );
    assertDenied(
      "cancel_restriction",
      adminComIssue,
      "capability-not-granted",
      "administrador+grant",
    );
  });

  // ───────────────────────────────────────────────────────────────────────────
  // FALHA FECHADA — estado de autorização degradado
  // ───────────────────────────────────────────────────────────────────────────

  await test("auth ausente nega", () => {
    assert.deepStrictEqual(
      decideRestrictionLifecycleGrant({
        authPresent: false,
        ra: "12345",
        userDoc: {},
        profileDoc: profileWith(ALL_ACTIONS),
        action: "issue_restriction",
      }),
      {kind: "denied", reason: "missing-auth"},
    );
  });

  await test("RA não resolvível nega mesmo com perfil completo", () => {
    for (const ra of ["", "   "]) {
      assert.deepStrictEqual(
        decideRestrictionLifecycleGrant({
          authPresent: true,
          ra,
          userDoc: {},
          profileDoc: profileWith(ALL_ACTIONS),
          action: "issue_restriction",
        }),
        {kind: "denied", reason: "unresolved-ra"},
      );
    }
  });

  await test("espelho de usuário ausente nega", () => {
    // Chamada direta, sem os helpers: passar `undefined` a um parâmetro com
    // valor default em JS ATIVA o default (`{}`), o que faria este caso testar
    // "espelho presente e vazio" em vez de "espelho ausente".
    assert.deepStrictEqual(
      decideRestrictionLifecycleGrant({
        authPresent: true,
        ra: "12345",
        userDoc: undefined,
        profileDoc: profileWith(ALL_ACTIONS),
        action: "issue_restriction",
      }),
      {kind: "denied", reason: "missing-user-mirror"},
    );
  });

  await test("espelho presente e vazio NÃO é confundido com ausente", () => {
    // `{}` é um espelho válido: a decisão prossegue e a autoridade passa a ser
    // o grant do perfil. A distinção `undefined` vs `{}` é load-bearing.
    assertGranted("issue_restriction", profileWith(ALL_ACTIONS), "espelho vazio");
  });

  await test("usuário soft-deleted nega", () => {
    assertDenied(
      "issue_restriction",
      profileWith(ALL_ACTIONS),
      "user-soft-deleted",
      "soft-deleted",
      {deleted_at: "2026-08-21T00:00:00Z"},
    );
  });

  await test("perfil de acesso ausente nega", () => {
    assertDenied(
      "issue_restriction",
      undefined,
      "missing-access-profile",
      "sem access_profiles/{id}",
    );
  });

  await test("perfil inativo nega mesmo com a capability presente", () => {
    for (const status of ["inactive", "", "disabled", 42, true]) {
      const perfil = {...profileWith(ALL_ACTIONS), status};
      assertDenied(
        "issue_restriction",
        perfil,
        "inactive-access-profile",
        `status=${JSON.stringify(status)}`,
      );
    }
  });

  await test("status ausente é tolerado como ativo (paridade com o gate canônico)", () => {
    // Paridade deliberada com `profileGrantsPermission`, que já define
    // `stringValue(status) ?? "active"` para este MESMO documento.
    const perfil: JsonMap = {permissions: {health: {issue_restriction: true}}};
    assertGranted("issue_restriction", perfil, "status ausente");
    assert.strictEqual(
      profileGrantsPermission(perfil, "health", "issue_restriction"),
      true,
      "o gate canônico deve concordar com esta tolerância",
    );
  });

  await test("mapa de permissões malformado nega", () => {
    const malformados: unknown[] = [
      undefined,
      null,
      "issue_restriction",
      ["issue_restriction"],
      42,
      {health: "issue_restriction"},
      {health: ["issue_restriction"]},
    ];
    for (const permissions of malformados) {
      assertDenied(
        "issue_restriction",
        {status: "active", permissions},
        "capability-not-granted",
        `permissions=${JSON.stringify(permissions)}`,
      );
    }
  });

  await test("capability truthy-mas-não-true nega", () => {
    // O contrato canônico exige `=== true`. "true", 1 e {} não concedem.
    for (const value of ["true", 1, {}, "yes"]) {
      assertDenied(
        "issue_restriction",
        {status: "active", permissions: {health: {issue_restriction: value}}},
        "capability-not-granted",
        `valor=${JSON.stringify(value)}`,
      );
    }
  });

  await test("as três actions são independentes entre si", () => {
    for (const granted of ALL_ACTIONS) {
      const perfil = profileWith([granted]);
      for (const action of ALL_ACTIONS) {
        if (action === granted) {
          assertGranted(action, perfil, `somente ${granted}`);
        } else {
          assertDenied(
            action,
            perfil,
            "capability-not-granted",
            `somente ${granted}`,
          );
        }
      }
    }
  });

  // ───────────────────────────────────────────────────────────────────────────
  // §10 — SINAL DE AUDITORIA PRESERVADO
  // ───────────────────────────────────────────────────────────────────────────

  await test("internal_role continua distinguindo admin de condutor", () => {
    // Autorização e classificação de auditoria são conceitos separados.
    // Remover o bypass NÃO pode apagar a informação de que o ator era admin.
    const caller = {uid: "uid-1", name: "Fulano", ra: "12345"};
    assert.strictEqual(
      (recordedByPayload(caller, true) as JsonMap).internal_role,
      "admin",
    );
    assert.strictEqual(
      (recordedByPayload(caller, false) as JsonMap).internal_role,
      "condutor",
    );
  });

  await test("isAdminToken/isAdminUserRecord seguem exportados e intactos", () => {
    // Continuam existindo para auditoria e para o bypass genérico do resto da
    // plataforma. Este gate não os alterou.
    assert.strictEqual(isAdminToken({admin: true} as never), true);
    assert.strictEqual(isAdminToken({role: "administrador"} as never), true);
    assert.strictEqual(isAdminToken({role: "gestor"} as never), false);
    assert.strictEqual(isAdminUserRecord({accessLevel: "gestor"}), false);
  });

  // ───────────────────────────────────────────────────────────────────────────
  // §14 — PROVAS ARQUITETURAIS (impedem a regressão silenciosa)
  // ───────────────────────────────────────────────────────────────────────────

  const indexSource = readSource("index.ts");
  const indexCode = stripComments(indexSource);

  await test("as três restriction actions NÃO usam o helper genérico", () => {
    for (const action of ALL_ACTIONS) {
      const generic = new RegExp(
        `requireAccessPermission\\(\\s*auth\\s*,\\s*"health"\\s*,\\s*"${action}"`,
      );
      assert.ok(
        !generic.test(indexCode),
        `${action} voltou ao caminho genérico com bypass administrativo`,
      );
    }
  });

  await test("as três actions usam a autoridade dedicada", () => {
    for (const action of ALL_ACTIONS) {
      const dedicated = new RegExp(
        `requireRestrictionLifecyclePermission\\(\\s*auth\\s*,\\s*"${action}"`,
      );
      assert.ok(
        dedicated.test(indexCode),
        `${action} não está usando requireRestrictionLifecyclePermission`,
      );
    }
  });

  await test("a autoridade dedicada não contém bypass administrativo", () => {
    const start = indexCode.indexOf(
      "async function requireRestrictionLifecyclePermission",
    );
    assert.ok(start > 0, "requireRestrictionLifecyclePermission não encontrada");
    const body = indexCode.slice(start, indexCode.indexOf("\n}", start));
    for (const forbidden of [
      "isAdminToken",
      "isAdminUserRecord",
      "isAdministrativeHealthAuthority",
      "requireAccessPermission",
    ]) {
      assert.ok(
        !body.includes(forbidden),
        `bypass reintroduzido: ${forbidden} apareceu na autoridade dedicada`,
      );
    }
  });

  await test("a decisão pura não contém bypass administrativo", () => {
    const start = indexCode.indexOf(
      "export function decideRestrictionLifecycleGrant",
    );
    assert.ok(start > 0, "decideRestrictionLifecycleGrant não encontrada");
    const body = indexCode.slice(start, indexCode.indexOf("\n}", start));
    for (const forbidden of ["isAdminToken", "isAdminUserRecord", "admin"]) {
      assert.ok(
        !body.includes(forbidden),
        `bypass reintroduzido na decisão pura: ${forbidden}`,
      );
    }
  });

  await test("o bypass administrativo GENÉRICO permanece preservado", () => {
    // O escopo aprovado é cirúrgico: o resto da plataforma não muda.
    const start = indexCode.indexOf("async function requireAccessPermission");
    assert.ok(start > 0, "requireAccessPermission não encontrada");
    const body = indexCode.slice(start, indexCode.indexOf("\n}", start));
    assert.ok(
      body.includes("isAdminToken(auth.token)"),
      "o bypass genérico por token desapareceu — fora do escopo deste gate",
    );
    assert.ok(
      body.includes("isAdminUserRecord(user)"),
      "o bypass genérico por espelho desapareceu — fora do escopo deste gate",
    );
  });

  await test("isAdministrativeHealthAuthority permanece intacta", () => {
    // Load-bearing em healthScheduleCancel (itens automáticos).
    const start = indexCode.indexOf(
      "async function isAdministrativeHealthAuthority",
    );
    assert.ok(start > 0, "isAdministrativeHealthAuthority não encontrada");
    const body = indexCode.slice(start, indexCode.indexOf("\n}", start));
    assert.ok(
      body.includes("isAdminToken(auth.token)") &&
        body.includes("isAdminUserRecord(user)"),
      "isAdministrativeHealthAuthority foi alterada — Schedule quebraria",
    );
  });

  await test("o guard administrativo do Schedule não foi tocado", () => {
    const schedule = stripComments(readSource("health_schedule_callables.ts"));
    assert.ok(
      schedule.includes("if (!isAdmin)"),
      "o guard de cancelamento automático do Schedule desapareceu",
    );
  });

  await test("os deps de restrição ainda expõem isAdministrativeAuthority", () => {
    // Autorização saiu do caminho admin; a classificação de auditoria fica.
    const callables = stripComments(
      readSource("health_restriction_callables.ts"),
    );
    assert.ok(
      callables.includes("isAdministrativeAuthority"),
      "o sinal de auditoria administrativa foi removido dos callables",
    );
    assert.ok(
      callables.includes("recordedByPayload(caller, isAdmin)"),
      "recorded_by deixou de registrar a natureza administrativa do ator",
    );
  });

  await test("isAdmin não decide nada nos callables de restrição", () => {
    // Se um ramo condicional passar a depender de isAdmin, autorização e
    // auditoria voltam a se confundir.
    const callables = stripComments(
      readSource("health_restriction_callables.ts"),
    );
    for (const branch of [
      "if (isAdmin",
      "if (!isAdmin",
      "isAdmin ?",
      "isAdmin &&",
      "isAdmin ||",
    ]) {
      assert.ok(
        !callables.includes(branch),
        `isAdmin voltou a ser load-bearing na restrição: "${branch}"`,
      );
    }
  });

  if (failed > 0) {
    console.error(`\n${failed} restriction-capability test(s) failed`);
    process.exit(1);
  }
  console.log("\nall restriction-capability tests passed");
}

void main();
