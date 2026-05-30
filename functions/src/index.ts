import * as crypto from "crypto";
import * as admin from "firebase-admin";
import {logger} from "firebase-functions";
import {onDocumentCreated} from "firebase-functions/v2/firestore";
import {HttpsError, onCall} from "firebase-functions/v2/https";

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
  return emailMatchesRa(caller.email, handlerId) ||
    teamAuthKeys.includes(`${handlerId}:${caller.uid}`);
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
  const accepted = new Set(acceptedHandlerIds(occurrence));
  return teamMembers(occurrence)
    .filter((member) => String(member.role ?? "integrante") !== "titular")
    .map(handlerIdForMember)
    .filter((handlerId) => handlerId.length > 0 && accepted.has(handlerId))
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

function eventHashPayload(eventId: string, event: JsonMap): JsonMap | null {
  if (event.deleted_at !== undefined && event.deleted_at !== null) return null;
  const photoMetadata = mapArray(event.photo_metadata);
  const photoHashes = photoMetadata
    .map((metadata) => stringValue(metadata.sha256))
    .filter((hash): hash is string => Boolean(hash))
    .sort();
  return {
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
    photo_hashes: photoHashes,
  };
}

function buildHashPayloadV4(
  occurrence: JsonMap,
  events: Array<{id: string; data: JsonMap}>,
  signatures: JsonMap[],
  participations: JsonMap[],
  correctionRequests: JsonMap[],
): JsonMap {
  const eventPayload = events
    .map((event) => eventHashPayload(event.id, event.data))
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

  return {
    details: normalizeForHash(occurrence.details ?? null),
    dog_id: occurrence.dog_id ?? "",
    final_report: occurrence.final_report ?? null,
    finalization_photos: stringArray(occurrence.finalization_photos),
    gps_accuracy: occurrence.gps_accuracy ?? null,
    gps_lat: occurrence.gps_lat ?? null,
    gps_lng: occurrence.gps_lng ?? null,
    hash_version: 4,
    location_address: occurrence.location_address ?? null,
    primary_handler_id: occurrence.primary_handler_id ?? "",
    primary_handler_ra: occurrence.primary_handler_ra ?? null,
    results: stringArray(occurrence.results),
    shift_id: occurrence.shift_id ?? "",
    crew_id: occurrence.crew_id ?? null,
    service_dog_id: occurrence.service_dog_id ?? occurrence.dog_id ?? "",
    vehicle_id: occurrence.vehicle_id ?? null,
    vehicle_label: occurrence.vehicle_label ?? null,
    vehicle_model: occurrence.vehicle_model ?? null,
    vehicle_prefix: occurrence.vehicle_prefix ?? null,
    vehicle_unit: occurrence.vehicle_unit ?? null,
    started_at: normalizeForHash(occurrence.started_at),
    events: eventPayload,
    type_code: occurrence.type_code ?? "",
    type_name: occurrence.type_name ?? "",
    finalization_photo_hashes: stringArray(occurrence.finalization_photo_hashes),
    team: sortedTeam,
    signatures: sortedSignatures,
    accepted_handler_ids: stringArray(occurrence.accepted_handler_ids),
    declined_handler_ids: stringArray(occurrence.declined_handler_ids),
    edit_authorized_handler_ids: stringArray(occurrence.edit_authorized_handler_ids),
    participation_revision: Number(occurrence.participation_revision ?? 0),
    participation_status: occurrence.participation_status ?? null,
    pending_handler_ids: stringArray(occurrence.pending_handler_ids),
    signature_round: signatureRound(occurrence),
    participations: sortedParticipations,
    correction_requests: correctionPayload,
  };
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
