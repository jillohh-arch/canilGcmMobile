/**
 * Testes do contrato de adminPatchK9Identity.
 *
 * Usa o runner nativo do Node (node:test) — o diretorio functions/ nao possui
 * framework de teste, e este gate nao autoriza adicionar dependencias.
 *
 * As dependencias de Firestore/autorizacao sao injetadas, portanto os testes
 * exercitam o contrato real (autorizacao, fronteira de dominio, concorrencia,
 * unicidade) sem emulador e sem I/O.
 */

import * as assert from "node:assert/strict";
import {test} from "node:test";
import {HttpsError} from "firebase-functions/v2/https";

import {
  DogSnapshotLike,
  K9IdentityPatchDeps,
  K9IdentityTransaction,
  PatchCaller,
  patchK9Identity,
} from "../src/admin_patch_k9_identity";

type JsonMap = Record<string, unknown>;

const CALLER: PatchCaller = {
  uid: "uid-admin",
  email: "1234@gcm.com.br",
  ra: "1234",
  name: "Admin Teste",
};

/** Stub de Timestamp do Firestore: apenas toMillis e usado pelo contrato. */
function ts(millis: number): {toMillis(): number} {
  return {toMillis: () => millis};
}

const SERVER_TIMESTAMP = Symbol("serverTimestamp");
const STORED_UPDATED_AT_MILLIS = 1_700_000_000_000;

/** Documento canonico de K9 ativo, com campos de outros dominios presentes. */
function activeDog(overrides: JsonMap = {}): JsonMap {
  return {
    id: "dog-1",
    name: "Bono",
    breed: "Pastor Belga Malinois",
    sex: "M",
    dateOfBirth: "2020-05-10T15:00:00.000Z",
    registrationNumber: "K9-001",
    matricula: "K9-001",
    status: "Operacional",
    active: true,
    cor: "Fulvo",
    microchip: "981000000000001",
    porte: "Grande",
    observacoes: "Observacao antiga.",
    profileImageUrl: "https://example.invalid/bono.jpg",
    // Dominios que este patch nunca pode tocar:
    conductorRa: "5678",
    weight: 32.5,
    idealWeightMin: 30,
    idealWeightMax: 35,
    condicaoCorporal: "ideal",
    specialties: ["deteccao"],
    updated_at: ts(STORED_UPDATED_AT_MILLIS),
    updatedAt: ts(STORED_UPDATED_AT_MILLIS),
    ...overrides,
  };
}

interface Recorded {
  dogPatches: Array<{dogId: string; patch: JsonMap}>;
  auditLogs: JsonMap[];
  authorizeCalls: number;
  registrationLookups: string[];
}

interface HarnessOptions {
  dog?: JsonMap | null;
  registrationOwners?: Record<string, string[]>;
  authorizeError?: HttpsError;
}

function harness(options: HarnessOptions = {}): {
  deps: K9IdentityPatchDeps;
  recorded: Recorded;
} {
  const recorded: Recorded = {
    dogPatches: [],
    auditLogs: [],
    authorizeCalls: 0,
    registrationLookups: [],
  };
  const dog = options.dog === undefined ? activeDog() : options.dog;

  const deps: K9IdentityPatchDeps = {
    authorize: async () => {
      recorded.authorizeCalls += 1;
      if (options.authorizeError) throw options.authorizeError;
      return CALLER;
    },
    runTransaction: async (handler) => {
      const tx: K9IdentityTransaction = {
        getDog: async (): Promise<DogSnapshotLike> => ({
          exists: dog !== null,
          data: () => (dog === null ? undefined : dog),
        }),
        findRegistrationOwners: async (registrationNumber) => {
          recorded.registrationLookups.push(registrationNumber);
          return options.registrationOwners?.[registrationNumber] ?? [];
        },
        patchDog: (dogId, patch) => {
          recorded.dogPatches.push({dogId, patch});
        },
        writeAuditLog: (entry) => {
          recorded.auditLogs.push(entry);
        },
      };
      return handler(tx);
    },
    serverTimestamp: () => SERVER_TIMESTAMP,
    auditEntry: (action, caller) => ({action, by: caller.uid, by_ra: caller.ra}),
    arrayUnion: (value) => ({__arrayUnion: value}),
  };

  return {deps, recorded};
}

