/**
 * CLIN-AUTH-BE-4A.I2.T0 — SEAM DE TESTABILIDADE DOS WRITERS DE ACCESS PROFILE.
 *
 * Extração MECÂNICA: os writers de `access_profiles` viviam inline em
 * `index.ts` como `onCall(...)` fechando sobre o `db` real do módulo, o que
 * tornava impossível exercitar localmente — sem Firebase — justamente os
 * invariants que o hardening 4A existe para travar:
 *
 *   - atomicidade de autorização (AUTHORIZED_OPERATION === EXECUTED_OPERATION);
 *   - `expectedUpdatedAt` obrigatório em EDIT / proibido em CREATE;
 *   - revogação explícita (`false` → FieldValue.delete() em merge);
 *   - validação do PAR canônico `module.action`;
 *   - `seed_version` server-managed;
 *   - zero write em qualquer caminho de falha.
 *
 * NENHUMA decisão funcional foi alterada nesta extração. As funções `run*`
 * recebem `deps` e o `index.ts` as liga aos dependentes reais.
 *
 * Por que este módulo NÃO importa `./index`: `index.ts` importa daqui para
 * fazer o wiring de produção. Importar de volta criaria ciclo. Seguindo a
 * convenção já existente no repositório (`health_*_callables.ts`), os
 * primitivos puros e genéricos são cópias locais verbatim — mesma prática de
 * `stringValue`, hoje duplicado em quatro módulos. O que carrega POLÍTICA
 * (autorização e trilha de auditoria) não é duplicado: é injetado.
 */
import * as admin from "firebase-admin";
import {CallableRequest, HttpsError} from "firebase-functions/v2/https";

import {AccessScope, parseAccessScope} from "./access_scope";

type JsonMap = Record<string, unknown>;

/**
 * Identidade do ator já resolvida pelo gate de autorização. Estruturalmente
 * idêntica a `CallerIdentity` de `index.ts` — mesma prática de
 * `DocumentCaller`/`RestrictionCaller` nos módulos irmãos.
 */
export interface AccessProfileWriterCaller {
  uid: string;
  email: string;
  ra: string;
  name: string;
}

/**
 * Fábrica da entrada de trilha de auditoria. Injetada, e não copiada: é
 * política de auditoria pertencente a `index.ts` (60 call sites) e duplicá-la
 * abriria espaço para divergência silenciosa de audit trail. Injetá-la também
 * dá ao teste um relógio determinístico sem alterar representação de tempo.
 */
export type AccessProfileAuditEntryFactory = (
  action: string,
  caller: AccessProfileWriterCaller,
  reason?: string,
) => JsonMap;

/**
 * Taxonomia canônica de ações de access profile.
 *
 * Fonte ÚNICA da união: `index.ts` importa este tipo. Duplicar a união em dois
 * módulos permitiria que a taxonomia de política divergisse.
 */
export type AccessProfileAction =
  | "view"
  // Leitura clínica (Clinical Read). Historicamente ausente desta união
  // embora já persistida nos perfis canônicos: a validação de permissões era
  // key-agnostic, então `health.read` gravava sem nunca constar do tipo.
  | "read"
  | "create"
  | "edit"
  | "archive"
  | "approve"
  | "audit"
  | "export"
  | "manage_nutrition_plan"
  | "record_routine"
  // Autoridade de emissão de restrição operacional (B1). Deliberadamente
  // distinta de `create`/`edit`: registrar um documento não é declarar que um
  // K9 não pode trabalhar.
  | "issue_restriction"
  // Transições terminais (B2). Três poderes distintos, três capabilities
  // distintas (ADR-005 E12): emitir cria impacto operacional, liberar declara
  // que o motivo clínico terminou, cancelar invalida o próprio registro.
  // `cancel_restriction` tem nome próprio porque um cancel indevido recoloca
  // um K9 em operação sem afirmar melhora clínica.
  | "release_restriction"
  | "cancel_restriction";

