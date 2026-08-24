/**
 * Testes do contrato de adminPatchHumanPersonnel (edicao de pessoal-only).
 *
 * Usa o runner nativo do Node (node:test), como admin_create_human.test.ts e
 * admin_patch_k9_identity.test.ts. As dependencias (autorizacao, transacao,
 * timestamp, auditoria, arrayUnion, deleteField) sao injetadas, portanto os
 * testes exercitam o contrato real (autorizacao, fronteira de dominio, patch/
 * clear, concorrencia otimista, auditoria, mapeamento de persistencia) sem
 * emulador e sem I/O.
 *
 * A interface de dependencias nao expoe Auth/claims/acesso: os testes da secao
 * E provam essa negativa ESTRUTURALMENTE (o conjunto de chaves escritas e
 * fechado e verificavel), nao apenas por ausencia de chamada.
 */

import * as assert from "node:assert/strict";
import {test} from "node:test";
import {HttpsError} from "firebase-functions/v2/https";

import {
  concurrencyAuthorityMillis,
  HumanPersonnelTransaction,
  patchHumanPersonnel,
  PatchHumanPersonnelCaller,
  PatchHumanPersonnelDeps,
  storedTimestampMillis,
} from "../src/admin_patch_human_personnel";

type JsonMap = Record<string, unknown>;

const CALLER: PatchHumanPersonnelCaller = {
  uid: "uid-admin",
  email: "1234@gcm.com.br",
  ra: "1234",
  name: "Admin Teste",
};

const SERVER_TIMESTAMP = Symbol("serverTimestamp");
const DELETE_SENTINEL = Symbol("deleteField");

/** Instante base dos espelhos de timestamp usados nos testes. */
const BASE_MILLIS = 1_700_000_000_000;

interface Recorded {
  authorizeCalls: number;
  patches: Array<{ra: string; patch: JsonMap}>;
  auditEntries: Array<{action: string; caller: PatchHumanPersonnelCaller}>;
  transactions: number;
}

interface HarnessOptions {
  authorizeError?: HttpsError;
  /** Documento existente; `null` simula documento ausente. */
  user?: JsonMap | null;
}

/** Documento de pessoal canonico usado como estado inicial padrao. */
function existingUser(overrides: JsonMap = {}): JsonMap {
  return {
    ra: "9001",
    name: "Joao da Silva",
    nomeCompleto: "Joao da Silva",
    callsign: "Silva",
    callSign: "Silva",
    cargo: "Adestrador",
    created_at: "CREATED_AT_SENTINEL",
    createdAt: "CREATED_AT_ISO_SENTINEL",
    updated_at: {toMillis: () => BASE_MILLIS},
    updatedAt: {toMillis: () => BASE_MILLIS},
    ...overrides,
  };
}

function harness(options: HarnessOptions = {}): {
  deps: PatchHumanPersonnelDeps;
  recorded: Recorded;
} {
  const recorded: Recorded = {
    authorizeCalls: 0,
    patches: [],
    auditEntries: [],
    transactions: 0,
  };
  const user =
    options.user === undefined ? existingUser() : options.user;

  const deps: PatchHumanPersonnelDeps = {
    authorize: async () => {
      recorded.authorizeCalls += 1;
      if (options.authorizeError) throw options.authorizeError;
      return CALLER;
    },
    runTransaction: async (handler) => {
      recorded.transactions += 1;
      const tx: HumanPersonnelTransaction = {
        getUser: async () => ({exists: user !== null, data: user}),
        patchUser: (ra, patch) => {
          recorded.patches.push({ra, patch});
        },
      };
      return handler(tx);
    },
    serverTimestamp: () => SERVER_TIMESTAMP,
    auditEntry: (action, caller) => {
      recorded.auditEntries.push({action, caller});
      return {action, by: caller.uid, by_ra: caller.ra};
    },
    arrayUnion: (value) => ({__arrayUnion: value}),
    deleteField: () => DELETE_SENTINEL,
  };

  return {deps, recorded};
}

/** Request minimo valido: RA + token de concorrencia + uma operacao. */
function validRequest(overrides: JsonMap = {}): JsonMap {
  return {
    ra: "9001",
    expectedUpdatedAt: BASE_MILLIS,
    patch: {cargo: "Instrutor de Obediencia"},
    ...overrides,
  };
}

async function expectHttpsError(
  run: () => Promise<unknown>,
  code: string,
): Promise<HttpsError> {
  try {
    await run();
  } catch (error) {
    assert.ok(
      error instanceof HttpsError,
      `esperava HttpsError, recebeu ${String(error)}`,
    );
    assert.equal((error as HttpsError).code, code);
    return error as HttpsError;
  }
  throw new Error(`esperava HttpsError(${code}), mas a chamada teve sucesso`);
}

function assertNoWrites(recorded: Recorded): void {
  assert.deepEqual(recorded.patches, [], "nao deve haver escrita de usuario");
  assert.deepEqual(
    recorded.auditEntries,
    [],
    "nao deve haver entrada de auditoria",
  );
}

function onlyPatch(recorded: Recorded): JsonMap {
  assert.equal(recorded.patches.length, 1, "esperava exatamente um patch");
  return recorded.patches[0].patch;
}

// ===========================================================================
// A. REQUEST / AUTH
// ===========================================================================

