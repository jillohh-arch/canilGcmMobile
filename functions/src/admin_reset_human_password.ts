import * as crypto from "crypto";
import {HttpsError} from "firebase-functions/v2/https";

export type JsonMap = Record<string, unknown>;

export interface ResetPasswordCaller {
  uid: string;
  ra: string;
}

export interface ResetPasswordAuthUser {
  disabled: boolean;
  email?: string;
  uid: string;
}

export interface ResetPasswordPersonnel {
  active?: boolean;
  authUid?: string;
  auth_uid?: string;
  deleted_at?: unknown;
  email?: string;
  status?: string;
  uid?: string;
}

export interface ResetPasswordDeps {
  authorize: (auth: unknown) => Promise<ResetPasswordCaller>;
  generateTemporaryPassword: () => string;
  getPersonnel: (ra: string) => Promise<{exists: boolean; data?: ResetPasswordPersonnel}>;
  lookupAuthByEmail: (email: string) => Promise<ResetPasswordAuthUser | null>;
  lookupAuthByUid: (uid: string) => Promise<ResetPasswordAuthUser | null>;
  serverTimestamp: () => unknown;
  updatePassword: (uid: string, password: string) => Promise<void>;
  updatePersonnelAudit: (ra: string, payload: JsonMap) => Promise<void>;
}

export interface ResetPasswordRequest {
  ra: string;
}

export interface ResetPasswordResult {
  temporary_password: string;
}

/**
 * Gera senha temporaria forte: 8 bytes aleatorios em base64url + "aA1!" para garantir
 * maiuscula, minuscula, numero e caractere especial exigidos pelo Firebase Auth.
 */
export function defaultGenerateTemporaryPassword(): string {
  return `${crypto.randomBytes(8).toString("base64url")}aA1!`;
}

function stringValue(val: unknown): string | undefined {
  if (typeof val === "string" && val.trim().length > 0) return val.trim();
  return undefined;
}

/**
 * Handler puro de reset administrativo de senha.
 *
 * Principios de seguranca:
 * 1. Nao cria conta Auth: integrante sem credencial continua sem credencial.
 * 2. Nao ativa Personnel nem Auth: conta disabled permanece disabled.
 * 3. Nao muta Access Profile, roles ou claims.
 * 4. Senha temporaria NUNCA e persistida no Firestore, NUNCA e colocada em log e
 *    NUNCA e incluida em payload de auditoria.
 * 5. Auditoria canonica no Firestore registra quem, quando e para qual RA/UID.
 * 6. Atualiza ambos os espelhos de timestamp (`updated_at` e `updatedAt`).
 */
export async function resetHumanPasswordLogic(
  request: {auth: unknown; data: unknown},
  deps: ResetPasswordDeps,
): Promise<ResetPasswordResult> {
  const caller = await deps.authorize(request.auth);

  if (typeof request.data !== "object" || request.data === null) {
    throw new HttpsError("invalid-argument", "Payload invalido.");
  }

  const rawRa = (request.data as Record<string, unknown>).ra;
  if (typeof rawRa !== "string" || !/^\d{4,7}$/.test(rawRa.trim())) {
    throw new HttpsError("invalid-argument", "RA de integrante invalido.");
  }
  const ra = rawRa.trim();

  const personnel = await deps.getPersonnel(ra);
  if (!personnel.exists || !personnel.data) {
    throw new HttpsError("not-found", "Integrante nao encontrado.");
  }

  const pData = personnel.data;
  const uidCandidate =
    stringValue(pData.auth_uid) ??
    stringValue(pData.authUid) ??
    stringValue(pData.uid);
  const emailCandidate =
    stringValue(pData.email) ?? `${ra.toLowerCase()}@gcm.com.br`;

  let authUser: ResetPasswordAuthUser | null = null;
  if (uidCandidate) {
    authUser = await deps.lookupAuthByUid(uidCandidate);
  }
  if (!authUser && emailCandidate) {
    authUser = await deps.lookupAuthByEmail(emailCandidate);
  }

  if (!authUser) {
    throw new HttpsError(
      "not-found",
      "Conta de acesso nao localizada para este integrante.",
      {reason: "AUTH_IDENTITY_NOT_FOUND"},
    );
  }

  const temporaryPassword = deps.generateTemporaryPassword();
  await deps.updatePassword(authUser.uid, temporaryPassword);

  const now = deps.serverTimestamp();
  const auditEntry = {
    action: "password_reset",
    at: now,
    by: caller.uid,
    by_ra: caller.ra,
    target_ra: ra,
    target_uid: authUser.uid,
  };

  await deps.updatePersonnelAudit(ra, {
    audit_trail: auditEntry,
    updated_at: now,
    updatedAt: now,
    updated_by: caller.ra,
  });

  return {
    temporary_password: temporaryPassword,
  };
}
