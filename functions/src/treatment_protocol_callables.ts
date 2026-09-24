/**
 * Callables do ciclo de Tratamentos e Administração de Doses (F20.TREATMENT-V1).
 *
 * Agregado canônico:
 *   dogs/{dogId}/treatment_protocols/{protocolId}
 *   dogs/{dogId}/treatment_protocols/{protocolId}/doses/{doseId}
 *
 * Transições geram ClinicalEvents imutáveis:
 *   treatment_start (treatment_start_v1)
 *   treatment_note (treatment_note_v1)
 *   dose_note (dose_note_v1)
 *
 * Atualização atômica das projeções de ClinicalCase:
 *   event_count, last_event_at, updated_at, revision, active_treatments_count, has_pending_schedule
 *
 * Operações idempotentes via receipt em clinical_cases/{caseId}/operations/{operationId}.
 * Admin SDK (bypassa Rules); clientes não escrevem diretamente.
 */

import * as crypto from "crypto";
import {FieldValue, Timestamp} from "firebase-admin/firestore";
import {CallableRequest, HttpsError} from "firebase-functions/v2/https";

import {
  isTerminalCaseStatus,
  parseClinicalCaseStatus,
} from "./clinical_domain";
import {
  JsonMap,
  assertDogId,
  normalizeOperationId,
  recordedByPayload,
  stableStringify,
  stringValue,
} from "./health_document_logic";

export const TREATMENT_SCHEMA_VERSION = 1;

export interface TreatmentCaller {
  uid: string;
  email: string;
  ra: string;
  name: string;
}

export interface TreatmentProtocolCallableDeps {
  db: FirebaseFirestore.Firestore;
  requireRecordClinical: (
    auth: CallableRequest["auth"],
  ) => Promise<TreatmentCaller>;
  requireFinalizeClinical: (
    auth: CallableRequest["auth"],
  ) => Promise<TreatmentCaller>;
  requireAmendClinical: (
    auth: CallableRequest["auth"],
  ) => Promise<TreatmentCaller>;
  requireRecordRoutine: (
    auth: CallableRequest["auth"],
  ) => Promise<TreatmentCaller>;
  requireDogAccess: (
    auth: CallableRequest["auth"],
    caller: TreatmentCaller,
    dogId: string,
    dog: Record<string, unknown>,
  ) => Promise<void>;
  isAdministrativeAuthority: (
    auth: CallableRequest["auth"],
    caller: TreatmentCaller,
  ) => Promise<boolean>;
  hasOtherOpenCaseSchedule: (
    dogId: string,
    caseId: string,
    excludeProtocolId?: string,
  ) => Promise<boolean>;
  now?: () => Date;
}

export function protocolRef(
  db: FirebaseFirestore.Firestore,
  dogId: string,
  protocolId: string,
): FirebaseFirestore.DocumentReference {
  return db
    .collection("dogs")
    .doc(dogId)
    .collection("treatment_protocols")
    .doc(protocolId);
}

export function doseRef(
  db: FirebaseFirestore.Firestore,
  dogId: string,
  protocolId: string,
  doseId: string,
): FirebaseFirestore.DocumentReference {
  return protocolRef(db, dogId, protocolId).collection("doses").doc(doseId);
}

export function caseRef(
  db: FirebaseFirestore.Firestore,
  dogId: string,
  caseId: string,
): FirebaseFirestore.DocumentReference {
  return db
    .collection("dogs")
    .doc(dogId)
    .collection("clinical_cases")
    .doc(caseId);
}

export function clinicalEventRef(
  db: FirebaseFirestore.Firestore,
  dogId: string,
  caseId: string,
  eventId: string,
): FirebaseFirestore.DocumentReference {
  return caseRef(db, dogId, caseId).collection("clinical_events").doc(eventId);
}

export function treatmentOperationRef(
  db: FirebaseFirestore.Firestore,
  dogId: string,
  caseId: string,
  operationId: string,
): FirebaseFirestore.DocumentReference {
  return caseRef(db, dogId, caseId).collection("operations").doc(operationId);
}

export function scheduleRef(
  db: FirebaseFirestore.Firestore,
  dogId: string,
  scheduleId: string,
): FirebaseFirestore.DocumentReference {
  return db
    .collection("dogs")
    .doc(dogId)
    .collection("health_schedule")
    .doc(scheduleId);
}

function sha256Hex(data: string | Buffer): string {
  return crypto.createHash("sha256").update(data).digest("hex");
}

/**
 * Identidade determinística canônica de DoseAdministration:
 * SHA-256 da serialização length-prefix (UTF-8) dos dois componentes lógicos.
 * u32be(len(A)) || utf8(A) || u32be(len(B)) || utf8(B)
 *
 * Byte-a-byte equivalente ao Dart `DoseIdentity.deriveDoseId()`.
 */
export function deriveDoseId(protocolId: string, plannedDoseId: string): string {
  const p = protocolId.trim();
  const d = plannedDoseId.trim();
  if (!p) {
    throw new HttpsError(
      "invalid-argument",
      "protocolId é obrigatório na identidade da dose.",
    );
  }
  if (!d) {
    throw new HttpsError(
      "invalid-argument",
      "plannedDoseId é obrigatório na identidade da dose.",
    );
  }
  const pBytes = Buffer.from(p, "utf8");
  const dBytes = Buffer.from(d, "utf8");
  const buf = Buffer.alloc(4 + pBytes.length + 4 + dBytes.length);
  buf.writeUInt32BE(pBytes.length, 0);
  pBytes.copy(buf, 4);
  buf.writeUInt32BE(dBytes.length, 4 + pBytes.length);
  dBytes.copy(buf, 4 + pBytes.length + 4);
  return sha256Hex(buf);
}

export function deterministicProtocolId(
  dogId: string,
  caseId: string,
  operationId: string,
): string {
  const hash = sha256Hex(`prot:${dogId}:${caseId}:${operationId}`).slice(0, 16);
  return `tp_${hash}`;
}

export function deterministicEventId(
  dogId: string,
  caseId: string,
  eventType: string,
  operationId: string,
): string {
  const hash = sha256Hex(`evt:${dogId}:${caseId}:${eventType}:${operationId}`).slice(0, 16);
  return `evt_${hash}`;
}

export function deterministicDoseScheduleId(
  dogId: string,
  protocolId: string,
  plannedDoseId: string,
): string {
  const hash = sha256Hex(`sched:${dogId}:${protocolId}:${plannedDoseId}`).slice(0, 16);
  return `sch_${hash}`;
}

export function auditDocId(
  dogId: string,
  caseId: string,
  operationId: string,
): string {
  return `audit_treat_${sha256Hex(`${dogId}:${caseId}:${operationId}`).slice(0, 20)}`;
}

export const VALID_DOSE_ROUTES = new Set([
  "oral",
  "topical",
  "injectable",
  "inhalation",
  "ophthalmic",
  "otic",
]);

export const VALID_SCHEDULE_TYPES = new Set([
  "interval",
  "fixed_times",
]);

async function loadDog(
  db: FirebaseFirestore.Firestore,
  dogId: string,
): Promise<JsonMap> {
  const snap = await db.collection("dogs").doc(dogId).get();
  if (!snap.exists) {
    throw new HttpsError("not-found", `Cão ${dogId} não encontrado.`);
  }
  return (snap.data() ?? {}) as JsonMap;
}

function parseRequiredString(data: JsonMap, field: string): string {
  const val = stringValue(data[field]);
  if (!val) {
    throw new HttpsError("invalid-argument", `Campo obrigatório ausente: ${field}`);
  }
  return val;
}

function parsePositiveNumber(value: unknown, field: string): number {
  const num = typeof value === "number" ? value : Number(value);
  if (isNaN(num) || num <= 0 || !isFinite(num)) {
    throw new HttpsError("invalid-argument", `${field} deve ser um número positivo.`);
  }
  return num;
}

// ─────────────────────────────────────────────────────────────────────────────
// 1. CREATE TREATMENT PROTOCOL
// ─────────────────────────────────────────────────────────────────────────────