test("1. autorizacao e exigida antes de qualquer leitura/escrita", async () => {
  const {deps, recorded} = harness({
    authorizeError: new HttpsError("permission-denied", "sem permissao"),
  });

  await expectHttpsError(
    () => patchHumanPersonnel(deps, validRequest()),
    "permission-denied",
  );

  assert.equal(recorded.authorizeCalls, 1);
  assert.equal(recorded.transactions, 0, "nao deve abrir transacao");
  assertNoWrites(recorded);
});

test("1b. autorizacao e chamada exatamente uma vez no caminho de sucesso", async () => {
  const {deps, recorded} = harness();
  await patchHumanPersonnel(deps, validRequest());
  assert.equal(recorded.authorizeCalls, 1);
});

test("2. RA invalido e recusado", async () => {
  for (const ra of ["", "  ", "abc", "12", "1234567890123", "90a1", "90.1"]) {
    const {deps, recorded} = harness();
    await expectHttpsError(
      () => patchHumanPersonnel(deps, validRequest({ra})),
      "invalid-argument",
    );
    assertNoWrites(recorded);
  }
});

test("2b. RA ausente e recusado", async () => {
  const {deps, recorded} = harness();
  await expectHttpsError(
    () =>
      patchHumanPersonnel(deps, {
        expectedUpdatedAt: BASE_MILLIS,
        patch: {cargo: "X"},
      }),
    "invalid-argument",
  );
  assertNoWrites(recorded);
});

test("2c. RA nao e patchavel nem limpavel (imutavel)", async () => {
  const {deps, recorded} = harness();
  await expectHttpsError(
    () =>
      patchHumanPersonnel(
        deps,
        validRequest({patch: {ra: "9002", cargo: "X"}}),
      ),
    "invalid-argument",
  );
  await expectHttpsError(
    () =>
      patchHumanPersonnel(deps, validRequest({clearFields: ["ra"]})),
    "invalid-argument",
  );
  assertNoWrites(recorded);
});

test("3. chave expectedUpdatedAt ausente e recusada", async () => {
  const {deps, recorded} = harness();
  await expectHttpsError(
    () => patchHumanPersonnel(deps, {ra: "9001", patch: {cargo: "X"}}),
    "invalid-argument",
  );
  assertNoWrites(recorded);
});

test("4. expectedUpdatedAt como string ISO e recusado (contrato externo estrito)", async () => {
  const {deps, recorded} = harness();
  const error = await expectHttpsError(
    () =>
      patchHumanPersonnel(
        deps,
        validRequest({expectedUpdatedAt: "2026-08-23T00:00:00.000Z"}),
      ),
    "invalid-argument",
  );
  assert.match(error.message, /epoch millis/);
  assertNoWrites(recorded);
});

test("5. expectedUpdatedAt como objeto/Date/Timestamp e recusado", async () => {
  const candidates: unknown[] = [
    {toMillis: () => BASE_MILLIS},
    new Date(BASE_MILLIS),
    {seconds: 1, nanoseconds: 0},
    [BASE_MILLIS],
    true,
    Number.NaN,
    Number.POSITIVE_INFINITY,
  ];
  for (const expectedUpdatedAt of candidates) {
    const {deps, recorded} = harness();
    await expectHttpsError(
      () =>
        patchHumanPersonnel(
          deps,
          validRequest({expectedUpdatedAt: expectedUpdatedAt as number}),
        ),
      "invalid-argument",
    );
    assertNoWrites(recorded);
  }
});

test("6. chave de topo desconhecida e recusada", async () => {
  for (const key of ["mode", "profile", "temporaryPassword", "qualquerCoisa"]) {
    const {deps, recorded} = harness();
    await expectHttpsError(
      () => patchHumanPersonnel(deps, validRequest({[key]: "x"})),
      "invalid-argument",
    );
    assertNoWrites(recorded);
  }
});

test("7. campo desconhecido no patch e recusado", async () => {
  const {deps, recorded} = harness();
  await expectHttpsError(
    () =>
      patchHumanPersonnel(
        deps,
        validRequest({patch: {cargo: "X", campoInexistente: "y"}}),
      ),
    "invalid-argument",
  );
  assertNoWrites(recorded);
});

test("8. campo de outro dominio no patch e recusado com dominio nomeado", async () => {
  const crossDomain: Array<[string, RegExp]> = [
    ["accessProfileId", /provisionamento de acesso/],
    ["access_profile_id", /provisionamento de acesso/],
    ["accessLevel", /provisionamento de acesso/],
    ["access_level", /provisionamento de acesso/],
    ["role", /provisionamento de acesso/],
    ["roles", /provisionamento de acesso/],
    ["admin", /provisionamento de acesso/],
    ["access_scope", /provisionamento de acesso/],
    ["claim_role", /provisionamento de acesso/],
    ["claim_updated_at", /provisionamento de acesso/],
    ["mobile_access", /provisionamento de acesso/],
    ["web_access", /provisionamento de acesso/],
    ["uid", /conta de autenticacao/],
    ["email", /conta de autenticacao/],
    ["displayName", /conta de autenticacao/],
    ["password", /conta de autenticacao/],
    ["disabled", /conta de autenticacao/],
    ["isK9Instructor", /treino/],
    ["is_k9_instructor", /treino/],
    ["training_role", /treino/],
    ["specialties", /treino/],
    ["certifications", /treino/],
    ["binomial", /binomio/],
    ["handlerRa", /binomio/],
    ["shiftGroupId", /turno\/escala/],
    ["shift_group_id", /turno\/escala/],
    ["shiftLabel", /turno\/escala/],
    ["photoUrl", /foto/],
    ["profileImageUrl", /foto/],
    ["active", /ciclo de vida/],
    ["status", /ciclo de vida/],
    ["created_at", /metadados de servidor/],
    ["updated_at", /metadados de servidor/],
    ["audit_trail", /metadados de servidor/],
  ];

  for (const [field, domain] of crossDomain) {
    const {deps, recorded} = harness();
    const error = await expectHttpsError(
      () =>
        patchHumanPersonnel(deps, validRequest({patch: {[field]: "x"}})),
      "invalid-argument",
    );
    assert.match(error.message, domain, `dominio errado para ${field}`);
    assertNoWrites(recorded);
  }
});

