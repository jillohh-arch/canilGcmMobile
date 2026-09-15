/**
 * adminPatchHumanPhoto — atualizacao administrativa estrita de FOTO de pessoal humano.
 *
 * Este callable altera SOMENTE a URL da foto de perfil em `users/{ra}`.
 *
 * Ele e deliberadamente incapaz de:
 *   - criar/alterar/desabilitar conta Firebase Auth;
 *   - alterar credenciais ou perfil de acesso;
 *   - alterar campos cadastrais de pessoal (fullName, callsign, cpf, etc.);
 *   - gravar turno/escala ou binomio;
 *   - alterar ciclo de vida (active/status).
 *
 * Regras estruturais:
 *   - `ra` e alvo imutavel obrigatorio (formato ^\d{4,12}$);
 *   - `photoUrl` e string de URL valida e segura (http/https/gs);
 *   - payload aceita SOMENTE `ra` e `photoUrl` (fail closed);
 *   - campos de outros dominios => REJECT;
 *   - integrante inexistente => NOT_FOUND;
 *   - integrante inativo/arquivado => FAILED_PRECONDITION;
 *   - atualizacao grava os espelhos de foto canonicos/legados (photoUrl, photoURL, profileImageUrl, image_url),
 *     atualiza updated_at/updatedAt e anexa entrada em audit_trail.
 */

import {HttpsError} from "firebase-functions/v2/https";

type JsonMap = Record<string, unknown>;

export interface PatchHumanPhotoCaller {
  uid: string;
  email: string;
  ra: string;
  name: string;
}

export interface HumanPhotoSnapshot {
  exists: boolean;
  data: JsonMap | null;
}

export interface HumanPhotoTransaction {
  getUser(ra: string): Promise<HumanPhotoSnapshot>;
  patchUser(ra: string, patch: JsonMap): void;
}

export interface PatchHumanPhotoDeps {
  authorize(): Promise<PatchHumanPhotoCaller>;
  runTransaction<T>(handler: (tx: HumanPhotoTransaction) => Promise<T>): Promise<T>;
  serverTimestamp(): unknown;
  auditEntry(action: string, caller: PatchHumanPhotoCaller): JsonMap;
  arrayUnion(value: unknown): unknown;
}

export interface PatchHumanPhotoResult {
  ra: string;
  photoUrl: string;
  updated: true;
}

const ALLOWED_TOP_LEVEL_KEYS = new Set<string>(["ra", "photoUrl"]);

const FORBIDDEN_FIELD_DOMAIN: Record<string, string> = {
  fullName: "pessoal (adminPatchHumanPersonnel)",
  callsign: "pessoal (adminPatchHumanPersonnel)",
  cpf: "pessoal (adminPatchHumanPersonnel)",
  birthDate: "pessoal (adminPatchHumanPersonnel)",
  phone: "pessoal (adminPatchHumanPersonnel)",
  institutionalEmail: "pessoal (adminPatchHumanPersonnel)",
  rank: "pessoal (adminPatchHumanPersonnel)",
  cargo: "pessoal (adminPatchHumanPersonnel)",
  unit: "pessoal (adminPatchHumanPersonnel)",
  team: "pessoal (adminPatchHumanPersonnel)",
  admissionDate: "pessoal (adminPatchHumanPersonnel)",
  notes: "pessoal (adminPatchHumanPersonnel)",
  accessProfile: "provisionamento de acesso",
  accessProfileId: "provisionamento de acesso",
  accessLevel: "provisionamento de acesso",
  roles: "provisionamento de acesso",
  password: "conta de autenticacao",
  temporaryPassword: "conta de autenticacao",
  active: "ciclo de vida",
  status: "ciclo de vida",
  shiftGroupId: "turno/escala",
  binomialId: "binomio/conducao",
};

function isPlainObject(value: unknown): value is JsonMap {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

function assertRa(ra: string): void {
  if (!/^\d{4,12}$/.test(ra)) {
    throw new HttpsError("invalid-argument", "RA deve conter apenas numeros.");
  }
}

function parseTargetRa(raw: JsonMap): string {
  const value = raw.ra;
  if (value === null || value === undefined) {
    throw new HttpsError("invalid-argument", "Campo obrigatorio ausente: ra.");
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

function parsePhotoUrl(raw: JsonMap): string {
  const value = raw.photoUrl;
  if (value === null || value === undefined) {
    throw new HttpsError("invalid-argument", "Campo obrigatorio ausente: photoUrl.");
  }
  if (typeof value !== "string") {
    throw new HttpsError("invalid-argument", "Campo photoUrl deve ser texto.");
  }
  const photoUrl = value.trim();
  if (photoUrl.length === 0) {
    throw new HttpsError("invalid-argument", "Campo photoUrl nao pode ser vazio.");
  }
  if (photoUrl.length > 2048) {
    throw new HttpsError("invalid-argument", "URL da foto excede o tamanho maximo permitido.");
  }
  try {
    const parsed = new URL(photoUrl);
    if (parsed.protocol !== "https:" && parsed.protocol !== "http:" && parsed.protocol !== "gs:") {
      throw new Error("Invalid protocol");
    }
  } catch {
    throw new HttpsError("invalid-argument", "photoUrl deve ser uma URL valida (http, https ou gs).");
  }
  return photoUrl;
}

interface ParsedPhotoRequest {
  ra: string;
  photoUrl: string;
}

function parseRequest(rawRequest: unknown): ParsedPhotoRequest {
  if (!isPlainObject(rawRequest)) {
    throw new HttpsError("invalid-argument", "Payload invalido.");
  }

  for (const key of Object.keys(rawRequest)) {
    if (!ALLOWED_TOP_LEVEL_KEYS.has(key)) {
      const domain = FORBIDDEN_FIELD_DOMAIN[key];
      if (domain) {
        throw new HttpsError(
          "invalid-argument",
          `Campo ${key} pertence ao dominio ${domain} e nao pode ser enviado na atualizacao de foto.`,
        );
      }
      throw new HttpsError("invalid-argument", `Chave desconhecida no payload: ${key}.`);
    }
  }

  const ra = parseTargetRa(rawRequest);
  const photoUrl = parsePhotoUrl(rawRequest);

  return {ra, photoUrl};
}

export async function patchHumanPhoto(
  deps: PatchHumanPhotoDeps,
  rawRequest: unknown,
): Promise<PatchHumanPhotoResult> {
  const caller = await deps.authorize();
  const {ra, photoUrl} = parseRequest(rawRequest);

  return deps.runTransaction(async (tx) => {
    const snapshot = await tx.getUser(ra);
    if (!snapshot.exists || snapshot.data === null) {
      throw new HttpsError("not-found", "Integrante nao encontrado.");
    }
    const user = snapshot.data;
    if (
      user.active === false ||
      user.status === "archived" ||
      user.deleted_at != null ||
      user.archived_at != null
    ) {
      throw new HttpsError(
        "failed-precondition",
        "Integrante arquivado nao pode ter a foto alterada.",
      );
    }

    const now = deps.serverTimestamp();
    const documentPatch: JsonMap = {
      photoUrl,
      photoURL: photoUrl,
      profileImageUrl: photoUrl,
      image_url: photoUrl,
      updated_at: now,
      updatedAt: now,
      audit_trail: deps.arrayUnion(deps.auditEntry("photo_updated", caller)),
    };

    tx.patchUser(ra, documentPatch);

    return {
      ra,
      photoUrl,
      updated: true as const,
    };
  });
}
