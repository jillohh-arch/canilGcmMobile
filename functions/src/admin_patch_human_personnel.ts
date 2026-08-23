/**
 * adminPatchHumanPersonnel — edicao administrativa estrita de PESSOAL humano.
 *
 * Este callable altera SOMENTE o registro de pessoal em `users/{ra}`.
 *
 * Ele NAO substitui o legado adminUpsertHuman e e deliberadamente incapaz de:
 *   - criar/alterar/desabilitar conta Firebase Auth;
 *   - alterar email/displayName/senha de Auth;
 *   - gravar claims (setCustomUserClaims);
 *   - resolver/gravar perfil de acesso, roles, escopo;
 *   - gravar binomio/conducao;
 *   - gravar turno/escala;
 *   - conceder autoridade de treino/instrutor;
 *   - anexar/alterar foto;
 *   - alterar ciclo de vida (active/status);
 *   - alterar Health.
 *
 * Regras estruturais (D1 / D1.R1 CONTRACT LOCKED):
 *   - `ra` e alvo imutavel: nao e patchavel nem limpavel;
 *   - patch aceita 12 campos de pessoal; chave desconhecida => REJECT;
 *   - campo de outro dominio => REJECT (fail closed);
 *   - `null` em patch => REJECT (limpeza exige clearFields);
 *   - string vazia/branca => REJECT (nao e sinal de limpeza);
 *   - clearFields remove o conjunto de aliases PERSONNEL do campo (D1.R1),
 *     nunca um alias de acesso/Auth;
 *   - `expectedUpdatedAt` e obrigatorio e, NO CONTRATO EXTERNO, e
 *     `number | null` em epoch millis — ISO/Date/Timestamp NAO sao aceitos;
 *   - concorrencia otimista: max(updated_at, updatedAt), nunca `??`;
 *   - verificacao e escrita ocorrem na MESMA transacao.
 *
 * A logica fica isolada em `patchHumanPersonnel` com dependencias injetadas.
 * A interface de dependencias nao expoe nenhuma capacidade de Auth/acesso, o
 * que torna a mutacao cross-domain estruturalmente impossivel. O wiring real
 * do Firestore vive em `index.ts`.
 */

import {HttpsError} from "firebase-functions/v2/https";

type JsonMap = Record<string, unknown>;

/** Compativel estruturalmente com o CallerIdentity canonico do index.ts. */
export interface PatchHumanPersonnelCaller {
  uid: string;
  email: string;
  ra: string;
  name: string;
}

/** Documento lido dentro da transacao. */
export interface HumanPersonnelSnapshot {
  exists: boolean;
  data: JsonMap | null;
}

/**
 * Superficie transacional minima. Deliberadamente so sabe LER e ESCREVER
 * `users/{ra}`: nao ha acesso a Auth, access_profiles, dogs, turnos ou Storage.
 */
export interface HumanPersonnelTransaction {
  getUser(ra: string): Promise<HumanPersonnelSnapshot>;
  patchUser(ra: string, patch: JsonMap): void;
}

/**
 * Dependencias injetadas. A ausencia de qualquer dependencia de Auth/claims/
 * acesso e parte do contrato: nao existe caminho de codigo capaz de mutar
 * esses dominios.
 */
export interface PatchHumanPersonnelDeps {
  /** Exige autenticacao + capacidade administrativa humans.edit. */
  authorize(): Promise<PatchHumanPersonnelCaller>;
  /** db.runTransaction no wiring real. */
  runTransaction<T>(
    handler: (tx: HumanPersonnelTransaction) => Promise<T>,
  ): Promise<T>;
  /** FieldValue.serverTimestamp() no wiring real. */
  serverTimestamp(): unknown;
  /** auditEntry canonico do index.ts. */
  auditEntry(action: string, caller: PatchHumanPersonnelCaller): JsonMap;
  /** FieldValue.arrayUnion(value) no wiring real. */
  arrayUnion(value: unknown): unknown;
  /** FieldValue.delete() no wiring real. */
  deleteField(): unknown;
}

/** Chaves de topo aceitas no request. */
const ALLOWED_TOP_LEVEL_KEYS = new Set<string>([
  "ra",
  "expectedUpdatedAt",
  "patch",
  "clearFields",
]);

/**
 * Campos obrigatorios do cadastro: podem ser OMITIDOS do patch (preservar),
 * mas quando enviados precisam ser texto valido — e nunca podem ser limpos.
 */
const REQUIRED_FIELDS = ["fullName", "callsign"] as const;

