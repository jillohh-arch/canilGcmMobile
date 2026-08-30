/**
 * Human Lifecycle V1 — autoridade canonica de DESATIVAR / REATIVAR humano.
 *
 * Contrato A1 FROZEN. Este modulo expoe duas operacoes independentes:
 *   - `deactivateHuman`  (callable adminDeactivateHuman)
 *   - `reactivateHuman`  (callable adminReactivateHuman)
 *
 * Ambas exigem a capacidade `humans.archive` (NAO `access.edit`: o gate legado
 * do painel Web era amplo demais e discordava do gate de servidor).
 *
 * Semantica congelada:
 *   - desativar = tornar o integrante administrativamente inativo E suspender
 *     seu acesso ao K9 Ops (Firestore + conta de Auth desabilitada);
 *   - reativar = devolver o integrante ao estado ativo e reabilitar a conta,
 *     valendo o acesso que existir NAQUELE momento;
 *   - perfil de acesso, roles, claims, Personnel e historico sao PRESERVADOS
 *     nas duas operacoes. Nao existe snapshot de privilegio: restaurar acesso
 *     historico ressuscitaria permissoes de uma politica ja revogada.
 *
 * Vocabulario canonico: `active`, `status` e o conjunto `deleted_*`. Os campos
 * `deactivated_*`/`reactivated_*` escritos pelo fluxo legado do browser sao
 * deliberadamente NAO adotados: nenhum leitor no ecossistema os consome e eles
 * estao fora da allowlist das Firestore Rules.
 *
 * Concorrencia: `expectedUpdatedAt` obrigatorio, validado contra
 * max(updated_at, updatedAt) — a mesma autoridade congelada pelo Human Edit V1,
 * reusada por import. Nunca `updated_at ?? updatedAt`.
 *
 * FRONTEIRA CROSS-SERVICE (importante):
 *   Firebase Auth NAO participa da transacao do Firestore. Nao existe
 *   atomicidade entre os dois servicos e este modulo nao a alega. As chamadas
 *   de Auth ficam FORA do callback de `runTransaction`, porque transacoes podem
 *   sofrer retry e repetiriam o efeito colateral externo.
 *
 *   A ordem e assimetrica de proposito (ver A1):
 *     - DESATIVAR: Auth disable ANTES do commit Firestore. Preferimos falhar
 *       com a conta ja bloqueada do que deixar alguem marcado inativo mas ainda
 *       conseguindo entrar. Se o Firestore falhar, compensamos reabilitando.
 *     - REATIVAR: commit Firestore ANTES do Auth enable. Preferimos falhar com
 *       a conta ainda bloqueada do que liberar acesso antes de o estado
 *       administrativo estar ativo. Se o Auth falhar, compensamos voltando o
 *       documento para inativo.
 *
 *   Nenhuma operacao retorna sucesso em estado parcial. Quando a compensacao
 *   tambem falha, o erro e explicitamente COMPENSATION_FAILED — a unica classe
 *   de erro que admite divergencia entre os servicos, e ela e reportada, nunca
 *   mascarada.
 *
 *   As compensacoes NAO sao rollback cego (B1.R1):
 *     - a desativacao restaura o `disabled` que a conta REALMENTE tinha antes,
 *       capturado via getAuthDisabled, porque documento e conta podem ja estar
 *       divergentes;
 *     - a reativacao releia o documento apos o commit para conhecer a versao que
 *       ela mesma produziu e so reverte se o documento ainda estiver nessa
 *       versao (compare-and-set), restaurando o snapshot lifecycle exato —
 *       incluindo a AUSENCIA de campos que nao existiam.
 *
 *   LIMITACAO RESIDUAL CROSS-SERVICE: o Firebase Auth nao oferece token de
 *   concorrencia equivalente ao max(updated_at, updatedAt) do Firestore. Uma
 *   mutacao externa feita diretamente no Auth entre a captura de
 *   `priorAuthDisabled` e a compensacao nao pode ser protegida por CAS. Isso e
 *   documentado, nao resolvido: resolver exigiria state machine nova.
 *
 * Nenhum estado intermediario (`deactivating`/`reactivating`) e introduzido:
 * isso exigiria novo gate de contrato.
 */

import {HttpsError} from "firebase-functions/v2/https";

import {concurrencyAuthorityMillis} from "./admin_patch_human_personnel";

type JsonMap = Record<string, unknown>;

/** Compativel estruturalmente com o CallerIdentity canonico do index.ts. */
export interface HumanLifecycleCaller {
  uid: string;
  email: string;
  ra: string;
  name: string;
}

/**
 * Discriminadores estaveis de erro. Viajam em `HttpsError.details.reason` para
 * que a camada Web distinga situacoes que compartilham o mesmo code Firebase.
 *
 * ACTIVE_SHIFT e STALE_WRITE sao ambos `failed-precondition` no nivel Firebase
 * e JAMAIS podem ser indistinguiveis para a UI: uma pede regularizar o turno, a
 * outra pede recarregar a tela.
 */
