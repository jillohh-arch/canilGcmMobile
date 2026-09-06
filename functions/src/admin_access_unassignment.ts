/**
 * FRONT10.ACCESS-CREDENTIALS — CANONICAL ACCESS PROFILE UNASSIGN WRITER.
 *
 * Remove o perfil de acesso base de um integrante mantendo:
 * 1. Independencia ortogonal da qualificacao de Instrutor (se ativa, permanece ativa);
 * 2. Zero autoridade residual ou sintetizada (sem condutor, sem operador, sem escopo);
 * 3. Identidade de Auth preservada com claims recompostas deterministicamente via composeEffectiveAccessClaims;
 * 4. Integrantes sem conta de Auth sofrem unassign apenas no Firestore sem auto-criacao de conta;
 * 5. Idempotencia segura caso o integrante ja nao possua perfil atribuido;
 * 6. Respeito ao ciclo de vida de pessoal (recusa fail-closed para inativos/arquivados via isCurrentlyActive);
 * 7. Trilha canonica de auditoria (unassign_access_profile) com previous_access_profile_id e target_ra;
 * 8. Compensacao estrita de claims se a gravacao no Firestore falhar apos mutacao no Auth.
 */

import { HttpsError } from "firebase-functions/v2/https";
import {
  composeEffectiveAccessClaims,
  JsonMap,
} from "./access_claims_composition";
import { isCurrentlyActive } from "./admin_human_lifecycle";

export interface UnassignAccessProfileCaller {
  uid: string;
  email: string;
  name: string;
  ra: string;
}

export interface UnassignAccessProfileDeps {
  authorize: (auth: unknown) => Promise<UnassignAccessProfileCaller>;
  getUser: (ra: string) => Promise<{ exists: boolean; data?: JsonMap | null }>;
  getProfile?: (profileId: string) => Promise<{ exists: boolean; data?: JsonMap | null }>;
  lookupAuthUserByUid: (uid: string) => Promise<{ uid: string; customClaims?: JsonMap } | null>;
  lookupAuthUserByEmail: (email: string) => Promise<{ uid: string; customClaims?: JsonMap } | null>;
  setCustomUserClaims: (uid: string, claims: JsonMap) => Promise<void>;
  updateUser: (ra: string, payload: JsonMap) => Promise<void>;
  serverTimestamp: () => unknown;
  deleteField: () => unknown;
  arrayUnion: (value: unknown) => unknown;
  auditEntry: (action: string, caller: UnassignAccessProfileCaller) => JsonMap;
  canonicalAuthEmail: (user: JsonMap, ra: string) => string;
}

export interface UnassignAccessProfileResult {
  ra: string;
  unassigned: boolean;
  previousProfileId: string | null;
  previousProfileName?: string | null;
}

function stringValue(val: unknown): string | undefined {
  if (typeof val === "string" && val.trim().length > 0) return val.trim();
  return undefined;
}

function assertHumanRa(ra: string): void {
  if (!/^\d{4,12}$/.test(ra)) {
    throw new HttpsError("invalid-argument", "RA deve conter apenas numeros.");
  }
}

/**
 * Logica canonica de desatribuicao de perfil de acesso.
 */
