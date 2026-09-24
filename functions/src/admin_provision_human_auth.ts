import * as crypto from "crypto";
import {HttpsError} from "firebase-functions/v2/https";
import {isCurrentlyActive} from "./admin_human_lifecycle";

export type JsonMap = Record<string, unknown>;

export interface ProvisionAuthCaller {
  uid: string;
  ra: string;
}

export interface ProvisionAuthUser {
  disabled: boolean;
  displayName?: string;
  email?: string;
  uid: string;
}

export interface ProvisionAuthPersonnel {
  active?: boolean;
  archived_at?: unknown;
  authUid?: string;
  auth_uid?: string;
  callsign?: string;
  deleted_at?: unknown;
  email?: string;
  name?: string;
  status?: string;
  uid?: string;
}

export interface CreateAuthUserInput {
  disabled: boolean;
  displayName?: string;
  email: string;
  password: string;
}

export interface ProvisionHumanAuthDeps {
  authorize: (auth: unknown) => Promise<ProvisionAuthCaller>;
  createAuthUser: (input: CreateAuthUserInput) => Promise<ProvisionAuthUser>;
  deleteAuthUser?: (uid: string) => Promise<void>;
  generateInitialPassword: () => string;
  getPersonnel: (ra: string) => Promise<{exists: boolean; data?: ProvisionAuthPersonnel}>;
  lookupAuthByEmail: (email: string) => Promise<ProvisionAuthUser | null>;
  lookupAuthByUid: (uid: string) => Promise<ProvisionAuthUser | null>;
  lookupPersonnelByAuthUid?: (uid: string) => Promise<string | null>;
  serverTimestamp: () => unknown;
  updateAuthUser: (uid: string, patch: {disabled?: boolean}) => Promise<void>;
  updatePersonnelAudit: (ra: string, payload: JsonMap) => Promise<void>;
}

export interface ProvisionHumanAuthRequest {
  ra: string;
}

export interface ProvisionHumanAuthResult {
  auth_uid: string;
  created: boolean;
  email: string;
  initial_password?: string;
  ra: string;
}

/**
 * Gera senha inicial criptograficamente forte:
 * 12 bytes aleatorios em base64url + "Aa1!" para satisfazer
 * requisitos de maiuscula, minuscula, numero e caractere especial do Firebase Auth.
 */
export function defaultGenerateInitialPassword(): string {
  const prefix = crypto.randomBytes(12).toString("base64url");
  return `${prefix}Aa1!`;
}

function stringValue(val: unknown): string | undefined {
  if (typeof val === "string" && val.trim().length > 0) return val.trim();
  return undefined;
}

/**
 * Handler puro de provisionamento dedicado de autenticacao para integrante (Personnel).
 *
 * Principios de seguranca e invariantes:
 * 1. Nao altera `adminCreateHuman` nem o cadastro pessoal: users/{ra} ja deve existir.
 * 2. Nao altera `adminAssignAccessProfile`: perfil continua sendo atribuido separadamente.
 * 3. Nao altera `adminResetHumanPassword`: reset continua exigindo conta preexistente.
 * 4. Valida autoridade administrativa canonica (access.edit ou humans.edit).
 * 5. Rejeita integrantes inativos/arquivados fail-closed via `isCurrentlyActive`.
 * 6. Idempotencia: se a conta Auth ja existir e for consistente com este RA, nao recria
 *    e NUNCA revela senha.
 * 7. Conflito de identidade: detecta divergencia de e-mail ou UID entre Auth e Firestore e falha fechado.
 * 8. Ciclo de vida seguro: cria conta inicialmente com `disabled: true`, vincula UID e auditoria no
 *    Firestore `users/{ra}`, e somente entao habilita com `disabled: false`.
 * 9. Senha inicial NUNCA e persistida no Firestore, NUNCA e colocada em logs de aplicacao nem em auditoria.
 * 10. Senha inicial e retornada SOMENTE na resposta da criacao efetiva (`created: true`).
 */
