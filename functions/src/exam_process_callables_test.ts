/**
 * Testes unitários dos callables de ciclo clínico de Exames (F20.EXAM-V1).
 * Executado via node assert.
 */
import * as assert from "assert";
import {
  ExamCaller,
  ExamProcessCallableDeps,
  runHealthRequestExam,
  runHealthRecordExamCollection,
  runHealthRecordExamResult,
  runHealthRecordExamInterpretation,
  runHealthAssessExamImpact,
  runHealthCancelExam,
} from "./exam_process_callables";

type JsonMap = Record<string, unknown>;

const testCaller: ExamCaller = {
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
      for (const [k, v] of pending.entries()) {
        store.set(k, v);
        versions.set(k, (versions.get(k) ?? 0) + 1);
      }
      return result;
    },
    _store: store,
  };
  return db as unknown as FirebaseFirestore.Firestore & {
    _store: Map<string, JsonMap>;
  };
}

function depsFor(options: {
  db: FirebaseFirestore.Firestore;
  allowRequest?: boolean;
  allowRecord?: boolean;
  allowInterpret?: boolean;
  allowManage?: boolean;
  dogAccess?: boolean;
}): ExamProcessCallableDeps {
  const allow = (auth: any, flag: boolean | undefined, cap: string) => {
    if (!auth || !auth.uid) {
      const error = new Error("Autenticação necessária.");
      (error as any).code = "unauthenticated";
      throw error;
    }
    if (flag === false) {
      const error = new Error(`Perfil sem permissão para health.${cap}`);
      (error as any).code = "permission-denied";
      throw error;
    }
    return Promise.resolve(testCaller);
  };
  return {
    db: options.db,
    requireRequestExam: (auth) => allow(auth, options.allowRequest, "request_exam"),
    requireRecordClinical: (auth) => allow(auth, options.allowRecord, "record_clinical"),
    requireInterpretExam: (auth) => allow(auth, options.allowInterpret, "interpret_exam"),
    requireManageClinicalCase: (auth) => allow(auth, options.allowManage, "manage_clinical_case"),
    requireDogAccess: () => {
      if (options.dogAccess === false) {
        const error = new Error("Acesso negado ao registro do cão.");
        (error as any).code = "permission-denied";
        throw error;
      }
      return Promise.resolve();
    },
    isAdministrativeAuthority: () => Promise.resolve(false),
    now: () => new Date("2026-09-04T12:00:00.000Z"),
  };
}

