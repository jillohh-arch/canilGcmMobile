/**
 * HEALTH-V1-OP-AUTH — testes do mutation owner autoritativo.
 *
 * O guard puro já é coberto por `shift_restriction_guard_test.ts`. Aqui o que
 * está sob teste é o COMANDO: que uma negativa não produz NENHUM write, que a
 * autorização acontece dentro da mesma transação da mutação, que o shape dos
 * documentos preserva o contrato atual de Turnos, que o fan-out de guarnição
 * sobrevive à migração e que retry é idempotente.
 *
 * Stage HEALTH-V1-OP-AUTH — implementação local. Não deployado.
 */
import * as assert from "assert";
import {RawQuery} from "./health_readiness_evidence_logic";
import {
  fingerprintCommand,
  JsonMap,
  runShiftAuthorizedCommand,
  ShiftActor,
  ShiftAuthorizationError,
  ShiftCommandInput,
  ShiftEngineDeps,
  ShiftTxDocSnap,
  ShiftTxn,
} from "./shift_authorization_engine";

const NOW = new Date("2026-08-13T12:00:00.000Z");
const MILLIS_PER_DAY = 86_400_000;

const ACTOR: ShiftActor = {
  uid: "uid-123",
  ra: "998877",
  email: "998877@gcm.com.br",
  name: "Condutor Teste",
};

function timestamp(date: Date): {toDate: () => Date} {
  return {toDate: () => date};
}

function daysAgo(days: number): {toDate: () => Date} {
  return timestamp(new Date(NOW.getTime() - days * MILLIS_PER_DAY));
}

interface WriteRecord {
  readonly path: string;
  readonly data: JsonMap;
  readonly merge: boolean;
}

/**
 * Firestore falso mínimo. Registra writes sem aplicá-los, para que um teste
 * possa afirmar "nenhuma mutação ocorreu" com precisão de caminho.
 */
class FakeStore {
  readonly writes: WriteRecord[] = [];
  readonly docs = new Map<string, JsonMap>();
  readonly collections = new Map<string, RawQuery>();
  /** Ordem real das operações, para provar que o guard precede os writes. */
  readonly ops: string[] = [];
  transactionAttempts = 0;
  private idCounter = 0;

  setDoc(path: string, data: JsonMap): void {
    this.docs.set(path, data);
  }

  setCollection(path: string, query: RawQuery): void {
    this.collections.set(path, query);
  }

  deps(): ShiftEngineDeps {
    const store = this;
    return {
      runTransaction: async <T>(fn: (txn: ShiftTxn) => Promise<T>): Promise<T> => {
        store.transactionAttempts += 1;
        const txn: ShiftTxn = {
          get: async (path: string): Promise<ShiftTxDocSnap> => {
            store.ops.push(`get:${path}`);
            const data = store.docs.get(path);
            return {exists: data !== undefined, data};
          },
          getCollection: async (path: string): Promise<RawQuery> => {
            store.ops.push(`getCollection:${path}`);
            return store.collections.get(path) ?? {kind: "docs", docs: []};
          },
          set: (path: string, data: JsonMap, options?: {merge?: boolean}) => {
            store.ops.push(`set:${path}`);
            store.writes.push({path, data, merge: options?.merge === true});
          },
        };
        return fn(txn);
      },
      createEntityId: () => `generated-${++store.idCounter}`,
      serverTimestamp: () => "__serverTimestamp__",
      timestampFromDate: (d: Date) => timestamp(d),
      arrayUnion: (...items: unknown[]) => ({__arrayUnion__: items}),
      deleteField: () => "__delete__",
      activeCrewMemberRas: async () => store.crewRas,
      activeShiftVehicleId: async () => store.vehicleId,
    };
  }

  crewRas: readonly string[] = [];
  vehicleId: string | null = null;

  /** Writes que tocam um documento operacional de turno. */
  operationalWrites(): readonly WriteRecord[] {
    return this.writes.filter(
      (write) =>
        write.path.startsWith("active_shifts/") ||
        write.path.startsWith("shift_logs/") ||
        write.path.startsWith("vehicle_crews/"),
    );
  }

  writeAt(path: string): WriteRecord | undefined {
    return this.writes.find((write) => write.path === path);
  }
}

