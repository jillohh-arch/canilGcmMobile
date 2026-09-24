import * as crypto from "crypto";
import * as admin from "firebase-admin";
import {HttpsError} from "firebase-functions/v2/https";

type JsonMap = Record<string, unknown>;

export type SnapshotCallableAuth = {
  uid: string;
  token: Record<string, unknown>;
} | undefined;

export interface SnapshotCaller {
  uid: string;
  ra: string;
}

export interface SnapshotDocument {
  data: JsonMap;
  exists: boolean;
  updateTime: string | null;
}

export interface SnapshotAuthUser {
  customClaims: JsonMap;
  disabled: boolean;
  uid: string;
}

export interface SnapshotUserCandidate {
  data: JsonMap;
  id: string;
}

export interface AccessHomologationSnapshotDeps {
  authorize: (auth: SnapshotCallableAuth) => Promise<SnapshotCaller>;
  correlationId: () => string;
  getAuthUser: (user: JsonMap, ra: string) => Promise<SnapshotAuthUser | null>;
  getDocuments: (paths: string[]) => Promise<SnapshotDocument[]>;
  hasActiveShift: (ra: string, dogId: string) => Promise<boolean>;
  listActiveUsers: (limit: number) => Promise<{
    truncated: boolean;
    users: SnapshotUserCandidate[];
  }>;
  logInfo: (event: JsonMap) => void;
  logWarning: (event: JsonMap) => void;
  now: () => Date;
  projectId: string;
}

export interface AccessHomologationSnapshotRequest {
  dogId: string;
  excludedRa: string;
  operatorProfileId: string;
  targetRa: string;
  temporaryProfileId: string;
}

export type DogAccessReason =
  | "global_scope"
  | "direct_link"
  | "active_shift"
  | "denied"
  | "unknown";

const REQUEST_KEYS = [
  "dogId",
  "excludedRa",
  "operatorProfileId",
  "targetRa",
  "temporaryProfileId",
] as const;

const MAX_ACTIVE_USERS = 200;
const AUTH_LOOKUP_CONCURRENCY = 10;
const DANGEROUS_PERMISSION_KEYS = new Set(["__proto__", "constructor", "prototype"]);