test("9. null em patch e recusado (limpeza exige clearFields)", async () => {
  for (const field of ["cargo", "phone", "fullName", "notes"]) {
    const {deps, recorded} = harness();
    const error = await expectHttpsError(
      () =>
        patchHumanPersonnel(deps, validRequest({patch: {[field]: null}})),
      "invalid-argument",
    );
    assert.match(error.message, /clearFields/);
    assertNoWrites(recorded);
  }
});

test("10. campo obrigatorio em branco e recusado", async () => {
  for (const field of ["fullName", "callsign"]) {
    for (const value of ["", "   ", "\t\n"]) {
      const {deps, recorded} = harness();
      await expectHttpsError(
        () =>
          patchHumanPersonnel(deps, validRequest({patch: {[field]: value}})),
        "invalid-argument",
      );
      assertNoWrites(recorded);
    }
  }
});

test("11. campo opcional em branco e recusado (string vazia nao limpa)", async () => {
  for (const field of ["cargo", "phone", "notes", "cpf"]) {
    const {deps, recorded} = harness();
    const error = await expectHttpsError(
      () => patchHumanPersonnel(deps, validRequest({patch: {[field]: "  "}})),
      "invalid-argument",
    );
    assert.match(error.message, /clearFields/);
    assertNoWrites(recorded);
  }
});

test("11b. valor nao-textual no patch e recusado sem coercao", async () => {
  const values: unknown[] = [42, true, {a: 1}, ["x"]];
  for (const value of values) {
    const {deps, recorded} = harness();
    await expectHttpsError(
      () =>
        patchHumanPersonnel(
          deps,
          validRequest({patch: {cargo: value as string}}),
        ),
      "invalid-argument",
    );
    assertNoWrites(recorded);
  }
});

test("12. strings do patch sao trimadas antes de persistir", async () => {
  const {deps, recorded} = harness();
  await patchHumanPersonnel(
    deps,
    validRequest({
      patch: {fullName: "  Maria Souza  ", cargo: "\tAdestradora\n"},
    }),
  );
  const patch = onlyPatch(recorded);
  assert.equal(patch.name, "Maria Souza");
  assert.equal(patch.nomeCompleto, "Maria Souza");
  assert.equal(patch.cargo, "Adestradora");
});

test("12b. payload nao-objeto e recusado", async () => {
  for (const raw of [null, undefined, 42, "x", ["a"]]) {
    const {deps, recorded} = harness();
    await expectHttpsError(
      () => patchHumanPersonnel(deps, raw),
      "invalid-argument",
    );
    assertNoWrites(recorded);
  }
});

test("12c. integrante inexistente retorna not-found sem escrita", async () => {
  const {deps, recorded} = harness({user: null});
  await expectHttpsError(
    () => patchHumanPersonnel(deps, validRequest()),
    "not-found",
  );
  assertNoWrites(recorded);
});

// ===========================================================================
// B. PATCH / CLEAR
// ===========================================================================

test("13. campo omitido e PRESERVADO (nao aparece no patch)", async () => {
  const {deps, recorded} = harness();
  await patchHumanPersonnel(
    deps,
    validRequest({patch: {cargo: "Instrutor"}}),
  );
  const patch = onlyPatch(recorded);

  // Somente cargo + metadados de servidor devem aparecer.
  assert.equal(patch.cargo, "Instrutor");
  for (const untouched of [
    "name",
    "nomeCompleto",
    "callsign",
    "callSign",
    "cpf",
    "birth_date",
    "telefone",
    "institutional_email",
    "rank",
    "unit",
    "team",
    "admission_date",
    "notes",
  ]) {
    assert.equal(
      untouched in patch,
      false,
      `${untouched} nao deveria estar no patch`,
    );
  }
});

test("14. limpeza de campo opcional e aceita", async () => {
  const {deps, recorded} = harness();
  const result = await patchHumanPersonnel(
    deps,
    validRequest({patch: undefined, clearFields: ["notes"]}),
  );
  const patch = onlyPatch(recorded);
  assert.equal(patch.notes, DELETE_SENTINEL);
  assert.deepEqual(result.clearedFields, ["notes"]);
  assert.deepEqual(result.updatedFields, []);
});