export async function runHealthCreateTreatmentProtocol(
  request: CallableRequest,
  deps: TreatmentProtocolCallableDeps,
): Promise<JsonMap> {
  const caller = await deps.requireRecordClinical(request.auth);
  const data = (request.data ?? {}) as JsonMap;

  const dogId = assertDogId(data["dogId"] ?? data["dog_id"]);
  const caseId = parseRequiredString(data, "caseId");
  const medicationName = parseRequiredString(data, "medicationName");

  const doseRaw = (data["dose"] ?? {}) as JsonMap;
  const doseValue = parsePositiveNumber(doseRaw["value"], "dose.value");
  const doseUnit = parseRequiredString(doseRaw, "unit");
  const dosePerKg = Boolean(doseRaw["per_kg"] ?? doseRaw["perKg"] ?? false);
  const doseRoute = parseRequiredString(doseRaw, "route");
  if (!VALID_DOSE_ROUTES.has(doseRoute)) {
    throw new HttpsError(
      "invalid-argument",
      `Via de administração inválida: ${doseRoute}`,
    );
  }

  const scheduleRaw = (data["schedule"] ?? {}) as JsonMap;
  const scheduleType = parseRequiredString(scheduleRaw, "type");
  if (scheduleType === "prn") {
    throw new HttpsError(
      "failed-precondition",
      "Tipo de agendamento 'prn' (se necessário) não é suportado em Treatment V1. Use 'interval' ou 'fixed_times'.",
    );
  }
  if (!VALID_SCHEDULE_TYPES.has(scheduleType)) {
    throw new HttpsError(
      "invalid-argument",
      `Tipo de agendamento de tratamento inválido: ${scheduleType}`,
    );
  }

  let intervalMinutes: number | null = null;
  if (scheduleType === "interval") {
    intervalMinutes = parsePositiveNumber(
      scheduleRaw["interval_minutes"] ?? scheduleRaw["intervalMinutes"],
      "schedule.interval_minutes",
    );
  }

  let timesOfDay: string[] = [];
  if (scheduleType === "fixed_times") {
    const rawTimes = scheduleRaw["times_of_day"] ?? scheduleRaw["timesOfDay"];
    if (!Array.isArray(rawTimes) || rawTimes.length === 0) {
      throw new HttpsError(
        "invalid-argument",
        "schedule.times_of_day deve ser uma lista não vazia de horários.",
      );
    }
    timesOfDay = rawTimes.map((t) => String(t).trim());
  }

  const timezone = stringValue(scheduleRaw["timezone"]) ?? "America/Sao_Paulo";
  const toleranceMinutes =
    typeof scheduleRaw["tolerance_minutes"] === "number"
      ? scheduleRaw["tolerance_minutes"]
      : typeof scheduleRaw["toleranceMinutes"] === "number"
      ? scheduleRaw["toleranceMinutes"]
      : 30;

  const rawDuration = data["durationDays"] ?? data["duration_days"];
  if (rawDuration == null) {
    throw new HttpsError(
      "invalid-argument",
      "durationDays é obrigatório em Treatment V1 (1 a 30 dias) para materialização determinística e finita de todas as doses.",
    );
  }
  const durationDays = parsePositiveNumber(rawDuration, "durationDays");
  if (durationDays > 30) {
    throw new HttpsError(
      "invalid-argument",
      "durationDays não pode exceder 30 dias em Treatment V1.",
    );
  }

  let totalDoses = 0;
  if (scheduleType === "interval" && intervalMinutes) {
    const totalMinutes = durationDays * 24 * 60;
    totalDoses = Math.floor(totalMinutes / intervalMinutes);
  } else if (scheduleType === "fixed_times" && timesOfDay.length > 0) {
    totalDoses = durationDays * timesOfDay.length;
  }

  if (totalDoses <= 0) {
    throw new HttpsError(
      "invalid-argument",
      "Configuração de agendamento resultou em 0 doses calculadas para a duração informada.",
    );
  }

  if (totalDoses > 50) {
    throw new HttpsError(
      "invalid-argument",
      `Protocolo excede o limite máximo de 50 doses planejadas em Treatment V1 (${totalDoses} doses calculadas para ${durationDays} dias). Ajuste o intervalo ou a duração do tratamento.`,
    );
  }

  const instructions = stringValue(data["instructions"]) ?? null;
  const dosageDisplay = stringValue(data["dosageDisplay"] ?? data["dosage_display"]) ?? null;
  const frequencyDisplay = stringValue(data["frequencyDisplay"] ?? data["frequency_display"]) ?? null;

  const professionalRaw = data["professional"] as JsonMap | undefined;
  if (!professionalRaw || !stringValue(professionalRaw["name"])) {
    throw new HttpsError(
      "invalid-argument",
      "professional com name é obrigatório para prescrição de tratamento.",
    );
  }

  const sourceDocRaw = (data["sourceDocument"] ?? data["source_document"]) as JsonMap | undefined;
  if (!sourceDocRaw || !stringValue(sourceDocRaw["health_document_id"] ?? sourceDocRaw["healthDocumentId"])) {
    throw new HttpsError(
      "invalid-argument",
      "source_document com health_document_id é obrigatório para prescrição de tratamento.",
    );
  }

  const operationId = normalizeOperationId(data["operationId"] ?? data["operation_id"]);

  const dog = await loadDog(deps.db, dogId);
  await deps.requireDogAccess(request.auth, caller, dogId, dog);
  const isAdmin = await deps.isAdministrativeAuthority(request.auth, caller);

  const protocolId = deterministicProtocolId(dogId, caseId, operationId);
  const eventId = deterministicEventId(dogId, caseId, "treatment_start", operationId);

  const pRef = protocolRef(deps.db, dogId, protocolId);
  const cRef = caseRef(deps.db, dogId, caseId);
  const evtRef = clinicalEventRef(deps.db, dogId, caseId, eventId);
  const opRef = treatmentOperationRef(deps.db, dogId, caseId, operationId);
  const auditRef = deps.db
    .collection("auditLogs")
    .doc(auditDocId(dogId, caseId, operationId));

  const nowDate = (deps.now ?? (() => new Date()))();
  const nowTs = Timestamp.fromDate(nowDate);

  const rawStartDate = data["startDate"] ?? data["start_date"];
  const startDate = rawStartDate ? new Date(String(rawStartDate)) : nowDate;
  if (isNaN(startDate.getTime())) {
    throw new HttpsError("invalid-argument", "startDate inválido.");
  }
  const startTs = Timestamp.fromDate(startDate);

  const rawEndDate = data["endDate"] ?? data["end_date"];
  const endTs = rawEndDate ? Timestamp.fromDate(new Date(String(rawEndDate))) : null;
  if (endTs && endTs.toMillis() < startTs.toMillis()) {
    throw new HttpsError("invalid-argument", "endDate não pode ser anterior a startDate.");
  }

  const fingerprint = sha256Hex(
    stableStringify({
      action: "create_treatment_protocol",
      dogId,
      caseId,
      medicationName,
      doseValue,
      doseUnit,
      dosePerKg,
      doseRoute,
      scheduleType,
      intervalMinutes,
      timesOfDay,
      timezone,
      durationDays,
    }),
  );

  return await deps.db.runTransaction(async (tx) => {
    const opSnap = await tx.get(opRef);
    if (opSnap.exists) {
      const receipt = opSnap.data() as JsonMap;
      if (receipt["fingerprint"] !== fingerprint) {
        throw new HttpsError(
          "already-exists",
          `operationId '${operationId}' já utilizado com payload diferente.`,
        );
      }
      return receipt["result"] as JsonMap;
    }

    const caseSnap = await tx.get(cRef);
    if (!caseSnap.exists) {
      throw new HttpsError("not-found", `Caso clínico ${caseId} não encontrado.`);
    }
    const caseData = (caseSnap.data() ?? {}) as JsonMap;
    const rawCaseStatus = stringValue(caseData["clinical_status"]);
    const currentCaseStatus = rawCaseStatus ? parseClinicalCaseStatus(rawCaseStatus) : null;
    if (currentCaseStatus && isTerminalCaseStatus(currentCaseStatus)) {
      throw new HttpsError(
        "failed-precondition",
        `Caso clínico ${caseId} está em estado terminal (${currentCaseStatus}).`,
      );
    }

    const recordedBy = recordedByPayload(caller, isAdmin);

    const protocolDoc: JsonMap = {
      protocol_id: protocolId,
      id: protocolId,
      dog_id: dogId,
      case_id: caseId,
      medication_name: medicationName,
      dose: {
        value: doseValue,
        unit: doseUnit,
        per_kg: dosePerKg,
        route: doseRoute,
      },
      schedule: {
        type: scheduleType,
        interval_minutes: intervalMinutes,
        times_of_day: timesOfDay,
        timezone,
        tolerance_minutes: toleranceMinutes,
      },
      start_date: startTs,
      recorded_by: recordedBy,
      professional: professionalRaw,
      source_document: sourceDocRaw,
      status: "active",
      schema_version: TREATMENT_SCHEMA_VERSION,
      created_at: nowTs,
      updated_at: nowTs,
      doses_administered: 0,
      revision: 1,
    };
    if (durationDays != null) protocolDoc["duration_days"] = durationDays;
    if (endTs != null) protocolDoc["end_date"] = endTs;
    if (instructions) protocolDoc["instructions"] = instructions;
    if (dosageDisplay) protocolDoc["dosage_display"] = dosageDisplay;
    if (frequencyDisplay) protocolDoc["frequency_display"] = frequencyDisplay;

    // Gerar plano completo de doses na agenda (todas as doses até totalDoses, máximo 50)
    const plannedDoseIds: string[] = [];
    const scheduleItemIds: string[] = [];

    if (scheduleType === "interval" && intervalMinutes) {
      const intervalMs = intervalMinutes * 60 * 1000;

      for (let i = 0; i < totalDoses; i++) {
        const doseInstantMs = startDate.getTime() + i * intervalMs;
        const doseTs = Timestamp.fromMillis(doseInstantMs);
        const dueUntilTs = Timestamp.fromMillis(doseInstantMs + toleranceMinutes * 60 * 1000);
        const plannedDoseId = `dose_${i + 1}`;
        const sId = deterministicDoseScheduleId(dogId, protocolId, plannedDoseId);
        const sRef = scheduleRef(deps.db, dogId, sId);

        const scheduleDoc: JsonMap = {
          dog_id: dogId,
          schedule_type: "dose",
          title: `Dose: ${medicationName} (${doseValue} ${doseUnit})`,
          scheduled_for: doseTs,
          due_until: dueUntilTs,
          timezone,
          lifecycle_status: "open",
          source_type: "treatment_protocol",
          source_id: protocolId,
          case_id: caseId,
          planned_dose_id: plannedDoseId,
          created_at: nowTs,
          recorded_by: recordedBy,
          schema_version: 1,
          revision: 1,
        };
        tx.set(sRef, scheduleDoc);
        plannedDoseIds.push(plannedDoseId);
        scheduleItemIds.push(sId);
      }
    } else if (scheduleType === "fixed_times" && timesOfDay.length > 0) {
      let count = 0;
      for (let day = 0; day < durationDays; day++) {
        for (const tod of timesOfDay) {
          count++;
          if (count > totalDoses) break;
          const [hhStr, mmStr] = tod.split(":");
          const hh = parseInt(hhStr, 10) || 0;
          const mm = parseInt(mmStr, 10) || 0;
          const doseDate = new Date(startDate.getTime() + day * 24 * 60 * 60 * 1000);
          doseDate.setHours(hh, mm, 0, 0);
          const doseTs = Timestamp.fromDate(doseDate);
          const dueUntilTs = Timestamp.fromMillis(doseDate.getTime() + toleranceMinutes * 60 * 1000);
          const plannedDoseId = `dose_${count}`;
          const sId = deterministicDoseScheduleId(dogId, protocolId, plannedDoseId);
          const sRef = scheduleRef(deps.db, dogId, sId);

          const scheduleDoc: JsonMap = {
            dog_id: dogId,
            schedule_type: "dose",
            title: `Dose: ${medicationName} (${doseValue} ${doseUnit})`,
            scheduled_for: doseTs,
            due_until: dueUntilTs,
            timezone,
            lifecycle_status: "open",
            source_type: "treatment_protocol",
            source_id: protocolId,
            case_id: caseId,
            planned_dose_id: plannedDoseId,
            created_at: nowTs,
            recorded_by: recordedBy,
            schema_version: 1,
            revision: 1,
          };
          tx.set(sRef, scheduleDoc);
          plannedDoseIds.push(plannedDoseId);
          scheduleItemIds.push(sId);
        }
      }
    }

    protocolDoc["doses_planned"] = totalDoses;
    protocolDoc["doses_remaining"] = totalDoses;

    const eventDoc: JsonMap = {
      entity_kind: "clinical_event",
      event_id: eventId,
      case_id: caseId,
      dog_id: dogId,
      treatment_protocol_id: protocolId,
      event_type: "treatment_start",
      payload_type: "treatment_start_v1",
      payload_version: 1,
      status: "final",
      occurred_at: nowTs,
      recorded_at: nowTs,
      updated_at: nowTs,
      recorded_by: recordedBy,
      content: {
        protocol_id: protocolId,
        medication_name: medicationName,
        dose: protocolDoc["dose"],
        schedule: protocolDoc["schedule"],
        start_date: startTs,
      },
      revision: 1,
      schema_version: 1,
    };
    if (professionalRaw) eventDoc["professional"] = professionalRaw;

    // Atualiza projeções do caso clínico
    const caseRev = typeof caseData["revision"] === "number" ? caseData["revision"] : 1;
    const casePatch: JsonMap = {
      event_count: FieldValue.increment(1),
      last_event_at: nowTs,
      updated_at: nowTs,
      revision: caseRev + 1,
      active_treatments_count: FieldValue.increment(1),
      has_pending_schedule: true,
    };

    // Iniciar tratamento leva o caso para under_treatment se estiver open, under_investigation ou monitoring
    if (
      currentCaseStatus === "open" ||
      currentCaseStatus === "under_investigation" ||
      currentCaseStatus === "monitoring"
    ) {
      casePatch["clinical_status"] = "under_treatment";
    }

    tx.set(cRef, casePatch, {merge: true});
    tx.set(pRef, protocolDoc);
    tx.set(evtRef, eventDoc);

    const result: JsonMap = {
      success: true,
      protocolId,
      eventId,
      status: "active",
      plannedDoseCount: plannedDoseIds.length,
    };

    tx.set(opRef, {
      operation_id: operationId,
      fingerprint,
      result,
      created_at: nowTs,
    });

    tx.set(auditRef, {
      action: "health.create_treatment_protocol",
      actor: recordedBy,
      dog_id: dogId,
      case_id: caseId,
      protocol_id: protocolId,
      timestamp: nowTs,
    });

    return result;
  });
}

