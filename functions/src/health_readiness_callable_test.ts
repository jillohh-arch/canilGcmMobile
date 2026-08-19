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
function fakeDb(rec: Recorder): FirebaseFirestore.Firestore {
  const store = new Map<string, Record<string, unknown>>();

  const docRef = (dogId: string, sub?: string): unknown => ({
    collection: (name: string) => ({
      doc: (id: string) => ({
        get: async () => {
          rec.subcollectionReads.push(`${dogId}/${name}/${id}`);
          const data = store.get(`${dogId}/${name}/${id}`);
          return {
            exists: data !== undefined,
            data: () => data,
          };
        },
        set: async (payload: Record<string, unknown>) => {
          rec.summaryWrites.push(`${dogId}/${name}/${id}`);
          store.set(`${dogId}/${name}/${id}`, payload);
        },
      }),
      get: async () => {
        rec.subcollectionReads.push(`${dogId}/${name}`);
        return {docs: []};
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