/** Campos opcionais de pessoal: patchaveis e limpaveis. */
const CLEARABLE_FIELDS = [
  "cpf",
  "birthDate",
  "phone",
  "institutionalEmail",
  "rank",
  "cargo",
  "unit",
  "team",
  "admissionDate",
  "notes",
] as const;

type RequiredField = (typeof REQUIRED_FIELDS)[number];
type ClearableField = (typeof CLEARABLE_FIELDS)[number];
type PatchField = RequiredField | ClearableField;

/** Ordem canonica dos campos, usada para saida determinística. */
const PATCH_FIELDS = [
  ...REQUIRED_FIELDS,
  ...CLEARABLE_FIELDS,
] as const satisfies readonly PatchField[];

const PATCH_FIELD_SET = new Set<string>(PATCH_FIELDS);
const CLEARABLE_FIELD_SET = new Set<string>(CLEARABLE_FIELDS);

/**
 * Campo wire -> campo(s) canonico(s) ESCRITO(s), identico ao mapa congelado do
 * adminCreateHuman (DOCUMENT_FIELDS_BY_WIRE). Aliases legados NAO sao
 * reescritos so porque existem historicamente.
 */
const WRITE_FIELDS_BY_WIRE: Record<PatchField, string[]> = {
  fullName: ["name", "nomeCompleto"],
  callsign: ["callsign", "callSign"],
  cpf: ["cpf"],
  birthDate: ["birth_date"],
  phone: ["telefone"],
  institutionalEmail: ["institutional_email"],
  rank: ["rank"],
  cargo: ["cargo"],
  unit: ["unit"],
  team: ["team"],
  admissionDate: ["admission_date"],
  notes: ["notes"],
};

/**
 * Conjunto de propriedade PERSONNEL removido numa limpeza explicita (D1.R1).
 *
 * Apagar apenas o campo canonico nao basta: os readers do Web sao
 * first-match-wins e, com o canonico AUSENTE, avancam para o proximo alias —
 * fazendo um valor legado "ressuscitar" e parecer que a limpeza falhou.
 *
 * `institutionalEmail` remove SOMENTE `institutional_email`: seu unico outro
 * alias (`email`) e o espelho da conta de Auth e jamais pode ser apagado. Esse
 * caso e resolvido no reader do Web, nao aqui.
 *
 * Nenhum alias de acesso/Auth/treino/turno aparece neste mapa.
 */
const CLEAR_FIELDS_BY_WIRE: Record<ClearableField, string[]> = {
  cpf: ["cpf", "document"],
  birthDate: ["birth_date", "birthDate"],
  phone: ["telefone", "phone"],
  institutionalEmail: ["institutional_email"],
  rank: ["rank", "posto", "graduacao"],
  cargo: ["cargo", "função"],
  unit: ["unit", "unidade", "lotação"],
  team: ["team", "equipe"],
  admissionDate: ["admission_date", "admissionDate"],
  notes: ["notes", "observações"],
};

/**
 * Campos explicitamente proibidos, com dominio responsavel, para mensagem de
 * erro precisa. Espelha o estilo provado do adminCreateHuman. Qualquer outra
 * chave desconhecida tambem e recusada pelo fail closed geral.
 */