test("15. limpeza usa o conjunto completo de aliases PERSONNEL (D1.R1)", async () => {
  const expected: Record<string, string[]> = {
    cpf: ["cpf", "document"],
    birthDate: ["birth_date", "birthDate"],
    phone: ["telefone", "phone"],
    institutionalEmail: ["institutional_email"],
    rank: ["rank", "posto", "graduacao"],
    cargo: ["cargo", "função"],
    unit: ["unit", "unidade", "lotação"],
    team: ["team", "equipe"],
    admissionDate: ["admission_date", "admissionDate"],
    notes: ["notes", "observações"],
  };

  for (const [field, documentFields] of Object.entries(expected)) {
    const {deps, recorded} = harness();
    await patchHumanPersonnel(
      deps,
      validRequest({patch: undefined, clearFields: [field]}),
    );
    const patch = onlyPatch(recorded);
    for (const documentField of documentFields) {
      assert.equal(
        patch[documentField],
        DELETE_SENTINEL,
        `${field}: esperava delete em ${documentField}`,
      );
    }
    // Nenhum outro campo de documento pode ser apagado.
    const deleted = Object.keys(patch).filter(
      (key) => patch[key] === DELETE_SENTINEL,
    );
    assert.deepEqual(
      deleted.sort(),
      [...documentFields].sort(),
      `${field}: conjunto de delete divergente`,
    );
  }
});

test("15b. institutionalEmail NUNCA apaga o espelho de Auth `email`", async () => {
  const {deps, recorded} = harness();
  await patchHumanPersonnel(
    deps,
    validRequest({patch: undefined, clearFields: ["institutionalEmail"]}),
  );
  const patch = onlyPatch(recorded);
  assert.equal(patch.institutional_email, DELETE_SENTINEL);
  assert.equal("email" in patch, false, "email de Auth jamais e tocado");
});

test("16. limpeza de campo obrigatorio e recusada", async () => {
  for (const field of ["fullName", "callsign"]) {
    const {deps, recorded} = harness();
    const error = await expectHttpsError(
      () =>
        patchHumanPersonnel(
          deps,
          validRequest({patch: undefined, clearFields: [field]}),
        ),
      "invalid-argument",
    );
    assert.match(error.message, /obrigatorio/);
    assertNoWrites(recorded);
  }
});

test("17. mesmo campo em patch e clearFields e recusado", async () => {
  const {deps, recorded} = harness();
  await expectHttpsError(
    () =>
      patchHumanPersonnel(
        deps,
        validRequest({patch: {cargo: "X"}, clearFields: ["cargo"]}),
      ),
    "invalid-argument",
  );
  assertNoWrites(recorded);
});

test("18. entrada duplicada em clearFields e recusada", async () => {
  const {deps, recorded} = harness();
  await expectHttpsError(
    () =>
      patchHumanPersonnel(
        deps,
        validRequest({patch: undefined, clearFields: ["notes", "notes"]}),
      ),
    "invalid-argument",
  );
  assertNoWrites(recorded);
});

test("18b. clearFields nao-lista / entrada nao-textual e recusado", async () => {
  for (const clearFields of ["notes", 42, [42], [null], [{}]]) {
    const {deps, recorded} = harness();
    await expectHttpsError(
      () =>
        patchHumanPersonnel(
          deps,
          validRequest({patch: undefined, clearFields}),
        ),
      "invalid-argument",
    );
    assertNoWrites(recorded);
  }
});

test("18c. campo de outro dominio em clearFields e recusado", async () => {
  for (const field of [
    "role",
    "accessLevel",
    "access_profile_id",
    "email",
    "specialties",
    "shift_group_id",
    "photoUrl",
    "active",
  ]) {
    const {deps, recorded} = harness();
    await expectHttpsError(
      () =>
        patchHumanPersonnel(
          deps,
          validRequest({patch: undefined, clearFields: [field]}),
        ),
      "invalid-argument",
    );
    assertNoWrites(recorded);
  }
});

test("19. operacao efetiva vazia e recusada", async () => {
  const variants: JsonMap[] = [
    {ra: "9001", expectedUpdatedAt: BASE_MILLIS},
    {ra: "9001", expectedUpdatedAt: BASE_MILLIS, patch: {}},
    {ra: "9001", expectedUpdatedAt: BASE_MILLIS, clearFields: []},
    {ra: "9001", expectedUpdatedAt: BASE_MILLIS, patch: {}, clearFields: []},
  ];
  for (const raw of variants) {
    const {deps, recorded} = harness();
    const error = await expectHttpsError(
      () => patchHumanPersonnel(deps, raw),
      "invalid-argument",
    );
    assert.match(error.message, /Nada para atualizar/);
    assertNoWrites(recorded);
  }
});

