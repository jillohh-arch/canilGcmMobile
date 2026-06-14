import * as crypto from "crypto";
import * as admin from "firebase-admin";
import {logger} from "firebase-functions";
import {onDocumentCreated, onDocumentUpdated} from "firebase-functions/v2/firestore";
import {
  CallableRequest,
  HttpsError,
  onCall,
  onRequest,
} from "firebase-functions/v2/https";

admin.initializeApp();

const db = admin.firestore();
const region = "southamerica-east1";

type JsonMap = Record<string, unknown>;

const ACTION_REQUIRED_NOTIFICATION_TYPES = new Set([
  "vehicle_crew_invitation",
  "signature_requested",
  "training_promotion_requested",
]);

interface ExpectedMedia {
  label: string;
  url: string;
  expectedHash?: string;
}

interface MediaVerificationResult {
  status: "not_requested" | "skipped" | "passed" | "failed";
  checked: number;
  issues: string[];
}

interface CallerIdentity {
  uid: string;
  email: string;
  ra: string;
  name: string;
}

function requireAuth(auth: {uid: string; token: admin.auth.DecodedIdToken} | undefined): CallerIdentity {
  if (!auth) {
    throw new HttpsError("unauthenticated", "Autenticacao obrigatoria.");
  }
  const email = String(auth.token.email ?? "").trim().toLowerCase();
  const ra = raFromEmail(email);
  return {
    uid: auth.uid,
    email,
    ra,
    name: String(auth.token.name ?? ra ?? auth.uid),
  };
}

function raFromEmail(email: string): string {
  return email
    .replace("@canilgcm.com", "")
    .replace("@gcm.com.br", "")
    .trim();
}

function emailMatchesRa(email: string, ra: unknown): boolean {
  if (typeof ra !== "string" || ra.trim().length === 0) return false;
  const normalized = ra.trim().toLowerCase();
  return email === `${normalized}@gcm.com.br` || email === `${normalized}@canilgcm.com`;
}

function emailForRa(ra: string): string {
  return `${ra.trim().toLowerCase()}@gcm.com.br`;
}

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

function boolValue(value: unknown): boolean {
  return value === true || value === "true";
}

function optionalNumberValue(value: unknown): number | null {
  if (typeof value === "number" && Number.isFinite(value)) return value;
  if (typeof value !== "string") return null;
  const parsed = Number(value.trim().replace(",", "."));
  return Number.isFinite(parsed) ? parsed : null;
}

function requiredTimestamp(value: unknown, label: string): admin.firestore.Timestamp {
  if (value instanceof admin.firestore.Timestamp) return value;
  const parsed = new Date(String(value ?? ""));
  if (Number.isNaN(parsed.getTime())) {
    throw new HttpsError("invalid-argument", `${label} invalida.`);
  }
  return admin.firestore.Timestamp.fromDate(parsed);
}