export async function provisionHumanAuthLogic(
  request: {auth: unknown; data: unknown},
  deps: ProvisionHumanAuthDeps,
): Promise<ProvisionHumanAuthResult> {
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
    throw new HttpsError("not-found", "Integrante nao encontrado.", {
      reason: "PERSONNEL_NOT_FOUND",
    });
  }

  const pData = personnel.data;
  if (!isCurrentlyActive(pData as JsonMap)) {
    throw new HttpsError(
      "failed-precondition",
      "Cadastro inativo nao pode receber provisionamento de autenticacao.",
      {reason: "PERSONNEL_INACTIVE"},
    );
  }

  const canonicalEmail = `${ra.toLowerCase()}@gcm.com.br`;
  const existingUid =
    stringValue(pData.auth_uid) ??
    stringValue(pData.authUid) ??
    stringValue(pData.uid) ??
    null;

  let existingAuthUser: ProvisionAuthUser | null = null;
  if (existingUid) {
    existingAuthUser = await deps.lookupAuthByUid(existingUid);
  }
  if (!existingAuthUser) {
    existingAuthUser = await deps.lookupAuthByEmail(canonicalEmail);
  }

  if (existingAuthUser) {
    // ── Validacao de Consistencia e Conflito de Identidade ───────────
    if (
      existingAuthUser.email &&
      existingAuthUser.email.trim().toLowerCase() !== canonicalEmail
    ) {
      throw new HttpsError(
        "already-exists",
        "Conflito de identidade: a conta vinculada possui e-mail divergente do RA.",
        {reason: "IDENTITY_CONFLICT"},
      );
    }

    if (existingUid && existingUid !== existingAuthUser.uid) {
      throw new HttpsError(
        "already-exists",
        "Conflito de identidade: o UID gravado no cadastro difere da conta vinculada ao e-mail institucional.",
        {reason: "IDENTITY_CONFLICT"},
      );
    }

    if (!existingUid && deps.lookupPersonnelByAuthUid) {
      const owningRa = await deps.lookupPersonnelByAuthUid(existingAuthUser.uid);
      if (owningRa && owningRa !== ra) {
        throw new HttpsError(
          "already-exists",
          "Conflito de identidade: o e-mail institucional ja pertence a outro usuario cadastrado.",
          {reason: "IDENTITY_CONFLICT"},
        );
      }
    }

    // Se o documento Firestore ainda nao possuia auth_uid, vinculamos agora de forma consistente
    if (!existingUid) {
      const now = deps.serverTimestamp();
      const auditEntry = {
        action: "link_existing_auth",
        at: now,
        by: caller.uid,
        by_ra: caller.ra,
        target_ra: ra,
        target_uid: existingAuthUser.uid,
      };

      await deps.updatePersonnelAudit(ra, {
        audit_trail: auditEntry,
        auth_provisioned_at: now,
        auth_provisioned_by: caller.ra,
        auth_uid: existingAuthUser.uid,
        email: canonicalEmail,
        updated_at: now,
        updatedAt: now,
        updated_by: caller.ra,
      });
    }

    // Se a conta estava desabilitada (ex: aborto anterior), garante reabilitacao
    if (existingAuthUser.disabled) {
      await deps.updateAuthUser(existingAuthUser.uid, {disabled: false});
    }

    // Idempotencia consistente: NUNCA gera nem revela senha
    return {
      auth_uid: existingAuthUser.uid,
      created: false,
      email: canonicalEmail,
      ra,
    };
  }

  // ── Criacao Efetiva com Ciclo de Vida Seguro (disabled -> firestore -> enabled) ──
  const initialPassword = deps.generateInitialPassword();
  const displayName = stringValue(pData.callsign) ?? stringValue(pData.name) ?? ra;

  const createdUser = await deps.createAuthUser({
    disabled: true,
    displayName,
    email: canonicalEmail,
    password: initialPassword,
  });

  const now = deps.serverTimestamp();
  const auditEntry = {
    action: "provision_human_auth",
    at: now,
    by: caller.uid,
    by_ra: caller.ra,
    target_ra: ra,
    target_uid: createdUser.uid,
  };

  try {
    await deps.updatePersonnelAudit(ra, {
      audit_trail: auditEntry,
      auth_provisioned_at: now,
      auth_provisioned_by: caller.ra,
      auth_uid: createdUser.uid,
      email: canonicalEmail,
      updated_at: now,
      updatedAt: now,
      updated_by: caller.ra,
    });
  } catch (firestoreError) {
    if (deps.deleteAuthUser) {
      try {
        await deps.deleteAuthUser(createdUser.uid);
      } catch {
        // Falha no delete compensatorio: a conta permanece disabled: true (segura contra uso orfao)
      }
    }
    throw new HttpsError(
      "internal",
      "Falha ao vincular autenticacao ao cadastro de pessoal. A conta criada permanece desativada.",
      {reason: "AUTH_PROVISION_PERSISTENCE_FAILED"},
    );
  }

  try {
    await deps.updateAuthUser(createdUser.uid, {disabled: false});
  } catch (activationError) {
    throw new HttpsError(
      "internal",
      "Autenticacao vinculada ao cadastro, mas falha ao ativar conta no Auth.",
      {
        reason: "AUTH_ACTIVATION_FAILED",
        target_uid: createdUser.uid,
      },
    );
  }

  // Senha inicial retornada SOMENTE no sucesso da criacao efetiva
  return {
    auth_uid: createdUser.uid,
    created: true,
    email: canonicalEmail,
    initial_password: initialPassword,
    ra,
  };
}