test("20. aliases de acesso/Auth NUNCA sao apagados em nenhuma limpeza", async () => {
  const forbidden = [
    "email",
    "role",
    "roles",
    "admin",
    "accessLevel",
    "access_level",
    "accessProfile",
    "access_profile",
    "accessProfileId",
    "access_profile_id",
    "access_scope",
    "claim_role",
    "claim_updated_at",
    "mobile_access",
    "web_access",
    "is_k9_instructor",
    "training_role",
    "specialties",
    "shift_group_id",
    "shift_label",
    "photoUrl",
    "profileImageUrl",
    "active",
    "status",
    "created_at",
    "createdAt",
  ];

  // Limpa TODOS os campos limpaveis de uma vez.
  const {deps, recorded} = harness();
  await patchHumanPersonnel(
    deps,
    validRequest({
      patch: undefined,
      clearFields: [
        "cpf",
        "birthDate",
        "phone",
        "institutionalEmail",
        "rank",
        "cargo",
        "unit",
        "team",
        "admissionDate",
        "notes",
      ],
    }),
  );
  const patch = onlyPatch(recorded);
  for (const key of forbidden) {
    assert.equal(key in patch, false, `${key} jamais pode ser tocado`);
  }
});

// ===========================================================================
// C. CONCURRENCY
// ===========================================================================

test("21. autoridade e max(updated_at, updatedAt), nunca `??`", async () => {
  // Espelhos iguais: o valor comum e a autoridade.
  assert.equal(
    concurrencyAuthorityMillis({
      updated_at: {toMillis: () => BASE_MILLIS},
      updatedAt: {toMillis: () => BASE_MILLIS},
    }),
    BASE_MILLIS,
  );
  // Divergentes: vence o mais novo, independente da ordem das chaves.
  assert.equal(
    concurrencyAuthorityMillis({
      updated_at: {toMillis: () => BASE_MILLIS},
      updatedAt: {toMillis: () => BASE_MILLIS + 5_000},
    }),
    BASE_MILLIS + 5_000,
  );
  assert.equal(
    concurrencyAuthorityMillis({
      updated_at: {toMillis: () => BASE_MILLIS + 5_000},
      updatedAt: {toMillis: () => BASE_MILLIS},
    }),
    BASE_MILLIS + 5_000,
  );
});

test("22. updated_at mais antigo / updatedAt mais novo: token antigo conflita", async () => {
  const user = existingUser({
    updated_at: {toMillis: () => BASE_MILLIS},
    updatedAt: {toMillis: () => BASE_MILLIS + 9_000},
  });
  // O token do espelho ANTIGO precisa falhar: e exatamente o lost update que
  // `updated_at ?? updatedAt` permitiria.
  const stale = harness({user});
  await expectHttpsError(
    () =>
      patchHumanPersonnel(
        stale.deps,
        validRequest({expectedUpdatedAt: BASE_MILLIS}),
      ),
    "failed-precondition",
  );
  assertNoWrites(stale.recorded);

  // O token do espelho MAIS NOVO e aceito.
  const fresh = harness({user});
  await patchHumanPersonnel(
    fresh.deps,
    validRequest({expectedUpdatedAt: BASE_MILLIS + 9_000}),
  );
  assert.equal(fresh.recorded.patches.length, 1);
});

test("23. updatedAt mais antigo / updated_at mais novo: token antigo conflita", async () => {
  const user = existingUser({
    updated_at: {toMillis: () => BASE_MILLIS + 9_000},
    updatedAt: {toMillis: () => BASE_MILLIS},
  });
  const stale = harness({user});
  await expectHttpsError(
    () =>
      patchHumanPersonnel(
        stale.deps,
        validRequest({expectedUpdatedAt: BASE_MILLIS}),
      ),
    "failed-precondition",
  );
  assertNoWrites(stale.recorded);

  const fresh = harness({user});
  await patchHumanPersonnel(
    fresh.deps,
    validRequest({expectedUpdatedAt: BASE_MILLIS + 9_000}),
  );
  assert.equal(fresh.recorded.patches.length, 1);
});

test("24. um espelho ausente: o presente e a autoridade", async () => {
  const onlySnake = harness({
    user: existingUser({
      updated_at: {toMillis: () => BASE_MILLIS},
      updatedAt: undefined,
    }),
  });
  await patchHumanPersonnel(
    onlySnake.deps,
    validRequest({expectedUpdatedAt: BASE_MILLIS}),
  );
  assert.equal(onlySnake.recorded.patches.length, 1);

  const onlyCamel = harness({
    user: existingUser({
      updated_at: undefined,
      updatedAt: {toMillis: () => BASE_MILLIS},
    }),
  });
  await patchHumanPersonnel(
    onlyCamel.deps,
    validRequest({expectedUpdatedAt: BASE_MILLIS}),
  );
  assert.equal(onlyCamel.recorded.patches.length, 1);
});

test("25. ambos os espelhos ausentes + expected null e aceito", async () => {
  const {deps, recorded} = harness({
    user: existingUser({updated_at: undefined, updatedAt: undefined}),
  });
  await patchHumanPersonnel(
    deps,
    validRequest({expectedUpdatedAt: null}),
  );
  assert.equal(recorded.patches.length, 1);
});

test("26. timestamp armazenado existe + expected null conflita", async () => {
  const {deps, recorded} = harness();
  await expectHttpsError(
    () =>
      patchHumanPersonnel(deps, validRequest({expectedUpdatedAt: null})),
    "failed-precondition",
  );
  assertNoWrites(recorded);
});

test("27. expected number + nenhum timestamp armazenado conflita", async () => {
  const {deps, recorded} = harness({
    user: existingUser({updated_at: undefined, updatedAt: undefined}),
  });
  await expectHttpsError(
    () =>
      patchHumanPersonnel(
        deps,
        validRequest({expectedUpdatedAt: BASE_MILLIS}),
      ),
    "failed-precondition",
  );
  assertNoWrites(recorded);
});

