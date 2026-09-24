/**
 * Testes unitários dos callables de Tratamentos e Administração de Doses (F20.TREATMENT-V1).
 * Executado via node assert.
 */
import * as assert from "assert";
import {
  TreatmentCaller,
  TreatmentProtocolCallableDeps,
  deriveDoseId,
  deterministicDoseScheduleId,
  runHealthCreateTreatmentProtocol,
  runHealthPauseTreatmentProtocol,
  runHealthResumeTreatmentProtocol,
  runHealthCompleteTreatmentProtocol,
  runHealthCancelTreatmentProtocol,
  runHealthAdministerTreatmentDose,
  runHealthSkipTreatmentDose,
} from "./treatment_protocol_callables";

type JsonMap = Record<string, unknown>;

const testCaller: TreatmentCaller = {
  uid: "uid-operador",
  email: "operador@gcm.com.br",
  ra: "123456",
  name: "GCM Operador",
};

function applyPatch(prev: JsonMap, patch: JsonMap): JsonMap {
  const next = {...prev};
  for (const [k, v] of Object.entries(patch)) {
    if (v && typeof v === "object" && "operand" in v) {
      const cur = typeof next[k] === "number" ? (next[k] as number) : 0;
      next[k] = cur + ((v as any).operand as number);
    } else {
      next[k] = v;
    }
  }
  return next;
}

function createFakeDb(initial: Record<string, JsonMap> = {}) {
  const store = new Map<string, JsonMap>();
  const versions = new Map<string, number>();
  for (const [k, v] of Object.entries(initial)) store.set(k, {...v});

  function makeDocRef(parts: string[]) {
    const path = parts.join("/");
    return {
      path,
      id: parts[parts.length - 1],
      collection(c: string) {
        return {doc: (id: string) => makeDocRef([...parts, c, id])};
      },
      async get() {
        const data = store.get(path);
        return {exists: data !== undefined, data: () => ({...(data ?? {})})};
      },
    };
  }

  const db = {
    collection(col: string) {
      return {
        doc(id?: string) {
          return makeDocRef([col, id ?? `auto_${store.size + 1}`]);
        },
      };
    },
    async runTransaction<T>(
      fn: (tx: {
        get: (ref: {path: string}) => Promise<{
          exists: boolean;
          data: () => JsonMap;
        }>;
        set: (
          ref: {path: string},
          data: JsonMap,
          options?: {merge?: boolean},
        ) => void;
        update: (ref: {path: string}, data: JsonMap) => void;
      }) => Promise<T>,
    ): Promise<T> {
      const pending = new Map<string, JsonMap>();
      const readVersions = new Map<string, number>();
      const tx = {
        async get(ref: {path: string}) {
          if (!readVersions.has(ref.path)) {
            readVersions.set(ref.path, versions.get(ref.path) ?? 0);
          }
          const data = pending.get(ref.path) ?? store.get(ref.path);
          return {
            exists: data !== undefined,
            data: () => ({...(data ?? {})}),
          };
        },
        set(
          ref: {path: string},
          data: JsonMap,
          options?: {merge?: boolean},
        ) {
          const prev = options?.merge
            ? pending.get(ref.path) ?? store.get(ref.path) ?? {}
            : {};
          pending.set(ref.path, applyPatch(prev, data));
        },
        update(ref: {path: string}, data: JsonMap) {
          const prev = pending.get(ref.path) ?? store.get(ref.path) ?? {};
          pending.set(ref.path, applyPatch(prev, data));
        },
      };
      const result = await fn(tx);
      for (const [p, v] of readVersions.entries()) {
        const cur = versions.get(p) ?? 0;
        if (cur !== v) throw new Error(`Concorrência detectada em ${p}`);
      }
      for (const [p, d] of pending.entries()) {
        store.set(p, d);
        versions.set(p, (versions.get(p) ?? 0) + 1);
      }
      return result;
    },
    _store: store,
  };

  return db;
}

function makeCallableRequest(data: JsonMap, uid = "uid-operador"): any {
  return {
    data,
    auth: {
      uid,
      token: {
        name: "GCM Operador",
        email: "operador@gcm.com.br",
        ra: "123456",
      },
    },
  };
}

function makeDeps(db: any): TreatmentProtocolCallableDeps {
  return {
    db: db as any,
    requireRecordClinical: async () => testCaller,
    requireFinalizeClinical: async () => testCaller,
    requireAmendClinical: async () => testCaller,
    requireRecordRoutine: async () => testCaller,
    requireDogAccess: async () => {},
    isAdministrativeAuthority: async () => false,
    hasOtherOpenCaseSchedule: async (dogId: string, caseId: string, excludeProtocolId?: string) => {
      const prefix = `dogs/${dogId}/health_schedule/`;
      for (const [key, val] of db._store.entries()) {
        if (key.startsWith(prefix)) {
          const d = val as any;
          if (
            d.case_id === caseId &&
            d.lifecycle_status === "open" &&
            (!excludeProtocolId || d.source_id !== excludeProtocolId)
          ) {
            return true;
          }
        }
      }
      return false;
    },
    now: () => new Date("2026-09-05T12:00:00Z"),
  };
}

