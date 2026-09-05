/**
 * Testes unitários dos callables de ciclo clínico de Exames (F20.EXAM-V1).
 * Executado via node assert.
 */
import * as assert from "assert";
import * as fs from "fs";
import * as path from "path";
import {
  EXAM_REQUEST_KIND,
  EXAM_REQUEST_OPERATION,
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
          pending.set(ref.path, {...prev, ...data});
        },
        update(ref: {path: string}, data: JsonMap) {
          const prev = pending.get(ref.path) ?? store.get(ref.path) ?? {};
          pending.set(ref.path, {...prev, ...data});
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

/**
 * Independent per-group registration (CLINICAL-BE.MERGE-I1 §20).
 *
 * The suite previously ran as one monolithic async function: the first failing
 * assertion aborted every later group, so a single regression hid all subsequent
 * results. Each group now runs isolated and reports its own verdict, matching the
 * runner convention already used by clinical_case_callables_test.ts and the other
 * functions/src/*_test.ts suites (these are executed as
 * `node lib/<name>_test.js`, not via `node --test`).
 */
const groupFailures: Array<{name: string; error: string}> = [];

async function group(name: string, fn: () => Promise<void>): Promise<void> {
  try {
    await fn();
    console.log(`ok   ${name}`);
  } catch (err) {
    groupFailures.push({name, error: (err as Error).message});
    console.error(`FAIL ${name}: ${(err as Error).message}`);
  }
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

  await group("1. REQUEST EXAM", async () => {
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
          expectedCaseRevision: 1,
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
          expectedCaseRevision: 1,
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

  });

  await group("2. RECORD COLLECTION", async () => {
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
          expectedCaseRevision: 1,
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
          expectedCaseRevision: 1,
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

  });

  await group("3. RECORD RESULT", async () => {
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
          expectedCaseRevision: 1,
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
          expectedCaseRevision: 1,
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
          expectedCaseRevision: 1,
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

  });

  await group("4. RECORD INTERPRETATION", async () => {
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
          expectedCaseRevision: 1,
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
          expectedCaseRevision: 1,
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
          expectedCaseRevision: 1,
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
          expectedCaseRevision: 1,
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

  });

  await group("5. ASSESS OPERATIONAL IMPACT", async () => {
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
          expectedCaseRevision: 1,
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
          expectedCaseRevision: 1,
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
          expectedCaseRevision: 1,
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
          expectedCaseRevision: 1,
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

  });

  await group("6. CANCEL EXAM", async () => {
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
          expectedCaseRevision: 1,
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
          expectedCaseRevision: 1,
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

  });

  await group("7. REQUEST NEGATIVES & EDGE CASES", async () => {
    const db = createFakeDb({
      "dogs/dog-1": dogDoc,
      "dogs/dog-1/clinical_cases/case-1": caseDoc,
    });

    // 7.1 Unauthenticated
    await assert.rejects(
      () =>
        runHealthRequestExam(
          {auth: null, data: {dogId: "dog-1", caseId: "case-1", expectedCaseRevision: 1, title: "Raio-X", examType: "imaging", operationId: "op-7-1"}} as any,
          depsFor({db}),
        ),
      (err: any) => err.code === "unauthenticated",
    );

    // 7.2 Missing capability
    await assert.rejects(
      () =>
        runHealthRequestExam(
          {auth: {uid: testCaller.uid}, data: {dogId: "dog-1", caseId: "case-1", expectedCaseRevision: 1, title: "Raio-X", examType: "imaging", operationId: "op-7-2"}} as any,
          depsFor({db, allowRequest: false}),
        ),
      (err: any) => err.code === "permission-denied",
    );

    // 7.3 Inaccessible dog
    await assert.rejects(
      () =>
        runHealthRequestExam(
          {auth: {uid: testCaller.uid}, data: {dogId: "dog-1", caseId: "case-1", expectedCaseRevision: 1, title: "Raio-X", examType: "imaging", operationId: "op-7-3"}} as any,
          depsFor({db, dogAccess: false}),
        ),
      (err: any) => err.code === "permission-denied",
    );

    // 7.4 Nonexistent case
    await assert.rejects(
      () =>
        runHealthRequestExam(
          {auth: {uid: testCaller.uid}, data: {dogId: "dog-1", caseId: "case-inexistente", expectedCaseRevision: 1, title: "Raio-X", examType: "imaging", operationId: "op-7-4"}} as any,
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
          {auth: {uid: testCaller.uid}, data: {dogId: "dog-1", caseId: "case-term", expectedCaseRevision: 2, title: "Raio-X", examType: "imaging", operationId: "op-7-5"}} as any,
          depsFor({db: dbTerminal}),
        ),
      (err: any) => err.code === "failed-precondition",
    );

    // 7.6 Malformed exam type
    await assert.rejects(
      () =>
        runHealthRequestExam(
          {auth: {uid: testCaller.uid}, data: {dogId: "dog-1", caseId: "case-1", expectedCaseRevision: 1, title: "Raio-X", examType: "magic_type", operationId: "op-7-6"}} as any,
          depsFor({db}),
        ),
      (err: any) => err.code === "invalid-argument",
    );

    // 7.7 Idempotency conflict: same opId with different title
    const resReq = await runHealthRequestExam(
      {auth: {uid: testCaller.uid}, data: {dogId: "dog-1", caseId: "case-1", expectedCaseRevision: 1, title: "Bioquímico", examType: "blood_work", operationId: "op-7-7"}} as any,
      depsFor({db}),
    );
    assert.strictEqual(resReq["success"], true);

    await assert.rejects(
      () =>
        runHealthRequestExam(
          {auth: {uid: testCaller.uid}, data: {dogId: "dog-1", caseId: "case-1", expectedCaseRevision: 1, title: "Outro Titulo Conflitante", examType: "blood_work", operationId: "op-7-7"}} as any,
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
      {auth: {uid: testCaller.uid}, data: {dogId: "dog-1", caseId: "case-treat", expectedCaseRevision: 2, title: "Controle", examType: "blood_work", operationId: "op-7-8"}} as any,
      depsFor({db: dbTreatment}),
    );
    assert.strictEqual(dbTreatment._store.get("dogs/dog-1/clinical_cases/case-treat")!["clinical_status"], "under_treatment");

    // 7.9 Actor spoofing: a client-supplied `recordedBy` is now REJECTED at the
    // boundary (§14.7), not silently ignored. Loud rejection is stronger: a
    // caller that believes it can set authorship is corrected instead of having
    // the field dropped and assuming it was stored.
    const dbSpoof = createFakeDb({
      "dogs/dog-1": dogDoc,
      "dogs/dog-1/clinical_cases/case-1": caseDoc,
    });
    await assert.rejects(
      () =>
        runHealthRequestExam(
          {auth: {uid: testCaller.uid}, data: {dogId: "dog-1", caseId: "case-1", expectedCaseRevision: 1, title: "Teste Spoof", examType: "blood_work", recordedBy: {uid: "impostor"}, operationId: "op-7-9"}} as any,
          depsFor({db: dbSpoof}),
        ),
      (err: any) => err.code === "invalid-argument",
    );
    // Zero writes: the spoof never reached the aggregate.
    assert.strictEqual(dbSpoof._store.size, 2, "7.9 payload rejeitado não pode escrever nada");

    // 7.10 Authorship remains server-derived on a clean payload.
    const dbActor = createFakeDb({
      "dogs/dog-1": dogDoc,
      "dogs/dog-1/clinical_cases/case-1": caseDoc,
    });
    const resActor = await runHealthRequestExam(
      {auth: {uid: testCaller.uid}, data: {dogId: "dog-1", caseId: "case-1", expectedCaseRevision: 1, title: "Teste Autoria", examType: "blood_work", operationId: "op-7-10"}} as any,
      depsFor({db: dbActor}),
    );
    const examActor = dbActor._store.get(`dogs/dog-1/clinical_cases/case-1/exams/${resActor["examId"]}`);
    assert.strictEqual((examActor!["recorded_by"] as any)["uid"], testCaller.uid);

  });

  await group("8. COLLECTION NEGATIVES & EDGE CASES", async () => {
    const db = createFakeDb({
      "dogs/dog-1": dogDoc,
      "dogs/dog-1/clinical_cases/case-1": caseDoc,
    });
    const deps = depsFor({db});

    const resReq = await runHealthRequestExam(
      {auth: {uid: testCaller.uid}, data: {dogId: "dog-1", caseId: "case-1", expectedCaseRevision: 1, title: "Hemograma", examType: "blood_work", operationId: "op-req-8"}} as any,
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

  });

  await group("9. RESULT NEGATIVES & INDEPENDENCE", async () => {
    const db = createFakeDb({
      "dogs/dog-1": dogDoc,
      "dogs/dog-1/clinical_cases/case-1": caseDoc,
    });
    const deps = depsFor({db});

    const resReq = await runHealthRequestExam(
      {auth: {uid: testCaller.uid}, data: {dogId: "dog-1", caseId: "case-1", expectedCaseRevision: 1, title: "Urina", examType: "urinalysis", operationId: "op-req-9"}} as any,
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

  });

  await group("10. INTERPRETATION NEGATIVES & PROFESSIONAL IDENTITY", async () => {
    const db = createFakeDb({
      "dogs/dog-1": dogDoc,
      "dogs/dog-1/clinical_cases/case-1": caseDoc,
    });
    const deps = depsFor({db});

    const resReq = await runHealthRequestExam(
      {auth: {uid: testCaller.uid}, data: {dogId: "dog-1", caseId: "case-1", expectedCaseRevision: 1, title: "Raio-X", examType: "imaging", operationId: "op-req-10"}} as any,
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

  });

  await group("11. IMPACT NEGATIVES & INDEPENDENCE", async () => {
    const db = createFakeDb({
      "dogs/dog-1": dogDoc,
      "dogs/dog-1/clinical_cases/case-1": caseDoc,
    });
    const deps = depsFor({db});

    const resReq = await runHealthRequestExam(
      {auth: {uid: testCaller.uid}, data: {dogId: "dog-1", caseId: "case-1", expectedCaseRevision: 1, title: "Cardio", examType: "cardiology", operationId: "op-req-11"}} as any,
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

  });

  await group("12. CANCEL NEGATIVES & TERMINAL STATE", async () => {
    const db = createFakeDb({
      "dogs/dog-1": dogDoc,
      "dogs/dog-1/clinical_cases/case-1": caseDoc,
    });
    const deps = depsFor({db});

    const resReq = await runHealthRequestExam(
      {auth: {uid: testCaller.uid}, data: {dogId: "dog-1", caseId: "case-1", expectedCaseRevision: 1, title: "Citologia", examType: "biopsy", operationId: "op-req-12"}} as any,
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

  });

  await group("13. TRANSACTIONAL ATOMICITY (ALL-OR-NOTHING)", async () => {
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
          {auth: {uid: testCaller.uid}, data: {dogId: "dog-1", caseId: "case-1", expectedCaseRevision: 1, title: "Hemograma", examType: "blood_work", operationId: "op-crash"}} as any,
          depsFor({db: failingDb}),
        ),
      /Simulated Firestore transaction network crash/,
    );

    // Prove zero partial writes occurred
    assert.strictEqual(db._store.size, 2, "No partial documents written to store on transaction failure");
    assert.ok(!db._store.has("dogs/dog-1/clinical_cases/case-1/exams/exam_crash"));

    console.log("✓ Transactional safety: failure leaves database completely untouched (all-or-nothing) passed");
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // PERMANENT KILLERS — CLINICAL-BE.MERGE-I1 §22
  //
  // Each of these proves a contract that regressed, or could silently regress,
  // when a specialized aggregate owns ClinicalCase state. They are not happy-path
  // coverage: every one of them fails on the pre-convergence Exam writer.
  // ═══════════════════════════════════════════════════════════════════════════

  await group("K1. expectedCaseRevision é OBRIGATÓRIO", async () => {
    const db = createFakeDb({
      "dogs/dog-1": dogDoc,
      "dogs/dog-1/clinical_cases/case-1": caseDoc,
    });
    await assert.rejects(
      () =>
        runHealthRequestExam(
          {auth: {uid: testCaller.uid}, data: {dogId: "dog-1", caseId: "case-1", title: "Sem OCC", examType: "blood_work", operationId: "op-k1"}} as any,
          depsFor({db}),
        ),
      (err: any) => err.code === "invalid-argument",
      "ausência de expectedCaseRevision deve ser invalid-argument",
    );
    assert.strictEqual(db._store.size, 2, "K1 não pode escrever nada");

    // Valor presente mas inválido também é rejeitado (inteiro seguro >= 1).
    for (const bad of [0, -1, 1.5, "1", null]) {
      await assert.rejects(
        () =>
          runHealthRequestExam(
            {auth: {uid: testCaller.uid}, data: {dogId: "dog-1", caseId: "case-1", expectedCaseRevision: bad, title: "OCC inválido", examType: "blood_work", operationId: `op-k1-${String(bad)}`}} as any,
            depsFor({db}),
          ),
        (err: any) => err.code === "invalid-argument",
        `expectedCaseRevision inválido (${String(bad)}) deve ser invalid-argument`,
      );
    }
    assert.strictEqual(db._store.size, 2, "K1 valores inválidos não podem escrever nada");
  });

  await group("K2. caso armazenado sem revision falha FECHADO (corrupção)", async () => {
    const db = createFakeDb({
      "dogs/dog-1": dogDoc,
      // Sem `revision`: F1.C1 trata ausência como CORRUPÇÃO, nunca default 1.
      "dogs/dog-1/clinical_cases/case-norev": {id: "case-norev", dog_id: "dog-1", clinical_status: "open"},
    });
    await assert.rejects(
      () =>
        runHealthRequestExam(
          {auth: {uid: testCaller.uid}, data: {dogId: "dog-1", caseId: "case-norev", expectedCaseRevision: 1, title: "Corrompido", examType: "blood_work", operationId: "op-k2"}} as any,
          depsFor({db}),
        ),
      (err: any) => err.code === "failed-precondition",
      "caso sem revision deve falhar fechado",
    );
    assert.strictEqual(db._store.size, 2, "K2 não pode escrever nada");
    assert.strictEqual(
      db._store.get("dogs/dog-1/clinical_cases/case-norev")!["revision"],
      undefined,
      "K2 não pode materializar uma revision inexistente",
    );
  });

  await group("K3. expectedCaseRevision divergente => rejeição OCC", async () => {
    const db = createFakeDb({
      "dogs/dog-1": dogDoc,
      "dogs/dog-1/clinical_cases/case-1": caseDoc,
    });
    await assert.rejects(
      () =>
        runHealthRequestExam(
          {auth: {uid: testCaller.uid}, data: {dogId: "dog-1", caseId: "case-1", expectedCaseRevision: 99, title: "Stale", examType: "blood_work", operationId: "op-k3"}} as any,
          depsFor({db}),
        ),
      (err: any) => err.code === "failed-precondition",
      "revision esperada != armazenada deve ser rejeição OCC",
    );
    assert.strictEqual(db._store.size, 2, "K3 não pode escrever nada");
    assert.strictEqual(
      db._store.get("dogs/dog-1/clinical_cases/case-1")!["clinical_status"],
      "open",
      "K3 não pode transicionar o caso",
    );
  });

  await group("K4/K5. replay ANTES do stale e fingerprint sem expectedCaseRevision", async () => {
    const db = createFakeDb({
      "dogs/dog-1": dogDoc,
      "dogs/dog-1/clinical_cases/case-1": caseDoc,
    });
    const payload = {dogId: "dog-1", caseId: "case-1", title: "Hemograma K4", examType: "blood_work", operationId: "op-k4"};
    const first = await runHealthRequestExam(
      {auth: {uid: testCaller.uid}, data: {...payload, expectedCaseRevision: 1}} as any,
      depsFor({db}),
    );
    // O caso avançou para revision 2, logo o token 1 do chamador está OBSOLETO.
    assert.strictEqual(db._store.get("dogs/dog-1/clinical_cases/case-1")!["revision"], 2);

    // K4: replay com token AGORA obsoleto ainda é replay — nunca erro de stale.
    const replayStale = await runHealthRequestExam(
      {auth: {uid: testCaller.uid}, data: {...payload, expectedCaseRevision: 1}} as any,
      depsFor({db}),
    );
    assert.deepStrictEqual(replayStale, first, "K4 replay deve ser resolvido antes do stale");

    // K5: replay com token DIFERENTE porém válido também é replay, o que prova
    // que expectedCaseRevision não entra no fingerprint de intenção.
    const replayFresh = await runHealthRequestExam(
      {auth: {uid: testCaller.uid}, data: {...payload, expectedCaseRevision: 2}} as any,
      depsFor({db}),
    );
    assert.deepStrictEqual(replayFresh, first, "K5 expectedCaseRevision não pode alterar o fingerprint");

    // Nenhum dos replays duplicou fato clínico nem avançou revision.
    assert.strictEqual(db._store.get("dogs/dog-1/clinical_cases/case-1")!["revision"], 2, "replays não incrementam revision");
    const exams = [...db._store.keys()].filter((k) => k.includes("/exams/"));
    const events = [...db._store.keys()].filter((k) => k.includes("/clinical_events/"));
    assert.strictEqual(exams.length, 1, "replay não pode duplicar exame");
    assert.strictEqual(events.length, 1, "replay não pode duplicar ClinicalEvent");
  });

  await group("K6/K7. transição open->under_investigation via autoridade única, +1 exato", async () => {
    const db = createFakeDb({
      "dogs/dog-1": dogDoc,
      "dogs/dog-1/clinical_cases/case-1": caseDoc,
    });
    await runHealthRequestExam(
      {auth: {uid: testCaller.uid}, data: {dogId: "dog-1", caseId: "case-1", expectedCaseRevision: 1, title: "Hemograma K6", examType: "blood_work", operationId: "op-k6"}} as any,
      depsFor({db}),
    );
    const c = db._store.get("dogs/dog-1/clinical_cases/case-1")!;
    assert.strictEqual(c["clinical_status"], "under_investigation", "K6 destino canônico");
    assert.strictEqual(c["revision"], 2, "K6 revision incrementa EXATAMENTE uma vez");
    assert.ok(c["updated_at"], "K6 updated_at é metadado temporal atualizado");
    // Campos de fechamento/reabertura NÃO são tocados por uma transição de exame.
    for (const f of ["closed_at", "closed_by", "closure_type", "closure_reason", "reopened_at"]) {
      assert.strictEqual(c[f], undefined, `K6 transição não pode escrever ${f}`);
    }

    // Um segundo exame no MESMO caso (já under_investigation) não re-transiciona.
    await runHealthRequestExam(
      {auth: {uid: testCaller.uid}, data: {dogId: "dog-1", caseId: "case-1", expectedCaseRevision: 2, title: "Segundo K6", examType: "imaging", operationId: "op-k6-b"}} as any,
      depsFor({db}),
    );
    const c2 = db._store.get("dogs/dog-1/clinical_cases/case-1")!;
    assert.strictEqual(c2["clinical_status"], "under_investigation");
    assert.strictEqual(c2["revision"], 2, "sem mutação de status => sem incremento de revision");

    // K7: o writer de Exame NÃO tem caminho próprio de transição. Uma asserção
    // comportamental não prova ausência de código; o texto-fonte prova.
    const src = fs.readFileSync(
      path.join(__dirname, "..", "src", "exam_process_callables.ts"),
      "utf8",
    );
    assert.ok(
      src.includes("applyClinicalCaseTransition"),
      "K7 Exame deve delegar à autoridade de ciclo de vida",
    );
    assert.ok(
      !src.includes("clinical_status: \""),
      "K7 Exame não pode atribuir clinical_status diretamente",
    );
    // Escopo desta asserção: a revision do CLINICAL CASE. Os fallbacks `: 1`
    // remanescentes em examData/schedData pertencem a OUTROS agregados
    // (ExamProcess e HealthScheduleItem), fora do contrato OCC clínico congelado
    // — Schedule inclusive tolera revision ausente por decisão própria. Endurecê-los
    // é gate futuro, não escopo desta convergência.
    assert.ok(
      !/caseData\["revision"\]/.test(src),
      "K7 Exame não pode ler a revision do ClinicalCase diretamente",
    );
    assert.ok(
      !/revision"\]\s*(\?\?|\|\|)\s*1/.test(src),
      "K7 Exame não pode usar `[\"revision\"] ?? 1` como fallback",
    );
    assert.ok(
      src.includes("assertClinicalCasePrecondition"),
      "K7 a precondição do caso deve vir da autoridade clínica",
    );
  });

  await group("K8. operationId reusado por OUTRO ator => idempotency conflict", async () => {
    const db = createFakeDb({
      "dogs/dog-1": dogDoc,
      "dogs/dog-1/clinical_cases/case-1": caseDoc,
    });
    const payload = {dogId: "dog-1", caseId: "case-1", expectedCaseRevision: 1, title: "Hemograma K8", examType: "blood_work", operationId: "op-k8"};
    await runHealthRequestExam(
      {auth: {uid: testCaller.uid}, data: payload} as any,
      depsFor({db}),
    );

    // MESMA intenção, MESMO operationId, ator DIFERENTE. Sem a checagem de
    // actor_uid isto seria lido como replay e devolveria o resultado alheio.
    const otherCaller: ExamCaller = {
      uid: "uid-outro",
      email: "outro@gcm.com.br",
      ra: "654321",
      name: "GCM Outro",
    };
    const otherDeps: ExamProcessCallableDeps = {
      ...depsFor({db}),
      requireRequestExam: () => Promise.resolve(otherCaller),
    };
    await assert.rejects(
      () =>
        runHealthRequestExam(
          {auth: {uid: otherCaller.uid}, data: {...payload, expectedCaseRevision: 2}} as any,
          otherDeps,
        ),
      (err: any) => err.code === "failed-precondition",
      "K8 reuso de operationId por outro ator deve ser conflito",
    );
    const exams = [...db._store.keys()].filter((k) => k.includes("/exams/"));
    assert.strictEqual(exams.length, 1, "K8 não pode criar um segundo exame");
  });

  await group("K9. operationId reusado com OUTRO operation_type => falha fechada", async () => {
    const db = createFakeDb({
      "dogs/dog-1": dogDoc,
      "dogs/dog-1/clinical_cases/case-1": caseDoc,
      // Receipt canônico de OUTRA operação ocupando o mesmo operationId.
      "dogs/dog-1/clinical_cases/case-1/operations/op-k9": {
        kind: "exam_collection_v1",
        operation_id: "op-k9",
        operation_type: "record_exam_collection",
        actor_uid: testCaller.uid,
        fingerprint: "qualquer",
        result: {success: true},
      },
    });
    await assert.rejects(
      () =>
        runHealthRequestExam(
          {auth: {uid: testCaller.uid}, data: {dogId: "dog-1", caseId: "case-1", expectedCaseRevision: 1, title: "Hemograma K9", examType: "blood_work", operationId: "op-k9"}} as any,
          depsFor({db}),
        ),
      (err: any) => err.code === "failed-precondition",
      "K9 receipt de operation_type incompatível deve falhar fechado",
    );
    const exams = [...db._store.keys()].filter((k) => k.includes("/exams/"));
    assert.strictEqual(exams.length, 0, "K9 não pode criar exame");
    assert.strictEqual(
      db._store.get("dogs/dog-1/clinical_cases/case-1")!["clinical_status"],
      "open",
      "K9 não pode transicionar o caso",
    );
  });

  await group("K10. caso TERMINAL não aceita novo exame", async () => {
    for (const terminal of ["discharged", "cancelled"]) {
      const db = createFakeDb({
        "dogs/dog-1": dogDoc,
        "dogs/dog-1/clinical_cases/case-t": {id: "case-t", dog_id: "dog-1", clinical_status: terminal, revision: 3},
      });
      await assert.rejects(
        () =>
          runHealthRequestExam(
            {auth: {uid: testCaller.uid}, data: {dogId: "dog-1", caseId: "case-t", expectedCaseRevision: 3, title: `Exame em ${terminal}`, examType: "blood_work", operationId: `op-k10-${terminal}`}} as any,
            depsFor({db}),
          ),
        (err: any) => err.code === "failed-precondition",
        `K10 caso ${terminal} deve recusar novo exame`,
      );
      assert.strictEqual(db._store.size, 2, `K10 ${terminal} não pode escrever nada`);
      assert.strictEqual(
        db._store.get("dogs/dog-1/clinical_cases/case-t")!["clinical_status"],
        terminal,
        `K10 ${terminal} não pode ser reativado por um exame`,
      );
      assert.strictEqual(
        db._store.get("dogs/dog-1/clinical_cases/case-t")!["revision"],
        3,
        `K10 ${terminal} não pode incrementar revision`,
      );
    }
  });

  await group("K11. receipt de Exame usa a forma canônica clínica", async () => {
    const db = createFakeDb({
      "dogs/dog-1": dogDoc,
      "dogs/dog-1/clinical_cases/case-1": caseDoc,
    });
    await runHealthRequestExam(
      {auth: {uid: testCaller.uid}, data: {dogId: "dog-1", caseId: "case-1", expectedCaseRevision: 1, title: "Hemograma K11", examType: "blood_work", operationId: "op-k11"}} as any,
      depsFor({db}),
    );
    const receipt = db._store.get("dogs/dog-1/clinical_cases/case-1/operations/op-k11")!;
    assert.ok(receipt, "K11 receipt deve existir");
    assert.strictEqual(receipt["kind"], EXAM_REQUEST_KIND);
    assert.strictEqual(receipt["operation_type"], EXAM_REQUEST_OPERATION);
    assert.strictEqual(receipt["operation_id"], "op-k11");
    assert.strictEqual(receipt["actor_uid"], testCaller.uid, "K11 receipt precisa carregar actor_uid");
    assert.ok(receipt["fingerprint"], "K11 receipt precisa carregar fingerprint");
    assert.ok(receipt["result"], "K11 receipt precisa carregar result");
  });
}

runTests()
  .then(() => {
    if (groupFailures.length > 0) {
      console.error(`\n${groupFailures.length} grupo(s) de teste falharam.`);
      process.exit(1);
    }
    console.log("\nTodos os grupos de teste do ExamProcess passaram.");
  })
  .catch((err) => {
    console.error("Test harness failure:", err);
    process.exit(1);
  });