/**
 * Dependências externas ao comportamento do writer.
 *
 * `requireAccessPermission` é injetado com a assinatura COMPLETA — e não como
 * um booleano `authorized` — porque o invariant de atomicidade exige provar
 * QUAL capability foi exigida ("create" vs "edit").
 */
export interface AccessProfileWriterDeps {
  db: FirebaseFirestore.Firestore;
  requireAccessPermission: (
    auth: CallableRequest["auth"],
    moduleId: "access",
    action: AccessProfileAction,
  ) => Promise<AccessProfileWriterCaller>;
  auditEntry: AccessProfileAuditEntryFactory;
}

// ─────────────────────────────────────────────────────────────────────────────
// PRIMITIVOS PUROS — cópias verbatim dos equivalentes de `index.ts`.
// Mantidos locais para evitar ciclo de módulos (ver cabeçalho). Nenhum deles
// carrega política: são parsers determinísticos.
// ─────────────────────────────────────────────────────────────────────────────

function stringValue(value: unknown): string | undefined {
  if (value === null || value === undefined) return undefined;
  const text = String(value).trim();
  return text.length === 0 ? undefined : text;
}

function requiredString(data: JsonMap, key: string): string {
  const value = stringValue(data[key]);
  if (!value) {
    throw new HttpsError("invalid-argument", `Campo obrigatório ausente: ${key}.`);
  }
  return value;
}

function optionalString(data: JsonMap, key: string): string | null {
  return stringValue(data[key]) ?? null;
}

function optionalNumberValue(value: unknown): number | null {
  if (typeof value === "number" && Number.isFinite(value)) return value;
  if (typeof value !== "string") return null;
  const parsed = Number(value.trim().replace(",", "."));
  return Number.isFinite(parsed) ? parsed : null;
}

function normalizedKey(value: unknown): string {
  return String(value ?? "")
    .trim()
    .toLowerCase()
    .normalize("NFD")
    .replace(/[\u0300-\u036f]/g, "")
    .replace(/[^a-z0-9]+/g, "_")
    .replace(/^_+|_+$/g, "");
}

function stringList(value: unknown): string[] {
  if (!Array.isArray(value)) return [];
  return value
    .map((item) => stringValue(item))
    .filter((item): item is string => Boolean(item));
}

