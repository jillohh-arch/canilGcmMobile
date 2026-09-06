/**
 * Regressao permanente do gate S2.A.D1/D3.
 *
 * Importa APENAS o modulo puro. Nao pode importar `../src/index`, porque
 * `index.ts` chama `admin.initializeApp()` em escopo de modulo e o import
 * executaria a inicializacao sem credencial.
 *
 * Tambem NAO importa `firebase-admin/lib/utils/error`: aquele caminho e interno
 * ao SDK (o `.d.ts` declara `FirebaseAuthError` sem construtor proprio, entao a
 * tipagem herdada nem corresponde ao runtime). Uma regressao permanente nao
 * deve depender de internals. O codigo publico canonico esta fixado abaixo como
 * constante, verificado empiricamente contra `firebase-admin@13.10.0` no gate
 * S2.A.D2:
 *
 *   AuthClientErrorCode.USER_NOT_FOUND.code  === "user-not-found"
 *   new FirebaseAuthError(...).code          === "auth/user-not-found"
 *
 * O DEFEITO que originou este arquivo: os wirings de Auth do lifecycle usavam
 * `catch { return null; }`. Em staging o service account do runtime nao tinha
 * permissao de Firebase Auth, `getUserByEmail` falhou com PERMISSION_DENIED, o
 * erro foi engolido e virou `null` — que o modulo le como "conta nao existe".
 * Resultado: Personnel marcado inativo no Firestore com a conta de acesso ainda
 * HABILITADA, e a callable devolvendo `authState: "not_provisioned"`.
 *
 * A unica coisa que pode virar "conta nao existe" e a inexistencia real.
 */

import * as assert from "node:assert/strict";
import {test} from "node:test";

import {isAuthUserNotFound} from "../src/auth_error_classification";

/** Forma publica prefixada — e ela que chega a quem captura o erro. */
const USER_NOT_FOUND = "auth/user-not-found";

/** Envelope minimo: o wiring so inspeciona `error.code`. */
function authError(code: string, message = "boom"): Error & {code: string} {
  return Object.assign(new Error(message), {code});
}

// ---------------------------------------------------------------------------
// A. A unica condicao que afirma inexistencia
// ---------------------------------------------------------------------------

test("o codigo canonico de conta inexistente e reconhecido", () => {
  assert.equal(isAuthUserNotFound(authError(USER_NOT_FOUND)), true);
});

test("objeto simples com o code exato basta (shape que o wiring ve)", () => {
  assert.equal(isAuthUserNotFound({code: USER_NOT_FOUND}), true);
});

// ---------------------------------------------------------------------------
// B. A falha operacional EXATA que causou o incidente em staging
// ---------------------------------------------------------------------------

test("PERMISSION_DENIED do Identity Toolkit NAO e conta ausente", () => {
  // Forma observada quando o runtime SA nao tem role de Firebase Auth.
  const error = Object.assign(
    new Error("Permission denied on resource project k9-ops-staging."),
    {code: "auth/insufficient-permission", status: "PERMISSION_DENIED"},
  );
  assert.equal(
    isAuthUserNotFound(error),
    false,
    "engolir este erro produz not_provisioned mentiroso com a conta habilitada",
  );
});

test("SERVICE_DISABLED / quota ausente NAO e conta ausente", () => {
  const error = Object.assign(
    new Error("identitytoolkit.googleapis.com is not enabled for project"),
    {code: "auth/internal-error", status: "PERMISSION_DENIED"},
  );
  assert.equal(isAuthUserNotFound(error), false);
});

test("erros operacionais conhecidos do Auth NAO sao conta ausente", () => {
  for (const code of [
    "auth/insufficient-permission",
    "auth/internal-error",
    "auth/invalid-credential",
    "auth/project-not-found",
    "auth/email-already-exists",
    "auth/invalid-uid",
  ]) {
    assert.equal(
      isAuthUserNotFound(authError(code)),
      false,
      `${code} nao deveria ser tratado como conta ausente`,
    );
  }
});

test("erro de transporte NAO e conta ausente", () => {
  assert.equal(isAuthUserNotFound(authError("ECONNRESET", "socket hang up")), false);
  assert.equal(isAuthUserNotFound(new Error("network timeout")), false);
});

// ---------------------------------------------------------------------------
// C. Entradas degeneradas
// ---------------------------------------------------------------------------

test("valores nao-objeto nunca sao conta ausente", () => {
  for (const value of [undefined, null, USER_NOT_FOUND, 404, true, Symbol("x")]) {
    assert.equal(
      isAuthUserNotFound(value),
      false,
      `${String(value)} nao deveria ser classificado como conta ausente`,
    );
  }
});

test("objeto sem code e recusado", () => {
  assert.equal(isAuthUserNotFound({}), false);
  assert.equal(isAuthUserNotFound({message: "no user record"}), false);
  assert.equal(isAuthUserNotFound({code: undefined}), false);
});

test("codes parecidos mas diferentes sao recusados", () => {
  for (const code of [
    "user-not-found", // sem o prefixo do produto
    "auth/user_not_found",
    "auth/user-not-found-really",
    "AUTH/USER-NOT-FOUND",
    " auth/user-not-found",
    "",
  ]) {
    assert.equal(isAuthUserNotFound({code}), false, `code "${code}" nao deveria casar`);
  }
});

// ---------------------------------------------------------------------------
// D. A propriedade da qual o wiring depende, declarada explicitamente
// ---------------------------------------------------------------------------

test("o predicado e a UNICA porta para null: todo o resto propaga", () => {
  // Reproduz a decisao do wiring corrigido sem importar index.ts.
  const resolve = (error: unknown): "null" | "throw" =>
    isAuthUserNotFound(error) ? "null" : "throw";

  assert.equal(resolve(authError(USER_NOT_FOUND)), "null");
  assert.equal(resolve(authError("auth/insufficient-permission")), "throw");
  assert.equal(resolve(authError("auth/internal-error")), "throw");
  assert.equal(resolve(authError("ECONNRESET")), "throw");
  assert.equal(resolve(undefined), "throw");
  assert.equal(resolve(null), "throw");
});
