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
      professional: {name: "Dra. Costa"},
      sourceDocument: {health_document_id: "doc-rec-01"},
      operationId: "op-create-prot-01",
    });
    await assert.rejects(
      () => runHealthCreateTreatmentProtocol(confReq, deps),
      /já utilizado com payload diferente/,
      "Conflito de payload detectado",
    );

    console.log("✓ Create TreatmentProtocol: happy path, idempotency & case transition passed");
  }

  // ───────────────────────────────────────────────────────────────────────────
  // 3. PAUSE & RESUME TREATMENT PROTOCOL
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
        medication_name: "Amoxicilina",
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

    const caseAfterResume = db._store.get("dogs/dog-01/clinical_cases/case-01")!;
    assert.strictEqual(caseAfterResume["active_treatments_count"], 1, "active treatments restaurado");
    assert.strictEqual(caseAfterResume["event_count"], 7, "event_count incrementado");

    console.log("✓ Pause & Resume TreatmentProtocol: lifecycle, events & active count passed");
  }

  // ───────────────────────────────────────────────────────────────────────────
  // 4. COMPLETE TREATMENT PROTOCOL (Case Monitoring Transition)
  // ───────────────────────────────────────────────────────────────────────────
  {
    const initial: Record<string, JsonMap> = {
      "dogs/dog-01": {id: "dog-01"},
      "dogs/dog-01/clinical_cases/case-01": {
        id: "case-01",
        clinical_status: "under_treatment",
        event_count: 7,
        revision: 4,
        active_treatments_count: 1,
      },
      "dogs/dog-01/treatment_protocols/tp-01": {
        id: "tp-01",
        case_id: "case-01",
        dog_id: "dog-01",
        status: "active",
        medication_name: "Amoxicilina",
        revision: 2,
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

    const caseDoc = db._store.get("dogs/dog-01/clinical_cases/case-01")!;
    assert.strictEqual(caseDoc["clinical_status"], "monitoring", "Caso transita para monitoring quando tratamentos ativos = 0");
    assert.strictEqual(caseDoc["active_treatments_count"], 0);
    assert.strictEqual(caseDoc["event_count"], 8);

    console.log("✓ Complete TreatmentProtocol: transition to monitoring passed");
  }

  // ───────────────────────────────────────────────────────────────────────────
  // 5. CANCEL TREATMENT PROTOCOL
  // ───────────────────────────────────────────────────────────────────────────
  {
    const initial: Record<string, JsonMap> = {
      "dogs/dog-01": {id: "dog-01"},
      "dogs/dog-01/clinical_cases/case-01": {
        id: "case-01",
        clinical_status: "under_treatment",
        event_count: 2,
        revision: 1,
        active_treatments_count: 1,
      },
      "dogs/dog-01/treatment_protocols/tp-01": {
        id: "tp-01",
        case_id: "case-01",
        dog_id: "dog-01",
        status: "active",
        medication_name: "Amoxicilina",
        revision: 1,
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

    const caseDoc = db._store.get("dogs/dog-01/clinical_cases/case-01")!;
    assert.strictEqual(caseDoc["active_treatments_count"], 0);
    assert.strictEqual(caseDoc["event_count"], 3);

    console.log("✓ Cancel TreatmentProtocol: reason, event & active count passed");
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

  console.log("\nALL TreatmentProtocol backend test groups passed successfully!");
}

runTests().catch((err) => {
  console.error("Test failed:", err);
  process.exit(1);
});
