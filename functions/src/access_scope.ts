/**
 * SEC-02A — contrato de escopo de acesso, FALHA FECHADA.
 *
 * Módulo puro e sem I/O: não importa `firebase-admin` nem `index.ts`, portanto é
 * testável sem emulador e sem credenciais. `index.ts` faz as leituras de
 * Firestore e delega a DECISÃO para cá.
 *
 * Princípio único, não negociável:
 *
 *   DESCONHECIDO / AUSENTE / MALFORMADO  =>  NUNCA global
 *
 * Antes deste gate, toda condição não-resolvível terminava em `"global"`, e
 * `requireDogRecordAccess` retornava imediatamente para escopo global — ou
 * seja, liberava qualquer K9 sem nenhuma prova de vínculo. Como o Admin SDK
 * ignora Firestore Rules, não havia segunda barreira.
 */

/** Valores canônicos. Não existe terceiro valor válido. */
export const ACCESS_SCOPE_VALUES = ["global", "own_records"] as const;

export type AccessScope = (typeof ACCESS_SCOPE_VALUES)[number];

/**
 * Valida escopo vindo de Firestore ou de custom claims.
 *
 * Retorna `null` para ausente/desconhecido/malformado — inclusive `""`,
 * `"ownRecords"`, `"unit"`, números e objetos. Quem chama decide o que fazer, e
 * a decisão segura é recusar amplitude.
 *
 * Comparação estrita e sem normalização, de propósito: `normalizedKey` tornaria
 * `"OwnRecords"` aceitável e aumentaria a superfície de valores que viram
 * permissão.
 */
export function parseAccessScope(value: unknown): AccessScope | null {
  if (typeof value !== "string") return null;
  const raw = value.trim();
  if (raw === "global") return "global";
  if (raw === "own_records") return "own_records";
  return null;
}

/** Motivo estruturado da recusa. Diagnóstico, nunca mensagem ao usuário. */
export type AccessScopeDenialReason =
  | "missing-auth"
  | "unresolved-ra"
  | "missing-user-mirror"
  | "user-soft-deleted"
  | "missing-access-profile"
  | "inactive-access-profile"
  | "unresolved-access-scope";

export type AccessScopeResolution =
  | {kind: "global"}
  | {kind: "own_records"}
  | {kind: "denied"; reason: AccessScopeDenialReason};

/**
 * Entradas já lidas do servidor. `undefined` distingue "documento ausente" de
 * "documento presente e vazio" — a diferença importa para falhar fechado.
 */
export interface AccessScopeInputs {
  /** Existe token autenticado. */
  authPresent: boolean;
  /** Resultado de `isAdminToken` — caminho administrativo explícito. */
  isAdminToken: boolean;
  /** RA derivado do e-mail do token. Vazio => identidade não mapeável. */
  ra: string;
  /** `users/{ra}`. `undefined` quando o documento não existe. */
  userDoc: Record<string, unknown> | undefined;
  /** `access_profiles/{id}`. `undefined` quando o documento não existe. */
  profileDoc: Record<string, unknown> | undefined;
  /** `access_scope` da custom claim. Só pode restringir, nunca ampliar. */
  tokenAccessScope: unknown;
}

/**
 * Decisão de escopo. Ordem de avaliação é contratual — testes dependem dela.
 */
export function decideAccessScope(
  inputs: AccessScopeInputs,
): AccessScopeResolution {
  if (!inputs.authPresent) return {kind: "denied", reason: "missing-auth"};

  // Caminho administrativo explícito, preservado como já era canônico.
  if (inputs.isAdminToken) return {kind: "global"};

  if (!inputs.ra.trim()) return {kind: "denied", reason: "unresolved-ra"};

  if (inputs.userDoc === undefined) {
    return {kind: "denied", reason: "missing-user-mirror"};
  }
  // Usuário desativado por soft-delete não conserva acesso. Antes deste gate
  // `deleted_at` não era consultado em nenhum ponto do caminho de escopo.
  if (inputs.userDoc.deleted_at != null) {
    return {kind: "denied", reason: "user-soft-deleted"};
  }

  if (inputs.profileDoc === undefined) {
    return {kind: "denied", reason: "missing-access-profile"};
  }

  // Ciclo de vida do perfil. O enum persistido é exatamente
  // `"active" | "inactive"` — provado pelo schema, não inventado:
  //   - tipo em accessProfilePayload options.status (index.ts)
  //   - coerção `=== "inactive" ? "inactive" : "active"` no mesmo writer
  //   - whitelist `["active", "inactive"]` em adminSetAccessProfileStatus
  //
  // AUSENTE é tolerado como ativo porque o contrato canônico vigente já o
  // define assim de forma explícita em `profileGrantsPermission`
  // (`stringValue(profile.status) ?? "active"`) — negar aqui divergiria do gate
  // de capability para o MESMO documento. Qualquer outro valor
  // (`""`, `"inactive"`, `"disabled"`, desconhecido, tipo errado) NEGA.
  //
  // Antes do SEC-02A o caminho de escopo não consultava `status` de forma
  // alguma: perfil inativo com `scope: "global"` concedia amplitude.
  const status = inputs.profileDoc.status;
  if (status !== undefined && status !== null) {
    if (typeof status !== "string" || status.trim() !== "active") {
      return {kind: "denied", reason: "inactive-access-profile"};
    }
  }

  // O perfil de acesso é a AUTORIDADE de escopo. Ausente, malformado ou
  // desconhecido => nega (decisão humana SEC-02A.1). Não há fallback para o
  // espelho nem para a claim: configuração declarativa quebrada não é suprida
  // por outra fonte, nem compensada por vínculo com o K9 depois.
  const profileScope = parseAccessScope(inputs.profileDoc.scope);
  if (profileScope === null) {
    return {kind: "denied", reason: "unresolved-access-scope"};
  }
  if (profileScope === "own_records") return {kind: "own_records"};

  // profileScope === "global": amplitude exige que o espelho/claim NÃO
  // contradiga. Uma claim ou espelho declarando own_records RESTRINGE — nunca
  // o contrário. Assim uma claim obsoleta jamais amplia, mas também não
  // silenciosamente derruba uma restrição declarada.
  const mirrored =
    parseAccessScope(inputs.userDoc.access_scope) ??
    parseAccessScope(inputs.userDoc.accessScope) ??
    parseAccessScope(inputs.tokenAccessScope);
  if (mirrored === "own_records") return {kind: "own_records"};

  return {kind: "global"};
}