function isPlainObject(value: unknown): value is JsonMap {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

function mapArray(value: unknown): JsonMap[] {
  if (!Array.isArray(value)) return [];
  return value.filter((item): item is JsonMap => isPlainObject(item));
}

function assertDocumentId(id: string, label: string): void {
  if (!/^[a-zA-Z0-9_-]{1,120}$/.test(id)) {
    throw new HttpsError("invalid-argument", `${label} contem caracteres invalidos.`);
  }
}

function isTimestamp(value: unknown): value is admin.firestore.Timestamp {
  return value instanceof admin.firestore.Timestamp;
}

// ─────────────────────────────────────────────────────────────────────────────
// POLÍTICA DE CAPABILITY — fonte única de verdade do par `module.action`.
// ─────────────────────────────────────────────────────────────────────────────

// CLIN-AUTH-BE-4A.I1.R1: a autoridade validada ao ESCREVER um access profile é
// o PAR canônico `module.action`, não a interseção de duas allowlists globais
// independentes. Validar só `módulo conhecido && ação conhecida` produziria uma
// matriz cartesiana inválida (ex.: `dashboard.cancel_restriction`,
// `me.manage_nutrition_plan`, `vehicles.record_routine`) — combinações em que
// cada token existe mas o par nunca é legítimo.
//
// Fontes versionadas dos pares:
//   1. contrato canônico de seed (default-access-profiles v6);
//   2. capabilities operacionais emitidas pelo próprio backend, todas no
//      módulo `health` (`record_routine` para WeightRecord; `issue_/release_/
//      cancel_restriction` no ciclo de vida de restrição).
//
// A maioria dos módulos compartilha o mesmo conjunto administrativo de sete
// ações observado no perfil `administrador` do seed.
export const BASE_ACCESS_PROFILE_ACTIONS: readonly AccessProfileAction[] = [
  "view",
  "create",
  "edit",
  "archive",
  "export",
  "approve",
  "audit",
];

export const CANONICAL_ACCESS_PROFILE_CAPABILITIES: Record<string, ReadonlySet<string>> = {
  access: new Set(BASE_ACCESS_PROFILE_ACTIONS),
  audit: new Set(BASE_ACCESS_PROFILE_ACTIONS),
  binomials: new Set(BASE_ACCESS_PROFILE_ACTIONS),
  dashboard: new Set(BASE_ACCESS_PROFILE_ACTIONS),
  humans: new Set(BASE_ACCESS_PROFILE_ACTIONS),
  inventory: new Set(BASE_ACCESS_PROFILE_ACTIONS),
  k9: new Set(BASE_ACCESS_PROFILE_ACTIONS),
  occurrences: new Set(BASE_ACCESS_PROFILE_ACTIONS),
  reports: new Set(BASE_ACCESS_PROFILE_ACTIONS),
  settings: new Set(BASE_ACCESS_PROFILE_ACTIONS),
  shifts: new Set(BASE_ACCESS_PROFILE_ACTIONS),
  training: new Set(BASE_ACCESS_PROFILE_ACTIONS),
  training_matrix: new Set(BASE_ACCESS_PROFILE_ACTIONS),
  vehicles: new Set(BASE_ACCESS_PROFILE_ACTIONS),
  // `me` no seed carrega apenas o par mínimo de autogestão.
  me: new Set<string>(["view", "edit"]),
  // `health` acumula o conjunto administrativo do seed mais as capabilities
  // clínicas/operacionais próprias do domínio.
  health: new Set<string>([
    ...BASE_ACCESS_PROFILE_ACTIONS,
    "read",
    "manage_nutrition_plan",
    "record_routine",
    "issue_restriction",
    "release_restriction",
    "cancel_restriction",
    // CLIN-WRITER-1.W2 — vocabulário clínico canônico. DEFINIÇÃO APENAS.
    // Entrar neste catálogo torna o PAR `health.<action>` sintaticamente
    // válido para uma futura concessão; NÃO concede nada a nenhum perfil.
    // Capability ausente de `access_profiles/{id}.permissions` continua
    // significando NÃO CONCEDIDA (fail-closed por omissão).
    // Estas cinco autorizam comandos callable do backend (Admin SDK), nunca
    // escrita Firestore do cliente — os três níveis de `clinical_cases`
    // permanecem `allow create, update, delete: if false`.
    "record_clinical",
    "finalize_clinical",
    "amend_clinical",
    "manage_clinical_case",
    "reopen_clinical_case",
  ]),
};

// Prova a legitimidade do PAR exato. Um typo (`heath.read`, `health.Read`) ou
// uma combinação cruzada inválida falha aqui sem qualquer normalização.
export function isCanonicalCapability(moduleId: string, action: string): boolean {
  const actions = CANONICAL_ACCESS_PROFILE_CAPABILITIES[moduleId];
  return actions !== undefined && actions.has(action);
}

/**
 * Valida escopo em caminho de ESCRITA. Rejeita com erro estruturado em vez de
 * coagir para `"global"`: nenhum writer pode ampliar permissão por omissão ou
 * erro de digitação.
 */
export function requireAccessScope(value: unknown): AccessScope {
  const scope = parseAccessScope(value);
  if (scope === null) {
    throw new HttpsError(
      "invalid-argument",
      "scope deve ser exatamente \"global\" ou \"own_records\".",
      {code: "invalid-access-scope"},
    );
  }
  return scope;
}

// Modo de mutação do payload de permissões.
//
// "merge"   → escrita incremental sobre documento existente. `false` vira
//             FieldValue.delete(), removendo de fato a capability.
// "replace" → documento novo/substituído sem merge. Um sentinel de delete não
//             é aceito pela API nesse formato, então `false` apenas omite a
//             chave — semanticamente idêntico num documento que ainda não
//             existe.
export type AccessPermissionMutationMode = "merge" | "replace";

// CLIN-AUTH-BE-4A: sanitizador tri-state, exclusivo do caminho de ESCRITA.
//
// Não confundir com `sanitizeAccessPermissions` (em `index.ts`), que continua
// sendo usado na leitura de autoridade (`profileGrantsPermission`) e por isso
// NÃO pode lançar erro nem produzir sentinels.
//
// Contrato congelado:
//   ação ausente        → não aparece no payload (merge preserva o stored)
//   true                → true
//   false               → revogação explícita (delete em merge, omissão em
//                         replace)
//   null / não-booleano → invalid-argument
//   módulo/ação fora da taxonomia canônica, submetido explicitamente
//                       → invalid-argument
export function accessPermissionsWritePayload(
  value: unknown,
  mode: AccessPermissionMutationMode,
): JsonMap {
  if (value === undefined) return {};
  if (value === null || !isPlainObject(value)) {
    throw new HttpsError(
      "invalid-argument",
      "Permissões do perfil devem ser um mapa de módulos.",
    );
  }

  const permissions: JsonMap = {};
  for (const [moduleId, modulePermissions] of Object.entries(value)) {
    if (modulePermissions === undefined) continue;
    // A chave é validada COMO VEIO. Normalizar um typo de capability para uma
    // chave válida transformaria erro de digitação em concessão de autoridade.
    if (CANONICAL_ACCESS_PROFILE_CAPABILITIES[moduleId] === undefined) {
      throw new HttpsError(
        "invalid-argument",
        `Módulo de permissão desconhecido: ${moduleId}.`,
      );
    }
    if (modulePermissions === null || !isPlainObject(modulePermissions)) {
      throw new HttpsError(
        "invalid-argument",
        `Permissões do módulo ${moduleId} devem ser um mapa de ações.`,
      );
    }

    const actions: JsonMap = {};
    for (const [action, enabled] of Object.entries(modulePermissions)) {
      if (enabled === undefined) continue;
      // Par exato, não "ação existe em algum módulo".
      if (!isCanonicalCapability(moduleId, action)) {
        throw new HttpsError(
          "invalid-argument",
          `Capability desconhecida para este módulo: ${moduleId}.${action}.`,
        );
      }
      if (typeof enabled !== "boolean") {
        throw new HttpsError(
          "invalid-argument",
          `Permissão ${moduleId}.${action} deve ser booleana. ` +
            "Ausência preserva o valor atual; false revoga explicitamente.",
        );
      }
      if (enabled) {
        actions[action] = true;
      } else if (mode === "merge") {
        actions[action] = admin.firestore.FieldValue.delete();
      }
      // mode === "replace" com false: omite a chave.
    }
    permissions[moduleId] = actions;
  }
  return permissions;
}

export function accessProfilePayload(
  profileId: string,
  source: JsonMap,
  caller: AccessProfileWriterCaller,
  options: {
    action: string;
    exists: boolean;
    status?: "active" | "inactive";
    // Modo de mutação real do call site. Obrigatório: um sentinel de delete
    // vazando para um set() sem merge lançaria em runtime.
    permissionMode: AccessPermissionMutationMode;
    // Valor de `seed_version` AFIRMADO PELO SERVIDOR. Quando presente, o
    // payload do cliente não tem nenhuma autoridade sobre o campo.
    //
    // `adminSaveAccessProfile` sempre o fornece — em EDIT com o valor do
    // documento armazenado, em CREATE com 0 (perfil manual não tem
    // proveniência de seed). Omitir é reservado aos writers que SÃO a
    // autoridade de seed (`adminSeedAccessProfiles`) ou que derivam de um
    // perfil já existente (`adminDuplicateAccessProfile`).
    storedSeedVersion?: number | null;
  },
  auditEntry: AccessProfileAuditEntryFactory,
): JsonMap {
  const status =
    options.status ??
    (stringValue(source.status) === "inactive" ? "inactive" : "active");
  const payload: JsonMap = {
    id: profileId,
    description: optionalString(source, "description") ?? "",
    level: optionalString(source, "level") ?? "restrito",
    module_tags: stringList(source.module_tags),
    name: requiredString(source, "name"),
    permissions: accessPermissionsWritePayload(
      source.permissions,
      options.permissionMode,
    ),
    role_keys: stringList(source.role_keys),
    // SEC-02A: escopo é validado explicitamente. Antes, qualquer valor
    // diferente de "own_records" — inclusive ausente, "" ou "ownRecords" —
    // era reescrito silenciosamente como "global", transformando erro de
    // digitação numa ampliação de permissão persistida.
    scope: requireAccessScope(source.scope),
    // CLIN-AUTH-BE-4A: `seed_version` é server-managed.
    //
    // Quando `storedSeedVersion` é fornecido (fluxo de save sobre documento
    // existente), o valor armazenado prevalece: um cliente desatualizado não
    // pode regredir a versão de seed e reabrir a pendência de sincronização.
    // O seeder (`adminSeedAccessProfiles`) não passa esse campo e mantém a
    // autoridade de avançar/reconciliar a versão.
    seed_version:
      options.storedSeedVersion !== undefined
        ? options.storedSeedVersion ?? 0
        : optionalNumberValue(source.seed_version) ?? 0,
    slug: optionalString(source, "slug") ?? profileId,
    status,
    tone: optionalString(source, "tone") ?? "cyan",
    ui_hidden: source.ui_hidden === true,
    updated_at: admin.firestore.FieldValue.serverTimestamp(),
    updated_by: caller.ra,
    audit_trail: options.exists
      ? admin.firestore.FieldValue.arrayUnion(auditEntry(options.action, caller))
      : [auditEntry("created", caller)],
  };

  if (!options.exists) {
    payload.created_at = admin.firestore.FieldValue.serverTimestamp();
    payload.created_by = caller.ra;
  }

  return payload;
}

export function accessProfileUpdatedAtMillis(stored: JsonMap): number | null {
  const value = stored.updated_at;
  if (isTimestamp(value)) return value.toMillis();
  return null;
}

export async function runAdminSaveAccessProfile(
  request: CallableRequest,
  deps: AccessProfileWriterDeps,
): Promise<{id: string; created: boolean}> {
  const data = request.data as JsonMap;
  const source = (data.profile ?? {}) as JsonMap;
  const profileId = stringValue(data.id) ?? requiredString(source, "id");
  assertDocumentId(profileId, "Identificador do perfil");
  const expectedUpdatedAtRaw = data.expectedUpdatedAt;

  const ref = deps.db.collection("access_profiles").doc(profileId);
  // CLIN-AUTH-BE-4A.I1.R1: a operação é CONGELADA aqui, antes da autorização, e
  // a transação não pode trocá-la.
  //
  // Antes, a existência era reavaliada dentro da transação e a operação
  // executada podia divergir da autorizada: um caller com apenas `access.create`
  // acabava executando um EDIT se outro processo criasse o documento na janela
  // entre a pré-leitura e o commit (e o inverso, EDIT autorizado virando
  // CREATE, se o documento desaparecesse).
  const preAuthSnapshot = await ref.get();
  const expectedOperation: "create" | "edit" =
    preAuthSnapshot.exists ? "edit" : "create";
  const caller = await deps.requireAccessPermission(
    request.auth,
    "access",
    expectedOperation,
  );

  const created = await deps.db.runTransaction(async (transaction) => {
    const snapshot = await transaction.get(ref);

    // A existência atual precisa continuar compatível com a operação
    // autorizada. Qualquer transição fecha a operação sem escrever nada.
    // `failed-precondition` — e não `permission-denied`/`already-exists`/
    // `not-found` — porque o caller estava legitimamente autorizado para a
    // before-image; foi o recurso que mudou antes do commit.
    if (expectedOperation === "create" && snapshot.exists) {
      throw new HttpsError(
        "failed-precondition",
        "Perfil passou a existir durante a operação. Recarregue e edite.",
        {code: "profile-operation-changed", expected: "create", actual: "edit"},
      );
    }
    if (expectedOperation === "edit" && !snapshot.exists) {
      throw new HttpsError(
        "failed-precondition",
        "Perfil deixou de existir durante a operação. Recarregue a lista.",
        {code: "profile-operation-changed", expected: "edit", actual: "create"},
      );
    }

    if (expectedOperation === "create") {
      // CREATE. O documento não existe, então não há versão a confrontar:
      // aceitar um `expectedUpdatedAt` aqui daria a falsa impressão de que a
      // criação foi protegida contra concorrência.
      if (expectedUpdatedAtRaw !== undefined && expectedUpdatedAtRaw !== null) {
        throw new HttpsError(
          "invalid-argument",
          "expectedUpdatedAt não se aplica à criação de perfil.",
        );
      }
      transaction.set(
        ref,
        accessProfilePayload(
          profileId,
          source,
          caller,
          {
            action: "created",
            exists: false,
            // Documento novo, escrito com merge: `false` não tem valor
            // armazenado para revogar, então a chave é apenas omitida.
            permissionMode: "replace",
            // CLIN-AUTH-BE-4A.I2.R1: `seed_version` é server-managed também na
            // CRIAÇÃO manual. Antes, sem valor armazenado a confrontar, o campo
            // caía no payload do cliente: bastava enviar a versão canônica
            // vigente para que um perfil criado à mão se apresentasse como
            // sincronizado por seed, sem nunca ter passado por
            // seeding/reconciliação. Um perfil manual não tem proveniência de
            // seed — logo, 0.
            storedSeedVersion: 0,
          },
          deps.auditEntry,
        ),
        {merge: true},
      );
      return true;
    }

    // EDIT — alcançado somente sob autoridade `access.edit`, com o documento
    // comprovadamente existente. `expectedUpdatedAt` é obrigatório: não existe
    // rota legacy sem precondition, porque era exatamente ela que permitia o
    // stale write restaurar silenciosamente uma capability revogada.
    if (expectedUpdatedAtRaw === undefined || expectedUpdatedAtRaw === null) {
      throw new HttpsError(
        "invalid-argument",
        "expectedUpdatedAt é obrigatório para editar um perfil de acesso.",
      );
    }
    if (
      typeof expectedUpdatedAtRaw !== "number" ||
      !Number.isFinite(expectedUpdatedAtRaw)
    ) {
      throw new HttpsError(
        "invalid-argument",
        "expectedUpdatedAt deve ser epoch em milissegundos (number).",
      );
    }

    const stored = snapshot.data() ?? {};
    const storedUpdatedAt = accessProfileUpdatedAtMillis(stored);
    if (storedUpdatedAt === null) {
      throw new HttpsError(
        "failed-precondition",
        "Perfil sem updated_at canônico; recarregue o perfil antes de editar.",
      );
    }
    if (storedUpdatedAt !== expectedUpdatedAtRaw) {
      throw new HttpsError(
        "failed-precondition",
        "Perfil alterado por outra operação. Recarregue antes de salvar.",
      );
    }

    transaction.set(
      ref,
      accessProfilePayload(
        profileId,
        source,
        caller,
        {
          action: "updated",
          exists: true,
          // Documento existente: `false` precisa remover a chave armazenada,
          // senão o merge preserva o `true` e a revogação é um no-op.
          permissionMode: "merge",
          storedSeedVersion: optionalNumberValue(stored.seed_version) ?? 0,
        },
        deps.auditEntry,
      ),
      {merge: true},
    );
    return false;
  });

  return {id: profileId, created};
}

export async function runAdminDuplicateAccessProfile(
  request: CallableRequest,
  deps: AccessProfileWriterDeps,
): Promise<{id: string}> {
  const caller = await deps.requireAccessPermission(
    request.auth,
    "access",
    "create",
  );
  const data = request.data as JsonMap;
  const source = (data.profile ?? {}) as JsonMap;
  const sourceId = requiredString(source, "id");
  const profileId =
    stringValue(data.id) ??
    `${normalizedKey(sourceId).slice(0, 70)}_copia_${Date.now().toString(36)}`;
  assertDocumentId(profileId, "Identificador do perfil");

  const ref = deps.db.collection("access_profiles").doc(profileId);
  if ((await ref.get()).exists) {
    throw new HttpsError("already-exists", "Ja existe um perfil com este identificador.");
  }

  await ref.set(
    accessProfilePayload(
      profileId,
      {
        ...source,
        id: profileId,
        name: `${requiredString(source, "name")} (copia)`,
        slug: profileId,
      },
      caller,
      {
        action: "duplicated",
        exists: false,
        status: "inactive",
        // set() sem merge cria um documento novo: um FieldValue.delete() nesse
        // formato lançaria em runtime, então `false` apenas omite a chave.
        permissionMode: "replace",
      },
      deps.auditEntry,
    ),
  );
  return {id: profileId};
}

export async function runAdminSeedAccessProfiles(
  request: CallableRequest,
  deps: AccessProfileWriterDeps,
): Promise<{archived: string[]; created: string[]; updated: string[]}> {
  const caller = await deps.requireAccessPermission(
    request.auth,
    "access",
    "approve",
  );
  const data = request.data as JsonMap;
  const profiles = mapArray(data.profiles);
  const reconcile = data.reconcile !== false;
  if (profiles.length === 0) {
    throw new HttpsError("invalid-argument", "Nenhum perfil informado para seed.");
  }

  const batch = deps.db.batch();
  const created: string[] = [];
  const updated: string[] = [];
  const archived: string[] = [];
  const seedIds = new Set<string>();
  for (const profile of profiles) {
    const profileId = requiredString(profile, "id");
    assertDocumentId(profileId, "Identificador do perfil");
    seedIds.add(profileId);
    const ref = deps.db.collection("access_profiles").doc(profileId);
    const snapshot = await ref.get();
    if (snapshot.exists) {
      updated.push(profileId);
    } else {
      created.push(profileId);
    }
    batch.set(ref, accessProfilePayload(profileId, profile, caller, {
      action: snapshot.exists ? "seed_updated" : "seeded",
      exists: snapshot.exists,
      // A escrita real é set(..., {merge: true}), então o modo de mutação
      // acompanha essa semântica. `storedSeedVersion` é deliberadamente
      // omitido: o seeder permanece a autoridade que avança/reconcilia
      // `seed_version`.
      permissionMode: "merge",
    }, deps.auditEntry), {merge: true});
  }

  if (reconcile) {
    const snapshot = await deps.db.collection("access_profiles").get();
    for (const docSnapshot of snapshot.docs) {
      if (seedIds.has(docSnapshot.id)) continue;
      const dataBefore = docSnapshot.data() ?? {};
      if (dataBefore.status === "inactive") continue;
      batch.set(docSnapshot.ref, {
        status: "inactive",
        deprecated_by_seed: true,
        updated_at: admin.firestore.FieldValue.serverTimestamp(),
        updated_by: caller.ra,
        audit_trail: admin.firestore.FieldValue.arrayUnion(
          deps.auditEntry("inactivated_by_profile_seed", caller),
        ),
      }, {merge: true});
      archived.push(docSnapshot.id);
    }
  }

  if (created.length > 0 || updated.length > 0 || archived.length > 0) {
    batch.set(deps.db.collection("auditLogs").doc(), {
      action: "access_profiles_seeded",
      entity_type: "access_profiles",
      entity_id: "access_profiles",
      summary: `Matriz de perfis reconciliada: ${created.length} criados, ${updated.length} atualizados, ${archived.length} inativados`,
      actor: caller,
      metadata: {archived, created, reconcile, updated},
      source: "functions",
      performed_at: admin.firestore.FieldValue.serverTimestamp(),
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
    });
  }
  await batch.commit();
  return {archived, created, updated};
}