// ─────────────────────────────────────────────────────────────────────────────
// 2. PAUSE TREATMENT PROTOCOL
// ─────────────────────────────────────────────────────────────────────────────

export async function runHealthPauseTreatmentProtocol(
  request: CallableRequest,
  deps: TreatmentProtocolCallableDeps,
): Promise<JsonMap> {
  const caller = await deps.requireRecordClinical(request.auth);
  const data = (request.data ?? {}) as JsonMap;

  const dogId = assertDogId(data["dogId"] ?? data["dog_id"]);
  const protocolId = parseRequiredString(data, "protocolId");
  const pauseReason = parseRequiredString(data, "pauseReason");
  const operationId = normalizeOperationId(data["operationId"] ?? data["operation_id"]);

  const dog = await loadDog(deps.db, dogId);
  await deps.requireDogAccess(request.auth, caller, dogId, dog);
  const isAdmin = await deps.isAdministrativeAuthority(request.auth, caller);

  const pRef = protocolRef(deps.db, dogId, protocolId);
  const nowDate = (deps.now ?? (() => new Date()))();
  const nowTs = Timestamp.fromDate(nowDate);

  const fingerprint = sha256Hex(
    stableStringify({
      action: "pause_treatment_protocol",
      dogId,
      protocolId,
      pauseReason,
    }),
  );

  return await deps.db.runTransaction(async (tx) => {
    const pSnap = await tx.get(pRef);
    if (!pSnap.exists) {
      throw new HttpsError("not-found", `Protocolo de tratamento ${protocolId} não encontrado.`);
    }
    const pData = (pSnap.data() ?? {}) as JsonMap;
    const caseId = stringValue(pData["case_id"]);
    if (!caseId) {
      throw new HttpsError("internal", "Protocolo sem case_id vinculado.");
    }

    const opRef = treatmentOperationRef(deps.db, dogId, caseId, operationId);
    const opSnap = await tx.get(opRef);
    if (opSnap.exists) {
      const receipt = opSnap.data() as JsonMap;
      if (receipt["fingerprint"] !== fingerprint) {
        throw new HttpsError(
          "already-exists",
          `operationId '${operationId}' já utilizado com payload diferente.`,
        );
      }
      return receipt["result"] as JsonMap;
    }

    if (pData["status"] !== "active") {
      throw new HttpsError(
        "failed-precondition",
        `Protocolo ${protocolId} não está ativo (status atual: ${pData["status"]}).`,
      );
    }

    const cRef = caseRef(deps.db, dogId, caseId);
    const caseSnap = await tx.get(cRef);
    if (!caseSnap.exists) {
      throw new HttpsError("not-found", `Caso clínico ${caseId} não encontrado.`);
    }
    const caseData = (caseSnap.data() ?? {}) as JsonMap;

    const recordedBy = recordedByPayload(caller, isAdmin);
    const eventId = deterministicEventId(dogId, caseId, "treatment_pause", operationId);
    const evtRef = clinicalEventRef(deps.db, dogId, caseId, eventId);
    const auditRef = deps.db
      .collection("auditLogs")
      .doc(auditDocId(dogId, caseId, operationId));

    const pRev = typeof pData["revision"] === "number" ? pData["revision"] : 1;

    // Leitura estrita de todas as doses antes de qualquer mutação (Firestore transaction read-before-write invariant)
    const dosesPlanned = typeof pData["doses_planned"] === "number"
      ? pData["doses_planned"]
      : 50;

    const scheduleItemsToPause: {
      ref: FirebaseFirestore.DocumentReference;
      data: JsonMap;
    }[] = [];

    for (let i = 1; i <= dosesPlanned; i++) {
      const plannedDoseId = `dose_${i}`;
      const sId = deterministicDoseScheduleId(dogId, protocolId, plannedDoseId);
      const sRef = scheduleRef(deps.db, dogId, sId);
      const sSnap = await tx.get(sRef);
      if (sSnap.exists) {
        const sData = sSnap.data() as JsonMap;
        if (sData["lifecycle_status"] === "open") {
          scheduleItemsToPause.push({ref: sRef, data: sData});
        }
      }
    }

    tx.set(
      pRef,
      {
        status: "paused",
        paused_at: nowTs,
        pause_reason: pauseReason,
        updated_at: nowTs,
        revision: pRev + 1,
      },
      {merge: true},
    );

    const eventDoc: JsonMap = {
      entity_kind: "clinical_event",
      event_id: eventId,
      case_id: caseId,
      dog_id: dogId,
      treatment_protocol_id: protocolId,
      event_type: "treatment_note",
      payload_type: "treatment_note_v1",
      payload_version: 1,
      status: "final",
      occurred_at: nowTs,
      recorded_at: nowTs,
      updated_at: nowTs,
      recorded_by: recordedBy,
      content: {
        action: "pause",
        protocol_id: protocolId,
        reason: pauseReason,
      },
      revision: 1,
      schema_version: 1,
    };
    tx.set(evtRef, eventDoc);

    // Pausar todas as doses futuras pendentes do protocolo pausado
    for (const item of scheduleItemsToPause) {
      const sRev = typeof item.data["revision"] === "number" ? item.data["revision"] : 1;
      tx.set(
        item.ref,
        {
          is_paused: true,
          paused_at: nowTs,
          pause_reason: pauseReason,
          updated_at: nowTs,
          revision: sRev + 1,
        },
        {merge: true},
      );
    }

    const caseRev = typeof caseData["revision"] === "number" ? caseData["revision"] : 1;
    tx.set(
      cRef,
      {
        event_count: FieldValue.increment(1),
        last_event_at: nowTs,
        updated_at: nowTs,
        revision: caseRev + 1,
        active_treatments_count: FieldValue.increment(-1),
      },
      {merge: true},
    );

    const result: JsonMap = {
      success: true,
      protocolId,
      eventId,
      status: "paused",
    };

    tx.set(opRef, {
      operation_id: operationId,
      fingerprint,
      result,
      created_at: nowTs,
    });

    tx.set(auditRef, {
      action: "health.pause_treatment_protocol",
      actor: recordedBy,
      dog_id: dogId,
      case_id: caseId,
      protocol_id: protocolId,
      timestamp: nowTs,
    });

    return result;
  });
}