export const LIFECYCLE_ERROR = {
  invalidArgument: "INVALID_ARGUMENT",
  notFound: "NOT_FOUND",
  permissionDenied: "PERMISSION_DENIED",
  selfDeactivationForbidden: "SELF_DEACTIVATION_FORBIDDEN",
  activeShift: "ACTIVE_SHIFT",
  staleWrite: "STALE_WRITE",
  alreadyInState: "ALREADY_IN_STATE",
  /** Documento Personnel existe, mas nao carrega nenhum alias de uid de Auth. */
  authIdentityMissing: "AUTH_IDENTITY_MISSING",
  /** O uid existe no documento, mas nao ha conta de Auth correspondente. */
  authIdentityNotFound: "AUTH_IDENTITY_NOT_FOUND",
  authOperationFailed: "AUTH_OPERATION_FAILED",
  /**
   * Uma alteracao RESTRITIVA no Firebase Auth foi aplicada com sucesso e
   * deliberadamente preservada, mas a gravacao posterior de audit/metadata no
   * Firestore falhou.
   *
   * Usado SOMENTE na reconciliacao de desativacao (Personnel ja inativo, conta
   * ainda habilitada). NAO e uma compensacao falhada: nenhuma reversao foi
   * tentada, porque reabilitar a conta devolveria acesso a alguem formalmente
   * inativo apenas porque uma escrita de auditoria falhou.
   *
   * O caller NAO deve interpretar este erro como "a desativacao nao aconteceu":
   * o acesso FOI suspenso. Ver [B2.RB/RB-1].
   */
  authAppliedAuditFailed: "AUTH_APPLIED_AUDIT_FAILED",
  /**
   * Espelho permissivo do anterior: a tentativa de HABILITAR a conta foi
   * aplicada, a gravacao posterior de audit/metadata falhou, e a alteracao foi
   * REVERTIDA COM SUCESSO. A conta permanece desabilitada.
   *
   * Usado SOMENTE na reconciliacao de reativacao (Personnel ja ativo, conta
   * desabilitada). NAO e `COMPENSATION_FAILED`: a compensacao ocorreu e
   * funcionou — nenhum acesso ficou concedido.
   *
   * O caller deve entender que a reativacao NAO foi concluida e que nada ficou
   * pendente de forma insegura. Ver [B1.R3/§10 -> B1.R4].
   */
  authEnableRevertedAuditFailed: "AUTH_ENABLE_REVERTED_AUDIT_FAILED",
  /**
   * Reservado para compensacao REAL que NAO conseguiu garantir a reversao:
   * a tentativa de rollback falhou, ou o rollback foi recusado porque nao seria
   * seguro (concorrencia/estado divergente). Nunca significa "compensacao
   * bem-sucedida" nem "decidimos conscientemente nao reverter".
   */
  compensationFailed: "COMPENSATION_FAILED",
} as const;

export type LifecycleErrorReason =
  (typeof LIFECYCLE_ERROR)[keyof typeof LIFECYCLE_ERROR];

/**
 * Acoes de auditoria. Reconciliacao de Auth tem nome PROPRIO: reutilizar
 * "deactivated"/"reactivated" quando o lifecycle do Firestore nao mudou
 * produziria um historico que afirma uma transicao de Personnel inexistente.
 */
export const AUDIT_ACTION = {
  deactivated: "deactivated",
  reactivated: "reactivated",
  reactivationCompensated: "reactivation_compensated",
  authReconciledDisabled: "human_auth_reconciled_disabled",
  authReconciledEnabled: "human_auth_reconciled_enabled",
} as const;

/** Estado ativo canonico de `status`, conforme adminCreateHuman (autoridade). */
export const ACTIVE_STATUS = "Ativo";
/** Estado inativo canonico de `status`, conforme adminArchiveHuman. */
export const INACTIVE_STATUS = "Inativo";

/**
 * `details.reason` e o contrato MINIMO estavel consumido pela camada Web.
 * `extraDetails` e opcional e existe para casos em que o caller precisa saber o
 * que efetivamente foi aplicado antes da falha — nunca substitui o reason.
 */
function fail(
  code:
    | "invalid-argument"
    | "not-found"
    | "failed-precondition"
    | "internal",
  reason: LifecycleErrorReason,
  message: string,
  extraDetails?: JsonMap,
): never {
  throw new HttpsError(code, message, {reason, ...extraDetails});
}

/** Snapshot lido dentro da transacao. */
export interface HumanLifecycleSnapshot {
  exists: boolean;
  data: JsonMap | null;
}

/** Dados minimos da conta de Auth que o lifecycle precisa conhecer. */
export interface AuthAccount {
  uid: string;
  disabled: boolean;
}

/**
 * Presenca de identidade de Auth para o alvo (A1.S1 FROZEN).
 *
 * A distincao entre ABSENT e DANGLING e contratual, nao cosmetica:
 *   - ABSENT  : nenhum alias de uid E nenhuma conta pelo e-mail canonico.
 *               Estado LEGITIMO — `adminCreateHuman` (Human Create V1, CLOSED)
 *               cria Personnel deliberadamente sem Auth, e
 *               `adminAssignAccessProfile` atribui perfil sem exigir conta.
 *               Lifecycle opera normalmente; Auth e NO-OP.
 *   - DANGLING: o documento AFIRMA um uid que nao existe mais no Auth. E drift,
 *               porque `auth_uid` so e gravado por writers que acabaram de
 *               confirmar a conta. Fail-closed.
 */
export type AuthPresence =
  | {kind: "present"; account: AuthAccount}
  | {kind: "absent"}
  | {kind: "dangling"; uid: string};

/**
 * Superficie transacional. Le `users/{ra}` E `active_shifts/{ra}`: uma
 * transacao do Firestore pode ler documentos de colecoes diferentes, e o guard
 * de turno PRECISA ser revalidado no mesmo instante logico da escrita (B2/D-1).
 * Escreve somente `users/{ra}`.
 */
export interface HumanLifecycleTransaction {
  getUser(ra: string): Promise<HumanLifecycleSnapshot>;
  getActiveShift(ra: string): Promise<HumanLifecycleSnapshot>;
  patchUser(ra: string, patch: JsonMap): void;
}

/**
 * Dependencias injetadas. Auth aparece como capacidades explicitas e estreitas
 * (ler `disabled`, escrever `disabled`), o que mantem o modulo incapaz de tocar
 * claims, senha, email ou perfil de acesso.
 */
