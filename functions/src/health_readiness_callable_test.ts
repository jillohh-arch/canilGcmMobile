/**
 * Readiness v1 — callable tests (C-01..C-12).
 *
 * Stage READINESS-V1 — Local implementation only. Not deployed.
 *
 * Estes testes invocam o HANDLER REAL
 * (`buildHealthReadinessRefreshHandler`), nunca uma cópia da lógica.
 *
 * Motivo: a versão anterior desta suíte reimplementava as validações dentro do
 * próprio arquivo de teste e por isso passava mesmo que o callable estivesse
 * errado — falso positivo. A autorização dog-level é a invariante mais
 * consequente aqui, porque o Admin SDK ignora as Firestore Rules: se o callable
 * não checar acesso ao K9, nada mais checa.
 */

import * as assert from "assert";
import {HttpsError} from "firebase-functions/v2/https";
import {
  buildHealthReadinessRefreshHandler,
  HealthReadinessCallableDeps,
} from "./health_readiness_callable";

let failed = 0;

async function test(name: string, fn: () => Promise<void>): Promise<void> {
  try {
    await fn();
    console.log(`ok - ${name}`);
  } catch (e) {
    failed++;
    console.error(`FAIL - ${name}`, e);
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Fakes mínimos
// ─────────────────────────────────────────────────────────────────────────────

const DOG_AUTHORIZED = "dog-vinculado";
const DOG_FOREIGN = "dog-alheio";

/** Registra o que o "backend" recebeu, para asserção de fluxo. */
interface Recorder {
  authCalls: number;
  accessChecks: Array<{uid: string; dogId: string}>;
  summaryWrites: string[];
  subcollectionReads: string[];
}

function recorder(): Recorder {
  return {
    authCalls: 0,
    accessChecks: [],
    summaryWrites: [],
    subcollectionReads: [],
  };
}

/**
 * Firestore fake suficiente para o projector rodar de ponta a ponta.
 *
 * Todas as subcoleções voltam vazias, o que produz `not_evaluated` — um estado
 * CLÍNICO válido. Basta para provar que o handler chegou até a projeção.
 */
interface FakeDbOptions {
  /** Pre-seeded docs, keyed `dogId/subcollection/docId`. */
  readonly seed?: Readonly<Record<string, Record<string, unknown>>>;
  /** Subcollections whose read throws, forcing the unavailable path (C2). */
  readonly failingSubcollections?: readonly string[];
  /** Pre-seeded coordination doc, keyed by full `_health_projection_state/...` path. */
  readonly seedPaths?: Readonly<Record<string, Record<string, unknown>>>;
  /** Makes the summary reread fail, so the causal observation is unavailable. */
  readonly failSummaryReread?: boolean;
  /**
   * Simulates a HIGHER ready generation committing between this execution's
   * apply and the caller's reread — i.e. another entry point won the race.
   */
  readonly concurrentReadyGenerationBeforeReread?: number;
  /**
   * Drops `projection_generation` from the summary just before the caller's
   * reread, reproducing a summary written by a backend that predates the
   * causal marker (rollout: new Mobile against old backend).
   */
  readonly stripGenerationBeforeReread?: boolean;
  /**
   * Simulates a NEWER generation applying an UNAVAILABLE patch between this
   * execution's apply and the caller's reread. The READY marker is left as-is,
   * exactly like the real merge, so the observed pair becomes
   * (`unavailable`, previous ready generation).
   */
  readonly concurrentUnavailableBeforeReread?: boolean;
}

function fakeDb(
  rec: Recorder,
  options: FakeDbOptions = {},
): FirebaseFirestore.Firestore {
  const store = new Map<string, Record<string, unknown>>();
  for (const [key, value] of Object.entries(options.seed ?? {})) {
    store.set(key, value);
  }
  for (const [key, value] of Object.entries(options.seedPaths ?? {})) {
    store.set(key, value);
  }
  const failing = new Set(options.failingSubcollections ?? []);
  // The handler's causal reread happens after the projector has finished, so
  // counting summary gets lets a test fail only that later read.
  let summaryGets = 0;

  const docRef = (dogId: string, sub?: string): unknown => ({
    collection: (name: string) => ({
      doc: (id: string) => ({
        get: async () => {
          rec.subcollectionReads.push(`${dogId}/${name}/${id}`);
          if (name === "health_summary") {
            summaryGets++;
            // The projector reads /current first; the handler's reread is later.
            if (options.failSummaryReread && summaryGets > 1) {
              throw new Error("summary_reread_failed");
            }
            const concurrent = options.concurrentReadyGenerationBeforeReread;
            if (concurrent !== undefined && summaryGets > 1) {
              const key = `${dogId}/${name}/${id}`;
              store.set(key, {
                ...(store.get(key) ?? {}),
                projection_status: "ready",
                projection_generation: concurrent,
              });
            }
            if (options.stripGenerationBeforeReread && summaryGets > 1) {
              const key = `${dogId}/${name}/${id}`;
              const current = {...(store.get(key) ?? {})};
              delete current.projection_generation;
              store.set(key, current);
            }
            if (options.concurrentUnavailableBeforeReread && summaryGets > 1) {
              const key = `${dogId}/${name}/${id}`;
              // Merge patch: projection_generation deliberately NOT advanced,
              // mirroring how a real unavailable write leaves the READY marker.
              store.set(key, {
                ...(store.get(key) ?? {}),
                projection_status: "unavailable",
              });
            }
          }
          const data = store.get(`${dogId}/${name}/${id}`);
          return {
            exists: data !== undefined,
            data: () => data,
          };
        },
        set: async (payload: Record<string, unknown>) => {
          rec.summaryWrites.push(`${dogId}/${name}/${id}`);
          // Firestore merge semantics: readiness unavailable writes are patches,
          // so a fake that replaced the doc would fake away last-known-good.
          store.set(`${dogId}/${name}/${id}`, {
            ...(store.get(`${dogId}/${name}/${id}`) ?? {}),
            ...payload,
          });
        },
      }),
      get: async () => {
        rec.subcollectionReads.push(`${dogId}/${name}`);
        if (failing.has(name)) {
          throw new Error(`source_read_failed:${name}`);
        }
        const docs = Object.entries(options.seed ?? {})
          .filter(([key]) => key.startsWith(`${dogId}/${name}/`))
          .map(([key, data]) => ({id: key.split("/").pop() as string, data: () => data}));
        return {docs};
      },
    }),
    get: async () => ({exists: true, data: () => ({name: "K9"})}),
  });

  // Path-addressed ref for the generation coordination document, backed by the
  // same store, so runTransaction reservation/apply work end to end.
  const genStore = store;
  const pathRef = (segments: string[]): unknown => {
    const key = segments.join("/");
    const ref = {
      collection: (name: string) => ({
        doc: (id: string) => pathRef([...segments, name, id]),
      }),
      get: async () => {
        const data = genStore.get(key);
        return {exists: data !== undefined, data: () => data};
      },
      set: async (payload: Record<string, unknown>) => {
        genStore.set(key, {...(genStore.get(key) ?? {}), ...payload});
      },
      _key: key,
    };
    return ref;
  };

  return {
    collection: (name: string) => ({
      doc: (id: string) =>
        name === "_health_projection_state" ? pathRef([name, id]) : docRef(id, name),
    }),
    runTransaction: async (
      fn: (txn: unknown) => Promise<unknown>,
    ): Promise<unknown> => {
      const txn = {
        get: async (ref: {_key?: string; get: () => Promise<unknown>}) => ref.get(),
        set: async (
          ref: {set: (p: Record<string, unknown>) => Promise<void>},
          payload: Record<string, unknown>,
        ) => {
          // The refs themselves record their own write paths.
          await ref.set(payload);
        },
      };
      return fn(txn);
    },
  } as unknown as FirebaseFirestore.Firestore;
}

/**
 * Deps que reproduzem o modelo real: autenticação + autorização por K9.
 *
 * `authorizedDogs` emula o resultado de `requireDogRecordAccess` — escopo
 * `own_records` com vínculo apenas a certos K9.
 */
function deps(
  rec: Recorder,
  options: {
    authenticated?: boolean;
    authorizedDogs?: readonly string[];
  } = {},
): HealthReadinessCallableDeps {
  const authenticated = options.authenticated ?? true;
  const authorized = options.authorizedDogs ?? [DOG_AUTHORIZED];

  return {
    requireAuth: async () => {
      rec.authCalls++;
      if (!authenticated) {
        throw new HttpsError("unauthenticated", "Autenticacao obrigatoria.");
      }
      return {uid: "uid-condutor"};
    },
    requireHealthReadAccess: async (uid, dogId) => {
      rec.accessChecks.push({uid, dogId});
      if (!authorized.includes(dogId)) {
        throw new HttpsError(
          "permission-denied",
          "Seu perfil permite registrar dados apenas para o K9 vinculado ou em turno ativo.",
        );
      }
    },
  };
}

function request(data: unknown, auth: unknown = {uid: "uid-condutor"}): never {
  return {data, auth} as never;
}

async function expectHttpsError(
  action: () => Promise<unknown>,
  expectedCode: string,
): Promise<HttpsError> {
  try {
    await action();
  } catch (e) {
    assert.ok(
      e instanceof HttpsError,
      `esperava HttpsError, veio ${String(e)}`,
    );
    const err = e as HttpsError;
    assert.strictEqual(
      err.code,
      expectedCode,
      `esperava code ${expectedCode}, veio ${err.code}`,
    );
    return err;
  }
  throw new assert.AssertionError({
    message: `esperava HttpsError(${expectedCode}), mas nada foi lançado`,
  });
}

// ─────────────────────────────────────────────────────────────────────────────

async function main() {
  // ══ AUTORIZAÇÃO POR K9 — a invariante que faltava provar ══════════════════

  await test(
    "C-01 own_records + K9 SEM vínculo -> permission-denied (handler real)",
    async () => {
      const rec = recorder();
      const handler = buildHealthReadinessRefreshHandler(
        deps(rec, {authorizedDogs: [DOG_AUTHORIZED]}),
        fakeDb(rec),
      );

      await expectHttpsError(
        () => handler(request({dogId: DOG_FOREIGN})),
        "permission-denied",
      );

      // A checagem realmente ocorreu, com o dogId solicitado.
      assert.deepStrictEqual(rec.accessChecks, [
        {uid: "uid-condutor", dogId: DOG_FOREIGN},
      ]);
      // E nada foi projetado para o K9 alheio.
      assert.deepStrictEqual(
        rec.summaryWrites,
        [],
        "K9 alheio nunca pode receber escrita de projeção",
      );
    },
  );

  await test(
    "C-02 own_records + K9 autorizado -> permitido e projeta",
    async () => {
      const rec = recorder();
      const handler = buildHealthReadinessRefreshHandler(
        deps(rec, {authorizedDogs: [DOG_AUTHORIZED]}),
        fakeDb(rec),
      );

      const response = await handler(request({dogId: DOG_AUTHORIZED}));

      assert.strictEqual(response.ok, true);
      assert.deepStrictEqual(rec.accessChecks, [
        {uid: "uid-condutor", dogId: DOG_AUTHORIZED},
      ]);
      // Projetou exatamente no documento canônico.
      assert.deepStrictEqual(rec.summaryWrites, [
        `${DOG_AUTHORIZED}/health_summary/current`,
      ]);
    },
  );

  await test(
    "C-03 autorização é consultada ANTES de qualquer projeção",
    async () => {
      const rec = recorder();
      const handler = buildHealthReadinessRefreshHandler(
        deps(rec, {authorizedDogs: []}),
        fakeDb(rec),
      );

      await expectHttpsError(
        () => handler(request({dogId: DOG_AUTHORIZED})),
        "permission-denied",
      );

      // Nenhuma leitura de evidência aconteceu: negado antes de ler o K9.
      assert.deepStrictEqual(
        rec.subcollectionReads,
        [],
        "negação deve preceder leitura de evidência",
      );
    },
  );

  await test("C-04 nenhum K9 autorizado -> todos negados", async () => {
    const rec = recorder();
    const handler = buildHealthReadinessRefreshHandler(
      deps(rec, {authorizedDogs: []}),
      fakeDb(rec),
    );

    for (const dogId of ["dog-a", "dog-b", "dog-c"]) {
      await expectHttpsError(
        () => handler(request({dogId})),
        "permission-denied",
      );
    }
    assert.strictEqual(rec.accessChecks.length, 3);
    assert.deepStrictEqual(rec.summaryWrites, []);
  });

  // ══ AUTENTICAÇÃO ══════════════════════════════════════════════════════════

  await test("C-05 não autenticado -> unauthenticated (handler real)", async () => {
    const rec = recorder();
    const handler = buildHealthReadinessRefreshHandler(
      deps(rec, {authenticated: false}),
      fakeDb(rec),
    );

    await expectHttpsError(
      () => handler(request({dogId: DOG_AUTHORIZED}, undefined)),
      "unauthenticated",
    );

    // Sem auth, nem autorização nem projeção acontecem.
    assert.deepStrictEqual(rec.accessChecks, []);
    assert.deepStrictEqual(rec.summaryWrites, []);
  });

  await test("C-06 auth é exigida antes da validação de payload", async () => {
    const rec = recorder();
    const handler = buildHealthReadinessRefreshHandler(
      deps(rec, {authenticated: false}),
      fakeDb(rec),
    );

    // Payload inválido E sem auth: auth vem primeiro.
    await expectHttpsError(
      () => handler(request({}, undefined)),
      "unauthenticated",
    );
    assert.strictEqual(rec.authCalls, 1);
  });

  // ══ PAYLOAD ═══════════════════════════════════════════════════════════════

  await test("C-07 dogId ausente/inválido -> erro, sem autorização", async () => {
    const rec = recorder();
    const handler = buildHealthReadinessRefreshHandler(deps(rec), fakeDb(rec));

    for (const bad of [
      undefined,
      null,
      "",
      "   ",
      42,
      "dogs/dog-1",
      ".",
      "..",
      "x".repeat(200),
    ]) {
      const response = await handler(request({dogId: bad}));
      assert.strictEqual(
        response.ok,
        false,
        `dogId ${JSON.stringify(bad)} deveria ser rejeitado`,
      );
      if (!response.ok) {
        assert.strictEqual(response.error.code, "invalid_dog_id");
      }
    }
    // Payload inválido nunca chega à autorização nem à projeção.
    assert.deepStrictEqual(rec.accessChecks, []);
    assert.deepStrictEqual(rec.summaryWrites, []);
  });

  await test(
    "C-08 readinessStatus do cliente -> rejeitado, sem projeção (handler real)",
    async () => {
      const rec = recorder();
      const handler = buildHealthReadinessRefreshHandler(deps(rec), fakeDb(rec));

      for (const attempted of [
        "operational",
        "temporarily_unfit",
        "not_evaluated",
      ]) {
        const response = await handler(
          request({dogId: DOG_AUTHORIZED, readinessStatus: attempted}),
        );
        assert.strictEqual(response.ok, false);
        if (!response.ok) {
          assert.strictEqual(response.error.code, "invalid_payload");
        }
      }

      // O cliente não conseguiu induzir nem autorização nem escrita.
      assert.deepStrictEqual(rec.accessChecks, []);
      assert.deepStrictEqual(
        rec.summaryWrites,
        [],
        "veredito do cliente jamais pode ser persistido",
      );
    },
  );

  await test("C-09 payload limpo com dogId é aceito", async () => {
    const rec = recorder();
    const handler = buildHealthReadinessRefreshHandler(deps(rec), fakeDb(rec));
    const response = await handler(request({dogId: DOG_AUTHORIZED}));
    assert.strictEqual(response.ok, true);
  });

  // ══ RESULTADO / IDEMPOTÊNCIA ══════════════════════════════════════════════

  await test("C-10 resultado não fabrica estado clínico", async () => {
    const rec = recorder();
    const handler = buildHealthReadinessRefreshHandler(deps(rec), fakeDb(rec));
    const response = await handler(request({dogId: DOG_AUTHORIZED}));

    assert.strictEqual(response.ok, true);
    if (response.ok) {
      // Sem evidência alguma, o servidor decide not_evaluated — estado clínico
      // legítimo, nunca um "operational" otimista.
      assert.strictEqual(response.result.readinessStatus, "not_evaluated");
      assert.strictEqual(response.result.projectionStatus, "ready");
      assert.notStrictEqual(response.result.readinessStatus, "operational");
    }
  });

  await test("C-11 refresh repetido mantém um único /current", async () => {
    const rec = recorder();
    const handler = buildHealthReadinessRefreshHandler(deps(rec), fakeDb(rec));

    await handler(request({dogId: DOG_AUTHORIZED}));
    await handler(request({dogId: DOG_AUTHORIZED}));
    await handler(request({dogId: DOG_AUTHORIZED}));

    // Sempre o mesmo caminho — nenhum documento novo por chamada.
    assert.deepStrictEqual(new Set(rec.summaryWrites), new Set([
      `${DOG_AUTHORIZED}/health_summary/current`,
    ]));
    assert.strictEqual(rec.summaryWrites.length, 3);
  });

  // ══ CONFIG ════════════════════════════════════════════════════════════════

  await test("C-12 config tipada resolve 90/180 na boundary", async () => {
    const {resolveReadinessConfig} = await import("./health_readiness_config");
    const config = resolveReadinessConfig();
    assert.strictEqual(config.weightMaxAgeDays, 90);
    assert.strictEqual(config.consultationMaxAgeDays, 180);
  });

  // ══ B4-R.C2 — CAUSAL REFRESH RESPONSE ═════════════════════════════════════
  //
  // Contrato humano congelado: result.convergence.{status,requiredGeneration,
  // observedGeneration}, com literais confirmed | not_confirmed | unavailable.

  const GEN_DOC = `_health_projection_state/health_readiness_v1/dogs/${DOG_AUTHORIZED}`;
  const SUMMARY_KEY = `${DOG_AUTHORIZED}/health_summary/current`;

  await test("C2-01 legacy: campos e semântica congelados permanecem", async () => {
    const rec = recorder();
    const handler = buildHealthReadinessRefreshHandler(deps(rec), fakeDb(rec));
    const response = await handler(request({dogId: DOG_AUTHORIZED}));

    assert.strictEqual(response.ok, true);
    if (!response.ok) return;
    // Nomes legados exatos, nenhum renomeado nem removido.
    for (const field of [
      "dogId",
      "projectionStatus",
      "readinessStatus",
      "readinessLabel",
      "readinessReasonCode",
      "technicalBlockers",
      "operation",
    ]) {
      assert.ok(
        field in response.result,
        `campo legado ausente: ${field}`,
      );
    }
    assert.strictEqual(response.result.dogId, DOG_AUTHORIZED);
    assert.strictEqual(response.result.projectionStatus, "ready");
    assert.strictEqual(response.result.readinessStatus, "not_evaluated");
    assert.strictEqual(response.result.operation, "ready");
  });

  await test("C2-02 cliente legado que só lê `ok` não é afetado", async () => {
    const rec = recorder();
    const handler = buildHealthReadinessRefreshHandler(deps(rec), fakeDb(rec));
    // Exatamente o que o gateway Dart faz hoje: response['ok'] == true.
    const legacyRead = (r: unknown): boolean =>
      (r as {ok?: unknown}).ok === true;

    assert.strictEqual(
      legacyRead(await handler(request({dogId: DOG_AUTHORIZED}))),
      true,
    );
  });

  await test("C2-03 confirmed: observed == required", async () => {
    const rec = recorder();
    const handler = buildHealthReadinessRefreshHandler(deps(rec), fakeDb(rec));
    const response = await handler(request({dogId: DOG_AUTHORIZED}));

    assert.strictEqual(response.ok, true);
    if (!response.ok) return;
    assert.deepStrictEqual(response.result.convergence, {
      status: "confirmed",
      requiredGeneration: 1,
      observedGeneration: 1,
    });
  });

  await test(
    "C2-04 confirmed: geração READY superior (H > G) satisfaz a barreira",
    async () => {
      const rec = recorder();
      const handler = buildHealthReadinessRefreshHandler(
        deps(rec),
        // Outra entrada commitou generation 9 antes do reread do caller.
        fakeDb(rec, {concurrentReadyGenerationBeforeReread: 9}),
      );

      const response = await handler(request({dogId: DOG_AUTHORIZED}));
      assert.strictEqual(response.ok, true);
      if (!response.ok) return;
      assert.strictEqual(response.result.convergence.status, "confirmed");
      assert.strictEqual(response.result.convergence.requiredGeneration, 1);
      assert.strictEqual(
        response.result.convergence.observedGeneration,
        9,
        "H > G é prova causal válida — igualdade não é exigida",
      );
    },
  );

  await test(
    "C2-05 not_confirmed: geração observada inferior nunca confirma",
    async () => {
      const rec = recorder();
      const handler = buildHealthReadinessRefreshHandler(
        deps(rec),
        // Reread devolve uma geração ready ANTERIOR à requerida.
        fakeDb(rec, {concurrentReadyGenerationBeforeReread: 1, seedPaths: {
          [GEN_DOC]: {
            last_reserved_generation: 40,
            last_applied_generation: 40,
          },
        }}),
      );

      const response = await handler(request({dogId: DOG_AUTHORIZED}));
      assert.strictEqual(response.ok, true);
      if (!response.ok) return;
      assert.strictEqual(response.result.convergence.requiredGeneration, 41);
      assert.strictEqual(response.result.convergence.observedGeneration, 1);
      assert.strictEqual(
        response.result.convergence.status,
        "not_confirmed",
        "geração stale jamais pode confirmar",
      );
    },
  );

  await test(
    "C2-06 not_confirmed: summary sem projection_generation (fail closed)",
    async () => {
      const rec = recorder();
      const handler = buildHealthReadinessRefreshHandler(
        deps(rec),
        // Summary READY, mas sem o marcador causal — o caso de rollout em que o
        // documento foi escrito por um backend anterior ao contrato.
        fakeDb(rec, {stripGenerationBeforeReread: true}),
      );

      const response = await handler(request({dogId: DOG_AUTHORIZED}));
      assert.strictEqual(response.ok, true);
      if (!response.ok) return;
      assert.strictEqual(
        response.result.convergence.observedGeneration,
        null,
        "marcador ausente é null, nunca 0",
      );
      assert.strictEqual(
        response.result.convergence.status,
        "not_confirmed",
        "sem marcador não há prova causal — falha fechada",
      );
      // Mesmo assim a projeção em si funcionou: legado intacto.
      assert.strictEqual(response.result.projectionStatus, "ready");
    },
  );

  await test(
    "C2R-01 execução UNAVAILABLE + READY concorrente H>G -> confirmed",
    async () => {
      const rec = recorder();
      const handler = buildHealthReadinessRefreshHandler(
        deps(rec),
        fakeDb(rec, {
          // Esta execução (G=42) cai no caminho unavailable...
          failingSubcollections: ["operational_restrictions"],
          // ...e uma projeção concorrente commita READY 43 antes do reread.
          concurrentReadyGenerationBeforeReread: 43,
          seedPaths: {
            [GEN_DOC]: {
              last_reserved_generation: 41,
              last_applied_generation: 41,
            },
          },
        }),
      );

      const response = await handler(request({dogId: DOG_AUTHORIZED}));
      assert.strictEqual(response.ok, true);
      if (!response.ok) return;

      // A execução própria terminou unavailable...
      assert.strictEqual(response.result.projectionStatus, "unavailable");
      // ...mas a prova observada é uma geração READY posterior à requerida.
      assert.deepStrictEqual(response.result.convergence, {
        status: "confirmed",
        requiredGeneration: 42,
        observedGeneration: 43,
      });
    },
  );

  await test(
    "C2R-02 execução READY + UNAVAILABLE concorrente mais novo -> unavailable",
    async () => {
      const rec = recorder();
      const handler = buildHealthReadinessRefreshHandler(
        deps(rec),
        // Esta execução aplica READY 42; depois uma geração mais nova aplica
        // unavailable, deixando o marcador READY 42 intacto por merge.
        fakeDb(rec, {concurrentUnavailableBeforeReread: true, seedPaths: {
          [GEN_DOC]: {
            last_reserved_generation: 41,
            last_applied_generation: 41,
          },
        }}),
      );

      const response = await handler(request({dogId: DOG_AUTHORIZED}));
      assert.strictEqual(response.ok, true);
      if (!response.ok) return;

      assert.strictEqual(response.result.convergence.requiredGeneration, 42);
      assert.strictEqual(response.result.convergence.observedGeneration, 42);
      assert.strictEqual(
        response.result.convergence.status,
        "unavailable",
        "marcador >= required não basta: o estado atual não é ready",
      );
    },
  );

  await test(
    "C2R-03 execução UNAVAILABLE + reread falho -> unavailable, observed null",
    async () => {
      const rec = recorder();
      const handler = buildHealthReadinessRefreshHandler(
        deps(rec),
        fakeDb(rec, {
          failingSubcollections: ["operational_restrictions"],
          failSummaryReread: true,
        }),
      );

      const response = await handler(request({dogId: DOG_AUTHORIZED}));
      assert.strictEqual(response.ok, true);
      if (!response.ok) return;
      assert.strictEqual(response.result.convergence.status, "unavailable");
      assert.strictEqual(response.result.convergence.observedGeneration, null);
    },
  );

  await test(
    "C2R-04 summary observado unavailable sem marcador -> unavailable",
    async () => {
      const {classifyConvergence} = await import(
        "./health_readiness_generation"
      );
      // Sem marcador algum, mas o estado factual é unavailable: preservar essa
      // informação em vez de degradar para not_confirmed.
      assert.strictEqual(
        classifyConvergence({
          requiredGeneration: 42,
          observedGeneration: null,
          observedProjectionStatus: "unavailable",
          isUnavailableResult: false,
        }).status,
        "unavailable",
      );
      // Já um summary ready sem marcador é ausência de prova, não indisponibilidade.
      assert.strictEqual(
        classifyConvergence({
          requiredGeneration: 42,
          observedGeneration: null,
          observedProjectionStatus: "ready",
          isUnavailableResult: false,
        }).status,
        "not_confirmed",
      );
    },
  );

  await test(
    "C2R-05 matriz completa de precedência (10 casos congelados)",
    async () => {
      const {classifyConvergence} = await import(
        "./health_readiness_generation"
      );

      const cases: Array<{
        readonly label: string;
        readonly observedGeneration: number | null;
        readonly observedProjectionStatus: unknown;
        readonly isUnavailableResult: boolean;
        readonly expected: string;
      }> = [
        {
          label: "READY exact G",
          observedGeneration: 42,
          observedProjectionStatus: "ready",
          isUnavailableResult: false,
          expected: "confirmed",
        },
        {
          label: "READY H>G",
          observedGeneration: 43,
          observedProjectionStatus: "ready",
          isUnavailableResult: false,
          expected: "confirmed",
        },
        {
          label: "UNAVAILABLE G + READY H>G",
          observedGeneration: 43,
          observedProjectionStatus: "ready",
          isUnavailableResult: true,
          expected: "confirmed",
        },
        {
          label: "READY G + newer UNAVAILABLE",
          observedGeneration: 42,
          observedProjectionStatus: "unavailable",
          isUnavailableResult: false,
          expected: "unavailable",
        },
        {
          label: "UNAVAILABLE + stale READY <G",
          observedGeneration: 41,
          observedProjectionStatus: "ready",
          isUnavailableResult: true,
          expected: "unavailable",
        },
        {
          label: "READY observed <G",
          observedGeneration: 41,
          observedProjectionStatus: "ready",
          isUnavailableResult: false,
          expected: "not_confirmed",
        },
        {
          label: "READY without marker",
          observedGeneration: null,
          observedProjectionStatus: "ready",
          isUnavailableResult: false,
          expected: "not_confirmed",
        },
        {
          label: "UNAVAILABLE without marker",
          observedGeneration: null,
          observedProjectionStatus: "unavailable",
          isUnavailableResult: true,
          expected: "unavailable",
        },
        {
          label: "READY + reread failure",
          observedGeneration: null,
          observedProjectionStatus: undefined,
          isUnavailableResult: false,
          expected: "not_confirmed",
        },
        {
          label: "UNAVAILABLE + reread failure",
          observedGeneration: null,
          observedProjectionStatus: undefined,
          isUnavailableResult: true,
          expected: "unavailable",
        },
      ];

      for (const c of cases) {
        const {status} = classifyConvergence({
          requiredGeneration: 42,
          observedGeneration: c.observedGeneration,
          observedProjectionStatus: c.observedProjectionStatus,
          isUnavailableResult: c.isUnavailableResult,
        });
        assert.strictEqual(status, c.expected, `caso: ${c.label}`);
      }
      assert.strictEqual(cases.length, 10);
    },
  );

  await test(
    "C2-07 unavailable: READY anterior (< G) preservado não confirma",
    async () => {
      const rec = recorder();
      const handler = buildHealthReadinessRefreshHandler(
        deps(rec),
        fakeDb(rec, {
          // Fonte de restrições ilegível → caminho unavailable real.
          failingSubcollections: ["operational_restrictions"],
          seed: {
            // Last-known-good READY de uma geração anterior.
            [SUMMARY_KEY]: {
              readiness_status: "operational",
              projection_status: "ready",
              projection_generation: 5,
            },
          },
          seedPaths: {
            [GEN_DOC]: {
              last_reserved_generation: 5,
              last_applied_generation: 5,
            },
          },
        }),
      );

      const response = await handler(request({dogId: DOG_AUTHORIZED}));
      assert.strictEqual(response.ok, true);
      if (!response.ok) return;

      assert.strictEqual(response.result.projectionStatus, "unavailable");
      assert.strictEqual(
        response.result.convergence.status,
        "unavailable",
        "unavailable jamais pode satisfazer convergência causal",
      );
      assert.strictEqual(response.result.convergence.requiredGeneration, 6);
      // O marcador READY antigo permanece 5 e NÃO é reinterpretado como prova.
      assert.strictEqual(response.result.convergence.observedGeneration, 5);
      assert.ok(
        response.result.convergence.observedGeneration! <
          response.result.convergence.requiredGeneration,
      );
    },
  );

  await test(
    "C2-08 unavailable preserva `ok: true` (semântica legada intacta)",
    async () => {
      const rec = recorder();
      const handler = buildHealthReadinessRefreshHandler(
        deps(rec),
        fakeDb(rec, {failingSubcollections: ["operational_restrictions"]}),
      );

      const response = await handler(request({dogId: DOG_AUTHORIZED}));
      // Exatamente o caso do contrato: ok=true com convergence não confirmada.
      assert.strictEqual(
        response.ok,
        true,
        "`ok` não pode virar false só porque o contrato causal nasceu",
      );
      if (!response.ok) return;
      assert.strictEqual(response.result.convergence.status, "unavailable");
    },
  );

  await test(
    "C2-09 observedGeneration nunca é fabricado como 0 ou negativo",
    async () => {
      const {readObservedReadyGeneration} = await import(
        "./health_readiness_generation"
      );
      // Ausente, nulo e malformado → null, nunca 0.
      for (const stored of [
        null,
        {},
        {projection_generation: null},
        {projection_generation: 0},
        {projection_generation: -3},
        {projection_generation: 1.5},
        {projection_generation: "7"},
        {projection_generation: Number.NaN},
      ] as Array<Record<string, unknown> | null>) {
        assert.strictEqual(
          readObservedReadyGeneration(stored),
          null,
          `deveria falhar fechado: ${JSON.stringify(stored)}`,
        );
      }
      // Valor válido é lido como está.
      assert.strictEqual(
        readObservedReadyGeneration({projection_generation: 42}),
        42,
      );
    },
  );

  await test(
    "C2-10 classificador: matriz completa da semântica congelada",
    async () => {
      const {classifyConvergence} = await import(
        "./health_readiness_generation"
      );

      // confirmed: ready + observed >= required.
      for (const observed of [42, 43]) {
        assert.strictEqual(
          classifyConvergence({
            requiredGeneration: 42,
            observedGeneration: observed,
            observedProjectionStatus: "ready",
            isUnavailableResult: false,
          }).status,
          "confirmed",
        );
      }

      // not_confirmed: observed inferior, ausente, ou summary não-ready.
      assert.strictEqual(
        classifyConvergence({
          requiredGeneration: 42,
          observedGeneration: 41,
          observedProjectionStatus: "ready",
          isUnavailableResult: false,
        }).status,
        "not_confirmed",
      );
      assert.strictEqual(
        classifyConvergence({
          requiredGeneration: 42,
          observedGeneration: null,
          observedProjectionStatus: "ready",
          isUnavailableResult: false,
        }).status,
        "not_confirmed",
      );
      // Geração suficiente NÃO é prova quando o estado observado não é ready.
      // Sob a precedência do C2.R esse caso é factualmente unavailable, não
      // apenas "sem prova": o marcador READY é last-known-good.
      assert.strictEqual(
        classifyConvergence({
          requiredGeneration: 42,
          observedGeneration: 42,
          observedProjectionStatus: "unavailable",
          isUnavailableResult: false,
        }).status,
        "unavailable",
        "marcador >= required com estado unavailable jamais confirma",
      );

      // Execução unavailable NÃO anula uma prova READY posterior (C2.R).
      assert.strictEqual(
        classifyConvergence({
          requiredGeneration: 42,
          observedGeneration: 99,
          observedProjectionStatus: "ready",
          isUnavailableResult: true,
        }).status,
        "confirmed",
        "prova observada tem precedência sobre o desfecho desta execução",
      );
      // Mas sem prova suficiente, o desfecho unavailable é reportado.
      assert.strictEqual(
        classifyConvergence({
          requiredGeneration: 42,
          observedGeneration: 41,
          observedProjectionStatus: "ready",
          isUnavailableResult: true,
        }).status,
        "unavailable",
      );

      // Vocabulário fechado: nenhum literal fora dos três aprovados.
      const allowed = new Set(["confirmed", "not_confirmed", "unavailable"]);
      for (const isUnavailableResult of [true, false]) {
        for (const observedGeneration of [null, 1, 42, 99]) {
          for (const observedProjectionStatus of [
            "ready",
            "unavailable",
            undefined,
          ]) {
            const {status} = classifyConvergence({
              requiredGeneration: 42,
              observedGeneration,
              observedProjectionStatus,
              isUnavailableResult,
            });
            assert.ok(allowed.has(status), `literal inesperado: ${status}`);
          }
        }
      }
    },
  );

  await test(
    "C2-11 requiredGeneration inválido é falha de integridade, não not_confirmed",
    async () => {
      const {classifyConvergence} = await import(
        "./health_readiness_generation"
      );
      for (const requiredGeneration of [0, -1, 1.5, Number.NaN]) {
        assert.throws(
          () =>
            classifyConvergence({
              requiredGeneration,
              observedGeneration: 42,
              observedProjectionStatus: "ready",
              isUnavailableResult: false,
            }),
          /invalid_generation_candidate/,
          `deveria falhar fechado para required=${requiredGeneration}`,
        );
      }
    },
  );

  await test(
    "C2-12 falha no reread não fabrica confirmação",
    async () => {
      const rec = recorder();
      const handler = buildHealthReadinessRefreshHandler(
        deps(rec),
        fakeDb(rec, {failSummaryReread: true}),
      );

      const response = await handler(request({dogId: DOG_AUTHORIZED}));
      assert.strictEqual(response.ok, true);
      if (!response.ok) return;
      // Sem observação, jamais confirmado.
      assert.strictEqual(response.result.convergence.status, "not_confirmed");
      assert.strictEqual(response.result.convergence.observedGeneration, null);
    },
  );

  await test(
    "C2-13 estado de geração server-only permanece fora da resposta",
    async () => {
      const rec = recorder();
      const handler = buildHealthReadinessRefreshHandler(deps(rec), fakeDb(rec));
      const response = await handler(request({dogId: DOG_AUTHORIZED}));

      assert.strictEqual(response.ok, true);
      if (!response.ok) return;
      const wire = JSON.stringify(response);
      for (const leaked of [
        "last_reserved_generation",
        "last_applied_generation",
        "lastReservedGeneration",
        "lastAppliedGeneration",
        "applyOutcome",
        "_health_projection_state",
      ]) {
        assert.ok(
          !wire.includes(leaked),
          `contador server-only vazou na resposta: ${leaked}`,
        );
      }
      // E os nomes rejeitados pelo contrato humano não aparecem.
      for (const rejected of [
        "requiredProjectionGeneration",
        "observedProjectionGeneration",
        "observedReadyGeneration",
        "convergenceStatus",
      ]) {
        assert.ok(!wire.includes(rejected), `nome proibido no wire: ${rejected}`);
      }
    },
  );

  await test(
    "C2-14 convergence é aninhado em result, não plano na raiz",
    async () => {
      const rec = recorder();
      const handler = buildHealthReadinessRefreshHandler(deps(rec), fakeDb(rec));
      const response = await handler(request({dogId: DOG_AUTHORIZED}));

      assert.strictEqual(response.ok, true);
      if (!response.ok) return;
      const result = response.result as unknown as Record<string, unknown>;
      assert.ok(
        result.convergence !== null && typeof result.convergence === "object",
        "convergence deve ser objeto aninhado",
      );
      assert.deepStrictEqual(
        Object.keys(result.convergence as object).sort(),
        ["observedGeneration", "requiredGeneration", "status"],
        "exatamente três campos, nomes exatos",
      );
      assert.strictEqual(result.requiredGeneration, undefined);
      assert.strictEqual(result.observedGeneration, undefined);
      assert.strictEqual(result.status, undefined);
    },
  );

  await test(
    "C2-15 projection_generation continua avançando só em READY (C1 intacto)",
    async () => {
      const rec = recorder();
      const handler = buildHealthReadinessRefreshHandler(
        deps(rec),
        fakeDb(rec, {
          failingSubcollections: ["operational_restrictions"],
          seed: {
            [SUMMARY_KEY]: {
              readiness_status: "operational",
              projection_status: "ready",
              projection_generation: 5,
            },
          },
          seedPaths: {
            [GEN_DOC]: {
              last_reserved_generation: 5,
              last_applied_generation: 5,
            },
          },
        }),
      );

      const response = await handler(request({dogId: DOG_AUTHORIZED}));
      assert.strictEqual(response.ok, true);
      if (!response.ok) return;
      // A execução unavailable NÃO avançou o marcador observável.
      assert.strictEqual(
        response.result.convergence.observedGeneration,
        5,
        "unavailable não pode avançar projection_generation",
      );
      // E o clínico last-known-good sobreviveu.
      assert.strictEqual(response.result.projectionStatus, "unavailable");
    },
  );

  console.log(
    `\nhealth_readiness_callable_test: ${
      failed === 0 ? "all passed" : `${failed} failed`
    }`,
  );
  if (failed > 0) process.exitCode = 1;
}

void main().catch((e) => {
  console.error(e);
  process.exitCode = 1;
});