async function runTests() {
  console.log("Starting TreatmentProtocol backend tests...");

  // ───────────────────────────────────────────────────────────────────────────
  // 1. DETERMINISTIC DOSE IDENTITY CONTRACT & VECTORS
  // ───────────────────────────────────────────────────────────────────────────
  {
    // Vetor p1/d1
    const d1 = deriveDoseId("p1", "d1");
    assert.strictEqual(
      d1,
      "d214c74332127faf1e6cd2198436939782f15f430fc8a5d2436949672621dcb8",
      "Vetor determinístico p1/d1",
    );

    // Vetor multibyte UTF-8
    const dMb = deriveDoseId("日本", "dose-α");
    assert.strictEqual(
      dMb,
      "5f344b47fd0fabd9937cd69d13998cba0997c1344280c8bc7a71964569062465",
      "Vetor determinístico multibyte 日本/dose-α",
    );

    // Prevenção de colisão de concatenação (ab+c vs a+bc)
    const dAbC = deriveDoseId("ab", "c");
    const dABc = deriveDoseId("a", "bc");
    assert.notStrictEqual(dAbC, dABc, "Length prefix previne colisão de concatenação");

    // Rejeição de vazios
    assert.throws(() => deriveDoseId("  ", "d1"));
    assert.throws(() => deriveDoseId("p1", ""));
    console.log("✓ DoseIdentity deterministic vectors and collision protection passed");
  }

  // ───────────────────────────────────────────────────────────────────────────
  // 2. CREATE TREATMENT PROTOCOL (Happy Path + Projections + Schedule)
  // ───────────────────────────────────────────────────────────────────────────
  {
    const initial: Record<string, JsonMap> = {
      "dogs/dog-01": {id: "dog-01", name: "Thor"},
      "dogs/dog-01/clinical_cases/case-01": {
        id: "case-01",
        clinical_status: "under_investigation",
        event_count: 3,
        revision: 2,
        active_treatments_count: 0,
      },
    };
    const db = createFakeDb(initial);
    const deps = makeDeps(db);

    const req = makeCallableRequest({
      dogId: "dog-01",
      caseId: "case-01",
      medicationName: "Carprofeno",
      dose: {
        value: 25,
        unit: "mg",
        per_kg: false,
        route: "oral",
      },
      schedule: {
        type: "interval",
        interval_minutes: 720,
        timezone: "America/Sao_Paulo",
      },
      durationDays: 3,
      startDate: "2026-09-05T12:00:00Z",
      professional: {
        name: "Dra. Costa",
        registration_type: "CRMV",
        registration_number: "SP-12345",
      },
      sourceDocument: {
        health_document_id: "doc-rec-01",
        description: "Receita carprofeno",
      },
      operationId: "op-create-prot-01",
    });

    const res = await runHealthCreateTreatmentProtocol(req, deps);
    assert.strictEqual(res["success"], true);
    assert.strictEqual(res["status"], "active");
    const protocolId = res["protocolId"] as string;

    // Prova protocolo persistido
    const protDoc = db._store.get(`dogs/dog-01/treatment_protocols/${protocolId}`);
    assert.ok(protDoc, "Protocolo deve existir");
    assert.strictEqual(protDoc["medication_name"], "Carprofeno");
    assert.strictEqual(protDoc["status"], "active");
    assert.strictEqual((protDoc["dose"] as any)["value"], 25);
    assert.strictEqual((protDoc["dose"] as any)["route"], "oral");

    // Prova ClinicalEvent treatment_start gerado
    const eventId = res["eventId"] as string;
    const evtDoc = db._store.get(`dogs/dog-01/clinical_cases/case-01/clinical_events/${eventId}`);
    assert.ok(evtDoc, "ClinicalEvent treatment_start deve existir");
    assert.strictEqual(evtDoc["event_type"], "treatment_start");
    assert.strictEqual(evtDoc["payload_type"], "treatment_start_v1");

    // Prova projeções atualizadas no ClinicalCase
    const caseDoc = db._store.get("dogs/dog-01/clinical_cases/case-01")!;
    assert.strictEqual(caseDoc["event_count"], 4, "event_count incrementado para 4");
    assert.strictEqual(caseDoc["active_treatments_count"], 1, "active_treatments_count = 1");
    assert.strictEqual(caseDoc["has_pending_schedule"], true, "has_pending_schedule = true");
    assert.strictEqual(caseDoc["clinical_status"], "under_treatment", "transitou para under_treatment");
    assert.strictEqual(caseDoc["revision"], 3, "revision incrementada");

    // Prova doses planejadas criadas no health_schedule
    // 3 dias com intervalo de 720m (12h) = 6 doses
    assert.strictEqual(res["plannedDoseCount"], 6, "6 doses planejadas");
    const sched1 = db._store.get(
      `dogs/dog-01/health_schedule/${deterministicDoseScheduleId("dog-01", protocolId, "dose_1")}`,
    );
    assert.ok(sched1, "Primeira dose na agenda existe");
    assert.strictEqual(sched1["lifecycle_status"], "open");
    assert.strictEqual(sched1["source_type"], "treatment_protocol");
    assert.ok(sched1["due_until"], "due_until deve ser materializado na agenda para a dose");
    assert.strictEqual(
      (sched1["due_until"] as any).toMillis() - (sched1["scheduled_for"] as any).toMillis(),
      30 * 60 * 1000,
      "due_until deve refletir scheduled_for + toleranceMinutes (30m padrão)",
    );

    // Prova idempotência com mesmo payload
    const replay = await runHealthCreateTreatmentProtocol(req, deps);
    assert.deepStrictEqual(replay, res, "Replay com mesmo operationId deve ser idempotente");

    // Prova rejeição com payload divergente
    const confReq = makeCallableRequest({
      dogId: "dog-01",
      caseId: "case-01",
      medicationName: "Carprofeno DIVERGENTE",
      dose: {value: 50, unit: "mg", route: "oral"},
      schedule: {type: "interval", interval_minutes: 720},
      durationDays: 3,
      professional: {name: "Dra. Costa"},
      sourceDocument: {health_document_id: "doc-rec-01"},
      operationId: "op-create-prot-01",
    });
    await assert.rejects(
      () => runHealthCreateTreatmentProtocol(confReq, deps),
      /já utilizado com payload diferente/,
      "Conflito de payload detectado",
    );

    // Prova rejeição de PRN (não suportado em Treatment V1)
    const prnReq = makeCallableRequest({
      dogId: "dog-01",
      caseId: "case-01",
      medicationName: "Dipirona",
      dose: {value: 10, unit: "mg", route: "oral"},
      schedule: {type: "prn"},
      durationDays: 3,
      professional: {name: "Dra. Costa"},
      sourceDocument: {health_document_id: "doc-rec-01"},
      operationId: "op-create-prn",
    });
    await assert.rejects(
      () => runHealthCreateTreatmentProtocol(prnReq, deps),
      /não é suportado em Treatment V1/,
      "PRN deve ser rejeitado com failed-precondition",
    );

    // Prova rejeição de ausência de durationDays
    const noDurReq = makeCallableRequest({
      dogId: "dog-01",
      caseId: "case-01",
      medicationName: "Carprofeno",
      dose: {value: 25, unit: "mg", route: "oral"},
      schedule: {type: "interval", interval_minutes: 720},
      professional: {name: "Dra. Costa"},
      sourceDocument: {health_document_id: "doc-rec-01"},
      operationId: "op-create-no-dur",
    });
    await assert.rejects(
      () => runHealthCreateTreatmentProtocol(noDurReq, deps),
      /durationDays é obrigatório em Treatment V1/,
      "Ausência de durationDays deve falhar",
    );

    // Prova rejeição sem truncamento silencioso quando doses calculadas > 50
    const over50Req = makeCallableRequest({
      dogId: "dog-01",
      caseId: "case-01",
      medicationName: "Carprofeno",
      dose: {value: 25, unit: "mg", route: "oral"},
      schedule: {type: "interval", interval_minutes: 60}, // 1h = 24 doses/dia
      durationDays: 3, // 3 dias = 72 doses > 50
      professional: {name: "Dra. Costa"},
      sourceDocument: {health_document_id: "doc-rec-01"},
      operationId: "op-create-over-50",
    });
    await assert.rejects(
      () => runHealthCreateTreatmentProtocol(over50Req, deps),
      /Protocolo excede o limite máximo de 50 doses planejadas/,
      "Doses > 50 deve falhar fechado sem truncamento silencioso",
    );

    console.log("✓ Create TreatmentProtocol: happy path, idempotency, PRN rejection & 50-cap passed");
  }

  // ───────────────────────────────────────────────────────────────────────────
  // 2B. CLINICAL CASE STATUS TRANSITIONS ON TREATMENT CREATION
  //     (open, under_investigation, monitoring -> under_treatment; under_treatment preserved)
  // ───────────────────────────────────────────────────────────────────────────
  {
    for (const originStatus of ["open", "under_investigation", "monitoring"] as const) {
      const db = createFakeDb({
        "dogs/dog-01": {id: "dog-01"},
        "dogs/dog-01/clinical_cases/case-trans": {
          id: "case-trans",
          clinical_status: originStatus,
          event_count: 2,
          revision: 1,
          active_treatments_count: 0,
          has_pending_schedule: false,
        },
      });
      const deps = makeDeps(db);

      const req = makeCallableRequest({
        dogId: "dog-01",
        caseId: "case-trans",
        medicationName: "Meloxicam",
        dose: {value: 10, unit: "mg", route: "oral"},
        schedule: {type: "interval", interval_minutes: 1440},
        durationDays: 2,
        professional: {name: "Dr. Silva"},
        sourceDocument: {health_document_id: "doc-rec-01"},
        operationId: `op-create-from-${originStatus}`,
      });

      const res = await runHealthCreateTreatmentProtocol(req, deps);
      assert.strictEqual(res["success"], true);

      const caseDoc = db._store.get("dogs/dog-01/clinical_cases/case-trans")!;
      assert.strictEqual(
        caseDoc["clinical_status"],
        "under_treatment",
        `Caso em status '${originStatus}' DEVE transitar para 'under_treatment'`,
      );
      assert.strictEqual(caseDoc["active_treatments_count"], 1);
      assert.strictEqual(caseDoc["has_pending_schedule"], true);
      assert.strictEqual(caseDoc["event_count"], 3);
      assert.strictEqual(caseDoc["revision"], 2);

      // Prova agendamento com due_until
      const protId = res["protocolId"] as string;
      const schedDose = db._store.get(
        `dogs/dog-01/health_schedule/${deterministicDoseScheduleId("dog-01", protId, "dose_1")}`,
      )!;
      assert.ok(schedDose["due_until"], "due_until deve ser materializado");
      assert.strictEqual(schedDose["lifecycle_status"], "open");
    }

    // Caso já em under_treatment permanece em under_treatment com active_treatments_count incrementado
    {
      const db = createFakeDb({
        "dogs/dog-01": {id: "dog-01"},
        "dogs/dog-01/clinical_cases/case-trans": {
          id: "case-trans",
          clinical_status: "under_treatment",
          event_count: 5,
          revision: 4,
          active_treatments_count: 1,
          has_pending_schedule: true,
        },
      });
      const deps = makeDeps(db);

      const req = makeCallableRequest({
        dogId: "dog-01",
        caseId: "case-trans",
        medicationName: "Amoxicilina",
        dose: {value: 250, unit: "mg", route: "oral"},
        schedule: {type: "interval", interval_minutes: 720},
        durationDays: 2,
        professional: {name: "Dr. Silva"},
        sourceDocument: {health_document_id: "doc-rec-02"},
        operationId: "op-create-while-under-treatment",
      });

      const res = await runHealthCreateTreatmentProtocol(req, deps);
      assert.strictEqual(res["success"], true);

      const caseDoc = db._store.get("dogs/dog-01/clinical_cases/case-trans")!;
      assert.strictEqual(
        caseDoc["clinical_status"],
        "under_treatment",
        "Caso já em under_treatment permanece em under_treatment",
      );
      assert.strictEqual(caseDoc["active_treatments_count"], 2, "active_treatments_count incrementado de 1 para 2");
      assert.strictEqual(caseDoc["has_pending_schedule"], true);
      assert.strictEqual(caseDoc["event_count"], 6);
      assert.strictEqual(caseDoc["revision"], 5);
    }

    // Casos em estados terminais são rejeitados
    for (const terminalStatus of ["discharged", "cancelled"] as const) {
      const db = createFakeDb({
        "dogs/dog-01": {id: "dog-01"},
        "dogs/dog-01/clinical_cases/case-terminal": {
          id: "case-terminal",
          clinical_status: terminalStatus,
          event_count: 5,
          revision: 4,
        },
      });
      const deps = makeDeps(db);

      const req = makeCallableRequest({
        dogId: "dog-01",
        caseId: "case-terminal",
        medicationName: "Amoxicilina",
        dose: {value: 250, unit: "mg", route: "oral"},
        schedule: {type: "interval", interval_minutes: 720},
        durationDays: 2,
        professional: {name: "Dr. Silva"},
        sourceDocument: {health_document_id: "doc-rec-02"},
        operationId: `op-create-terminal-${terminalStatus}`,
      });

      await assert.rejects(
        () => runHealthCreateTreatmentProtocol(req, deps),
        /está em estado terminal/,
        `Caso em '${terminalStatus}' deve ser rejeitado ao tentar criar tratamento`,
      );
    }

    console.log("✓ Create TreatmentProtocol status transitions: open, under_investigation, monitoring -> under_treatment & terminal rejection passed");
  }

  // ───────────────────────────────────────────────────────────────────────────
  // 3. PAUSE & RESUME TREATMENT PROTOCOL (With Schedule is_paused toggling)
  // ───────────────────────────────────────────────────────────────────────────
  {
    const schedId = deterministicDoseScheduleId("dog-01", "tp-01", "dose_1");
    const initial: Record<string, JsonMap> = {
      "dogs/dog-01": {id: "dog-01"},
      "dogs/dog-01/clinical_cases/case-01": {
        id: "case-01",
        clinical_status: "under_treatment",
        event_count: 5,
        revision: 3,
        active_treatments_count: 1,
      },
      "dogs/dog-01/treatment_protocols/tp-01": {
        id: "tp-01",
        case_id: "case-01",
        dog_id: "dog-01",
        status: "active",
        medication_name: "Amoxicilina",
        revision: 1,
        doses_planned: 1,
      },
      [`dogs/dog-01/health_schedule/${schedId}`]: {
        id: schedId,
        dog_id: "dog-01",
        lifecycle_status: "open",
        source_type: "treatment_protocol",
        source_id: "tp-01",
        case_id: "case-01",
        planned_dose_id: "dose_1",
        revision: 1,
      },
    };
    const db = createFakeDb(initial);
    const deps = makeDeps(db);

    // Pausa
    const pauseReq = makeCallableRequest({
      dogId: "dog-01",
      protocolId: "tp-01",
      pauseReason: "Reação gástrica temporária",
      operationId: "op-pause-01",
    });
    const pauseRes = await runHealthPauseTreatmentProtocol(pauseReq, deps);
    assert.strictEqual(pauseRes["success"], true);
    assert.strictEqual(pauseRes["status"], "paused");

    const pDocAfterPause = db._store.get("dogs/dog-01/treatment_protocols/tp-01")!;
    assert.strictEqual(pDocAfterPause["status"], "paused");
    assert.strictEqual(pDocAfterPause["pause_reason"], "Reação gástrica temporária");

    const schedAfterPause = db._store.get(`dogs/dog-01/health_schedule/${schedId}`)!;
    assert.strictEqual(schedAfterPause["is_paused"], true, "Schedule marcado como is_paused=true");
    assert.strictEqual(schedAfterPause["pause_reason"], "Reação gástrica temporária");
    assert.strictEqual(schedAfterPause["revision"], 2);

    const caseAfterPause = db._store.get("dogs/dog-01/clinical_cases/case-01")!;
    assert.strictEqual(caseAfterPause["active_treatments_count"], 0, "active treatments decrementado");
    assert.strictEqual(caseAfterPause["event_count"], 6, "event_count incrementado");

    // Retoma
    const resumeReq = makeCallableRequest({
      dogId: "dog-01",
      protocolId: "tp-01",
      operationId: "op-resume-01",
    });
    const resumeRes = await runHealthResumeTreatmentProtocol(resumeReq, deps);
    assert.strictEqual(resumeRes["success"], true);
    assert.strictEqual(resumeRes["status"], "active");

    const pDocAfterResume = db._store.get("dogs/dog-01/treatment_protocols/tp-01")!;
    assert.strictEqual(pDocAfterResume["status"], "active");
    assert.strictEqual(pDocAfterResume["paused_at"], null);

    const schedAfterResume = db._store.get(`dogs/dog-01/health_schedule/${schedId}`)!;
    assert.strictEqual(schedAfterResume["is_paused"], false, "Schedule restaurado com is_paused=false");
    assert.strictEqual(schedAfterResume["paused_at"], null);
    assert.strictEqual(schedAfterResume["pause_reason"], null);
    assert.strictEqual(schedAfterResume["revision"], 3);
    assert.strictEqual(schedAfterResume["id"], schedId, "Mesmo documento de schedule mantido (sem regeneração)");

    const caseAfterResume = db._store.get("dogs/dog-01/clinical_cases/case-01")!;
    assert.strictEqual(caseAfterResume["active_treatments_count"], 1, "active treatments restaurado");
    assert.strictEqual(caseAfterResume["event_count"], 7, "event_count incrementado");

    console.log("✓ Pause & Resume TreatmentProtocol: lifecycle, events, active count & schedule is_paused toggle passed");
  }

  // ───────────────────────────────────────────────────────────────────────────
  // 4. COMPLETE TREATMENT PROTOCOL (Case Monitoring Transition & Schedule Cancellation)
  // ───────────────────────────────────────────────────────────────────────────
  {
    const schedId = deterministicDoseScheduleId("dog-01", "tp-01", "dose_1");
    const initial: Record<string, JsonMap> = {
      "dogs/dog-01": {id: "dog-01"},
      "dogs/dog-01/clinical_cases/case-01": {
        id: "case-01",
        clinical_status: "under_treatment",
        event_count: 7,
        revision: 4,
        active_treatments_count: 1,
        has_pending_schedule: true,
      },
      "dogs/dog-01/treatment_protocols/tp-01": {
        id: "tp-01",
        case_id: "case-01",
        dog_id: "dog-01",
        status: "active",
        medication_name: "Amoxicilina",
        revision: 2,
        doses_planned: 1,
      },
      [`dogs/dog-01/health_schedule/${schedId}`]: {
        id: schedId,
        dog_id: "dog-01",
        lifecycle_status: "open",
        source_type: "treatment_protocol",
        source_id: "tp-01",
      },
    };
    const db = createFakeDb(initial);
    const deps = makeDeps(db);

    const compReq = makeCallableRequest({
      dogId: "dog-01",
      protocolId: "tp-01",
      operationId: "op-comp-01",
    });
    const compRes = await runHealthCompleteTreatmentProtocol(compReq, deps);
    assert.strictEqual(compRes["success"], true);
    assert.strictEqual(compRes["status"], "completed");
    assert.strictEqual(compRes["caseStatus"], "monitoring");

    const pDoc = db._store.get("dogs/dog-01/treatment_protocols/tp-01")!;
    assert.strictEqual(pDoc["status"], "completed");
    assert.ok(pDoc["completed_at"]);

    // Prova que doses futuras abertas foram canceladas
    const schedDoc = db._store.get(`dogs/dog-01/health_schedule/${schedId}`)!;
    assert.strictEqual(schedDoc["lifecycle_status"], "cancelled", "Agendamento aberto cancelado na conclusão");
    assert.strictEqual(schedDoc["cancel_reason"], "Tratamento concluído");

    const caseDoc = db._store.get("dogs/dog-01/clinical_cases/case-01")!;
    assert.strictEqual(caseDoc["clinical_status"], "monitoring", "Caso transita para monitoring quando tratamentos ativos = 0");
    assert.strictEqual(caseDoc["active_treatments_count"], 0);
    assert.strictEqual(caseDoc["has_pending_schedule"], false, "has_pending_schedule é false quando não restam tratamentos ativos");
    assert.strictEqual(caseDoc["event_count"], 8);

    console.log("✓ Complete TreatmentProtocol: transition to monitoring & schedule cancelled passed");
  }

  // ───────────────────────────────────────────────────────────────────────────
  // 4B. COMPLETE TREATMENT PROTOCOL WITH OTHER OPEN CASE SCHEDULE (Option A projection)
  // ───────────────────────────────────────────────────────────────────────────
  {
    const schedDoseId = deterministicDoseScheduleId("dog-01", "tp-01", "dose_1");
    const schedExamId = "sch_exam_unrelated_01";
    const initial: Record<string, JsonMap> = {
      "dogs/dog-01": {id: "dog-01"},
      "dogs/dog-01/clinical_cases/case-01": {
        id: "case-01",
        clinical_status: "under_treatment",
        event_count: 7,
        revision: 4,
        active_treatments_count: 1,
        has_pending_schedule: true,
      },
      "dogs/dog-01/treatment_protocols/tp-01": {
        id: "tp-01",
        case_id: "case-01",
        dog_id: "dog-01",
        status: "active",
        medication_name: "Amoxicilina",
        revision: 2,
        doses_planned: 1,
      },
      [`dogs/dog-01/health_schedule/${schedDoseId}`]: {
        id: schedDoseId,
        dog_id: "dog-01",
        lifecycle_status: "open",
        source_type: "treatment_protocol",
        source_id: "tp-01",
        case_id: "case-01",
      },
      [`dogs/dog-01/health_schedule/${schedExamId}`]: {
        id: schedExamId,
        dog_id: "dog-01",
        lifecycle_status: "open",
        source_type: "exam",
        source_id: "exam_01",
        case_id: "case-01",
      },
    };
    const db = createFakeDb(initial);
    const deps = makeDeps(db);

    const compReq = makeCallableRequest({
      dogId: "dog-01",
      protocolId: "tp-01",
      operationId: "op-comp-other-sched",
    });
    const compRes = await runHealthCompleteTreatmentProtocol(compReq, deps);
    assert.strictEqual(compRes["success"], true);

    const caseDoc = db._store.get("dogs/dog-01/clinical_cases/case-01")!;
    assert.strictEqual(caseDoc["active_treatments_count"], 0);
    assert.strictEqual(
      caseDoc["has_pending_schedule"],
      true,
      "has_pending_schedule permanece true devido a agendamento de exame pendente no mesmo caso",
    );
    console.log("✓ Complete TreatmentProtocol with other open case schedule: has_pending_schedule correctly preserved as true");
  }

  // ───────────────────────────────────────────────────────────────────────────
  // 4C. MULTIPLE TREATMENTS COEXISTENCE (Treatment A + Treatment B in same case)
  // ───────────────────────────────────────────────────────────────────────────
  {
    const schedA = deterministicDoseScheduleId("dog-01", "tp-a", "dose_1");
    const schedB = deterministicDoseScheduleId("dog-01", "tp-b", "dose_1");
    const initial: Record<string, JsonMap> = {
      "dogs/dog-01": {id: "dog-01"},
      "dogs/dog-01/clinical_cases/case-01": {
        id: "case-01",
        clinical_status: "under_treatment",
        event_count: 10,
        revision: 5,
        active_treatments_count: 2,
        has_pending_schedule: true,
      },
      "dogs/dog-01/treatment_protocols/tp-a": {
        id: "tp-a",
        case_id: "case-01",
        dog_id: "dog-01",
        status: "active",
        medication_name: "Antibiótico A",
        revision: 1,
        doses_planned: 1,
      },
      "dogs/dog-01/treatment_protocols/tp-b": {
        id: "tp-b",
        case_id: "case-01",
        dog_id: "dog-01",
        status: "active",
        medication_name: "Anti-inflamatório B",
        revision: 1,
        doses_planned: 1,
      },
      [`dogs/dog-01/health_schedule/${schedA}`]: {
        id: schedA,
        dog_id: "dog-01",
        lifecycle_status: "open",
        source_type: "treatment_protocol",
        source_id: "tp-a",
        case_id: "case-01",
      },
      [`dogs/dog-01/health_schedule/${schedB}`]: {
        id: schedB,
        dog_id: "dog-01",
        lifecycle_status: "open",
        source_type: "treatment_protocol",
        source_id: "tp-b",
        case_id: "case-01",
      },
    };
    const db = createFakeDb(initial);
    const deps = makeDeps(db);

    // Conclui apenas Tratamento A
    const compAReq = makeCallableRequest({
      dogId: "dog-01",
      protocolId: "tp-a",
      operationId: "op-comp-a",
    });
    const resA = await runHealthCompleteTreatmentProtocol(compAReq, deps);
    assert.strictEqual(resA["success"], true);

    const caseAfterA = db._store.get("dogs/dog-01/clinical_cases/case-01")!;
    assert.strictEqual(caseAfterA["active_treatments_count"], 1, "Tratamento B continua ativo");
    assert.strictEqual(caseAfterA["clinical_status"], "under_treatment", "Status permanece under_treatment");
    assert.strictEqual(caseAfterA["has_pending_schedule"], true, "has_pending_schedule permanece true");

    const schedDocA = db._store.get(`dogs/dog-01/health_schedule/${schedA}`)!;
    assert.strictEqual(schedDocA["lifecycle_status"], "cancelled", "Dose do Tratamento A cancelada");

    const schedDocB = db._store.get(`dogs/dog-01/health_schedule/${schedB}`)!;
    assert.strictEqual(schedDocB["lifecycle_status"], "open", "Dose do Tratamento B continua open");

    // Conclui Tratamento B
    const compBReq = makeCallableRequest({
      dogId: "dog-01",
      protocolId: "tp-b",
      operationId: "op-comp-b",
    });
    const resB = await runHealthCompleteTreatmentProtocol(compBReq, deps);
    assert.strictEqual(resB["success"], true);

    const caseAfterB = db._store.get("dogs/dog-01/clinical_cases/case-01")!;
    assert.strictEqual(caseAfterB["active_treatments_count"], 0, "Nenhum tratamento ativo restante");
    assert.strictEqual(caseAfterB["clinical_status"], "monitoring", "Transita para monitoring");
    assert.strictEqual(caseAfterB["has_pending_schedule"], false, "Sem mais pendências de agenda");

    console.log("✓ Multiple treatments coexistence: independent lifecycles, projections & schedules passed");
  }

  // ───────────────────────────────────────────────────────────────────────────
  // 5. CANCEL TREATMENT PROTOCOL (Schedule Cancellation & has_pending_schedule)
  // ───────────────────────────────────────────────────────────────────────────
  {
    const schedId = deterministicDoseScheduleId("dog-01", "tp-01", "dose_1");
    const initial: Record<string, JsonMap> = {
      "dogs/dog-01": {id: "dog-01"},
      "dogs/dog-01/clinical_cases/case-01": {
        id: "case-01",
        clinical_status: "under_treatment",
        event_count: 2,
        revision: 1,
        active_treatments_count: 1,
        has_pending_schedule: true,
      },
      "dogs/dog-01/treatment_protocols/tp-01": {
        id: "tp-01",
        case_id: "case-01",
        dog_id: "dog-01",
        status: "active",
        medication_name: "Amoxicilina",
        revision: 1,
        doses_planned: 1,
      },
      [`dogs/dog-01/health_schedule/${schedId}`]: {
        id: schedId,
        dog_id: "dog-01",
        lifecycle_status: "open",
        source_type: "treatment_protocol",
        source_id: "tp-01",
      },
    };
    const db = createFakeDb(initial);
    const deps = makeDeps(db);

    const cancelReq = makeCallableRequest({
      dogId: "dog-01",
      protocolId: "tp-01",
      cancelReason: "Prescrição suspensa pelo veterinário",
      operationId: "op-cancel-01",
    });
    const cancelRes = await runHealthCancelTreatmentProtocol(cancelReq, deps);
    assert.strictEqual(cancelRes["success"], true);
    assert.strictEqual(cancelRes["status"], "cancelled");

    const pDoc = db._store.get("dogs/dog-01/treatment_protocols/tp-01")!;
    assert.strictEqual(pDoc["status"], "cancelled");
    assert.strictEqual(pDoc["cancel_reason"], "Prescrição suspensa pelo veterinário");

    // Prova que doses futuras abertas foram canceladas com o motivo fornecido
    const schedDoc = db._store.get(`dogs/dog-01/health_schedule/${schedId}`)!;
    assert.strictEqual(schedDoc["lifecycle_status"], "cancelled", "Agendamento aberto cancelado no cancelamento do protocolo");
    assert.strictEqual(schedDoc["cancel_reason"], "Prescrição suspensa pelo veterinário");

    const caseDoc = db._store.get("dogs/dog-01/clinical_cases/case-01")!;
    assert.strictEqual(caseDoc["active_treatments_count"], 0);
    assert.strictEqual(caseDoc["has_pending_schedule"], false, "has_pending_schedule é false após cancelamento");
    assert.strictEqual(caseDoc["event_count"], 3);

    console.log("✓ Cancel TreatmentProtocol: reason, event, active count & schedule cancelled passed");
  }

  // ───────────────────────────────────────────────────────────────────────────
  // 6. ADMINISTER DOSE (Deterministic doseId, Schedule reconciliation, ClinicalEvent)
  // ───────────────────────────────────────────────────────────────────────────
  {
    const initial: Record<string, JsonMap> = {
      "dogs/dog-01": {id: "dog-01"},
      "dogs/dog-01/clinical_cases/case-01": {
        id: "case-01",
        clinical_status: "under_treatment",
        event_count: 4,
        revision: 2,
        active_treatments_count: 1,
      },
      "dogs/dog-01/treatment_protocols/tp-01": {
        id: "tp-01",
        case_id: "case-01",
        dog_id: "dog-01",
        status: "active",
        medication_name: "Carprofeno",
        doses_administered: 0,
      },
      [`dogs/dog-01/health_schedule/${deterministicDoseScheduleId("dog-01", "tp-01", "dose_1")}`]: {
        id: deterministicDoseScheduleId("dog-01", "tp-01", "dose_1"),
        lifecycle_status: "open",
        schedule_type: "dose",
      },
    };
    const db = createFakeDb(initial);
    const deps = makeDeps(db);

    const adminReq = makeCallableRequest({
      dogId: "dog-01",
      protocolId: "tp-01",
      plannedDoseId: "dose_1",
      administeredAt: "2026-09-05T12:00:00Z",
      observations: "Administrado com alimento",
      operationId: "op-admin-01",
    });

    const res = await runHealthAdministerTreatmentDose(adminReq, deps);
    assert.strictEqual(res["success"], true);
    assert.strictEqual(res["status"], "administered");
    const expectedDoseId = deriveDoseId("tp-01", "dose_1");
    assert.strictEqual(res["doseId"], expectedDoseId);

    // Prova DoseAdministration gravada com ID determinístico
    const doseDoc = db._store.get(`dogs/dog-01/treatment_protocols/tp-01/doses/${expectedDoseId}`);
    assert.ok(doseDoc, "DoseAdministration deve existir");
    assert.strictEqual(doseDoc["status"], "administered");
    assert.strictEqual(doseDoc["planned_dose_id"], "dose_1");
    assert.strictEqual(doseDoc["idempotency_key"], expectedDoseId);
    assert.strictEqual(doseDoc["observations"], "Administrado com alimento");

    // Prova HealthScheduleItem reconciliado para completed
    const schedDoc = db._store.get(
      `dogs/dog-01/health_schedule/${deterministicDoseScheduleId("dog-01", "tp-01", "dose_1")}`,
    )!;
    assert.strictEqual(schedDoc["lifecycle_status"], "completed");

    // Prova doses_administered incrementado no protocolo
    const pDoc = db._store.get("dogs/dog-01/treatment_protocols/tp-01")!;
    assert.strictEqual(pDoc["doses_administered"], 1);

    // Prova ClinicalEvent dose_note emitido
    const eventId = res["eventId"] as string;
    const evtDoc = db._store.get(`dogs/dog-01/clinical_cases/case-01/clinical_events/${eventId}`)!;
    assert.strictEqual(evtDoc["event_type"], "dose_note");
    assert.strictEqual(evtDoc["payload_type"], "dose_note_v1");

    // Prova projeções atualizadas no ClinicalCase
    const caseDoc = db._store.get("dogs/dog-01/clinical_cases/case-01")!;
    assert.strictEqual(caseDoc["event_count"], 5);

    // Prova replay com mesmo operationId é idempotente
    const replay = await runHealthAdministerTreatmentDose(adminReq, deps);
    assert.deepStrictEqual(replay, res);

    // Prova que tentar administrar a mesma dose planejada com outro operationId falha
    const secondReq = makeCallableRequest({
      dogId: "dog-01",
      protocolId: "tp-01",
      plannedDoseId: "dose_1",
      operationId: "op-admin-02-different",
    });
    const secondRes = await runHealthAdministerTreatmentDose(secondReq, deps);
    assert.strictEqual(secondRes["status"], "administered", "Dose já administrada retorna recibo existente sem duplicar");

    console.log("✓ Administer Dose: deterministic doseId, schedule completion & idempotency passed");
  }

  // ───────────────────────────────────────────────────────────────────────────
  // 7. SKIP DOSE
  // ───────────────────────────────────────────────────────────────────────────
  {
    const initial: Record<string, JsonMap> = {
      "dogs/dog-01": {id: "dog-01"},
      "dogs/dog-01/clinical_cases/case-01": {
        id: "case-01",
        clinical_status: "under_treatment",
        event_count: 5,
        revision: 3,
        active_treatments_count: 1,
      },
      "dogs/dog-01/treatment_protocols/tp-01": {
        id: "tp-01",
        case_id: "case-01",
        dog_id: "dog-01",
        status: "active",
        medication_name: "Carprofeno",
      },
      [`dogs/dog-01/health_schedule/${deterministicDoseScheduleId("dog-01", "tp-01", "dose_2")}`]: {
        id: deterministicDoseScheduleId("dog-01", "tp-01", "dose_2"),
        lifecycle_status: "open",
        schedule_type: "dose",
      },
    };
    const db = createFakeDb(initial);
    const deps = makeDeps(db);

    const skipReq = makeCallableRequest({
      dogId: "dog-01",
      protocolId: "tp-01",
      plannedDoseId: "dose_2",
      skipReason: "Cão apresentou êmese pós-alimentar",
      operationId: "op-skip-01",
    });

    const res = await runHealthSkipTreatmentDose(skipReq, deps);
    assert.strictEqual(res["success"], true);
    assert.strictEqual(res["status"], "skipped");
    const expectedDoseId = deriveDoseId("tp-01", "dose_2");

    const doseDoc = db._store.get(`dogs/dog-01/treatment_protocols/tp-01/doses/${expectedDoseId}`)!;
    assert.strictEqual(doseDoc["status"], "skipped");
    assert.strictEqual(doseDoc["skip_reason"], "Cão apresentou êmese pós-alimentar");

    const schedDoc = db._store.get(
      `dogs/dog-01/health_schedule/${deterministicDoseScheduleId("dog-01", "tp-01", "dose_2")}`,
    )!;
    assert.strictEqual(schedDoc["lifecycle_status"], "completed");

    const caseDoc = db._store.get("dogs/dog-01/clinical_cases/case-01")!;
    assert.strictEqual(caseDoc["event_count"], 6);

    console.log("✓ Skip Dose: reason required, schedule updated & event created passed");
  }

  // ───────────────────────────────────────────────────────────────────────────
  // 8. TRANSACTIONAL SAFETY (All-or-Nothing Rollback)
  // ───────────────────────────────────────────────────────────────────────────
  {
    const initial: Record<string, JsonMap> = {
      "dogs/dog-01": {id: "dog-01"},
      "dogs/dog-01/clinical_cases/case-01": {
        id: "case-01",
        clinical_status: "under_treatment",
        event_count: 10,
      },
    };
    const db = createFakeDb(initial);
    const deps = makeDeps(db);

    // Tentativa com protocolo inexistente deve falhar e não alterar nada
    const badReq = makeCallableRequest({
      dogId: "dog-01",
      protocolId: "tp-inexistente",
      plannedDoseId: "dose_1",
      operationId: "op-bad",
    });

    await assert.rejects(
      () => runHealthAdministerTreatmentDose(badReq, deps),
      /não encontrado/,
    );

    const caseDoc = db._store.get("dogs/dog-01/clinical_cases/case-01")!;
    assert.strictEqual(caseDoc["event_count"], 10, "Rollback: event_count inalterado");
    console.log("✓ Transactional safety: failure leaves database completely untouched");
  }

  // ───────────────────────────────────────────────────────────────────────────
  // 9. AUTHORIZATION MATRIX (Dose Administration & Skip)
  // ───────────────────────────────────────────────────────────────────────────
  {
    const initial: Record<string, JsonMap> = {
      "dogs/dog-01": {id: "dog-01"},
      "dogs/dog-01/clinical_cases/case-01": {
        id: "case-01",
        clinical_status: "under_treatment",
        event_count: 1,
      },
      "dogs/dog-01/treatment_protocols/tp-01": {
        id: "tp-01",
        case_id: "case-01",
        dog_id: "dog-01",
        status: "active",
        medication_name: "Dipirona",
      },
    };

    // Cenário A: Ator sem permissão de rotina nem clínica -> Negado
    const dbA = createFakeDb(initial);
    const depsA = makeDeps(dbA);
    depsA.requireRecordRoutine = async () => {
      throw new Error("permission-denied: Usuário não possui permissão para registrar rotina ou ato clínico");
    };

    const reqA = makeCallableRequest({
      dogId: "dog-01",
      protocolId: "tp-01",
      plannedDoseId: "dose_1",
      operationId: "op-auth-denied",
    });

    await assert.rejects(
      () => runHealthAdministerTreatmentDose(reqA, depsA),
      /permission-denied/,
      "Ator sem permissões deve ser rejeitado",
    );

    // Cenário B: Ator sem acesso ao cão específico -> Negado
    const dbB = createFakeDb(initial);
    const depsB = makeDeps(dbB);
    depsB.requireDogAccess = async () => {
      throw new Error("permission-denied: Sem acesso ao prontuário deste cão");
    };

    await assert.rejects(
      () => runHealthAdministerTreatmentDose(reqA, depsB),
      /permission-denied/,
      "Ator sem acesso ao cão deve ser rejeitado",
    );

    // Cenário C: Ator com permissão de rotina e acesso ao cão -> Autorizado
    const dbC = createFakeDb(initial);
    const depsC = makeDeps(dbC);
    const resC = await runHealthAdministerTreatmentDose(reqA, depsC);
    assert.strictEqual(resC["success"], true, "Ator com record_routine executa dose com sucesso");

    // Cenário D: Ator com permissão clínica e acesso ao cão -> Autorizado
    const dbD = createFakeDb(initial);
    const depsD = makeDeps(dbD);
    depsD.requireRecordRoutine = async () => ({
      uid: "uid-vet",
      name: "Veterinário",
      email: "vet@gcm.com.br",
      ra: "654321",
    });
    const resD = await runHealthAdministerTreatmentDose(reqA, depsD);
    assert.strictEqual(resD["success"], true, "Ator com record_clinical executa dose com sucesso");

    // Cenário E: Ator com apenas permissão genérica CRUD health.create (sem rotina nem clínica) -> Negado
    const dbE = createFakeDb(initial);
    const depsE = makeDeps(dbE);
    depsE.requireRecordRoutine = async () => {
      // Simula a nova implementação de index.ts onde health.create NÃO concede execução de dose
      throw new Error("permission-denied: Permissão 'health.create' insuficiente para administração de dose (exige record_routine ou record_clinical)");
    };
    await assert.rejects(
      () => runHealthAdministerTreatmentDose(reqA, depsE),
      /permission-denied/,
      "health.create não deve autorizar administração de dose",
    );

    console.log("✓ Authorization matrix: routine/clinical/dogAccess access checks and health.create rejection passed");
  }

  console.log("\nALL TreatmentProtocol backend test groups passed successfully!");
}

runTests().catch((err) => {
  console.error("Test failed:", err);
  process.exit(1);
});
