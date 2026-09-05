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
  accessScope?: "global" | "own_records" | null;
}

export const MANAGED_ACCESS_ROLES = new Set<string>([
  "adestrador",
  "adestrador_k9",
  "admin",
  "admin_master",
  "administrador",
  "almoxarifado",
  "comando",
  "coordenador",
  "condutor",
  "estoque",
  "gestor",
  "gestor_canil",
  "guarda_k9",
  "handler",
  "inspetor",
  "instrutor",
  "instrutor_k9",
  "inventory_manager",
  "mobile_user",
  "operacional",
  "operador",
  "operador_k9",
  "operador_mobile",
  "subinspetor",
  "subinspetor_inspetor",
  "supervisor",
  "supervisor_operacional",
  "ti",
]);

function normalizedKey(value: unknown): string {
  return typeof value === "string"
    ? value.trim().toLowerCase().replace(/[\s-]+/g, "_")
    : "";
}

/**
 * Composicao deterministica de custom claims do Auth.
 *
 * Invariantes de seguranca (F10.ACCESS-CREDENTIALS.I2.R1):
 * - INSTRUCTOR TOGGLE != ACCESS PROFILE ASSIGNMENT
 * - INSTRUCTOR TOGGLE != IMPLICIT OPERATOR ACCESS
 * - Perfil base ausente => zero autorizacao base fabricada (sem profile_id, sem escopo, sem singular role, sem condutor/operador).
 * - Claims proprietarias de acesso antigas sao expurgadas para nao virarem autoridade acidental.
 */
export function composeEffectiveAccessClaims(
  existingClaims: JsonMap,
  ra: string,
  baseProfile: BaseProfileState,
  isInstructor: boolean,
): JsonMap {
  const hasValidBaseProfile = Boolean(baseProfile.profileId && baseProfile.accessScope);
  const profileKey = hasValidBaseProfile ? normalizedKey(baseProfile.profileId!) : "";
  const profileRoleKeys = hasValidBaseProfile
    ? (baseProfile.roleKeys ?? []).map(normalizedKey).filter(Boolean)
    : [];
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

  // Preserva roles nao-gerenciadas existentes (ignora quaisquer roles gerenciadas antigas)
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
    // CT-I2-03: Instrutor NÃO adiciona condutor nem sintetiza autorizacao de operador.
  } else {
    // Se nao e instrutor, remove tokens funcionais de instrutor se nao fizerem parte do perfil base
    if (!isInstructorFromProfile) {
      roles.delete("instrutor_k9");
      roles.delete("instrutor");
      roles.delete("adestrador");
      roles.delete("adestrador_k9");
    }
  }

  // Role singular base:
  // Se ha perfil base valido, segue o papel singular do perfil.
  // Instrutor nao sobrepoe nem degrada a role de admin, gestor, almoxarifado ou operador.
  // Se NAO ha perfil base valido, nenhuma role singular e fabricada.
  let primaryRole: string | null = null;
  if (hasValidBaseProfile) {
    primaryRole = isAdminProfile
      ? "admin"
      : isManagerProfile
        ? "gestor"
        : isInventoryProfile
          ? "inventory_manager"
          : (profileKey === "instrutor_k9" || isInstructorFromProfile)
            ? "instrutor_k9"
            : (isHandlerProfile || profileKey === "operador_k9")
              ? "condutor"
              : profileKey;
  }

  // Limpa chaves proprietarias de acesso do Front 10 para nao herdar autorizacao obsoleta de claims antigas
  const cleanedExistingClaims: JsonMap = { ...existingClaims };
  delete cleanedExistingClaims.access_profile_id;
  delete cleanedExistingClaims.access_scope;
  delete cleanedExistingClaims.admin;
  delete cleanedExistingClaims.inventory_manager;
  delete cleanedExistingClaims.instrutor_k9;
  delete cleanedExistingClaims.training_role;
  delete cleanedExistingClaims.training_instructor;
  delete cleanedExistingClaims.app_access;
  delete cleanedExistingClaims.mobile_access;
  delete cleanedExistingClaims.web_access;
  delete cleanedExistingClaims.role;
  delete cleanedExistingClaims.claim_role;
  delete cleanedExistingClaims.roles;

  const mobileAccess = hasValidBaseProfile && (isAdminProfile || isHandlerProfile);
  const appAccess = mobileAccess ? ["web", "mobile"] : (hasValidBaseProfile ? ["web"] : []);

  const claims: JsonMap = {
    ...cleanedExistingClaims,
    ra,
    access_profile_id: hasValidBaseProfile ? profileKey : null,
    access_scope: hasValidBaseProfile ? (baseProfile.accessScope ?? "global") : null,
    admin: isAdminProfile,
    app_access: appAccess,
    mobile_access: mobileAccess,
    role: primaryRole,
    roles: Array.from(roles).sort(),
    web_access: hasValidBaseProfile,
  };

  if (effectiveInstructor) {
    claims.instrutor_k9 = true;
    claims.training_role = "instrutor_k9";
    claims.training_instructor = true;
  }

  if (isInventoryProfile) {
    claims.inventory_manager = true;
  }

  return claims;
}
