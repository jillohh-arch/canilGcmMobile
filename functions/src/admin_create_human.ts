/**
 * adminCreateHuman — cadastro administrativo estrito do Efetivo Humano.
 *
 * Este callable cria SOMENTE o registro de pessoal em `users/{ra}`.
 *
 * Ele NAO substitui o legado adminUpsertHuman e NAO executa nenhuma acao de
 * provisionamento de acesso. Diferente do legado (que acopla pessoal + Firebase
 * Auth + senha provisoria + perfil de acesso + custom claims + escopo +
 * habilitacao de login + papel de treino), este callable e deliberadamente
 * incapaz de:
 *   - criar/alterar conta Firebase Auth;
 *   - gerar senha;
 *   - resolver/gravar perfil de acesso;
 *   - gravar claims/roles/escopo;
 *   - gravar binomio/conducao;
 *   - gravar turno/escala/viatura;
 *   - conceder autoridade de treino/instrutor;
 *   - anexar foto.
 *
 * Regras estruturais (H1/H2 CONTRACT LOCKED):
 *   - required: ra, fullName, callsign;
 *   - opcionais de pessoal: cpf, birthDate, phone, institutionalEmail, rank,
 *     cargo, unit, team, admissionDate, notes;
 *   - chave desconhecida => REJECT;
 *   - campo de outro dominio => REJECT (fail closed);
 *   - null explicito => REJECT (omissao expressa ausencia);
 *   - RA duplicado => REJECT de forma atomica (create-only, sem merge);
 *   - ciclo de vida inicial autoritativo pelo servidor: active=true / "Ativo";
 *   - timestamps e auditoria autoritativos pelo servidor.
 *
 * A logica fica isolada em `createHuman` com dependencias injetadas para
 * permitir teste direto sem emulador e sem I/O. O wiring real do Firestore
 * vive em `index.ts`.
 */

import {HttpsError} from "firebase-functions/v2/https";

type JsonMap = Record<string, unknown>;

/** Compativel estruturalmente com o CallerIdentity canonico do index.ts. */
export interface CreateHumanCaller {
  uid: string;
  email: string;
  ra: string;
  name: string;
}

/**
 * Erro atomico esperado quando o documento ja existe. O wiring real mapeia a
 * falha de `DocumentReference.create()` (codigo Firestore ALREADY_EXISTS /
 * code 6) para este sinal, mantendo semantica create-only sem TOCTOU.
 */
export class DocumentAlreadyExistsError extends Error {}

export interface CreateHumanDeps {
  /** Exige autenticacao + capacidade administrativa humans.create. */
  authorize(): Promise<CreateHumanCaller>;
  /**
   * Gravacao create-only de `users/{ra}`. DEVE falhar (lancar
   * DocumentAlreadyExistsError) se o documento ja existir. Nunca merge/overwrite.
   */
  createUserDoc(ra: string, payload: JsonMap): Promise<void>;
  /** FieldValue.serverTimestamp() no wiring real. */
  serverTimestamp(): unknown;
  /** auditEntry canonico do index.ts. */
  auditEntry(action: string, caller: CreateHumanCaller): JsonMap;
}

/** Campos obrigatorios (wire). */
const REQUIRED_FIELDS = ["ra", "fullName", "callsign"] as const;

