/**
 * adminPatchK9Identity — patch administrativo seguro da identidade do K9.
 *
 * Este callable substitui o comportamento legado de edicao, que reescrevia o
 * documento inteiro do K9 e podia sobrescrever saude, binomio, treino,
 * especialidades ou reativar um K9 arquivado.
 *
 * Regras estruturais:
 * - somente o dominio de identidade administrativa e gravado;
 * - campos omitidos sao preservados;
 * - null enviado pelo cliente nunca limpa campo (use clearFields);
 * - qualquer campo fora do dominio de identidade e recusado (fail closed).
 *
 * A logica fica isolada em `patchK9Identity` com dependencias injetadas para
 * permitir teste direto sem emulador. O wiring real do Firestore vive em
 * `index.ts`.
 */

import {HttpsError} from "firebase-functions/v2/https";

type JsonMap = Record<string, unknown>;

/** Compativel estruturalmente com o CallerIdentity canonico do index.ts. */
export interface PatchCaller {
  uid: string;
  email: string;
  ra: string;
  name: string;
}

export interface DogSnapshotLike {
  exists: boolean;
  data(): JsonMap | undefined;
}

export interface K9IdentityTransaction {
  /** Leitura do K9 alvo dentro da transacao. */
  getDog(dogId: string): Promise<DogSnapshotLike>;
  /**
   * Ids de K9 que ja usam a matricula/RGA informada, considerando o campo
   * canonico `registrationNumber` e o espelho legado `matricula`.
   */
  findRegistrationOwners(registrationNumber: string): Promise<string[]>;
  /** Merge patch no documento do K9. */
  patchDog(dogId: string, patch: JsonMap): void;
  /** Registro em auditLogs. */
  writeAuditLog(entry: JsonMap): void;
}

export interface K9IdentityPatchDeps {
  /** Exige autenticacao + capacidade administrativa k9.edit. */
  authorize(): Promise<PatchCaller>;
  runTransaction<T>(handler: (tx: K9IdentityTransaction) => Promise<T>): Promise<T>;
  /** FieldValue.serverTimestamp() no wiring real. */
  serverTimestamp(): unknown;
  /** auditEntry canonico do index.ts. */
  auditEntry(action: string, caller: PatchCaller): JsonMap;
  /** FieldValue.arrayUnion no wiring real. */
  arrayUnion(value: JsonMap): unknown;
}

/**
 * Campos obrigatorios de identidade: nome do campo no payload (wire) mapeado
 * para os campos canonicos do documento `dogs/{dogId}`.
 *
 * `registrationNumber` grava tambem o espelho legado `matricula`, exatamente
 * como o contrato canonico de criacao (k9ProfilePayload).
 */
const REQUIRED_IDENTITY_FIELDS = new Set([
  "name",
  "registrationNumber",
  "breed",
  "sex",
  "birthDate",
]);

const OPTIONAL_IDENTITY_FIELDS = new Set([
  "color",
  "microchip",
  "size",
  "profileImageUrl",
  "notes",
]);

/** Campo wire -> campo canonico do documento. */
const DOCUMENT_FIELD_BY_WIRE_FIELD: Record<string, string> = {
  name: "name",
  registrationNumber: "registrationNumber",
  breed: "breed",
  sex: "sex",
  birthDate: "dateOfBirth",
  color: "cor",
  microchip: "microchip",
  size: "porte",
  profileImageUrl: "profileImageUrl",
  notes: "observacoes",
};

const ALLOWED_TOP_LEVEL_KEYS = new Set([
  "dogId",
  "expectedUpdatedAt",
  "patch",
  "clearFields",
]);

/**
 * Campos explicitamente recusados, com o dominio responsavel. Serve para
 * mensagem de erro precisa; qualquer outro campo desconhecido tambem e
 * recusado pelo fail closed geral.
 */
