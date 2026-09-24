/**
 * Classificacao de erros do Firebase Admin Auth.
 *
 * Modulo PURO de proposito unico: nao importa `firebase-admin`, nao inicializa
 * app, nao toca Firestore, nao conhece dominio. Existe separado de `index.ts`
 * porque `index.ts` chama `admin.initializeApp()` em escopo de modulo — logo
 * importar qualquer export dele de um teste executaria a inicializacao e
 * exigiria credencial. Um modulo puro e testavel isoladamente.
 *
 * MOTIVO (S2.A.D1): os wirings de Auth do lifecycle usavam `catch { return
 * null; }`. `null` significa "conta nao existe", entao QUALQUER falha
 * operacional — permissao ausente, erro de API, rede — era apresentada como
 * "Personnel legitimo sem conta". Em staging isso produziu um
 * `authState: "not_provisioned"` mentiroso enquanto a conta seguia habilitada:
 * o Firestore foi marcado inativo e o acesso permaneceu aberto.
 *
 * Somente a inexistencia REAL pode virar `null`. Todo o resto propaga e falha
 * fechado pela taxonomia ja congelada.
 */

/**
 * `true` somente para o codigo publico canonico do Firebase Admin que afirma
 * que o identificador nao corresponde a nenhuma conta.
 *
 * `firebase-admin@13.10.0` expoe `AuthClientErrorCode.USER_NOT_FOUND` com
 * `code: "user-not-found"`, prefixado para `"auth/user-not-found"` em
 * `FirebaseAuthError`. Comparamos a forma publica prefixada, que e o que chega
 * a quem captura o erro.
 *
 * Deliberadamente NAO reconhece `auth/insufficient-permission`,
 * `auth/internal-error` nem qualquer erro de transporte: sao falhas
 * operacionais, nao ausencia de conta.
 */
export function isAuthUserNotFound(error: unknown): boolean {
  if (error === null || typeof error !== "object") return false;
  return (error as {code?: unknown}).code === "auth/user-not-found";
}