function validRequest(overrides: JsonMap = {}): JsonMap {
  return {
    dogId: "dog-1",
    expectedUpdatedAt: STORED_UPDATED_AT_MILLIS,
    patch: {name: "Bono II"},
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
  assert.deepEqual(recorded.dogPatches, [], "nao deve haver escrita no K9");
  assert.deepEqual(recorded.auditLogs, [], "nao deve haver escrita de auditoria");
}

function onlyPatch(recorded: Recorded): JsonMap {
  assert.equal(recorded.dogPatches.length, 1, "esperava exatamente um patch");
  return recorded.dogPatches[0].patch;
}

/** Chaves de metadados sempre autoradas pelo servidor. */
const SERVER_METADATA_KEYS = new Set(["updated_at", "updatedAt", "audit_trail"]);

// --- autorizacao -----------------------------------------------------------

test("chamada nao autenticada e recusada sem escrever", async () => {
  const {deps, recorded} = harness({
    authorizeError: new HttpsError("unauthenticated", "Autenticacao obrigatoria."),
  });
  await expectHttpsError(
    () => patchK9Identity(deps, validRequest()),
    "unauthenticated",
  );
  assertNoWrites(recorded);
});

test("caller sem k9.edit e recusado sem escrever", async () => {
  const {deps, recorded} = harness({
    authorizeError: new HttpsError("permission-denied", "Permissao k9.edit ausente."),
  });
  await expectHttpsError(
    () => patchK9Identity(deps, validRequest()),
    "permission-denied",
  );
  assertNoWrites(recorded);
});

test("autorizacao acontece antes de qualquer validacao de payload", async () => {
  const {deps, recorded} = harness({
    authorizeError: new HttpsError("permission-denied", "Permissao k9.edit ausente."),
  });
  await expectHttpsError(
    () => patchK9Identity(deps, {lixo: true}),
    "permission-denied",
  );
  assert.equal(recorded.authorizeCalls, 1);
  assertNoWrites(recorded);
});

// --- campos de identidade --------------------------------------------------

test("campo de identidade permitido e atualizado", async () => {
  const {deps, recorded} = harness();
  const result = await patchK9Identity(deps, validRequest({patch: {name: "Bono II"}}));

  const patch = onlyPatch(recorded);
  assert.equal(patch.name, "Bono II");
  assert.deepEqual(result.updatedFields, ["name"]);
  assert.deepEqual(result.clearedFields, []);
});

test("campo omitido e preservado (nao aparece no patch)", async () => {
  const {deps, recorded} = harness();
  await patchK9Identity(deps, validRequest({patch: {name: "Bono II"}}));

  const patch = onlyPatch(recorded);
  const writtenIdentityKeys = Object.keys(patch).filter(
    (key) => !SERVER_METADATA_KEYS.has(key),
  );
  assert.deepEqual(writtenIdentityKeys, ["name"]);
  for (const untouched of [
    "breed",
    "sex",
    "dateOfBirth",
    "registrationNumber",
    "matricula",
    "cor",
    "microchip",
    "porte",
    "observacoes",
    "profileImageUrl",
  ]) {
    assert.ok(!(untouched in patch), `${untouched} nao deveria ser escrito`);
  }
});

test("birthDate e normalizado para o formato canonico do backend", async () => {
  const {deps, recorded} = harness();
  await patchK9Identity(deps, validRequest({patch: {birthDate: "2021-03-04"}}));

  const patch = onlyPatch(recorded);
  assert.equal(patch.dateOfBirth, new Date("2021-03-04T12:00:00").toISOString());
  assert.ok(!("birthDate" in patch), "wire name nao deve vazar para o documento");
});

test("birthDate invalido e recusado", async () => {
  const {deps, recorded} = harness();
  await expectHttpsError(
    () => patchK9Identity(deps, validRequest({patch: {birthDate: "31/02/2021"}})),
    "invalid-argument",
  );
  assertNoWrites(recorded);
});

test("campos opcionais usam os nomes canonicos do documento", async () => {
  const {deps, recorded} = harness();
  await patchK9Identity(
    deps,
    validRequest({
      patch: {
        color: "Preto",
        size: "Medio",
        notes: "Nova observacao.",
        microchip: "981000000000002",
        profileImageUrl: "https://example.invalid/novo.jpg",
      },
    }),
  );

  const patch = onlyPatch(recorded);
  assert.equal(patch.cor, "Preto");
  assert.equal(patch.porte, "Medio");
  assert.equal(patch.observacoes, "Nova observacao.");
  assert.equal(patch.microchip, "981000000000002");
  assert.equal(patch.profileImageUrl, "https://example.invalid/novo.jpg");
});

test("valor nao textual em campo de identidade e recusado", async () => {
  const {deps, recorded} = harness();
  await expectHttpsError(
    () => patchK9Identity(deps, validRequest({patch: {name: 42}})),
    "invalid-argument",
  );
  assertNoWrites(recorded);
});

test("string vazia nao serve como limpeza implicita", async () => {
  const {deps, recorded} = harness();
  await expectHttpsError(
    () => patchK9Identity(deps, validRequest({patch: {color: "   "}})),
    "invalid-argument",
  );
  assertNoWrites(recorded);
});

// --- clearFields -----------------------------------------------------------

test("limpeza de campo opcional via clearFields grava null", async () => {
  const {deps, recorded} = harness();
  const result = await patchK9Identity(
    deps,
    validRequest({patch: {}, clearFields: ["microchip", "notes"]}),
  );

  const patch = onlyPatch(recorded);
  assert.equal(patch.microchip, null);
  assert.equal(patch.observacoes, null);
  assert.deepEqual(result.clearedFields, ["microchip", "notes"]);
  assert.deepEqual(result.updatedFields, []);
});

test("null enviado no patch e recusado (sem semantica null-as-clear)", async () => {
  const {deps, recorded} = harness();
  const error = await expectHttpsError(
    () => patchK9Identity(deps, validRequest({patch: {microchip: null}})),
    "invalid-argument",
  );
  assert.match(error.message, /clearFields/);
  assertNoWrites(recorded);
});

test("limpeza de campo obrigatorio e recusada", async () => {
  for (const field of ["name", "registrationNumber", "breed", "sex", "birthDate"]) {
    const {deps, recorded} = harness();
    await expectHttpsError(
      () => patchK9Identity(deps, validRequest({patch: {}, clearFields: [field]})),
      "invalid-argument",
    );
    assertNoWrites(recorded);
  }
});

test("mesmo campo em patch e clearFields e recusado", async () => {
  const {deps, recorded} = harness();
  await expectHttpsError(
    () =>
      patchK9Identity(
        deps,
        validRequest({patch: {color: "Preto"}, clearFields: ["color"]}),
      ),
    "invalid-argument",
  );
  assertNoWrites(recorded);
});

// --- fronteira de dominio (fail closed) ------------------------------------

test("campos de outros dominios sao recusados no patch", async () => {
  const forbidden: JsonMap = {
    conductorRa: "9999",
    weight: 40,
    idealWeightMin: 20,
    readiness: {state: "ready"},
    restrictions: ["nenhuma"],
    specialties: ["patrulha"],
    training: {level: 3},
    operationalStatus: "Operacional",
    status: "Operacional",
    active: true,
    physicalCondition: "magro",
    archived_at: null,
    audit_trail: [],
    id: "outro-id",
    updated_at: 123,
  };
  for (const [field, value] of Object.entries(forbidden)) {
    const {deps, recorded} = harness();
    await expectHttpsError(
      () => patchK9Identity(deps, validRequest({patch: {[field]: value}})),
      "invalid-argument",
    );
    assertNoWrites(recorded);
  }
});

test("campos de outros dominios sao recusados em clearFields", async () => {
  for (const field of ["conductorRa", "weight", "specialties", "active"]) {
    const {deps, recorded} = harness();
    await expectHttpsError(
      () => patchK9Identity(deps, validRequest({patch: {}, clearFields: [field]})),
      "invalid-argument",
    );
    assertNoWrites(recorded);
  }
});

test("campo desconhecido nao e ignorado silenciosamente", async () => {
  const {deps, recorded} = harness();
  await expectHttpsError(
    () => patchK9Identity(deps, validRequest({patch: {campoInventado: "x"}})),
    "invalid-argument",
  );
  assertNoWrites(recorded);
});

test("chave desconhecida no topo do payload e recusada", async () => {
  const {deps, recorded} = harness();
  await expectHttpsError(
    () => patchK9Identity(deps, validRequest({mode: "edit"})),
    "invalid-argument",
  );
  assertNoWrites(recorded);
});

test("payload malformado e recusado", async () => {
  for (const raw of [null, "texto", 7, []]) {
    const {deps, recorded} = harness();
    await expectHttpsError(() => patchK9Identity(deps, raw), "invalid-argument");
    assertNoWrites(recorded);
  }
});

test("patch e clearFields vazios sao recusados", async () => {
  const {deps, recorded} = harness();
  await expectHttpsError(
    () => patchK9Identity(deps, validRequest({patch: {}, clearFields: []})),
    "invalid-argument",
  );
  assertNoWrites(recorded);
});

test("patch de identidade nunca escreve campos de outros dominios", async () => {
  const {deps, recorded} = harness();
  await patchK9Identity(
    deps,
    validRequest({
      patch: {
        name: "Bono II",
        breed: "Malinois",
        sex: "M",
        birthDate: "2021-03-04",
        registrationNumber: "K9-002",
        color: "Preto",
        microchip: "981000000000002",
        size: "Grande",
        notes: "Nota.",
        profileImageUrl: "https://example.invalid/x.jpg",
      },
    }),
  );

  const patch = onlyPatch(recorded);
  const allowedDocumentKeys = new Set([
    "name",
    "breed",
    "sex",
    "dateOfBirth",
    "registrationNumber",
    "matricula",
    "cor",
    "microchip",
    "porte",
    "observacoes",
    "profileImageUrl",
    ...SERVER_METADATA_KEYS,
  ]);
  for (const key of Object.keys(patch)) {
    assert.ok(allowedDocumentKeys.has(key), `chave inesperada gravada: ${key}`);
  }
  for (const forbidden of [
    "active",
    "status",
    "conductorRa",
    "weight",
    "idealWeightMin",
    "idealWeightMax",
    "condicaoCorporal",
    "specialties",
    "readiness",
    "restrictions",
    "deleted_at",
    "archived_at",
  ]) {
    assert.ok(!(forbidden in patch), `${forbidden} nao pode ser escrito`);
  }
});

test("nenhum patch bem-sucedido escreve active nem reativa o K9", async () => {
  const {deps, recorded} = harness();
  await patchK9Identity(deps, validRequest({patch: {name: "Bono II"}}));
  const patch = onlyPatch(recorded);
  assert.ok(!("active" in patch), "active nunca pode ser escrito");
  assert.ok(!("status" in patch), "status nunca pode ser escrito");
  assert.ok(!("deleted_at" in patch));
  assert.ok(!("deleted_by" in patch));
});

// --- ciclo de vida / arquivamento -----------------------------------------

test("K9 inexistente retorna not-found", async () => {
  const {deps, recorded} = harness({dog: null});
  await expectHttpsError(() => patchK9Identity(deps, validRequest()), "not-found");
  assertNoWrites(recorded);
});

test("K9 arquivado/inativo e recusado por qualquer marca canonica", async () => {
  const archivedVariants: JsonMap[] = [
    {active: false},
    {status: "Inativo"},
    {status: "inactive"},
    {deleted_at: ts(STORED_UPDATED_AT_MILLIS)},
    {archived_at: ts(STORED_UPDATED_AT_MILLIS)},
  ];
  for (const overrides of archivedVariants) {
    const {deps, recorded} = harness({dog: activeDog(overrides)});
    await expectHttpsError(
      () => patchK9Identity(deps, validRequest()),
      "failed-precondition",
    );
    assertNoWrites(recorded);
  }
});

test("K9 arquivado e recusado antes de checar concorrencia ou unicidade", async () => {
  const {deps, recorded} = harness({dog: activeDog({active: false})});
  await expectHttpsError(
    () =>
      patchK9Identity(
        deps,
        validRequest({
          expectedUpdatedAt: 1,
          patch: {registrationNumber: "K9-999"},
        }),
      ),
    "failed-precondition",
  );
  assert.deepEqual(recorded.registrationLookups, []);
  assertNoWrites(recorded);
});

// --- concorrencia otimista -------------------------------------------------

test("expectedUpdatedAt correto tem sucesso", async () => {
  const {deps, recorded} = harness();
  const result = await patchK9Identity(
    deps,
    validRequest({expectedUpdatedAt: STORED_UPDATED_AT_MILLIS}),
  );
  assert.equal(result.id, "dog-1");
  assert.equal(recorded.dogPatches.length, 1);
});

test("expectedUpdatedAt aceita ISO e Timestamp equivalentes", async () => {
  for (const expected of [
    new Date(STORED_UPDATED_AT_MILLIS).toISOString(),
    ts(STORED_UPDATED_AT_MILLIS),
  ] as unknown[]) {
    const {deps, recorded} = harness();
    await patchK9Identity(deps, validRequest({expectedUpdatedAt: expected}));
    assert.equal(recorded.dogPatches.length, 1);
  }
});

test("expectedUpdatedAt defasado falha sem escrita parcial", async () => {
  const {deps, recorded} = harness();
  await expectHttpsError(
    () =>
      patchK9Identity(
        deps,
        validRequest({expectedUpdatedAt: STORED_UPDATED_AT_MILLIS - 5_000}),
      ),
    "failed-precondition",
  );
  assertNoWrites(recorded);
});

test("expectedUpdatedAt ausente e recusado", async () => {
  const {deps, recorded} = harness();
  await expectHttpsError(
    () => patchK9Identity(deps, {dogId: "dog-1", patch: {name: "Bono II"}}),
    "invalid-argument",
  );
  assertNoWrites(recorded);
});

test("expectedUpdatedAt null so vale para documento sem updated_at", async () => {
  const {deps: staleDeps, recorded: staleRecorded} = harness();
  await expectHttpsError(
    () => patchK9Identity(staleDeps, validRequest({expectedUpdatedAt: null})),
    "failed-precondition",
  );
  assertNoWrites(staleRecorded);

  const dogWithoutTimestamp = activeDog();
  delete dogWithoutTimestamp.updated_at;
  delete dogWithoutTimestamp.updatedAt;
  const {deps, recorded} = harness({dog: dogWithoutTimestamp});
  await patchK9Identity(deps, validRequest({expectedUpdatedAt: null}));
  assert.equal(recorded.dogPatches.length, 1);
});

test("expectedUpdatedAt invalido e recusado", async () => {
  const {deps, recorded} = harness();
  await expectHttpsError(
    () => patchK9Identity(deps, validRequest({expectedUpdatedAt: "nao-e-data"})),
    "invalid-argument",
  );
  assertNoWrites(recorded);
});

// --- unicidade de matricula -----------------------------------------------

test("matricula duplicada em outro K9 e recusada", async () => {
  const {deps, recorded} = harness({
    registrationOwners: {"K9-002": ["dog-2"]},
  });
  await expectHttpsError(
    () => patchK9Identity(deps, validRequest({patch: {registrationNumber: "K9-002"}})),
    "already-exists",
  );
  assertNoWrites(recorded);
});

test("mesma matricula do proprio K9 nao dispara conflito nem consulta", async () => {
  const {deps, recorded} = harness({
    registrationOwners: {"K9-001": ["dog-1"]},
  });
  await patchK9Identity(deps, validRequest({patch: {registrationNumber: "K9-001"}}));
  assert.deepEqual(recorded.registrationLookups, []);
  assert.equal(recorded.dogPatches.length, 1);
});

test("matricula nova grava tambem o espelho legado matricula", async () => {
  const {deps, recorded} = harness();
  await patchK9Identity(deps, validRequest({patch: {registrationNumber: "K9-003"}}));

  const patch = onlyPatch(recorded);
  assert.equal(patch.registrationNumber, "K9-003");
  assert.equal(patch.matricula, "K9-003");
  assert.deepEqual(recorded.registrationLookups, ["K9-003"]);
});

test("consulta de unicidade ignora o proprio documento", async () => {
  const {deps, recorded} = harness({
    registrationOwners: {"K9-003": ["dog-1"]},
  });
  await patchK9Identity(deps, validRequest({patch: {registrationNumber: "K9-003"}}));
  assert.equal(recorded.dogPatches.length, 1);
});

// --- metadados de servidor e auditoria ------------------------------------

test("updated_at e autorado pelo servidor e auditoria e registrada", async () => {
  const {deps, recorded} = harness();
  await patchK9Identity(
    deps,
    validRequest({patch: {name: "Bono II"}, clearFields: ["microchip"]}),
  );

  const patch = onlyPatch(recorded);
  assert.equal(patch.updated_at, SERVER_TIMESTAMP);
  assert.equal(patch.updatedAt, SERVER_TIMESTAMP);
  assert.deepEqual(patch.audit_trail, {
    __arrayUnion: {action: "updated", by: CALLER.uid, by_ra: CALLER.ra},
  });

  assert.equal(recorded.auditLogs.length, 1);
  const log = recorded.auditLogs[0];
  assert.equal(log.action, "k9_identity_patched");
  assert.equal(log.entity_type, "dog");
  assert.equal(log.entity_id, "dog-1");
  assert.deepEqual(log.metadata, {
    updated_fields: ["name"],
    cleared_fields: ["microchip"],
  });
});

// --- autoridade de concorrencia entre os dois espelhos de timestamp --------
//
// O documento `dogs/{id}` e escrito por origens que NAO mantem os dois
// espelhos em sincronia:
// - adminUpsertK9 / adminArchiveK9 / adminCreateK9WeightRecord: ambos;
// - generateNutritionAiInsight: somente updated_at (snake);
// - mobile dog_service.dart (saveDog, updateDogWeight, deleteDog,
//   updateDogDates): somente updatedAt (camel).
//
// Portanto um unico campo nao pode ser autoridade: se o espelho lido estiver
// defasado, um lost update passa silenciosamente. A autoridade e o MAIS NOVO
// entre os dois.

const NEWER_MILLIS = STORED_UPDATED_AT_MILLIS + 60_000;

test("espelho camelCase mais novo invalida precondicao defasada", async () => {
  // Cenario mobile: saveDog bumpou apenas updatedAt.
  const dog = activeDog({
    updated_at: ts(STORED_UPDATED_AT_MILLIS),
    updatedAt: ts(NEWER_MILLIS),
  });
  const {deps, recorded} = harness({dog});
  await expectHttpsError(
    () =>
      patchK9Identity(
        deps,
        validRequest({expectedUpdatedAt: STORED_UPDATED_AT_MILLIS}),
      ),
    "failed-precondition",
  );
  assertNoWrites(recorded);
});

test("espelho snake_case mais novo invalida precondicao defasada", async () => {
  // Cenario generateNutritionAiInsight: bumpou apenas updated_at.
  const dog = activeDog({
    updated_at: ts(NEWER_MILLIS),
    updatedAt: ts(STORED_UPDATED_AT_MILLIS),
  });
  const {deps, recorded} = harness({dog});
  await expectHttpsError(
    () =>
      patchK9Identity(
        deps,
        validRequest({expectedUpdatedAt: STORED_UPDATED_AT_MILLIS}),
      ),
    "failed-precondition",
  );
  assertNoWrites(recorded);
});

test("timestamp mais novo entre os espelhos e aceito como autoridade", async () => {
  for (const dog of [
    activeDog({updated_at: ts(STORED_UPDATED_AT_MILLIS), updatedAt: ts(NEWER_MILLIS)}),
    activeDog({updated_at: ts(NEWER_MILLIS), updatedAt: ts(STORED_UPDATED_AT_MILLIS)}),
  ]) {
    const {deps, recorded} = harness({dog});
    await patchK9Identity(deps, validRequest({expectedUpdatedAt: NEWER_MILLIS}));
    assert.equal(recorded.dogPatches.length, 1);
  }
});

test("apenas um espelho presente continua sendo autoridade", async () => {
  const camelOnly = activeDog({updatedAt: ts(NEWER_MILLIS)});
  delete camelOnly.updated_at;
  const {deps, recorded} = harness({dog: camelOnly});
  await patchK9Identity(deps, validRequest({expectedUpdatedAt: NEWER_MILLIS}));
  assert.equal(recorded.dogPatches.length, 1);

  const snakeOnly = activeDog({updated_at: ts(NEWER_MILLIS)});
  delete snakeOnly.updatedAt;
  const {deps: d2, recorded: r2} = harness({dog: snakeOnly});
  await expectHttpsError(
    () =>
      patchK9Identity(
        d2,
        validRequest({expectedUpdatedAt: STORED_UPDATED_AT_MILLIS}),
      ),
    "failed-precondition",
  );
  assertNoWrites(r2);
});

test("patch bem-sucedido bump os dois espelhos de timestamp", async () => {
  const {deps, recorded} = harness();
  await patchK9Identity(deps, validRequest());
  const patch = onlyPatch(recorded);
  assert.equal(patch.updated_at, SERVER_TIMESTAMP);
  assert.equal(patch.updatedAt, SERVER_TIMESTAMP);
});

// --- coberturas adicionais pedidas pelo E2 --------------------------------

test("patch de color preserva os demais dominios", async () => {
  const {deps, recorded} = harness();
  await patchK9Identity(deps, validRequest({patch: {color: "Preto"}}));
  const patch = onlyPatch(recorded);
  const identityKeys = Object.keys(patch).filter(
    (key) => !SERVER_METADATA_KEYS.has(key),
  );
  assert.deepEqual(identityKeys, ["cor"]);
  for (const untouched of [
    "weight",
    "conductorRa",
    "specialties",
    "condicaoCorporal",
    "active",
    "status",
  ]) {
    assert.ok(!(untouched in patch), `${untouched} nao deveria ser escrito`);
  }
});

test("referencia de foto pode ser limpa explicitamente", async () => {
  const {deps, recorded} = harness();
  const result = await patchK9Identity(
    deps,
    validRequest({patch: {}, clearFields: ["profileImageUrl"]}),
  );
  const patch = onlyPatch(recorded);
  assert.equal(patch.profileImageUrl, null);
  assert.deepEqual(result.clearedFields, ["profileImageUrl"]);
});

test("dogId invalido e recusado", async () => {
  for (const dogId of ["", "   ", "dogs/dog-1", "dog 1"]) {
    const {deps, recorded} = harness();
    await expectHttpsError(
      () => patchK9Identity(deps, validRequest({dogId})),
      "invalid-argument",
    );
    assertNoWrites(recorded);
  }
});