test("28. token desatualizado (number diferente) conflita", async () => {
  for (const expected of [BASE_MILLIS - 1, BASE_MILLIS + 1, 0]) {
    const {deps, recorded} = harness();
    await expectHttpsError(
      () =>
        patchHumanPersonnel(
          deps,
          validRequest({expectedUpdatedAt: expected}),
        ),
      "failed-precondition",
    );
    assertNoWrites(recorded);
  }
});

test("29. conflito de concorrencia produz ZERO escrita e ZERO auditoria", async () => {
  const {deps, recorded} = harness();
  await expectHttpsError(
    () =>
      patchHumanPersonnel(
        deps,
        validRequest({
          patch: {fullName: "Outro Nome"},
          expectedUpdatedAt: BASE_MILLIS - 1000,
        }),
      ),
    "failed-precondition",
  );
  assert.equal(recorded.transactions, 1, "a transacao abre e nao escreve");
  assertNoWrites(recorded);
});

test("29b. normalizador de timestamp ARMAZENADO aceita as formas reais", async () => {
  assert.equal(storedTimestampMillis(BASE_MILLIS), BASE_MILLIS);
  assert.equal(storedTimestampMillis(new Date(BASE_MILLIS)), BASE_MILLIS);
  assert.equal(
    storedTimestampMillis({toMillis: () => BASE_MILLIS}),
    BASE_MILLIS,
  );
  assert.equal(
    storedTimestampMillis({toDate: () => new Date(BASE_MILLIS)}),
    BASE_MILLIS,
  );
  assert.equal(
    storedTimestampMillis("2023-11-14T22:13:20.000Z"),
    Date.parse("2023-11-14T22:13:20.000Z"),
  );
  assert.equal(storedTimestampMillis(null), null);
  assert.equal(storedTimestampMillis(undefined), null);
  assert.equal(storedTimestampMillis("nao-e-data"), null);
  assert.equal(storedTimestampMillis(Number.NaN), null);
  // Espelhos ilegiveis sao excluidos conservadoramente.
  assert.equal(concurrencyAuthorityMillis({updated_at: "lixo"}), null);
});

// ===========================================================================
// D. SUCCESS
// ===========================================================================

test("30. patch de pessoal bem-sucedido escreve os campos canonicos", async () => {
  const {deps, recorded} = harness();
  const result = await patchHumanPersonnel(
    deps,
    validRequest({
      patch: {
        cpf: "12345678901",
        birthDate: "1990-05-20",
        phone: "11999998888",
        institutionalEmail: "silva@gcm.com.br",
        rank: "GCM 1a Classe",
        cargo: "Adestrador",
        unit: "Canil Central",
        team: "Alfa",
        admissionDate: "2020-03-01",
        notes: "Observacao funcional",
      },
    }),
  );
  const patch = onlyPatch(recorded);

  assert.equal(patch.cpf, "12345678901");
  assert.equal(patch.birth_date, "1990-05-20");
  assert.equal(patch.telefone, "11999998888");
  assert.equal(patch.institutional_email, "silva@gcm.com.br");
  assert.equal(patch.rank, "GCM 1a Classe");
  assert.equal(patch.cargo, "Adestrador");
  assert.equal(patch.unit, "Canil Central");
  assert.equal(patch.team, "Alfa");
  assert.equal(patch.admission_date, "2020-03-01");
  assert.equal(patch.notes, "Observacao funcional");
  assert.equal(result.updated, true);
  assert.equal(result.ra, "9001");
  assert.equal(recorded.patches[0].ra, "9001");
});

test("30b. datas sao armazenadas verbatim (sem Timestamp/timezone)", async () => {
  const {deps, recorded} = harness();
  await patchHumanPersonnel(
    deps,
    validRequest({
      patch: {birthDate: "1990-05-20", admissionDate: "2020-03-01"},
    }),
  );
  const patch = onlyPatch(recorded);
  assert.equal(typeof patch.birth_date, "string");
  assert.equal(patch.birth_date, "1990-05-20");
  assert.equal(typeof patch.admission_date, "string");
  assert.equal(patch.admission_date, "2020-03-01");
});

test("30c. CPF nao sofre checksum/unicidade (apenas texto trimado)", async () => {
  const {deps, recorded} = harness();
  // CPF sintaticamente "invalido" e aceito: Create tambem aceita.
  await patchHumanPersonnel(deps, validRequest({patch: {cpf: " 000.000 "}}));
  assert.equal(onlyPatch(recorded).cpf, "000.000");
});

test("31. limpeza bem-sucedida combinada com patch", async () => {
  const {deps, recorded} = harness();
  const result = await patchHumanPersonnel(
    deps,
    validRequest({
      patch: {cargo: "Instrutor"},
      clearFields: ["phone", "notes"],
    }),
  );
  const patch = onlyPatch(recorded);
  assert.equal(patch.cargo, "Instrutor");
  assert.equal(patch.telefone, DELETE_SENTINEL);
  assert.equal(patch.phone, DELETE_SENTINEL);
  assert.equal(patch.notes, DELETE_SENTINEL);
  assert.equal(patch["observações"], DELETE_SENTINEL);
  assert.deepEqual(result.updatedFields, ["cargo"]);
  assert.deepEqual(result.clearedFields, ["phone", "notes"]);
});

