/**
 * SEC-02A — testes de regressão de segurança do escopo de acesso.
 * npm run build && node lib/access_scope_test.js
 *
 * O invariante central: nenhuma entrada não-resolvível pode produzir `global`.
 * Estes testes asseveram o MOTIVO da recusa, não apenas "recusou" — senão um
 * teste passa pelo motivo errado e mascara a falha real.
 */
import * as assert from "assert";

import {
  decideAccessScope,
  parseAccessScope,
  type AccessScopeInputs,
} from "./access_scope";

/** Base VÁLIDA e restrita. Cada teste degrada um único campo. */
function baseInputs(overrides: Partial<AccessScopeInputs> = {}): AccessScopeInputs {
  return {
    authPresent: true,
    isAdminToken: false,
    ra: "691755",
    userDoc: {access_scope: "own_records"},
    profileDoc: {status: "active", scope: "own_records"},
    tokenAccessScope: "own_records",
    ...overrides,
  };
}

let passed = 0;

function test(name: string, fn: () => void): void {
  try {
    fn();
    console.log(`ok - ${name}`);
    passed++;
  } catch (e) {
    console.error(`FAIL - ${name}`);
    throw e;
  }
}

function main(): void {
  // ---------------------------------------------------------------- parse
  test("parseAccessScope aceita apenas os dois valores canônicos", () => {
    assert.strictEqual(parseAccessScope("global"), "global");
    assert.strictEqual(parseAccessScope("own_records"), "own_records");
  });

  test("parseAccessScope rejeita variantes que antes viravam global", () => {
    // "ownRecords" é o caso perigoso: camelCase é a convenção em todo o resto
    // do arquivo, então o erro de digitação é plausível — e antes concedia
    // acesso global silenciosamente.
    for (const value of [
      "ownRecords", "OWN_RECORDS", "Global", "unit", "", "   ",
      null, undefined, 0, 1, true, {}, [], "own_records ",
    ]) {
      const parsed = parseAccessScope(value as unknown);
      assert.strictEqual(
        parsed === "global", false,
        `valor ${JSON.stringify(value)} NUNCA pode virar global`,
      );
    }
    assert.strictEqual(parseAccessScope("ownRecords"), null);
    assert.strictEqual(parseAccessScope(""), null);
    assert.strictEqual(parseAccessScope(undefined), null);
  });

  test("parseAccessScope tolera espaço em volta do valor canônico", () => {
    assert.strictEqual(parseAccessScope("  global  "), "global");
    assert.strictEqual(parseAccessScope(" own_records "), "own_records");
  });

  // ------------------------------------------------- caminhos de recusa
  test("sem auth → denied/missing-auth", () => {
    const r = decideAccessScope(baseInputs({authPresent: false}));
    assert.deepStrictEqual(r, {kind: "denied", reason: "missing-auth"});
  });

  test("RA vazio → denied/unresolved-ra (nunca global)", () => {
    for (const ra of ["", "   "]) {
      const r = decideAccessScope(baseInputs({ra}));
      assert.deepStrictEqual(r, {kind: "denied", reason: "unresolved-ra"});
    }
  });

  test("espelho users/{ra} ausente → denied (era o vetor principal)", () => {
    // Cenário do ataque: conta Auth válida sem documento espelho. Antes isto
    // resolvia para "global" e liberava qualquer K9.
    const r = decideAccessScope(baseInputs({userDoc: undefined}));
    assert.deepStrictEqual(r, {kind: "denied", reason: "missing-user-mirror"});
  });

  test("usuário soft-deleted → denied", () => {
    const r = decideAccessScope(baseInputs({
      userDoc: {access_scope: "global", deleted_at: "2026-01-01T00:00:00Z"},
    }));
    assert.deepStrictEqual(r, {kind: "denied", reason: "user-soft-deleted"});
  });

  test("access_profiles/{id} ausente → denied", () => {
    const r = decideAccessScope(baseInputs({
      userDoc: {},
      profileDoc: undefined,
    }));
    assert.deepStrictEqual(r, {
      kind: "denied", reason: "missing-access-profile",
    });
  });

  test("perfil inativo não concede escopo, nem com scope global", () => {
    const r = decideAccessScope(baseInputs({
      userDoc: {},
      profileDoc: {status: "inactive", scope: "global"},
    }));
    assert.deepStrictEqual(r, {
      kind: "denied", reason: "inactive-access-profile",
    });
  });

  test("status de perfil vazio/desconhecido/tipo errado → denied", () => {
    // Enum persistido é exatamente "active" | "inactive". AUSENTE/null é
    // tolerado como ativo (contrato canônico de profileGrantsPermission);
    // qualquer OUTRO valor nega.
    for (const status of ["", "   ", "disabled", "ACTIVE", "Active", 1, true, {}]) {
      const r = decideAccessScope(baseInputs({
        userDoc: {},
        profileDoc: {status, scope: "global"},
        tokenAccessScope: undefined,
      }));
      assert.strictEqual(
        r.kind, "denied",
        `status ${JSON.stringify(status)} deveria negar, obteve ${r.kind}`,
      );
      assert.strictEqual(
        (r as {reason: string}).reason, "inactive-access-profile",
      );
    }
  });

  test("perfil inativo + scope global → DENY (nao concede amplitude)", () => {
    const r = decideAccessScope(baseInputs({
      userDoc: {access_scope: "global"},
      profileDoc: {status: "inactive", scope: "global"},
      tokenAccessScope: "global",
    }));
    assert.deepStrictEqual(r, {
      kind: "denied", reason: "inactive-access-profile",
    });
  });

  test("perfil inativo + scope own_records → DENY", () => {
    const r = decideAccessScope(baseInputs({
      profileDoc: {status: "inactive", scope: "own_records"},
    }));
    assert.deepStrictEqual(r, {
      kind: "denied", reason: "inactive-access-profile",
    });
  });

  test("usuario soft-deleted + scope global → DENY", () => {
    const r = decideAccessScope(baseInputs({
      userDoc: {deleted_at: "2026-01-01T00:00:00Z", access_scope: "global"},
      profileDoc: {status: "active", scope: "global"},
      tokenAccessScope: "global",
    }));
    assert.deepStrictEqual(r, {kind: "denied", reason: "user-soft-deleted"});
  });

  test("usuario soft-deleted + scope own_records → DENY", () => {
    const r = decideAccessScope(baseInputs({
      userDoc: {deleted_at: 1767225600000, access_scope: "own_records"},
      profileDoc: {status: "active", scope: "own_records"},
    }));
    assert.deepStrictEqual(r, {kind: "denied", reason: "user-soft-deleted"});
  });

  test("deleted_at null/ausente segue o contrato de usuario ativo", () => {
    for (const userDoc of [{}, {deleted_at: null}]) {
      const r = decideAccessScope(baseInputs({
        userDoc,
        profileDoc: {status: "active", scope: "global"},
        tokenAccessScope: undefined,
      }));
      assert.deepStrictEqual(r, {kind: "global"});
    }
  });

  test("claims legadas/obsoletas nao adquirem global", () => {
    // Tokens antigos são entrada adversarial: podem não ter ra, não ter
    // access_scope, ou tê-lo malformado. Nenhum caminho concede amplitude.
    for (const tokenAccessScope of [undefined, "", "   ", "ownRecords", "unit", 1, {}]) {
      const r = decideAccessScope(baseInputs({
        userDoc: {},
        profileDoc: {status: "active"},
        tokenAccessScope,
      }));
      assert.strictEqual(
        r.kind === "global", false,
        `claim ${JSON.stringify(tokenAccessScope)} nao pode conceder global`,
      );
    }
  });

  test("scope ausente/desconhecido/malformado → denied, nunca global", () => {
    for (const scope of [
      undefined, null, "", "   ", "ownRecords", "unit", "GLOBAL", 42, {}, [],
    ]) {
      const r = decideAccessScope(baseInputs({
        // espelho e claim também sem valor válido
        userDoc: {},
        profileDoc: {status: "active", scope},
        tokenAccessScope: undefined,
      }));
      assert.strictEqual(
        r.kind, "denied",
        `scope ${JSON.stringify(scope)} deveria recusar, obteve ${r.kind}`,
      );
      assert.strictEqual(
        (r as {reason: string}).reason, "unresolved-access-scope",
      );
    }
  });

  // --------------------------------------------- caminhos legítimos
  test("perfil own_records explícito → own_records", () => {
    const r = decideAccessScope(baseInputs({
      profileDoc: {status: "active", scope: "own_records"},
    }));
    assert.deepStrictEqual(r, {kind: "own_records"});
  });

  test("perfil global explícito → global (comportamento legítimo preservado)", () => {
    const r = decideAccessScope(baseInputs({
      userDoc: {},
      profileDoc: {status: "active", scope: "global"},
      tokenAccessScope: undefined,
    }));
    assert.deepStrictEqual(r, {kind: "global"});
  });

  test("perfil sem status é tratado como ativo (compatibilidade legada)", () => {
    const r = decideAccessScope(baseInputs({
      userDoc: {},
      profileDoc: {scope: "global"},
      tokenAccessScope: undefined,
    }));
    assert.deepStrictEqual(r, {kind: "global"});
  });

  test("admin token → global sem depender de documento algum", () => {
    const r = decideAccessScope(baseInputs({
      isAdminToken: true,
      ra: "",
      userDoc: undefined,
      profileDoc: undefined,
      tokenAccessScope: undefined,
    }));
    assert.deepStrictEqual(r, {kind: "global"});
  });

  // ----------------------------------------- espelho só pode restringir
  test("perfil sem escopo válido → DENY, espelho não supre a autoridade", () => {
    // SEC-02A.1: o perfil de acesso é a ÚNICA autoridade de escopo. Antes o
    // espelho podia suprir um perfil sem scope; isso permitia que uma
    // configuração declarativa quebrada seguisse para prova de vínculo.
    for (const userDoc of [
      {access_scope: "own_records"},
      {accessScope: "own_records"},
      {access_scope: "global"},
    ]) {
      const r = decideAccessScope(baseInputs({
        userDoc,
        profileDoc: {status: "active"},
        tokenAccessScope: "own_records",
      }));
      assert.deepStrictEqual(
        r, {kind: "denied", reason: "unresolved-access-scope"},
        `espelho ${JSON.stringify(userDoc)} não pode suprir escopo do perfil`,
      );
    }
  });

  test("espelho/claim own_records RESTRINGE um perfil global", () => {
    // Direção segura preservada: quem declara restrição em qualquer camada
    // acaba restrito. O inverso (ampliar) é impossível.
    for (const userDoc of [
      {access_scope: "own_records"},
      {accessScope: "own_records"},
    ]) {
      const r = decideAccessScope(baseInputs({
        userDoc,
        profileDoc: {status: "active", scope: "global"},
        tokenAccessScope: undefined,
      }));
      assert.deepStrictEqual(r, {kind: "own_records"});
    }

    const byClaim = decideAccessScope(baseInputs({
      userDoc: {},
      profileDoc: {status: "active", scope: "global"},
      tokenAccessScope: "own_records",
    }));
    assert.deepStrictEqual(byClaim, {kind: "own_records"});
  });

  test("claim access_scope pode restringir, NUNCA ampliar", () => {
    // claim own_records restringe um perfil global
    const restricted = decideAccessScope(baseInputs({
      userDoc: {},
      profileDoc: {status: "active", scope: "global"},
      tokenAccessScope: "own_records",
    }));
    assert.deepStrictEqual(restricted, {kind: "own_records"});

    // claim global NÃO amplia: sem escopo válido no perfil, nega — a claim não
    // é autoridade de escopo.
    const notWidened = decideAccessScope(baseInputs({
      userDoc: {},
      profileDoc: {status: "active"},
      tokenAccessScope: "global",
    }));
    assert.deepStrictEqual(notWidened, {
      kind: "denied", reason: "unresolved-access-scope",
    });
  });

  test("perfil own_records vence claim global (não é ampliável)", () => {
    const r = decideAccessScope(baseInputs({
      userDoc: {access_scope: "global"},
      profileDoc: {status: "active", scope: "own_records"},
      tokenAccessScope: "global",
    }));
    assert.deepStrictEqual(r, {kind: "own_records"});
  });

  // ------------------------------------------------- invariante global
  test("INVARIANTE: nenhuma combinação degradada produz global", () => {
    const degraded: Array<Partial<AccessScopeInputs>> = [];
    const userDocs = [undefined, {}, {access_scope: "ownRecords"},
      {deleted_at: 1}, {access_scope: ""}];
    const profileDocs = [undefined, {}, {status: "active"},
      {status: "inactive", scope: "global"}, {scope: "ownRecords"},
      {status: "active", scope: ""}];
    const claims = [undefined, "", "ownRecords", "unit", null];

    for (const userDoc of userDocs) {
      for (const profileDoc of profileDocs) {
        for (const tokenAccessScope of claims) {
          degraded.push({userDoc, profileDoc, tokenAccessScope});
        }
      }
    }

    let checked = 0;
    for (const overrides of degraded) {
      const r = decideAccessScope(baseInputs({...overrides, ra: "691755"}));
      assert.strictEqual(
        r.kind === "global", false,
        `combinação concedeu global: ${JSON.stringify(overrides)}`,
      );
      checked++;
    }
    assert.strictEqual(checked, userDocs.length * profileDocs.length *
      claims.length);
    console.log(`   (${checked} combinações degradadas verificadas)`);
  });

  console.log(`\n${passed} testes de segurança passaram.`);
}

main();