// ─────────────────────────────────────────────────────────────────────────────
// 3. RESUME TREATMENT PROTOCOL
// ─────────────────────────────────────────────────────────────────────────────

export async function runHealthResumeTreatmentProtocol(
  request: CallableRequest,
  deps: TreatmentProtocolCallableDeps,
): Promise<JsonMap> {
  const caller = await deps.requireRecordClinical(request.auth);
  const data = (request.data ?? {}) as JsonMap;

  const dogId = assertDogId(data["dogId"] ?? data["dog_id"]);
  const protocolId = parseRequiredString(data, "protocolId");
  const operationId = normalizeOperationId(data["operationId"] ?? data["operation_id"]);

  const dog = await loadDog(deps.db, dogId);
  await deps.requireDogAccess(request.auth, caller, dogId, dog);
  const isAdmin = await deps.isAdministrativeAuthority(request.auth, caller);

  const pRef = protocolRef(deps.db, dogId, protocolId);
  const nowDate = (deps.now ?? (() => new Date()))();
  const nowTs = Timestamp.fromDate(nowDate);

  const fingerprint = sha256Hex(
    stableStringify({
      action: "resume_treatment_protocol",
      dogId,
      protocolId,
    }),
  );

  return await deps.db.runTransaction(async (tx) => {
    const pSnap = await tx.get(pRef);
    if (!pSnap.exists) {
      throw new HttpsError("not-found", `Protocolo de tratamento ${protocolId} não encontrado.`);
    }
    const pData = (pSnap.data() ?? {}) as JsonMap;
    const caseId = stringValue(pData["case_id"]);
    if (!caseId) {
      throw new HttpsError("internal", "Protocolo sem case_id vinculado.");
    }

    const opRef = treatmentOperationRef(deps.db, dogId, caseId, operationId);
    const opSnap = await tx.get(opRef);
    if (opSnap.exists) {
      const receipt = opSnap.data() as JsonMap;
      if (receipt["fingerprint"] !== fingerprint) {
        throw new HttpsError(
          "already-exists",
          `operationId '${operationId}' já utilizado com payload diferente.`,
        );
      }
      return receipt["result"] as JsonMap;
    }

    if (pData["status"] !== "paused") {
      throw new HttpsError(
        "failed-precondition",
        `Protocolo ${protocolId} não está pausado (status atual: ${pData["status"]}).`,
      );
    }

    const cRef = caseRef(deps.db, dogId, caseId);
    const caseSnap = await tx.get(cRef);
    if (!caseSnap.exists) {
      throw new HttpsError("not-found", `Caso clínico ${caseId} não encontrado.`);
    }
    const caseData = (caseSnap.data() ?? {}) as JsonMap;

    const recordedBy = recordedByPayload(caller, isAdmin);
    const eventId = deterministicEventId(dogId, caseId, "treatment_resume", operationId);
    const evtRef = clinicalEventRef(deps.db, dogId, caseId, eventId);
    const auditRef = deps.db
      .collection("auditLogs")
      .doc(auditDocId(dogId, caseId, operationId));

    const pRev = typeof pData["revision"] === "number" ? pData["revision"] : 1;

    // Leitura estrita de todas as doses antes de qualquer mutação (Firestore transaction read-before-write invariant)
    const dosesPlanned = typeof pData["doses_planned"] === "number"
      ? pData["doses_planned"]
      : 50;

    const scheduleItemsToResume: {
      ref: FirebaseFirestore.DocumentReference;
      data: JsonMap;
    }[] = [];

    for (let i = 1; i <= dosesPlanned; i++) {
      const plannedDoseId = `dose_${i}`;
      const sId = deterministicDoseScheduleId(dogId, protocolId, plannedDoseId);
      const sRef = scheduleRef(deps.db, dogId, sId);
      const sSnap = await tx.get(sRef);
      if (sSnap.exists) {
        const sData = sSnap.data() as JsonMap;
        if (sData["lifecycle_status"] === "open" && sData["is_paused"] === true) {
          scheduleItemsToResume.push({ref: sRef, data: sData});
        }
      }
    }

    tx.set(
      pRef,
      {
        status: "active",
        paused_at: null,
        pause_reason: null,
        updated_at: nowTs,
        revision: pRev + 1,
      },
      {merge: true},
    );

    const eventDoc: JsonMap = {
      entity_kind: "clinical_event",
      event_id: eventId,
      case_id: caseId,
      dog_id: dogId,
      treatment_protocol_id: protocolId,
      event_type: "treatment_note",
      payload_type: "treatment_note_v1",
      payload_version: 1,
      status: "final",
      occurred_at: nowTs,
      recorded_at: nowTs,
      updated_at: nowTs,
      recorded_by: recordedBy,
      content: {
        action: "resume",
        protocol_id: protocolId,
      },
      revision: 1,
      schema_version: 1,
    };
    tx.set(evtRef, eventDoc);

    // Despausar todas as doses futuras pendentes do protocolo retomado
    for (const item of scheduleItemsToResume) {
      const sRev = typeof item.data["revision"] === "number" ? item.data["revision"] : 1;
      tx.set(
        item.ref,
        {
          is_paused: false,
          paused_at: null,
          pause_reason: null,
          updated_at: nowTs,
          revision: sRev + 1,
        },
        {merge: true},
      );
    }

    const caseRev = typeof caseData["revision"] === "number" ? caseData["revision"] : 1;
    tx.set(
      cRef,
      {
        event_count: FieldValue.increment(1),
        last_event_at: nowTs,
        updated_at: nowTs,
        revision: caseRev + 1,
        active_treatments_count: FieldValue.increment(1),
      },
      {merge: true},
    );

    const result: JsonMap = {
      success: true,
      protocolId,
      eventId,
      status: "active",
    };

    tx.set(opRef, {
      operation_id: operationId,
      fingerprint,
      result,
      created_at: nowTs,
    });

    tx.set(auditRef, {
      action: "health.resume_treatment_protocol",
      actor: recordedBy,
      dog_id: dogId,
      case_id: caseId,
      protocol_id: protocolId,
      timestamp: nowTs,
    });

    return result;
  });
}

