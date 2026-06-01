import * as crypto from "crypto";
import * as admin from "firebase-admin";
import {logger} from "firebase-functions";
import {onDocumentCreated} from "firebase-functions/v2/firestore";
import {HttpsError, onCall, onRequest} from "firebase-functions/v2/https";

admin.initializeApp();

const db = admin.firestore();
const region = "southamerica-east1";

type JsonMap = Record<string, unknown>;

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

async function verifyOccurrenceDocument(occurrenceId: string): Promise<JsonMap> {
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
  const intact = storedHash === recalculatedHash;

  return {
    ...baseResult,
    status: intact ? "intact" : "broken",
    sealed: true,
    intact,
    recalculated_hash: recalculatedHash,
    events_checked: events.length,
    signatures_checked: signatures.length,
    participations_checked: participations.length,
    correction_requests_checked: correctionRequests.length,
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
  const title = ok ? "Selo íntegro" : "Selo não confirmado";
  const accent = ok ? "#1f9d52" : "#b42318";
  const message = ok ?
    "O hash armazenado confere com o recálculo feito no servidor." :
    status === "broken" ?
      "O hash armazenado não confere com o recálculo do servidor." :
      "Não foi possível confirmar a integridade deste registro.";
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
  </style>
</head>
<body>
  <main>
    <section class="card">
      <span class="badge">${htmlEscape(title)}</span>
      <h1>Verificação de ocorrência</h1>
      <p>${htmlEscape(message)}</p>
      <dl>
        <dt>Ocorrência</dt><dd><code>${htmlEscape(result.occurrence_id)}</code></dd>
        <dt>Natureza</dt><dd>${htmlEscape(result.type_name ?? "Não informada")}</dd>
        <dt>Status</dt><dd>${htmlEscape(result.status_current ?? status)}</dd>
        <dt>Versão do hash</dt><dd>${htmlEscape(result.hash_version)}</dd>
        <dt>Hash armazenado</dt><dd><code>${htmlEscape(result.stored_hash ?? "-")}</code></dd>
        <dt>Hash recalculado</dt><dd><code>${htmlEscape(result.recalculated_hash ?? "-")}</code></dd>
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

    const result = await verifyOccurrenceDocument(occurrenceId);
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