test("32. espelhos de fullName sao escritos juntos", async () => {
  const {deps, recorded} = harness();
  await patchHumanPersonnel(
    deps,
    validRequest({patch: {fullName: "Maria Souza"}}),
  );
  const patch = onlyPatch(recorded);
  assert.equal(patch.name, "Maria Souza");
  assert.equal(patch.nomeCompleto, "Maria Souza");
});

test("33. espelhos de callsign sao escritos juntos", async () => {
  const {deps, recorded} = harness();
  await patchHumanPersonnel(
    deps,
    validRequest({patch: {callsign: "SOUZA"}}),
  );
  const patch = onlyPatch(recorded);
  assert.equal(patch.callsign, "SOUZA");
  assert.equal(patch.callSign, "SOUZA");
});

test("33b. callsign NAO escreve displayName de Auth nem nome_guerra", async () => {
  const {deps, recorded} = harness();
  await patchHumanPersonnel(
    deps,
    validRequest({patch: {callsign: "SOUZA"}}),
  );
  const patch = onlyPatch(recorded);
  assert.equal("displayName" in patch, false);
  assert.equal("nome_guerra" in patch, false);
});

test("34. aliases legados NAO sao reescritos so porque existem", async () => {
  const {deps, recorded} = harness();
  await patchHumanPersonnel(
    deps,
    validRequest({
      patch: {
        phone: "11999998888",
        rank: "GCM",
        unit: "Central",
        team: "Alfa",
        cargo: "Adestrador",
        notes: "obs",
        cpf: "123",
        birthDate: "1990-05-20",
        admissionDate: "2020-03-01",
      },
    }),
  );
  const patch = onlyPatch(recorded);
  for (const legacy of [
    "phone",
    "posto",
    "graduacao",
    "unidade",
    "lotação",
    "equipe",
    "função",
    "observações",
    "document",
    "birthDate",
    "admissionDate",
  ]) {
    assert.equal(
      legacy in patch,
      false,
      `alias legado ${legacy} nao deve ser escrito em patch`,
    );
  }
});

test("35+36. created_at e createdAt sao preservados (nunca no patch)", async () => {
  const {deps, recorded} = harness();
  await patchHumanPersonnel(deps, validRequest());
  const patch = onlyPatch(recorded);
  assert.equal("created_at" in patch, false);
  assert.equal("createdAt" in patch, false);
});

test("37. updated_at e updatedAt sao bumpados no MESMO instante logico", async () => {
  const {deps, recorded} = harness();
  await patchHumanPersonnel(deps, validRequest());
  const patch = onlyPatch(recorded);
  assert.equal(patch.updated_at, SERVER_TIMESTAMP);
  assert.equal(patch.updatedAt, SERVER_TIMESTAMP);
  assert.equal(
    patch.updated_at,
    patch.updatedAt,
    "os dois espelhos devem usar o mesmo sentinel",
  );
});

test("38. claim_updated_at NAO e tocado", async () => {
  const {deps, recorded} = harness();
  await patchHumanPersonnel(deps, validRequest());
  assert.equal("claim_updated_at" in onlyPatch(recorded), false);
});

test("39. auditoria appendada exatamente uma vez com action=updated", async () => {
  const {deps, recorded} = harness();
  await patchHumanPersonnel(deps, validRequest());
  assert.equal(recorded.auditEntries.length, 1);
  assert.equal(recorded.auditEntries[0].action, "updated");
  assert.equal(recorded.auditEntries[0].caller.uid, CALLER.uid);
  assert.equal(recorded.auditEntries[0].caller.ra, CALLER.ra);

  // Append (arrayUnion), nunca substituicao do historico.
  const patch = onlyPatch(recorded);
  assert.deepEqual(patch.audit_trail, {
    __arrayUnion: {action: "updated", by: CALLER.uid, by_ra: CALLER.ra},
  });
});

test("40. updatedFields usa nomes semanticos em ordem canonica", async () => {
  const {deps, recorded} = harness();
  const result = await patchHumanPersonnel(
    deps,
    validRequest({
      patch: {notes: "obs", fullName: "Maria Souza", cargo: "Adestradora"},
    }),
  );
  assert.deepEqual(result.updatedFields, ["fullName", "cargo", "notes"]);
  // Nao expõe aliases crus do Firestore.
  for (const raw of ["name", "nomeCompleto", "telefone", "birth_date"]) {
    assert.equal(result.updatedFields.includes(raw), false);
  }
  assert.equal(recorded.patches.length, 1);
});

test("41. clearedFields usa nomes semanticos em ordem canonica", async () => {
  const {deps} = harness();
  const result = await patchHumanPersonnel(
    deps,
    validRequest({
      patch: undefined,
      clearFields: ["notes", "cpf", "unit"],
    }),
  );
  assert.deepEqual(result.clearedFields, ["cpf", "unit", "notes"]);
  for (const raw of ["document", "unidade", "observações"]) {
    assert.equal(result.clearedFields.includes(raw), false);
  }
});