function isPlainObject(value: unknown): value is JsonMap {
  return typeof value === "object" && value !== null && !Array.isArray(value);
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

function requiredStrictString(data: JsonMap, key: string, maxLength: number): string {
  const value = data[key];
  if (typeof value !== "string" || value.trim().length === 0) {
    throw new HttpsError("invalid-argument", `Campo obrigatorio invalido: ${key}.`);
  }
  const parsed = value.trim();
  if (parsed.length > maxLength) {
    throw new HttpsError("invalid-argument", `Campo excede o limite: ${key}.`);
  }
  return parsed;
}

function assertRa(ra: string): void {
  if (!/^\d{4,12}$/.test(ra)) {
    throw new HttpsError("invalid-argument", "RA deve conter apenas numeros.");
  }
}

function assertDocumentId(id: string, label: string): void {
  if (!/^[a-zA-Z0-9_-]{1,120}$/.test(id)) {
    throw new HttpsError("invalid-argument", `${label} contem caracteres invalidos.`);
  }
}

export function parseAccessHomologationSnapshotRequest(
  raw: unknown,
): AccessHomologationSnapshotRequest {
  if (!isPlainObject(raw)) {
    throw new HttpsError("invalid-argument", "Request deve ser um objeto.");
  }
  const keys = Object.keys(raw).sort();
  const expected = [...REQUEST_KEYS].sort();
  if (keys.length !== expected.length || keys.some((key, index) => key !== expected[index])) {
    throw new HttpsError("invalid-argument", "Request contem campos ausentes ou desconhecidos.");
  }

  const parsed = {
    dogId: requiredStrictString(raw, "dogId", 120),
    excludedRa: requiredStrictString(raw, "excludedRa", 12),
    operatorProfileId: requiredStrictString(raw, "operatorProfileId", 120),
    targetRa: requiredStrictString(raw, "targetRa", 12),
    temporaryProfileId: requiredStrictString(raw, "temporaryProfileId", 120),
  };
  assertRa(parsed.targetRa);
  assertRa(parsed.excludedRa);
  assertDocumentId(parsed.dogId, "Identificador do K9");
  assertDocumentId(parsed.operatorProfileId, "Identificador do profile Operador");
  assertDocumentId(parsed.temporaryProfileId, "Identificador do profile temporario");
  if (parsed.targetRa === parsed.excludedRa) {
    throw new HttpsError("invalid-argument", "Target e excluded devem ser distintos.");
  }
  if (parsed.operatorProfileId === parsed.temporaryProfileId) {
    throw new HttpsError("invalid-argument", "Profiles Operador e temporario devem ser distintos.");
  }
  return parsed;
}

export function maskIdentifier(value: string): string {
  const characters = Array.from(value);
  if (characters.length <= 7) return "…";
  return `${characters.slice(0, 3).join("")}…${characters.slice(-4).join("")}`;
}

export function maskRa(value: string): string {
  const characters = Array.from(value);
  if (characters.length <= 5) return "…";
  return `${characters[0]}…${characters.slice(-4).join("")}`;
}

export function sanitizePermissions(value: unknown): JsonMap {
  if (!isPlainObject(value)) return {};
  const permissions: JsonMap = {};
  const modules = Object.entries(value).sort(([left], [right]) => left.localeCompare(right));
  for (const [moduleId, modulePermissions] of modules) {
    const normalizedModule = normalizedKey(moduleId);
    if (
      !normalizedModule ||
      DANGEROUS_PERMISSION_KEYS.has(moduleId) ||
      DANGEROUS_PERMISSION_KEYS.has(normalizedModule) ||
      !isPlainObject(modulePermissions)
    ) continue;
    const existingActions = Object.prototype.hasOwnProperty.call(permissions, normalizedModule) ?
      permissions[normalizedModule] : null;
    const actions: JsonMap = isPlainObject(existingActions) ? existingActions : {};
    const entries = Object.entries(modulePermissions)
      .sort(([left], [right]) => left.localeCompare(right));
    for (const [action, enabled] of entries) {
      const normalizedAction = normalizedKey(action);
      if (
        normalizedAction &&
        !DANGEROUS_PERMISSION_KEYS.has(action) &&
        !DANGEROUS_PERMISSION_KEYS.has(normalizedAction) &&
        enabled === true
      ) actions[normalizedAction] = true;
    }
    permissions[normalizedModule] = actions;
  }
  return permissions;
}

function stringValue(value: unknown): string | null {
  if (typeof value !== "string" && typeof value !== "number") return null;
  const parsed = String(value).trim();
  return parsed.length ? parsed : null;
}

function isArchived(data: JsonMap): boolean {
  return data.archived_at != null || data.deleted_at != null || data.deletedAt != null;
}

function isActiveRecord(data: JsonMap): boolean {
  const status = normalizedKey(data.status);
  return data.active !== false && !["inactive", "inativo", "archived", "arquivado"].includes(status) && !isArchived(data);
}

function isActiveProfile(data: JsonMap): boolean {
  return (stringValue(data.status) ?? "active") === "active";
}

function legacyAccessProfileId(value: unknown): string | null {
  const normalized = normalizedKey(value);
  if (!normalized) return null;
  if (["admin", "administrador", "admin_master"].includes(normalized)) return "administrador";
  if (["condutor", "handler", "mobile_user", "operador_mobile", "operador", "operador_k9", "guarda_k9"].includes(normalized)) return "operador_k9";
  if (["gestor", "comando", "supervisor", "subinspetor", "inspetor"].includes(normalized)) return "gestor";
  if (["inventory_manager", "almoxarifado", "estoque"].includes(normalized)) return "almoxarifado";
  if (["instrutor", "instrutor_k9", "adestrador"].includes(normalized)) return "instrutor_k9";
  return normalized;
}

export function documentProfileId(data: JsonMap): string | null {
  const candidates = [
    data.access_profile_id,
    data.accessProfileId,
    data.accessProfile,
    data.access_profile,
    data.accessLevel,
    data.access_level,
    data.role,
    data.claim_role,
    data.training_role,
    ...(Array.isArray(data.roles) ? data.roles : []),
  ];
  for (const candidate of candidates) {
    const resolved = legacyAccessProfileId(candidate);
    if (resolved) return resolved;
  }
  if (data.admin === true) return "administrador";
  return null;
}

function claimProfileId(authUser: SnapshotAuthUser | null): string | null {
  return authUser ? legacyAccessProfileId(authUser.customClaims.access_profile_id) : null;
}

function adminClaimBypass(authUser: SnapshotAuthUser | null): boolean {
  if (!authUser) return false;
  const claims = authUser.customClaims;
  const claimRole = normalizedKey(claims.role);
  const claimRoles = Array.isArray(claims.roles) ? claims.roles.map(normalizedKey) : [];
  const adminRoles = ["admin", "administrador", "admin_master"];
  return claims.admin === true ||
    adminRoles.includes(claimRole) ||
    claimRoles.some((role) => adminRoles.includes(role));
}

function adminBypass(authUser: SnapshotAuthUser | null, user: JsonMap): boolean {
  if (!authUser) return false;
  return adminClaimBypass(authUser) ||
    user.admin === true ||
    ["admin", "administrador"].includes(normalizedKey(user.accessLevel ?? user.access_level));
}

function internalRole(authUser: SnapshotAuthUser | null, user: JsonMap): "admin" | "condutor" | null {
  if (!authUser) return null;
  if (adminBypass(authUser, user)) return "admin";
  const documentProfile = documentProfileId(user);
  const claimProfile = claimProfileId(authUser);
  return documentProfile != null && documentProfile === claimProfile ? "condutor" : null;
}

function dogHandlerRa(dog: JsonMap): string | null {
  return stringValue(dog.conductorRa) ?? stringValue(dog.conductor_ra) ?? stringValue(dog.handlerId) ?? stringValue(dog.handler_id);
}

export function evaluateDogAccess(input: {
  activeShift: boolean;
  directLink: boolean;
  dogExists: boolean;
  scope: string | null;
}): {allowed: boolean; reason: DogAccessReason} {
  if (!input.dogExists) return {allowed: false, reason: "unknown"};
  if (input.scope === "global") return {allowed: true, reason: "global_scope"};
  if (input.directLink) return {allowed: true, reason: "direct_link"};
  if (input.activeShift) return {allowed: true, reason: "active_shift"};
  if (input.scope === "own_records") return {allowed: false, reason: "denied"};
  return {allowed: false, reason: "unknown"};
}

function recordRoutine(permissions: unknown): {present: boolean; value: boolean | null} {
  if (
    !isPlainObject(permissions) ||
    !Object.prototype.hasOwnProperty.call(permissions, "health") ||
    !isPlainObject(permissions.health)
  ) return {present: false, value: null};
  const present = Object.prototype.hasOwnProperty.call(permissions.health, "record_routine");
  return {
    present,
    value: present && typeof permissions.health.record_routine === "boolean" ?
      permissions.health.record_routine : null,
  };
}

async function mapWithConcurrency<T, R>(
  items: T[],
  concurrency: number,
  mapper: (item: T) => Promise<R>,
): Promise<R[]> {
  const results = new Array<R>(items.length);
  let nextIndex = 0;
  const workers = Array.from(
    {length: Math.min(concurrency, items.length)},
    async () => {
      while (nextIndex < items.length) {
        const index = nextIndex++;
        results[index] = await mapper(items[index]);
      }
    },
  );
  await Promise.all(workers);
  return results;
}

function canonicalize(value: unknown): unknown {
  if (Array.isArray(value)) return value.map(canonicalize);
  if (!isPlainObject(value)) return value;
  return Object.fromEntries(Object.keys(value).sort().map((key) => [key, canonicalize(value[key])]));
}

export function snapshotFingerprint(value: unknown): string {
  return crypto.createHash("sha256").update(JSON.stringify(canonicalize(value))).digest("hex").toUpperCase();
}

function addBlocker(blockers: string[], condition: boolean, code: string): void {
  if (condition && !blockers.includes(code)) blockers.push(code);
}

function authErrorCode(error: unknown): string | null {
  if (!isPlainObject(error)) return null;
  const code = error.code;
  return typeof code === "string" ? code : null;
}

function isAuthLookupMiss(error: unknown): boolean {
  return ["auth/invalid-email", "auth/invalid-uid", "auth/user-not-found"]
    .includes(authErrorCode(error) ?? "");
}

function userSnapshot(
  ra: string,
  document: SnapshotDocument,
  authUser: SnapshotAuthUser | null,
  linkedToDog: boolean,
) {
  const user = document.data;
  const docProfile = document.exists ? documentProfileId(user) : null;
  const claimProfile = claimProfileId(authUser);
  return {
    authDisabled: authUser?.disabled ?? null,
    authUidMasked: authUser ? maskIdentifier(authUser.uid) : null,
    authUserExists: authUser != null,
    claimProfileId: claimProfile,
    documentExists: document.exists,
    documentProfileId: docProfile,
    documentUpdateTime: document.updateTime,
    internalRole: document.exists ? internalRole(authUser, user) : null,
    linkedToDog,
    managedClaims: {
      accessProfileId: claimProfile,
      adminBypass: adminBypass(authUser, user),
    },
    profileIdsCoherent: docProfile != null && claimProfile != null && docProfile === claimProfile,
    raMasked: maskRa(ra),
    status: document.exists && isActiveRecord(user) ? "active" : "inactive",
  };
}

export function buildAdminGetAccessHomologationSnapshotHandler(
  deps: AccessHomologationSnapshotDeps,
) {
  return async (request: {auth?: {uid: string; token: Record<string, unknown>}; data: unknown}) => {
    const correlationId = deps.correlationId();
    try {
      const caller = await deps.authorize(request.auth);
      const input = parseAccessHomologationSnapshotRequest(request.data);
      const paths = [
        `users/${input.targetRa}`,
        `users/${input.excludedRa}`,
        `access_profiles/${input.operatorProfileId}`,
        `access_profiles/${input.temporaryProfileId}`,
        `dogs/${input.dogId}`,
      ];
      const [targetDoc, excludedDoc, operatorDoc, temporaryDoc, dogDoc] = await deps.getDocuments(paths);
      const [targetAuth, excludedAuth, activeUsersResult] = await Promise.all([
        targetDoc.exists ? deps.getAuthUser(targetDoc.data, input.targetRa) : Promise.resolve(null),
        excludedDoc.exists ? deps.getAuthUser(excludedDoc.data, input.excludedRa) : Promise.resolve(null),
        deps.listActiveUsers(MAX_ACTIVE_USERS + 1),
      ]);

      const dogHandler = dogDoc.exists ? dogHandlerRa(dogDoc.data) : null;
      const targetLinked = dogHandler === input.targetRa;
      const excludedLinked = dogHandler === input.excludedRa;
      const target = userSnapshot(input.targetRa, targetDoc, targetAuth, targetLinked);
      const excluded = {
        ...userSnapshot(input.excludedRa, excludedDoc, excludedAuth, excludedLinked),
        distinctFromTarget: input.targetRa !== input.excludedRa && targetAuth?.uid !== excludedAuth?.uid,
      };

      const allActiveUsers = activeUsersResult.users.slice(0, MAX_ACTIVE_USERS);
      const associated = allActiveUsers.filter(
        (user) => isActiveRecord(user.data) &&
          documentProfileId(user.data) === input.operatorProfileId,
      );
      const associatedAuth = await mapWithConcurrency(
        associated,
        AUTH_LOOKUP_CONCURRENCY,
        (user) => deps.getAuthUser(user.data, user.id),
      );
      const authEnabledCount = associatedAuth.filter((user) => user != null && !user.disabled).length;
      const claimCoherentCount = associated.filter((user, index) => {
        const authUser = associatedAuth[index];
        return authUser != null && documentProfileId(user.data) === claimProfileId(authUser);
      }).length;
      const temporaryAssociated = allActiveUsers.filter(
        (user) => isActiveRecord(user.data) &&
          documentProfileId(user.data) === input.temporaryProfileId,
      );
      const temporaryAssociatedAuth = await mapWithConcurrency(
        temporaryAssociated,
        AUTH_LOOKUP_CONCURRENCY,
        (user) => deps.getAuthUser(user.data, user.id),
      );
      const temporaryAuthEnabledCount = temporaryAssociatedAuth.filter(
        (user) => user != null && !user.disabled,
      ).length;
      const temporaryClaimCoherentCount = temporaryAssociated.filter((user, index) => {
        const authUser = temporaryAssociatedAuth[index];
        return authUser != null && documentProfileId(user.data) === claimProfileId(authUser);
      }).length;

      const operatorPermissions = operatorDoc.exists ? sanitizePermissions(operatorDoc.data.permissions) : {};
      const operatorRoutine = operatorDoc.exists ? recordRoutine(operatorDoc.data.permissions) : {present: false, value: null};
      const operatorScope = operatorDoc.exists && stringValue(operatorDoc.data.scope) === "own_records" ? "own_records" : operatorDoc.exists && stringValue(operatorDoc.data.scope) === "global" ? "global" : null;
      const temporaryPermissions = temporaryDoc.exists ? sanitizePermissions(temporaryDoc.data.permissions) : {};
      const temporaryRoutine = temporaryDoc.exists ? recordRoutine(temporaryDoc.data.permissions) : {present: false, value: null};
      const temporaryScope = temporaryDoc.exists && stringValue(temporaryDoc.data.scope) === "own_records" ? "own_records" : temporaryDoc.exists && stringValue(temporaryDoc.data.scope) === "global" ? "global" : null;

      const targetUsesOperatorProfile =
        target.documentProfileId === input.operatorProfileId &&
        target.claimProfileId === input.operatorProfileId;
      const excludedUsesOperatorProfile =
        excluded.documentProfileId === input.operatorProfileId &&
        excluded.claimProfileId === input.operatorProfileId;
      const effectiveScope = adminClaimBypass(targetAuth) ?
        "global" : targetUsesOperatorProfile ? operatorScope : null;
      const activeShift = effectiveScope === "own_records" && !targetLinked ?
        await deps.hasActiveShift(input.targetRa, input.dogId) : false;
      const access = evaluateDogAccess({
        activeShift,
        directLink: targetLinked,
        dogExists: dogDoc.exists,
        scope: effectiveScope,
      });

      const blockers: string[] = [];
      const warnings: string[] = [];
      addBlocker(blockers, !target.documentExists, "target_user_document_missing");
      addBlocker(blockers, !target.authUserExists, "target_auth_user_missing");
      addBlocker(blockers, target.authDisabled === true, "target_auth_disabled");
      addBlocker(blockers, target.status !== "active", "target_user_inactive");
      addBlocker(blockers, !target.profileIdsCoherent, "target_profile_claim_mismatch");
      addBlocker(blockers, !targetUsesOperatorProfile, "target_operator_profile_mismatch");
      addBlocker(blockers, !excluded.documentExists, "excluded_user_document_missing");
      addBlocker(blockers, !excluded.authUserExists, "excluded_auth_user_missing");
      addBlocker(blockers, excluded.authDisabled === true, "excluded_auth_disabled");
      addBlocker(blockers, excluded.status !== "active", "excluded_user_inactive");
      addBlocker(blockers, !excluded.profileIdsCoherent, "excluded_profile_claim_mismatch");
      addBlocker(blockers, !excludedUsesOperatorProfile, "excluded_operator_profile_mismatch");
      addBlocker(blockers, !excluded.distinctFromTarget, "excluded_user_not_distinct");
      addBlocker(blockers, !operatorDoc.exists, "operator_profile_missing");
      addBlocker(blockers, operatorDoc.exists && !isActiveProfile(operatorDoc.data), "operator_profile_inactive");
      addBlocker(blockers, operatorScope !== "global", "operator_scope_unexpected");
      addBlocker(blockers, operatorRoutine.present && operatorRoutine.value == null, "record_routine_invalid");
      addBlocker(blockers, operatorRoutine.present && operatorRoutine.value != null, "record_routine_already_present");
      addBlocker(blockers, associated.length !== 4 || authEnabledCount !== 4 || claimCoherentCount !== 4, "operator_active_user_count_unexpected");
      addBlocker(blockers, temporaryDoc.exists, "temporary_profile_exists");
      addBlocker(blockers, activeUsersResult.truncated, "association_scan_truncated");
      addBlocker(blockers, !dogDoc.exists, "dog_missing");
      addBlocker(blockers, dogDoc.exists && !isActiveRecord(dogDoc.data), "dog_inactive");
      addBlocker(blockers, access.reason === "denied", "dog_access_denied");
      addBlocker(blockers, access.reason === "unknown", "dog_access_unknown");
      addBlocker(blockers, target.internalRole == null, "internal_role_unresolved");
      addBlocker(blockers, [targetDoc, excludedDoc, operatorDoc, temporaryDoc, dogDoc].some((doc) => doc.exists && doc.updateTime == null), "update_time_missing");
      if (activeUsersResult.truncated) warnings.push("association_scan_truncated");

      const preconditions = {
        dog: {
          access,
          active: dogDoc.exists && isActiveRecord(dogDoc.data),
          exists: dogDoc.exists,
          linkedToExcluded: excludedLinked,
          linkedToTarget: targetLinked,
          updateTime: dogDoc.updateTime,
        },
        excludedUser: {
          adminBypass: excluded.managedClaims.adminBypass,
          authDisabled: excluded.authDisabled,
          authUserExists: excluded.authUserExists,
          claimProfileId: excluded.managedClaims.accessProfileId,
          distinctFromTarget: excluded.distinctFromTarget,
          documentExists: excluded.documentExists,
          documentProfileId: excluded.documentProfileId,
          status: excluded.status,
          updateTime: excluded.documentUpdateTime,
        },
        hardGate: {blockers, warnings},
        operatorProfile: {
          associationSummary: {
            authEnabledCount,
            claimCoherentCount,
            documentCount: associated.length,
          },
          exists: operatorDoc.exists,
          permissions: operatorPermissions,
          recordRoutine: operatorRoutine,
          scope: operatorScope,
          status: operatorDoc.exists && isActiveProfile(operatorDoc.data) ? "active" : "inactive",
          updateTime: operatorDoc.updateTime,
        },
        targetUser: {
          adminBypass: target.managedClaims.adminBypass,
          authDisabled: target.authDisabled,
          authUserExists: target.authUserExists,
          claimProfileId: target.managedClaims.accessProfileId,
          documentExists: target.documentExists,
          documentProfileId: target.documentProfileId,
          internalRole: target.internalRole,
          status: target.status,
          updateTime: target.documentUpdateTime,
        },
        temporaryProfile: {
          associationSummary: {
            authEnabledCount: temporaryAuthEnabledCount,
            claimCoherentCount: temporaryClaimCoherentCount,
            documentCount: temporaryAssociated.length,
          },
          exists: temporaryDoc.exists,
          permissions: temporaryPermissions,
          recordRoutine: temporaryRoutine,
          scope: temporaryScope,
          status: temporaryDoc.exists && isActiveProfile(temporaryDoc.data) ?
            "active" : temporaryDoc.exists ? "inactive" : null,
          updateTime: temporaryDoc.updateTime,
        },
      };
      const fingerprint = snapshotFingerprint(preconditions);
      const response = {
        dog: {
          active: dogDoc.exists && isActiveRecord(dogDoc.data),
          documentUpdateTime: dogDoc.updateTime,
          exists: dogDoc.exists,
          idMasked: maskIdentifier(input.dogId),
          linkedToExcluded: excludedLinked,
          linkedToTarget: targetLinked,
        },
        dogAccessEvaluation: {...access, internalRole: target.internalRole},
        excludedUser: excluded,
        hardGate: {blockers, ready: blockers.length === 0, warnings},
        inspectedAt: deps.now().toISOString(),
        operatorProfile: {
          activeAssociatedUsers: authEnabledCount,
          associationSummary: {authEnabledCount, claimCoherentCount, documentCount: associated.length},
          documentUpdateTime: operatorDoc.updateTime,
          exists: operatorDoc.exists,
          permissions: operatorPermissions,
          recordRoutine: operatorRoutine,
          scope: operatorScope,
          status: operatorDoc.exists && isActiveProfile(operatorDoc.data) ? "active" : "inactive",
        },
        projectId: deps.projectId,
        snapshotFingerprint: fingerprint,
        targetUser: target,
        temporaryProfile: {
          activeAssociatedUsers: temporaryDoc.exists ? temporaryAuthEnabledCount : 0,
          associationSummary: {
            authEnabledCount: temporaryDoc.exists ? temporaryAuthEnabledCount : 0,
            claimCoherentCount: temporaryDoc.exists ? temporaryClaimCoherentCount : 0,
            documentCount: temporaryDoc.exists ? temporaryAssociated.length : 0,
          },
          documentUpdateTime: temporaryDoc.updateTime,
          exists: temporaryDoc.exists,
          permissions: temporaryPermissions,
          recordRoutine: temporaryRoutine,
          scope: temporaryScope,
          status: temporaryDoc.exists && isActiveProfile(temporaryDoc.data) ? "active" : temporaryDoc.exists ? "inactive" : null,
        },
      };
      deps.logInfo({
        actorUidMasked: maskIdentifier(caller.uid),
        blockerCount: blockers.length,
        correlationId,
        dogIdMasked: maskIdentifier(input.dogId),
        event: "admin_access_homologation_snapshot_read",
        hardGateReady: blockers.length === 0,
        targetRaMasked: maskRa(input.targetRa),
      });
      return response;
    } catch (error) {
      if (error instanceof HttpsError) {
        if (error.code === "internal" || error.code === "unavailable") {
          deps.logWarning({correlationId, event: "admin_access_homologation_snapshot_read_failed"});
        }
        throw error;
      }
      deps.logWarning({correlationId, event: "admin_access_homologation_snapshot_read_failed"});
      throw new HttpsError("internal", "Falha interna ao inspecionar autorizacao.");
    }
  };
}

export function createAdminAccessHomologationSnapshotDeps(input: {
  auth: admin.auth.Auth;
  authorize: AccessHomologationSnapshotDeps["authorize"];
  correlationId?: () => string;
  db: admin.firestore.Firestore;
  logInfo?: (event: JsonMap) => void;
  logWarning?: (event: JsonMap) => void;
  now?: () => Date;
  projectId: string;
}): AccessHomologationSnapshotDeps {
  const resolveAuthUser = async (user: JsonMap, ra: string): Promise<SnapshotAuthUser | null> => {
    const uid = stringValue(user.auth_uid) ?? stringValue(user.authUid) ?? stringValue(user.uid);
    let record: admin.auth.UserRecord | null = null;
    if (uid) {
      try {
        record = await input.auth.getUser(uid);
      } catch (error) {
        if (!isAuthLookupMiss(error)) {
          throw new HttpsError("unavailable", "Firebase Auth temporariamente indisponivel.");
        }
      }
    }
    if (!record) {
      const email = stringValue(user.email) ?? `${ra.trim().toLowerCase()}@gcm.com.br`;
      try {
        record = await input.auth.getUserByEmail(email);
      } catch (error) {
        if (!isAuthLookupMiss(error)) {
          throw new HttpsError("unavailable", "Firebase Auth temporariamente indisponivel.");
        }
      }
    }
    return record ? {customClaims: record.customClaims ?? {}, disabled: record.disabled, uid: record.uid} : null;
  };

  return {
    authorize: input.authorize,
    correlationId: input.correlationId ?? (() => crypto.randomUUID()),
    getAuthUser: resolveAuthUser,
    getDocuments: async (paths) => {
      const snapshots = await input.db.getAll(...paths.map((path) => input.db.doc(path)));
      return snapshots.map((snapshot) => ({
        data: snapshot.data() ?? {},
        exists: snapshot.exists,
        updateTime: snapshot.updateTime?.toDate().toISOString() ?? null,
      }));
    },
    hasActiveShift: async (ra, dogId) => {
      const snapshot = await input.db.collection("active_shifts").doc(ra).get();
      const shift = snapshot.data() ?? {};
      const activeDogId = stringValue(shift.currentDogId) ?? stringValue(shift.service_dog_id) ?? stringValue(shift.dogId);
      return snapshot.exists && stringValue(shift.status) === "active" && activeDogId === dogId;
    },
    listActiveUsers: async (limit) => {
      const snapshot = await input.db.collection("users").where("active", "==", true).limit(limit).get();
      return {
        truncated: snapshot.size >= limit,
        users: snapshot.docs.map((doc) => ({data: doc.data(), id: doc.id})),
      };
    },
    logInfo: input.logInfo ?? (() => {}),
    logWarning: input.logWarning ?? (() => {}),
    now: input.now ?? (() => new Date()),
    projectId: input.projectId,
  };
}