function restrictionDocs(
  ...list: readonly Record<string, unknown>[]
): RawQuery {
  return {
    kind: "docs",
    docs: list.map((data, index) => ({
      id: (data.__id as string) ?? `r${index + 1}`,
      data: {
        status: "active",
        level: "attention",
        description: "Restrição registrada.",
        category: "injury",
        activities_restricted: [],
        issued_at: daysAgo(2),
        ...data,
      },
    })),
  };
}

function storeWithActiveShift(dogId = "dog-old"): FakeStore {
  const store = new FakeStore();
  store.setDoc("dogs/dog-1", {name: "Bono"});
  store.setDoc("active_shifts/998877", {
    shiftId: "shift-1",
    handlerId: ACTOR.ra,
    status: "active",
    service_dog_id: dogId,
    dogId,
    vehicle_id: "VTR-01",
    vehicle_crew_id: "VTR-01",
  });
  return store;
}

function baseInput(overrides: Partial<ShiftCommandInput> = {}): ShiftCommandInput {
  return {
    action: "start_shift",
    dogId: "dog-1",
    operationId: "op-1",
    startedAt: NOW,
    ...overrides,
  };
}

async function expectError(
  fn: () => Promise<unknown>,
): Promise<ShiftAuthorizationError> {
  try {
    await fn();
  } catch (error) {
    assert.ok(
      error instanceof ShiftAuthorizationError,
      `esperava ShiftAuthorizationError, recebi ${String(error)}`,
    );
    return error as ShiftAuthorizationError;
  }
  throw new assert.AssertionError({message: "esperava erro, não houve"});
}

let failed = 0;

async function test(name: string, fn: () => void | Promise<void>): Promise<void> {
  try {
    await fn();
    console.log(`ok - ${name}`);
  } catch (error) {
    failed += 1;
    console.error(`FAIL - ${name}`);
    console.error(error);
  }
}