test("41b. resposta tem exatamente as quatro chaves do contrato", async () => {
  const {deps} = harness();
  const result = await patchHumanPersonnel(deps, validRequest());
  assert.deepEqual(Object.keys(result).sort(), [
    "clearedFields",
    "ra",
    "updated",
    "updatedFields",
  ]);
  // Nada de updatedAt / Auth / acesso na resposta.
  for (const forbidden of [
    "updatedAt",
    "updated_at",
    "uid",
    "email",
    "claims",
    "accessProfileId",
    "temporary_password",
  ]) {
    assert.equal(forbidden in result, false, `${forbidden} nao pode vazar`);
  }
});

test("41c. escrita ocorre dentro de UMA transacao (atomicidade)", async () => {
  const {deps, recorded} = harness();
  await patchHumanPersonnel(deps, validRequest());
  assert.equal(recorded.transactions, 1);
  assert.equal(recorded.patches.length, 1, "um unico patch atomico");
});

// ===========================================================================
// E. DOMAIN NEGATIVES (estruturais)
// ===========================================================================

/**
 * Conjunto FECHADO de chaves de documento que a capacidade pode escrever.
 * Qualquer chave fora disto num patch bem-sucedido e vazamento de dominio.
 */
const WRITABLE_DOCUMENT_KEYS = new Set<string>([
  // canonicos escritos
  "name",
  "nomeCompleto",
  "callsign",
  "callSign",
  "cpf",
  "birth_date",
  "telefone",
  "institutional_email",
  "rank",
  "cargo",
  "unit",
  "team",
  "admission_date",
  "notes",
  // aliases PERSONNEL removidos em limpeza explicita
  "document",
  "birthDate",
  "phone",
  "posto",
  "graduacao",
  "função",
  "unidade",
  "lotação",
  "equipe",
  "admissionDate",
  "observações",
  // metadados de servidor desta capacidade
  "updated_at",
  "updatedAt",
  "audit_trail",
]);

test("42+43. deps NAO expõem Auth nem claims (negativa estrutural)", async () => {
  const {deps} = harness();
  const exposed = Object.keys(deps).sort();
  assert.deepEqual(exposed, [
    "arrayUnion",
    "auditEntry",
    "authorize",
    "deleteField",
    "runTransaction",
    "serverTimestamp",
  ]);
  // Nenhuma capacidade de Auth/claims/acesso e injetavel.
  for (const forbidden of [
    "auth",
    "createUser",
    "updateUser",
    "deleteUser",
    "setCustomUserClaims",
    "setClaims",
    "getUserByEmail",
    "generatePasswordResetLink",
    "accessProfiles",
    "storage",
  ]) {
    assert.equal(
      forbidden in (deps as unknown as JsonMap),
      false,
      `${forbidden} nao pode existir nas deps`,
    );
  }
});

test("43b. transacao so sabe ler/escrever users/{ra}", async () => {
  const {deps} = harness();
  let exposed: string[] = [];
  await deps.runTransaction(async (tx) => {
    exposed = Object.keys(tx).sort();
    return null;
  });
  assert.deepEqual(exposed, ["getUser", "patchUser"]);
});

test("44+45+46. patch bem-sucedido nunca escreve fora do dominio Personnel", async () => {
  // Exercita simultaneamente todo patch e todo clear possiveis.
  const {deps, recorded} = harness();
  await patchHumanPersonnel(deps, {
    ra: "9001",
    expectedUpdatedAt: BASE_MILLIS,
    patch: {
      fullName: "Maria Souza",
      callsign: "SOUZA",
      cargo: "Adestradora",
      rank: "GCM",
      unit: "Central",
    },
    clearFields: [
      "cpf",
      "birthDate",
      "phone",
      "institutionalEmail",
      "team",
      "admissionDate",
      "notes",
    ],
  });
  const patch = onlyPatch(recorded);

  for (const key of Object.keys(patch)) {
    assert.equal(
      WRITABLE_DOCUMENT_KEYS.has(key),
      true,
      `chave fora do dominio Personnel no patch: ${key}`,
    );
  }

  // Negativas explicitas por dominio.
  for (const forbidden of [
    // acesso / claims
    "role",
    "roles",
    "admin",
    "accessLevel",
    "access_level",
    "accessProfile",
    "access_profile",
    "accessProfileId",
    "access_profile_id",
    "access_scope",
    "accessScope",
    "claim_role",
    "claim_updated_at",
    "mobile_access",
    "web_access",
    "app_access",
    // Auth
    "email",
    "uid",
    "auth_uid",
    "authUid",
    "displayName",
    "password",
    "temporary_password",
    "disabled",
    // treino
    "is_k9_instructor",
    "training_instructor",
    "training_role",
    "specialties",
    "certifications",
    // turno / binomio
    "shift_group_id",
    "shiftGroupId",
    "shift_label",
    "shiftLabel",
    "vehicle",
    "crew",
    "binomial",
    "handlerRa",
    "handler_id",
    // foto / Health
    "photoUrl",
    "photo_url",
    "profileImageUrl",
    "health",
    "health_summary",
    // ciclo de vida
    "active",
    "status",
    "archived_at",
    "deleted_at",
    "deleted_by",
    // metadados de criacao
    "created_at",
    "createdAt",
  ]) {
    assert.equal(
      forbidden in patch,
      false,
      `dominio externo tocado: ${forbidden}`,
    );
  }
});
