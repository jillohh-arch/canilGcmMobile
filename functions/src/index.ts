import * as crypto from "crypto";
import * as admin from "firebase-admin";
import {logger} from "firebase-functions";
import {onDocumentCreated, onDocumentUpdated} from "firebase-functions/v2/firestore";
import {HttpsError, onCall, onRequest} from "firebase-functions/v2/https";

admin.initializeApp();

const db = admin.firestore();
const region = "southamerica-east1";

type JsonMap = Record<string, unknown>;

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

async function requireAdmin(
  auth: {uid: string; token: admin.auth.DecodedIdToken} | undefined,
): Promise<CallerIdentity> {
  const caller = requireAuth(auth);
  if (auth && isAdminToken(auth.token)) return caller;

  const userSnap = await db.collection("users").doc(caller.ra).get();
  const user = userSnap.data() ?? {};
  const accessLevel = String(user.accessLevel ?? user.access_level ?? "").trim().toLowerCase();
  if (accessLevel === "admin") return caller;

  throw new HttpsError("permission-denied", "Somente Admin pode alterar papel Instrutor K9.");
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
    action_required: targetScreen !== "none",
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
    action_required: type === "vehicle_crew_invitation",
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
    action_required: type === "training_promotion_requested",
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
    action_required: true,
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

export const setK9InstructorRole = onCall({region}, async (request) => {
  const caller = await requireAdmin(request.auth);
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
      try {
        await applyApprovedTrainingPromotion(event.params.requestId, after);
      } catch (error) {
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
      return;
    }

    if (after.status === "rejected") {
      await notifyPromotionRequester("training_promotion_rejected", event.params.requestId, after);
      await change.after.ref.set({
        processed_at: admin.firestore.FieldValue.serverTimestamp(),
        processing_status: "completed",
      }, {merge: true});
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