const FORBIDDEN_FIELD_DOMAIN: Record<string, string> = {
  // Provisionamento de acesso
  accessProfile: "provisionamento de acesso",
  accessProfileId: "provisionamento de acesso",
  access_profile: "provisionamento de acesso",
  access_profile_id: "provisionamento de acesso",
  accessLevel: "provisionamento de acesso",
  access_level: "provisionamento de acesso",
  accessScope: "provisionamento de acesso",
  access_scope: "provisionamento de acesso",
  access_role: "provisionamento de acesso",
  roles: "provisionamento de acesso",
  role: "provisionamento de acesso",
  admin: "provisionamento de acesso",
  claims: "provisionamento de acesso",
  claim_role: "provisionamento de acesso",
  claim_updated_at: "provisionamento de acesso",
  mobile_access: "provisionamento de acesso",
  web_access: "provisionamento de acesso",
  app_access: "provisionamento de acesso",
  inventory_manager: "provisionamento de acesso",
  // Conta de autenticacao
  auth_uid: "conta de autenticacao",
  authUid: "conta de autenticacao",
  uid: "conta de autenticacao",
  email: "conta de autenticacao",
  displayName: "conta de autenticacao",
  password: "conta de autenticacao",
  temporaryPassword: "conta de autenticacao",
  temporary_password: "conta de autenticacao",
  disabled: "conta de autenticacao",
  // Treino / instrutor
  isK9Instructor: "treino",
  is_k9_instructor: "treino",
  training_instructor: "treino",
  training_role: "treino",
  specialties: "treino/capacitacoes",
  certifications: "treino/capacitacoes",
  // Binomio / conducao
  binomial: "binomio/conducao",
  binomialId: "binomio/conducao",
  handlerId: "binomio/conducao",
  handlerRa: "binomio/conducao",
  conductorRa: "binomio/conducao",
  conductor_ra: "binomio/conducao",
  // Turno / operacional
  shiftGroupId: "turno/escala",
  shift_group_id: "turno/escala",
  shiftLabel: "turno/escala",
  shift_label: "turno/escala",
  vehicle: "turno/escala",
  crew: "turno/escala",
  // Foto (capacidade separada)
  photoUrl: "foto (capacidade separada)",
  photoURL: "foto (capacidade separada)",
  photo_url: "foto (capacidade separada)",
  profileImageUrl: "foto (capacidade separada)",
  // Ciclo de vida / metadados de servidor
  active: "ciclo de vida",
  status: "ciclo de vida",
  archived: "ciclo de vida",
  archived_at: "ciclo de vida",
  deleted_at: "ciclo de vida",
  deleted_by: "ciclo de vida",
  created_at: "metadados de servidor",
  createdAt: "metadados de servidor",
  updated_at: "metadados de servidor",
  updatedAt: "metadados de servidor",
  audit_trail: "metadados de servidor",
  // Controle legado
  mode: "controle legado (adminUpsertHuman)",
  profile: "controle legado (adminUpsertHuman)",
};