/** Campos opcionais de pessoal (wire). */
const OPTIONAL_FIELDS = [
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

const ALLOWED_WIRE_FIELDS = new Set<string>([
  ...REQUIRED_FIELDS,
  ...OPTIONAL_FIELDS,
]);

/**
 * Campo wire -> campo(s) canonico(s) do documento `users/{ra}`, espelhando a
 * representacao ja escrita pelo legado adminUpsertHuman e consumida pelos
 * readers atuais (human-admin-service.ts / use-effective-data.ts).
 *
 * fullName  -> name + nomeCompleto
 * callsign  -> callsign + callSign
 * cpf       -> cpf
 * birthDate -> birth_date (string as-is, sem coercao de Timestamp)
 * phone     -> telefone
 * institutionalEmail -> institutional_email
 * rank      -> rank
 * cargo     -> cargo
 * unit      -> unit
 * team      -> team
 * admissionDate -> admission_date (string as-is)
 * notes     -> notes
 */
const DOCUMENT_FIELDS_BY_WIRE: Record<string, string[]> = {
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
 * Campos explicitamente proibidos, com dominio responsavel, para mensagem de
 * erro precisa. Qualquer outra chave desconhecida tambem e recusada pelo fail
 * closed geral (ALLOWED_WIRE_FIELDS).
 */
const FORBIDDEN_FIELD_DOMAIN: Record<string, string> = {
  // Provisionamento de acesso / Auth
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
  mobile_access: "provisionamento de acesso",
  web_access: "provisionamento de acesso",
  app_access: "provisionamento de acesso",
  inventory_manager: "provisionamento de acesso",
  auth_uid: "conta de autenticacao",
  authUid: "conta de autenticacao",
  uid: "conta de autenticacao",
  email: "conta de autenticacao",
  password: "conta de autenticacao",
  temporaryPassword: "conta de autenticacao",
  temporary_password: "conta de autenticacao",
  // Treino / instrutor
  isK9Instructor: "treino",
  is_k9_instructor: "treino",
  training_instructor: "treino",
  training_role: "treino",
  specialties: "treino/capacitacoes",
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
  // Foto (gate posterior)
  photoUrl: "foto (fluxo pos-cadastro)",
  photoURL: "foto (fluxo pos-cadastro)",
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
  mode: "controle legado (adminUpsertHuman)",
  profile: "controle legado (adminUpsertHuman)",
};

function isPlainObject(value: unknown): value is JsonMap {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

/**
 * Aceita apenas string nao-vazia. Nao coage numero/boolean: payload malformado
 * falha fechado. null e undefined sao recusados com mensagem especifica.
 */
function requireText(field: string, value: unknown): string {
  if (value === null) {
    throw new HttpsError(
      "invalid-argument",
      `Campo ${field} recebeu null. Omita o campo para expressar ausencia.`,
    );
  }
  if (typeof value !== "string") {
    throw new HttpsError("invalid-argument", `Campo ${field} deve ser texto.`);
  }
  const text = value.trim();
  if (text.length === 0) {
    throw new HttpsError(
      "invalid-argument",
      `Campo ${field} nao pode ser vazio.`,
    );
  }
  return text;
}

/**
 * Opcional textual: null e recusado (H1 null=REJECT). Omissao (undefined/chave
 * ausente) e o unico modo valido de expressar ausencia.
 */
function optionalText(field: string, value: unknown): string | null {
  if (value === undefined) return null;
  return requireText(field, value);
}

/** Formato canonico do RA (espelha assertHumanRa do index.ts). */
function assertRa(ra: string): void {
  if (!/^\d{4,12}$/.test(ra)) {
    throw new HttpsError("invalid-argument", "RA deve conter apenas numeros.");
  }
}

interface ParsedCreateRequest {
  ra: string;
  fullName: string;
  callsign: string;
  optionals: JsonMap; // wire field -> string (apenas os fornecidos)
}

function parseRequest(raw: unknown): ParsedCreateRequest {
  if (!isPlainObject(raw)) {
    throw new HttpsError("invalid-argument", "Payload invalido.");
  }

  // Fail closed: nenhuma chave fora do allowlist.
  for (const key of Object.keys(raw)) {
    if (!ALLOWED_WIRE_FIELDS.has(key)) {
      const domain = FORBIDDEN_FIELD_DOMAIN[key];
      if (domain) {
        throw new HttpsError(
          "invalid-argument",
          `Campo ${key} pertence ao dominio ${domain} e nao pode ser enviado no cadastro de pessoal.`,
        );
      }
      throw new HttpsError(
        "invalid-argument",
        `Chave desconhecida no payload: ${key}.`,
      );
    }
  }

  const ra = requireText("ra", raw.ra);
  assertRa(ra);
  const fullName = requireText("fullName", raw.fullName);
  const callsign = requireText("callsign", raw.callsign);

  const optionals: JsonMap = {};
  for (const field of OPTIONAL_FIELDS) {
    if (!(field in raw)) continue;
    const parsed = optionalText(field, raw[field]);
    if (parsed !== null) optionals[field] = parsed;
  }

  return {ra, fullName, callsign, optionals};
}

/** Documento canonico de pessoal, com ciclo de vida/metadados do servidor. */
function buildPersonnelDocument(
  parsed: ParsedCreateRequest,
  deps: CreateHumanDeps,
  caller: CreateHumanCaller,
): JsonMap {
  const now = deps.serverTimestamp();
  const doc: JsonMap = {
    ra: parsed.ra,
  };

  // fullName / callsign (obrigatorios) via mapeamento canonico + espelhos.
  for (const documentField of DOCUMENT_FIELDS_BY_WIRE.fullName) {
    doc[documentField] = parsed.fullName;
  }
  for (const documentField of DOCUMENT_FIELDS_BY_WIRE.callsign) {
    doc[documentField] = parsed.callsign;
  }

  // Opcionais fornecidos -> campo(s) canonico(s).
  for (const [field, value] of Object.entries(parsed.optionals)) {
    for (const documentField of DOCUMENT_FIELDS_BY_WIRE[field]) {
      doc[documentField] = value;
    }
  }

  // Ciclo de vida autoritativo do servidor (cliente nunca controla).
  doc.active = true;
  doc.status = "Ativo";

  // Timestamps espelhados: um unico instante logico.
  doc.created_at = now;
  doc.createdAt = now;
  doc.updated_at = now;
  doc.updatedAt = now;

  // Auditoria server-side no documento inicial.
  doc.audit_trail = [deps.auditEntry("created", caller)];

  return doc;
}

export interface CreateHumanResult {
  ra: string;
  created: true;
}

export async function createHuman(
  deps: CreateHumanDeps,
  rawRequest: unknown,
): Promise<CreateHumanResult> {
  // Autorizacao antes de qualquer parsing/escrita.
  const caller = await deps.authorize();
  const parsed = parseRequest(rawRequest);

  const now = deps.serverTimestamp();
  const document = buildPersonnelDocument(parsed, deps, caller);
  // Um unico sentinel de servidor nos quatro espelhos: mesmo instante logico
  // no commit. A resposta NAO devolve este valor (sentinel nao serializa).
  document.updated_at = now;
  document.updatedAt = now;
  document.created_at = now;
  document.createdAt = now;

  try {
    await deps.createUserDoc(parsed.ra, document);
  } catch (error) {
    if (error instanceof DocumentAlreadyExistsError) {
      throw new HttpsError(
        "already-exists",
        "Ja existe um usuario com este RA.",
      );
    }
    throw error;
  }

  // A resposta nao carrega timestamp: o callable nao conhece o commit time
  // materializado (serverTimestamp() so resolve no commit). Consumidores que
  // precisem do instante autoritativo leem users/{ra} apos a criacao.
  return {
    ra: parsed.ra,
    created: true,
  };
}