export interface HumanLifecycleDeps {
  /** Exige autenticacao + capacidade administrativa humans.archive. */
  authorize(): Promise<HumanLifecycleCaller>;
  /** db.runTransaction no wiring real. */
  runTransaction<T>(
    handler: (tx: HumanLifecycleTransaction) => Promise<T>,
  ): Promise<T>;
  /** Leitura read-only de `users/{ra}` para pre-validacao. */
  getUser(ra: string): Promise<HumanLifecycleSnapshot>;
  /** Leitura read-only de `active_shifts/{ra}`. Doc unico: a colecao e chaveada por RA. */
  getActiveShift(ra: string): Promise<HumanLifecycleSnapshot>;
  /**
   * admin.auth().getUser(uid). Retorna `null` quando a conta NAO existe — esse
   * caso e DANGLING (A1.S1 CASE 2), nao ausencia legitima. O `disabled` lido
   * aqui e o valor restaurado pela compensacao (B2/F-5).
   */
  getAuthAccount(uid: string): Promise<AuthAccount | null>;
  /**
   * admin.auth().getUserByEmail(email). Fallback CANONICO ja usado por
   * adminAssignAccessProfile/adminUpsertHuman/setK9InstructorRole. Retorna
   * `null` quando nao existe conta — ai sim e ABSENT (A1.S1 CASE 1).
   */
  findAuthAccountByEmail(email: string): Promise<AuthAccount | null>;
  /**
   * E-mail canonico da conta de Auth, resolvido pelo wiring com a MESMA
   * expressao provada no repo: `users.email` e, na ausencia dele, o padrao
   * institucional derivado do RA. NUNCA `institutional_email`, que pertence a
   * Personnel e nao a conta de acesso.
   */
  canonicalAuthEmail(user: JsonMap, ra: string): string;
  /** admin.auth().updateUser(uid, {disabled}) no wiring real. */
  setAuthDisabled(uid: string, disabled: boolean): Promise<void>;
  /** FieldValue.serverTimestamp() no wiring real. */
  serverTimestamp(): unknown;
  /** auditEntry canonico do index.ts (ator derivado do caller, nunca do payload). */
  auditEntry(
    action: string,
    caller: HumanLifecycleCaller,
    reason?: string,
  ): JsonMap;
  /** FieldValue.arrayUnion(value) no wiring real. */
  arrayUnion(value: unknown): unknown;
  /** FieldValue.delete() no wiring real. */
  deleteField(): unknown;
}

const DEACTIVATE_TOP_LEVEL_KEYS = new Set(["ra", "reason", "expectedUpdatedAt"]);
const REACTIVATE_TOP_LEVEL_KEYS = new Set(["ra", "expectedUpdatedAt", "reason"]);

/** Tamanho minimo do motivo, alinhado ao diálogo legado e as Rules. */
const MIN_REASON_LENGTH = 5;