function isPlainObject(value: unknown): value is JsonMap {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

/** Mensagem de recusa de campo, com dominio quando conhecido. */
function rejectField(field: string, context: string): never {
  const domain = FORBIDDEN_FIELD_DOMAIN[field];
  if (domain) {
    throw new HttpsError(
      "invalid-argument",
      `Campo ${field} pertence ao dominio ${domain} e nao pode ser enviado na edicao de pessoal.`,
    );
  }
  throw new HttpsError("invalid-argument", `${context}: ${field}.`);
}

/**
 * Aceita apenas string nao-vazia apos trim. Nao coage numero/boolean: payload
 * malformado falha fechado. `null` e recusado com mensagem especifica, porque
 * limpeza exige clearFields.
 */
function patchText(field: string, value: unknown): string {
  if (value === null) {
    throw new HttpsError(
      "invalid-argument",
      `Campo ${field} recebeu null. Limpeza de campo exige clearFields.`,
    );
  }
  if (value === undefined) {
    throw new HttpsError(
      "invalid-argument",
      `Campo ${field} recebeu undefined. Omita o campo para preserva-lo.`,
    );
  }
  if (typeof value !== "string") {
    throw new HttpsError("invalid-argument", `Campo ${field} deve ser texto.`);
  }
  const text = value.trim();
  if (text.length === 0) {
    throw new HttpsError(
      "invalid-argument",
      `Campo ${field} nao pode ser vazio. Para remover, use clearFields.`,
    );
  }
  return text;
}

/** Formato canonico do RA (espelha assertHumanRa/adminCreateHuman). */
function assertRa(ra: string): void {
  if (!/^\d{4,12}$/.test(ra)) {
    throw new HttpsError("invalid-argument", "RA deve conter apenas numeros.");
  }
}

/**
 * Validador do RA alvo. RA nunca vem de patch/clearFields: e apenas o alvo.
 */
function parseTargetRa(raw: JsonMap): string {
  const value = raw.ra;
  if (value === null || value === undefined) {
    throw new HttpsError(
      "invalid-argument",
      "Campo obrigatorio ausente: ra.",
    );
  }
  if (typeof value !== "string") {
    throw new HttpsError("invalid-argument", "Campo ra deve ser texto.");
  }
  const ra = value.trim();
  if (ra.length === 0) {
    throw new HttpsError("invalid-argument", "Campo ra nao pode ser vazio.");
  }
  assertRa(ra);
  return ra;
}

/**
 * Validador do CONTRATO EXTERNO de concorrencia.
 *
 * Deliberadamente estrito: `number | null` em epoch millis. ISO string, Date e
 * Firestore Timestamp NAO sao aceitos no request, mesmo que o normalizador de
 * valores ARMAZENADOS saiba interpreta-los. Normalizacao de leitura nao e
 * contrato de escrita.
 */
function parseExpectedUpdatedAt(raw: JsonMap): number | null {
  if (!("expectedUpdatedAt" in raw)) {
    throw new HttpsError(
      "invalid-argument",
      "Campo obrigatorio ausente: expectedUpdatedAt.",
    );
  }
  const value = raw.expectedUpdatedAt;
  if (value === null) return null;
  if (typeof value !== "number" || !Number.isFinite(value)) {
    throw new HttpsError(
      "invalid-argument",
      "expectedUpdatedAt deve ser epoch millis (number) ou null.",
    );
  }
  return value;
}

/** Parse do objeto `patch`: allowlist + tipos + trim. */
function parsePatch(raw: JsonMap): Map<PatchField, string> {
  const result = new Map<PatchField, string>();
  if (!("patch" in raw) || raw.patch === undefined) return result;
  const patch = raw.patch;
  if (!isPlainObject(patch)) {
    throw new HttpsError("invalid-argument", "Campo patch deve ser um objeto.");
  }
  for (const key of Object.keys(patch)) {
    if (!PATCH_FIELD_SET.has(key)) {
      rejectField(key, "Campo nao pertence ao cadastro de pessoal");
    }
  }
  // Percorre na ordem canonica para saida determinística.
  for (const field of PATCH_FIELDS) {
    if (!(field in patch)) continue;
    result.set(field, patchText(field, patch[field]));
  }
  return result;
}

/** Parse de `clearFields`: allowlist + duplicidade + campos obrigatorios. */
function parseClearFields(raw: JsonMap): Set<ClearableField> {
  const result = new Set<ClearableField>();
  if (!("clearFields" in raw) || raw.clearFields === undefined) return result;
  const clearFields = raw.clearFields;
  if (!Array.isArray(clearFields)) {
    throw new HttpsError(
      "invalid-argument",
      "Campo clearFields deve ser uma lista.",
    );
  }
  for (const entry of clearFields) {
    if (typeof entry !== "string") {
      throw new HttpsError(
        "invalid-argument",
        "clearFields aceita apenas nomes de campo em texto.",
      );
    }
    if ((REQUIRED_FIELDS as readonly string[]).includes(entry)) {
      throw new HttpsError(
        "invalid-argument",
        `Campo ${entry} e obrigatorio e nao pode ser removido.`,
      );
    }
    if (!CLEARABLE_FIELD_SET.has(entry)) {
      rejectField(entry, "Campo nao pode ser removido na edicao de pessoal");
    }
    if (result.has(entry as ClearableField)) {
      throw new HttpsError(
        "invalid-argument",
        `Campo ${entry} duplicado em clearFields.`,
      );
    }
    result.add(entry as ClearableField);
  }
  return result;
}

interface ParsedPatchRequest {
  ra: string;
  expectedUpdatedAt: number | null;
  patch: Map<PatchField, string>;
  clearFields: Set<ClearableField>;
}

function parseRequest(rawRequest: unknown): ParsedPatchRequest {
  if (!isPlainObject(rawRequest)) {
    throw new HttpsError("invalid-argument", "Payload invalido.");
  }

  // Fail closed: nenhuma chave de topo fora do allowlist.
  for (const key of Object.keys(rawRequest)) {
    if (!ALLOWED_TOP_LEVEL_KEYS.has(key)) {
      rejectField(key, "Chave desconhecida no payload");
    }
  }

  const ra = parseTargetRa(rawRequest);
  const expectedUpdatedAt = parseExpectedUpdatedAt(rawRequest);
  const patch = parsePatch(rawRequest);
  const clearFields = parseClearFields(rawRequest);

  // Um campo nao pode ser atualizado e removido na mesma operacao.
  for (const field of clearFields) {
    if (patch.has(field)) {
      throw new HttpsError(
        "invalid-argument",
        `Campo ${field} aparece em patch e clearFields simultaneamente.`,
      );
    }
  }

  if (patch.size === 0 && clearFields.size === 0) {
    throw new HttpsError(
      "invalid-argument",
      "Nada para atualizar: informe patch ou clearFields.",
    );
  }

  return {ra, expectedUpdatedAt, patch, clearFields};
}

/**
 * Normalizador de timestamp ARMAZENADO no Firestore.
 *
 * Permissivo de proposito: `updated_at`/`updatedAt` podem chegar como
 * Timestamp, Date, number ou string ISO dependendo do escritor. Este helper
 * NAO e usado para validar `request.expectedUpdatedAt`.
 */
export function storedTimestampMillis(value: unknown): number | null {
  if (value === null || value === undefined) return null;
  if (typeof value === "number") {
    return Number.isFinite(value) ? value : null;
  }
  if (value instanceof Date) {
    return Number.isNaN(value.getTime()) ? null : value.getTime();
  }
  const candidate = value as {toMillis?: unknown; toDate?: unknown};
  if (typeof candidate.toMillis === "function") {
    const millis = (candidate.toMillis as () => number)();
    return Number.isFinite(millis) ? millis : null;
  }
  if (typeof candidate.toDate === "function") {
    const asDate = (candidate.toDate as () => Date)();
    return Number.isNaN(asDate.getTime()) ? null : asDate.getTime();
  }
  if (typeof value === "string") {
    const parsed = Date.parse(value);
    return Number.isNaN(parsed) ? null : parsed;
  }
  return null;
}

/**
 * Autoridade de concorrencia do documento `users/{ra}`.
 *
 * O documento tem dois espelhos (`updated_at` e `updatedAt`) que NAO sao
 * mantidos em sincronia por todos os escritores: o legado adminUpsertHuman
 * escreve ambos, enquanto servicos de cliente e scripts administrativos
 * escrevem somente `updated_at`.
 *
 * Eleger um unico campo como autoridade permitiria lost update silencioso:
 * bastaria o escritor concorrente ter bumpado apenas o outro espelho. Por isso
 * a autoridade e o MAIS NOVO entre os espelhos presentes — nunca
 * `updated_at ?? updatedAt`.
 */
export function concurrencyAuthorityMillis(user: JsonMap): number | null {
  const candidates = [
    storedTimestampMillis(user.updated_at ?? null),
    storedTimestampMillis(user.updatedAt ?? null),
  ].filter((value): value is number => value !== null);
  if (candidates.length === 0) return null;
  return Math.max(...candidates);
}

export interface PatchHumanPersonnelResult {
  ra: string;
  updated: true;
  updatedFields: string[];
  clearedFields: string[];
}

export async function patchHumanPersonnel(
  deps: PatchHumanPersonnelDeps,
  rawRequest: unknown,
): Promise<PatchHumanPersonnelResult> {
  // Autorizacao antes de qualquer parsing/leitura/escrita.
  const caller = await deps.authorize();
  const parsed = parseRequest(rawRequest);

  return deps.runTransaction(async (tx) => {
    const snapshot = await tx.getUser(parsed.ra);
    if (!snapshot.exists || snapshot.data === null) {
      throw new HttpsError("not-found", "Integrante nao encontrado.");
    }
    const user = snapshot.data;

    // Concorrencia otimista ANTES de montar qualquer escrita.
    const storedMillis = concurrencyAuthorityMillis(user);
    const staleError = new HttpsError(
      "failed-precondition",
      "Cadastro do integrante foi alterado por outra sessao. Recarregue antes de editar.",
    );
    if (parsed.expectedUpdatedAt === null) {
      if (storedMillis !== null) throw staleError;
    } else if (storedMillis === null) {
      throw staleError;
    } else if (storedMillis !== parsed.expectedUpdatedAt) {
      throw staleError;
    }

    const documentPatch: JsonMap = {};
    const updatedFields: string[] = [];
    const clearedFields: string[] = [];

    // Atualizacoes: somente campos canonicos do mapa congelado do Create.
    for (const field of PATCH_FIELDS) {
      const value = parsed.patch.get(field);
      if (value === undefined) continue;
      for (const documentField of WRITE_FIELDS_BY_WIRE[field]) {
        documentPatch[documentField] = value;
      }
      updatedFields.push(field);
    }

    // Limpezas explicitas: remove o conjunto PERSONNEL do campo (D1.R1).
    for (const field of CLEARABLE_FIELDS) {
      if (!parsed.clearFields.has(field)) continue;
      for (const documentField of CLEAR_FIELDS_BY_WIRE[field]) {
        documentPatch[documentField] = deps.deleteField();
      }
      clearedFields.push(field);
    }

    // Timestamps espelhados: um unico instante logico. `created_at`/`createdAt`
    // e `claim_updated_at` permanecem intocados.
    const now = deps.serverTimestamp();
    documentPatch.updated_at = now;
    documentPatch.updatedAt = now;

    // Auditoria: exatamente uma entrada appendada, preservando o historico.
    documentPatch.audit_trail = deps.arrayUnion(
      deps.auditEntry("updated", caller),
    );

    tx.patchUser(parsed.ra, documentPatch);

    return {
      ra: parsed.ra,
      updated: true as const,
      updatedFields,
      clearedFields,
    };
  });
}