async function main(): Promise<void> {
  // ── Autorização permitida ─────────────────────────────────────────────────
  await test("start_shift sem restrição escreve shift_logs + active_shifts", async () => {
    const store = new FakeStore();
    store.setDoc("dogs/dog-1", {name: "Bono"});

    const result = await runShiftAuthorizedCommand(
      store.deps(),
      ACTOR,
      baseInput(),
      NOW,
    );

    assert.strictEqual(result.decision, "allowed");
    assert.strictEqual(result.wasNoOp, false);
    const active = store.writeAt("active_shifts/998877");
    assert.ok(active, "active_shifts deve ser escrito");
    assert.strictEqual(active.data.dogId, "dog-1");
    assert.strictEqual(active.data.service_dog_id, "dog-1");
    assert.strictEqual(active.data.status, "active");
    assert.strictEqual(active.data.handlerId, ACTOR.ra);
    // Contrato preservado: active_shifts/shift_logs NÃO levam `name`.
    assert.strictEqual(active.data.name, undefined);
    assert.strictEqual(active.data.auth_uid, ACTOR.uid);

    const log = store.writes.find((w) => w.path.startsWith("shift_logs/"));
    assert.ok(log, "shift_logs deve ser escrito");
    assert.strictEqual(log.data.initialDogId, "dog-1");
    assert.strictEqual(log.data.currentDogId, "dog-1");
    assert.strictEqual(log.data.endedAt, null);
    assert.deepStrictEqual(log.data.dogSwitches, []);
  });

  await test("start_shift grava auditoria no owner canônico auditLogs", async () => {
    const store = new FakeStore();
    store.setDoc("dogs/dog-1", {name: "Bono"});

    await runShiftAuthorizedCommand(store.deps(), ACTOR, baseInput(), NOW);

    const audit = store.writes.find((w) => w.path.startsWith("auditLogs/"));
    assert.ok(audit, "auditoria deve existir");
    assert.strictEqual(audit.data.action, "shift_start_shift");
    assert.strictEqual(audit.data.source, "functions");
    const metadata = audit.data.metadata as JsonMap;
    assert.strictEqual(metadata.dog_id, "dog-1");
    assert.strictEqual(metadata.guard_decision, "allowed");
    // Registro explícito de qual coleção autorizou.
    assert.strictEqual(metadata.authority, "operational_restrictions");
  });

  // ── ABSOLUTE bloqueia e NÃO escreve ───────────────────────────────────────
  await test("S-05 absolute ativa bloqueia start_shift sem NENHUM write operacional", async () => {
    const store = new FakeStore();
    store.setDoc("dogs/dog-1", {name: "Bono"});
    store.setCollection(
      "dogs/dog-1/operational_restrictions",
      restrictionDocs({level: "absolute"}),
    );

    const error = await expectError(() =>
      runShiftAuthorizedCommand(store.deps(), ACTOR, baseInput(), NOW),
    );

    assert.strictEqual(error.appCode, "absolute_restriction_active");
    assert.strictEqual(error.httpCode, "failed-precondition");
    assert.deepStrictEqual(store.operationalWrites(), []);
    // Nem receipt: uma operação negada não consome o operationId.
    assert.deepStrictEqual(store.writes, []);
  });

  await test("absolute bloqueia switch_dog e não altera nenhum membro da guarnição", async () => {
    const store = storeWithActiveShift();
    store.vehicleId = "VTR-01";
    store.crewRas = ["111111", "222222"];
    store.setCollection(
      "dogs/dog-1/operational_restrictions",
      restrictionDocs({level: "absolute"}),
    );

    const error = await expectError(() =>
      runShiftAuthorizedCommand(
        store.deps(),
        ACTOR,
        baseInput({action: "switch_dog", operationId: "op-sw"}),
        NOW,
      ),
    );

    assert.strictEqual(error.appCode, "absolute_restriction_active");
    // SW-03: operação bloqueada não altera nenhum membro.
    assert.deepStrictEqual(store.operationalWrites(), []);
    assert.strictEqual(store.writeAt("active_shifts/111111"), undefined);
    assert.strictEqual(store.writeAt("active_shifts/222222"), undefined);
  });

  await test("absolute bloqueia assume_vehicle sem tocar a guarnição", async () => {
    const store = storeWithActiveShift("");
    store.setCollection(
      "dogs/dog-1/operational_restrictions",
      restrictionDocs({level: "absolute"}),
    );

    const error = await expectError(() =>
      runShiftAuthorizedCommand(
        store.deps(),
        ACTOR,
        baseInput({
          action: "assume_vehicle",
          operationId: "op-av",
          role: "k9",
          vehicle: {
            id: "VTR-02",
            label: "VTR 02",
            prefix: "02",
            modelName: "Hilux",
            unit: "GCM",
            crewSize: 2,
          },
        }),
        NOW,
      ),
    );

    assert.strictEqual(error.appCode, "absolute_restriction_active");
    assert.deepStrictEqual(store.operationalWrites(), []);
  });

  // ── Ordem: guard antes de qualquer write ──────────────────────────────────
  await test("guard lê restrições ANTES de qualquer set (sem TOCTOU)", async () => {
    const store = new FakeStore();
    store.setDoc("dogs/dog-1", {name: "Bono"});

    await runShiftAuthorizedCommand(store.deps(), ACTOR, baseInput(), NOW);

    const guardIndex = store.ops.indexOf(
      "getCollection:dogs/dog-1/operational_restrictions",
    );
    const firstSet = store.ops.findIndex((op) => op.startsWith("set:"));
    assert.ok(guardIndex >= 0, "guard deve consultar a coleção canônica");
    assert.ok(firstSet >= 0, "deve haver writes");
    assert.ok(
      guardIndex < firstSet,
      `guard (${guardIndex}) deve preceder o primeiro write (${firstSet})`,
    );
    // Autorização e mutação na MESMA transação.
    assert.strictEqual(store.transactionAttempts, 1);
  });

  // ── PARTIAL exige ciência ─────────────────────────────────────────────────
  await test("partial sem ciência não conclui a mutação", async () => {
    const store = new FakeStore();
    store.setDoc("dogs/dog-1", {name: "Bono"});
    store.setCollection(
      "dogs/dog-1/operational_restrictions",
      restrictionDocs({
        __id: "rp-1",
        level: "partial",
        activities_restricted: ["busca"],
      }),
    );

    const error = await expectError(() =>
      runShiftAuthorizedCommand(store.deps(), ACTOR, baseInput(), NOW),
    );

    assert.strictEqual(error.appCode, "partial_acknowledgement_required");
    assert.deepStrictEqual(store.operationalWrites(), []);
    // A UI recebe as restrições para poder exibir o alerta.
    const restrictions = error.details?.restrictions as JsonMap[];
    assert.strictEqual(restrictions.length, 1);
    assert.deepStrictEqual(error.details?.pendingAcknowledgementIds, ["rp-1"]);
  });

  await test("partial com ciência válida permite e audita o aceite", async () => {
    const store = new FakeStore();
    store.setDoc("dogs/dog-1", {name: "Bono"});
    store.setCollection(
      "dogs/dog-1/operational_restrictions",
      restrictionDocs({
        __id: "rp-1",
        level: "partial",
        activities_restricted: ["busca", "guarda"],
      }),
    );

    const result = await runShiftAuthorizedCommand(
      store.deps(),
      ACTOR,
      baseInput({acknowledgedRestrictionIds: ["rp-1"]}),
      NOW,
    );

    assert.strictEqual(result.decision, "allowed_with_restrictions");
    assert.strictEqual(result.acknowledgementRecorded, true);
    assert.ok(store.writeAt("active_shifts/998877"), "turno deve ser criado");

    const audit = store.writes.find((w) => w.path.startsWith("auditLogs/"));
    const metadata = audit?.data.metadata as JsonMap;
    assert.deepStrictEqual(metadata.partial_acknowledged, ["rp-1"]);
    assert.deepStrictEqual(metadata.active_restriction_ids, ["rp-1"]);
  });

  await test("ciência de outra restrição não libera a parcial vigente", async () => {
    // Aceite tem de cobrir as restrições ATUAIS; um id alheio não serve.
    const store = new FakeStore();
    store.setDoc("dogs/dog-1", {name: "Bono"});
    store.setCollection(
      "dogs/dog-1/operational_restrictions",
      restrictionDocs({
        __id: "rp-nova",
        level: "partial",
        activities_restricted: ["busca"],
      }),
    );

    const error = await expectError(() =>
      runShiftAuthorizedCommand(
        store.deps(),
        ACTOR,
        baseInput({acknowledgedRestrictionIds: ["rp-antiga"]}),
        NOW,
      ),
    );

    assert.strictEqual(error.appCode, "partial_acknowledgement_required");
    assert.deepStrictEqual(store.operationalWrites(), []);
  });

  await test("aceite NÃO escreve em operational_restrictions nem health_summary", async () => {
    const store = new FakeStore();
    store.setDoc("dogs/dog-1", {name: "Bono"});
    store.setCollection(
      "dogs/dog-1/operational_restrictions",
      restrictionDocs({
        __id: "rp-1",
        level: "partial",
        activities_restricted: ["busca"],
      }),
    );

    await runShiftAuthorizedCommand(
      store.deps(),
      ACTOR,
      baseInput({acknowledgedRestrictionIds: ["rp-1"]}),
      NOW,
    );

    // P-04 e P-05: ciência operacional não é override clínico.
    for (const write of store.writes) {
      assert.ok(
        !write.path.includes("operational_restrictions"),
        `aceite não pode escrever restrição: ${write.path}`,
      );
      assert.ok(
        !write.path.includes("health_summary"),
        `aceite não pode escrever summary: ${write.path}`,
      );
    }
  });

  // ── ATTENTION não bloqueia ────────────────────────────────────────────────
  await test("attention permite sem exigir ciência, e retorna aviso", async () => {
    const store = new FakeStore();
    store.setDoc("dogs/dog-1", {name: "Bono"});
    store.setCollection(
      "dogs/dog-1/operational_restrictions",
      restrictionDocs({__id: "ra-1", level: "attention"}),
    );

    const result = await runShiftAuthorizedCommand(
      store.deps(),
      ACTOR,
      baseInput(),
      NOW,
    );

    assert.strictEqual(result.decision, "allowed");
    assert.strictEqual(result.acknowledgementRecorded, false);
    assert.strictEqual(result.restrictions.length, 1);
    assert.ok(store.writeAt("active_shifts/998877"));
  });

  // ── ended / cancelled ─────────────────────────────────────────────────────
  await test("absolute ended e cancelled não bloqueiam", async () => {
    for (const status of ["ended", "cancelled"]) {
      const store = new FakeStore();
      store.setDoc("dogs/dog-1", {name: "Bono"});
      store.setCollection(
        "dogs/dog-1/operational_restrictions",
        restrictionDocs({level: "absolute", status}),
      );

      const result = await runShiftAuthorizedCommand(
        store.deps(),
        ACTOR,
        baseInput({operationId: `op-${status}`}),
        NOW,
      );
      assert.strictEqual(result.decision, "allowed", `status ${status}`);
      assert.ok(store.writeAt("active_shifts/998877"));
    }
  });

  await test("absolute active com expected_end vencido continua bloqueando", async () => {
    const store = new FakeStore();
    store.setDoc("dogs/dog-1", {name: "Bono"});
    store.setCollection(
      "dogs/dog-1/operational_restrictions",
      restrictionDocs({level: "absolute", expected_end: daysAgo(5)}),
    );

    const error = await expectError(() =>
      runShiftAuthorizedCommand(store.deps(), ACTOR, baseInput(), NOW),
    );
    assert.strictEqual(error.appCode, "absolute_restriction_active");
    assert.deepStrictEqual(store.operationalWrites(), []);
  });

  // ── FAIL CLOSED ───────────────────────────────────────────────────────────
  await test("F-04 falha de leitura das restrições NÃO vira lista vazia", async () => {
    const store = new FakeStore();
    store.setDoc("dogs/dog-1", {name: "Bono"});
    store.setCollection("dogs/dog-1/operational_restrictions", {
      kind: "failed",
      reasonCode: "permission_denied",
    });

    const error = await expectError(() =>
      runShiftAuthorizedCommand(store.deps(), ACTOR, baseInput(), NOW),
    );

    assert.strictEqual(error.appCode, "restrictions_unavailable");
    // Distinguível de bloqueio clínico — o Mobile precisa diferenciar.
    assert.notStrictEqual(error.appCode, "absolute_restriction_active");
    assert.deepStrictEqual(store.operationalWrites(), []);
  });

  await test("F-01 level inválido falha fechado", async () => {
    const store = new FakeStore();
    store.setDoc("dogs/dog-1", {name: "Bono"});
    store.setCollection(
      "dogs/dog-1/operational_restrictions",
      restrictionDocs({level: "quarentena"}),
    );

    const error = await expectError(() =>
      runShiftAuthorizedCommand(store.deps(), ACTOR, baseInput(), NOW),
    );
    assert.strictEqual(error.appCode, "restrictions_unavailable");
    assert.deepStrictEqual(store.operationalWrites(), []);
  });

  await test("F-03 timestamp inválido falha fechado", async () => {
    const store = new FakeStore();
    store.setDoc("dogs/dog-1", {name: "Bono"});
    store.setCollection(
      "dogs/dog-1/operational_restrictions",
      restrictionDocs({level: "absolute", issued_at: 12345}),
    );

    const error = await expectError(() =>
      runShiftAuthorizedCommand(store.deps(), ACTOR, baseInput(), NOW),
    );
    assert.strictEqual(error.appCode, "restrictions_unavailable");
    assert.deepStrictEqual(store.operationalWrites(), []);
  });

  await test("K9 inexistente é negado antes de qualquer write", async () => {
    const store = new FakeStore();
    const error = await expectError(() =>
      runShiftAuthorizedCommand(store.deps(), ACTOR, baseInput(), NOW),
    );
    assert.strictEqual(error.appCode, "k9_not_found");
    assert.deepStrictEqual(store.writes, []);
  });

  // ── Fan-out de guarnição ──────────────────────────────────────────────────
  await test("switch_dog propaga o novo K9 para os demais membros ativos", async () => {
    const store = storeWithActiveShift("dog-old");
    store.vehicleId = "VTR-01";
    store.crewRas = ["111111", "222222"];

    const result = await runShiftAuthorizedCommand(
      store.deps(),
      ACTOR,
      baseInput({action: "switch_dog", operationId: "op-sw"}),
      NOW,
    );

    assert.strictEqual(result.decision, "allowed");
    const own = store.writeAt("active_shifts/998877");
    assert.strictEqual(own?.data.dogId, "dog-1");
    assert.strictEqual(own?.merge, true);
    // Fan-out preservado.
    assert.strictEqual(store.writeAt("active_shifts/111111")?.data.service_dog_id, "dog-1");
    assert.strictEqual(store.writeAt("active_shifts/222222")?.data.service_dog_id, "dog-1");
    // Histórico do cão registrado com origem e destino.
    const log = store.writeAt("shift_logs/shift-1");
    assert.strictEqual(log?.data.currentDogId, "dog-1");
    const dogChanges = log?.data.dog_changes as {__arrayUnion__: JsonMap[]};
    assert.strictEqual(dogChanges.__arrayUnion__[0].from, "dog-old");
    assert.strictEqual(dogChanges.__arrayUnion__[0].to, "dog-1");
    // Guarnição acompanha.
    assert.strictEqual(
      store.writeAt("vehicle_crews/VTR-01")?.data.service_dog_id,
      "dog-1",
    );
  });

  await test("switch_dog sem turno ativo é invalid_state, não cria turno", async () => {
    const store = new FakeStore();
    store.setDoc("dogs/dog-1", {name: "Bono"});

    const error = await expectError(() =>
      runShiftAuthorizedCommand(
        store.deps(),
        ACTOR,
        baseInput({action: "switch_dog", operationId: "op-sw2"}),
        NOW,
      ),
    );
    assert.strictEqual(error.appCode, "invalid_state");
    assert.deepStrictEqual(store.operationalWrites(), []);
  });

  // ── assume_vehicle ────────────────────────────────────────────────────────
  await test("assume_vehicle grava o K9 autorizado na guarnição e no membro", async () => {
    const store = storeWithActiveShift("");
    const result = await runShiftAuthorizedCommand(
      store.deps(),
      ACTOR,
      baseInput({
        action: "assume_vehicle",
        operationId: "op-av",
        role: "k9",
        handlerName: "Condutor Teste",
        vehicle: {
          id: "VTR-02",
          label: "VTR 02",
          prefix: "02",
          modelName: "Hilux",
          unit: "GCM",
          crewSize: 3,
        },
      }),
      NOW,
    );

    assert.strictEqual(result.decision, "allowed");
    const crew = store.writeAt("vehicle_crews/VTR-02");
    assert.strictEqual(crew?.data.service_dog_id, "dog-1");
    assert.strictEqual(crew?.data.active, true);
    // created_at/ended_at não são tocados no assume — só na abertura.
    assert.strictEqual(crew?.data.created_at, undefined);
    assert.strictEqual(crew?.data.ended_at, undefined);
    // members leva `name`, ao contrário de active_shifts.
    const member = store.writeAt("vehicle_crews/VTR-02/members/998877");
    assert.strictEqual(member?.data.dog_id, "dog-1");
    assert.strictEqual(member?.data.name, "Condutor Teste");
    assert.strictEqual(member?.data.role, "k9");
  });

  await test("assume_vehicle rejeita guarnição ativa com outro K9 embarcado", async () => {
    const store = storeWithActiveShift("");
    store.setDoc("vehicle_crews/VTR-02", {
      active: true,
      service_dog_id: "dog-outro",
    });

    const error = await expectError(() =>
      runShiftAuthorizedCommand(
        store.deps(),
        ACTOR,
        baseInput({
          action: "assume_vehicle",
          operationId: "op-av2",
          vehicle: {
            id: "VTR-02",
            label: "VTR 02",
            prefix: "02",
            modelName: "Hilux",
            unit: "GCM",
            crewSize: 3,
          },
        }),
        NOW,
      ),
    );
    assert.strictEqual(error.appCode, "invalid_state");
    assert.deepStrictEqual(store.operationalWrites(), []);
  });

  // ── Idempotência ──────────────────────────────────────────────────────────
  await test("retry com mesmo operationId não duplica o turno", async () => {
    const store = new FakeStore();
    store.setDoc("dogs/dog-1", {name: "Bono"});

    const first = await runShiftAuthorizedCommand(
      store.deps(),
      ACTOR,
      baseInput(),
      NOW,
    );
    assert.strictEqual(first.wasNoOp, false);

    // Persiste o receipt como o Firestore real faria.
    const receipt = store.writeAt("shift_operations/op-1");
    assert.ok(receipt, "receipt deve ser gravado");
    store.setDoc("shift_operations/op-1", receipt.data);
    const writesBefore = store.writes.length;

    const second = await runShiftAuthorizedCommand(
      store.deps(),
      ACTOR,
      baseInput(),
      NOW,
    );

    assert.strictEqual(second.wasNoOp, true);
    assert.strictEqual(second.shiftId, first.shiftId);
    assert.strictEqual(
      store.writes.length,
      writesBefore,
      "replay não pode produzir novos writes",
    );
  });

  await test("mesmo operationId com payload diferente é idempotency_conflict", async () => {
    const store = new FakeStore();
    store.setDoc("dogs/dog-1", {name: "Bono"});
    store.setDoc("dogs/dog-2", {name: "Zeus"});

    await runShiftAuthorizedCommand(store.deps(), ACTOR, baseInput(), NOW);
    const receipt = store.writeAt("shift_operations/op-1");
    store.setDoc("shift_operations/op-1", receipt!.data);

    const error = await expectError(() =>
      runShiftAuthorizedCommand(
        store.deps(),
        ACTOR,
        baseInput({dogId: "dog-2"}),
        NOW,
      ),
    );
    assert.strictEqual(error.appCode, "idempotency_conflict");
  });

  await test(
    "ciclo partial completo: negativa NÃO cria receipt terminal e o retry " +
      "com o MESMO operationId executa exatamente uma vez",
    async () => {
      // Risco concreto sob teste: se a primeira negativa gravasse um receipt, o
      // reenvio com ciência colidiria (fingerprint diferente) ou seria tratado
      // como replay — e o turno nunca aconteceria. O aceite ficaria num
      // deadlock permanente.
      const store = new FakeStore();
      store.setDoc("dogs/dog-1", {name: "Bono"});
      store.setCollection(
        "dogs/dog-1/operational_restrictions",
        restrictionDocs({
          __id: "rp-1",
          level: "partial",
          activities_restricted: ["busca"],
        }),
      );

      // ── 1ª chamada: operationId = X, SEM ciência ──
      const error = await expectError(() =>
        runShiftAuthorizedCommand(store.deps(), ACTOR, baseInput(), NOW),
      );
      assert.strictEqual(error.appCode, "partial_acknowledgement_required");
      assert.deepStrictEqual(store.operationalWrites(), []);
      // Nenhum receipt: a negativa não consome o operationId.
      assert.strictEqual(
        store.writeAt("shift_operations/op-1"),
        undefined,
        "negativa por ciência pendente NÃO pode gravar receipt",
      );
      // Comparação por tamanho (e não deepStrictEqual com []) de propósito:
      // igualar a array vazia estreita o tipo para never[] e quebra os filtros
      // usados adiante neste mesmo teste.
      assert.strictEqual(store.writes.length, 0, "nenhum write na negativa");

      // ── 2ª chamada: MESMO operationId = X, COM ciência ──
      const result = await runShiftAuthorizedCommand(
        store.deps(),
        ACTOR,
        baseInput({acknowledgedRestrictionIds: ["rp-1"]}),
        NOW,
      );

      // Sem colisão de idempotência.
      assert.notStrictEqual(result.decision, undefined);
      assert.strictEqual(result.decision, "allowed_with_restrictions");
      assert.strictEqual(result.wasNoOp, false);
      assert.strictEqual(result.acknowledgementRecorded, true);

      // Executou EXATAMENTE uma vez.
      const activeWrites = store.writes.filter(
        (write) => write.path === "active_shifts/998877",
      );
      assert.strictEqual(activeWrites.length, 1, "turno criado uma única vez");
      const logWrites = store.writes.filter((write) =>
        write.path.startsWith("shift_logs/"),
      );
      assert.strictEqual(logWrites.length, 1, "shift_log criado uma única vez");

      // Auditoria de ciência EXATAMENTE uma vez.
      const audits = store.writes.filter((write) =>
        write.path.startsWith("auditLogs/"),
      );
      assert.strictEqual(audits.length, 1, "audit de ciência uma única vez");
      const metadata = audits[0].data.metadata as JsonMap;
      assert.deepStrictEqual(metadata.partial_acknowledged, ["rp-1"]);

      // E o receipt agora existe, com o fingerprint do comando.
      const receipt = store.writeAt("shift_operations/op-1");
      assert.ok(receipt, "receipt gravado após execução autorizada");
    },
  );

  await test(
    "fingerprint ignora a ciência, então retry é o MESMO comando",
    async () => {
      // Se `acknowledgedRestrictionIds` entrasse no fingerprint, o reenvio com
      // ciência seria classificado como "outra operação" e bateria em
      // idempotency_conflict.
      const withoutAck = fingerprintCommand(baseInput());
      const withAck = fingerprintCommand(
        baseInput({acknowledgedRestrictionIds: ["rp-1"]}),
      );
      assert.strictEqual(withAck, withoutAck);
    },
  );

  await test("retry de aceite parcial não duplica registro de ciência", async () => {
    const store = new FakeStore();
    store.setDoc("dogs/dog-1", {name: "Bono"});
    store.setCollection(
      "dogs/dog-1/operational_restrictions",
      restrictionDocs({
        __id: "rp-1",
        level: "partial",
        activities_restricted: ["busca"],
      }),
    );

    const input = baseInput({acknowledgedRestrictionIds: ["rp-1"]});
    await runShiftAuthorizedCommand(store.deps(), ACTOR, input, NOW);
    const receipt = store.writeAt("shift_operations/op-1");
    store.setDoc("shift_operations/op-1", receipt!.data);

    const auditsBefore = store.writes.filter((w) =>
      w.path.startsWith("auditLogs/"),
    ).length;

    const second = await runShiftAuthorizedCommand(
      store.deps(),
      ACTOR,
      input,
      NOW,
    );
    assert.strictEqual(second.wasNoOp, true);
    const auditsAfter = store.writes.filter((w) =>
      w.path.startsWith("auditLogs/"),
    ).length;
    assert.strictEqual(auditsAfter, auditsBefore, "ciência não pode duplicar");
  });

  // ── Validação de payload ──────────────────────────────────────────────────
  await test("dogId vazio é invalid_argument (não vira turno sem K9 por engano)", async () => {
    const store = new FakeStore();
    const error = await expectError(() =>
      runShiftAuthorizedCommand(
        store.deps(),
        ACTOR,
        baseInput({dogId: "   "}),
        NOW,
      ),
    );
    assert.strictEqual(error.appCode, "invalid_argument");
    assert.deepStrictEqual(store.writes, []);
  });

  await test("role inválido é rejeitado", async () => {
    const store = new FakeStore();
    store.setDoc("dogs/dog-1", {name: "Bono"});
    const error = await expectError(() =>
      runShiftAuthorizedCommand(
        store.deps(),
        ACTOR,
        baseInput({role: "comandante_geral"}),
        NOW,
      ),
    );
    assert.strictEqual(error.appCode, "invalid_argument");
  });

  // ── A-05: cliente não influencia decisão clínica ──────────────────────────
  await test("A-05 campos clínicos enviados pelo cliente são ignorados", async () => {
    const store = new FakeStore();
    store.setDoc("dogs/dog-1", {name: "Bono"});
    store.setCollection(
      "dogs/dog-1/operational_restrictions",
      restrictionDocs({level: "absolute"}),
    );

    // O cliente tenta se autorizar. A entrada nem tem esses campos no tipo, e
    // o engine só lê a coleção canônica — então a tentativa é inócua.
    const hostileInput = {
      ...baseInput(),
      restrictionStatus: "none",
      readinessStatus: "operational",
      override: true,
    } as unknown as ShiftCommandInput;

    const error = await expectError(() =>
      runShiftAuthorizedCommand(store.deps(), ACTOR, hostileInput, NOW),
    );
    assert.strictEqual(error.appCode, "absolute_restriction_active");
    assert.deepStrictEqual(store.operationalWrites(), []);
  });

  if (failed > 0) {
    console.error(`\n${failed} test(s) failed`);
    process.exit(1);
  }
  console.log("shift_authorization_engine_test: all passed");
}

void main();