// ─────────────────────────────────────────────────────────────────────────────
// 4. COMPLETE TREATMENT PROTOCOL
// ─────────────────────────────────────────────────────────────────────────────

export async function runHealthCompleteTreatmentProtocol(
  request: CallableRequest,
  deps: TreatmentProtocolCallableDeps,
): Promise<JsonMap> {
  const caller = await deps.requireFinalizeClinical(request.auth);
  const data = (request.data ?? {}) as JsonMap;

  const dogId = assertDogId(data["dogId"] ?? data["dog_id"]);
  const protocolId = parseRequiredString(data, "protocolId");
  const operationId = normalizeOperationId(data["operationId"] ?? data["operation_id"]);

  const dog = await loadDog(deps.db, dogId);
  await deps.requireDogAccess(request.auth, caller, dogId, dog);
  const isAdmin = await deps.isAdministrativeAuthority(request.auth, caller);

  const pRef = protocolRef(deps.db, dogId, protocolId);
  const nowDate = (deps.now ?? (() => new Date()))();
  const nowTs = Timestamp.fromDate(nowDate);

  const fingerprint = sha256Hex(
    stableStringify({
      action: "complete_treatment_protocol",
      dogId,
      protocolId,
    }),
  );

  return await deps.db.runTransaction(async (tx) => {
    const pSnap = await tx.get(pRef);
    if (!pSnap.exists) {
      throw new HttpsError("not-found", `Protocolo de tratamento ${protocolId} não encontrado.`);
    }
    const pData = (pSnap.data() ?? {}) as JsonMap;
    const caseId = stringValue(pData["case_id"]);
    if (!caseId) {
      throw new HttpsError("internal", "Protocolo sem case_id vinculado.");
    }

    const opRef = treatmentOperationRef(deps.db, dogId, caseId, operationId);
    const opSnap = await tx.get(opRef);
    if (opSnap.exists) {
      const receipt = opSnap.data() as JsonMap;
      if (receipt["fingerprint"] !== fingerprint) {
        throw new HttpsError(
          "already-exists",
          `operationId '${operationId}' já utilizado com payload diferente.`,
        );
      }
      return receipt["result"] as JsonMap;
    }

    const prevStatus = pData["status"];
    if (prevStatus !== "active" && prevStatus !== "paused") {
      throw new HttpsError(
        "failed-precondition",
        `Protocolo ${protocolId} não pode ser concluído no estado '${prevStatus}'.`,
      );
    }

    const cRef = caseRef(deps.db, dogId, caseId);
    const caseSnap = await tx.get(cRef);
    if (!caseSnap.exists) {
      throw new HttpsError("not-found", `Caso clínico ${caseId} não encontrado.`);
    }
    const caseData = (caseSnap.data() ?? {}) as JsonMap;

    const recordedBy = recordedByPayload(caller, isAdmin);
    const eventId = deterministicEventId(dogId, caseId, "treatment_complete", operationId);
    const evtRef = clinicalEventRef(deps.db, dogId, caseId, eventId);
    const auditRef = deps.db
      .collection("auditLogs")
      .doc(auditDocId(dogId, caseId, operationId));

    const pRev = typeof pData["revision"] === "number" ? pData["revision"] : 1;

    // Leitura estrita de todas as doses antes de qualquer mutação (Firestore transaction read-before-write invariant)
    const dosesPlanned = typeof pData["doses_planned"] === "number"
      ? pData["doses_planned"]
      : 50;

    const scheduleItemsToCancel: {
      ref: FirebaseFirestore.DocumentReference;
      data: JsonMap;
    }[] = [];

    for (let i = 1; i <= dosesPlanned; i++) {
      const plannedDoseId = `dose_${i}`;
      const sId = deterministicDoseScheduleId(dogId, protocolId, plannedDoseId);
      const sRef = scheduleRef(deps.db, dogId, sId);
      const sSnap = await tx.get(sRef);
      if (sSnap.exists) {
        const sData = sSnap.data() as JsonMap;
        if (sData["lifecycle_status"] === "open") {
          scheduleItemsToCancel.push({ref: sRef, data: sData});
        }
      }
    }

    const currentActiveCount = typeof caseData["active_treatments_count"] === "number"
      ? caseData["active_treatments_count"]
      : 1;
    const newActiveCount = prevStatus === "active" ? Math.max(0, currentActiveCount - 1) : currentActiveCount;

    let hasOtherPending = false;
    if (newActiveCount === 0) {
      hasOtherPending = await deps.hasOtherOpenCaseSchedule(dogId, caseId, protocolId);
    }

    tx.set(
      pRef,
      {
        status: "completed",
        completed_at: nowTs,
        updated_at: nowTs,
        revision: pRev + 1,
      },
      {merge: true},
    );

    const eventDoc: JsonMap = {
      entity_kind: "clinical_event",
      event_id: eventId,
      case_id: caseId,
      dog_id: dogId,
      treatment_protocol_id: protocolId,
      event_type: "treatment_note",
      payload_type: "treatment_note_v1",
      payload_version: 1,
      status: "final",
      occurred_at: nowTs,
      recorded_at: nowTs,
      updated_at: nowTs,
      recorded_by: recordedBy,
      content: {
        action: "complete",
        protocol_id: protocolId,
      },
      revision: 1,
      schema_version: 1,
    };
    tx.set(evtRef, eventDoc);

    // Cancelar todas as doses futuras pendentes do protocolo concluído
    for (const item of scheduleItemsToCancel) {
      const sRev = typeof item.data["revision"] === "number" ? item.data["revision"] : 1;
      tx.set(
        item.ref,
        {
          lifecycle_status: "cancelled",
          cancelled_at: nowTs,
          cancelled_by: recordedBy,
          cancel_reason: "Tratamento concluído",
          updated_at: nowTs,
          revision: sRev + 1,
        },
        {merge: true},
      );
    }

    const caseRev = typeof caseData["revision"] === "number" ? caseData["revision"] : 1;

    const casePatch: JsonMap = {
      event_count: FieldValue.increment(1),
      last_event_at: nowTs,
      updated_at: nowTs,
      revision: caseRev + 1,
    };
    if (prevStatus === "active") {
      casePatch["active_treatments_count"] = FieldValue.increment(-1);
    }

    // Se nenhum tratamento ativo restar e caso estiver under_treatment -> transitar para monitoring
    if (newActiveCount === 0) {
      if (caseData["clinical_status"] === "under_treatment") {
        casePatch["clinical_status"] = "monitoring";
      }
      casePatch["has_pending_schedule"] = hasOtherPending;
    }

    tx.set(cRef, casePatch, {merge: true});

    const result: JsonMap = {
      success: true,
      protocolId,
      eventId,
      status: "completed",
      caseStatus: casePatch["clinical_status"] ?? caseData["clinical_status"],
    };

    tx.set(opRef, {
      operation_id: operationId,
      fingerprint,
      result,
      created_at: nowTs,
    });

    tx.set(auditRef, {
      action: "health.complete_treatment_protocol",
      actor: recordedBy,
      dog_id: dogId,
      case_id: caseId,
      protocol_id: protocolId,
      timestamp: nowTs,
    });

    return result;
  });
}

