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
  const allow = (flag: boolean | undefined, cap: string) => {
    if (flag === false) {
      const error = new Error(`Perfil sem permissão para health.${cap}`);
      (error as any).code = "permission-denied";
      throw error;
    }
    return Promise.resolve(testCaller);
  };
  return {
    db: options.db,
    requireRequestExam: () => allow(options.allowRequest, "request_exam"),
    requireRecordClinical: () => allow(options.allowRecord, "record_clinical"),
    requireInterpretExam: () => allow(options.allowInterpret, "interpret_exam"),
    requireManageClinicalCase: () => allow(options.allowManage, "manage_clinical_case"),
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
    assert.strictEqual(schedSnap["status"], "scheduled");

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
    assert.strictEqual(evtSnap["event_type"], "exam_collection");

    console.log("✓ Record Collection: happy path passed");
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
    assert.strictEqual(schedSnap!["status"], "completed");

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
    assert.strictEqual(schedSnap!["status"], "cancelled");

    console.log("✓ Cancel Exam: happy path and schedule cancellation passed");
  }

  console.log("\nALL 6 ExamProcess backend test groups passed successfully!");
}

runTests().catch((err) => {
  console.error("Test failure:", err);
  process.exit(1);
});
