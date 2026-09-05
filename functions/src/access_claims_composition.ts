/**
 * FRONT10.ACCESS-CREDENTIALS.D — COMPOSICAO DETERMINISTICA DE CLAIMS DE ACESSO.
 *
 * Politica Congelada (F10.ACCESS-CREDENTIALS.I2):
 * - ACCESS PROFILE: Autoridade de autorizacao base (perfil, escopo, permissoes, role singular).
 * - INSTRUCTOR ROLE: Qualificacao funcional ortogonal independente (is_k9_instructor, flags de treino).
 * - EFFECTIVE CLAIMS: Composicao deterministica de [Base Profile + Instructor Qualification].
 *
 * Invariantes permanentes:
 * 1. PROFILE CHANGE != INSTRUCTOR REVOCATION (mudar perfil nao cassa instrutor).
 * 2. INSTRUCTOR TOGGLE != ACCESS PROFILE REPLACEMENT (ligar/desligar instrutor nao apaga perfil).
 * 3. Preserve todas as claims nao pertencentes ao dominio do Front 10.
 */

export type JsonMap = Record<string, unknown>;

export interface BaseProfileState {
  profileId: string | null;
  roleKeys?: string[];
  accessScope?: "global" | "own_records";
}

export const MANAGED_ACCESS_ROLES = new Set<string>([
  "adestrador",
  "adestrador_k9",
  "admin",
  "admin_master",
  "administrador",
  "almoxarifado",
  "comando",
  "condutor",
  "coordenador",
  "estoque",
  "gestor",
  "handler",
  "inspetor",
  "instrutor",
  "instrutor_k9",
  "inventory_manager",
  "mobile_user",
  "operacional",
  "operador",
  "operador_k9",
  "guarda_k9",
  "subinspetor",
  "subinspetor_inspetor",
  "supervisor",
  "supervisor_operacional",
]);

function normalizedKey(value: unknown): string {
  return typeof value === "string"
    ? value.trim().toLowerCase().replace(/[\s-]+/g, "_")
    : "";
}

/**
 * Composicao deterministica de custom claims do Auth.
 */
export function composeEffectiveAccessClaims(
  existingClaims: JsonMap,
  ra: string,
  baseProfile: BaseProfileState,
  isInstructor: boolean,
): JsonMap {
  const profileKey = baseProfile.profileId ? normalizedKey(baseProfile.profileId) : "";
  const profileRoleKeys = (baseProfile.roleKeys ?? []).map(normalizedKey).filter(Boolean);
  const profileRoles = new Set<string>([
    ...profileRoleKeys,
    ...(profileKey ? [profileKey] : []),
  ]);

  const isAdminProfile =
    profileRoles.has("admin") ||
    profileRoles.has("administrador") ||
    profileRoles.has("admin_master");

  const isInventoryProfile =
    profileRoles.has("inventory_manager") ||
    profileRoles.has("almoxarifado") ||
    profileRoles.has("estoque");

  const isManagerProfile =
    profileRoles.has("gestor") ||
    profileRoles.has("subinspetor") ||
    profileRoles.has("inspetor") ||
    profileRoles.has("subinspetor_inspetor");

  const isHandlerProfile =
    profileRoles.has("condutor") ||
    profileRoles.has("handler") ||
    profileRoles.has("mobile_user") ||
    profileRoles.has("operacional") ||
    profileRoles.has("operador") ||
    profileRoles.has("operador_k9") ||
    profileRoles.has("guarda_k9");

  const isInstructorFromProfile =
    profileRoles.has("instrutor_k9") ||
    profileRoles.has("instrutor") ||
    profileRoles.has("adestrador") ||
    profileRoles.has("adestrador_k9");

  // Qualificacao de instrutor efetiva: funcional direta OU perfil legado de instrutor
  const effectiveInstructor = isInstructor || isInstructorFromProfile;

  // Preserva roles nao-gerenciadas existentes
  const preservedRoles = Array.isArray(existingClaims.roles)
    ? (existingClaims.roles as unknown[])
        .map((r) => normalizedKey(String(r)))
        .filter((r) => r.length > 0 && !MANAGED_ACCESS_ROLES.has(r))
    : [];

  const roles = new Set<string>([...preservedRoles, ...profileRoles]);

  if (isAdminProfile) roles.add("admin");
  if (isInventoryProfile) roles.add("inventory_manager");
  if (isManagerProfile) roles.add("gestor");
  if (isHandlerProfile) roles.add("condutor");

  if (effectiveInstructor) {
    roles.add("instrutor_k9");
    roles.add("condutor");
  } else {
    // Se nao e instrutor, remove tokens funcionais de instrutor se nao fizerem parte do perfil base
    if (!isInstructorFromProfile) {
      roles.delete("instrutor_k9");
      roles.delete("instrutor");
      roles.delete("adestrador");
      roles.delete("adestrador_k9");
    }
  }

  // Role singular base: o perfil de acesso e o dono da autoridade base.
  // Instrutor nao sobrepoe nem degrada a role de admin, gestor ou almoxarifado.
  const primaryRole = isAdminProfile
    ? "admin"
    : isManagerProfile
      ? "gestor"
      : isInventoryProfile
        ? "inventory_manager"
        : (profileKey === "instrutor_k9" || isInstructorFromProfile)
          ? "instrutor_k9"
          : profileKey
            ? "condutor"
            : (effectiveInstructor ? "instrutor_k9" : "condutor");

  const mobileAccess = isAdminProfile || effectiveInstructor || isHandlerProfile;
  const accessScope = baseProfile.accessScope ?? "global";
  const appAccess = mobileAccess ? ["web", "mobile"] : ["web"];

  const claims: JsonMap = {
    ...existingClaims,
    ra,
    access_profile_id: profileKey || null,
    access_scope: accessScope,
    admin: isAdminProfile,
    app_access: appAccess,
    mobile_access: mobileAccess,
    role: primaryRole,
    roles: Array.from(roles).sort(),
    web_access: true,
  };

  if (effectiveInstructor) {
    claims.instrutor_k9 = true;
    claims.training_role = "instrutor_k9";
    claims.training_instructor = true;
  } else {
    delete claims.instrutor_k9;
    delete claims.training_role;
    delete claims.training_instructor;
  }

  if (isInventoryProfile) {
    claims.inventory_manager = true;
  } else {
    delete claims.inventory_manager;
  }

  return claims;
}