// ─────────────────────────────────────────────────────────────────────────────
// 5. CANCEL TREATMENT PROTOCOL
// ─────────────────────────────────────────────────────────────────────────────

export async function runHealthCancelTreatmentProtocol(
  request: CallableRequest,
  deps: TreatmentProtocolCallableDeps,
): Promise<JsonMap> {
  const caller = await deps.requireAmendClinical(request.auth);
  const data = (request.data ?? {}) as JsonMap;

  const dogId = assertDogId(data["dogId"] ?? data["dog_id"]);
  const protocolId = parseRequiredString(data, "protocolId");
  const cancelReason = parseRequiredString(data, "cancelReason");
  const operationId = normalizeOperationId(data["operationId"] ?? data["operation_id"]);

  const dog = await loadDog(deps.db, dogId);
  await deps.requireDogAccess(request.auth, caller, dogId, dog);
  const isAdmin = await deps.isAdministrativeAuthority(request.auth, caller);

  const pRef = protocolRef(deps.db, dogId, protocolId);
  const nowDate = (deps.now ?? (() => new Date()))();
  const nowTs = Timestamp.fromDate(nowDate);

  const fingerprint = sha256Hex(
    stableStringify({
      action: "cancel_treatment_protocol",
      dogId,
      protocolId,
      cancelReason,
    }),
  );

  return await deps.db.runTransaction(async (tx) => {
    const pSnap = await tx.get(pRef);
    if (!pSnap.exists) {
      throw new HttpsError("not-found", `Protocolo de tratamento ${protocolId} não encontrado.`);
    }
    const pData = (pSnap.data() ?? {}) as JsonMap;
    const caseId = stringValue(pData["case_id"]);
    if (!caseId) {
      throw new HttpsError("internal", "Protocolo sem case_id vinculado.");
    }

    const opRef = treatmentOperationRef(deps.db, dogId, caseId, operationId);
    const opSnap = await tx.get(opRef);
    if (opSnap.exists) {
      const receipt = opSnap.data() as JsonMap;
      if (receipt["fingerprint"] !== fingerprint) {
        throw new HttpsError(
          "already-exists",
          `operationId '${operationId}' já utilizado com payload diferente.`,
        );
      }
      return receipt["result"] as JsonMap;
    }

    const prevStatus = pData["status"];
    if (prevStatus !== "active" && prevStatus !== "paused") {
      throw new HttpsError(
        "failed-precondition",
        `Protocolo ${protocolId} não pode ser cancelado no estado '${prevStatus}'.`,
      );
    }

    const cRef = caseRef(deps.db, dogId, caseId);
    const caseSnap = await tx.get(cRef);
    if (!caseSnap.exists) {
      throw new HttpsError("not-found", `Caso clínico ${caseId} não encontrado.`);
    }
    const caseData = (caseSnap.data() ?? {}) as JsonMap;

    const recordedBy = recordedByPayload(caller, isAdmin);
    const eventId = deterministicEventId(dogId, caseId, "treatment_cancel", operationId);
    const evtRef = clinicalEventRef(deps.db, dogId, caseId, eventId);
    const auditRef = deps.db
      .collection("auditLogs")
      .doc(auditDocId(dogId, caseId, operationId));

    const pRev = typeof pData["revision"] === "number" ? pData["revision"] : 1;

    // Leitura estrita de todas as doses antes de qualquer mutação (Firestore transaction read-before-write invariant)
    const dosesPlanned = typeof pData["doses_planned"] === "number"
      ? pData["doses_planned"]
      : 50;

    const scheduleItemsToCancel: {
      ref: FirebaseFirestore.DocumentReference;
      data: JsonMap;
    }[] = [];

    for (let i = 1; i <= dosesPlanned; i++) {
      const plannedDoseId = `dose_${i}`;
      const sId = deterministicDoseScheduleId(dogId, protocolId, plannedDoseId);
      const sRef = scheduleRef(deps.db, dogId, sId);
      const sSnap = await tx.get(sRef);
      if (sSnap.exists) {
        const sData = sSnap.data() as JsonMap;
        if (sData["lifecycle_status"] === "open") {
          scheduleItemsToCancel.push({ref: sRef, data: sData});
        }
      }
    }

    const currentActiveCount = typeof caseData["active_treatments_count"] === "number"
      ? caseData["active_treatments_count"]
      : 1;
    const newActiveCount = prevStatus === "active" ? Math.max(0, currentActiveCount - 1) : currentActiveCount;

    let hasOtherPending = false;
    if (newActiveCount === 0) {
      hasOtherPending = await deps.hasOtherOpenCaseSchedule(dogId, caseId, protocolId);
    }

    tx.set(
      pRef,
      {
        status: "cancelled",
        cancelled_at: nowTs,
        cancel_reason: cancelReason,
        updated_at: nowTs,
        revision: pRev + 1,
      },
      {merge: true},
    );

    const eventDoc: JsonMap = {
      entity_kind: "clinical_event",
      event_id: eventId,
      case_id: caseId,
      dog_id: dogId,
      treatment_protocol_id: protocolId,
      event_type: "treatment_note",
      payload_type: "treatment_note_v1",
      payload_version: 1,
      status: "final",
      occurred_at: nowTs,
      recorded_at: nowTs,
      updated_at: nowTs,
      recorded_by: recordedBy,
      content: {
        action: "cancel",
        protocol_id: protocolId,
        reason: cancelReason,
      },
      revision: 1,
      schema_version: 1,
    };
    tx.set(evtRef, eventDoc);

    // Cancelar todas as doses futuras pendentes do protocolo cancelado
    for (const item of scheduleItemsToCancel) {
      const sRev = typeof item.data["revision"] === "number" ? item.data["revision"] : 1;
      tx.set(
        item.ref,
        {
          lifecycle_status: "cancelled",
          cancelled_at: nowTs,
          cancelled_by: recordedBy,
          cancel_reason: cancelReason,
          updated_at: nowTs,
          revision: sRev + 1,
        },
        {merge: true},
      );
    }

    const caseRev = typeof caseData["revision"] === "number" ? caseData["revision"] : 1;

    const casePatch: JsonMap = {
      event_count: FieldValue.increment(1),
      last_event_at: nowTs,
      updated_at: nowTs,
      revision: caseRev + 1,
    };
    if (prevStatus === "active") {
      casePatch["active_treatments_count"] = FieldValue.increment(-1);
    }
    if (newActiveCount === 0) {
      casePatch["has_pending_schedule"] = hasOtherPending;
    }
    tx.set(cRef, casePatch, {merge: true});

    const result: JsonMap = {
      success: true,
      protocolId,
      eventId,
      status: "cancelled",
    };

    tx.set(opRef, {
      operation_id: operationId,
      fingerprint,
      result,
      created_at: nowTs,
    });

    tx.set(auditRef, {
      action: "health.cancel_treatment_protocol",
      actor: recordedBy,
      dog_id: dogId,
      case_id: caseId,
      protocol_id: protocolId,
      timestamp: nowTs,
    });

    return result;
  });
}