function isPlainObject(value: unknown): value is JsonMap {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

function assertNoUnknownKeys(raw: JsonMap, allowed: Set<string>): void {
  for (const key of Object.keys(raw)) {
    if (!allowed.has(key)) {
      fail(
        "invalid-argument",
        LIFECYCLE_ERROR.invalidArgument,
        `Chave desconhecida no payload: ${key}.`,
      );
    }
  }
}

/** Formato canonico do RA (espelha assertHumanRa/adminCreateHuman). */
function parseTargetRa(raw: JsonMap): string {
  const value = raw.ra;
  if (value === null || value === undefined) {
    fail(
      "invalid-argument",
      LIFECYCLE_ERROR.invalidArgument,
      "Campo obrigatorio ausente: ra.",
    );
  }
  if (typeof value !== "string") {
    fail(
      "invalid-argument",
      LIFECYCLE_ERROR.invalidArgument,
      "Campo ra deve ser texto.",
    );
  }
  const ra = value.trim();
  if (!/^\d{4,12}$/.test(ra)) {
    fail(
      "invalid-argument",
      LIFECYCLE_ERROR.invalidArgument,
      "RA deve conter apenas numeros.",
    );
  }
  return ra;
}

/**
 * Motivo. Obrigatorio na desativacao, opcional na reativacao — mas quando
 * fornecido e sempre validado com o mesmo rigor.
 */
function parseReason(raw: JsonMap, required: boolean): string | null {
  const present = "reason" in raw && raw.reason !== undefined;
  if (!present) {
    if (required) {
      fail(
        "invalid-argument",
        LIFECYCLE_ERROR.invalidArgument,
        "Campo obrigatorio ausente: reason.",
      );
    }
    return null;
  }
  const value = raw.reason;
  if (value === null) {
    if (required) {
      fail(
        "invalid-argument",
        LIFECYCLE_ERROR.invalidArgument,
        "Campo reason nao pode ser null.",
      );
    }
    return null;
  }
  if (typeof value !== "string") {
    fail(
      "invalid-argument",
      LIFECYCLE_ERROR.invalidArgument,
      "Campo reason deve ser texto.",
    );
  }
  const reason = value.trim();
  if (reason.length < MIN_REASON_LENGTH) {
    fail(
      "invalid-argument",
      LIFECYCLE_ERROR.invalidArgument,
      `Campo reason deve ter ao menos ${MIN_REASON_LENGTH} caracteres.`,
    );
  }
  return reason;
}

/**
 * CONTRATO EXTERNO de concorrencia, identico ao Human Edit V1: `number | null`
 * em epoch millis. ISO/Date/Timestamp NAO sao aceitos no request.
 */
function parseExpectedUpdatedAt(raw: JsonMap): number | null {
  if (!("expectedUpdatedAt" in raw)) {
    fail(
      "invalid-argument",
      LIFECYCLE_ERROR.invalidArgument,
      "Campo obrigatorio ausente: expectedUpdatedAt.",
    );
  }
  const value = raw.expectedUpdatedAt;
  if (value === null) return null;
  if (typeof value !== "number" || !Number.isFinite(value)) {
    fail(
      "invalid-argument",
      LIFECYCLE_ERROR.invalidArgument,
      "expectedUpdatedAt deve ser epoch millis (number) ou null.",
    );
  }
  return value;
}

/**
 * Verificacao de concorrencia contra max(updated_at, updatedAt).
 *
 * Reusa `concurrencyAuthorityMillis` do Human Edit V1 em vez de reimplementar:
 * os dois espelhos nao sao mantidos em sincronia por todos os escritores, e
 * eleger um unico campo permitiria lost update silencioso.
 */
function assertFresh(user: JsonMap, expectedUpdatedAt: number | null): void {
  const storedMillis = concurrencyAuthorityMillis(user);
  const stale = (): never =>
    fail(
      "failed-precondition",
      LIFECYCLE_ERROR.staleWrite,
      "Cadastro do integrante foi alterado por outra sessao. Recarregue antes de continuar.",
    );
  if (expectedUpdatedAt === null) {
    if (storedMillis !== null) stale();
    return;
  }
  if (storedMillis === null) stale();
  if (storedMillis !== expectedUpdatedAt) stale();
  return;
}

/**
 * Leitura canonica de "esta ativo?" no modelo atual. Espelha os leitores do Web
 * (`human-admin-service`, `human-edit-service`): qualquer marcador de
 * arquivamento conta, nao apenas `active`.
 */
export function isCurrentlyActive(user: JsonMap): boolean {
  if (user.active === false) return false;
  if (user.deleted_at !== null && user.deleted_at !== undefined) return false;
  if (user.archived_at !== null && user.archived_at !== undefined) return false;
  const status = user.status;
  if (typeof status === "string") {
    const normalized = status.trim().toLowerCase();
    if (normalized === "inativo" || normalized === "inactive") return false;
  }
  return true;
}

/** Resolve o uid da conta de Auth a partir dos aliases do documento. */
function authUidFrom(user: JsonMap): string | null {
  for (const key of ["auth_uid", "authUid", "uid"]) {
    const value = user[key];
    if (typeof value === "string" && value.trim().length > 0) {
      return value.trim();
    }
  }
  return null;
}

/**
 * Resolve a presenca de identidade de Auth (A1.S1 FROZEN).
 *
 * Ordem, exatamente a canonica ja provada no repo (adminAssignAccessProfile,
 * adminUpsertHuman, setK9InstructorRole):
 *   1. aliases `auth_uid` / `authUid` / `uid` -> getUser(uid)
 *        conta existe    => PRESENT
 *        user-not-found  => DANGLING (fail-closed; o doc afirma um vinculo morto)
 *   2. sem alias -> getUserByEmail(email canonico)
 *        conta existe    => PRESENT (o doc so nao tinha o espelho do uid)
 *        nenhuma conta   => ABSENT (Personnel legitimo sem acesso)
 *
 * O e-mail canonico e `users.email ?? <ra>@gcm.com.br`, resolvido pelo wiring.
 * `institutional_email` NAO participa: pertence a Personnel, nao a conta de
 * acesso, e essa fronteira ja foi protegida no Human Edit V1.
 *
 * Nenhuma heuristica nova, nenhuma conta criada, nenhum uid persistido como
 * efeito colateral do lifecycle.
 */
async function resolveAuthPresence(
  deps: HumanLifecycleDeps,
  user: JsonMap,
  ra: string,
): Promise<AuthPresence> {
  const uid = authUidFrom(user);
  if (uid !== null) {
    const account = await deps.getAuthAccount(uid);
    if (account === null) return {kind: "dangling", uid};
    return {kind: "present", account};
  }
  const account = await deps.findAuthAccountByEmail(
    deps.canonicalAuthEmail(user, ra),
  );
  if (account === null) return {kind: "absent"};
  return {kind: "present", account};
}

/** CASE 2: o documento afirma um vinculo de Auth que deixou de existir. */
function failDangling(uid: string): never {
  fail(
    "failed-precondition",
    LIFECYCLE_ERROR.authIdentityNotFound,
    `O cadastro aponta a conta de autenticacao ${uid}, que nao existe mais. ` +
      "Estado inconsistente: regularize o vinculo antes de alterar o ciclo de vida.",
  );
}

/**
 * Campos que compoem o estado de ciclo de vida do documento. Usados APENAS em
 * memoria, durante uma unica chamada, para permitir compensacao exata (B2/G-1).
 *
 * Isto NAO e o snapshot historico de privilegios rejeitado no A1: nao inclui
 * perfil de acesso, roles nem claims, e nunca e persistido como campo novo.
 */
const LIFECYCLE_STATE_FIELDS = [
  "active",
  "status",
  "deleted_at",
  "deleted_by",
  "delete_reason",
  "deleted_reason",
] as const;

/**
 * Snapshot em memoria do lifecycle imediatamente anterior a operacao.
 *
 * Guarda PRESENCA e valor. A distincao importa: um campo que nao existia deve
 * voltar a NAO existir, e nao virar `null` — `null` e um valor presente e os
 * leitores canonicos (`isCurrentlyActive`, `human-edit-service`) tratam
 * presenca de forma diferente de ausencia.
 */
export type LifecycleStateSnapshot = Map<string, unknown>;

function captureLifecycleState(user: JsonMap): LifecycleStateSnapshot {
  const snapshot: LifecycleStateSnapshot = new Map();
  for (const field of LIFECYCLE_STATE_FIELDS) {
    if (field in user) snapshot.set(field, user[field]);
  }
  return snapshot;
}

/**
 * Monta o patch que restaura EXATAMENTE o snapshot capturado: valor original
 * quando o campo existia, `FieldValue.delete()` quando estava ausente.
 */
function restoreLifecycleStatePatch(
  snapshot: LifecycleStateSnapshot,
  deleteField: () => unknown,
): JsonMap {
  const patch: JsonMap = {};
  for (const field of LIFECYCLE_STATE_FIELDS) {
    patch[field] = snapshot.has(field) ? snapshot.get(field) : deleteField();
  }
  return patch;
}

/** Turno ativo: doc unico `active_shifts/{ra}` com status === "active". */
function hasActiveShift(snapshot: HumanLifecycleSnapshot): boolean {
  if (!snapshot.exists || snapshot.data === null) return false;
  const status = snapshot.data.status;
  return typeof status === "string" && status.trim() === "active";
}

/**
 * Invariante de lifecycle produzido por uma reativacao bem-sucedida.
 *
 * Este e o CAS da compensacao (B2.RA/RA-1). Substitui a falsa "autoria por
 * producedVersion": o read-after-commit observava apenas o ESTADO num instante,
 * e um writer concorrente que escrevesse entre o commit e a releitura fazia sua
 * propria versao ser adotada como se fosse nossa — aprovando o CAS e permitindo
 * clobber. Nao existe token de autoria sem ampliar schema, entao comparamos o
 * DOMINIO: o rollback so acontece se o lifecycle ainda estiver exatamente no
 * estado que a reativacao produziu.
 *
 * Presenca de `null` NAO equivale a ausencia: usa-se teste de presenca real.
 */
function lifecycleMatchesReactivatedState(user: JsonMap): boolean {
  if (user.active !== true) return false;
  if (user.status !== ACTIVE_STATUS) return false;
  for (const field of [
    "deleted_at",
    "deleted_by",
    "delete_reason",
    "deleted_reason",
  ]) {
    if (field in user) return false;
  }
  return true;
}

/**
 * Como a conta de Auth participou da operacao.
 *   - `updated`           : o `disabled` da conta foi efetivamente alterado;
 *   - `not_provisioned`   : Personnel legitimo sem conta (A1.S1 CASE 1);
 *   - `already_converged` : havia conta e ela ja estava no estado alvo.
 */
export type AuthOperationState =
  | "updated"
  | "not_provisioned"
  | "already_converged";

export interface DeactivateHumanResult {
  ra: string;
  active: false;
  status: typeof INACTIVE_STATUS;
  authState: AuthOperationState;
  /** true quando SOMENTE o Auth divergente foi corrigido (Personnel ja inativo). */
  reconciliationOnly: boolean;
}

export interface ReactivateHumanResult {
  ra: string;
  active: true;
  status: typeof ACTIVE_STATUS;
  authState: AuthOperationState;
  /** true quando SOMENTE o Auth divergente foi corrigido (Personnel ja ativo). */
  reconciliationOnly: boolean;
}

/**
 * DESATIVAR.
 *
 * Estado alvo GLOBAL: Personnel inativo E acesso suspenso. `ALREADY_IN_STATE` so
 * ocorre quando ambos ja convergiram (A1.S1) — antes, um Personnel inativo com
 * conta habilitada recebia "ja esta inativo" e o writer se tornava um obstaculo
 * a correcao do proprio drift que deveria resolver.
 *
 * Ordem (transicao normal): validacao read-only -> Auth disable -> transacao
 * Firestore que REVALIDA existencia, OCC e turno -> compensacao de Auth para o
 * valor ANTERIOR se o Firestore falhar.
 */
export async function deactivateHuman(
  deps: HumanLifecycleDeps,
  rawRequest: unknown,
): Promise<DeactivateHumanResult> {
  // Autorizacao antes de qualquer parsing, leitura ou escrita.
  const caller = await deps.authorize();

  if (!isPlainObject(rawRequest)) {
    fail(
      "invalid-argument",
      LIFECYCLE_ERROR.invalidArgument,
      "Payload invalido.",
    );
  }
  assertNoUnknownKeys(rawRequest, DEACTIVATE_TOP_LEVEL_KEYS);
  const ra = parseTargetRa(rawRequest);
  const reason = parseReason(rawRequest, true) as string;
  const expectedUpdatedAt = parseExpectedUpdatedAt(rawRequest);

  // Invariante preservada do adminArchiveHuman legado.
  if (caller.ra === ra) {
    fail(
      "failed-precondition",
      LIFECYCLE_ERROR.selfDeactivationForbidden,
      "O administrador logado nao pode desativar o proprio cadastro.",
    );
  }

  // --- Pre-validacao read-only: nenhuma mutacao pode acontecer antes daqui ---
  const preSnapshot = await deps.getUser(ra);
  if (!preSnapshot.exists || preSnapshot.data === null) {
    fail("not-found", LIFECYCLE_ERROR.notFound, "Integrante nao encontrado.");
  }
  const preUser = preSnapshot.data;

  const presence = await resolveAuthPresence(deps, preUser, ra);
  if (presence.kind === "dangling") failDangling(presence.uid);

  const personnelActive = isCurrentlyActive(preUser);
  const authNeedsDisable =
    presence.kind === "present" && presence.account.disabled === false;

  // Convergencia GLOBAL: Personnel inativo E sem acesso habilitado.
  if (!personnelActive && !authNeedsDisable) {
    fail(
      "failed-precondition",
      LIFECYCLE_ERROR.alreadyInState,
      "Integrante ja esta inativo e sem acesso habilitado.",
    );
  }

  // OCC pre-checada aqui e REVALIDADA na transacao.
  assertFresh(preUser, expectedUpdatedAt);

  // Turno ativo: guard apenas fail-fast; a revalidacao autoritativa acontece
  // dentro da transacao. So se aplica a transicao real de Personnel.
  if (personnelActive && hasActiveShift(await deps.getActiveShift(ra))) {
    fail(
      "failed-precondition",
      LIFECYCLE_ERROR.activeShift,
      "Nao e possivel desativar este integrante enquanto houver turno ativo. Regularize o turno primeiro.",
    );
  }

  // ============================ RECONCILIACAO ============================
  // Personnel JA inativo, mas a conta continua habilitada. Corrigimos somente o
  // Auth: nao ha transicao de Personnel, logo nao se inventa `deleted_*` novo,
  // nao se sobrescreve o motivo original e nao se exige guard de turno (nao
  // estamos afastando ninguem, apenas removendo acesso de quem ja esta inativo).
  if (!personnelActive) {
    const account = (presence as {kind: "present"; account: AuthAccount}).account;
    await disableAuthOrFail(deps, account.uid, true);
    try {
      await deps.runTransaction(async (tx) => {
        const snapshot = await tx.getUser(ra);
        if (!snapshot.exists || snapshot.data === null) {
          fail(
            "not-found",
            LIFECYCLE_ERROR.notFound,
            "Integrante nao encontrado.",
          );
        }
        assertFresh(snapshot.data, expectedUpdatedAt);
        const now = deps.serverTimestamp();
        // NENHUM campo de lifecycle e tocado: apenas registro e espelhos.
        tx.patchUser(ra, {
          updated_at: now,
          updatedAt: now,
          audit_trail: deps.arrayUnion(
            deps.auditEntry(AUDIT_ACTION.authReconciledDisabled, caller, reason),
          ),
        });
      });
    } catch (error) {
      // Deliberadamente NAO reabilitamos a conta: o estado resultante
      // (inativo + sem acesso) e estritamente mais seguro e mais convergido que
      // o drift original. Reverter devolveria acesso a alguem formalmente
      // inativo por causa de uma falha de registro.
      // NAO e COMPENSATION_FAILED: nenhuma reversao foi tentada nem falhou.
      // O rotulo precisa dizer ao caller que a suspensao FOI aplicada, para que
      // ele nao conclua que a desativacao nao aconteceu (B2.RB/RB-1).
      fail(
        "internal",
        LIFECYCLE_ERROR.authAppliedAuditFailed,
        "O acesso foi suspenso, mas nao foi possivel registrar a auditoria. " +
          "A conta permanece desabilitada de proposito (estado mais restritivo). " +
          `Atualize os dados antes de tentar novamente. Erro: ${errorText(error)}`,
        {authApplied: true, authDisabled: true, personnelChanged: false},
      );
    }
    return {
      ra,
      active: false,
      status: INACTIVE_STATUS,
      authState: "updated",
      reconciliationOnly: true,
    };
  }

  // ========================= TRANSICAO NORMAL =========================
  // Estado de Auth ANTERIOR, capturado antes de qualquer mutacao (B2/F-5): a
  // compensacao restaura este valor, nunca um `false` presumido.
  const priorAuthDisabled =
    presence.kind === "present" ? presence.account.disabled : null;
  const authUid = presence.kind === "present" ? presence.account.uid : null;

  // --- Mutacao 1: Firebase Auth (fora da transacao, por retry) ---
  // CASE 1 / ABSENT: nao existe conta a suspender. NO-OP, e jamais criamos uma
  // — Personnel Lifecycle nao e Access Provisioning (A1.S1).
  if (authUid !== null && priorAuthDisabled === false) {
    await disableAuthOrFail(deps, authUid, true);
  }
  const authMutated = authUid !== null && priorAuthDisabled === false;

  // --- Mutacao 2: Firestore, com revalidacao dentro da transacao ---
  try {
    await deps.runTransaction(async (tx) => {
      // TODAS as leituras antes de qualquer escrita.
      const snapshot = await tx.getUser(ra);
      if (!snapshot.exists || snapshot.data === null) {
        fail(
          "not-found",
          LIFECYCLE_ERROR.notFound,
          "Integrante nao encontrado.",
        );
      }
      const user = snapshot.data;

      // Guard de turno REVALIDADO no mesmo instante logico da escrita (D-1).
      const shift = await tx.getActiveShift(ra);

      assertFresh(user, expectedUpdatedAt);

      if (hasActiveShift(shift)) {
        fail(
          "failed-precondition",
          LIFECYCLE_ERROR.activeShift,
          "Nao e possivel desativar este integrante enquanto houver turno ativo. Regularize o turno primeiro.",
        );
      }

      const now = deps.serverTimestamp();
      tx.patchUser(ra, {
        active: false,
        status: INACTIVE_STATUS,
        deleted_at: now,
        deleted_by: caller.uid,
        delete_reason: reason,
        deleted_reason: reason,
        updated_at: now,
        updatedAt: now,
        audit_trail: deps.arrayUnion(
          deps.auditEntry(AUDIT_ACTION.deactivated, caller, reason),
        ),
      });
    });
  } catch (error) {
    // Compensacao: o estado administrativo nao mudou, logo a conta deve voltar
    // ao estado em que ESTAVA — que pode ser `disabled: true` por outro motivo.
    if (authMutated && authUid !== null) {
      try {
        // `authMutated` so e verdadeiro quando `priorAuthDisabled === false`:
        // uma conta ja desabilitada nunca e mutada, portanto nunca precisa de
        // compensacao. Restaurar = voltar a `false`, o valor real anterior.
        // A invariante F-5 ("nao habilitar conta que ja estava desabilitada")
        // e garantida na entrada, nao aqui.
        await deps.setAuthDisabled(authUid, false);
      } catch (compensationError) {
        fail(
          "internal",
          LIFECYCLE_ERROR.compensationFailed,
          "A desativacao falhou no Firestore e a conta de autenticacao NAO pude ser restaurada. " +
            `Estado divergente: Auth desabilitado, cadastro ainda ativo. Erro original: ${errorText(error)}. ` +
            `Erro da compensacao: ${errorText(compensationError)}`,
        );
      }
    }
    throw error;
  }

  return {
    ra,
    active: false,
    status: INACTIVE_STATUS,
    authState:
      authUid === null
        ? "not_provisioned"
        : authMutated
          ? "updated"
          : "already_converged",
    reconciliationOnly: false,
  };
}

/**
 * REATIVAR.
 *
 * Estado alvo GLOBAL: Personnel ativo E acesso habilitado. `ALREADY_IN_STATE` so
 * ocorre quando ambos convergiram; Personnel ativo com conta desabilitada e
 * RECONCILIACAO, nao recusa.
 *
 * Ordem (transicao normal): validacao read-only -> transacao Firestore -> Auth
 * enable -> compensacao do Firestore sob CAS de invariante de lifecycle.
 */
export async function reactivateHuman(
  deps: HumanLifecycleDeps,
  rawRequest: unknown,
): Promise<ReactivateHumanResult> {
  const caller = await deps.authorize();

  if (!isPlainObject(rawRequest)) {
    fail(
      "invalid-argument",
      LIFECYCLE_ERROR.invalidArgument,
      "Payload invalido.",
    );
  }
  assertNoUnknownKeys(rawRequest, REACTIVATE_TOP_LEVEL_KEYS);
  const ra = parseTargetRa(rawRequest);
  const reason = parseReason(rawRequest, false);
  const expectedUpdatedAt = parseExpectedUpdatedAt(rawRequest);

  const preSnapshot = await deps.getUser(ra);
  if (!preSnapshot.exists || preSnapshot.data === null) {
    fail("not-found", LIFECYCLE_ERROR.notFound, "Integrante nao encontrado.");
  }
  const preUser = preSnapshot.data;

  const presence = await resolveAuthPresence(deps, preUser, ra);
  if (presence.kind === "dangling") failDangling(presence.uid);

  const personnelActive = isCurrentlyActive(preUser);
  const authNeedsEnable =
    presence.kind === "present" && presence.account.disabled === true;

  if (personnelActive && !authNeedsEnable) {
    fail(
      "failed-precondition",
      LIFECYCLE_ERROR.alreadyInState,
      "Integrante ja esta ativo com o acesso disponivel.",
    );
  }

  assertFresh(preUser, expectedUpdatedAt);

  // ============================ RECONCILIACAO ============================
  // Personnel JA ativo, mas a conta esta desabilitada. Corrigimos somente o
  // Auth: nenhum campo de Personnel/lifecycle e reescrito.
  if (personnelActive) {
    const account = (presence as {kind: "present"; account: AuthAccount}).account;
    await disableAuthOrFail(deps, account.uid, false);
    try {
      await deps.runTransaction(async (tx) => {
        const snapshot = await tx.getUser(ra);
        if (!snapshot.exists || snapshot.data === null) {
          fail(
            "not-found",
            LIFECYCLE_ERROR.notFound,
            "Integrante nao encontrado.",
          );
        }
        assertFresh(snapshot.data, expectedUpdatedAt);
        const now = deps.serverTimestamp();
        tx.patchUser(ra, {
          updated_at: now,
          updatedAt: now,
          audit_trail: deps.arrayUnion(
            reason === null
              ? deps.auditEntry(AUDIT_ACTION.authReconciledEnabled, caller)
              : deps.auditEntry(
                AUDIT_ACTION.authReconciledEnabled,
                caller,
                reason,
              ),
          ),
        });
      });
    } catch (error) {
      // Aqui a compensacao E feita, ao contrario da reconciliacao de
      // desativacao: uma concessao de acesso nao registrada e pior que manter a
      // conta desabilitada. Sempre preferimos o estado mais restritivo.
      try {
        await deps.setAuthDisabled(account.uid, true);
      } catch (compensationError) {
        fail(
          "internal",
          LIFECYCLE_ERROR.compensationFailed,
          "O acesso foi reabilitado, o registro de auditoria falhou e a conta NAO pude ser " +
            "desabilitada de volta. Estado divergente: acesso concedido sem auditoria. " +
            `Erro original: ${errorText(error)}. Erro da compensacao: ${errorText(compensationError)}`,
        );
      }
      // A compensacao FUNCIONOU: a conta voltou a desabilitada e nenhum acesso
      // ficou concedido. Rotular como COMPENSATION_FAILED diria ao caller que a
      // reversao nao foi garantida, o que e falso [B1.R4].
      fail(
        "internal",
        LIFECYCLE_ERROR.authEnableRevertedAuditFailed,
        "Nao foi possivel concluir a reativacao do acesso. A alteracao foi revertida " +
          "e a conta permanece desabilitada. Atualize os dados antes de tentar novamente. " +
          `Erro: ${errorText(error)}`,
        {
          authEnableAttempted: true,
          authReverted: true,
          authDisabled: true,
          personnelChanged: false,
        },
      );
    }
    return {
      ra,
      active: true,
      status: ACTIVE_STATUS,
      authState: "updated",
      reconciliationOnly: true,
    };
  }

  // ========================= TRANSICAO NORMAL =========================
  // Snapshot EM MEMORIA do lifecycle pre-operacao (G-1). Nao e persistido e nao
  // inclui perfil/roles/claims: serve apenas para compensar esta chamada.
  const preOperationLifecycle = captureLifecycleState(preUser);
  const authUid = presence.kind === "present" ? presence.account.uid : null;
  const authNeedsMutation =
    presence.kind === "present" && presence.account.disabled === true;

  // --- Mutacao 1: Firestore ---
  await deps.runTransaction(async (tx) => {
    const snapshot = await tx.getUser(ra);
    if (!snapshot.exists || snapshot.data === null) {
      fail("not-found", LIFECYCLE_ERROR.notFound, "Integrante nao encontrado.");
    }
    const user = snapshot.data;
    assertFresh(user, expectedUpdatedAt);

    const now = deps.serverTimestamp();
    // Perfil de acesso, roles, claims e Personnel NAO aparecem aqui: reativar
    // devolve o estado administrativo, nunca privilegio historico.
    tx.patchUser(ra, {
      active: true,
      status: ACTIVE_STATUS,
      deleted_at: deps.deleteField(),
      deleted_by: deps.deleteField(),
      delete_reason: deps.deleteField(),
      deleted_reason: deps.deleteField(),
      updated_at: now,
      updatedAt: now,
      audit_trail: deps.arrayUnion(
        reason === null
          ? deps.auditEntry(AUDIT_ACTION.reactivated, caller)
          : deps.auditEntry(AUDIT_ACTION.reactivated, caller, reason),
      ),
    });
  });

  // --- Mutacao 2: Firebase Auth, apos o estado administrativo estar ativo ---
  // CASE 1 / ABSENT: nada a habilitar e nada a compensar, porque nenhuma
  // mutacao cross-service ocorreu. Jamais criamos conta (A1.S1).
  if (authUid === null || !authNeedsMutation) {
    return {
      ra,
      active: true,
      status: ACTIVE_STATUS,
      authState: authUid === null ? "not_provisioned" : "already_converged",
      reconciliationOnly: false,
    };
  }

  try {
    await deps.setAuthDisabled(authUid, false);
  } catch (error) {
    // Sem acesso efetivo, o cadastro nao deve figurar como ativo. A reversao so
    // e legitima se o LIFECYCLE ainda estiver no estado que produzimos — CAS de
    // dominio, nao de autoria temporal (RA-1).
    try {
      await deps.runTransaction(async (tx) => {
        const snapshot = await tx.getUser(ra);
        if (!snapshot.exists || snapshot.data === null) {
          fail(
            "not-found",
            LIFECYCLE_ERROR.notFound,
            "Integrante nao encontrado durante a compensacao.",
          );
        }
        if (!lifecycleMatchesReactivatedState(snapshot.data)) {
          // Outro writer mexeu no LIFECYCLE. Nao sobrescrevemos.
          // Alteracoes concorrentes em Personnel (telefone, unidade) ou Access
          // (perfil, claims) NAO bloqueiam: o patch abaixo toca somente os seis
          // campos de lifecycle + espelhos + auditoria.
          fail(
            "failed-precondition",
            LIFECYCLE_ERROR.staleWrite,
            "concurrent lifecycle modification",
          );
        }

        const now = deps.serverTimestamp();
        tx.patchUser(ra, {
          ...restoreLifecycleStatePatch(preOperationLifecycle, deps.deleteField),
          updated_at: now,
          updatedAt: now,
          audit_trail: deps.arrayUnion(
            deps.auditEntry(
              AUDIT_ACTION.reactivationCompensated,
              caller,
              "Falha ao reabilitar a conta de autenticacao.",
            ),
          ),
        });
      });
    } catch (compensationError) {
      const concurrent =
        compensationError instanceof HttpsError &&
        (compensationError.details as {reason?: unknown} | undefined)?.reason ===
          LIFECYCLE_ERROR.staleWrite;
      fail(
        "internal",
        LIFECYCLE_ERROR.compensationFailed,
        concurrent
          ? "A reativacao falhou no Auth e a reversao foi RECUSADA porque o ciclo de vida " +
              "do cadastro foi alterado por outra sessao (concurrent lifecycle modification). " +
              "Nada foi sobrescrito. Estado divergente: cadastro possivelmente ativo, " +
              `Auth ainda desabilitado. Erro original: ${errorText(error)}`
          : "A reativacao falhou no Auth e o cadastro NAO pude ser revertido. " +
              `Estado divergente: cadastro ativo, Auth ainda desabilitado. Erro original: ${errorText(error)}. ` +
              `Erro da compensacao: ${errorText(compensationError)}`,
      );
    }
    fail(
      "internal",
      LIFECYCLE_ERROR.authOperationFailed,
      `Falha ao reabilitar a conta de autenticacao: ${errorText(error)}`,
    );
  }

  return {
    ra,
    active: true,
    status: ACTIVE_STATUS,
    authState: "updated",
    reconciliationOnly: false,
  };
}

/** Mutacao de Auth com erro tipado. Sempre FORA de callback transacional. */
async function disableAuthOrFail(
  deps: HumanLifecycleDeps,
  uid: string,
  disabled: boolean,
): Promise<void> {
  try {
    await deps.setAuthDisabled(uid, disabled);
  } catch (error) {
    fail(
      "internal",
      LIFECYCLE_ERROR.authOperationFailed,
      `Falha ao ${disabled ? "desabilitar" : "reabilitar"} a conta de autenticacao: ${errorText(error)}`,
    );
  }
}

function errorText(error: unknown): string {
  if (error instanceof Error) return error.message;
  return String(error);
}