function optionalTimestamp(value: unknown, label: string): admin.firestore.Timestamp | null {
  if (value === null || value === undefined || String(value).trim() === "") {
    return null;
  }
  return requiredTimestamp(value, label);
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

function optionalString(data: JsonMap, key: string): string | null {
  return stringValue(data[key]) ?? null;
}

function assertHumanRa(ra: string): void {
  if (!/^\d{4,12}$/.test(ra)) {
    throw new HttpsError("invalid-argument", "RA deve conter apenas numeros.");
  }
}

function assertDocumentId(id: string, label: string): void {
  if (!/^[a-zA-Z0-9_-]{1,120}$/.test(id)) {
    throw new HttpsError("invalid-argument", `${label} contem caracteres invalidos.`);
  }
}

function isAdminAccessLevel(accessLevel: string): boolean {
  return ["admin", "administrador"].includes(normalizedKey(accessLevel));
}

const MANAGED_ACCESS_ROLES = new Set([
  "admin",
  "administrador",
  "admin_master",
  "almoxarifado",
  "condutor",
  "estoque",
  "gestor",
  "handler",
  "inspetor",
  "instrutor",
  "instrutor_k9",
  "inventory_manager",
  "mobile_user",
  "subinspetor",
  "subinspetor_inspetor",
  "supervisor",
  "supervisor_operacional",
]);

function normalizedRoleKeys(...sources: unknown[]): string[] {
  return Array.from(
    new Set(
      sources
        .flatMap((source) => stringList(source))
        .map((role) => normalizedKey(role))
        .filter((role) => role.length > 0),
    ),
  );
}

function accessClaimsForProfile(
  existingClaims: JsonMap,
  ra: string,
  profileId: string | null,
  roleKeys: string[],
  accessScope: "global" | "own_records" = "global",
): JsonMap {
  const profileKey = normalizedKey(profileId);
  const profileRoles = new Set([
    ...roleKeys.map((role) => normalizedKey(role)).filter((role) => role.length > 0),
    ...(profileKey ? [profileKey] : []),
  ]);
  const isAdminProfile = profileRoles.has("admin") ||
    profileRoles.has("administrador") ||
    profileRoles.has("admin_master");
  const isInstructorProfile = profileRoles.has("instrutor_k9") ||
    profileRoles.has("instrutor") ||
    profileRoles.has("adestrador");
  const isInventoryProfile = profileRoles.has("inventory_manager") ||
    profileRoles.has("almoxarifado") ||
    profileRoles.has("estoque");
  const isManagerProfile = profileRoles.has("gestor") ||
    profileRoles.has("subinspetor") ||
    profileRoles.has("inspetor") ||
    profileRoles.has("subinspetor_inspetor");
  const isHandlerProfile = profileRoles.has("condutor") ||
    profileRoles.has("handler") ||
    profileRoles.has("mobile_user");
  const mobileAccess = isAdminProfile || isInstructorProfile || isHandlerProfile;
  const webAccess = true;
  const preservedRoles = Array.isArray(existingClaims.roles) ?
    existingClaims.roles
      .map((role) => normalizedKey(role))
      .filter((role) => role.length > 0 && !MANAGED_ACCESS_ROLES.has(role)) :
    [];
  const roles = new Set([...preservedRoles, ...profileRoles]);

  if (isAdminProfile) roles.add("admin");
  if (isInstructorProfile) {
    roles.add("instrutor_k9");
    roles.add("condutor");
  }
  if (isInventoryProfile) roles.add("inventory_manager");
  if (isManagerProfile) roles.add("gestor");
  if (isHandlerProfile) roles.add("condutor");

  const primaryRole = isAdminProfile
    ? "admin"
    : isInstructorProfile
      ? "instrutor_k9"
      : isInventoryProfile
        ? "inventory_manager"
        : isManagerProfile
          ? "gestor"
          : "condutor";
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
    web_access: webAccess,
  };

  if (isInstructorProfile) {
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

function humanClaims(
  existingClaims: JsonMap,
  ra: string,
  accessLevel: string,
  accessProfileId: string | null,
  isK9Instructor: boolean,
  accessScope: "global" | "own_records" = "global",
): JsonMap {
  const roleKeys = normalizedRoleKeys(
    [accessLevel, accessProfileId],
    isK9Instructor ? ["instrutor_k9"] : [],
  );
  return accessClaimsForProfile(
    existingClaims,
    ra,
    accessProfileId,
    roleKeys,
    accessScope,
  );
}

function isActionRequiredNotification(type: string): boolean {
  return ACTION_REQUIRED_NOTIFICATION_TYPES.has(type);
}

function stringArray(value: unknown): string[] {
  if (!Array.isArray(value)) return [];
  return Array.from(
    new Set(
      value
        .map((item) => stringValue(item))
        .filter((item): item is string => Boolean(item)),
    ),
  ).sort();
}

function stringList(value: unknown): string[] {
  if (!Array.isArray(value)) return [];
  return value
    .map((item) => stringValue(item))
    .filter((item): item is string => Boolean(item));
}

function customClaimRoles(token: admin.auth.DecodedIdToken): string[] {
  return Array.isArray(token.roles) ? token.roles.map((item) => String(item)) : [];
}

function isAdminToken(token: admin.auth.DecodedIdToken): boolean {
  return token.admin === true ||
    token.role === "admin" ||
    customClaimRoles(token).includes("admin");
}

type AccessModule =
  | "access"
  | "binomials"
  | "health"
  | "humans"
  | "inventory"
  | "k9"
  | "training"
  | "vehicles";

type AccessAction = "view" | "create" | "edit" | "archive" | "approve";

function legacyAccessProfileId(value: unknown): string | null {
  const normalized = normalizedKey(value);
  if (!normalized) return null;
  if ([
    "admin",
    "administrador",
    "admin_master",
  ].includes(normalized)) {
    return "administrador";
  }
  if ([
    "gestor",
    "comando",
    "comando_canil",
    "supervisor",
    "supervisor_operacional",
    "subinspetor",
    "inspetor",
    "gestor_canil",
    "coordenador",
  ].includes(normalized)) {
    return "gestor";
  }
  if ([
    "instrutor",
    "instrutor_k9",
    "adestrador",
    "adestrador_k9",
    "k9_instructor",
  ].includes(normalized)) {
    return "instrutor_k9";
  }
  if ([
    "condutor",
    "handler",
    "mobile_user",
    "operador_mobile",
    "operador",
    "operador_k9",
    "guarda_k9",
  ].includes(normalized)) {
    return "operador_k9";
  }
  return normalized;
}

function accessProfileIdFrom(
  token: admin.auth.DecodedIdToken | undefined,
  user: JsonMap,
): string {
  const candidates = [
    token?.access_profile_id,
    user.access_profile_id,
    user.accessProfileId,
    user.accessProfile,
    user.access_profile,
    user.accessLevel,
    user.access_level,
    user.role,
    user.claim_role,
    user.training_role,
    ...(Array.isArray(user.roles) ? user.roles : []),
    ...(Array.isArray(token?.roles) ? token?.roles ?? [] : []),
  ];
  for (const candidate of candidates) {
    const profileId = legacyAccessProfileId(candidate);
    if (profileId) return profileId;
  }
  if (user.admin === true || token?.admin === true) return "administrador";
  if (user.inventory_manager === true || token?.inventory_manager === true) {
    return "almoxarifado";
  }
  if (
    user.is_k9_instructor === true ||
    user.training_instructor === true ||
    token?.instrutor_k9 === true ||
    token?.training_instructor === true
  ) {
    return "instrutor_k9";
  }
  return "operador_k9";
}

function profileGrantsPermission(
  profile: JsonMap,
  moduleId: AccessModule,
  action: AccessAction,
): boolean {
  const status = stringValue(profile.status) ?? "active";
  if (status !== "active") return false;
  const permissions = sanitizeAccessPermissions(profile.permissions);
  const modulePermissions = permissions[moduleId];
  if (!isPlainObject(modulePermissions)) return false;
  return modulePermissions[action] === true;
}

async function requireAccessPermission(
  auth: {uid: string; token: admin.auth.DecodedIdToken} | undefined,
  moduleId: AccessModule,
  action: AccessAction,
): Promise<CallerIdentity> {
  const caller = requireAuth(auth);
  if (auth && isAdminToken(auth.token)) return caller;

  const userSnap = await db.collection("users").doc(caller.ra).get();
  const user = userSnap.data() ?? {};
  const accessLevel = String(user.accessLevel ?? user.access_level ?? "");
  if (isAdminAccessLevel(accessLevel) || user.admin === true) return caller;

  const profileId = accessProfileIdFrom(auth?.token, user);
  const profileSnap = await db.collection("access_profiles").doc(profileId).get();
  if (
    profileSnap.exists &&
    profileGrantsPermission(profileSnap.data() ?? {}, moduleId, action)
  ) {
    return caller;
  }

  throw new HttpsError(
    "permission-denied",
    `Perfil sem permissao para ${moduleId}.${action}.`,
  );
}

async function requireAnyAccessPermission(
  auth: {uid: string; token: admin.auth.DecodedIdToken} | undefined,
  moduleId: AccessModule,
  actions: AccessAction[],
): Promise<CallerIdentity> {
  let lastError: unknown = null;
  for (const action of actions) {
    try {
      return await requireAccessPermission(auth, moduleId, action);
    } catch (error) {
      if (error instanceof HttpsError && error.code === "permission-denied") {
        lastError = error;
        continue;
      }
      throw error;
    }
  }
  throw lastError ?? new HttpsError(
    "permission-denied",
    `Perfil sem permissao para ${moduleId}.`,
  );
}

async function accessScopeForCaller(
  auth: {uid: string; token: admin.auth.DecodedIdToken} | undefined,
  caller: CallerIdentity,
): Promise<"global" | "own_records"> {
  if (auth && isAdminToken(auth.token)) return "global";

  const userSnap = await db.collection("users").doc(caller.ra).get();
  const user = userSnap.data() ?? {};
  const profileId = accessProfileIdFrom(auth?.token, user);
  const profileSnap = await db.collection("access_profiles").doc(profileId).get();
  const profileScope = stringValue(profileSnap.data()?.scope);
  if (profileScope === "own_records") return "own_records";
  if (profileScope === "global") return "global";

  const mirroredScope =
    stringValue(user.access_scope) ??
    stringValue(user.accessScope) ??
    stringValue(auth?.token.access_scope);
  return mirroredScope === "own_records" ? "own_records" : "global";
}

function dogHandlerRa(dog: JsonMap): string | null {
  return (
    stringValue(dog.conductorRa) ??
    stringValue(dog.conductor_ra) ??
    stringValue(dog.handlerId) ??
    stringValue(dog.handler_id) ??
    null
  );
}

async function callerHasActiveDog(caller: CallerIdentity, dogId: string) {
  const shiftSnap = await db.collection("active_shifts").doc(caller.ra).get();
  if (!shiftSnap.exists) return false;
  const shift = shiftSnap.data() ?? {};
  const activeDogId =
    stringValue(shift.currentDogId) ??
    stringValue(shift.service_dog_id) ??
    stringValue(shift.dogId);
  return stringValue(shift.status) === "active" && activeDogId === dogId;
}

async function requireDogRecordAccess(
  auth: {uid: string; token: admin.auth.DecodedIdToken} | undefined,
  caller: CallerIdentity,
  dogId: string,
  dog: JsonMap,
) {
  if ((await accessScopeForCaller(auth, caller)) === "global") return;
  if (dogHandlerRa(dog) === caller.ra) return;
  if (await callerHasActiveDog(caller, dogId)) return;

  throw new HttpsError(
    "permission-denied",
    "Seu perfil permite registrar dados apenas para o K9 vinculado ou em turno ativo.",
  );
}

function sanitizeAccessPermissions(value: unknown): JsonMap {
  if (!isPlainObject(value)) return {};
  const permissions: JsonMap = {};
  for (const [moduleId, modulePermissions] of Object.entries(value)) {
    const normalizedModule = normalizedKey(moduleId);
    if (!normalizedModule || !isPlainObject(modulePermissions)) continue;
    const actions: JsonMap = {};
    for (const [action, enabled] of Object.entries(modulePermissions)) {
      const normalizedAction = normalizedKey(action);
      if (normalizedAction && enabled === true) {
        actions[normalizedAction] = true;
      }
    }
    permissions[normalizedModule] = actions;
  }
  return permissions;
}

function accessProfilePayload(
  profileId: string,
  source: JsonMap,
  caller: CallerIdentity,
  options: {
    action: string;
    exists: boolean;
    status?: "active" | "inactive";
  },
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
    permissions: sanitizeAccessPermissions(source.permissions),
    role_keys: stringList(source.role_keys),
    scope: stringValue(source.scope) === "own_records" ? "own_records" : "global",
    seed_version: optionalNumberValue(source.seed_version) ?? 0,
    slug: optionalString(source, "slug") ?? profileId,
    status,
    tone: optionalString(source, "tone") ?? "cyan",
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

function mapArray(value: unknown): JsonMap[] {
  if (!Array.isArray(value)) return [];
  return value.filter((item): item is JsonMap => isPlainObject(item));
}

function isPlainObject(value: unknown): value is JsonMap {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

function isTimestamp(value: unknown): value is admin.firestore.Timestamp {
  return value instanceof admin.firestore.Timestamp;
}

function timestampToDartIso(timestamp: admin.firestore.Timestamp): string {
  const nanos = timestamp.nanoseconds;
  const millis = Math.floor(nanos / 1_000_000);
  const micros = Math.floor(nanos / 1_000) % 1_000;
  const date = new Date((timestamp.seconds * 1000) + millis);
  const iso = date.toISOString();
  if (micros === 0) return iso;
  return iso.replace("Z", `${micros.toString().padStart(3, "0")}Z`);
}

function normalizeForHash(value: unknown): unknown {
  if (value === undefined) return null;
  if (value === null) return null;
  if (isTimestamp(value)) return timestampToDartIso(value);
  if (value instanceof Date) return value.toISOString();
  if (Array.isArray(value)) return value.map((item) => normalizeForHash(item));
  if (isPlainObject(value)) {
    const output: JsonMap = {};
    for (const key of Object.keys(value).sort()) {
      output[key] = normalizeForHash(value[key]);
    }
    return output;
  }
  return value;
}

function canonicalJson(value: unknown): string {
  return JSON.stringify(normalizeForHash(value));
}

function hashPayload(payload: unknown): string {
  return crypto.createHash("sha256").update(canonicalJson(payload), "utf8").digest("hex");
}

function storageLocationFromUrl(rawUrl: string): {bucket?: string; path?: string} {
  const url = rawUrl.trim();
  if (!url) return {};
  if (url.startsWith("gs://")) {
    const withoutScheme = url.slice("gs://".length);
    const slash = withoutScheme.indexOf("/");
    if (slash < 0) return {bucket: withoutScheme};
    return {
      bucket: withoutScheme.slice(0, slash),
      path: withoutScheme.slice(slash + 1),
    };
  }
  try {
    const parsed = new URL(url);
    const parts = parsed.pathname.split("/").filter(Boolean);
    const bucketIndex = parts.indexOf("b");
    const objectIndex = parts.indexOf("o");
    if (bucketIndex >= 0 && objectIndex > bucketIndex && parts[bucketIndex + 1]) {
      return {
        bucket: decodeURIComponent(parts[bucketIndex + 1]),
        path: decodeURIComponent(parts.slice(objectIndex + 1).join("/")),
      };
    }
    if (parsed.hostname === "storage.googleapis.com" && parts.length >= 2) {
      return {
        bucket: decodeURIComponent(parts[0]),
        path: decodeURIComponent(parts.slice(1).join("/")),
      };
    }
  } catch {
    return {};
  }
  return {};
}

async function sha256FromStorageUrl(rawUrl: string, maxBytes = 20 * 1024 * 1024): Promise<string | undefined> {
  const location = storageLocationFromUrl(rawUrl);
  if (!location.path) return undefined;
  const bucket = location.bucket ?
    admin.storage().bucket(location.bucket) :
    admin.storage().bucket();
  const file = bucket.file(location.path);
  const [metadata] = await file.getMetadata();
  const size = Number(metadata.size ?? 0);
  if (Number.isFinite(size) && size > maxBytes) {
    throw new Error(`midia excede limite de ${maxBytes} bytes`);
  }
  const [bytes] = await file.download();
  return crypto.createHash("sha256").update(bytes).digest("hex");
}

function isPrimaryHandler(occurrence: JsonMap, caller: CallerIdentity): boolean {
  const createdBy = occurrence.created_by;
  return occurrence.primary_handler_id === caller.uid ||
    emailMatchesRa(caller.email, occurrence.primary_handler_ra) ||
    emailMatchesRa(caller.email, occurrence.created_by) ||
    (isPlainObject(createdBy) &&
      (createdBy.uid === caller.uid || emailMatchesRa(caller.email, createdBy.ra)));
}

function canActAsHandler(occurrence: JsonMap, handlerId: string, caller: CallerIdentity): boolean {
  const teamAuthKeys = stringArray(occurrence.team_auth_keys);
  const matchingMember = teamMembers(occurrence).find((member) => handlerIdForMember(member) === handlerId);
  const memberAuthUid = matchingMember ? stringValue(matchingMember.auth_uid ?? matchingMember.authUid) : undefined;
  return emailMatchesRa(caller.email, handlerId) ||
    teamAuthKeys.includes(`${handlerId}:${caller.uid}`) ||
    memberAuthUid === caller.uid ||
    (handlerId === caller.ra && teamHandlerIds(occurrence).includes(handlerId));
}

function isTeamParticipant(occurrence: JsonMap, caller: CallerIdentity): boolean {
  const teamAuthUids = stringArray(occurrence.team_auth_uids);
  const teamEmails = stringArray(occurrence.team_emails).map((email) => email.toLowerCase());
  const teamHandlerIds = stringArray(occurrence.team_handler_ids);
  return teamAuthUids.includes(caller.uid) ||
    teamEmails.includes(caller.email) ||
    teamHandlerIds.includes(caller.ra);
}

function isParticipant(occurrence: JsonMap, caller: CallerIdentity): boolean {
  return isPrimaryHandler(occurrence, caller) || isTeamParticipant(occurrence, caller);
}

function teamMembers(occurrence: JsonMap): JsonMap[] {
  return mapArray(occurrence.team);
}

function handlerIdForMember(member: JsonMap): string {
  return stringValue(member.handler_id ?? member.handlerId ?? member.handler_ra ?? member.ra) ?? "";
}

function teamHandlerIds(occurrence: JsonMap): string[] {
  const fromIndex = stringArray(occurrence.team_handler_ids);
  if (fromIndex.length > 0) return fromIndex;
  return Array.from(new Set(teamMembers(occurrence).map(handlerIdForMember).filter(Boolean))).sort();
}

function acceptedHandlerIds(occurrence: JsonMap): string[] {
  const accepted = stringArray(occurrence.accepted_handler_ids);
  if (accepted.length > 0 || Number(occurrence.participation_revision ?? 0) > 0) {
    return accepted;
  }
  return teamHandlerIds(occurrence);
}

function coSignerIds(occurrence: JsonMap): string[] {
  const accepted = new Set(stringArray(occurrence.accepted_handler_ids));
  const pending = new Set(stringArray(occurrence.pending_handler_ids));
  const declined = new Set(stringArray(occurrence.declined_handler_ids));
  const hasParticipationLists = accepted.size > 0 ||
    pending.size > 0 ||
    declined.size > 0 ||
    Number(occurrence.participation_revision ?? 0) > 0;
  return teamMembers(occurrence)
    .filter((member) => String(member.role ?? "integrante") !== "titular")
    .map(handlerIdForMember)
    .filter((handlerId) => {
      if (handlerId.length === 0) return false;
      if (declined.has(handlerId)) return false;
      if (!hasParticipationLists) return true;
      return accepted.has(handlerId) || pending.has(handlerId);
    })
    .sort();
}

function signatureRound(occurrence: JsonMap): number {
  const raw = Number(occurrence.signature_round ?? 1);
  return Number.isFinite(raw) && raw > 0 ? Math.round(raw) : 1;
}

function hasAllSignatures(
  occurrence: JsonMap,
  signatures: JsonMap[],
): boolean {
  const required = coSignerIds(occurrence);
  if (required.length === 0) return true;
  const round = signatureRound(occurrence);
  const signed = new Set(
    signatures
      .filter((signature) => Number(signature.round ?? signature.signature_round ?? 1) === round)
      .filter((signature) => signature.status === "signed")
      .map((signature) => stringValue(signature.handler_id ?? signature.handlerId) ?? "")
      .filter(Boolean),
  );
  return required.every((handlerId) => signed.has(handlerId));
}

function teamHashPayload(member: JsonMap): JsonMap {
  const payload: JsonMap = {
    handler_id: handlerIdForMember(member),
    role: String(member.role ?? "integrante"),
  };
  copyIfPresent(member, payload, "auth_uid", "auth_uid");
  copyIfPresent(member, payload, "handler_email", "handler_email");
  copyIfPresent(member, payload, "display_name", "display_name");
  copyIfPresent(member, payload, "dog_id", "dog_id");
  copyIfPresent(member, payload, "dog_name", "dog_name");
  copyIfPresent(member, payload, "dog_matricula", "dog_matricula");
  copyIfPresent(member, payload, "dog_breed", "dog_breed");
  payload.added_at = normalizeForHash(member.added_at ?? member.addedAt);
  copyIfPresent(member, payload, "added_by", "added_by");
  copyIfPresent(member, payload, "added_by_uid", "added_by_uid");
  return payload;
}

function signatureHashPayload(signature: JsonMap): JsonMap {
  const payload: JsonMap = {
    handler_id: stringValue(signature.handler_id ?? signature.handlerId) ?? "",
    round: Number(signature.round ?? signature.signature_round ?? 1),
    status: String(signature.status ?? "pending"),
    signed_at: normalizeForHash(signature.signed_at ?? signature.signedAt),
    signature_method: String(signature.signature_method ?? signature.signatureMethod ?? "biometric"),
    invalidated_at: normalizeForHash(signature.invalidated_at ?? signature.invalidatedAt),
  };
  copyIfPresent(signature, payload, "reason", "reason");
  copyIfPresent(signature, payload, "invalidated_by", "invalidated_by");
  copyIfPresent(signature, payload, "invalidation_reason", "invalidation_reason");
  return payload;
}

function participationHashPayload(participation: JsonMap): JsonMap {
  const payload: JsonMap = {
    handler_id: stringValue(participation.handler_id ?? participation.handlerId ?? participation.ra) ?? "",
    status: String(participation.status ?? "included"),
    at: normalizeForHash(participation.at ?? participation.updated_at ?? participation.created_at),
  };
  copyIfPresent(participation, payload, "decline_reason", "decline_reason");
  copyIfPresent(participation, payload, "updated_by", "updated_by");
  return payload;
}

function copyIfPresent(source: JsonMap, target: JsonMap, sourceKey: string, targetKey: string): void {
  if (source[sourceKey] !== undefined && source[sourceKey] !== null) {
    target[targetKey] = source[sourceKey];
  }
}

function eventHashPayload(
  eventId: string,
  event: JsonMap,
  includePhotoHashes: boolean,
): JsonMap | null {
  if (event.deleted_at !== undefined && event.deleted_at !== null) return null;
  const photoMetadata = mapArray(event.photo_metadata);
  const photoHashes = photoMetadata
    .map((metadata) => stringValue(metadata.sha256))
    .filter((hash): hash is string => Boolean(hash))
    .sort();
  const payload: JsonMap = {
    category: event.category ?? "other",
    description: event.description ?? null,
    dog_handler_id: event.dog_handler_id ?? null,
    gps_lat: event.gps_lat ?? null,
    gps_lng: event.gps_lng ?? null,
    id: eventId,
    photo_urls: stringArray(event.photo_urls),
    place_label: event.place_label ?? null,
    timestamp: normalizeForHash(event.timestamp),
    title: event.title ?? null,
  };
  if (includePhotoHashes) payload.photo_hashes = photoHashes;
  return payload;
}

function expectedEventMedia(eventId: string, event: JsonMap): ExpectedMedia[] {
  if (event.deleted_at !== undefined && event.deleted_at !== null) return [];
  const metadata = mapArray(event.photo_metadata);
  const metadataByUrl = new Map<string, JsonMap>();
  for (const item of metadata) {
    const url = stringValue(item.url);
    if (url) metadataByUrl.set(url, item);
  }
  return stringList(event.photo_urls).map((url, index) => {
    const item = metadataByUrl.get(url) ?? metadata[index];
    return {
      label: `evento ${eventId} foto ${index + 1}`,
      url,
      expectedHash: stringValue(item?.sha256),
    };
  });
}

function expectedFinalizationMedia(occurrence: JsonMap): ExpectedMedia[] {
  const urls = stringList(occurrence.finalization_photos);
  const hashes = stringList(occurrence.finalization_photo_hashes);
  return urls.map((url, index) => ({
    label: `finalizacao foto ${index + 1}`,
    url,
    expectedHash: hashes[index],
  }));
}

async function verifyMediaBytes(
  occurrence: JsonMap,
  events: Array<{id: string; data: JsonMap}>,
): Promise<MediaVerificationResult> {
  const expectedMedia = [
    ...events.flatMap((event) => expectedEventMedia(event.id, event.data)),
    ...expectedFinalizationMedia(occurrence),
  ];
  const issues: string[] = [];
  let checked = 0;

  for (const media of expectedMedia) {
    if (!media.url) continue;
    if (!media.expectedHash) {
      issues.push(`${media.label}: hash esperado ausente`);
      continue;
    }
    try {
      const actualHash = await sha256FromStorageUrl(media.url);
      checked += 1;
      if (!actualHash) {
        issues.push(`${media.label}: URL de Storage nao reconhecida`);
      } else if (actualHash !== media.expectedHash) {
        issues.push(`${media.label}: SHA-256 da midia nao confere`);
      }
    } catch (error) {
      issues.push(`${media.label}: falha ao verificar midia (${String(error)})`);
    }
  }

  return {
    status: issues.length > 0 ? "failed" : "passed",
    checked,
    issues,
  };
}

function buildHashPayloadForVersion(
  occurrence: JsonMap,
  events: Array<{id: string; data: JsonMap}>,
  signatures: JsonMap[],
  participations: JsonMap[],
  correctionRequests: JsonMap[],
  version: number,
): JsonMap {
  const includePhotoHashes = version >= 2;
  const includeTeamAndSignatures = version >= 3;
  const includeCrewReview = version >= 4;
  const eventPayload = events
    .map((event) => eventHashPayload(event.id, event.data, includePhotoHashes))
    .filter((event): event is JsonMap => event !== null)
    .sort((a, b) => {
      const byTimestamp = String(a.timestamp).localeCompare(String(b.timestamp));
      return byTimestamp !== 0 ? byTimestamp : String(a.id).localeCompare(String(b.id));
    });

  const sortedTeam = teamMembers(occurrence)
    .map(teamHashPayload)
    .sort((a, b) => String(a.handler_id).localeCompare(String(b.handler_id)));
  const sortedSignatures = signatures
    .map(signatureHashPayload)
    .sort((a, b) => {
      const byRound = Number(a.round).valueOf() - Number(b.round).valueOf();
      return byRound !== 0 ? byRound : String(a.handler_id).localeCompare(String(b.handler_id));
    });
  const sortedParticipations = participations
    .map(participationHashPayload)
    .filter((participation) => String(participation.handler_id).length > 0)
    .sort((a, b) => String(a.handler_id).localeCompare(String(b.handler_id)));
  const correctionPayload = correctionRequests
    .map((request) => normalizeForHash(request) as JsonMap)
    .sort((a, b) => canonicalJson(a).localeCompare(canonicalJson(b)));

  const payload: JsonMap = {
    details: normalizeForHash(occurrence.details ?? null),
    dog_id: occurrence.dog_id ?? "",
    final_report: occurrence.final_report ?? null,
    finalization_photos: stringArray(occurrence.finalization_photos),
    gps_accuracy: occurrence.gps_accuracy ?? null,
    gps_lat: occurrence.gps_lat ?? null,
    gps_lng: occurrence.gps_lng ?? null,
    hash_version: version,
    location_address: occurrence.location_address ?? null,
    primary_handler_id: occurrence.primary_handler_id ?? "",
    primary_handler_ra: occurrence.primary_handler_ra ?? null,
    results: stringArray(occurrence.results),
    shift_id: occurrence.shift_id ?? "",
    vehicle_id: occurrence.vehicle_id ?? null,
    vehicle_label: occurrence.vehicle_label ?? null,
    vehicle_model: occurrence.vehicle_model ?? null,
    vehicle_prefix: occurrence.vehicle_prefix ?? null,
    vehicle_unit: occurrence.vehicle_unit ?? null,
    started_at: normalizeForHash(occurrence.started_at),
    events: eventPayload,
    type_code: occurrence.type_code ?? "",
    type_name: occurrence.type_name ?? "",
  };
  if (includePhotoHashes) {
    payload.finalization_photo_hashes = stringArray(occurrence.finalization_photo_hashes);
  }
  if (includeTeamAndSignatures) {
    payload.team = sortedTeam;
    payload.signatures = sortedSignatures;
  }
  if (includeCrewReview) {
    payload.crew_id = occurrence.crew_id ?? null;
    payload.service_dog_id = occurrence.service_dog_id ?? occurrence.dog_id ?? "";
    payload.accepted_handler_ids = stringArray(occurrence.accepted_handler_ids);
    payload.declined_handler_ids = stringArray(occurrence.declined_handler_ids);
    payload.edit_authorized_handler_ids = stringArray(occurrence.edit_authorized_handler_ids);
    payload.participation_revision = Number(occurrence.participation_revision ?? 0);
    payload.participation_status = occurrence.participation_status ?? null;
    payload.pending_handler_ids = stringArray(occurrence.pending_handler_ids);
    payload.signature_round = signatureRound(occurrence);
    payload.participations = sortedParticipations;
    payload.correction_requests = correctionPayload;
  }
  return payload;
}

function buildHashPayloadV4(
  occurrence: JsonMap,
  events: Array<{id: string; data: JsonMap}>,
  signatures: JsonMap[],
  participations: JsonMap[],
  correctionRequests: JsonMap[],
): JsonMap {
  return buildHashPayloadForVersion(
    occurrence,
    events,
    signatures,
    participations,
    correctionRequests,
    4,
  );
}

function auditEntry(action: string, caller: CallerIdentity, reason?: string): JsonMap {
  const now = admin.firestore.Timestamp.now();
  const entry: JsonMap = {
    action,
    at: now,
    by: caller.uid,
    by_name: caller.name,
    by_ra: caller.ra,
    performed_by: caller.uid,
    performed_at: timestampToDartIso(now),
  };
  if (reason) entry.reason = reason;
  return entry;
}

function notificationPayload(
  type: string,
  occurrenceId: string,
  occurrence: JsonMap,
  targetScreen: string,
  additionalData?: string,
): JsonMap {
  return {
    type,
    occurrence_id: occurrenceId,
    occurrence_title: String(occurrence.type_name ?? "Ocorrência"),
    target_screen: targetScreen,
    action_required: isActionRequiredNotification(type),
    created_at: admin.firestore.FieldValue.serverTimestamp(),
    read_at: null,
    resolved_at: null,
    additional_data: additionalData ?? "",
  };
}

function finalizationDraftFromOccurrence(
  occurrence: JsonMap,
  reason: string,
  round: number,
): JsonMap {
  return {
    current_step: 2,
    final_report: stringValue(occurrence.final_report) ?? "",
    results: Array.isArray(occurrence.results) ? occurrence.results : [],
    details: occurrence.details ?? null,
    saved_at: new Date().toISOString(),
    restored_from_signature_round: round,
    correction_reason: reason,
  };
}

function notificationText(type: string, occurrenceTitle: string): {title: string; body: string} {
  if (type === "vehicle_crew_invitation") {
    return {
      title: "Convite para a guarnição",
      body: occurrenceTitle,
    };
  }
  if (type === "vehicle_crew_invitation_accepted") {
    return {
      title: "Convite aceito",
      body: occurrenceTitle,
    };
  }
  if (type === "vehicle_crew_invitation_declined") {
    return {
      title: "Convite recusado",
      body: occurrenceTitle,
    };
  }
  if (type === "signature_requested") {
    return {
      title: "Assinatura necessária",
      body: `Revise e assine a ocorrência: ${occurrenceTitle}`,
    };
  }
  if (type === "occurrence_participation_requested") {
    return {
      title: "Ocorrência aberta",
      body: `Você foi incluído na ocorrência: ${occurrenceTitle}`,
    };
  }
  if (type === "occurrence_participation_accepted") {
    return {
      title: "Participacao confirmada",
      body: occurrenceTitle,
    };
  }
  if (type === "occurrence_participation_declined") {
    return {
      title: "Participacao recusada",
      body: occurrenceTitle,
    };
  }
  if (type === "correction_requested") {
    return {
      title: "Correção solicitada",
      body: `A ocorrência voltou para edição: ${occurrenceTitle}`,
    };
  }
  if (type === "occurrence_finalized") {
    return {
      title: "Ocorrência finalizada",
      body: occurrenceTitle,
    };
  }
  if (type === "training_promotion_requested") {
    return {
      title: "Validacao de treino",
      body: occurrenceTitle,
    };
  }
  if (type === "training_promotion_approved") {
    return {
      title: "Evolucao aprovada",
      body: occurrenceTitle,
    };
  }
  if (type === "training_promotion_rejected") {
    return {
      title: "Evolucao reprovada",
      body: occurrenceTitle,
    };
  }
  if (type === "training_bonus_milestone_available") {
    return {
      title: "Marco-bonus disponivel",
      body: occurrenceTitle,
    };
  }
  return {
    title: "Canil K9",
    body: occurrenceTitle,
  };
}

function crewNotificationPayload(
  type: string,
  crewId: string,
  vehicleLabel: string,
  additionalData?: string,
): JsonMap {
  return {
    type,
    occurrence_id: "",
    occurrence_title: vehicleLabel,
    target_screen: "vehicle_crew",
    action_required: isActionRequiredNotification(type),
    created_at: admin.firestore.FieldValue.serverTimestamp(),
    read_at: null,
    resolved_at: null,
    additional_data: additionalData ?? crewId,
  };
}

function trainingRequestTitle(request: JsonMap): string {
  const dogName = stringValue(request.dog_name) ?? "K9";
  const moduleName = stringValue(request.module_name) ?? "Modulo";
  return `${dogName} - ${moduleName}`;
}

function trainingNotificationPayload(
  type: string,
  requestId: string,
  request: JsonMap,
): JsonMap {
  return {
    type,
    occurrence_id: "",
    occurrence_title: trainingRequestTitle(request),
    target_screen: "training_promotion_request",
    action_required: isActionRequiredNotification(type),
    created_at: admin.firestore.FieldValue.serverTimestamp(),
    read_at: null,
    resolved_at: null,
    additional_data: requestId,
    promotion_request_id: requestId,
    dog_id: stringValue(request.dog_id) ?? "",
    modality: stringValue(request.modality) ?? "",
    module_id: stringValue(request.module_id) ?? "",
    decision_reason: stringValue(request.decision_reason) ?? "",
  };
}

function trainingBonusNotificationPayload(data: {
  dogId: string;
  dogName: string;
  modality: string;
  moduleId: string;
  moduleName: string;
  milestoneId: string;
  milestoneLabel: string;
  programVersion: number;
}): JsonMap {
  const additionalData = [
    data.dogId,
    data.modality,
    data.moduleId,
    data.milestoneId,
  ].join("|");
  return {
    type: "training_bonus_milestone_available",
    occurrence_id: "",
    occurrence_title: `${data.dogName} - ${data.milestoneLabel}`,
    target_screen: "training_bonus_milestone",
    action_required: false,
    created_at: admin.firestore.FieldValue.serverTimestamp(),
    read_at: null,
    resolved_at: null,
    additional_data: additionalData,
    dog_id: data.dogId,
    dog_name: data.dogName,
    modality: data.modality,
    module_id: data.moduleId,
    module_name: data.moduleName,
    milestone_id: data.milestoneId,
    milestone_label: data.milestoneLabel,
    program_version: data.programVersion,
  };
}

interface NotificationResolutionOptions {
  type: string;
  resolutionAction: string;
  actor?: CallerIdentity;
  occurrenceId?: string;
  additionalData?: string;
  promotionRequestId?: string;
  metadata?: JsonMap;
}

function notificationResolutionPatch(options: NotificationResolutionOptions): JsonMap {
  const actor = options.actor;
  return {
    resolved_at: admin.firestore.FieldValue.serverTimestamp(),
    read_at: admin.firestore.FieldValue.serverTimestamp(),
    resolution_source: "function",
    resolution_action: options.resolutionAction,
    resolution_actor_uid: actor?.uid ?? null,
    resolution_actor_ra: actor?.ra ?? null,
    resolution_actor_name: actor?.name ?? null,
    resolution_metadata: options.metadata ?? {},
  };
}

function matchesNotificationResolution(data: JsonMap, options: NotificationResolutionOptions): boolean {
  if (String(data.type ?? "") !== options.type) return false;
  if (data.resolved_at !== null && data.resolved_at !== undefined) return false;
  if (options.occurrenceId && String(data.occurrence_id ?? "") !== options.occurrenceId) {
    return false;
  }
  if (options.additionalData && String(data.additional_data ?? "") !== options.additionalData) {
    return false;
  }
  if (options.promotionRequestId) {
    const requestId =
      stringValue(data.promotion_request_id) ??
      stringValue(data.additional_data);
    if (requestId !== options.promotionRequestId) return false;
  }
  return true;
}

async function resolveUserActionNotificationsInTransaction(
  transaction: admin.firestore.Transaction,
  userId: string | undefined,
  options: NotificationResolutionOptions,
): Promise<number> {
  const resolvedUserId = stringValue(userId);
  if (!resolvedUserId) return 0;

  let query: admin.firestore.Query = db
    .collection("notifications")
    .doc(resolvedUserId)
    .collection("items");
  if (options.occurrenceId) {
    query = query.where("occurrence_id", "==", options.occurrenceId);
  } else if (options.additionalData) {
    query = query.where("additional_data", "==", options.additionalData);
  } else if (options.promotionRequestId) {
    query = query.where("promotion_request_id", "==", options.promotionRequestId);
  } else {
    query = query.where("type", "==", options.type);
  }

  const snapshot = await transaction.get(query);
  let resolved = 0;
  for (const doc of snapshot.docs) {
    const data = doc.data() ?? {};
    if (!matchesNotificationResolution(data, options)) continue;
    transaction.set(doc.ref, notificationResolutionPatch(options), {merge: true});
    resolved += 1;
  }
  return resolved;
}

async function resolveTrainingPromotionRequestNotifications(
  requestId: string,
  resolutionAction: string,
  metadata: JsonMap,
): Promise<number> {
  const snapshots: admin.firestore.QuerySnapshot[] = [
    await db.collectionGroup("items").where("promotion_request_id", "==", requestId).get(),
  ];
  try {
    snapshots.push(
      await db.collectionGroup("items").where("additional_data", "==", requestId).get(),
    );
  } catch (error) {
    logger.warn("Fallback additional_data ignorado ao resolver notificacoes de promocao.", {
      requestId,
      error: errorMessage(error),
    });
  }
  const seen = new Set<string>();
  let batch = db.batch();
  let pendingWrites = 0;
  let resolved = 0;
  const patch = notificationResolutionPatch({
    type: "training_promotion_requested",
    promotionRequestId: requestId,
    resolutionAction,
    metadata,
  });

  for (const snapshot of snapshots) {
    for (const doc of snapshot.docs) {
      if (seen.has(doc.ref.path)) continue;
      seen.add(doc.ref.path);
      const data = doc.data() ?? {};
      if (!matchesNotificationResolution(data, {
        type: "training_promotion_requested",
        promotionRequestId: requestId,
        resolutionAction,
      })) {
        continue;
      }
      batch.set(doc.ref, patch, {merge: true});
      pendingWrites += 1;
      resolved += 1;
      if (pendingWrites >= 450) {
        await batch.commit();
        batch = db.batch();
        pendingWrites = 0;
      }
    }
  }

  if (pendingWrites > 0) {
    await batch.commit();
  }
  return resolved;
}

export const decidePromotionRequest = onCall({region}, async (request) => {
  const caller = await requireAccessPermission(request.auth, "training", "approve");
  const data = request.data as JsonMap;
  const requestId = requiredString(data, "requestId");
  const decisionValue = requiredString(data, "decision");
  if (decisionValue !== "approved" && decisionValue !== "rejected") {
    throw new HttpsError("invalid-argument", "Decisao invalida.");
  }
  const reason = stringValue(data.reason);
  const note = stringValue(data.note);
  assertDocumentId(requestId, "Identificador da solicitacao");

  const ref = db.collection("promotion_requests").doc(requestId);
  const snap = await ref.get();
  if (!snap.exists) {
    throw new HttpsError("not-found", "Solicitacao nao encontrada.");
  }
  const current = snap.data() ?? {};
  if (current.status !== "pending") {
    throw new HttpsError(
      "failed-precondition",
      `Solicitacao ja foi decidida como "${current.status}".`,
    );
  }

  const now = admin.firestore.FieldValue.serverTimestamp();
  const decisionBy = caller.ra || caller.uid;
  const entry: JsonMap = {
    action: `training_module_promotion_${decisionValue}`,
    at: now,
    by: caller.uid,
    by_name: caller.name,
    by_ra: decisionBy,
    performed_by: caller.uid,
    performed_at: now,
  };
  if (note) entry.note = note;
  if (decisionValue === "rejected" && reason) entry.reason = reason;

  const update: JsonMap = {
    audit_trail: admin.firestore.FieldValue.arrayUnion(entry),
    decided_at: now,
    decision: decisionValue,
    decision_by: decisionBy,
    decision_by_email: caller.email,
    decision_by_uid: caller.uid,
    status: decisionValue,
    updated_at: now,
  };
  if (decisionValue === "rejected" && reason) {
    update.decision_reason = reason;
  }

  await ref.set(update, {merge: true});
  return {id: requestId, status: decisionValue};
});

export const adminSaveAccessProfile = onCall({region}, async (request) => {
  const data = request.data as JsonMap;
  const source = (data.profile ?? {}) as JsonMap;
  const profileId = stringValue(data.id) ?? requiredString(source, "id");
  assertDocumentId(profileId, "Identificador do perfil");

  const ref = db.collection("access_profiles").doc(profileId);
  const snapshot = await ref.get();
  const caller = await requireAccessPermission(
    request.auth,
    "access",
    snapshot.exists ? "edit" : "create",
  );
  await ref.set(
    accessProfilePayload(profileId, source, caller, {
      action: "updated",
      exists: snapshot.exists,
    }),
    {merge: true},
  );
  return {id: profileId, created: !snapshot.exists};
});

export const adminDuplicateAccessProfile = onCall({region}, async (request) => {
  const caller = await requireAccessPermission(request.auth, "access", "create");
  const data = request.data as JsonMap;
  const source = (data.profile ?? {}) as JsonMap;
  const sourceId = requiredString(source, "id");
  const profileId =
    stringValue(data.id) ??
    `${normalizedKey(sourceId).slice(0, 70)}_copia_${Date.now().toString(36)}`;
  assertDocumentId(profileId, "Identificador do perfil");

  const ref = db.collection("access_profiles").doc(profileId);
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
      },
    ),
  );
  return {id: profileId};
});

export const adminSetAccessProfileStatus = onCall({region}, async (request) => {
  const data = request.data as JsonMap;
  const profileId = requiredString(data, "id");
  const status = requiredString(data, "status");
  assertDocumentId(profileId, "Identificador do perfil");
  if (!["active", "inactive"].includes(status)) {
    throw new HttpsError("invalid-argument", "Status do perfil invalido.");
  }
  const caller = await requireAccessPermission(
    request.auth,
    "access",
    status === "inactive" ? "archive" : "edit",
  );

  const ref = db.collection("access_profiles").doc(profileId);
  const snapshot = await ref.get();
  if (!snapshot.exists) {
    throw new HttpsError("not-found", "Perfil de acesso nao encontrado.");
  }
  await ref.set(
    {
      status,
      updated_at: admin.firestore.FieldValue.serverTimestamp(),
      updated_by: caller.ra,
      audit_trail: admin.firestore.FieldValue.arrayUnion(
        auditEntry(
          status === "inactive" ? "inactivate_access_profile" : "activate_access_profile",
          caller,
        ),
      ),
    },
    {merge: true},
  );
  return {id: profileId, status};
});

export const adminAssignAccessProfile = onCall({region}, async (request) => {
  const caller = await requireAccessPermission(request.auth, "access", "edit");
  const data = request.data as JsonMap;
  const ra = requiredString(data, "ra");
  const profileId = requiredString(data, "profileId");
  assertHumanRa(ra);
  assertDocumentId(profileId, "Identificador do perfil");

  const userRef = db.collection("users").doc(ra);
  const profileRef = db.collection("access_profiles").doc(profileId);
  const [userSnap, profileSnap] = await Promise.all([userRef.get(), profileRef.get()]);
  if (!userSnap.exists) {
    throw new HttpsError("not-found", "Usuario nao encontrado.");
  }
  if (!profileSnap.exists) {
    throw new HttpsError("not-found", "Perfil de acesso nao encontrado.");
  }
  const profile = profileSnap.data() ?? {};
  if (profile.status === "inactive") {
    throw new HttpsError("failed-precondition", "Perfil inativo nao pode ser atribuido.");
  }
  const profileName = stringValue(profile.name) ?? profileId;
  const seedVersion = optionalNumberValue(profile.seed_version) ?? null;
  const accessScope =
    stringValue(profile.scope) === "own_records" ? "own_records" : "global";
  const roleKeys = normalizedRoleKeys(profile.role_keys, [profileId]);
  const roleSet = new Set(roleKeys);
  const isAdminProfile = roleSet.has("admin") ||
    roleSet.has("administrador") ||
    roleSet.has("admin_master");
  const isInstructorProfile = roleSet.has("instrutor_k9") ||
    roleSet.has("instrutor") ||
    roleSet.has("adestrador");
  const isInventoryProfile = roleSet.has("inventory_manager") ||
    roleSet.has("almoxarifado") ||
    roleSet.has("estoque");
  const isManagerProfile = roleSet.has("gestor") ||
    roleSet.has("subinspetor") ||
    roleSet.has("inspetor") ||
    roleSet.has("subinspetor_inspetor");
  const mobileAccess = isAdminProfile ||
    isInstructorProfile ||
    roleSet.has("condutor") ||
    roleSet.has("handler") ||
    roleSet.has("mobile_user");
  const appAccess = mobileAccess ? ["web", "mobile"] : ["web"];
  const userData = userSnap.data() ?? {};
  const authUid =
    stringValue(userData.auth_uid) ??
    stringValue(userData.authUid) ??
    stringValue(userData.uid);
  const authEmail = stringValue(userData.email) ?? emailForRa(ra);
  let authUser: admin.auth.UserRecord | null = null;
  if (authUid) {
    try {
      authUser = await admin.auth().getUser(authUid);
    } catch {
      authUser = null;
    }
  }
  if (!authUser) {
    try {
      authUser = await admin.auth().getUserByEmail(authEmail);
    } catch {
      authUser = null;
    }
  }
  if (authUser) {
    await admin.auth().setCustomUserClaims(
      authUser.uid,
      accessClaimsForProfile(
        authUser.customClaims ?? {},
        ra,
        profileId,
        roleKeys,
        accessScope,
      ),
    );
  }

  await userRef.set(
    {
      ...(authUser ? {auth_uid: authUser.uid, email: authEmail} : {}),
      access_profile_id: profileId,
      access_profile: profileName,
      accessProfile: profileName,
      accessProfileId: profileId,
      access_scope: accessScope,
      accessScope,
      admin: isAdminProfile,
      app_access: appAccess,
      claim_role: isAdminProfile
        ? "admin"
        : isInstructorProfile
          ? "instrutor_k9"
          : isInventoryProfile
            ? "inventory_manager"
            : isManagerProfile
              ? "gestor"
              : "condutor",
      inventory_manager: isInventoryProfile,
      is_k9_instructor: isInstructorProfile,
      mobile_access: mobileAccess,
      permissions_version: seedVersion,
      role: isAdminProfile
        ? "admin"
        : isInstructorProfile
          ? "instrutor_k9"
          : isInventoryProfile
            ? "inventory_manager"
            : isManagerProfile
              ? "gestor"
              : "condutor",
      roles: roleKeys,
      training_instructor: isInstructorProfile,
      training_role: isInstructorProfile ? "instrutor_k9" : null,
      web_access: true,
      claim_refresh_required: authUser != null,
      claim_updated_at: authUser
        ? admin.firestore.FieldValue.serverTimestamp()
        : null,
      updated_at: admin.firestore.FieldValue.serverTimestamp(),
      updated_by: caller.ra,
      audit_trail: admin.firestore.FieldValue.arrayUnion({
        ...auditEntry("assign_access_profile", caller),
        access_profile_id: profileId,
        access_profile_name: profileName,
      }),
    },
    {merge: true},
  );
  return {ra, profileId, profileName};
});

export const adminSeedAccessProfiles = onCall({region}, async (request) => {
  const caller = await requireAccessPermission(request.auth, "access", "approve");
  const data = request.data as JsonMap;
  const profiles = mapArray(data.profiles);
  const reconcile = data.reconcile !== false;
  if (profiles.length === 0) {
    throw new HttpsError("invalid-argument", "Nenhum perfil informado para seed.");
  }

  const batch = db.batch();
  const created: string[] = [];
  const updated: string[] = [];
  const archived: string[] = [];
  const seedIds = new Set<string>();
  for (const profile of profiles) {
    const profileId = requiredString(profile, "id");
    assertDocumentId(profileId, "Identificador do perfil");
    seedIds.add(profileId);
    const ref = db.collection("access_profiles").doc(profileId);
    const snapshot = await ref.get();
    if (snapshot.exists) {
      updated.push(profileId);
    } else {
      created.push(profileId);
    }
    batch.set(ref, accessProfilePayload(profileId, profile, caller, {
      action: snapshot.exists ? "seed_updated" : "seeded",
      exists: snapshot.exists,
    }), {merge: true});
  }

  if (reconcile) {
    const snapshot = await db.collection("access_profiles").get();
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
          auditEntry("inactivated_by_profile_seed", caller),
        ),
      }, {merge: true});
      archived.push(docSnapshot.id);
    }
  }

  if (created.length > 0 || updated.length > 0 || archived.length > 0) {
    batch.set(db.collection("auditLogs").doc(), {
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
});

const K9_MODALITY_LABELS: Record<string, string> = {
  busca_captura: "Busca & Captura",
  deteccao: "Deteccao",
  guarda_protecao: "Guarda & Protecao",
};

function canonicalK9Modality(value: unknown): string {
  const slug = normalizedKey(String(value ?? "").replace("&", " e "));
  if ([
    "deteccao",
    "detection",
    "deteccao_de_armas",
    "deteccao_armas",
    "deteccao_de_armas_e_polvora",
    "deteccao_de_entorpecentes",
    "deteccao_entorpecentes",
    "deteccao_de_drogas",
    "deteccao_drogas",
  ].includes(slug)) {
    return "deteccao";
  }
  if (["busca_captura", "busca_e_captura"].includes(slug)) {
    return "busca_captura";
  }
  if (["guarda_protecao", "guarda_e_protecao"].includes(slug)) {
    return "guarda_protecao";
  }
  return slug;
}

function isCanonicalK9Modality(value: string): boolean {
  return Object.prototype.hasOwnProperty.call(K9_MODALITY_LABELS, value);
}

function canonicalK9ModalityLabel(value: string): string {
  return K9_MODALITY_LABELS[canonicalK9Modality(value)] ?? value;
}

function canonicalK9Modalities(values: unknown): string[] {
  return Array.from(
    new Set(
      stringList(values)
        .map(canonicalK9Modality)
        .filter(isCanonicalK9Modality),
    ),
  );
}

function k9Text(data: JsonMap, ...keys: string[]): string {
  for (const key of keys) {
    const value = stringValue(data[key]);
    if (value) return value;
  }
  return "";
}

function k9Number(data: JsonMap, ...keys: string[]): number | null {
  for (const key of keys) {
    const value = optionalNumberValue(data[key]);
    if (value !== null) return value;
  }
  return null;
}

function parseK9BirthDate(profile: JsonMap): string {
  const birthDate = requiredString(profile, "birthDate");
  const parsed = new Date(`${birthDate}T12:00:00`);
  if (Number.isNaN(parsed.getTime())) {
    throw new HttpsError("invalid-argument", "Data de nascimento do K9 invalida.");
  }
  return parsed.toISOString();
}

function k9ProfilePayload(dogId: string, profile: JsonMap): JsonMap {
  const conductorRa = optionalString(profile, "conductorRa");
  if (conductorRa) assertHumanRa(conductorRa);
  const registrationNumber = requiredString(profile, "registrationNumber");
  const weight = optionalNumberValue(profile.weight);
  return {
    id: dogId,
    name: requiredString(profile, "name"),
    breed: requiredString(profile, "breed"),
    sex: requiredString(profile, "sex"),
    dateOfBirth: parseK9BirthDate(profile),
    status: requiredString(profile, "operationalStatus"),
    active: true,
    profileImageUrl: optionalString(profile, "profileImageUrl"),
    conductorRa: conductorRa ?? null,
    weight,
    registrationNumber,
    matricula: registrationNumber,
    idealWeightMin: optionalNumberValue(profile.idealWeightMin),
    idealWeightMax: optionalNumberValue(profile.idealWeightMax),
    cor: optionalString(profile, "color"),
    microchip: optionalString(profile, "microchip"),
    observacoes: optionalString(profile, "notes"),
    condicaoCorporal: optionalString(profile, "physicalCondition"),
    porte: optionalString(profile, "size"),
  };
}

async function k9RegistrationExists(
  registrationNumber: string,
  currentDogId?: string,
): Promise<boolean> {
  const normalized = registrationNumber.trim();
  const [legacySnap, currentSnap] = await Promise.all([
    db.collection("dogs").where("matricula", "==", normalized).get(),
    db.collection("dogs").where("registrationNumber", "==", normalized).get(),
  ]);
  return [legacySnap, currentSnap].some((snapshot) =>
    snapshot.docs.some((docSnapshot) => docSnapshot.id !== currentDogId),
  );
}

function k9SpecialtyModality(data: JsonMap, id: string): string {
  return canonicalK9Modality(k9Text(data, "type", "modality", "name") || id);
}

function isActiveK9Specialty(data: JsonMap): boolean {
  const status = normalizedKey(k9Text(data, "status", "state"));
  return [
    "in_formation",
    "em_formacao",
    "operational",
    "operacional",
    "maintenance",
    "manutencao",
  ].includes(status);
}

function hasDetectionProgressDoc(data: JsonMap): boolean {
  if (data.deleted_at != null || data.archived_at != null) return false;
  const status = normalizedKey(k9Text(data, "status", "state"));
  return Boolean(status && !["not_started", "nao_iniciado"].includes(status));
}

async function protectedK9Modalities(dogId: string): Promise<string[]> {
  const [trainingSnap, detectionSnap] = await Promise.all([
    db.collection("dogs").doc(dogId).collection("training").get(),
    db.collection("dogs").doc(dogId).collection("detection_lines").get(),
  ]);
  const protectedSet = new Set<string>();
  trainingSnap.docs
    .filter((docSnapshot) => {
      const data = docSnapshot.data() ?? {};
      return data.deleted_at == null && data.archived_at == null;
    })
    .map((docSnapshot) => {
      const data = docSnapshot.data() ?? {};
      return canonicalK9Modality(k9Text(data, "modality", "type", "name") || docSnapshot.id);
    })
    .filter(isCanonicalK9Modality)
    .forEach((modality) => protectedSet.add(modality));
  if (detectionSnap.docs.some((docSnapshot) => hasDetectionProgressDoc(docSnapshot.data() ?? {}))) {
    protectedSet.add("deteccao");
  }
  return Array.from(protectedSet);
}

function firestoreRecordDate(data: JsonMap): number {
  for (const key of ["measured_at", "measuredAt", "created_at", "createdAt"]) {
    const value = data[key];
    if (value instanceof admin.firestore.Timestamp) {
      return value.toMillis();
    }
    if (typeof value === "string" || typeof value === "number") {
      const parsed = new Date(value);
      if (!Number.isNaN(parsed.getTime())) return parsed.getTime();
    }
  }
  return 0;
}

async function latestK9Weight(dogId: string, fallback: unknown): Promise<number | null> {
  const snapshot = await db.collection("dogs").doc(dogId).collection("weight_records").get();
  const latest = [...snapshot.docs].sort(
    (a, b) => firestoreRecordDate(b.data() ?? {}) - firestoreRecordDate(a.data() ?? {}),
  )[0];
  if (latest) {
    return k9Number(latest.data() ?? {}, "weight_kg", "weightKg", "weight", "peso");
  }
  return optionalNumberValue(fallback);
}

function appendK9WeightRecord(
  batch: admin.firestore.WriteBatch,
  dogId: string,
  weight: number,
  caller: CallerIdentity,
): void {
  const recordRef = db.collection("dogs").doc(dogId).collection("weight_records").doc();
  batch.set(recordRef, {
    dogId,
    dog_id: dogId,
    weight_kg: weight,
    measured_at: admin.firestore.FieldValue.serverTimestamp(),
    performed_by: caller.ra,
    created_at: admin.firestore.FieldValue.serverTimestamp(),
    updated_at: admin.firestore.FieldValue.serverTimestamp(),
    audit_trail: [auditEntry("created", caller)],
  });
}

async function reconcileK9Specialties(
  batch: admin.firestore.WriteBatch,
  dogId: string,
  selected: string[],
  caller: CallerIdentity,
): Promise<void> {
  const existingSnap = await db.collection("dogs").doc(dogId).collection("specialties").get();
  const existingByModality = new Map<string, Array<{
    data: JsonMap;
    ref: admin.firestore.DocumentReference;
  }>>();
  for (const docSnapshot of existingSnap.docs) {
    const data = docSnapshot.data() ?? {};
    const modality = k9SpecialtyModality(data, docSnapshot.id);
    existingByModality.set(modality, [
      ...(existingByModality.get(modality) ?? []),
      {data, ref: docSnapshot.ref},
    ]);
  }

  const selectedSet = new Set(selected);
  for (const modality of selectedSet) {
    const grouped = existingByModality.get(modality) ?? [];
    const canonicalExisting = grouped.find((item) => item.ref.id === modality);
    const source =
      canonicalExisting ??
      grouped.find((item) => isActiveK9Specialty(item.data)) ??
      grouped[0];
    const specialtyRef =
      canonicalExisting?.ref ??
      db.collection("dogs").doc(dogId).collection("specialties").doc(modality);

    if (!canonicalExisting) {
      const sourceData = source?.data ?? {};
      batch.set(specialtyRef, {
        type: modality,
        name: canonicalK9ModalityLabel(modality),
        status: k9Text(sourceData, "status", "state") || "not_started",
        ...(k9Text(sourceData, "state") ? {state: k9Text(sourceData, "state")} : {}),
        ...(Array.isArray(sourceData.sub_areas) ? {sub_areas: sourceData.sub_areas} : {}),
        ...(sourceData.started_at ? {started_at: sourceData.started_at} : {}),
        ...(sourceData.operational_since ? {operational_since: sourceData.operational_since} : {}),
        ...(sourceData.current_phase ? {current_phase: sourceData.current_phase} : {}),
        created_at: admin.firestore.FieldValue.serverTimestamp(),
        updated_at: admin.firestore.FieldValue.serverTimestamp(),
        audit_trail: [auditEntry("created", caller)],
      });
    }

    if (
      canonicalExisting &&
      (canonicalExisting.data.deleted_at != null || canonicalExisting.data.archived_at != null)
    ) {
      batch.set(canonicalExisting.ref, {
        deleted_at: admin.firestore.FieldValue.delete(),
        deleted_by: admin.firestore.FieldValue.delete(),
        delete_reason: admin.firestore.FieldValue.delete(),
        deleted_reason: admin.firestore.FieldValue.delete(),
        archived_at: admin.firestore.FieldValue.delete(),
        updated_at: admin.firestore.FieldValue.serverTimestamp(),
        audit_trail: admin.firestore.FieldValue.arrayUnion(auditEntry("restored", caller)),
      }, {merge: true});
    }

    for (const alias of grouped) {
      if (
        alias.ref.id !== modality &&
        alias.data.deleted_at == null &&
        alias.data.archived_at == null
      ) {
        const reason = `Alias legado consolidado em ${canonicalK9ModalityLabel(modality)}.`;
        batch.set(alias.ref, {
          deleted_at: admin.firestore.FieldValue.serverTimestamp(),
          deleted_by: caller.uid,
          delete_reason: reason,
          deleted_reason: reason,
          updated_at: admin.firestore.FieldValue.serverTimestamp(),
          audit_trail: admin.firestore.FieldValue.arrayUnion(auditEntry("deleted", caller, reason)),
        }, {merge: true});
      }
    }
  }

  for (const [modality, grouped] of existingByModality) {
    if (selectedSet.has(modality)) continue;
    const reason = "Modalidade desvinculada no cadastro administrativo web.";
    for (const existing of grouped) {
      if (existing.data.deleted_at != null || existing.data.archived_at != null) continue;
      batch.set(existing.ref, {
        deleted_at: admin.firestore.FieldValue.serverTimestamp(),
        deleted_by: caller.uid,
        delete_reason: reason,
        deleted_reason: reason,
        updated_at: admin.firestore.FieldValue.serverTimestamp(),
        audit_trail: admin.firestore.FieldValue.arrayUnion(auditEntry("deleted", caller, reason)),
      }, {merge: true});
    }
  }
}

export const adminUpsertK9 = onCall({region}, async (request) => {
  const data = request.data as JsonMap;
  const mode = requiredString(data, "mode");
  if (!["create", "edit"].includes(mode)) {
    throw new HttpsError("invalid-argument", "Modo de cadastro invalido.");
  }
  const caller = await requireAccessPermission(
    request.auth,
    "k9",
    mode === "create" ? "create" : "edit",
  );
  const profile = (data.profile ?? {}) as JsonMap;
  const dogId = stringValue(data.dogId) ?? db.collection("dogs").doc().id;
  assertDocumentId(dogId, "Identificador do K9");
  const dogRef = db.collection("dogs").doc(dogId);
  const existingSnap = await dogRef.get();
  if (mode === "create" && existingSnap.exists) {
    throw new HttpsError("already-exists", "Ja existe um K9 com este identificador.");
  }
  if (mode === "edit" && !existingSnap.exists) {
    throw new HttpsError("not-found", "K9 nao encontrado.");
  }

  const payload = k9ProfilePayload(dogId, profile);
  const registrationNumber = requiredString(profile, "registrationNumber");
  if (await k9RegistrationExists(registrationNumber, dogId)) {
    throw new HttpsError("already-exists", "Ja existe um K9 com esta matricula/RGA.");
  }

  const selected = canonicalK9Modalities(profile.specialties);
  const protectedModalities = await protectedK9Modalities(dogId);
  const blockedRemoval = protectedModalities.filter(
    (modality) => !selected.includes(modality),
  );
  if (blockedRemoval.length > 0) {
    throw new HttpsError(
      "failed-precondition",
      `Nao e possivel remover ${blockedRemoval
        .map(canonicalK9ModalityLabel)
        .join(", ")} aqui porque ha progressao de treino registrada.`,
    );
  }

  const previousData = existingSnap.data() ?? {};
  const currentWeight = mode === "create" ?
    null :
    await latestK9Weight(dogId, previousData.weight);
  const nextWeight = optionalNumberValue(profile.weight);
  const batch = db.batch();
  const now = admin.firestore.FieldValue.serverTimestamp();
  const dogPatch: JsonMap = {
    ...payload,
    specialties: selected,
    updated_at: now,
    updatedAt: now,
  };

  if (mode === "create") {
    dogPatch.created_at = now;
    dogPatch.audit_trail = [auditEntry("created", caller)];
    batch.set(dogRef, dogPatch);
  } else {
    dogPatch.audit_trail = admin.firestore.FieldValue.arrayUnion(
      auditEntry("updated", caller),
    );
    batch.set(dogRef, dogPatch, {merge: true});
  }

  if (nextWeight !== null && (mode === "create" || currentWeight === null || nextWeight !== currentWeight)) {
    appendK9WeightRecord(batch, dogId, nextWeight, caller);
  }

  await reconcileK9Specialties(batch, dogId, selected, caller);
  batch.set(db.collection("auditLogs").doc(), {
    action: mode === "create" ? "k9_created" : "k9_updated",
    entity_type: "dog",
    entity_id: dogId,
    summary: `${mode === "create" ? "K9 cadastrado" : "K9 atualizado"}: ${payload.name}`,
    actor: caller,
    source: "functions",
    performed_at: now,
    createdAt: now,
  });
  await batch.commit();
  return {id: dogId};
});

export const adminArchiveK9 = onCall({region}, async (request) => {
  const caller = await requireAccessPermission(request.auth, "k9", "archive");
  const data = request.data as JsonMap;
  const id = requiredString(data, "id");
  const reason = requiredString(data, "reason");
  assertDocumentId(id, "Identificador do K9");
  const dogRef = db.collection("dogs").doc(id);
  const snapshot = await dogRef.get();
  if (!snapshot.exists) {
    throw new HttpsError("not-found", "K9 nao encontrado.");
  }
  const dog = snapshot.data() ?? {};
  const now = admin.firestore.FieldValue.serverTimestamp();
  await db.runTransaction(async (transaction) => {
    transaction.set(dogRef, {
      active: false,
      status: "Inativo",
      deleted_at: now,
      deleted_by: caller.uid,
      delete_reason: reason,
      deleted_reason: reason,
      updatedAt: now,
      updated_at: now,
      audit_trail: admin.firestore.FieldValue.arrayUnion(
        auditEntry("deleted", caller, reason),
      ),
    }, {merge: true});
    transaction.set(db.collection("auditLogs").doc(), {
      action: "k9_archived",
      entity_type: "dog",
      entity_id: id,
      summary: `K9 arquivado: ${stringValue(dog.name) ?? id}`,
      actor: caller,
      metadata: {reason},
      source: "functions",
      performed_at: now,
      createdAt: now,
    });
  });
  return {id, archived: true};
});

const HEALTH_EVENT_TYPES = new Set([
  "antiparasitic",
  "consultation",
  "exam",
  "medication",
  "other",
  "surgery",
  "symptom",
  "vaccination",
]);

export const adminCreateHealthEvent = onCall({region}, async (request) => {
  const caller = await requireAnyAccessPermission(
    request.auth,
    "health",
    ["create", "edit"],
  );
  const data = request.data as JsonMap;
  const dogId = requiredString(data, "dogId");
  const payload = (data.payload ?? {}) as JsonMap;
  assertDocumentId(dogId, "Identificador do K9");
  const dogRef = db.collection("dogs").doc(dogId);
  const dogSnapshot = await dogRef.get();
  if (!dogSnapshot.exists) {
    throw new HttpsError("not-found", "K9 nao encontrado.");
  }
  const type = normalizedKey(requiredString(payload, "type"));
  if (!HEALTH_EVENT_TYPES.has(type)) {
    throw new HttpsError("invalid-argument", "Tipo de evento de saude invalido.");
  }
  const eventDate = requiredTimestamp(payload.date, "Data do evento");
  const nextDueDate = optionalTimestamp(payload.nextDueDate, "Proxima data");
  const costBrl = optionalNumberValue(payload.costBrl);
  if (costBrl !== null && costBrl < 0) {
    throw new HttpsError("invalid-argument", "Custo nao pode ser negativo.");
  }
  const dog = dogSnapshot.data() ?? {};
  await requireDogRecordAccess(request.auth, caller, dogId, dog);
  const dogName = k9Text(dog, "name", "nome") || dogId;
  const eventRef = dogRef.collection("health_events").doc();
  const now = admin.firestore.FieldValue.serverTimestamp();
  const record: JsonMap = {
    dogId,
    dogName,
    date: eventDate,
    type,
    healthObservations: optionalString(payload, "healthObservations") ?? "",
    createdBy: caller.ra,
    created_by: caller.ra,
    created_by_uid: caller.uid,
    updated_by: caller.ra,
    created_at: now,
    updated_at: now,
    audit_trail: [auditEntry("created", caller)],
  };
  const subtype = optionalString(payload, "subtype");
  const professionalCrmv = optionalString(payload, "professionalCrmv");
  const professionalClinic = optionalString(payload, "professionalClinic");
  const attachmentUrl = optionalString(payload, "attachmentUrl");
  const attachmentName = optionalString(payload, "attachmentName");
  const attachmentStoragePath = optionalString(payload, "attachmentStoragePath");
  const vetName = optionalString(payload, "vetName");
  if (subtype) record.subtype = subtype;
  if (nextDueDate) record.nextDueDate = nextDueDate;
  if (professionalCrmv) record.professionalCrmv = professionalCrmv;
  if (professionalClinic) record.professionalClinic = professionalClinic;
  if (attachmentUrl) record.attachmentUrl = attachmentUrl;
  if (attachmentName) record.attachmentName = attachmentName;
  if (attachmentStoragePath) record.attachmentStoragePath = attachmentStoragePath;
  if (costBrl !== null) record.costBrl = costBrl;
  if (vetName) record.vetName = vetName;

  const batch = db.batch();
  batch.set(eventRef, record);
  batch.set(db.collection("auditLogs").doc(), {
    action: "health_event_created",
    entity_type: "health_event",
    entity_id: eventRef.id,
    entity_path: `dogs/${dogId}/health_events/${eventRef.id}`,
    summary: `Evento de saude registrado para ${dogName}`,
    actor: caller,
    metadata: {dog_id: dogId, type},
    source: "functions",
    performed_at: now,
    createdAt: now,
  });
  await batch.commit();
  return {dogId, id: eventRef.id, type};
});

export const adminCreateK9WeightRecord = onCall({region}, async (request) => {
  const caller = await requireAnyAccessPermission(
    request.auth,
    "health",
    ["create", "edit"],
  );
  const data = request.data as JsonMap;
  const dogId = requiredString(data, "dogId");
  const payload = (data.payload ?? {}) as JsonMap;
  assertDocumentId(dogId, "Identificador do K9");
  const weightKg = optionalNumberValue(payload.weightKg);
  if (weightKg === null || weightKg <= 0 || weightKg > 100) {
    throw new HttpsError("invalid-argument", "Peso do K9 invalido.");
  }
  const measuredAt = requiredTimestamp(payload.measuredAt, "Data da pesagem");
  const dogRef = db.collection("dogs").doc(dogId);
  const dogSnapshot = await dogRef.get();
  if (!dogSnapshot.exists) {
    throw new HttpsError("not-found", "K9 nao encontrado.");
  }
  const dog = dogSnapshot.data() ?? {};
  await requireDogRecordAccess(request.auth, caller, dogId, dog);
  const dogName = k9Text(dog, "name", "nome") || dogId;
  const recordRef = dogRef.collection("weight_records").doc();
  const legacyRef = dogRef.collection("weight_history").doc(recordRef.id);
  const now = admin.firestore.FieldValue.serverTimestamp();
  const record: JsonMap = {
    dogId,
    dog_id: dogId,
    weight_kg: weightKg,
    measured_at: measuredAt,
    measured_by: caller.ra,
    performed_by: caller.ra,
    context: optionalString(payload, "context") ?? "canil",
    created_at: now,
    updated_at: now,
    audit_trail: [auditEntry("created", caller)],
  };
  const notes = optionalString(payload, "notes");
  if (notes) record.notes = notes;

  const batch = db.batch();
  batch.set(recordRef, record);
  batch.set(legacyRef, record);
  batch.set(dogRef, {
    weight: weightKg,
    updatedAt: now,
    updated_at: now,
    audit_trail: admin.firestore.FieldValue.arrayUnion(
      auditEntry("weight_updated", caller),
    ),
  }, {merge: true});
  batch.set(db.collection("auditLogs").doc(), {
    action: "k9_weight_recorded",
    entity_type: "weight",
    entity_id: recordRef.id,
    entity_path: `dogs/${dogId}/weight_records/${recordRef.id}`,
    summary: `Pesagem registrada para ${dogName}: ${weightKg} kg`,
    actor: caller,
    metadata: {dog_id: dogId, weight_kg: weightKg},
    source: "functions",
    performed_at: now,
    createdAt: now,
  });
  await batch.commit();
  return {dogId, id: recordRef.id, weightKg};
});

export const adminCreateK9HealthDocument = onCall({region}, async (request) => {
  const caller = await requireAnyAccessPermission(
    request.auth,
    "health",
    ["create", "edit"],
  );
  const data = request.data as JsonMap;
  const dogId = requiredString(data, "dogId");
  const payload = (data.payload ?? {}) as JsonMap;
  assertDocumentId(dogId, "Identificador do K9");
  const dogRef = db.collection("dogs").doc(dogId);
  const dogSnapshot = await dogRef.get();
  if (!dogSnapshot.exists) {
    throw new HttpsError("not-found", "K9 nao encontrado.");
  }
  const url = requiredString(payload, "url");
  const name = requiredString(payload, "name");
  const type = requiredString(payload, "type");
  const dog = dogSnapshot.data() ?? {};
  await requireDogRecordAccess(request.auth, caller, dogId, dog);
  const dogName = k9Text(dog, "name", "nome") || dogId;
  const documentRef = db.collection("documentos").doc();
  const uploadedAt = admin.firestore.Timestamp.now();
  const now = admin.firestore.FieldValue.serverTimestamp();
  const record: JsonMap = {
    caoId: dogId,
    nome: name,
    descricao: optionalString(payload, "description") ?? "",
    tipo: type,
    url,
    dataUpload: uploadedAt,
    emissor: optionalString(payload, "issuer") ?? caller.name,
    audit_trail: [auditEntry("created", caller)],
  };
  const batch = db.batch();
  batch.set(documentRef, record);
  batch.set(db.collection("auditLogs").doc(), {
    action: "k9_health_document_created",
    entity_type: "dog_document",
    entity_id: documentRef.id,
    entity_path: `documentos/${documentRef.id}`,
    summary: `Documento de saude anexado para ${dogName}: ${name}`,
    actor: caller,
    metadata: {dog_id: dogId, type},
    source: "functions",
    performed_at: now,
    createdAt: now,
  });
  await batch.commit();
  return {dogId, id: documentRef.id, url};
});

export const adminUpsertHuman = onCall({region}, async (request) => {
  const data = request.data as JsonMap;
  const ra = requiredString(data, "ra");
  const mode = requiredString(data, "mode");
  const profile = (data.profile ?? {}) as JsonMap;
  assertHumanRa(ra);

  if (!["create", "edit"].includes(mode)) {
    throw new HttpsError("invalid-argument", "Modo de cadastro invalido.");
  }
  const caller = await requireAccessPermission(
    request.auth,
    "humans",
    mode === "create" ? "create" : "edit",
  );

  const userRef = db.collection("users").doc(ra);
  const userSnap = await userRef.get();
  if (mode === "create" && userSnap.exists) {
    throw new HttpsError("already-exists", "Ja existe um usuario com este RA.");
  }
  if (mode === "edit" && !userSnap.exists) {
    throw new HttpsError("not-found", "Usuario nao encontrado.");
  }

  const fullName = requiredString(profile, "fullName");
  const callsign = requiredString(profile, "callsign");
  const accessLevel = requiredString(profile, "accessLevel");
  const accessProfileName =
    optionalString(profile, "accessProfile") ??
    optionalString(profile, "access_profile");
  const accessProfileId =
    optionalString(profile, "accessProfileId") ??
    optionalString(profile, "access_profile_id");
  const unit = requiredString(profile, "unit");
  const active = profile.active !== false;
  const isK9Instructor =
    boolValue(profile.isK9Instructor) ||
    normalizedKey(accessProfileId) == "instrutor_k9" ||
    normalizedKey(accessProfileName) == "instrutor_k9";
  const profileRoleKeys = normalizedRoleKeys(
    [accessLevel, accessProfileId],
    isK9Instructor ? ["instrutor_k9"] : [],
  );
  const profileRoleSet = new Set(profileRoleKeys);
  const accessProfileSnapshot = accessProfileId
    ? await db.collection("access_profiles").doc(accessProfileId).get()
    : null;
  const accessScope =
    stringValue(accessProfileSnapshot?.data()?.scope) === "own_records"
      ? "own_records"
      : "global";
  const isAdminProfile = profileRoleSet.has("admin") ||
    profileRoleSet.has("administrador") ||
    profileRoleSet.has("admin_master");
  const isInventoryProfile = profileRoleSet.has("inventory_manager") ||
    profileRoleSet.has("almoxarifado") ||
    profileRoleSet.has("estoque");
  const isManagerProfile = profileRoleSet.has("gestor") ||
    profileRoleSet.has("subinspetor") ||
    profileRoleSet.has("inspetor") ||
    profileRoleSet.has("subinspetor_inspetor");
  const mobileAccess = isAdminProfile ||
    isK9Instructor ||
    profileRoleSet.has("condutor") ||
    profileRoleSet.has("handler") ||
    profileRoleSet.has("mobile_user");
  const accessRole = isAdminProfile
    ? "admin"
    : isK9Instructor
      ? "instrutor_k9"
      : isInventoryProfile
        ? "inventory_manager"
        : isManagerProfile
          ? "gestor"
          : "condutor";
  const email = emailForRa(ra);
  const existingData = userSnap.data() ?? {};
  const existingUid =
    stringValue(existingData.auth_uid) ??
    stringValue(existingData.authUid) ??
    stringValue(existingData.uid);
  if (
    caller.ra === ra &&
    isAdminAccessLevel(String(existingData.accessLevel ?? "")) &&
    !isAdminAccessLevel(accessLevel)
  ) {
    throw new HttpsError(
      "failed-precondition",
      "O administrador logado nao pode remover o proprio acesso administrativo.",
    );
  }
  let authUser: admin.auth.UserRecord | null = null;

  if (existingUid) {
    try {
      authUser = await admin.auth().getUser(existingUid);
    } catch {
      authUser = null;
    }
  }
  if (!authUser) {
    try {
      authUser = await admin.auth().getUserByEmail(email);
    } catch {
      authUser = null;
    }
  }

  let temporaryPassword: string | null = null;
  if (!authUser) {
    if (mode !== "create") {
      throw new HttpsError(
        "failed-precondition",
        "Cadastro existe no Firestore, mas a conta de acesso nao foi localizada.",
      );
    }
    temporaryPassword =
      stringValue(data.temporaryPassword) ??
      `${crypto.randomBytes(8).toString("base64url")}aA1!`;
    if (temporaryPassword.length < 8) {
      throw new HttpsError(
        "invalid-argument",
        "A senha provisoria deve ter ao menos 8 caracteres.",
      );
    }
    authUser = await admin.auth().createUser({
      disabled: !active,
      displayName: callsign,
      email,
      password: temporaryPassword,
      photoURL: optionalString(profile, "photoUrl") ?? undefined,
    });
  } else {
    authUser = await admin.auth().updateUser(authUser.uid, {
      disabled: !active,
      displayName: callsign,
      photoURL: optionalString(profile, "photoUrl") ?? undefined,
    });
  }

  const claims = humanClaims(
    authUser.customClaims ?? {},
    ra,
    accessLevel,
    accessProfileId,
    isK9Instructor,
    accessScope,
  );
  await admin.auth().setCustomUserClaims(authUser.uid, claims);

  const payload: JsonMap = {
    ra,
    auth_uid: authUser.uid,
    email,
    name: fullName,
    nomeCompleto: fullName,
    callsign,
    callSign: callsign,
    accessLevel,
    unit,
    active,
    status: active ? requiredString(profile, "status") : "Inativo",
    cargo: optionalString(profile, "role"),
    rank: optionalString(profile, "rank"),
    team: optionalString(profile, "team"),
    telefone: optionalString(profile, "phone"),
    institutional_email: optionalString(profile, "institutionalEmail"),
    cpf: optionalString(profile, "cpf"),
    birth_date: optionalString(profile, "birthDate"),
    admission_date: optionalString(profile, "admissionDate"),
    shift_label: optionalString(profile, "shiftLabel"),
    accessProfile: accessProfileName,
    access_profile: accessProfileName,
    accessProfileId: accessProfileId,
    access_profile_id: accessProfileId,
    accessScope,
    access_scope: accessScope,
    access_role: accessRole,
    admin: isAdminProfile,
    app_access: mobileAccess ? ["web", "mobile"] : ["web"],
    claim_role: accessRole,
    inventory_manager: isInventoryProfile,
    mobile_access: mobileAccess,
    permissions_version: optionalNumberValue(
      profile.permissionsVersion ?? profile.permissions_version,
    ),
    role: accessRole,
    roles: profileRoleKeys,
    notes: optionalString(profile, "notes"),
    photoUrl: optionalString(profile, "photoUrl"),
    specialties: stringArray(profile.specialties),
    is_k9_instructor: isK9Instructor,
    training_instructor: isK9Instructor,
    training_role: isK9Instructor ? "instrutor_k9" : null,
    web_access: true,
    claim_refresh_required: true,
    claim_updated_at: admin.firestore.FieldValue.serverTimestamp(),
    updated_at: admin.firestore.FieldValue.serverTimestamp(),
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
  };

  if (active) {
    payload.deleted_at = admin.firestore.FieldValue.delete();
    payload.deleted_by = admin.firestore.FieldValue.delete();
    payload.delete_reason = admin.firestore.FieldValue.delete();
    payload.deleted_reason = admin.firestore.FieldValue.delete();
  }
  if (mode === "create") {
    payload.created_at = admin.firestore.FieldValue.serverTimestamp();
    payload.createdAt = new Date().toISOString();
    payload.audit_trail = [auditEntry("created", caller)];
  } else {
    payload.audit_trail = admin.firestore.FieldValue.arrayUnion(
      auditEntry(active ? "updated" : "deactivated", caller),
    );
  }

  await userRef.set(payload, {merge: true});
  return {
    ra,
    uid: authUser.uid,
    created: mode === "create",
    temporary_password: temporaryPassword,
    token_refresh_required: true,
  };
});

export const adminArchiveHuman = onCall({region}, async (request) => {
  const caller = await requireAccessPermission(request.auth, "humans", "archive");
  const data = request.data as JsonMap;
  const ra = requiredString(data, "ra");
  const reason = requiredString(data, "reason");
  assertHumanRa(ra);
  if (caller.ra === ra) {
    throw new HttpsError(
      "failed-precondition",
      "O administrador logado nao pode arquivar o proprio cadastro.",
    );
  }

  const userRef = db.collection("users").doc(ra);
  const snapshot = await userRef.get();
  if (!snapshot.exists) {
    throw new HttpsError("not-found", "Usuario nao encontrado.");
  }
  const userData = snapshot.data() ?? {};
  const uid =
    stringValue(userData.auth_uid) ??
    stringValue(userData.authUid) ??
    stringValue(userData.uid);
  if (uid) await admin.auth().updateUser(uid, {disabled: true});

  await userRef.set({
    active: false,
    status: "Inativo",
    deleted_at: admin.firestore.FieldValue.serverTimestamp(),
    deleted_by: caller.uid,
    delete_reason: reason,
    deleted_reason: reason,
    updated_at: admin.firestore.FieldValue.serverTimestamp(),
    audit_trail: admin.firestore.FieldValue.arrayUnion(
      auditEntry("deleted", caller, reason),
    ),
  }, {merge: true});
  return {ra, archived: true};
});

async function saveHumanSubrecord(
  request: CallableRequest<unknown>,
  collectionName: "certifications" | "documents",
) {
  const data = request.data as JsonMap;
  const ra = requiredString(data, "ra");
  const payload = (data.payload ?? {}) as JsonMap;
  const recordId = stringValue(data.id);
  const caller = await requireAccessPermission(
    request.auth,
    "humans",
    recordId ? "edit" : "create",
  );
  assertHumanRa(ra);
  const userRef = db.collection("users").doc(ra);
  if (!(await userRef.get()).exists) {
    throw new HttpsError("not-found", "Usuario nao encontrado.");
  }
  const recordRef = recordId
    ? userRef.collection(collectionName).doc(recordId)
    : userRef.collection(collectionName).doc();
  const existing = await recordRef.get();
  const common: JsonMap = {
    name: requiredString(payload, "name"),
    type: optionalString(payload, "type"),
    category: optionalString(payload, "category"),
    issuer: optionalString(payload, "issuer"),
    issued_at: optionalString(payload, "issuedAt"),
    expires_at: optionalString(payload, "expiresAt"),
    document_url: optionalString(payload, "documentUrl"),
    storage_path: optionalString(payload, "storagePath"),
    file_name: optionalString(payload, "fileName"),
    notes: optionalString(payload, "notes"),
    updated_at: admin.firestore.FieldValue.serverTimestamp(),
    audit_trail: existing.exists
      ? admin.firestore.FieldValue.arrayUnion(auditEntry("updated", caller))
      : [auditEntry("created", caller)],
  };
  if (!existing.exists) {
    common.created_at = admin.firestore.FieldValue.serverTimestamp();
  }
  await recordRef.set(common, {merge: true});
  return {id: recordRef.id, ra};
}

async function archiveHumanSubrecord(
  request: CallableRequest<unknown>,
  collectionName: "certifications" | "documents",
) {
  const caller = await requireAccessPermission(request.auth, "humans", "archive");
  const data = request.data as JsonMap;
  const ra = requiredString(data, "ra");
  const id = requiredString(data, "id");
  const reason = requiredString(data, "reason");
  const ref = db.collection("users").doc(ra).collection(collectionName).doc(id);
  if (!(await ref.get()).exists) {
    throw new HttpsError("not-found", "Registro nao encontrado.");
  }
  await ref.set({
    deleted_at: admin.firestore.FieldValue.serverTimestamp(),
    deleted_by: caller.uid,
    delete_reason: reason,
    deleted_reason: reason,
    updated_at: admin.firestore.FieldValue.serverTimestamp(),
    audit_trail: admin.firestore.FieldValue.arrayUnion(
      auditEntry("deleted", caller, reason),
    ),
  }, {merge: true});
  return {id, ra, archived: true};
}

export const adminSaveHumanCertification = onCall(
  {region},
  async (request) => saveHumanSubrecord(request, "certifications"),
);

export const adminArchiveHumanCertification = onCall(
  {region},
  async (request) => archiveHumanSubrecord(request, "certifications"),
);

export const adminSaveHumanDocument = onCall(
  {region},
  async (request) => saveHumanSubrecord(request, "documents"),
);

export const adminArchiveHumanDocument = onCall(
  {region},
  async (request) => archiveHumanSubrecord(request, "documents"),
);

export const adminSaveHumanMovement = onCall({region}, async (request) => {
  const data = request.data as JsonMap;
  const payload = (data.payload ?? {}) as JsonMap;
  const id = stringValue(data.id);
  const caller = await requireAccessPermission(
    request.auth,
    "humans",
    id ? "edit" : "create",
  );
  const ra = requiredString(payload, "ra");
  assertHumanRa(ra);
  const user = await db.collection("users").doc(ra).get();
  if (!user.exists) throw new HttpsError("not-found", "Usuario nao encontrado.");

  const ref = id
    ? db.collection("effective_movements").doc(id)
    : db.collection("effective_movements").doc();
  const existing = await ref.get();
  const userData = user.data() ?? {};
  const record: JsonMap = {
    entity_type: "human",
    entity_id: ra,
    entity_name:
      stringValue(userData.callsign) ??
      stringValue(userData.nomeCompleto) ??
      ra,
    movement_type: requiredString(payload, "movementType"),
    status: requiredString(payload, "status"),
    start_at: requiredString(payload, "startAt"),
    expected_end_at: optionalString(payload, "expectedEndAt"),
    ended_at: optionalString(payload, "endedAt"),
    reason: requiredString(payload, "reason"),
    destination_unit: optionalString(payload, "destinationUnit"),
    operational_impact: optionalString(payload, "operationalImpact"),
    notes: optionalString(payload, "notes"),
    updated_at: admin.firestore.FieldValue.serverTimestamp(),
    audit_trail: existing.exists
      ? admin.firestore.FieldValue.arrayUnion(auditEntry("updated", caller))
      : [auditEntry("created", caller)],
  };
  if (!existing.exists) {
    record.created_at = admin.firestore.FieldValue.serverTimestamp();
  }
  await ref.set(record, {merge: true});
  return {id: ref.id, ra};
});

export const adminArchiveHumanMovement = onCall({region}, async (request) => {
  const caller = await requireAccessPermission(request.auth, "humans", "archive");
  const data = request.data as JsonMap;
  const id = requiredString(data, "id");
  const reason = requiredString(data, "reason");
  const ref = db.collection("effective_movements").doc(id);
  if (!(await ref.get()).exists) {
    throw new HttpsError("not-found", "Movimentacao nao encontrada.");
  }
  await ref.set({
    deleted_at: admin.firestore.FieldValue.serverTimestamp(),
    deleted_by: caller.uid,
    delete_reason: reason,
    deleted_reason: reason,
    updated_at: admin.firestore.FieldValue.serverTimestamp(),
    audit_trail: admin.firestore.FieldValue.arrayUnion(
      auditEntry("deleted", caller, reason),
    ),
  }, {merge: true});
  return {id, archived: true};
});

function vehicleLabel(name: string, prefix: string): string {
  const pieces = [name.trim(), prefix.trim()].filter(Boolean);
  return pieces.length ? pieces.join(" ") : prefix.trim();
}

function vehicleStatus(profile: JsonMap): {active: boolean; status: string} {
  const status = optionalString(profile, "status") ?? "Ativa";
  const normalized = normalizedKey(status);
  const active = ![
    "baixada",
    "inativa",
    "inactive",
    "retirada",
    "arquivada",
  ].includes(normalized);
  return {active, status};
}

export const adminUpsertVehicle = onCall({region}, async (request) => {
  const data = request.data as JsonMap;
  const mode = requiredString(data, "mode");
  const profile = (data.profile ?? {}) as JsonMap;
  if (!["create", "edit"].includes(mode)) {
    throw new HttpsError("invalid-argument", "Modo de cadastro invalido.");
  }
  const caller = await requireAccessPermission(
    request.auth,
    "vehicles",
    mode === "create" ? "create" : "edit",
  );

  const prefix = requiredString(profile, "prefix");
  const requestedId = stringValue(data.vehicleId) ?? prefix;
  const vehicleId = requestedId.trim();
  assertDocumentId(vehicleId, "Identificador da viatura");
  const name = requiredString(profile, "name");
  const label = vehicleLabel(name, prefix);
  const {active, status} = vehicleStatus(profile);
  const vehicleRef = db.collection("vehicles").doc(vehicleId);
  const snapshot = await vehicleRef.get();
  if (mode === "create" && snapshot.exists) {
    throw new HttpsError("already-exists", "Ja existe uma viatura com este prefixo.");
  }
  if (mode === "edit" && !snapshot.exists) {
    throw new HttpsError("not-found", "Viatura nao encontrada.");
  }

  const payload: JsonMap = {
    id: vehicleId,
    prefix,
    name,
    label,
    plate: requiredString(profile, "plate"),
    model: requiredString(profile, "model"),
    brand: optionalString(profile, "brand"),
    year: optionalString(profile, "year"),
    type: optionalString(profile, "type"),
    unit: requiredString(profile, "unit"),
    base: optionalString(profile, "base"),
    status,
    active,
    crew_size: optionalNumberValue(profile.crewSize) ?? 1,
    mileage_km: optionalNumberValue(profile.mileageKm),
    fuel: optionalString(profile, "fuel"),
    color: optionalString(profile, "color"),
    renavam: optionalString(profile, "renavam"),
    chassis: optionalString(profile, "chassis"),
    licensing: optionalString(profile, "licensing"),
    insurance: optionalString(profile, "insurance"),
    document_valid_until: optionalString(profile, "documentValidUntil"),
    next_review_at: optionalString(profile, "nextReviewAt"),
    next_review_km: optionalNumberValue(profile.nextReviewKm),
    maintenance_status: optionalString(profile, "maintenanceStatus"),
    capacity: optionalString(profile, "capacity"),
    accessories: optionalString(profile, "accessories"),
    notes: optionalString(profile, "notes"),
    photoUrl: optionalString(profile, "photoUrl"),
    updated_at: admin.firestore.FieldValue.serverTimestamp(),
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
  };

  if (active) {
    payload.deleted_at = admin.firestore.FieldValue.delete();
    payload.deleted_by = admin.firestore.FieldValue.delete();
    payload.delete_reason = admin.firestore.FieldValue.delete();
    payload.deleted_reason = admin.firestore.FieldValue.delete();
  }
  if (mode === "create") {
    payload.created_at = admin.firestore.FieldValue.serverTimestamp();
    payload.audit_trail = [auditEntry("created", caller)];
  } else {
    payload.audit_trail = admin.firestore.FieldValue.arrayUnion(
      auditEntry(active ? "updated" : "deactivated", caller),
    );
  }

  const batch = db.batch();
  batch.set(vehicleRef, payload, {merge: true});

  const operationalVehiclePatch = {
    vehicle_id: vehicleId,
    vehicle_label: label,
    vehicle_prefix: prefix,
    vehicle_model: payload.model,
    vehicle_unit: payload.unit,
    crew_size: payload.crew_size,
    updated_at: admin.firestore.FieldValue.serverTimestamp(),
  };
  const crewRef = db.collection("vehicle_crews").doc(vehicleId);
  const crewSnap = await crewRef.get();
  if (crewSnap.exists) {
    batch.set(crewRef, operationalVehiclePatch, {merge: true});
  }
  const activeShiftSnap = await db
    .collection("active_shifts")
    .where("vehicle_id", "==", vehicleId)
    .get();
  activeShiftSnap.docs.forEach((doc) => {
    batch.set(doc.ref, {
      vehicle_label: label,
      vehicle_prefix: prefix,
      vehicle_model: payload.model,
      vehicle_unit: payload.unit,
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    }, {merge: true});
  });
  batch.set(db.collection("auditLogs").doc(), {
    action: mode === "create" ? "vehicle_created" : "vehicle_updated",
    entity_type: "vehicle",
    entity_id: vehicleId,
    summary: `${mode === "create" ? "Viatura cadastrada" : "Viatura atualizada"}: ${label}`,
    actor: caller,
    source: "functions",
    performed_at: admin.firestore.FieldValue.serverTimestamp(),
    createdAt: admin.firestore.FieldValue.serverTimestamp(),
  });
  await batch.commit();
  return {id: vehicleId, label};
});

export const adminArchiveVehicle = onCall({region}, async (request) => {
  const caller = await requireAccessPermission(request.auth, "vehicles", "archive");
  const data = request.data as JsonMap;
  const id = requiredString(data, "id");
  const reason = requiredString(data, "reason");
  assertDocumentId(id, "Identificador da viatura");
  const ref = db.collection("vehicles").doc(id);
  const snapshot = await ref.get();
  if (!snapshot.exists) throw new HttpsError("not-found", "Viatura nao encontrada.");

  await ref.set({
    active: false,
    status: "Baixada",
    deleted_at: admin.firestore.FieldValue.serverTimestamp(),
    deleted_by: caller.uid,
    delete_reason: reason,
    deleted_reason: reason,
    updated_at: admin.firestore.FieldValue.serverTimestamp(),
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    audit_trail: admin.firestore.FieldValue.arrayUnion(
      auditEntry("deleted", caller, reason),
    ),
  }, {merge: true});
  await db.collection("auditLogs").doc().set({
    action: "vehicle_archived",
    entity_type: "vehicle",
    entity_id: id,
    summary: `Viatura arquivada: ${id}`,
    actor: caller,
    metadata: {reason},
    source: "functions",
    performed_at: admin.firestore.FieldValue.serverTimestamp(),
    createdAt: admin.firestore.FieldValue.serverTimestamp(),
  });
  return {id, archived: true};
});

export const adminSaveVehicleEvent = onCall({region}, async (request) => {
  const data = request.data as JsonMap;
  const vehicleId = requiredString(data, "vehicleId");
  const payload = (data.payload ?? {}) as JsonMap;
  const id = stringValue(data.id);
  const caller = await requireAccessPermission(
    request.auth,
    "vehicles",
    id ? "edit" : "create",
  );
  assertDocumentId(vehicleId, "Identificador da viatura");
  const vehicleRef = db.collection("vehicles").doc(vehicleId);
  if (!(await vehicleRef.get()).exists) {
    throw new HttpsError("not-found", "Viatura nao encontrada.");
  }
  const recordRef = id
    ? vehicleRef.collection("events").doc(id)
    : vehicleRef.collection("events").doc();
  const existing = await recordRef.get();
  await recordRef.set({
    type: requiredString(payload, "type"),
    title: requiredString(payload, "title"),
    date: requiredString(payload, "date"),
    odometer_km: optionalNumberValue(payload.odometerKm),
    responsible: optionalString(payload, "responsible"),
    provider: optionalString(payload, "provider"),
    cost: optionalNumberValue(payload.cost),
    status: optionalString(payload, "status"),
    notes: optionalString(payload, "notes"),
    document_url: optionalString(payload, "documentUrl"),
    storage_path: optionalString(payload, "storagePath"),
    updated_at: admin.firestore.FieldValue.serverTimestamp(),
    audit_trail: existing.exists
      ? admin.firestore.FieldValue.arrayUnion(auditEntry("updated", caller))
      : [auditEntry("created", caller)],
    ...(!existing.exists
      ? {created_at: admin.firestore.FieldValue.serverTimestamp()}
      : {}),
  }, {merge: true});
  return {id: recordRef.id, vehicleId};
});

export const adminArchiveVehicleEvent = onCall({region}, async (request) => {
  const caller = await requireAccessPermission(request.auth, "vehicles", "archive");
  const data = request.data as JsonMap;
  const vehicleId = requiredString(data, "vehicleId");
  const id = requiredString(data, "id");
  const reason = requiredString(data, "reason");
  const ref = db.collection("vehicles").doc(vehicleId).collection("events").doc(id);
  if (!(await ref.get()).exists) {
    throw new HttpsError("not-found", "Registro nao encontrado.");
  }
  await ref.set({
    deleted_at: admin.firestore.FieldValue.serverTimestamp(),
    deleted_by: caller.uid,
    delete_reason: reason,
    deleted_reason: reason,
    updated_at: admin.firestore.FieldValue.serverTimestamp(),
    audit_trail: admin.firestore.FieldValue.arrayUnion(
      auditEntry("deleted", caller, reason),
    ),
  }, {merge: true});
  return {id, vehicleId, archived: true};
});

function binomialIdFor(dogId: string, handlerRa: string): string {
  return `${dogId}__${handlerRa}`.replace(/[^a-zA-Z0-9_-]/g, "_");
}

function binomialIsActive(status: string, explicitActive: unknown): boolean {
  if (explicitActive === false) return false;
  return ![
    "inativo",
    "inactive",
    "encerrado",
    "ended",
    "afastado",
    "arquivado",
  ].includes(normalizedKey(status));
}

export const adminUpsertBinomial = onCall({region}, async (request) => {
  const data = request.data as JsonMap;
  const mode = requiredString(data, "mode");
  const profile = (data.profile ?? {}) as JsonMap;
  if (!["create", "edit"].includes(mode)) {
    throw new HttpsError("invalid-argument", "Modo de cadastro invalido.");
  }
  const caller = await requireAccessPermission(
    request.auth,
    "binomials",
    mode === "create" ? "create" : "edit",
  );
  const dogId = requiredString(profile, "dogId");
  const handlerRa = requiredString(profile, "handlerRa");
  assertHumanRa(handlerRa);
  const status = requiredString(profile, "status");
  const active = binomialIsActive(status, profile.active);
  const id = stringValue(data.id) ?? binomialIdFor(dogId, handlerRa);
  assertDocumentId(id, "Identificador do binomio");

  const dogRef = db.collection("dogs").doc(dogId);
  const handlerRef = db.collection("users").doc(handlerRa);
  const binomialRef = db.collection("binomials").doc(id);
  const [dogSnap, handlerSnap, existingSnap] = await Promise.all([
    dogRef.get(),
    handlerRef.get(),
    binomialRef.get(),
  ]);
  if (!dogSnap.exists) throw new HttpsError("not-found", "K9 nao encontrado.");
  if (!handlerSnap.exists) throw new HttpsError("not-found", "Condutor nao encontrado.");
  if (mode === "create" && existingSnap.exists) {
    throw new HttpsError("already-exists", "Este binomio ja existe.");
  }
  const dog = dogSnap.data() ?? {};
  const handler = handlerSnap.data() ?? {};
  const dogName = stringValue(dog.name) ?? stringValue(dog.nome) ?? dogId;
  const handlerName =
    stringValue(handler.callsign) ??
    stringValue(handler.callSign) ??
    stringValue(handler.nomeCompleto) ??
    handlerRa;
  const primary = boolValue(profile.primary);
  const batch = db.batch();

  if (active && primary) {
    const duplicateSnap = await db
      .collection("binomials")
      .where("dog_id", "==", dogId)
      .where("active", "==", true)
      .get();
    duplicateSnap.docs
      .filter((doc) => doc.id !== id)
      .forEach((doc) => {
        batch.set(doc.ref, {
          active: false,
          status: "Encerrado",
          ended_at: admin.firestore.FieldValue.serverTimestamp(),
          end_at: admin.firestore.FieldValue.serverTimestamp(),
          updated_at: admin.firestore.FieldValue.serverTimestamp(),
          audit_trail: admin.firestore.FieldValue.arrayUnion(
            auditEntry("ended_by_reassignment", caller),
          ),
        }, {merge: true});
      });
  }

  const payload: JsonMap = {
    id,
    dog_id: dogId,
    dogId,
    dog_name: dogName,
    dog_registration:
      stringValue(dog.registrationNumber) ??
      stringValue(dog.matricula) ??
      stringValue(dog.rga) ??
      null,
    dog_photo_url:
      stringValue(dog.profileImageUrl) ??
      stringValue(dog.photoUrl) ??
      null,
    handler_ra: handlerRa,
    handlerRa,
    handler_name: handlerName,
    handler_photo_url: stringValue(handler.photoUrl) ?? stringValue(handler.image_url) ?? null,
    status,
    active,
    primary,
    type: optionalString(profile, "type"),
    primary_specialty: optionalString(profile, "primarySpecialty"),
    unit: optionalString(profile, "unit"),
    team: optionalString(profile, "team"),
    start_at: requiredString(profile, "startAt"),
    end_at: optionalString(profile, "endAt"),
    readiness_score: optionalNumberValue(profile.readinessScore),
    synergy_score: optionalNumberValue(profile.synergyScore),
    notes: optionalString(profile, "notes"),
    updated_at: admin.firestore.FieldValue.serverTimestamp(),
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    audit_trail: existingSnap.exists
      ? admin.firestore.FieldValue.arrayUnion(auditEntry(active ? "updated" : "deactivated", caller))
      : [auditEntry("created", caller)],
  };
  if (!existingSnap.exists) {
    payload.created_at = admin.firestore.FieldValue.serverTimestamp();
  }
  if (active) {
    payload.deleted_at = admin.firestore.FieldValue.delete();
    payload.deleted_by = admin.firestore.FieldValue.delete();
    payload.delete_reason = admin.firestore.FieldValue.delete();
    payload.deleted_reason = admin.firestore.FieldValue.delete();
  }
  batch.set(binomialRef, payload, {merge: true});

  if (primary) {
    batch.set(dogRef, {
      conductorRa: active ? handlerRa : null,
      handlerId: active ? handlerRa : null,
      updated_at: admin.firestore.FieldValue.serverTimestamp(),
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      audit_trail: admin.firestore.FieldValue.arrayUnion(
        auditEntry(active ? "binomial_linked" : "binomial_unlinked", caller),
      ),
    }, {merge: true});
  }
  batch.set(db.collection("auditLogs").doc(), {
    action: existingSnap.exists ? "binomial_updated" : "binomial_created",
    entity_type: "binomial",
    entity_id: id,
    summary: `Binomio ${handlerName} + ${dogName}`,
    actor: caller,
    source: "functions",
    performed_at: admin.firestore.FieldValue.serverTimestamp(),
    createdAt: admin.firestore.FieldValue.serverTimestamp(),
  });
  await batch.commit();
  return {id, dogId, handlerRa};
});

export const adminArchiveBinomial = onCall({region}, async (request) => {
  const caller = await requireAccessPermission(request.auth, "binomials", "archive");
  const data = request.data as JsonMap;
  const id = requiredString(data, "id");
  const reason = requiredString(data, "reason");
  assertDocumentId(id, "Identificador do binomio");
  const ref = db.collection("binomials").doc(id);
  const snapshot = await ref.get();
  if (!snapshot.exists) throw new HttpsError("not-found", "Binomio nao encontrado.");
  const binomial = snapshot.data() ?? {};
  const dogId = stringValue(binomial.dog_id ?? binomial.dogId);
  const handlerRa = stringValue(binomial.handler_ra ?? binomial.handlerRa);
  const batch = db.batch();
  batch.set(ref, {
    active: false,
    status: "Encerrado",
    ended_at: admin.firestore.FieldValue.serverTimestamp(),
    end_at: admin.firestore.FieldValue.serverTimestamp(),
    deleted_at: admin.firestore.FieldValue.serverTimestamp(),
    deleted_by: caller.uid,
    delete_reason: reason,
    deleted_reason: reason,
    updated_at: admin.firestore.FieldValue.serverTimestamp(),
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    audit_trail: admin.firestore.FieldValue.arrayUnion(
      auditEntry("deleted", caller, reason),
    ),
  }, {merge: true});
  if (dogId && handlerRa) {
    const dogRef = db.collection("dogs").doc(dogId);
    const dogSnap = await dogRef.get();
    if (dogSnap.exists && stringValue(dogSnap.data()?.conductorRa) === handlerRa) {
      batch.set(dogRef, {
        conductorRa: null,
        handlerId: null,
        updated_at: admin.firestore.FieldValue.serverTimestamp(),
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        audit_trail: admin.firestore.FieldValue.arrayUnion(
          auditEntry("binomial_unlinked", caller, reason),
        ),
      }, {merge: true});
    }
  }
  batch.set(db.collection("auditLogs").doc(), {
    action: "binomial_archived",
    entity_type: "binomial",
    entity_id: id,
    summary: `Binomio arquivado: ${id}`,
    actor: caller,
    metadata: {reason},
    source: "functions",
    performed_at: admin.firestore.FieldValue.serverTimestamp(),
    createdAt: admin.firestore.FieldValue.serverTimestamp(),
  });
  await batch.commit();
  return {id, archived: true};
});

const DEFAULT_INVENTORY_CATEGORIES = [
  {id: "alimentacao", name: "Alimentacao", description: "Racao, petiscos e insumos alimentares."},
  {id: "saude", name: "Saude", description: "Medicamentos, suplementos e materiais veterinarios."},
  {id: "treinamento", name: "Treinamento", description: "Mordedores, mangas, trajes e materiais de treino."},
  {id: "equipamento", name: "Equipamento", description: "Guias, coleiras, focinheiras, EPIs e acessorios."},
  {id: "limpeza", name: "Limpeza", description: "Produtos de higiene, limpeza e manutencao do canil."},
  {id: "administrativo", name: "Administrativo", description: "Documentos, materiais administrativos e apoio."},
];

function inventoryItemStatus(
  quantity: number,
  minimumQuantity: number,
  expirationDate?: string | null,
  active = true,
): string {
  if (!active) return "inactive";
  if (expirationDate) {
    const parsed = new Date(`${expirationDate}T00:00:00`);
    if (!Number.isNaN(parsed.getTime())) {
      const today = new Date();
      today.setHours(0, 0, 0, 0);
      if (parsed < today) return "expired";
    }
  }
  if (quantity <= 0) return "out_of_stock";
  if (minimumQuantity > 0 && quantity <= minimumQuantity) return "low_stock";
  return "active";
}

function movementDelta(type: string, quantity: number): number {
  const normalized = normalizedKey(type);
  if (normalized === "entrada") return quantity;
  if (normalized === "saida" ||
    normalized === "descarte" ||
    normalized === "perda" ||
    normalized === "vencimento") {
    return -quantity;
  }
  if (normalized === "ajuste") return quantity;
  throw new HttpsError("invalid-argument", "Tipo de movimentacao invalido.");
}

function parseMovementQuantity(type: string, raw: unknown): number {
  const quantity = optionalNumberValue(raw);
  if (quantity === null || quantity === 0) {
    throw new HttpsError("invalid-argument", "Quantidade da movimentacao invalida.");
  }
  if (normalizedKey(type) !== "ajuste" && quantity < 0) {
    throw new HttpsError("invalid-argument", "Quantidade deve ser positiva para este tipo.");
  }
  return quantity;
}

function inventoryItemIdFromName(name: string): string {
  const base = normalizedKey(name).slice(0, 70) || "item";
  return `${base}_${Date.now().toString(36)}`;
}

export const adminSeedInventoryDefaults = onCall({region}, async (request) => {
  const caller = await requireAccessPermission(request.auth, "inventory", "create");
  const batch = db.batch();
  const now = admin.firestore.FieldValue.serverTimestamp();
  DEFAULT_INVENTORY_CATEGORIES.forEach((category) => {
    const ref = db.collection("inventory_categories").doc(category.id);
    batch.set(ref, {
      ...category,
      active: true,
      updated_at: now,
      audit_trail: admin.firestore.FieldValue.arrayUnion(
        auditEntry("seeded", caller),
      ),
    }, {merge: true});
  });
  batch.set(db.collection("auditLogs").doc(), {
    action: "inventory_defaults_seeded",
    entity_type: "inventory",
    entity_id: "inventory_categories",
    summary: "Categorias padrao de estoque semeadas",
    actor: caller,
    source: "functions",
    performed_at: now,
    createdAt: now,
  });
  await batch.commit();
  return {seeded: DEFAULT_INVENTORY_CATEGORIES.length};
});

export const adminUpsertInventoryCategory = onCall({region}, async (request) => {
  const data = request.data as JsonMap;
  const mode = requiredString(data, "mode");
  const payload = (data.payload ?? {}) as JsonMap;
  if (!["create", "edit"].includes(mode)) {
    throw new HttpsError("invalid-argument", "Modo de categoria invalido.");
  }
  const caller = await requireAccessPermission(
    request.auth,
    "inventory",
    mode === "create" ? "create" : "edit",
  );
  const name = requiredString(payload, "name");
  const id = stringValue(data.id) ?? normalizedKey(name);
  assertDocumentId(id, "Identificador da categoria");
  const ref = db.collection("inventory_categories").doc(id);
  const snapshot = await ref.get();
  if (mode === "create" && snapshot.exists) {
    throw new HttpsError("already-exists", "Ja existe uma categoria com este identificador.");
  }
  if (mode === "edit" && !snapshot.exists) {
    throw new HttpsError("not-found", "Categoria nao encontrada.");
  }
  const active = payload.active !== false;
  await ref.set({
    id,
    name,
    description: optionalString(payload, "description"),
    active,
    updated_at: admin.firestore.FieldValue.serverTimestamp(),
    audit_trail: snapshot.exists
      ? admin.firestore.FieldValue.arrayUnion(auditEntry(active ? "updated" : "deactivated", caller))
      : [auditEntry("created", caller)],
    ...(!snapshot.exists ? {created_at: admin.firestore.FieldValue.serverTimestamp()} : {}),
    ...(active ? {
      deleted_at: admin.firestore.FieldValue.delete(),
      deleted_by: admin.firestore.FieldValue.delete(),
      delete_reason: admin.firestore.FieldValue.delete(),
      deleted_reason: admin.firestore.FieldValue.delete(),
    } : {}),
  }, {merge: true});
  return {id};
});

export const adminArchiveInventoryCategory = onCall({region}, async (request) => {
  const caller = await requireAccessPermission(request.auth, "inventory", "archive");
  const data = request.data as JsonMap;
  const id = requiredString(data, "id");
  const reason = requiredString(data, "reason");
  assertDocumentId(id, "Identificador da categoria");
  const ref = db.collection("inventory_categories").doc(id);
  if (!(await ref.get()).exists) {
    throw new HttpsError("not-found", "Categoria nao encontrada.");
  }
  await ref.set({
    active: false,
    deleted_at: admin.firestore.FieldValue.serverTimestamp(),
    deleted_by: caller.uid,
    delete_reason: reason,
    deleted_reason: reason,
    updated_at: admin.firestore.FieldValue.serverTimestamp(),
    audit_trail: admin.firestore.FieldValue.arrayUnion(
      auditEntry("deleted", caller, reason),
    ),
  }, {merge: true});
  return {id, archived: true};
});

export const adminUpsertInventoryItem = onCall({region}, async (request) => {
  const data = request.data as JsonMap;
  const mode = requiredString(data, "mode");
  const profile = (data.profile ?? {}) as JsonMap;
  if (!["create", "edit"].includes(mode)) {
    throw new HttpsError("invalid-argument", "Modo de item invalido.");
  }
  const caller = await requireAccessPermission(
    request.auth,
    "inventory",
    mode === "create" ? "create" : "edit",
  );
  const name = requiredString(profile, "name");
  const id = stringValue(data.id) ?? inventoryItemIdFromName(name);
  assertDocumentId(id, "Identificador do item");
  const ref = db.collection("inventory_items").doc(id);
  const snapshot = await ref.get();
  if (mode === "create" && snapshot.exists) {
    throw new HttpsError("already-exists", "Ja existe um item com este identificador.");
  }
  if (mode === "edit" && !snapshot.exists) {
    throw new HttpsError("not-found", "Item de estoque nao encontrado.");
  }
  const previous = snapshot.data() ?? {};
  const currentQuantity = optionalNumberValue(previous.current_quantity) ?? 0;
  const minimumQuantity = optionalNumberValue(profile.minimumQuantity) ?? 0;
  const active = profile.active !== false;
  const expirationDate = optionalString(profile, "expirationDate");
  const initialQuantity = mode === "create" ?
    optionalNumberValue(profile.initialQuantity) ?? 0 :
    null;
  if (initialQuantity !== null && initialQuantity < 0) {
    throw new HttpsError("invalid-argument", "Quantidade inicial nao pode ser negativa.");
  }
  const startingQuantity = mode === "create" ? initialQuantity ?? 0 : currentQuantity;
  const status = inventoryItemStatus(startingQuantity, minimumQuantity, expirationDate, active);
  const categoryId = requiredString(profile, "categoryId");
  const categoryName = requiredString(profile, "categoryName");
  const unit = requiredString(profile, "unit");
  const now = admin.firestore.FieldValue.serverTimestamp();

  await db.runTransaction(async (transaction) => {
    transaction.set(ref, {
      id,
      name,
      category_id: categoryId,
      category_name: categoryName,
      unit,
      current_quantity: startingQuantity,
      minimum_quantity: minimumQuantity,
      status,
      active,
      brand: optionalString(profile, "brand"),
      supplier_name: optionalString(profile, "supplierName"),
      storage_location: optionalString(profile, "storageLocation"),
      expiration_date: expirationDate,
      lot: optionalString(profile, "lot"),
      description: optionalString(profile, "description"),
      notes: optionalString(profile, "notes"),
      photo_url: optionalString(profile, "photoUrl"),
      document_url: optionalString(profile, "documentUrl"),
      storage_path: optionalString(profile, "storagePath"),
      updated_at: now,
      audit_trail: snapshot.exists
        ? admin.firestore.FieldValue.arrayUnion(auditEntry(active ? "updated" : "deactivated", caller))
        : [auditEntry("created", caller)],
      ...(!snapshot.exists ? {created_at: now} : {}),
      ...(active ? {
        deleted_at: admin.firestore.FieldValue.delete(),
        deleted_by: admin.firestore.FieldValue.delete(),
        delete_reason: admin.firestore.FieldValue.delete(),
        deleted_reason: admin.firestore.FieldValue.delete(),
      } : {}),
    }, {merge: true});

    if (mode === "create" && initialQuantity && initialQuantity > 0) {
      const movementRef = db.collection("inventory_movements").doc();
      transaction.set(movementRef, {
        id: movementRef.id,
        item_id: id,
        item_name: name,
        type: "entrada",
        quantity: initialQuantity,
        delta: initialQuantity,
        unit,
        reason: "Estoque inicial",
        balance_before: 0,
        balance_after: initialQuantity,
        category_id: categoryId,
        category_name: categoryName,
        performed_by_ra: caller.ra,
        performed_by_name: caller.name,
        performed_by_uid: caller.uid,
        performed_at: now,
        notes: "Lancamento automatico do cadastro inicial.",
        created_at: now,
        audit_trail: [auditEntry("created", caller)],
      });
    }

    transaction.set(db.collection("auditLogs").doc(), {
      action: snapshot.exists ? "inventory_item_updated" : "inventory_item_created",
      entity_type: "inventory_item",
      entity_id: id,
      summary: `${snapshot.exists ? "Item atualizado" : "Item criado"}: ${name}`,
      actor: caller,
      source: "functions",
      performed_at: now,
      createdAt: now,
    });
  });
  return {id, status, current_quantity: startingQuantity};
});

export const adminArchiveInventoryItem = onCall({region}, async (request) => {
  const caller = await requireAccessPermission(request.auth, "inventory", "archive");
  const data = request.data as JsonMap;
  const id = requiredString(data, "id");
  const reason = requiredString(data, "reason");
  assertDocumentId(id, "Identificador do item");
  const ref = db.collection("inventory_items").doc(id);
  if (!(await ref.get()).exists) {
    throw new HttpsError("not-found", "Item de estoque nao encontrado.");
  }
  const now = admin.firestore.FieldValue.serverTimestamp();
  await ref.set({
    active: false,
    status: "inactive",
    deleted_at: now,
    deleted_by: caller.uid,
    delete_reason: reason,
    deleted_reason: reason,
    updated_at: now,
    audit_trail: admin.firestore.FieldValue.arrayUnion(
      auditEntry("deleted", caller, reason),
    ),
  }, {merge: true});
  await db.collection("auditLogs").doc().set({
    action: "inventory_item_archived",
    entity_type: "inventory_item",
    entity_id: id,
    summary: `Item de estoque arquivado: ${id}`,
    actor: caller,
    metadata: {reason},
    source: "functions",
    performed_at: now,
    createdAt: now,
  });
  return {id, archived: true};
});

export const adminCreateInventoryMovement = onCall({region}, async (request) => {
  const caller = await requireAccessPermission(request.auth, "inventory", "create");
  const data = request.data as JsonMap;
  const payload = (data.payload ?? {}) as JsonMap;
  const itemId = requiredString(payload, "itemId");
  assertDocumentId(itemId, "Identificador do item");
  const type = requiredString(payload, "type");
  const quantity = parseMovementQuantity(type, payload.quantity);
  const delta = movementDelta(type, quantity);
  const reason = requiredString(payload, "reason");
  const itemRef = db.collection("inventory_items").doc(itemId);
  const now = admin.firestore.FieldValue.serverTimestamp();

  return db.runTransaction(async (transaction) => {
    const itemSnap = await transaction.get(itemRef);
    if (!itemSnap.exists) {
      throw new HttpsError("not-found", "Item de estoque nao encontrado.");
    }
    const item = itemSnap.data() ?? {};
    const active = item.active !== false && item.deleted_at == null;
    if (!active) {
      throw new HttpsError("failed-precondition", "Item arquivado nao aceita movimentacao.");
    }
    const before = optionalNumberValue(item.current_quantity) ?? 0;
    const after = before + delta;
    if (after < 0) {
      throw new HttpsError("failed-precondition", "Movimentacao deixaria o estoque negativo.");
    }
    const minimumQuantity = optionalNumberValue(item.minimum_quantity) ?? 0;
    const status = inventoryItemStatus(
      after,
      minimumQuantity,
      stringValue(item.expiration_date),
      active,
    );
    const movementRef = db.collection("inventory_movements").doc();
    const itemName = stringValue(item.name) ?? itemId;
    const unit = stringValue(item.unit) ?? requiredString(payload, "unit");
    const movement: JsonMap = {
      id: movementRef.id,
      item_id: itemId,
      item_name: itemName,
      type: normalizedKey(type),
      quantity,
      delta,
      unit,
      reason,
      balance_before: before,
      balance_after: after,
      category_id: stringValue(item.category_id) ?? null,
      category_name: stringValue(item.category_name) ?? null,
      performed_by_ra: caller.ra,
      performed_by_name: caller.name,
      performed_by_uid: caller.uid,
      performed_at: now,
      related_dog_id: optionalString(payload, "relatedDogId"),
      related_dog_name: optionalString(payload, "relatedDogName"),
      related_user_ra: optionalString(payload, "relatedUserRa"),
      related_user_name: optionalString(payload, "relatedUserName"),
      related_occurrence_id: optionalString(payload, "relatedOccurrenceId"),
      related_training_session_id: optionalString(payload, "relatedTrainingSessionId"),
      lot: optionalString(payload, "lot"),
      expiration_date: optionalString(payload, "expirationDate"),
      document_url: optionalString(payload, "documentUrl"),
      storage_path: optionalString(payload, "storagePath"),
      notes: optionalString(payload, "notes"),
      created_at: now,
      audit_trail: [auditEntry("created", caller)],
    };
    transaction.set(movementRef, movement);
    transaction.set(itemRef, {
      current_quantity: after,
      status,
      last_movement_at: now,
      last_movement_type: normalizedKey(type),
      updated_at: now,
      audit_trail: admin.firestore.FieldValue.arrayUnion(
        auditEntry(`movement_${normalizedKey(type)}`, caller, reason),
      ),
    }, {merge: true});
    transaction.set(db.collection("auditLogs").doc(), {
      action: "inventory_movement_created",
      entity_type: "inventory_item",
      entity_id: itemId,
      summary: `Movimentacao de estoque: ${type} ${quantity} ${unit} em ${itemName}`,
      actor: caller,
      metadata: {
        item_id: itemId,
        movement_id: movementRef.id,
        type: normalizedKey(type),
        quantity,
        delta,
        balance_before: before,
        balance_after: after,
      },
      source: "functions",
      performed_at: now,
      createdAt: now,
    });
    return {
      id: movementRef.id,
      itemId,
      balance_before: before,
      balance_after: after,
      status,
    };
  });
});

export const setK9InstructorRole = onCall({region}, async (request) => {
  const caller = await requireAccessPermission(request.auth, "access", "edit");
  const data = request.data as JsonMap;
  const ra = requiredString(data, "ra");
  const enabled = boolValue(data.enabled);
  const userRef = db.collection("users").doc(ra);
  const userSnap = await userRef.get();
  if (!userSnap.exists) {
    throw new HttpsError("not-found", "Usuario nao encontrado.");
  }

  const userData = userSnap.data() ?? {};
  const uidFromDoc = stringValue(userData.auth_uid) ?? stringValue(userData.authUid) ?? stringValue(userData.uid);
  const email = stringValue(userData.email) ?? emailForRa(ra);
  let userRecord: admin.auth.UserRecord;
  if (uidFromDoc) {
    userRecord = await admin.auth().getUser(uidFromDoc);
  } else {
    userRecord = await admin.auth().getUserByEmail(email);
  }

  const existingClaims = userRecord.customClaims ?? {};
  const roles = new Set<string>(Array.isArray(existingClaims.roles) ? existingClaims.roles.map(String) : []);
  if (enabled) {
    roles.add("instrutor_k9");
  } else {
    roles.delete("instrutor_k9");
  }
  const nextClaims: JsonMap = {
    ...existingClaims,
    roles: Array.from(roles),
  };
  if (enabled) {
    nextClaims.role = "instrutor_k9";
    nextClaims.instrutor_k9 = true;
    nextClaims.training_role = "instrutor_k9";
    nextClaims.training_instructor = true;
  } else {
    delete nextClaims.instrutor_k9;
    delete nextClaims.training_role;
    delete nextClaims.training_instructor;
    if (nextClaims.role === "instrutor_k9") delete nextClaims.role;
  }

  await admin.auth().setCustomUserClaims(userRecord.uid, nextClaims);
  await userRef.set({
    auth_uid: userRecord.uid,
    email,
    is_k9_instructor: enabled,
    training_role: enabled ? "instrutor_k9" : null,
    claim_role: enabled ? "instrutor_k9" : null,
    claim_refresh_required: true,
    claim_updated_at: admin.firestore.FieldValue.serverTimestamp(),
    updated_at: admin.firestore.FieldValue.serverTimestamp(),
    audit_trail: admin.firestore.FieldValue.arrayUnion(auditEntry(
      enabled ? "k9_instructor_role_granted" : "k9_instructor_role_revoked",
      caller,
    )),
  }, {merge: true});

  return {
    ra,
    uid: userRecord.uid,
    enabled,
    token_refresh_required: true,
  };
});

interface TrainingMilestoneSnapshot {
  id: string;
  order: number;
  label: string;
  required: boolean;
}

interface TrainingModuleSnapshot {
  id: string;
  order: number;
  name: string;
  milestones: TrainingMilestoneSnapshot[];
}

function numberValue(value: unknown, fallback = 0): number {
  if (typeof value === "number" && Number.isFinite(value)) return value;
  if (typeof value === "string") {
    const parsed = Number(value);
    if (Number.isFinite(parsed)) return parsed;
  }
  return fallback;
}

function errorMessage(error: unknown): string {
  return error instanceof Error ? error.message : String(error);
}

function trainingDecisionCaller(request: JsonMap): CallerIdentity {
  const ra = stringValue(request.decision_by) ?? "instrutor_k9";
  const uid = stringValue(request.decision_by_uid) ?? ra;
  const email = stringValue(request.decision_by_email) ?? emailForRa(ra);
  return {
    uid,
    email,
    ra,
    name: stringValue(request.decision_by_name) ?? ra,
  };
}

function achievementFor(progress: JsonMap, moduleId: string, milestoneId: string): JsonMap | undefined {
  const achievedByModule = isPlainObject(progress.achieved_milestones) ?
    progress.achieved_milestones[moduleId] :
    undefined;
  if (!isPlainObject(achievedByModule)) return undefined;
  const achievement = achievedByModule[milestoneId];
  return isPlainObject(achievement) ? achievement : undefined;
}

async function trainingProgramSnapshot(
  transaction: admin.firestore.Transaction,
  modality: string,
): Promise<{program: JsonMap; modules: TrainingModuleSnapshot[]}> {
  const programRef = db.collection("training_programs").doc(modality);
  const programSnap = await transaction.get(programRef);
  if (!programSnap.exists) {
    throw new HttpsError("not-found", "Curriculo de treino nao encontrado.");
  }

  const modulesSnap = await transaction.get(programRef.collection("modules").orderBy("order"));
  const modules: TrainingModuleSnapshot[] = [];
  for (const moduleDoc of modulesSnap.docs) {
    const moduleData = moduleDoc.data();
    if (moduleData.active === false) continue;
    const milestonesSnap = await transaction.get(moduleDoc.ref.collection("milestones").orderBy("order"));
    const milestones = milestonesSnap.docs
      .map((milestoneDoc) => {
        const milestoneData = milestoneDoc.data();
        if (milestoneData.active === false) return undefined;
        return {
          id: milestoneDoc.id,
          order: numberValue(milestoneData.order),
          label: stringValue(milestoneData.label) ?? milestoneDoc.id,
          required: milestoneData.required !== false,
        };
      })
      .filter((item): item is TrainingMilestoneSnapshot => item !== undefined)
      .sort((a, b) => a.order - b.order);
    modules.push({
      id: moduleDoc.id,
      order: numberValue(moduleData.order),
      name: stringValue(moduleData.name) ?? moduleDoc.id,
      milestones,
    });
  }
  modules.sort((a, b) => a.order - b.order);
  return {
    program: programSnap.data() ?? {},
    modules,
  };
}

async function specialtyRefForTraining(
  transaction: admin.firestore.Transaction,
  dogId: string,
  modality: string,
): Promise<{ref: admin.firestore.DocumentReference; exists: boolean}> {
  const collection = db.collection("dogs").doc(dogId).collection("specialties");
  const existing = await transaction.get(collection.where("type", "==", modality).limit(1));
  if (!existing.empty) {
    return {
      ref: existing.docs[0].ref,
      exists: true,
    };
  }
  return {
    ref: collection.doc(modality),
    exists: false,
  };
}

function completedModuleSnapshot(
  request: JsonMap,
  module: TrainingModuleSnapshot,
  progress: JsonMap,
  completedAt: admin.firestore.Timestamp,
): JsonMap {
  const programVersion = numberValue(request.program_version, 1);
  const caller = trainingDecisionCaller(request);
  return {
    module_id: module.id,
    module_order: module.order,
    module_name: module.name,
    program_version: programVersion,
    completed_at: completedAt,
    completed_by: caller.ra,
    completed_by_uid: caller.uid,
    milestones: module.milestones.map((milestone) => {
      const achievement = achievementFor(progress, module.id, milestone.id);
      return {
        milestone_id: milestone.id,
        order: milestone.order,
        label: milestone.label,
        required: milestone.required,
        achieved: achievement?.achieved === true,
        achieved_at: achievement?.achieved_at ?? null,
        achieved_by: stringValue(achievement?.achieved_by) ?? null,
        program_version: programVersion,
      };
    }),
  };
}

async function notifyK9Instructors(requestId: string, request: JsonMap): Promise<void> {
  const recipients = new Set<string>();
  const [byFlag, byRole] = await Promise.all([
    db.collection("users").where("is_k9_instructor", "==", true).get(),
    db.collection("users").where("training_role", "==", "instrutor_k9").get(),
  ]);
  for (const doc of [...byFlag.docs, ...byRole.docs]) {
    const ra = stringValue(doc.data().ra) ?? doc.id;
    if (ra) recipients.add(ra);
  }

  if (recipients.size === 0) {
    logger.warn("Nenhum Instrutor K9 encontrado para notificacao de promocao.", {requestId});
    return;
  }

  const batch = db.batch();
  for (const ra of recipients) {
    batch.set(
      db.collection("notifications").doc(ra).collection("items").doc(),
      trainingNotificationPayload("training_promotion_requested", requestId, request),
    );
  }
  await batch.commit();
}

async function notifyPromotionRequester(
  type: "training_promotion_approved" | "training_promotion_rejected",
  requestId: string,
  request: JsonMap,
): Promise<void> {
  const requesterRa = stringValue(request.requester_ra);
  if (!requesterRa) {
    logger.warn("Solicitacao de promocao sem requester_ra.", {requestId});
    return;
  }
  await db.collection("notifications").doc(requesterRa).collection("items").doc().set(
    trainingNotificationPayload(type, requestId, request),
  );
}

async function applyApprovedTrainingPromotion(requestId: string, request: JsonMap): Promise<void> {
  await db.runTransaction(async (transaction) => {
    const requestRef = db.collection("promotion_requests").doc(requestId);
    const requestSnap = await transaction.get(requestRef);
    if (!requestSnap.exists) {
      throw new HttpsError("not-found", "Solicitacao de evolucao nao encontrada.");
    }

    const currentRequest = requestSnap.data() ?? {};
    if (currentRequest.status !== "approved" || currentRequest.processed_at) {
      return;
    }

    const dogId = requiredString(currentRequest, "dog_id");
    const modality = requiredString(currentRequest, "modality");
    const moduleId = requiredString(currentRequest, "module_id");
    const progressRef = db.collection("dogs").doc(dogId).collection("training").doc(modality);
    const progressSnap = await transaction.get(progressRef);
    if (!progressSnap.exists) {
      throw new HttpsError("failed-precondition", "Progresso de treino nao encontrado.");
    }
    const progress = progressSnap.data() ?? {};
    if (progress.status === "operational") {
      throw new HttpsError("failed-precondition", "Cao ja esta operacional nesta modalidade.");
    }

    const {program, modules} = await trainingProgramSnapshot(transaction, modality);
    if (modules.length === 0) {
      throw new HttpsError("failed-precondition", "Curriculo sem modulos ativos.");
    }
    const requestedProgramVersion = numberValue(currentRequest.program_version, 1);
    const activeProgramVersion = numberValue(program.version, requestedProgramVersion);
    if (activeProgramVersion !== requestedProgramVersion) {
      throw new HttpsError("failed-precondition", "Curriculo mudou desde a solicitacao. Gere nova rodada.");
    }
    const moduleIndex = modules.findIndex((item) => item.id === moduleId);
    if (moduleIndex < 0) {
      throw new HttpsError("not-found", "Modulo aprovado nao existe no curriculo ativo.");
    }
    const module = modules[moduleIndex];
    const currentModuleId =
      stringValue(progress.current_module) ??
      stringValue(progress.current_module_id) ??
      modules[0].id;
    if (currentModuleId !== module.id) {
      throw new HttpsError("failed-precondition", "Somente o modulo atual pode ser aprovado.");
    }

    const missingRequired = module.milestones.filter((milestone) =>
      milestone.required && achievementFor(progress, module.id, milestone.id)?.achieved !== true,
    );
    if (missingRequired.length > 0) {
      throw new HttpsError("failed-precondition", "Marcos obrigatorios ainda nao atingidos.");
    }

    const completedAt = admin.firestore.Timestamp.now();
    const completedIds = new Set<string>(stringArray(progress.completed_module_ids));
    completedIds.add(module.id);
    const completedModules = mapArray(progress.completed_modules)
      .filter((item) => stringValue(item.module_id) !== module.id);
    completedModules.push(completedModuleSnapshot(currentRequest, module, progress, completedAt));

    const nextModule = moduleIndex < modules.length - 1 ? modules[moduleIndex + 1] : undefined;
    const isOperational = nextModule === undefined;
    const status = isOperational ? "operational" : "in_formation";
    const caller = trainingDecisionCaller(currentRequest);
    const entry = auditEntry("training_module_promotion_approved", caller);
    const programVersion = activeProgramVersion;
    const progressPercent = isOperational ? 100 : Math.round((completedIds.size / modules.length) * 100);

    const {ref: specialtyRef, exists: specialtyExists} = await specialtyRefForTraining(transaction, dogId, modality);
    const specialtyPayload: JsonMap = {
      type: modality,
      name: stringValue(program.name) ?? stringValue(currentRequest.modality) ?? modality,
      status,
      state: status,
      program_version: programVersion,
      current_module: nextModule?.id ?? null,
      current_phase: nextModule?.id ?? null,
      progress_percentage: progressPercent,
      updated_at: admin.firestore.FieldValue.serverTimestamp(),
      audit_trail: specialtyExists ? admin.firestore.FieldValue.arrayUnion(entry) : [entry],
    };
    if (!specialtyExists) {
      specialtyPayload.created_at = admin.firestore.FieldValue.serverTimestamp();
      specialtyPayload.started_at = admin.firestore.FieldValue.serverTimestamp();
    }
    if (isOperational) {
      specialtyPayload.operational_since = completedAt;
    }

    transaction.set(progressRef, {
      modality,
      status,
      current_module: nextModule?.id ?? null,
      current_module_id: nextModule?.id ?? null,
      program_version: programVersion,
      completed_module_ids: Array.from(completedIds),
      completed_modules: completedModules,
      operational_since: isOperational ? completedAt : null,
      updated_at: admin.firestore.FieldValue.serverTimestamp(),
      audit_trail: admin.firestore.FieldValue.arrayUnion(entry),
    }, {merge: true});

    transaction.set(specialtyRef, specialtyPayload, {merge: true});
    transaction.set(
      db.collection("notifications")
        .doc(requiredString(currentRequest, "requester_ra"))
        .collection("items")
        .doc(),
      trainingNotificationPayload("training_promotion_approved", requestId, currentRequest),
    );
    transaction.set(requestRef, {
      processed_at: admin.firestore.FieldValue.serverTimestamp(),
      processing_status: "completed",
      resulting_status: status,
      next_module: nextModule?.id ?? null,
      operational: isOperational,
    }, {merge: true});
  });
}

export const onTrainingPromotionRequestCreated = onDocumentCreated(
  {
    document: "promotion_requests/{requestId}",
    region,
  },
  async (event) => {
    const snapshot = event.data;
    if (!snapshot) return;
    const request = snapshot.data() ?? {};
    if (request.status !== "pending") return;
    if (request.direct_instructor === true) return;
    await notifyK9Instructors(event.params.requestId, request);
  },
);

export const onTrainingPromotionRequestUpdated = onDocumentUpdated(
  {
    document: "promotion_requests/{requestId}",
    region,
  },
  async (event) => {
    const change = event.data;
    if (!change) return;
    const before = change.before.data() ?? {};
    const after = change.after.data() ?? {};
    if (before.status !== "pending") return;

    if (after.status === "approved") {
      let processingStatus = "completed";
      try {
        await applyApprovedTrainingPromotion(event.params.requestId, after);
      } catch (error) {
        processingStatus = "error";
        logger.error("Falha ao aplicar promocao de treino.", {
          requestId: event.params.requestId,
          error: errorMessage(error),
        });
        await change.after.ref.set({
          processed_at: admin.firestore.FieldValue.serverTimestamp(),
          processing_status: "error",
          processing_error: errorMessage(error),
        }, {merge: true});
      }
      await resolveTrainingPromotionRequestNotifications(
        event.params.requestId,
        "training_promotion_approved",
        {
          request_id: event.params.requestId,
          status: "approved",
          processing_status: processingStatus,
        },
      );
      return;
    }

    if (after.status === "rejected") {
      await notifyPromotionRequester("training_promotion_rejected", event.params.requestId, after);
      await change.after.ref.set({
        processed_at: admin.firestore.FieldValue.serverTimestamp(),
        processing_status: "completed",
      }, {merge: true});
      await resolveTrainingPromotionRequestNotifications(
        event.params.requestId,
        "training_promotion_rejected",
        {
          request_id: event.params.requestId,
          status: "rejected",
        },
      );
    }
  },
);

function dogDisplayName(dogId: string, dog: JsonMap): string {
  return stringValue(dog.name) ?? stringValue(dog.nome) ?? dogId;
}

function handlerRaFromDogOrProgress(dog: JsonMap, progress: JsonMap): string | undefined {
  return stringValue(dog.conductorRa) ??
    stringValue(dog.conductor_ra) ??
    stringValue(dog.handler_ra) ??
    stringValue(dog.handlerId) ??
    stringValue(dog.handler_id) ??
    stringValue(dog.current_handler_ra) ??
    stringValue(dog.primary_handler_ra) ??
    stringValue(progress.conductor_ra) ??
    stringValue(progress.handler_ra) ??
    stringValue(progress.handlerId) ??
    stringValue(progress.handler_id);
}

async function activeShiftHandlersForDog(dogId: string): Promise<string[]> {
  const recipients = new Set<string>();
  const byServiceDog = await db
    .collection("active_shifts")
    .where("service_dog_id", "==", dogId)
    .where("status", "==", "active")
    .get();
  const byDogId = await db
    .collection("active_shifts")
    .where("dogId", "==", dogId)
    .where("status", "==", "active")
    .get();
  for (const doc of [...byServiceDog.docs, ...byDogId.docs]) {
    const data = doc.data();
    const ra = stringValue(data.handlerId) ??
      stringValue(data.handler_id) ??
      stringValue(data.ra) ??
      doc.id;
    if (ra) recipients.add(ra);
  }
  return Array.from(recipients).sort();
}

async function bonusMilestoneRecipients(
  dogId: string,
  dog: JsonMap,
  progress: JsonMap,
): Promise<string[]> {
  const recipients = new Set<string>();
  const fromDog = handlerRaFromDogOrProgress(dog, progress);
  if (fromDog) recipients.add(fromDog);
  for (const ra of await activeShiftHandlersForDog(dogId)) {
    recipients.add(ra);
  }
  return Array.from(recipients).sort();
}

export const onTrainingProgramMilestoneCreated = onDocumentCreated(
  {
    document: "training_programs/{programId}/modules/{moduleId}/milestones/{milestoneId}",
    region,
  },
  async (event) => {
    const snapshot = event.data;
    if (!snapshot) return;
    const milestone = snapshot.data() ?? {};
    if (milestone.active === false) return;

    const {programId, moduleId, milestoneId} = event.params;
    const [programSnap, moduleSnap, dogsSnap] = await Promise.all([
      db.collection("training_programs").doc(programId).get(),
      db.collection("training_programs").doc(programId).collection("modules").doc(moduleId).get(),
      db.collection("dogs").get(),
    ]);
    const program = programSnap.data() ?? {};
    const moduleData = moduleSnap.data() ?? {};
    if (program.active === false || moduleData.active === false) return;

    const milestoneLabel = stringValue(milestone.label) ?? milestoneId;
    const moduleName = stringValue(moduleData.name) ?? moduleId;
    const programVersion = numberValue(program.version, numberValue(milestone.program_version, 1));
    let batch = db.batch();
    let writes = 0;

    async function commitIfNeeded(force = false): Promise<void> {
      if (writes === 0) return;
      if (!force && writes < 400) return;
      await batch.commit();
      batch = db.batch();
      writes = 0;
    }

    for (const dogDoc of dogsSnap.docs) {
      const dog = dogDoc.data() ?? {};
      if (dog.deleted_at || dog.active === false) continue;

      const progressRef = dogDoc.ref.collection("training").doc(programId);
      const progressSnap = await progressRef.get();
      if (!progressSnap.exists) continue;
      const progress = progressSnap.data() ?? {};
      if (progress.status !== "operational") continue;

      const bonusId = `${moduleId}__${milestoneId}`;
      const bonusSnap = await progressRef.collection("bonus_milestones").doc(bonusId).get();
      if (bonusSnap.exists) continue;

      const recipients = await bonusMilestoneRecipients(dogDoc.id, dog, progress);
      if (recipients.length === 0) {
        logger.warn("Cao operacional sem condutor para notificacao de marco-bonus.", {
          dogId: dogDoc.id,
          modality: programId,
          moduleId,
          milestoneId,
        });
        continue;
      }

      for (const ra of recipients) {
        batch.set(
          db.collection("notifications").doc(ra).collection("items").doc(),
          trainingBonusNotificationPayload({
            dogId: dogDoc.id,
            dogName: dogDisplayName(dogDoc.id, dog),
            modality: programId,
            moduleId,
            moduleName,
            milestoneId,
            milestoneLabel,
            programVersion,
          }),
        );
        writes++;
        await commitIfNeeded();
      }
    }

    await commitIfNeeded(true);
  },
);

function activeCrewMemberCount(members: JsonMap[]): number {
  return members.filter((member) =>
    ["titular", "accepted", "pending"].includes(String(member.status ?? "")),
  ).length;
}

export const inviteVehicleCrewMember = onCall({region}, async (request) => {
  const caller = requireAuth(request.auth);
  const data = request.data as JsonMap;
  const crewId = requiredString(data, "crew_id");
  const handlerId = requiredString(data, "handler_id");
  const crewRef = db.collection("vehicle_crews").doc(crewId);
  const memberRef = crewRef.collection("members").doc(handlerId);
  const targetUserRef = db.collection("users").doc(handlerId);

  await db.runTransaction(async (transaction) => {
    const [crewSnap, targetUserSnap] = await Promise.all([
      transaction.get(crewRef),
      transaction.get(targetUserRef),
    ]);
    if (!crewSnap.exists) {
      throw new HttpsError("not-found", "Guarnição não encontrada.");
    }
    if (!targetUserSnap.exists) {
      throw new HttpsError("not-found", "Condutor nao cadastrado.");
    }
    const crew = crewSnap.data() ?? {};
    const targetUser = targetUserSnap.data() ?? {};
    if (crew.active !== true) {
      throw new HttpsError("failed-precondition", "Guarnição inativa.");
    }
    if (!emailMatchesRa(caller.email, crew.titular_handler_id)) {
      throw new HttpsError("permission-denied", "Somente o titular convida parceiros.");
    }
    if (handlerId === caller.ra) {
      throw new HttpsError("invalid-argument", "O titular já pertence à guarnição.");
    }

    const membersSnap = await transaction.get(crewRef.collection("members"));
    const members = membersSnap.docs.map((doc) => doc.data());
    const existingMember = membersSnap.docs.find((doc) => doc.id === handlerId)?.data();
    if (existingMember && ["titular", "accepted", "pending"].includes(String(existingMember.status ?? ""))) {
      throw new HttpsError("already-exists", "Condutor ja esta vinculado ou convidado.");
    }
    const capacity = Number(crew.crew_size ?? 1);
    if (activeCrewMemberCount(members) >= capacity) {
      throw new HttpsError("resource-exhausted", "Guarnição completa.");
    }

    transaction.set(memberRef, {
      handler_id: handlerId,
      auth_uid: targetUser.auth_uid ?? null,
      handler_email: targetUser.email ?? emailForRa(handlerId),
      role: "integrante",
      status: "pending",
      invited_at: admin.firestore.FieldValue.serverTimestamp(),
      invited_by: caller.ra,
      invited_by_uid: caller.uid,
      updated_at: admin.firestore.FieldValue.serverTimestamp(),
    }, {merge: true});
    transaction.update(crewRef, {
      updated_at: admin.firestore.FieldValue.serverTimestamp(),
    });
    transaction.set(
      db.collection("notifications").doc(handlerId).collection("items").doc(),
      crewNotificationPayload(
        "vehicle_crew_invitation",
        crewId,
        String(crew.vehicle_label ?? crewId),
        crewId,
      ),
    );
    transaction.set(db.collection("auditLogs").doc(), {
      action: "vehicle_crew_member_invited",
      entity_type: "vehicle_crew",
      entity_id: crewId,
      summary: `Convite enviado para ${handlerId}`,
      actor: caller,
      metadata: {handler_id: handlerId},
      source: "functions",
      performed_at: admin.firestore.FieldValue.serverTimestamp(),
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
    });
  });
});

export const respondVehicleCrewInvitation = onCall({region}, async (request) => {
  const caller = requireAuth(request.auth);
  const data = request.data as JsonMap;
  const crewId = requiredString(data, "crew_id");
  const accept = data.accept === true;
  const reason = stringValue(data.reason);
  if (!accept && !reason) {
    throw new HttpsError("invalid-argument", "Informe o motivo da recusa.");
  }

  const crewRef = db.collection("vehicle_crews").doc(crewId);
  const memberRef = crewRef.collection("members").doc(caller.ra);
  const activeShiftRef = db.collection("active_shifts").doc(caller.ra);

  await db.runTransaction(async (transaction) => {
    const [crewSnap, memberSnap, activeShiftSnap] = await Promise.all([
      transaction.get(crewRef),
      transaction.get(memberRef),
      transaction.get(activeShiftRef),
    ]);
    if (!crewSnap.exists || !memberSnap.exists) {
      throw new HttpsError("not-found", "Convite de guarnição não encontrado.");
    }
    const crew = crewSnap.data() ?? {};
    const member = memberSnap.data() ?? {};
    if (member.status !== "pending") {
      throw new HttpsError("failed-precondition", "Convite ja respondido.");
    }
    if (!emailMatchesRa(caller.email, caller.ra) ||
        (member.auth_uid && member.auth_uid !== caller.uid)) {
      throw new HttpsError("permission-denied", "Convite pertence a outro condutor.");
    }

    if (accept) {
      const membersSnap = await transaction.get(crewRef.collection("members"));
      const members = membersSnap.docs.map((doc) => doc.data());
      const capacity = Number(crew.crew_size ?? 1);
      const acceptedCount = members.filter((item) =>
        ["titular", "accepted"].includes(String(item.status ?? "")),
      ).length;
      if (acceptedCount >= capacity) {
        throw new HttpsError("resource-exhausted", "Guarnição completa.");
      }

      const activeShiftIsActive = activeShiftSnap.exists && activeShiftSnap.data()?.status === "active";
      const activeShift = activeShiftIsActive ? activeShiftSnap.data() ?? {} : {};
      const otherCrew = stringValue(activeShift.vehicle_crew_id ?? activeShift.crew_id);
      if (activeShiftIsActive && otherCrew && otherCrew !== crewId) {
        throw new HttpsError("failed-precondition", "Condutor ja esta em outra viatura.");
      }
      await resolveUserActionNotificationsInTransaction(transaction, caller.ra, {
        type: "vehicle_crew_invitation",
        additionalData: crewId,
        resolutionAction: accept ? "vehicle_crew_invitation_accepted" : "vehicle_crew_invitation_declined",
        actor: caller,
        metadata: {
          crew_id: crewId,
          result: "accepted",
        },
      });
      const vehicleFields = {
        vehicle_id: crew.vehicle_id ?? crewId,
        vehicle_label: crew.vehicle_label ?? crewId,
        vehicle_prefix: crew.vehicle_prefix ?? null,
        vehicle_model: crew.vehicle_model ?? null,
        vehicle_unit: crew.vehicle_unit ?? null,
        vehicle_joined_at: admin.firestore.FieldValue.serverTimestamp(),
        vehicle_crew_id: crewId,
        crew_id: crewId,
        crew_role: "integrante",
        crew_status: "accepted",
        service_dog_id: crew.service_dog_id ?? activeShift.service_dog_id ?? activeShift.dogId ?? "",
        dogId: crew.service_dog_id ?? activeShift.service_dog_id ?? activeShift.dogId ?? "",
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      };
      if (activeShiftIsActive) {
        transaction.set(activeShiftRef, vehicleFields, {merge: true});
        const shiftId = stringValue(activeShift.shiftId);
        if (shiftId) {
          transaction.set(db.collection("shift_logs").doc(shiftId), {
            ...vehicleFields,
            currentDogId: vehicleFields.dogId,
          }, {merge: true});
        }
      }
      transaction.set(memberRef, {
        status: "accepted",
        auth_uid: member.auth_uid ?? caller.uid,
        handler_email: member.handler_email ?? caller.email ?? emailForRa(caller.ra),
        responded_at: admin.firestore.FieldValue.serverTimestamp(),
        updated_at: admin.firestore.FieldValue.serverTimestamp(),
      }, {merge: true});
    } else {
      await resolveUserActionNotificationsInTransaction(transaction, caller.ra, {
        type: "vehicle_crew_invitation",
        additionalData: crewId,
        resolutionAction: "vehicle_crew_invitation_declined",
        actor: caller,
        metadata: {
          crew_id: crewId,
          result: "declined",
          reason: reason ?? null,
        },
      });
      transaction.set(memberRef, {
        status: "declined",
        decline_reason: reason,
        responded_at: admin.firestore.FieldValue.serverTimestamp(),
        updated_at: admin.firestore.FieldValue.serverTimestamp(),
      }, {merge: true});
    }

    transaction.update(crewRef, {
      updated_at: admin.firestore.FieldValue.serverTimestamp(),
    });
    const titularRa = stringValue(crew.titular_handler_id);
    if (titularRa) {
      transaction.set(
        db.collection("notifications").doc(titularRa).collection("items").doc(),
        crewNotificationPayload(
          accept ? "vehicle_crew_invitation_accepted" : "vehicle_crew_invitation_declined",
          crewId,
          String(crew.vehicle_label ?? crewId),
          crewId,
        ),
      );
    }
    transaction.set(db.collection("auditLogs").doc(), {
      action: accept ? "vehicle_crew_invitation_accepted" : "vehicle_crew_invitation_declined",
      entity_type: "vehicle_crew",
      entity_id: crewId,
      summary: accept ? `Convite aceito por ${caller.ra}` : `Convite recusado por ${caller.ra}`,
      actor: caller,
      metadata: {
        handler_id: caller.ra,
        reason: reason ?? null,
      },
      source: "functions",
      performed_at: admin.firestore.FieldValue.serverTimestamp(),
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
    });
  });
});

export const sealOccurrenceV4 = onCall({region}, async (request) => {
  const caller = requireAuth(request.auth);
  const data = request.data as JsonMap;
  const occurrenceId = requiredString(data, "occurrence_id");
  const withPending = data.with_pending === true;
  const finalReport = requiredString(data, "final_report");
  const occurrenceRef = db.collection("occurrences").doc(occurrenceId);

  return db.runTransaction(async (transaction) => {
    const occurrenceSnap = await transaction.get(occurrenceRef);
    if (!occurrenceSnap.exists) {
      throw new HttpsError("not-found", "Ocorrência não encontrada.");
    }

    const occurrence = occurrenceSnap.data() ?? {};
    if (!isParticipant(occurrence, caller)) {
      throw new HttpsError("permission-denied", "Usuário fora da equipe da ocorrência.");
    }

    const currentStatus = String(occurrence.status ?? "in_progress");
    const signaturesSnap = await transaction.get(occurrenceRef.collection("signatures"));
    const signatures = signaturesSnap.docs.map((doc) => ({id: doc.id, ...doc.data()}));

    if (withPending) {
      const deadline = occurrence.signature_deadline;
      if (!isPrimaryHandler(occurrence, caller)) {
        throw new HttpsError("permission-denied", "Somente o relator finaliza com pendencia.");
      }
      if (currentStatus !== "awaiting_signatures") {
        throw new HttpsError("failed-precondition", "Ocorrência não está aguardando assinaturas.");
      }
      if (!isTimestamp(deadline) || deadline.toMillis() > Date.now()) {
        throw new HttpsError("failed-precondition", "Prazo de assinatura ainda não venceu.");
      }
    } else if (currentStatus === "awaiting_signatures") {
      if (!hasAllSignatures(occurrence, signatures)) {
        throw new HttpsError("failed-precondition", "Ainda ha assinaturas pendentes.");
      }
    } else if (currentStatus === "in_progress" || currentStatus === "finalizing") {
      if (!isPrimaryHandler(occurrence, caller)) {
        throw new HttpsError("permission-denied", "Somente o relator sela ocorrência sem rodada de assinatura.");
      }
    } else {
      throw new HttpsError("failed-precondition", "Estado da ocorrência não permite selamento.");
    }

    const eventsSnap = await transaction.get(occurrenceRef.collection("events"));
    const participationsSnap = await transaction.get(occurrenceRef.collection("participations"));
    const correctionSnap = await transaction.get(occurrenceRef.collection("correction_requests"));
    const enrichedOccurrence: JsonMap = {
      ...occurrence,
      final_report: finalReport,
      results: Array.isArray(data.results) ? data.results : occurrence.results ?? [],
      details: data.details ?? occurrence.details ?? null,
      finalization_photos: Array.isArray(data.finalization_photos) ?
        data.finalization_photos :
        occurrence.finalization_photos ?? [],
      finalization_photo_hashes: Array.isArray(data.finalization_photo_hashes) ?
        data.finalization_photo_hashes :
        occurrence.finalization_photo_hashes ?? [],
      hash_version: 4,
    };

    const events = eventsSnap.docs.map((doc) => ({id: doc.id, data: doc.data()}));
    const participations = participationsSnap.docs.map((doc) => ({id: doc.id, ...doc.data()}));
    const correctionRequests = correctionSnap.docs.map((doc) => ({id: doc.id, ...doc.data()}));
    const integrityHash = hashPayload(
      buildHashPayloadV4(enrichedOccurrence, events, signatures, participations, correctionRequests),
    );
    const status = withPending ? "finalized_with_pending" : "finalized";
    const entry = auditEntry(status === "finalized" ? "finalized" : "finalized_with_pending", caller);

    transaction.update(occurrenceRef, {
      status,
      finalized_at: admin.firestore.FieldValue.serverTimestamp(),
      integrity_hash: integrityHash,
      hash_version: 4,
      final_report: finalReport,
      results: enrichedOccurrence.results,
      details: enrichedOccurrence.details,
      finalization_photos: enrichedOccurrence.finalization_photos,
      finalization_photo_hashes: enrichedOccurrence.finalization_photo_hashes,
      finalization_draft: admin.firestore.FieldValue.delete(),
      updated_at: admin.firestore.FieldValue.serverTimestamp(),
      audit_trail: admin.firestore.FieldValue.arrayUnion(entry),
    });

    for (const handlerId of teamHandlerIds(occurrence)) {
      const notificationRef = db
        .collection("notifications")
        .doc(handlerId)
        .collection("items")
        .doc();
      transaction.set(
        notificationRef,
        notificationPayload("occurrence_finalized", occurrenceId, enrichedOccurrence, "none", integrityHash),
      );
    }

    return {
      integrity_hash: integrityHash,
      hash_version: 4,
      status,
    };
  });
});

export const closeOccurrenceForSignatures = onCall({region}, async (request) => {
  const caller = requireAuth(request.auth);
  const data = request.data as JsonMap;
  const occurrenceId = requiredString(data, "occurrence_id");
  const finalReport = requiredString(data, "final_report");
  const occurrenceRef = db.collection("occurrences").doc(occurrenceId);
  const requestedResults = Array.isArray(data.results) ? data.results : [];
  const requestedDetails = data.details ?? null;
  const requestedPhotos = Array.isArray(data.finalization_photos) ?
    data.finalization_photos :
    [];
  const requestedPhotoHashes = Array.isArray(data.finalization_photo_hashes) ?
    data.finalization_photo_hashes :
    [];
  const rawDeadlineMinutes = Number(data.signature_deadline_minutes ?? 2880);
  const deadlineMinutes = Number.isFinite(rawDeadlineMinutes) && rawDeadlineMinutes > 0 ?
    Math.round(rawDeadlineMinutes) :
    2880;

  return db.runTransaction(async (transaction) => {
    const occurrenceSnap = await transaction.get(occurrenceRef);
    if (!occurrenceSnap.exists) {
      throw new HttpsError("not-found", "OcorrÃªncia nÃ£o encontrada.");
    }

    const occurrence = occurrenceSnap.data() ?? {};
    const currentStatus = String(occurrence.status ?? "in_progress");
    if (!(currentStatus === "in_progress" || currentStatus === "finalizing")) {
      throw new HttpsError(
        "failed-precondition",
        "SÃ³ Ã© possÃ­vel fechar ocorrÃªncias em andamento ou finalizaÃ§Ã£o.",
      );
    }
    if (!isPrimaryHandler(occurrence, caller)) {
      throw new HttpsError("permission-denied", "Somente o relator fecha para assinaturas.");
    }

    const coSigners = coSignerIds(occurrence);
    if (coSigners.length === 0) {
      throw new HttpsError("failed-precondition", "Nenhum integrante apto para co-assinatura.");
    }

    const round = signatureRound(occurrence);
    const deadline = admin.firestore.Timestamp.fromMillis(
      Date.now() + (deadlineMinutes * 60 * 1000),
    );
    const finalizationPhotos = requestedPhotos.length > 0 ?
      requestedPhotos :
      (Array.isArray(occurrence.finalization_photos) ? occurrence.finalization_photos : []);
    const finalizationPhotoHashes = requestedPhotoHashes.length > 0 ?
      requestedPhotoHashes :
      (Array.isArray(occurrence.finalization_photo_hashes) ?
        occurrence.finalization_photo_hashes :
        []);
    const results = requestedResults.length > 0 ?
      requestedResults :
      (Array.isArray(occurrence.results) ? occurrence.results : []);
    const details = requestedDetails ?? occurrence.details ?? null;
    const entry = auditEntry("closed_for_signatures", caller);

    transaction.update(occurrenceRef, {
      status: "awaiting_signatures",
      signature_request_at: admin.firestore.FieldValue.serverTimestamp(),
      signature_deadline: deadline,
      final_report: finalReport,
      results,
      details,
      finalization_photos: finalizationPhotos,
      finalization_photo_hashes: finalizationPhotoHashes,
      finalization_draft: admin.firestore.FieldValue.delete(),
      signature_round: round,
      signed_handler_ids: [],
      signed_emails: [],
      signed_auth_uids: [],
      updated_at: admin.firestore.FieldValue.serverTimestamp(),
      audit_trail: admin.firestore.FieldValue.arrayUnion(entry),
    });

    for (const handlerId of coSigners) {
      const signatureId = round <= 1 ? handlerId : `round_${round}_${handlerId}`;
      transaction.set(
        occurrenceRef.collection("signatures").doc(signatureId),
        {
          handler_id: handlerId,
          status: "pending",
          signed_at: null,
          signature_method: "biometric",
          signature_hash: "",
          round,
          signature_round: round,
          invalidated_at: null,
          created_at: admin.firestore.FieldValue.serverTimestamp(),
          updated_at: admin.firestore.FieldValue.serverTimestamp(),
        },
        {merge: true},
      );
      transaction.set(
        db.collection("notifications").doc(handlerId).collection("items").doc(),
        notificationPayload(
          "signature_requested",
          occurrenceId,
          occurrence,
          "occurrence_review",
          handlerId,
        ),
      );
    }

    transaction.set(db.collection("auditLogs").doc(), {
      action: "closed_for_signatures",
      entity_type: "occurrence",
      entity_id: occurrenceId,
      summary: "OcorrÃªncia fechada para assinaturas",
      actor: caller,
      metadata: {
        signature_round: round,
        pending_signatures: coSigners,
      },
      source: "functions",
      performed_at: admin.firestore.FieldValue.serverTimestamp(),
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
    });

    return {
      status: "awaiting_signatures",
      signature_round: round,
      pending_signatures: coSigners,
    };
  });
});

export const signOccurrence = onCall({region}, async (request) => {
  const caller = requireAuth(request.auth);
  const data = request.data as JsonMap;
  const occurrenceId = requiredString(data, "occurrence_id");
  const handlerId = stringValue(data.handler_id) ?? caller.ra;
  const signatureMethod = stringValue(data.signature_method) ?? "biometric";
  const signatureHash = stringValue(data.signature_hash) ?? "";
  const occurrenceRef = db.collection("occurrences").doc(occurrenceId);

  return db.runTransaction(async (transaction) => {
    const occurrenceSnap = await transaction.get(occurrenceRef);
    if (!occurrenceSnap.exists) {
      throw new HttpsError("not-found", "OcorrÃªncia nÃ£o encontrada.");
    }

    const occurrence = occurrenceSnap.data() ?? {};
    if (String(occurrence.status ?? "") !== "awaiting_signatures") {
      throw new HttpsError("failed-precondition", "OcorrÃªncia nÃ£o estÃ¡ aguardando assinaturas.");
    }
    if (!coSignerIds(occurrence).includes(handlerId)) {
      throw new HttpsError("permission-denied", "Condutor nÃ£o possui assinatura pendente nesta ocorrÃªncia.");
    }
    if (!canActAsHandler(occurrence, handlerId, caller)) {
      throw new HttpsError("permission-denied", "UsuÃ¡rio autenticado nÃ£o corresponde ao condutor da assinatura.");
    }

    const round = signatureRound(occurrence);
    const signatureId = round <= 1 ? handlerId : `round_${round}_${handlerId}`;
    const signatureRef = occurrenceRef.collection("signatures").doc(signatureId);
    const signaturesSnap = await transaction.get(occurrenceRef.collection("signatures"));
    const existingSignatures: JsonMap[] = signaturesSnap.docs.map((doc) => ({id: doc.id, ...doc.data()}));
    const previousSignature = existingSignatures.find((signature) => signature.id === signatureId);
    if (previousSignature?.["status"] === "signed") {
      await resolveUserActionNotificationsInTransaction(transaction, handlerId, {
        type: "signature_requested",
        occurrenceId,
        resolutionAction: "signature_already_signed",
        actor: caller,
        metadata: {
          occurrence_id: occurrenceId,
          handler_id: handlerId,
          signature_round: round,
        },
      });
      return {
        status: "signed",
        signature_round: round,
        already_signed: true,
      };
    }

    const entry = auditEntry("signature_added", caller);
    const signedEmailSet = new Set([
      emailForRa(handlerId),
      `${handlerId.trim().toLowerCase()}@canilgcm.com`,
      caller.email,
    ].filter((email) => email.length > 0));

    await resolveUserActionNotificationsInTransaction(transaction, handlerId, {
      type: "signature_requested",
      occurrenceId,
      resolutionAction: "signature_added",
      actor: caller,
      metadata: {
        occurrence_id: occurrenceId,
        handler_id: handlerId,
        signature_round: round,
      },
    });

    transaction.set(signatureRef, {
      handler_id: handlerId,
      status: "signed",
      signed_at: admin.firestore.FieldValue.serverTimestamp(),
      signature_method: signatureMethod,
      signature_hash: signatureHash,
      round,
      signature_round: round,
      invalidated_at: null,
      updated_at: admin.firestore.FieldValue.serverTimestamp(),
    }, {merge: true});

    transaction.update(occurrenceRef, {
      signed_handler_ids: admin.firestore.FieldValue.arrayUnion(handlerId),
      signed_emails: admin.firestore.FieldValue.arrayUnion(...Array.from(signedEmailSet)),
      signed_auth_uids: admin.firestore.FieldValue.arrayUnion(caller.uid),
      updated_at: admin.firestore.FieldValue.serverTimestamp(),
      audit_trail: admin.firestore.FieldValue.arrayUnion(entry),
    });

    const primaryRa = stringValue(occurrence.primary_handler_ra ?? occurrence.primary_handler_id);
    if (primaryRa) {
      transaction.set(
        db.collection("notifications").doc(primaryRa).collection("items").doc(),
        notificationPayload(
          "signature_completed",
          occurrenceId,
          occurrence,
          "occurrence_team",
          handlerId,
        ),
      );
    }

    transaction.set(db.collection("auditLogs").doc(), {
      action: "signature_added",
      entity_type: "occurrence",
      entity_id: occurrenceId,
      summary: `Assinatura registrada por ${handlerId}`,
      actor: caller,
      metadata: {
        handler_id: handlerId,
        signature_round: round,
        signature_method: signatureMethod,
      },
      source: "functions",
      performed_at: admin.firestore.FieldValue.serverTimestamp(),
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
    });

    return {
      status: "signed",
      signature_round: round,
    };
  });
});

export const requestOccurrenceCorrection = onCall({region}, async (request) => {
  const caller = requireAuth(request.auth);
  const data = request.data as JsonMap;
  const occurrenceId = requiredString(data, "occurrence_id");
  const reason = requiredString(data, "reason");
  const occurrenceRef = db.collection("occurrences").doc(occurrenceId);

  await db.runTransaction(async (transaction) => {
    const occurrenceSnap = await transaction.get(occurrenceRef);
    if (!occurrenceSnap.exists) {
      throw new HttpsError("not-found", "Ocorrência não encontrada.");
    }
    const occurrence = occurrenceSnap.data() ?? {};
    if (String(occurrence.status ?? "") !== "awaiting_signatures") {
      throw new HttpsError("failed-precondition", "Ocorrência não está aguardando assinaturas.");
    }
    if (!isParticipant(occurrence, caller)) {
      throw new HttpsError("permission-denied", "Usuário fora da equipe da ocorrência.");
    }

    const round = signatureRound(occurrence);
    const signaturesSnap = await transaction.get(occurrenceRef.collection("signatures"));
    const entry = auditEntry("reverted_to_draft", caller, reason);
    const correctionRef = occurrenceRef.collection("correction_requests").doc();

    for (const doc of signaturesSnap.docs) {
      const signature = doc.data();
      const signatureDocRound = Number(signature.round ?? signature.signature_round ?? 1);
      if (signatureDocRound !== round || signature.status === "obsolete") continue;
      transaction.set(doc.ref, {
        status: "obsolete",
        invalidated_at: admin.firestore.FieldValue.serverTimestamp(),
        invalidated_by: caller.ra,
        invalidation_reason: reason,
        updated_at: admin.firestore.FieldValue.serverTimestamp(),
      }, {merge: true});
    }

    transaction.set(correctionRef, {
      id: correctionRef.id,
      round,
      requested_at: admin.firestore.FieldValue.serverTimestamp(),
      requested_by: caller.ra,
      requested_by_uid: caller.uid,
      reason,
      status: "open",
    });
    transaction.update(occurrenceRef, {
      status: "in_progress",
      signature_request_at: null,
      signature_deadline: null,
      finalization_draft: finalizationDraftFromOccurrence(occurrence, reason, round),
      signature_round: round + 1,
      signed_handler_ids: [],
      signed_emails: [],
      signed_auth_uids: [],
      updated_at: admin.firestore.FieldValue.serverTimestamp(),
      audit_trail: admin.firestore.FieldValue.arrayUnion(entry),
    });

    const primaryRa = stringValue(occurrence.primary_handler_ra ?? occurrence.primary_handler_id);
    if (primaryRa) {
      transaction.set(
        db.collection("notifications").doc(primaryRa).collection("items").doc(),
        notificationPayload("correction_requested", occurrenceId, occurrence, "occurrence_review", reason),
      );
    }
  });
});

export const acceptOccurrenceParticipation = onCall({region}, async (request) => {
  const caller = requireAuth(request.auth);
  const data = request.data as JsonMap;
  const occurrenceId = requiredString(data, "occurrence_id");
  const occurrenceRef = db.collection("occurrences").doc(occurrenceId);

  await db.runTransaction(async (transaction) => {
    const occurrenceSnap = await transaction.get(occurrenceRef);
    if (!occurrenceSnap.exists) {
      throw new HttpsError("not-found", "Ocorrencia nao encontrada.");
    }
    const occurrence = occurrenceSnap.data() ?? {};
    if (!(String(occurrence.status ?? "in_progress") === "in_progress" ||
      String(occurrence.status ?? "in_progress") === "finalizing")) {
      throw new HttpsError("failed-precondition", "Participacao so pode ser confirmada com ocorrencia aberta.");
    }
    if (isPrimaryHandler(occurrence, caller)) {
      return {status: "accepted", already_accepted: true};
    }
    if (!teamHandlerIds(occurrence).includes(caller.ra) ||
        !canActAsHandler(occurrence, caller.ra, caller)) {
      throw new HttpsError("permission-denied", "Usuario nao corresponde ao integrante.");
    }

    const participationRef = occurrenceRef.collection("participations").doc(caller.ra);
    const participationSnap = await transaction.get(participationRef);
    if (!participationSnap.exists) {
      throw new HttpsError("not-found", "Participacao nao encontrada.");
    }
    const participation = participationSnap.data() ?? {};
    const currentStatus = String(participation.status ?? "pending");
    if (currentStatus === "accepted") {
      return {status: "accepted", already_accepted: true};
    }
    if (currentStatus === "declined") {
      throw new HttpsError("failed-precondition", "Participacao ja foi recusada.");
    }

    const accepted = new Set(stringArray(occurrence.accepted_handler_ids));
    const declined = new Set(stringArray(occurrence.declined_handler_ids));
    const pending = new Set(stringArray(occurrence.pending_handler_ids));
    const authorized = new Set(stringArray(occurrence.edit_authorized_handler_ids));
    const authorizedEmails = new Set(stringArray(occurrence.edit_authorized_emails));
    accepted.add(caller.ra);
    pending.delete(caller.ra);
    declined.delete(caller.ra);
    authorized.add(caller.ra);
    [emailForRa(caller.ra), `${caller.ra.trim().toLowerCase()}@canilgcm.com`, caller.email]
      .filter((email) => email.length > 0)
      .forEach((email) => authorizedEmails.add(email));

    const participationStatus = declined.size > 0 ?
      "declined_present" :
      (pending.size > 0 ? "pending_acceptance" : "accepted");
    const entry = auditEntry("participation_accepted", caller);

    transaction.set(participationRef, {
      status: "accepted",
      responded_at: admin.firestore.FieldValue.serverTimestamp(),
      response_method: "in_app",
      auth_uid: caller.uid,
      handler_email: caller.email || emailForRa(caller.ra),
      updated_by: caller.ra,
    }, {merge: true});
    transaction.update(occurrenceRef, {
      accepted_handler_ids: Array.from(accepted).sort(),
      declined_handler_ids: Array.from(declined).sort(),
      pending_handler_ids: Array.from(pending).sort(),
      edit_authorized_handler_ids: Array.from(authorized).sort(),
      edit_authorized_emails: Array.from(authorizedEmails).sort(),
      participation_status: participationStatus,
      participation_revision: admin.firestore.FieldValue.increment(1),
      updated_at: admin.firestore.FieldValue.serverTimestamp(),
      audit_trail: admin.firestore.FieldValue.arrayUnion(entry),
    });

    const primaryRa = stringValue(occurrence.primary_handler_ra ?? occurrence.primary_handler_id);
    if (primaryRa && primaryRa !== caller.ra) {
      transaction.set(
        db.collection("notifications").doc(primaryRa).collection("items").doc(),
        notificationPayload("occurrence_participation_accepted", occurrenceId, occurrence, "occurrence_review", caller.ra),
      );
    }

    transaction.set(db.collection("auditLogs").doc(), {
      action: "participation_accepted",
      entity_type: "occurrence",
      entity_id: occurrenceId,
      summary: `Participacao confirmada por ${caller.ra}`,
      actor: caller,
      metadata: {handler_id: caller.ra},
      source: "functions",
      performed_at: admin.firestore.FieldValue.serverTimestamp(),
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
    });

    return {status: "accepted"};
  });
});

export const declineOccurrenceParticipation = onCall({region}, async (request) => {
  const caller = requireAuth(request.auth);
  const data = request.data as JsonMap;
  const occurrenceId = requiredString(data, "occurrence_id");
  const reason = requiredString(data, "reason");
  const occurrenceRef = db.collection("occurrences").doc(occurrenceId);

  await db.runTransaction(async (transaction) => {
    const occurrenceSnap = await transaction.get(occurrenceRef);
    if (!occurrenceSnap.exists) {
      throw new HttpsError("not-found", "Ocorrência não encontrada.");
    }
    const occurrence = occurrenceSnap.data() ?? {};
    if (!(String(occurrence.status ?? "in_progress") === "in_progress" ||
      String(occurrence.status ?? "in_progress") === "finalizing")) {
      throw new HttpsError("failed-precondition", "Participação só pode ser recusada com ocorrência aberta.");
    }
    if (!canActAsHandler(occurrence, caller.ra, caller)) {
      throw new HttpsError("permission-denied", "Usuário não corresponde ao integrante.");
    }

    const participationRef = occurrenceRef.collection("participations").doc(caller.ra);
    const participationSnap = await transaction.get(participationRef);
    if (!participationSnap.exists) {
      throw new HttpsError("not-found", "Participação não encontrada.");
    }
    const accepted = new Set(acceptedHandlerIds(occurrence));
    const declined = new Set(stringArray(occurrence.declined_handler_ids));
    const pending = new Set(stringArray(occurrence.pending_handler_ids));
    const authorized = new Set(stringArray(occurrence.edit_authorized_handler_ids));
    const authorizedEmails = new Set(stringArray(occurrence.edit_authorized_emails));
    accepted.delete(caller.ra);
    pending.delete(caller.ra);
    authorized.delete(caller.ra);
    authorizedEmails.delete(emailForRa(caller.ra));
    authorizedEmails.delete(`${caller.ra.trim().toLowerCase()}@canilgcm.com`);
    declined.add(caller.ra);

    const entry = auditEntry("participation_declined", caller, reason);
    transaction.set(participationRef, {
      status: "declined",
      decline_reason: reason,
      responded_at: admin.firestore.FieldValue.serverTimestamp(),
      response_method: "in_app",
      updated_by: caller.ra,
    }, {merge: true});
    transaction.update(occurrenceRef, {
      accepted_handler_ids: Array.from(accepted).sort(),
      declined_handler_ids: Array.from(declined).sort(),
      pending_handler_ids: Array.from(pending).sort(),
      edit_authorized_handler_ids: Array.from(authorized).sort(),
      edit_authorized_emails: Array.from(authorizedEmails).sort(),
      participation_status: "declined_present",
      participation_revision: admin.firestore.FieldValue.increment(1),
      updated_at: admin.firestore.FieldValue.serverTimestamp(),
      audit_trail: admin.firestore.FieldValue.arrayUnion(entry),
    });

    const primaryRa = stringValue(occurrence.primary_handler_ra ?? occurrence.primary_handler_id);
    if (primaryRa) {
      transaction.set(
        db.collection("notifications").doc(primaryRa).collection("items").doc(),
        notificationPayload("occurrence_participation_declined", occurrenceId, occurrence, "occurrence_review", reason),
      );
    }
  });
});

function occurrenceIdFromRequest(req: {path: string; url?: string; query: JsonMap}): string | undefined {
  const queryId = req.query.id;
  const fromQuery = Array.isArray(queryId) ? queryId[0] : queryId;
  const queryText = stringValue(fromQuery);
  if (queryText) return queryText;

  const rawPath = String(req.path || req.url || "").split("?")[0];
  const parts = rawPath.split("/").filter(Boolean).map((part) => decodeURIComponent(part));
  const vIndex = parts.indexOf("v");
  if (vIndex >= 0 && parts[vIndex + 1]) return parts[vIndex + 1];
  if (parts.length > 0 && parts[0] !== "verifyOccurrence") return parts[parts.length - 1];
  return undefined;
}

async function verifyOccurrenceDocument(
  occurrenceId: string,
  options: {verifyMedia?: boolean} = {},
): Promise<JsonMap> {
  const occurrenceRef = db.collection("occurrences").doc(occurrenceId);
  const occurrenceSnap = await occurrenceRef.get();
  const checkedAt = new Date().toISOString();
  if (!occurrenceSnap.exists) {
    return {
      occurrence_id: occurrenceId,
      checked_at: checkedAt,
      status: "not_found",
      found: false,
      sealed: false,
      intact: false,
    };
  }

  const occurrence = occurrenceSnap.data() ?? {};
  const storedHash = stringValue(occurrence.integrity_hash ?? occurrence.hash);
  const rawVersion = Number(occurrence.hash_version ?? occurrence.hashVersion ?? 1);
  const hashVersion = Number.isFinite(rawVersion) ? Math.round(rawVersion) : 1;
  const baseResult: JsonMap = {
    occurrence_id: occurrenceId,
    checked_at: checkedAt,
    found: true,
    type_name: occurrence.type_name ?? null,
    status_current: occurrence.status ?? null,
    hash_version: hashVersion,
    stored_hash: storedHash ?? null,
    finalized_at: normalizeForHash(occurrence.finalized_at ?? occurrence.finalizedAt),
  };

  if (!storedHash) {
    return {
      ...baseResult,
      status: "unsealed",
      sealed: false,
      intact: false,
    };
  }

  if (hashVersion < 1 || hashVersion > 4) {
    return {
      ...baseResult,
      status: "unsupported_version",
      sealed: true,
      intact: false,
    };
  }

  const eventsSnap = await occurrenceRef.collection("events").get();
  const events = eventsSnap.docs.map((doc) => ({id: doc.id, data: doc.data()}));
  const signaturesSnap = hashVersion >= 3 ?
    await occurrenceRef.collection("signatures").get() :
    undefined;
  const participationsSnap = hashVersion >= 4 ?
    await occurrenceRef.collection("participations").get() :
    undefined;
  const correctionSnap = hashVersion >= 4 ?
    await occurrenceRef.collection("correction_requests").get() :
    undefined;

  const signatures = signaturesSnap?.docs.map((doc) => ({id: doc.id, ...doc.data()})) ?? [];
  const participations = participationsSnap?.docs.map((doc) => ({id: doc.id, ...doc.data()})) ?? [];
  const correctionRequests = correctionSnap?.docs.map((doc) => ({id: doc.id, ...doc.data()})) ?? [];
  const recalculatedHash = hashPayload(
    buildHashPayloadForVersion(
      occurrence,
      events,
      signatures,
      participations,
      correctionRequests,
      hashVersion,
    ),
  );
  const documentIntact = storedHash === recalculatedHash;
  let mediaResult: MediaVerificationResult = {
    status: "not_requested",
    checked: 0,
    issues: [],
  };
  if (options.verifyMedia === true) {
    mediaResult = documentIntact && hashVersion >= 2 ?
      await verifyMediaBytes(occurrence, events) :
      {status: "skipped", checked: 0, issues: []};
  }
  const mediaIntact = mediaResult.status === "passed" ? true :
    mediaResult.status === "failed" ? false :
      null;
  const intact = documentIntact && mediaIntact !== false;
  const status = !documentIntact ? "broken" :
    mediaIntact === false ? "media_broken" :
      "intact";

  return {
    ...baseResult,
    status,
    sealed: true,
    intact,
    document_intact: documentIntact,
    recalculated_hash: recalculatedHash,
    events_checked: events.length,
    signatures_checked: signatures.length,
    participations_checked: participations.length,
    correction_requests_checked: correctionRequests.length,
    media_verification: mediaResult.status,
    media_checked: mediaResult.checked,
    media_intact: mediaIntact,
    media_issues: mediaResult.issues,
  };
}

function htmlEscape(value: unknown): string {
  return String(value ?? "")
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;")
    .replace(/'/g, "&#39;");
}

function verificationHtml(result: JsonMap): string {
  const status = String(result.status ?? "unknown");
  const ok = result.intact === true;
  const mediaStatus = String(result.media_verification ?? "not_requested");
  const mediaChecked = Number(result.media_checked ?? 0);
  const title = ok && mediaStatus === "passed" ?
    "Selo e midias integros" :
    ok ? "Selo documental integro" : "Selo nao confirmado";
  const accent = ok ? "#1f9d52" : "#b42318";
  const message = ok && mediaStatus === "passed" ?
    "O hash armazenado confere com o recalculo do servidor, e as midias verificadas no Storage conferem com os SHA-256 registrados." :
    ok ?
      "O hash documental armazenado confere com o recalculo feito no servidor. As midias nao foram baixadas nesta consulta." :
      status === "media_broken" ?
        "O hash documental confere, mas uma ou mais midias nao conferem com os SHA-256 registrados." :
        status === "broken" ?
          "O hash armazenado nao confere com o recalculo do servidor." :
          "Nao foi possivel confirmar a integridade deste registro.";
  const mediaIssues = Array.isArray(result.media_issues) ? result.media_issues : [];
  const mediaRows = mediaIssues.length > 0 ?
    `<dt>Problemas de midia</dt><dd>${mediaIssues.map((issue) => `<div>${htmlEscape(issue)}</div>`).join("")}</dd>` :
    "";
  const mediaAction = ok && mediaStatus === "not_requested" ?
    `<p><a href="?id=${encodeURIComponent(String(result.occurrence_id ?? ""))}&media=1">Verificar fotos no Storage</a></p>` :
    "";
  return `<!doctype html>
<html lang="pt-BR">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>Verificação Canil K9</title>
  <style>
    body { margin: 0; font-family: Arial, sans-serif; background: #050d10; color: #eef7f8; }
    main { max-width: 760px; margin: 0 auto; padding: 32px 18px; }
    .card { border: 1px solid rgba(77,208,225,.24); border-radius: 14px; background: #0b171b; padding: 22px; }
    .badge { display: inline-block; padding: 7px 11px; border-radius: 999px; background: ${accent}; color: #fff; font-weight: 700; }
    h1 { margin: 18px 0 8px; font-size: 30px; }
    p { color: #b8c9ce; line-height: 1.5; }
    dl { display: grid; grid-template-columns: 160px 1fr; gap: 10px 14px; margin-top: 22px; }
    dt { color: #7aa1aa; }
    dd { margin: 0; overflow-wrap: anywhere; }
    code { color: #4dd0e1; }
    a { color: #4dd0e1; font-weight: 700; }
  </style>
</head>
<body>
  <main>
    <section class="card">
      <span class="badge">${htmlEscape(title)}</span>
      <h1>Verificação de ocorrência</h1>
      <p>${htmlEscape(message)}</p>
      ${mediaAction}
      <dl>
        <dt>Ocorrência</dt><dd><code>${htmlEscape(result.occurrence_id)}</code></dd>
        <dt>Natureza</dt><dd>${htmlEscape(result.type_name ?? "Não informada")}</dd>
        <dt>Status</dt><dd>${htmlEscape(result.status_current ?? status)}</dd>
        <dt>Versão do hash</dt><dd>${htmlEscape(result.hash_version)}</dd>
        <dt>Hash armazenado</dt><dd><code>${htmlEscape(result.stored_hash ?? "-")}</code></dd>
        <dt>Hash recalculado</dt><dd><code>${htmlEscape(result.recalculated_hash ?? "-")}</code></dd>
        <dt>Midias</dt><dd>${htmlEscape(mediaStatus)} - ${htmlEscape(mediaChecked)} verificada(s)</dd>
        ${mediaRows}
        <dt>Verificado em</dt><dd>${htmlEscape(result.checked_at)}</dd>
      </dl>
    </section>
  </main>
</body>
</html>`;
}

export const verifyOccurrence = onRequest({region}, async (req, res) => {
  try {
    const occurrenceId = occurrenceIdFromRequest(req);
    if (!occurrenceId) {
      res.status(400).json({status: "invalid_request", message: "Informe o ID da ocorrencia."});
      return;
    }

    const verifyMedia = req.query.media === "1" ||
      req.query.media === "true" ||
      req.query.deep === "1";
    const result = await verifyOccurrenceDocument(occurrenceId, {verifyMedia});
    const wantsJson = req.query.format === "json" ||
      String(req.headers.accept ?? "").includes("application/json");
    const statusCode = result.status === "not_found" ? 404 : 200;
    res.set("Cache-Control", "no-store");
    if (wantsJson) {
      res.status(statusCode).json(result);
      return;
    }
    res.status(statusCode).send(verificationHtml(result));
  } catch (error) {
    logger.error("Falha na verificacao publica", {error});
    res.status(500).json({status: "error", message: "Falha ao verificar ocorrencia."});
  }
});

export const onNotificationCreated = onDocumentCreated(
  {
    document: "notifications/{userId}/items/{notificationId}",
    region,
  },
  async (event) => {
    const snapshot = event.data;
    if (!snapshot) return;
    const userId = event.params.userId;
    const notificationId = event.params.notificationId;
    const notification = snapshot.data() ?? {};
    const devices = await db.collection("users").doc(userId).collection("devices").get();
    const tokens = devices.docs
      .map((doc) => stringValue(doc.data().token))
      .filter((token): token is string => Boolean(token));

    if (tokens.length === 0) {
      logger.info("Sem tokens FCM cadastrados", {userId, notificationId});
      return;
    }

    const occurrenceTitle = String(notification.occurrence_title ?? "Ocorrência");
    const text = notificationText(String(notification.type ?? ""), occurrenceTitle);
    const response = await admin.messaging().sendEachForMulticast({
      tokens,
      data: {
        notification_id: notificationId,
        type: String(notification.type ?? ""),
        title: text.title,
        body: text.body,
        occurrence_id: String(notification.occurrence_id ?? ""),
        target_screen: String(notification.target_screen ?? ""),
        additional_data: String(notification.additional_data ?? ""),
        crew_id: String(notification.additional_data ?? ""),
        promotion_request_id: String(notification.promotion_request_id ?? notification.additional_data ?? ""),
        dog_id: String(notification.dog_id ?? ""),
        modality: String(notification.modality ?? ""),
        module_id: String(notification.module_id ?? ""),
        click_action: "FLUTTER_NOTIFICATION_CLICK",
      },
      android: {
        priority: "high",
      },
    });

    response.responses.forEach((result, index) => {
      if (!result.success) {
        logger.warn("Falha ao enviar FCM", {
          userId,
          notificationId,
          tokenIndex: index,
          error: result.error?.message,
        });
      }
    });
  },
);

// ─── Shift Reminder Notification ───────────────────────────────────────────────

/**
 * Envia notificação para提醒 usuário sobre turno pendente de encerramento.
 * Pode ser chamado via scheduled task (ex: a cada hora).
 *
 * shifts aberto há mais de 12h sem encerramento → notificação de "turno pendente"
 */
export const checkOpenShiftsAndNotify = onCall(
  {region, secrets: []},
  async (request: CallableRequest) => {
    const caller = request.auth;
    if (!caller) {
      throw new HttpsError("unauthenticated", "Requer autenticação.");
    }

    const now = new Date();
    const maxOpenHours = 12;
    const threshold = new Date(now.getTime() - maxOpenHours * 60 * 60 * 1000);

    // Buscar turnos abertos há mais de 12h
    const openShiftsSnap = await db
      .collection("active_shifts")
      .where("status", "==", "active")
      .where("startedAt", "<", threshold)
      .get();

    logger.info(`Found ${openShiftsSnap.size} open shifts over ${maxOpenHours}h`, {
      threshold: threshold.toISOString(),
    });

    const notifications: Array<Promise<void>> = [];

    for (const shiftDoc of openShiftsSnap.docs) {
      const shiftData = shiftDoc.data();
      const handlerId = shiftData.handlerId ?? shiftDoc.id;
      const startedAt = shiftData.startedAt?.toDate?.() ?? new Date(shiftData.startedAt);
      const hoursOpen = Math.floor((now.getTime() - startedAt.getTime()) / (1000 * 60 * 60));

      // Verificar se já recebeu notificação recently (últimas 4h)
      const recentNotif = await db
        .collection("notifications")
        .doc(handlerId)
        .collection("items")
        .where("type", "==", "shift_open_reminder")
        .where("created_at", ">", new Date(now.getTime() - 4 * 60 * 60 * 1000))
        .limit(1)
        .get();

      if (!recentNotif.empty) {
        logger.info(`Skipping reminder for ${handlerId} - already notified recently`);
        continue;
      }

      // Obter dados do usuário para FCM tokens
      const userDoc = await db.collection("users").doc(handlerId).get();
      const userData = userDoc.data();
      const tokens: string[] = [];

      // Buscar tokens FCM (simplificado - ajuste conforme seu padrão)
      if (userData?.fcmTokens) {
        const tokenMap = userData.fcmTokens as Record<string, boolean>;
        for (const [token, enabled] of Object.entries(tokenMap)) {
          if (enabled) tokens.push(token);
        }
      }

      if (tokens.length === 0) {
        logger.info(`No FCM tokens for user ${handlerId}`);
        continue;
      }

      // Criar notificação
      const notifRef = db
        .collection("notifications")
        .doc(handlerId)
        .collection("items")
        .doc();

      const notifData = {
        type: "shift_open_reminder",
        title: "Turno pendente de encerramento",
        body: `Seu turno está aberto há ${hoursOpen}h. Clique para encerrar.`,
        created_at: admin.firestore.FieldValue.serverTimestamp(),
        archived_at: null,
        shift_id: shiftDoc.id,
        hours_open: hoursOpen,
        read: false,
        action_required: true,
      };

      notifications.push(
        (async () => {
          await notifRef.set(notifData);

          // Enviar FCM
          try {
            await admin.messaging().sendEachForMulticast({
              notification: { title: notifData.title, body: notifData.body },
              data: { type: "shift_open_reminder", shift_id: shiftDoc.id, hours_open: String(hoursOpen) },
              tokens,
            });
          } catch (e) {
            logger.error("Failed to send FCM for shift reminder", { handlerId, error: e });
          }
        })(),
      );
    }

    await Promise.allSettled(notifications);

    return {
      checked: openShiftsSnap.size,
      notified: notifications.length,
    };
  },
);