// ─────────────────────────────────────────────────────────────────────────────
// 6. ADMINISTER DOSE
// ─────────────────────────────────────────────────────────────────────────────

export async function runHealthAdministerTreatmentDose(
  request: CallableRequest,
  deps: TreatmentProtocolCallableDeps,
): Promise<JsonMap> {
  const caller = await deps.requireRecordRoutine(request.auth);
  const data = (request.data ?? {}) as JsonMap;

  const dogId = assertDogId(data["dogId"] ?? data["dog_id"]);
  const protocolId = parseRequiredString(data, "protocolId");
  const plannedDoseId = parseRequiredString(data, "plannedDoseId");
  const scheduleItemId = stringValue(data["scheduleItemId"] ?? data["schedule_item_id"]) ?? null;
  const observations = stringValue(data["observations"]) ?? null;
  const sideEffects = stringValue(data["sideEffects"] ?? data["side_effects"]) ?? null;
  const rawAdministeredAt = data["administeredAt"] ?? data["administered_at"];
  const operationId = normalizeOperationId(data["operationId"] ?? data["operation_id"]);

  const dog = await loadDog(deps.db, dogId);
  await deps.requireDogAccess(request.auth, caller, dogId, dog);
  const isAdmin = await deps.isAdministrativeAuthority(request.auth, caller);

  const doseId = deriveDoseId(protocolId, plannedDoseId);
  const dRef = doseRef(deps.db, dogId, protocolId, doseId);
  const pRef = protocolRef(deps.db, dogId, protocolId);

  const nowDate = (deps.now ?? (() => new Date()))();
  const nowTs = Timestamp.fromDate(nowDate);

  const adminDate = rawAdministeredAt ? new Date(String(rawAdministeredAt)) : nowDate;
  if (isNaN(adminDate.getTime())) {
    throw new HttpsError("invalid-argument", "administeredAt inválido.");
  }
  if (adminDate.getTime() > nowDate.getTime() + 60000) {
    throw new HttpsError(
      "invalid-argument",
      "administered_at não pode ser futuro.",
    );
  }
  const adminTs = Timestamp.fromDate(adminDate);

  const fingerprint = sha256Hex(
    stableStringify({
      action: "administer_dose",
      dogId,
      protocolId,
      plannedDoseId,
      doseId,
      observations,
      sideEffects,
    }),
  );

  return await deps.db.runTransaction(async (tx) => {
    const pSnap = await tx.get(pRef);
    if (!pSnap.exists) {
      throw new HttpsError("not-found", `Protocolo de tratamento ${protocolId} não encontrado.`);
    }
    const pData = (pSnap.data() ?? {}) as JsonMap;
    const caseId = stringValue(pData["case_id"]);
    if (!caseId) {
      throw new HttpsError("internal", "Protocolo sem case_id vinculado.");
    }

    const opRef = treatmentOperationRef(deps.db, dogId, caseId, operationId);
    const opSnap = await tx.get(opRef);
    if (opSnap.exists) {
      const receipt = opSnap.data() as JsonMap;
      if (receipt["fingerprint"] !== fingerprint) {
        throw new HttpsError(
          "already-exists",
          `operationId '${operationId}' já utilizado com payload diferente.`,
        );
      }
      return receipt["result"] as JsonMap;
    }

    if (pData["status"] !== "active") {
      throw new HttpsError(
        "failed-precondition",
        `Dose não pode ser administrada: protocolo está '${pData["status"]}'.`,
      );
    }

    const dSnap = await tx.get(dRef);
    if (dSnap.exists) {
      const existingDose = dSnap.data() as JsonMap;
      if (existingDose["status"] === "administered") {
        const result: JsonMap = {
          success: true,
          doseId,
          protocolId,
          plannedDoseId,
          status: "administered",
        };
        tx.set(opRef, {
          operation_id: operationId,
          fingerprint,
          result,
          created_at: nowTs,
        });
        return result;
      }
      throw new HttpsError(
        "already-exists",
        `Dose ${plannedDoseId} já possui registro com status '${existingDose["status"]}'.`,
      );
    }

    const cRef = caseRef(deps.db, dogId, caseId);
    const caseSnap = await tx.get(cRef);
    if (!caseSnap.exists) {
      throw new HttpsError("not-found", `Caso clínico ${caseId} não encontrado.`);
    }
    const caseData = (caseSnap.data() ?? {}) as JsonMap;

    // Leitura estrita da agenda antes de qualquer escrita (Firestore transaction read-before-write invariant)
    const resolvedScheduleId =
      scheduleItemId ?? deterministicDoseScheduleId(dogId, protocolId, plannedDoseId);
    const sRef = scheduleRef(deps.db, dogId, resolvedScheduleId);
    const sSnap = await tx.get(sRef);

    const recordedBy = recordedByPayload(caller, isAdmin);
    const eventId = deterministicEventId(dogId, caseId, "dose_admin", operationId);
    const evtRef = clinicalEventRef(deps.db, dogId, caseId, eventId);
    const auditRef = deps.db
      .collection("auditLogs")
      .doc(auditDocId(dogId, caseId, operationId));

    const doseDoc: JsonMap = {
      dose_id: doseId,
      protocol_id: protocolId,
      planned_dose_id: plannedDoseId,
      schedule_item_id: scheduleItemId,
      idempotency_key: doseId,
      scheduled_for: adminTs,
      status: "administered",
      administered_at: adminTs,
      administered_by: recordedBy,
      recorded_by: recordedBy,
      recorded_at: nowTs,
      schema_version: TREATMENT_SCHEMA_VERSION,
    };
    if (observations) doseDoc["observations"] = observations;
    if (sideEffects) doseDoc["side_effects"] = sideEffects;

    tx.set(dRef, doseDoc);

    // Reconciliação do HealthScheduleItem se existir
    if (sSnap.exists) {
      tx.set(
        sRef,
        {
          lifecycle_status: "completed",
          completed_at: nowTs,
          completed_by: recordedBy,
        },
        {merge: true},
      );
    }

    // Atualiza contadores derivados do protocolo
    tx.set(
      pRef,
      {
        doses_administered: FieldValue.increment(1),
        last_administered_at: adminTs,
        updated_at: nowTs,
      },
      {merge: true},
    );

    // Registra ClinicalEvent dose_note
    const eventDoc: JsonMap = {
      entity_kind: "clinical_event",
      event_id: eventId,
      case_id: caseId,
      dog_id: dogId,
      treatment_protocol_id: protocolId,
      dose_id: doseId,
      event_type: "dose_note",
      payload_type: "dose_note_v1",
      payload_version: 1,
      status: "final",
      occurred_at: adminTs,
      recorded_at: nowTs,
      updated_at: nowTs,
      recorded_by: recordedBy,
      content: {
        dose_id: doseId,
        protocol_id: protocolId,
        planned_dose_id: plannedDoseId,
        action: "administered",
        if_observations: observations,
        if_side_effects: sideEffects,
      },
      revision: 1,
      schema_version: 1,
    };
    tx.set(evtRef, eventDoc);

    // Atualiza projeções do caso clínico
    const caseRev = typeof caseData["revision"] === "number" ? caseData["revision"] : 1;
    tx.set(
      cRef,
      {
        event_count: FieldValue.increment(1),
        last_event_at: nowTs,
        updated_at: nowTs,
        revision: caseRev + 1,
      },
      {merge: true},
    );

    const result: JsonMap = {
      success: true,
      doseId,
      protocolId,
      plannedDoseId,
      eventId,
      status: "administered",
    };

    tx.set(opRef, {
      operation_id: operationId,
      fingerprint,
      result,
      created_at: nowTs,
    });

    tx.set(auditRef, {
      action: "health.administer_dose",
      actor: recordedBy,
      dog_id: dogId,
      case_id: caseId,
      protocol_id: protocolId,
      dose_id: doseId,
      timestamp: nowTs,
    });

    return result;
  });
}