async function runTests() {
  console.log("Starting ExamProcess backend tests...");

  const dogDoc = {id: "dog-1", name: "Spike"};
  const caseDoc = {
    id: "case-1",
    dog_id: "dog-1",
    clinical_status: "open",
    revision: 1,
  };

  // ── 1. REQUEST EXAM ──
  {
    const db = createFakeDb({
      "dogs/dog-1": dogDoc,
      "dogs/dog-1/clinical_cases/case-1": caseDoc,
    });
    const deps = depsFor({db});

    const res = await runHealthRequestExam(
      {
        auth: {uid: testCaller.uid, token: {}} as any,
        data: {
          dogId: "dog-1",
          caseId: "case-1",
          title: "Hemograma Completo",
          examType: "blood_work",
          urgency: "routine",
          labName: "LabVet",
          requestReason: "Checkup",
          operationId: "op-req-1",
        },
      } as any,
      deps,
    );

    assert.strictEqual(res["success"], true);
    assert.strictEqual(res["stage"], "requested");
    const examId = res["examId"] as string;
    assert.ok(examId);

    // Verifica ExamProcess criado
    const examSnap = db._store.get(`dogs/dog-1/clinical_cases/case-1/exams/${examId}`);
    assert.ok(examSnap);
    assert.strictEqual(examSnap["current_stage"], "requested");
    assert.strictEqual(examSnap["title"], "Hemograma Completo");

    // Verifica ClinicalEvent criado
    const eventId = res["eventId"] as string;
    const evtSnap = db._store.get(`dogs/dog-1/clinical_cases/case-1/clinical_events/${eventId}`);
    assert.ok(evtSnap);
    assert.strictEqual(evtSnap["event_type"], "exam_request");
    assert.strictEqual(evtSnap["status"], "final");

    // Verifica transição do ClinicalCase para under_investigation
    const caseSnap = db._store.get("dogs/dog-1/clinical_cases/case-1");
    assert.strictEqual(caseSnap!["clinical_status"], "under_investigation");

    // Verifica HealthScheduleItem criado
    const scheduleId = res["scheduleId"] as string;
    const schedSnap = db._store.get(`dogs/dog-1/health_schedule/${scheduleId}`);
    assert.ok(schedSnap);
    assert.strictEqual(schedSnap["schedule_type"], "exam");
    assert.strictEqual(schedSnap["lifecycle_status"], "open");
    assert.strictEqual(schedSnap["source_type"], "exam_process");
    assert.strictEqual(schedSnap["source_id"], examId);

    // Replay idempotente com mesmo operationId
    const replayRes = await runHealthRequestExam(
      {
        auth: {uid: testCaller.uid, token: {}} as any,
        data: {
          dogId: "dog-1",
          caseId: "case-1",
          title: "Hemograma Completo",
          examType: "blood_work",
          urgency: "routine",
          labName: "LabVet",
          requestReason: "Checkup",
          operationId: "op-req-1",
        },
      } as any,
      deps,
    );
    assert.deepStrictEqual(replayRes, res);

    console.log("✓ Request Exam: happy path, idempotency, schedule generation passed");
  }

  // ── 2. RECORD COLLECTION ──
  {
    const db = createFakeDb({
      "dogs/dog-1": dogDoc,
      "dogs/dog-1/clinical_cases/case-1": caseDoc,
    });
    const deps = depsFor({db});

    const reqRes = await runHealthRequestExam(
      {
        auth: {uid: testCaller.uid, token: {}} as any,
        data: {
          dogId: "dog-1",
          caseId: "case-1",
          title: "Hemograma",
          examType: "blood_work",
          operationId: "op-req-2",
        },
      } as any,
      deps,
    );
    const examId = reqRes["examId"] as string;

    const colRes = await runHealthRecordExamCollection(
      {
        auth: {uid: testCaller.uid, token: {}} as any,
        data: {
          dogId: "dog-1",
          caseId: "case-1",
          examId,
          collectionSite: "Veia cefálica",
          collectionNotes: "Coleta tranquila",
          operationId: "op-col-1",
        },
      } as any,
      deps,
    );
    assert.strictEqual(colRes["success"], true);
    assert.strictEqual(colRes["stage"], "collected");

    const examSnap = db._store.get(`dogs/dog-1/clinical_cases/case-1/exams/${examId}`);
    assert.strictEqual(examSnap!["current_stage"], "collected");
    assert.strictEqual(examSnap!["collection_site"], "Veia cefálica");

    const eventId = colRes["eventId"] as string;
    const evtSnap = db._store.get(`dogs/dog-1/clinical_cases/case-1/clinical_events/${eventId}`);
    assert.ok(evtSnap);
    assert.strictEqual(evtSnap!["entity_kind"], "clinical_event");
    assert.strictEqual(evtSnap!["dog_id"], "dog-1");
    assert.strictEqual(evtSnap!["case_id"], "case-1");
    assert.strictEqual(evtSnap!["exam_id"], examId);
    assert.strictEqual(evtSnap!["event_type"], "exam_collection");
    assert.strictEqual(evtSnap!["payload_type"], "exam_collection_v1");
    assert.strictEqual(evtSnap!["payload_version"], 1);
    assert.strictEqual(evtSnap!["schema_version"], 1);
    assert.strictEqual(evtSnap!["revision"], 1);
    assert.strictEqual(evtSnap!["status"], "final");
    assert.strictEqual((evtSnap!["recorded_by"] as any)["uid"], testCaller.uid);
    assert.strictEqual((evtSnap!["recorded_by"] as any)["name"], testCaller.name);
    assert.ok(evtSnap!["occurred_at"]);
    assert.ok(evtSnap!["recorded_at"]);
    assert.ok(evtSnap!["updated_at"]);
    assert.strictEqual((evtSnap!["content"] as any)["exam_id"], examId);
    assert.strictEqual((evtSnap!["content"] as any)["if_collection_site"], "Veia cefálica");
    assert.strictEqual((evtSnap!["content"] as any)["if_collection_notes"], "Coleta tranquila");

    console.log("✓ Record Collection: happy path & immutable ClinicalEvent passed");
  }

  // ── 3. RECORD RESULT ──
  {
    const db = createFakeDb({
      "dogs/dog-1": dogDoc,
      "dogs/dog-1/clinical_cases/case-1": caseDoc,
    });
    const deps = depsFor({db});

    const reqRes = await runHealthRequestExam(
      {
        auth: {uid: testCaller.uid, token: {}} as any,
        data: {
          dogId: "dog-1",
          caseId: "case-1",
          title: "Hemograma",
          examType: "blood_work",
          operationId: "op-req-3",
        },
      } as any,
      deps,
    );
    const examId = reqRes["examId"] as string;
    const scheduleId = reqRes["scheduleId"] as string;

    await runHealthRecordExamCollection(
      {
        auth: {uid: testCaller.uid, token: {}} as any,
        data: {
          dogId: "dog-1",
          caseId: "case-1",
          examId,
          operationId: "op-col-2",
        },
      } as any,
      deps,
    );

    const resRes = await runHealthRecordExamResult(
      {
        auth: {uid: testCaller.uid, token: {}} as any,
        data: {
          dogId: "dog-1",
          caseId: "case-1",
          examId,
          resultSummary: "Hematócrito normal, plaquetas normais.",
          resultDocumentId: "doc-laudo-123",
          operationId: "op-res-1",
        },
      } as any,
      deps,
    );

    assert.strictEqual(resRes["success"], true);
    assert.strictEqual(resRes["stage"], "resulted");

    const examSnap = db._store.get(`dogs/dog-1/clinical_cases/case-1/exams/${examId}`);
    assert.strictEqual(examSnap!["current_stage"], "resulted");
    assert.strictEqual(examSnap!["result_summary"], "Hematócrito normal, plaquetas normais.");

    // Verifica que o agendamento preventivo foi completado
    const schedSnap = db._store.get(`dogs/dog-1/health_schedule/${scheduleId}`);
    assert.strictEqual(schedSnap!["lifecycle_status"], "completed");

    console.log("✓ Record Result: happy path and schedule completion passed");
  }

  // ── 4. RECORD INTERPRETATION ──
  {
    const db = createFakeDb({
      "dogs/dog-1": dogDoc,
      "dogs/dog-1/clinical_cases/case-1": caseDoc,
    });
    const deps = depsFor({db});

    const reqRes = await runHealthRequestExam(
      {
        auth: {uid: testCaller.uid, token: {}} as any,
        data: {
          dogId: "dog-1",
          caseId: "case-1",
          title: "Hemograma",
          examType: "blood_work",
          operationId: "op-req-4",
        },
      } as any,
      deps,
    );
    const examId = reqRes["examId"] as string;

    await runHealthRecordExamCollection(
      {
        auth: {uid: testCaller.uid, token: {}} as any,
        data: {
          dogId: "dog-1",
          caseId: "case-1",
          examId,
          operationId: "op-col-3",
        },
      } as any,
      deps,
    );

    await runHealthRecordExamResult(
      {
        auth: {uid: testCaller.uid, token: {}} as any,
        data: {
          dogId: "dog-1",
          caseId: "case-1",
          examId,
          resultSummary: "Laudo anexado.",
          operationId: "op-res-2",
        },
      } as any,
      deps,
    );

    const interpRes = await runHealthRecordExamInterpretation(
      {
        auth: {uid: testCaller.uid, token: {}} as any,
        data: {
          dogId: "dog-1",
          caseId: "case-1",
          examId,
          interpretationText: "Cão saudável sem sinais de infecção.",
          professional: {
            name: "Dra. Carolina",
            registration_type: "crmv",
            registration_number: "SP-9999",
            clinic: "Hospital Vet",
          },
          operationId: "op-int-1",
        },
      } as any,
      deps,
    );

    assert.strictEqual(interpRes["success"], true);
    assert.strictEqual(interpRes["stage"], "interpreted");

    const examSnap = db._store.get(`dogs/dog-1/clinical_cases/case-1/exams/${examId}`);
    assert.strictEqual(examSnap!["current_stage"], "interpreted");
    assert.strictEqual(examSnap!["interpretation_text"], "Cão saudável sem sinais de infecção.");

    const eventId = interpRes["eventId"] as string;
    const evtSnap = db._store.get(`dogs/dog-1/clinical_cases/case-1/clinical_events/${eventId}`);
    assert.strictEqual(evtSnap!["event_type"], "exam_interpretation");
    assert.ok(evtSnap!["professional"]);

    console.log("✓ Record Interpretation: happy path with ProfessionalIdentity passed");
  }

  // ── 5. ASSESS OPERATIONAL IMPACT ──
  {
    const db = createFakeDb({
      "dogs/dog-1": dogDoc,
      "dogs/dog-1/clinical_cases/case-1": caseDoc,
    });
    const deps = depsFor({db});

    const reqRes = await runHealthRequestExam(
      {
        auth: {uid: testCaller.uid, token: {}} as any,
        data: {
          dogId: "dog-1",
          caseId: "case-1",
          title: "Raio-X",
          examType: "imaging",
          operationId: "op-req-5",
        },
      } as any,
      deps,
    );
    const examId = reqRes["examId"] as string;

    await runHealthRecordExamCollection(
      {
        auth: {uid: testCaller.uid, token: {}} as any,
        data: {dogId: "dog-1", caseId: "case-1", examId, operationId: "op-col-4"},
      } as any,
      deps,
    );
    await runHealthRecordExamResult(
      {
        auth: {uid: testCaller.uid, token: {}} as any,
        data: {
          dogId: "dog-1",
          caseId: "case-1",
          examId,
          resultSummary: "Fratura consolidada.",
          operationId: "op-res-3",
        },
      } as any,
      deps,
    );
    await runHealthRecordExamInterpretation(
      {
        auth: {uid: testCaller.uid, token: {}} as any,
        data: {
          dogId: "dog-1",
          caseId: "case-1",
          examId,
          interpretationText: "Liberação para treino gradual.",
          professional: {
            name: "Dr. Marcos",
            registration_type: "crmv",
            registration_number: "SP-8888",
            clinic: "VetK9",
          },
          operationId: "op-int-2",
        },
      } as any,
      deps,
    );

    const impactRes = await runHealthAssessExamImpact(
      {
        auth: {uid: testCaller.uid, token: {}} as any,
        data: {
          dogId: "dog-1",
          caseId: "case-1",
          examId,
          operationalImpact: {
            level: "low",
            description: "Apto para serviço com moderação.",
            restrictions_issued: [],
          },
          operationId: "op-imp-1",
        },
      } as any,
      deps,
    );

    assert.strictEqual(impactRes["success"], true);
    assert.strictEqual(impactRes["stage"], "impact_assessed");

    const examSnap = db._store.get(`dogs/dog-1/clinical_cases/case-1/exams/${examId}`);
    assert.strictEqual(examSnap!["current_stage"], "impact_assessed");

    console.log("✓ Assess Operational Impact: happy path passed");
  }

  // ── 6. CANCEL EXAM ──
  {
    const db = createFakeDb({
      "dogs/dog-1": dogDoc,
      "dogs/dog-1/clinical_cases/case-1": caseDoc,
    });
    const deps = depsFor({db});

    const reqRes = await runHealthRequestExam(
      {
        auth: {uid: testCaller.uid, token: {}} as any,
        data: {
          dogId: "dog-1",
          caseId: "case-1",
          title: "Ecografia",
          examType: "imaging",
          operationId: "op-req-6",
        },
      } as any,
      deps,
    );
    const examId = reqRes["examId"] as string;
    const scheduleId = reqRes["scheduleId"] as string;

    const cancelRes = await runHealthCancelExam(
      {
        auth: {uid: testCaller.uid, token: {}} as any,
        data: {
          dogId: "dog-1",
          caseId: "case-1",
          examId,
          cancelReason: "Solicitado por engano pelo condutor.",
          operationId: "op-cnc-1",
        },
      } as any,
      deps,
    );

    assert.strictEqual(cancelRes["success"], true);
    assert.strictEqual(cancelRes["stage"], "cancelled");

    const examSnap = db._store.get(`dogs/dog-1/clinical_cases/case-1/exams/${examId}`);
    assert.strictEqual(examSnap!["current_stage"], "cancelled");
    assert.strictEqual(examSnap!["cancel_reason"], "Solicitado por engano pelo condutor.");

    // Verifica que o agendamento foi cancelado
    const schedSnap = db._store.get(`dogs/dog-1/health_schedule/${scheduleId}`);
    assert.strictEqual(schedSnap!["lifecycle_status"], "cancelled");

    console.log("✓ Cancel Exam: happy path and schedule cancellation passed");
  }

  // ── 7. REQUEST NEGATIVES & EDGE CASES ──
  {
    const db = createFakeDb({
      "dogs/dog-1": dogDoc,
      "dogs/dog-1/clinical_cases/case-1": caseDoc,
    });

    // 7.1 Unauthenticated
    await assert.rejects(
      () =>
        runHealthRequestExam(
          {auth: null, data: {dogId: "dog-1", caseId: "case-1", title: "Raio-X", examType: "imaging", operationId: "op-7-1"}} as any,
          depsFor({db}),
        ),
      (err: any) => err.code === "unauthenticated",
    );

    // 7.2 Missing capability
    await assert.rejects(
      () =>
        runHealthRequestExam(
          {auth: {uid: testCaller.uid}, data: {dogId: "dog-1", caseId: "case-1", title: "Raio-X", examType: "imaging", operationId: "op-7-2"}} as any,
          depsFor({db, allowRequest: false}),
        ),
      (err: any) => err.code === "permission-denied",
    );

    // 7.3 Inaccessible dog
    await assert.rejects(
      () =>
        runHealthRequestExam(
          {auth: {uid: testCaller.uid}, data: {dogId: "dog-1", caseId: "case-1", title: "Raio-X", examType: "imaging", operationId: "op-7-3"}} as any,
          depsFor({db, dogAccess: false}),
        ),
      (err: any) => err.code === "permission-denied",
    );

    // 7.4 Nonexistent case
    await assert.rejects(
      () =>
        runHealthRequestExam(
          {auth: {uid: testCaller.uid}, data: {dogId: "dog-1", caseId: "case-inexistente", title: "Raio-X", examType: "imaging", operationId: "op-7-4"}} as any,
          depsFor({db}),
        ),
      (err: any) => err.code === "not-found",
    );

    // 7.5 Case in terminal status (discharged)
    const dbTerminal = createFakeDb({
      "dogs/dog-1": dogDoc,
      "dogs/dog-1/clinical_cases/case-term": {id: "case-term", dog_id: "dog-1", clinical_status: "discharged", revision: 2},
    });
    await assert.rejects(
      () =>
        runHealthRequestExam(
          {auth: {uid: testCaller.uid}, data: {dogId: "dog-1", caseId: "case-term", title: "Raio-X", examType: "imaging", operationId: "op-7-5"}} as any,
          depsFor({db: dbTerminal}),
        ),
      (err: any) => err.code === "failed-precondition",
    );

    // 7.6 Malformed exam type
    await assert.rejects(
      () =>
        runHealthRequestExam(
          {auth: {uid: testCaller.uid}, data: {dogId: "dog-1", caseId: "case-1", title: "Raio-X", examType: "magic_type", operationId: "op-7-6"}} as any,
          depsFor({db}),
        ),
      (err: any) => err.code === "invalid-argument",
    );

    // 7.7 Idempotency conflict: same opId with different title
    const resReq = await runHealthRequestExam(
      {auth: {uid: testCaller.uid}, data: {dogId: "dog-1", caseId: "case-1", title: "Bioquímico", examType: "blood_work", operationId: "op-7-7"}} as any,
      depsFor({db}),
    );
    assert.strictEqual(resReq["success"], true);

    await assert.rejects(
      () =>
        runHealthRequestExam(
          {auth: {uid: testCaller.uid}, data: {dogId: "dog-1", caseId: "case-1", title: "Outro Titulo Conflitante", examType: "blood_work", operationId: "op-7-7"}} as any,
          depsFor({db}),
        ),
      (err: any) => err.code === "failed-precondition",
    );

    // 7.8 Case status integrity: under_treatment and monitoring do NOT regress
    const dbTreatment = createFakeDb({
      "dogs/dog-1": dogDoc,
      "dogs/dog-1/clinical_cases/case-treat": {id: "case-treat", dog_id: "dog-1", clinical_status: "under_treatment", revision: 2},
    });
    await runHealthRequestExam(
      {auth: {uid: testCaller.uid}, data: {dogId: "dog-1", caseId: "case-treat", title: "Controle", examType: "blood_work", operationId: "op-7-8"}} as any,
      depsFor({db: dbTreatment}),
    );
    assert.strictEqual(dbTreatment._store.get("dogs/dog-1/clinical_cases/case-treat")!["clinical_status"], "under_treatment");

    // 7.9 Actor spoofing: client supplied recordedBy is ignored
    const dbSpoof = createFakeDb({
      "dogs/dog-1": dogDoc,
      "dogs/dog-1/clinical_cases/case-1": caseDoc,
    });
    const resSpoof = await runHealthRequestExam(
      {auth: {uid: testCaller.uid}, data: {dogId: "dog-1", caseId: "case-1", title: "Teste Spoof", examType: "blood_work", recordedBy: {uid: "impostor"}, operationId: "op-7-9"}} as any,
      depsFor({db: dbSpoof}),
    );
    const examSpoof = dbSpoof._store.get(`dogs/dog-1/clinical_cases/case-1/exams/${resSpoof["examId"]}`);
    assert.strictEqual((examSpoof!["recorded_by"] as any)["uid"], testCaller.uid);

    console.log("✓ Request Exam: authorization, validation, conflict & status integrity passed");
  }

  // ── 8. COLLECTION NEGATIVES & EDGE CASES ──
  {
    const db = createFakeDb({
      "dogs/dog-1": dogDoc,
      "dogs/dog-1/clinical_cases/case-1": caseDoc,
    });
    const deps = depsFor({db});

    const resReq = await runHealthRequestExam(
      {auth: {uid: testCaller.uid}, data: {dogId: "dog-1", caseId: "case-1", title: "Hemograma", examType: "blood_work", operationId: "op-req-8"}} as any,
      deps,
    );
    const examId = resReq["examId"] as string;

    // 8.1 First collection succeeds
    const colRes = await runHealthRecordExamCollection(
      {auth: {uid: testCaller.uid}, data: {dogId: "dog-1", caseId: "case-1", examId, collectedAt: "2026-09-04T12:30:00.000Z", operationId: "op-col-8"}} as any,
      deps,
    );
    assert.strictEqual(colRes["success"], true);

    // 8.2 Attempting second collection with DIFFERENT operationId fails (invalid prior stage)
    await assert.rejects(
      () =>
        runHealthRecordExamCollection(
          {auth: {uid: testCaller.uid}, data: {dogId: "dog-1", caseId: "case-1", examId, collectedAt: "2026-09-04T13:00:00.000Z", operationId: "op-col-8-bis"}} as any,
          deps,
        ),
      (err: any) => err.code === "failed-precondition",
    );

    // 8.3 Replay with same operationId is idempotent
    const replay = await runHealthRecordExamCollection(
      {auth: {uid: testCaller.uid}, data: {dogId: "dog-1", caseId: "case-1", examId, collectedAt: "2026-09-04T12:30:00.000Z", operationId: "op-col-8"}} as any,
      deps,
    );
    assert.strictEqual(replay["success"], true);

    console.log("✓ Record Collection: stage transitions and replay safety passed");
  }

  // ── 9. RESULT NEGATIVES & INDEPENDENCE ──
  {
    const db = createFakeDb({
      "dogs/dog-1": dogDoc,
      "dogs/dog-1/clinical_cases/case-1": caseDoc,
    });
    const deps = depsFor({db});

    const resReq = await runHealthRequestExam(
      {auth: {uid: testCaller.uid}, data: {dogId: "dog-1", caseId: "case-1", title: "Urina", examType: "urinalysis", operationId: "op-req-9"}} as any,
      deps,
    );
    const examId = resReq["examId"] as string;

    // 9.1 Cannot result skipping collection (stage is requested)
    await assert.rejects(
      () =>
        runHealthRecordExamResult(
          {auth: {uid: testCaller.uid}, data: {dogId: "dog-1", caseId: "case-1", examId, resultedAt: "2026-09-04T14:00:00.000Z", resultSummary: "Densidade 1.025", operationId: "op-res-9"}} as any,
          deps,
        ),
      (err: any) => err.code === "failed-precondition",
    );

    // 9.2 Missing result summary
    await runHealthRecordExamCollection(
      {auth: {uid: testCaller.uid}, data: {dogId: "dog-1", caseId: "case-1", examId, collectedAt: "2026-09-04T12:00:00.000Z", operationId: "op-col-9"}} as any,
      deps,
    );
    await assert.rejects(
      () =>
        runHealthRecordExamResult(
          {auth: {uid: testCaller.uid}, data: {dogId: "dog-1", caseId: "case-1", examId, resultedAt: "2026-09-04T14:00:00.000Z", resultSummary: "", operationId: "op-res-9-empty"}} as any,
          deps,
        ),
      (err: any) => err.code === "invalid-argument",
    );

    // 9.3 Result does NOT create veterinary interpretation
    const resRes = await runHealthRecordExamResult(
      {auth: {uid: testCaller.uid}, data: {dogId: "dog-1", caseId: "case-1", examId, resultedAt: "2026-09-04T14:00:00.000Z", resultSummary: "Normal", operationId: "op-res-9"}} as any,
      deps,
    );
    assert.strictEqual(resRes["success"], true);
    const examSnap = db._store.get(`dogs/dog-1/clinical_cases/case-1/exams/${examId}`);
    assert.strictEqual(examSnap!["interpreted_at"], undefined);
    assert.strictEqual(examSnap!["interpretation_text"], undefined);

    console.log("✓ Record Result: preconditions, validation & independence passed");
  }

  // ── 10. INTERPRETATION NEGATIVES & PROFESSIONAL IDENTITY ──
  {
    const db = createFakeDb({
      "dogs/dog-1": dogDoc,
      "dogs/dog-1/clinical_cases/case-1": caseDoc,
    });
    const deps = depsFor({db});

    const resReq = await runHealthRequestExam(
      {auth: {uid: testCaller.uid}, data: {dogId: "dog-1", caseId: "case-1", title: "Raio-X", examType: "imaging", operationId: "op-req-10"}} as any,
      deps,
    );
    const examId = resReq["examId"] as string;
    await runHealthRecordExamCollection(
      {auth: {uid: testCaller.uid}, data: {dogId: "dog-1", caseId: "case-1", examId, collectedAt: "2026-09-04T12:00:00.000Z", operationId: "op-col-10"}} as any,
      deps,
    );

    // 10.1 Cannot interpret before result (still in collected stage)
    await assert.rejects(
      () =>
        runHealthRecordExamInterpretation(
          {auth: {uid: testCaller.uid}, data: {
            dogId: "dog-1", caseId: "case-1", examId,
            interpretedAt: "2026-09-04T14:00:00.000Z",
            interpretationText: "Tudo certo",
            professional: {name: "Dr Vet", registrationType: "crmv", registrationNumber: "1234", clinic: "Vet"},
            operationId: "op-int-10-early",
          }} as any,
          deps,
        ),
      (err: any) => err.code === "failed-precondition",
    );

    // Result the exam
    await runHealthRecordExamResult(
      {auth: {uid: testCaller.uid}, data: {dogId: "dog-1", caseId: "case-1", examId, resultedAt: "2026-09-04T13:00:00.000Z", resultSummary: "Sem fratura", operationId: "op-res-10"}} as any,
      deps,
    );

    // 10.2 Missing professional identity fields
    await assert.rejects(
      () =>
        runHealthRecordExamInterpretation(
          {auth: {uid: testCaller.uid}, data: {
            dogId: "dog-1", caseId: "case-1", examId,
            interpretedAt: "2026-09-04T14:00:00.000Z",
            interpretationText: "Laudo aprovado",
            professional: {name: "Dr Vet", registrationType: "crmv", registrationNumber: "" /* missing */, clinic: "Vet"},
            operationId: "op-int-10-crmv",
          }} as any,
          deps,
        ),
      (err: any) => err.code === "invalid-argument",
    );

    // 10.3 Missing capability
    await assert.rejects(
      () =>
        runHealthRecordExamInterpretation(
          {auth: {uid: testCaller.uid}, data: {
            dogId: "dog-1", caseId: "case-1", examId,
            interpretedAt: "2026-09-04T14:00:00.000Z",
            interpretationText: "Laudo aprovado",
            professional: {name: "Dr Vet", registrationType: "crmv", registrationNumber: "1234-SP", clinic: "Vet"},
            operationId: "op-int-10-cap",
          }} as any,
          depsFor({db, allowInterpret: false}),
        ),
      (err: any) => err.code === "permission-denied",
    );

    console.log("✓ Record Interpretation: professional identity, stage & authority passed");
  }

  // ── 11. IMPACT NEGATIVES & INDEPENDENCE ──
  {
    const db = createFakeDb({
      "dogs/dog-1": dogDoc,
      "dogs/dog-1/clinical_cases/case-1": caseDoc,
    });
    const deps = depsFor({db});

    const resReq = await runHealthRequestExam(
      {auth: {uid: testCaller.uid}, data: {dogId: "dog-1", caseId: "case-1", title: "Cardio", examType: "cardiology", operationId: "op-req-11"}} as any,
      deps,
    );
    const examId = resReq["examId"] as string;

    // 11.1 Cannot assess impact on requested stage
    await assert.rejects(
      () =>
        runHealthAssessExamImpact(
          {auth: {uid: testCaller.uid}, data: {
            dogId: "dog-1", caseId: "case-1", examId,
            impactAssessedAt: "2026-09-04T15:00:00.000Z",
            operationalImpact: {level: "none", description: "Apto"},
            operationId: "op-imp-11",
          }} as any,
          deps,
        ),
      (err: any) => err.code === "failed-precondition",
    );

    console.log("✓ Assess Operational Impact: preconditions & stage guards passed");
  }

  // ── 12. CANCEL NEGATIVES & TERMINAL STATE ──
  {
    const db = createFakeDb({
      "dogs/dog-1": dogDoc,
      "dogs/dog-1/clinical_cases/case-1": caseDoc,
    });
    const deps = depsFor({db});

    const resReq = await runHealthRequestExam(
      {auth: {uid: testCaller.uid}, data: {dogId: "dog-1", caseId: "case-1", title: "Citologia", examType: "biopsy", operationId: "op-req-12"}} as any,
      deps,
    );
    const examId = resReq["examId"] as string;

    // 12.1 Missing cancel reason
    await assert.rejects(
      () =>
        runHealthCancelExam(
          {auth: {uid: testCaller.uid}, data: {dogId: "dog-1", caseId: "case-1", examId, cancelReason: "", operationId: "op-cnc-12-empty"}} as any,
          deps,
        ),
      (err: any) => err.code === "invalid-argument",
    );

    // Cancel successfully
    await runHealthCancelExam(
      {auth: {uid: testCaller.uid}, data: {dogId: "dog-1", caseId: "case-1", examId, cancelReason: "Desistência justificada", operationId: "op-cnc-12"}} as any,
      deps,
    );

    // 12.2 Cannot cancel already cancelled exam
    await assert.rejects(
      () =>
        runHealthCancelExam(
          {auth: {uid: testCaller.uid}, data: {dogId: "dog-1", caseId: "case-1", examId, cancelReason: "Outro motivo", operationId: "op-cnc-12-bis"}} as any,
          deps,
        ),
      (err: any) => err.code === "failed-precondition",
    );

    console.log("✓ Cancel Exam: terminal state protections & validation passed");
  }

  // ── 13. TRANSACTIONAL ATOMICITY (ALL-OR-NOTHING) ──
  {
    const db = createFakeDb({
      "dogs/dog-1": dogDoc,
      "dogs/dog-1/clinical_cases/case-1": caseDoc,
    });

    // Injected transactional error
    const failingDb = {
      ...db,
      async runTransaction<T>(_fn: any): Promise<T> {
        throw new Error("Simulated Firestore transaction network crash");
      },
    } as any;

    await assert.rejects(
      () =>
        runHealthRequestExam(
          {auth: {uid: testCaller.uid}, data: {dogId: "dog-1", caseId: "case-1", title: "Hemograma", examType: "blood_work", operationId: "op-crash"}} as any,
          depsFor({db: failingDb}),
        ),
      /Simulated Firestore transaction network crash/,
    );

    // Prove zero partial writes occurred
    assert.strictEqual(db._store.size, 2, "No partial documents written to store on transaction failure");
    assert.ok(!db._store.has("dogs/dog-1/clinical_cases/case-1/exams/exam_crash"));

    console.log("✓ Transactional safety: failure leaves database completely untouched (all-or-nothing) passed");
  }

  // ── 14. CLINICALCASE DERIVED PROJECTIONS & ATOMICITY (F20.EXAM-V1) ──
  {
    const initialT0 = new Date("2026-09-04T10:00:00.000Z");
    const tReq = new Date("2026-09-04T11:00:00.000Z");
    const tCol = new Date("2026-09-04T12:00:00.000Z");
    const tRes = new Date("2026-09-04T13:00:00.000Z");
    const tInt = new Date("2026-09-04T14:00:00.000Z");
    const tImp = new Date("2026-09-04T15:00:00.000Z");

    const casePath = "dogs/dog-1/clinical_cases/case-proj-1";
    const initialCase = {
      id: "case-proj-1",
      dog_id: "dog-1",
      clinical_status: "open",
      revision: 1,
      event_count: 1,
      last_event_at: initialT0,
    };

    const db = createFakeDb({
      "dogs/dog-1": dogDoc,
      [casePath]: initialCase,
    });

    let currentTestTime = tReq;
    const testDeps = {
      ...depsFor({db}),
      now: () => currentTestTime,
    };

    // 1. REQUEST: count 1 -> 2, last_event_at -> tReq
    const reqRes = await runHealthRequestExam(
      {
        auth: {uid: testCaller.uid},
        data: {
          dogId: "dog-1",
          caseId: "case-proj-1",
          title: "Hemograma Projeção",
          examType: "blood_work",
          operationId: "op-proj-req",
        },
      } as any,
      testDeps,
    );
    const examId = reqRes["examId"] as string;
    let caseAfterReq = db._store.get(casePath)!;
    assert.strictEqual(caseAfterReq["event_count"], 2, "event_count increments 1 -> 2 on exam request");
    assert.strictEqual(caseAfterReq["revision"], 2, "case revision increments 1 -> 2");
    assert.strictEqual(caseAfterReq["clinical_status"], "under_investigation");
    assert.strictEqual(
      (caseAfterReq["last_event_at"] as any).toMillis(),
      tReq.getTime(),
      "last_event_at matches request recorded_at",
    );

    // 2. COLLECTION: count 2 -> 3, last_event_at -> tCol
    currentTestTime = tCol;
    await runHealthRecordExamCollection(
      {
        auth: {uid: testCaller.uid},
        data: {
          dogId: "dog-1",
          caseId: "case-proj-1",
          examId,
          collectionSite: "Veia cefálica",
          operationId: "op-proj-col",
        },
      } as any,
      testDeps,
    );
    let caseAfterCol = db._store.get(casePath)!;
    assert.strictEqual(caseAfterCol["event_count"], 3, "event_count increments 2 -> 3 on collection");
    assert.strictEqual(caseAfterCol["revision"], 3, "case revision increments 2 -> 3");
    assert.strictEqual(
      (caseAfterCol["last_event_at"] as any).toMillis(),
      tCol.getTime(),
      "last_event_at matches collection recorded_at",
    );

    // 3. RESULT: count 3 -> 4, last_event_at -> tRes
    currentTestTime = tRes;
    await runHealthRecordExamResult(
      {
        auth: {uid: testCaller.uid},
        data: {
          dogId: "dog-1",
          caseId: "case-proj-1",
          examId,
          resultSummary: "Plaquetas normais",
          operationId: "op-proj-res",
        },
      } as any,
      testDeps,
    );
    let caseAfterRes = db._store.get(casePath)!;
    assert.strictEqual(caseAfterRes["event_count"], 4, "event_count increments 3 -> 4 on result");
    assert.strictEqual(caseAfterRes["revision"], 4, "case revision increments 3 -> 4");
    assert.strictEqual(
      (caseAfterRes["last_event_at"] as any).toMillis(),
      tRes.getTime(),
      "last_event_at matches result recorded_at",
    );

    // 4. INTERPRETATION: count 4 -> 5, last_event_at -> tInt
    currentTestTime = tInt;
    await runHealthRecordExamInterpretation(
      {
        auth: {uid: testCaller.uid},
        data: {
          dogId: "dog-1",
          caseId: "case-proj-1",
          examId,
          interpretationText: "Cão saudável",
          professional: {
            name: "Dr. Veterinário",
            registration_type: "CRMV",
            registration_number: "CRMV-1234",
            clinic: "Clínica Central",
          },
          operationId: "op-proj-int",
        },
      } as any,
      testDeps,
    );
    let caseAfterInt = db._store.get(casePath)!;
    assert.strictEqual(caseAfterInt["event_count"], 5, "event_count increments 4 -> 5 on interpretation");
    assert.strictEqual(caseAfterInt["revision"], 5, "case revision increments 4 -> 5");
    assert.strictEqual(
      (caseAfterInt["last_event_at"] as any).toMillis(),
      tInt.getTime(),
      "last_event_at matches interpretation recorded_at",
    );

    // 5. IMPACT ASSESSMENT: count 5 -> 6, last_event_at -> tImp
    currentTestTime = tImp;
    await runHealthAssessExamImpact(
      {
        auth: {uid: testCaller.uid},
        data: {
          dogId: "dog-1",
          caseId: "case-proj-1",
          examId,
          operationalImpact: {
            level: "none",
            description: "Apto para serviço operacional",
          },
          operationId: "op-proj-imp",
        },
      } as any,
      testDeps,
    );
    let caseAfterImp = db._store.get(casePath)!;
    assert.strictEqual(caseAfterImp["event_count"], 6, "event_count increments 5 -> 6 on impact assessment");
    assert.strictEqual(caseAfterImp["revision"], 6, "case revision increments 5 -> 6");
    assert.strictEqual(
      (caseAfterImp["last_event_at"] as any).toMillis(),
      tImp.getTime(),
      "last_event_at matches impact recorded_at",
    );

    // 6. IDEMPOTENT REPLAY: must NOT increment event_count or mutate last_event_at
    const replayRes = await runHealthAssessExamImpact(
      {
        auth: {uid: testCaller.uid},
        data: {
          dogId: "dog-1",
          caseId: "case-proj-1",
          examId,
          operationalImpact: {
            level: "none",
            description: "Apto para serviço operacional",
          },
          operationId: "op-proj-imp",
        },
      } as any,
      testDeps,
    );
    assert.strictEqual(replayRes["stage"], "impact_assessed");
    let caseAfterReplay = db._store.get(casePath)!;
    assert.strictEqual(caseAfterReplay["event_count"], 6, "event_count UNCHANGED on idempotent replay");
    assert.strictEqual(caseAfterReplay["revision"], 6, "case revision UNCHANGED on idempotent replay");
    assert.strictEqual(
      (caseAfterReplay["last_event_at"] as any).toMillis(),
      tImp.getTime(),
      "last_event_at UNCHANGED on idempotent replay",
    );

    // 7. CANCELLATION: cancellation creates no ClinicalEvent, so event_count is preserved
    const req2Res = await runHealthRequestExam(
      {
        auth: {uid: testCaller.uid},
        data: {
          dogId: "dog-1",
          caseId: "case-proj-1",
          title: "Exame Cancelável",
          examType: "urinalysis",
          operationId: "op-proj-cancel-req",
        },
      } as any,
      testDeps,
    );
    const exam2Id = req2Res["examId"] as string;
    let caseAfterReq2 = db._store.get(casePath)!;
    assert.strictEqual(caseAfterReq2["event_count"], 7, "event_count increments to 7 for 2nd exam request");

    await runHealthCancelExam(
      {
        auth: {uid: testCaller.uid},
        data: {
          dogId: "dog-1",
          caseId: "case-proj-1",
          examId: exam2Id,
          cancelReason: "Cancelado pelo veterinário",
          operationId: "op-proj-cancel",
        },
      } as any,
      testDeps,
    );
    let caseAfterCancel = db._store.get(casePath)!;
    assert.strictEqual(caseAfterCancel["event_count"], 7, "event_count remains 7 after cancel (no clinical event)");

    // 8. FAILURE ATOMICITY: forced failure leaves event_count, revision and events untouched
    const failingDb = {
      ...db,
      async runTransaction<T>(_fn: any): Promise<T> {
        throw new Error("Forced transaction failure for atomicity test");
      },
    } as any;
    await assert.rejects(
      () =>
        runHealthRequestExam(
          {
            auth: {uid: testCaller.uid},
            data: {
              dogId: "dog-1",
              caseId: "case-proj-1",
              title: "Exame Falho",
              examType: "blood_work",
              operationId: "op-proj-fail",
            },
          } as any,
          depsFor({db: failingDb}),
        ),
      /Forced transaction failure for atomicity test/,
    );
    let caseAfterFail = db._store.get(casePath)!;
    assert.strictEqual(caseAfterFail["event_count"], 7, "event_count untouched on transaction failure");
    assert.strictEqual(caseAfterFail["revision"], 7, "revision untouched on transaction failure");

    console.log("✓ ClinicalCase derived event projections, idempotency, cancellation & atomicity passed");
  }

  console.log("\nALL 14 ExamProcess backend test groups passed successfully!");
}

runTests().catch((err) => {
  console.error("Test failure:", err);
  process.exit(1);
});