export async function unassignAccessProfileLogic(
  data: unknown,
  deps: UnassignAccessProfileDeps,
  authContext?: unknown,
): Promise<UnassignAccessProfileResult> {
  const caller = await deps.authorize(authContext);

  if (!data || typeof data !== "object" || Array.isArray(data)) {
    throw new HttpsError("invalid-argument", "Dados da requisicao invalidos.");
  }

  const rawRa = (data as JsonMap).ra;
  const ra = stringValue(rawRa);
  if (!ra) {
    throw new HttpsError("invalid-argument", "Campo obrigatorio ausente: ra.");
  }
  assertHumanRa(ra);

  const userSnap = await deps.getUser(ra);
  if (!userSnap.exists || !userSnap.data) {
    throw new HttpsError("not-found", "Usuario nao encontrado.");
  }

  const userData = userSnap.data;

  // FRONT10.ACCESS-CREDENTIALS.B / Lifecycle check:
  // Rejeicao fail-closed de alteracao de acesso para Personnel inativo.
  if (!isCurrentlyActive(userData)) {
    throw new HttpsError(
      "failed-precondition",
      "Cadastro inativo nao pode receber ou trocar perfil de acesso. " +
        "Reative o integrante antes de alterar o acesso.",
      { reason: "PERSONNEL_INACTIVE" },
    );
  }

  // Identifica perfil atual atribuido
  const currentProfileId =
    stringValue(userData.access_profile_id) ??
    stringValue(userData.accessProfileId) ??
    null;

  // IDEMPOTENCIA: Se o integrante ja nao possui perfil de acesso atribuido,
  // retorna resultado idempotente sem mutacao e sem duplicar auditoria.
  if (!currentProfileId) {
    return {
      ra,
      unassigned: false,
      previousProfileId: null,
    };
  }

  // Tenta resolver o nome do perfil anterior para auditoria rica se disponivel
  let previousProfileName: string | null =
    stringValue(userData.access_profile) ??
    stringValue(userData.accessProfile) ??
    null;

  if (!previousProfileName && deps.getProfile) {
    try {
      const profSnap = await deps.getProfile(currentProfileId);
      if (profSnap.exists && profSnap.data) {
        previousProfileName = stringValue(profSnap.data.name) ?? null;
      }
    } catch {
      // Falha de leitura de nome de perfil nao bloqueia o unassign
    }
  }

  // Preservacao ortogonal da dimensao de Instrutor
  const isInstructor = userData.is_k9_instructor === true;

  // Busca da conta Auth correspondente (A1/A2 fail-closed lookup)
  const authUid =
    stringValue(userData.auth_uid) ??
    stringValue(userData.authUid) ??
    stringValue(userData.uid);
  const authEmail = deps.canonicalAuthEmail(userData, ra);

  let authUser: { uid: string; customClaims?: JsonMap } | null = null;
  if (authUid) {
    authUser = await deps.lookupAuthUserByUid(authUid);
  }
  if (!authUser && authEmail) {
    authUser = await deps.lookupAuthUserByEmail(authEmail);
  }

  const previousClaims: JsonMap | null = authUser
    ? ({ ...(authUser.customClaims ?? {}) } as JsonMap)
    : null;
  let claimsMutated = false;

  // Se a conta de Auth existe, recompoe claims deterministicamente SEM perfil base
  if (authUser) {
    const nextClaims = composeEffectiveAccessClaims(
      authUser.customClaims ?? {},
      ra,
      {
        profileId: null,
        roleKeys: [],
        accessScope: null,
      },
      isInstructor,
    );

    await deps.setCustomUserClaims(authUser.uid, nextClaims);
    claimsMutated = true;
  }

  // Monta payload de desatribuicao do Firestore
  const unassignPayload: JsonMap = {
    access_profile_id: deps.deleteField(),
    accessProfileId: deps.deleteField(),
    access_profile: deps.deleteField(),
    accessProfile: deps.deleteField(),
    access_scope: deps.deleteField(),
    accessScope: deps.deleteField(),
    access_role: deps.deleteField(),
    admin: deps.deleteField(),
    inventory_manager: deps.deleteField(),
    permissions_version: deps.deleteField(),
    permissionsVersion: deps.deleteField(),
    web_access: deps.deleteField(),
    mobile_access: deps.deleteField(),
    app_access: deps.deleteField(),
    claim_role: deps.deleteField(),
    role: deps.deleteField(),
    claim_refresh_required: authUser !== null,
    claim_updated_at:
      authUser !== null ? deps.serverTimestamp() : deps.deleteField(),
    updated_at: deps.serverTimestamp(),
    updatedAt: deps.serverTimestamp(),
    updated_by: caller.ra,
    audit_trail: deps.arrayUnion({
      ...deps.auditEntry("unassign_access_profile", caller),
      previous_access_profile_id: currentProfileId,
      ...(previousProfileName
        ? { previous_access_profile_name: previousProfileName }
        : {}),
      target_ra: ra,
    }),
  };

  // Se o integrante e instrutor, mantem a qualificacao funcional de instrutor.
  // Caso contrario, expurga flags e roles de instrutor.
  if (isInstructor) {
    unassignPayload.is_k9_instructor = true;
    unassignPayload.training_instructor = true;
    unassignPayload.training_role = "instrutor_k9";
    unassignPayload.roles = ["instrutor_k9"];
  } else {
    unassignPayload.roles = deps.deleteField();
    unassignPayload.is_k9_instructor = deps.deleteField();
    unassignPayload.training_instructor = deps.deleteField();
    unassignPayload.training_role = deps.deleteField();
  }

  // Gravacao canonica no Firestore com compensacao de claims
  try {
    await deps.updateUser(ra, unassignPayload);
  } catch (firestoreError) {
    if (claimsMutated && authUser) {
      try {
        await deps.setCustomUserClaims(authUser.uid, previousClaims ?? {});
      } catch (compensationError) {
        throw new HttpsError(
          "internal",
          "As claims de acesso foram alteradas, a gravacao do cadastro falhou e a " +
            "reversao nao foi garantida. Confira o acesso deste integrante antes " +
            "de nova tentativa.",
          {
            reason: "COMPENSATION_FAILED",
            operation: "adminUnassignAccessProfile",
            stage: "revert_custom_claims",
            target_ra: ra,
          },
        );
      }
    }
    throw firestoreError;
  }

  return {
    ra,
    unassigned: true,
    previousProfileId: currentProfileId,
    ...(previousProfileName ? { previousProfileName } : {}),
  };
}