const FORBIDDEN_FIELD_DOMAIN: Record<string, string> = {
  conductorRa: "binomio/conducao",
  conductor_ra: "binomio/conducao",
  binomial: "binomio/conducao",
  binomialId: "binomio/conducao",
  handlerRa: "binomio/conducao",
  weight: "saude/peso",
  idealWeightMin: "saude/peso",
  idealWeightMax: "saude/peso",
  physicalCondition: "saude",
  condicaoCorporal: "saude",
  health: "saude",
  readiness: "prontidao",
  restrictions: "restricoes operacionais",
  operational_restrictions: "restricoes operacionais",
  specialties: "especialidades",
  training: "treino",
  operationalStatus: "estado operacional",
  status: "estado operacional",
  active: "ciclo de vida/arquivamento",
  archived_at: "ciclo de vida/arquivamento",
  deleted_at: "ciclo de vida/arquivamento",
  deleted_by: "ciclo de vida/arquivamento",
  delete_reason: "ciclo de vida/arquivamento",
  updated_at: "metadados de servidor",
  updatedAt: "metadados de servidor",
  created_at: "metadados de servidor",
  audit_trail: "metadados de servidor",
  id: "identificador do documento",
};

function isPlainObject(value: unknown): value is JsonMap {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

function assertDocumentId(id: string): void {
  if (!/^[a-zA-Z0-9_-]{1,120}$/.test(id)) {
    throw new HttpsError(
      "invalid-argument",
      "Identificador do K9 contem caracteres invalidos.",
    );
  }
}

/**
 * Identidade aceita apenas string. Diferente do stringValue canonico, nao
 * coage numero/boolean: payload malformado falha fechado.
 */
function identityString(field: string, value: unknown): string {
  if (typeof value !== "string") {
    throw new HttpsError(
      "invalid-argument",
      `Campo ${field} deve ser texto.`,
    );
  }
  const text = value.trim();
  if (text.length === 0) {
    throw new HttpsError(
      "invalid-argument",
      `Campo ${field} nao pode ser vazio. Use clearFields para limpar campos opcionais.`,
    );
  }
  return text;
}

/** Mesma normalizacao do parseK9BirthDate canonico: ISO ancorado ao meio-dia. */
function parseBirthDate(value: unknown): string {
  const birthDate = identityString("birthDate", value);
  const parsed = new Date(`${birthDate}T12:00:00`);
  if (Number.isNaN(parsed.getTime())) {
    throw new HttpsError("invalid-argument", "Data de nascimento do K9 invalida.");
  }
  return parsed.toISOString();
}

function timestampMillis(value: unknown): number | null {
  if (value === null || value === undefined) return null;
  if (typeof value === "number") {
    return Number.isFinite(value) ? value : null;
  }
  if (value instanceof Date) {
    return Number.isNaN(value.getTime()) ? null : value.getTime();
  }
  const candidate = value as {toMillis?: unknown; toDate?: unknown};
  if (typeof candidate.toMillis === "function") {
    return (candidate.toMillis as () => number)();
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
 * Autoridade de concorrencia do documento `dogs/{id}`.
 *
 * O documento tem dois espelhos de timestamp (`updated_at` e `updatedAt`) que
 * NAO sao mantidos em sincronia por todos os escritores:
 * - adminUpsertK9, adminArchiveK9, adminCreateK9WeightRecord: escrevem ambos;
 * - generateNutritionAiInsight: escreve somente `updated_at`;
 * - mobile dog_service.dart (saveDog/updateDogWeight/deleteDog/updateDogDates):
 *   escreve somente `updatedAt`.
 *
 * Eleger um unico campo como autoridade permitiria lost update silencioso:
 * bastaria o escritor concorrente ter bumpado apenas o outro espelho. Por isso
 * a autoridade e o MAIS NOVO entre os dois espelhos presentes.
 */
function concurrencyAuthorityMillis(dog: JsonMap): number | null {
  const candidates = [
    timestampMillis(dog.updated_at ?? null),
    timestampMillis(dog.updatedAt ?? null),
  ].filter((value): value is number => value !== null);
  if (candidates.length === 0) return null;
  return Math.max(...candidates);
}

/**
 * Semantica canonica de arquivamento (espelha adminArchiveK9 e as checagens de
 * protectedK9Modalities): inativo por `active === false`, `status` inativo, ou
 * marcas de exclusao/arquivamento.
 */
function archivedReason(dog: JsonMap): string | null {
  if (dog.active === false) return "K9 inativo";
  if (dog.deleted_at != null) return "K9 excluido";
  if (dog.archived_at != null) return "K9 arquivado";
  const status = String(dog.status ?? "").trim().toLowerCase();
  if (status === "inativo" || status === "inactive") return "K9 inativo";
  return null;
}

function assertNoForbiddenField(field: string, source: "patch" | "clearFields"): void {
  const domain = FORBIDDEN_FIELD_DOMAIN[field];
  if (domain) {
    throw new HttpsError(
      "invalid-argument",
      `Campo ${field} pertence ao dominio ${domain} e nao pode ser alterado por este patch de identidade.`,
    );
  }
  if (!REQUIRED_IDENTITY_FIELDS.has(field) && !OPTIONAL_IDENTITY_FIELDS.has(field)) {
    throw new HttpsError(
      "invalid-argument",
      `Campo ${field} nao pertence a identidade administrativa do K9 (${source}).`,
    );
  }
}

interface ParsedPatchRequest {
  dogId: string;
  expectedUpdatedAt: unknown;
  expectedUpdatedAtProvided: boolean;
  patch: JsonMap;
  clearFields: string[];
}

function parseRequest(raw: unknown): ParsedPatchRequest {
  if (!isPlainObject(raw)) {
    throw new HttpsError("invalid-argument", "Payload invalido.");
  }
  for (const key of Object.keys(raw)) {
    if (!ALLOWED_TOP_LEVEL_KEYS.has(key)) {
      throw new HttpsError("invalid-argument", `Chave desconhecida no payload: ${key}.`);
    }
  }

  if (typeof raw.dogId !== "string") {
    throw new HttpsError("invalid-argument", "Campo obrigatório ausente: dogId.");
  }
  const dogId = raw.dogId.trim();
  if (dogId.length === 0) {
    throw new HttpsError("invalid-argument", "Campo obrigatório ausente: dogId.");
  }
  assertDocumentId(dogId);

  if (!("expectedUpdatedAt" in raw)) {
    throw new HttpsError(
      "invalid-argument",
      "Campo obrigatório ausente: expectedUpdatedAt.",
    );
  }

  const patchRaw = raw.patch ?? {};
  if (!isPlainObject(patchRaw)) {
    throw new HttpsError("invalid-argument", "Campo patch deve ser um objeto.");
  }

  const clearRaw = raw.clearFields ?? [];
  if (!Array.isArray(clearRaw)) {
    throw new HttpsError("invalid-argument", "Campo clearFields deve ser uma lista.");
  }
  const clearFields: string[] = [];
  for (const entry of clearRaw) {
    if (typeof entry !== "string" || entry.trim().length === 0) {
      throw new HttpsError(
        "invalid-argument",
        "clearFields deve conter apenas nomes de campos.",
      );
    }
    const field = entry.trim();
    if (clearFields.includes(field)) {
      throw new HttpsError(
        "invalid-argument",
        `Campo ${field} repetido em clearFields.`,
      );
    }
    clearFields.push(field);
  }

  if (Object.keys(patchRaw).length === 0 && clearFields.length === 0) {
    throw new HttpsError(
      "invalid-argument",
      "Nada para atualizar: informe patch ou clearFields.",
    );
  }

  return {
    dogId,
    expectedUpdatedAt: raw.expectedUpdatedAt,
    expectedUpdatedAtProvided: true,
    patch: patchRaw,
    clearFields,
  };
}

function validateFields(patch: JsonMap, clearFields: string[]): void {
  for (const [field, value] of Object.entries(patch)) {
    assertNoForbiddenField(field, "patch");
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
  }

  for (const field of clearFields) {
    assertNoForbiddenField(field, "clearFields");
    if (REQUIRED_IDENTITY_FIELDS.has(field)) {
      throw new HttpsError(
        "invalid-argument",
        `Campo ${field} e obrigatorio na identidade do K9 e nao pode ser limpo.`,
      );
    }
    if (field in patch) {
      throw new HttpsError(
        "invalid-argument",
        `Campo ${field} nao pode estar em patch e clearFields ao mesmo tempo.`,
      );
    }
  }
}

/** Valores de identidade normalizados, prontos para gravacao. */
function buildIdentityValues(patch: JsonMap): JsonMap {
  const values: JsonMap = {};
  for (const [field, value] of Object.entries(patch)) {
    if (field === "birthDate") {
      values.dateOfBirth = parseBirthDate(value);
      continue;
    }
    const documentField = DOCUMENT_FIELD_BY_WIRE_FIELD[field];
    values[documentField] = identityString(field, value);
  }
  return values;
}

export interface PatchK9IdentityResult {
  id: string;
  updatedFields: string[];
  clearedFields: string[];
}

export async function patchK9Identity(
  deps: K9IdentityPatchDeps,
  rawRequest: unknown,
): Promise<PatchK9IdentityResult> {
  const caller = await deps.authorize();
  const parsed = parseRequest(rawRequest);
  validateFields(parsed.patch, parsed.clearFields);
  const identityValues = buildIdentityValues(parsed.patch);

  return deps.runTransaction(async (tx) => {
    const snapshot = await tx.getDog(parsed.dogId);
    if (!snapshot.exists) {
      throw new HttpsError("not-found", "K9 nao encontrado.");
    }
    const dog = snapshot.data() ?? {};

    const archived = archivedReason(dog);
    if (archived) {
      throw new HttpsError(
        "failed-precondition",
        `${archived}: edicao administrativa de identidade nao permitida. Reative o K9 pelo fluxo proprio.`,
      );
    }

    const storedMillis = concurrencyAuthorityMillis(dog);
    const expectedMillis = timestampMillis(parsed.expectedUpdatedAt);
    if (parsed.expectedUpdatedAt === null) {
      if (storedMillis !== null) {
        throw new HttpsError(
          "failed-precondition",
          "Registro do K9 foi alterado por outra sessao. Recarregue antes de editar.",
        );
      }
    } else if (expectedMillis === null) {
      throw new HttpsError("invalid-argument", "expectedUpdatedAt invalido.");
    } else if (storedMillis === null || storedMillis !== expectedMillis) {
      throw new HttpsError(
        "failed-precondition",
        "Registro do K9 foi alterado por outra sessao. Recarregue antes de editar.",
      );
    }

    const documentPatch: JsonMap = {};
    const updatedFields: string[] = [];

    for (const field of Object.keys(parsed.patch)) {
      const documentField = DOCUMENT_FIELD_BY_WIRE_FIELD[field];
      const nextValue = identityValues[documentField];
      documentPatch[documentField] = nextValue;
      updatedFields.push(field);
      if (field === "registrationNumber") {
        documentPatch.matricula = nextValue;
      }
    }

    for (const field of parsed.clearFields) {
      documentPatch[DOCUMENT_FIELD_BY_WIRE_FIELD[field]] = null;
    }

    const nextRegistration = identityValues.registrationNumber;
    if (typeof nextRegistration === "string") {
      const currentRegistration = typeof dog.registrationNumber === "string" ?
        dog.registrationNumber.trim() :
        null;
      if (nextRegistration !== currentRegistration) {
        const owners = await tx.findRegistrationOwners(nextRegistration);
        if (owners.some((ownerId) => ownerId !== parsed.dogId)) {
          throw new HttpsError(
            "already-exists",
            "Ja existe um K9 com esta matricula/RGA.",
          );
        }
      }
    }

    const now = deps.serverTimestamp();
    documentPatch.updated_at = now;
    documentPatch.updatedAt = now;
    documentPatch.audit_trail = deps.arrayUnion(deps.auditEntry("updated", caller));

    tx.patchDog(parsed.dogId, documentPatch);
    tx.writeAuditLog({
      action: "k9_identity_patched",
      entity_type: "dog",
      entity_id: parsed.dogId,
      summary: `Identidade administrativa atualizada: ${
        String(dog.name ?? parsed.dogId)
      }`,
      actor: caller,
      metadata: {
        updated_fields: updatedFields,
        cleared_fields: parsed.clearFields,
      },
      source: "functions",
      performed_at: now,
      createdAt: now,
    });

    return {
      id: parsed.dogId,
      updatedFields,
      clearedFields: parsed.clearFields,
    };
  });
}