// ─────────────────────────────────────────────────────────────────────────────
// 7. SKIP DOSE
// ─────────────────────────────────────────────────────────────────────────────

export async function runHealthSkipTreatmentDose(
  request: CallableRequest,
  deps: TreatmentProtocolCallableDeps,
): Promise<JsonMap> {
  const caller = await deps.requireRecordRoutine(request.auth);
  const data = (request.data ?? {}) as JsonMap;

  const dogId = assertDogId(data["dogId"] ?? data["dog_id"]);
  const protocolId = parseRequiredString(data, "protocolId");
  const plannedDoseId = parseRequiredString(data, "plannedDoseId");
  const skipReason = parseRequiredString(data, "skipReason");
  const scheduleItemId = stringValue(data["scheduleItemId"] ?? data["schedule_item_id"]) ?? null;
  const observations = stringValue(data["observations"]) ?? null;
  const operationId = normalizeOperationId(data["operationId"] ?? data["operation_id"]);

  const dog = await loadDog(deps.db, dogId);
  await deps.requireDogAccess(request.auth, caller, dogId, dog);
  const isAdmin = await deps.isAdministrativeAuthority(request.auth, caller);

  const doseId = deriveDoseId(protocolId, plannedDoseId);
  const dRef = doseRef(deps.db, dogId, protocolId, doseId);
  const pRef = protocolRef(deps.db, dogId, protocolId);

  const nowDate = (deps.now ?? (() => new Date()))();
  const nowTs = Timestamp.fromDate(nowDate);

  const fingerprint = sha256Hex(
    stableStringify({
      action: "skip_dose",
      dogId,
      protocolId,
      plannedDoseId,
      doseId,
      skipReason,
      observations,
    }),
  );

  return await deps.db.runTransaction(async (tx) => {
    const pSnap = await tx.get(pRef);
    if (!pSnap.exists) {
      throw new HttpsError("not-found", `Protocolo de tratamento ${protocolId} não encontrado.`);
    }
    const pData = (pSnap.data() ?? {}) as JsonMap;
    const caseId = stringValue(pData["case_id"]);
    if (!caseId) {
      throw new HttpsError("internal", "Protocolo sem case_id vinculado.");
    }

    const opRef = treatmentOperationRef(deps.db, dogId, caseId, operationId);
    const opSnap = await tx.get(opRef);
    if (opSnap.exists) {
      const receipt = opSnap.data() as JsonMap;
      if (receipt["fingerprint"] !== fingerprint) {
        throw new HttpsError(
          "already-exists",
          `operationId '${operationId}' já utilizado com payload diferente.`,
        );
      }
      return receipt["result"] as JsonMap;
    }

    if (pData["status"] !== "active") {
      throw new HttpsError(
        "failed-precondition",
        `Dose não pode ser pulada: protocolo está '${pData["status"]}'.`,
      );
    }

    const dSnap = await tx.get(dRef);
    if (dSnap.exists) {
      const existingDose = dSnap.data() as JsonMap;
      if (existingDose["status"] === "skipped") {
        const result: JsonMap = {
          success: true,
          doseId,
          protocolId,
          plannedDoseId,
          status: "skipped",
        };
        tx.set(opRef, {
          operation_id: operationId,
          fingerprint,
          result,
          created_at: nowTs,
        });
        return result;
      }
      throw new HttpsError(
        "already-exists",
        `Dose ${plannedDoseId} já possui registro com status '${existingDose["status"]}'.`,
      );
    }

    const cRef = caseRef(deps.db, dogId, caseId);
    const caseSnap = await tx.get(cRef);
    if (!caseSnap.exists) {
      throw new HttpsError("not-found", `Caso clínico ${caseId} não encontrado.`);
    }
    const caseData = (caseSnap.data() ?? {}) as JsonMap;

    // Leitura estrita da agenda antes de qualquer escrita (Firestore transaction read-before-write invariant)
    const resolvedScheduleId =
      scheduleItemId ?? deterministicDoseScheduleId(dogId, protocolId, plannedDoseId);
    const sRef = scheduleRef(deps.db, dogId, resolvedScheduleId);
    const sSnap = await tx.get(sRef);

    const recordedBy = recordedByPayload(caller, isAdmin);
    const eventId = deterministicEventId(dogId, caseId, "dose_skip", operationId);
    const evtRef = clinicalEventRef(deps.db, dogId, caseId, eventId);
    const auditRef = deps.db
      .collection("auditLogs")
      .doc(auditDocId(dogId, caseId, operationId));

    const doseDoc: JsonMap = {
      dose_id: doseId,
      protocol_id: protocolId,
      planned_dose_id: plannedDoseId,
      schedule_item_id: scheduleItemId,
      idempotency_key: doseId,
      scheduled_for: nowTs,
      status: "skipped",
      skip_reason: skipReason,
      recorded_by: recordedBy,
      recorded_at: nowTs,
      schema_version: TREATMENT_SCHEMA_VERSION,
    };
    if (observations) doseDoc["observations"] = observations;

    tx.set(dRef, doseDoc);

    // Reconciliação do HealthScheduleItem se existir
    if (sSnap.exists) {
      tx.set(
        sRef,
        {
          lifecycle_status: "completed",
          completed_at: nowTs,
          completed_by: recordedBy,
          notes: `Dose pulada: ${skipReason}`,
        },
        {merge: true},
      );
    }

    // Registra ClinicalEvent dose_note
    const eventDoc: JsonMap = {
      entity_kind: "clinical_event",
      event_id: eventId,
      case_id: caseId,
      dog_id: dogId,
      treatment_protocol_id: protocolId,
      dose_id: doseId,
      event_type: "dose_note",
      payload_type: "dose_note_v1",
      payload_version: 1,
      status: "final",
      occurred_at: nowTs,
      recorded_at: nowTs,
      updated_at: nowTs,
      recorded_by: recordedBy,
      content: {
        dose_id: doseId,
        protocol_id: protocolId,
        planned_dose_id: plannedDoseId,
        action: "skipped",
        reason: skipReason,
        if_observations: observations,
      },
      revision: 1,
      schema_version: 1,
    };
    tx.set(evtRef, eventDoc);

    // Atualiza projeções do caso clínico
    const caseRev = typeof caseData["revision"] === "number" ? caseData["revision"] : 1;
    tx.set(
      cRef,
      {
        event_count: FieldValue.increment(1),
        last_event_at: nowTs,
        updated_at: nowTs,
        revision: caseRev + 1,
      },
      {merge: true},
    );

    const result: JsonMap = {
      success: true,
      doseId,
      protocolId,
      plannedDoseId,
      eventId,
      status: "skipped",
    };

    tx.set(opRef, {
      operation_id: operationId,
      fingerprint,
      result,
      created_at: nowTs,
    });

    tx.set(auditRef, {
      action: "health.skip_dose",
      actor: recordedBy,
      dog_id: dogId,
      case_id: caseId,
      protocol_id: protocolId,
      dose_id: doseId,
      timestamp: nowTs,
    });

    return result;
  });
}
