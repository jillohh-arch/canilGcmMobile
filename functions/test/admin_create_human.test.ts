/**
 * Testes do contrato de adminCreateHuman (cadastro de pessoal-only).
 *
 * Usa o runner nativo do Node (node:test), como admin_patch_k9_identity.test.ts.
 * As dependencias (autorizacao, escrita create-only, timestamp, auditoria) sao
 * injetadas, portanto os testes exercitam o contrato real (autorizacao,
 * fronteira de dominio, create-only/unicidade, ciclo de vida, mapeamento de
 * persistencia) sem emulador e sem I/O.
 */

import * as assert from "node:assert/strict";
import {test} from "node:test";
import {HttpsError} from "firebase-functions/v2/https";

import {
  createHuman,
  CreateHumanCaller,
  CreateHumanDeps,
  DocumentAlreadyExistsError,
} from "../src/admin_create_human";

type JsonMap = Record<string, unknown>;

const CALLER: CreateHumanCaller = {
  uid: "uid-admin",
  email: "1234@gcm.com.br",
  ra: "1234",
  name: "Admin Teste",
};

const SERVER_TIMESTAMP = Symbol("serverTimestamp");

interface Recorded {
  createdDocs: Array<{ra: string; payload: JsonMap}>;
  authorizeCalls: number;
}

interface HarnessOptions {
  authorizeError?: HttpsError;
  existingRas?: Set<string>;
}

function harness(options: HarnessOptions = {}): {
  deps: CreateHumanDeps;
  recorded: Recorded;
} {
  const recorded: Recorded = {
    createdDocs: [],
    authorizeCalls: 0,
  };
  const existing = options.existingRas ?? new Set<string>();

  const deps: CreateHumanDeps = {
    authorize: async () => {
      recorded.authorizeCalls += 1;
      if (options.authorizeError) throw options.authorizeError;
      return CALLER;
    },
    createUserDoc: async (ra, payload) => {
      if (existing.has(ra)) {
        // Espelha a falha atomica de DocumentReference.create().
        throw new DocumentAlreadyExistsError();
      }
      existing.add(ra);
      recorded.createdDocs.push({ra, payload});
    },
    serverTimestamp: () => SERVER_TIMESTAMP,
    auditEntry: (action, caller) => ({action, by: caller.uid, by_ra: caller.ra}),
  };

  return {deps, recorded};
}

function validRequest(overrides: JsonMap = {}): JsonMap {
  return {
    ra: "9001",
    fullName: "Joao da Silva",
    callsign: "Silva",
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
  // A unica escrita persistente e o create() de users/{ra}. auditEntry e um
  // builder puro (chamado ao montar o payload), nao uma escrita — por isso a
  // invariante "sem escrita" e "nenhum documento criado".
  assert.deepEqual(recorded.createdDocs, [], "nao deve haver escrita de usuario");
}

function onlyDoc(recorded: Recorded): JsonMap {
  assert.equal(recorded.createdDocs.length, 1, "esperava exatamente um create");
  return recorded.createdDocs[0].payload;
}

// Chaves de metadados/ciclo de vida sempre autoradas pelo servidor.
const SERVER_KEYS = new Set([
  "active",
  "status",
  "created_at",
  "createdAt",
  "updated_at",
  "updatedAt",
  "audit_trail",
]);

// --- autorizacao -----------------------------------------------------------

test("A. payload minimo valido cria o registro", async () => {
  const {deps, recorded} = harness();
  const result = await createHuman(deps, validRequest());

  assert.equal(recorded.createdDocs.length, 1);
  assert.equal(recorded.createdDocs[0].ra, "9001");
  assert.deepEqual(result, {
    ra: "9001",
    created: true,
  });
});

test("B. payload com todos os opcionais mapeia persistencia canonica", async () => {
  const {deps, recorded} = harness();
  await createHuman(
    deps,
    validRequest({
      cpf: "12345678900",
      birthDate: "1990-05-10",
      phone: "11999998888",
      institutionalEmail: "silva@gcm.com.br",
      rank: "Sargento",
      cargo: "Condutor",
      unit: "Canil Central",
      team: "Alfa",
      admissionDate: "2015-03-01",
      notes: "Observacao funcional.",
    }),
  );

  const doc = onlyDoc(recorded);
  // Identidade obrigatoria + espelhos.
  assert.equal(doc.name, "Joao da Silva");
  assert.equal(doc.nomeCompleto, "Joao da Silva");
  assert.equal(doc.callsign, "Silva");
  assert.equal(doc.callSign, "Silva");
  assert.equal(doc.ra, "9001");
  // Opcionais nos nomes canonicos.
  assert.equal(doc.cpf, "12345678900");
  assert.equal(doc.birth_date, "1990-05-10");
  assert.equal(doc.telefone, "11999998888");
  assert.equal(doc.institutional_email, "silva@gcm.com.br");
  assert.equal(doc.rank, "Sargento");
  assert.equal(doc.cargo, "Condutor");
  assert.equal(doc.unit, "Canil Central");
  assert.equal(doc.team, "Alfa");
  assert.equal(doc.admission_date, "2015-03-01");
  assert.equal(doc.notes, "Observacao funcional.");
  // Wire names sem campo canonico homonimo nao devem vazar para o documento.
  // (callsign e um campo canonico legitimo do documento, por isso nao entra.)
  for (const wire of [
    "fullName",
    "birthDate",
    "phone",
    "institutionalEmail",
    "admissionDate",
  ]) {
    assert.ok(!(wire in doc), `wire name ${wire} nao deve ser gravado`);
  }
});

test("C. RA duplicado retorna already-exists e nao sobrescreve", async () => {
  const {deps, recorded} = harness({existingRas: new Set(["9001"])});
  await expectHttpsError(() => createHuman(deps, validRequest()), "already-exists");
  assertNoWrites(recorded);
});

test("D. ra ausente e invalid-argument", async () => {
  const {deps, recorded} = harness();
  const req = validRequest();
  delete req.ra;
  await expectHttpsError(() => createHuman(deps, req), "invalid-argument");
  assertNoWrites(recorded);
});

test("E. RA invalido e invalid-argument", async () => {
  for (const bad of ["abc", "12", "123456789012345", "90-01", ""]) {
    const {deps, recorded} = harness();
    await expectHttpsError(
      () => createHuman(deps, validRequest({ra: bad})),
      "invalid-argument",
    );
    assertNoWrites(recorded);
  }
});

test("F. fullName ausente e invalid-argument", async () => {
  const {deps, recorded} = harness();
  const req = validRequest();
  delete req.fullName;
  await expectHttpsError(() => createHuman(deps, req), "invalid-argument");
  assertNoWrites(recorded);
});

test("G. callsign ausente e invalid-argument", async () => {
  const {deps, recorded} = harness();
  const req = validRequest();
  delete req.callsign;
  await expectHttpsError(() => createHuman(deps, req), "invalid-argument");
  assertNoWrites(recorded);
});

test("H. null explicito em qualquer campo e invalid-argument", async () => {
  const fields = [
    "ra",
    "fullName",
    "callsign",
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
  ];
  for (const field of fields) {
    const {deps, recorded} = harness();
    await expectHttpsError(
      () => createHuman(deps, validRequest({[field]: null})),
      "invalid-argument",
    );
    assertNoWrites(recorded);
  }
});

test("I. chave desconhecida e invalid-argument", async () => {
  const {deps, recorded} = harness();
  await expectHttpsError(
    () => createHuman(deps, validRequest({campoInventado: "x"})),
    "invalid-argument",
  );
  assertNoWrites(recorded);
});

// --- J..S: fronteira de dominio (fail closed) ------------------------------

test("J. accessProfileId e recusado (dominio acesso)", async () => {
  const {deps, recorded} = harness();
  await expectHttpsError(
    () => createHuman(deps, validRequest({accessProfileId: "operador_k9"})),
    "invalid-argument",
  );
  assertNoWrites(recorded);
});

test("K. roles e recusado", async () => {
  const {deps, recorded} = harness();
  await expectHttpsError(
    () => createHuman(deps, validRequest({roles: ["admin"]})),
    "invalid-argument",
  );
  assertNoWrites(recorded);
});

test("L. auth_uid e recusado", async () => {
  const {deps, recorded} = harness();
  await expectHttpsError(
    () => createHuman(deps, validRequest({auth_uid: "uid-x"})),
    "invalid-argument",
  );
  assertNoWrites(recorded);
});

test("M. password/temporary_password sao recusados", async () => {
  for (const field of ["password", "temporary_password", "temporaryPassword"]) {
    const {deps, recorded} = harness();
    await expectHttpsError(
      () => createHuman(deps, validRequest({[field]: "segredo123"})),
      "invalid-argument",
    );
    assertNoWrites(recorded);
  }
});

test("N. specialties e recusado", async () => {
  const {deps, recorded} = harness();
  await expectHttpsError(
    () => createHuman(deps, validRequest({specialties: ["Condutor K9"]})),
    "invalid-argument",
  );
  assertNoWrites(recorded);
});

test("O. isK9Instructor e recusado", async () => {
  for (const field of ["isK9Instructor", "is_k9_instructor", "training_role"]) {
    const {deps, recorded} = harness();
    await expectHttpsError(
      () => createHuman(deps, validRequest({[field]: true})),
      "invalid-argument",
    );
    assertNoWrites(recorded);
  }
});

test("P. shiftGroupId e recusado", async () => {
  for (const field of ["shiftGroupId", "shift_group_id", "shiftLabel"]) {
    const {deps, recorded} = harness();
    await expectHttpsError(
      () => createHuman(deps, validRequest({[field]: "grupo-1"})),
      "invalid-argument",
    );
    assertNoWrites(recorded);
  }
});

test("Q. campos de binomio/conducao sao recusados", async () => {
  for (const field of ["conductorRa", "handlerRa", "handlerId", "binomial"]) {
    const {deps, recorded} = harness();
    await expectHttpsError(
      () => createHuman(deps, validRequest({[field]: "5678"})),
      "invalid-argument",
    );
    assertNoWrites(recorded);
  }
});

test("R. lifecycle active/status enviados sao recusados", async () => {
  for (const field of ["active", "status", "archived", "deleted_at"]) {
    const {deps, recorded} = harness();
    await expectHttpsError(
      () => createHuman(deps, validRequest({[field]: "x"})),
      "invalid-argument",
    );
    assertNoWrites(recorded);
  }
});

test("S. timestamp/audit enviados pelo cliente sao recusados", async () => {
  for (const field of ["created_at", "createdAt", "updated_at", "updatedAt", "audit_trail"]) {
    const {deps, recorded} = harness();
    await expectHttpsError(
      () => createHuman(deps, validRequest({[field]: "x"})),
      "invalid-argument",
    );
    assertNoWrites(recorded);
  }
});

test("photoUrl e recusado (foto e fluxo pos-cadastro)", async () => {
  const {deps, recorded} = harness();
  await expectHttpsError(
    () => createHuman(deps, validRequest({photoUrl: "https://x/y.jpg"})),
    "invalid-argument",
  );
  assertNoWrites(recorded);
});

test("payload malformado e recusado", async () => {
  for (const raw of [null, "texto", 7, []]) {
    const {deps, recorded} = harness();
    await expectHttpsError(() => createHuman(deps, raw), "invalid-argument");
    assertNoWrites(recorded);
  }
});

// --- T. autorizacao --------------------------------------------------------

test("T. caller nao autenticado e recusado sem escrever", async () => {
  const {deps, recorded} = harness({
    authorizeError: new HttpsError("unauthenticated", "Autenticacao obrigatoria."),
  });
  await expectHttpsError(() => createHuman(deps, validRequest()), "unauthenticated");
  assertNoWrites(recorded);
});

test("T2. caller sem humans.create e recusado sem escrever", async () => {
  const {deps, recorded} = harness({
    authorizeError: new HttpsError("permission-denied", "Perfil sem permissao."),
  });
  await expectHttpsError(() => createHuman(deps, validRequest()), "permission-denied");
  assertNoWrites(recorded);
});

test("T3. autorizacao acontece antes de validar payload", async () => {
  const {deps, recorded} = harness({
    authorizeError: new HttpsError("permission-denied", "Perfil sem permissao."),
  });
  await expectHttpsError(
    () => createHuman(deps, {lixo: true, accessProfileId: "x"}),
    "permission-denied",
  );
  assert.equal(recorded.authorizeCalls, 1);
  assertNoWrites(recorded);
});

// --- U. ciclo de vida ------------------------------------------------------

test("U. ciclo de vida inicial e autoritativo: active=true / Ativo", async () => {
  const {deps, recorded} = harness();
  await createHuman(deps, validRequest());
  const doc = onlyDoc(recorded);
  assert.equal(doc.active, true);
  assert.equal(doc.status, "Ativo");
});

// --- V. auditoria ----------------------------------------------------------

test("V. auditoria created e gerada server-side no documento", async () => {
  const {deps, recorded} = harness();
  await createHuman(deps, validRequest());
  const doc = onlyDoc(recorded);
  assert.ok(Array.isArray(doc.audit_trail), "audit_trail deve ser lista");
  const trail = doc.audit_trail as JsonMap[];
  assert.equal(trail.length, 1);
  assert.equal(trail[0].action, "created");
  assert.equal(trail[0].by_ra, CALLER.ra);
});

// --- W. timestamps espelhados ----------------------------------------------

test("W. timestamps espelhados representam o mesmo instante logico", async () => {
  const {deps, recorded} = harness();
  await createHuman(deps, validRequest());
  const doc = onlyDoc(recorded);
  assert.equal(doc.created_at, SERVER_TIMESTAMP);
  assert.equal(doc.createdAt, SERVER_TIMESTAMP);
  assert.equal(doc.updated_at, SERVER_TIMESTAMP);
  assert.equal(doc.updatedAt, SERVER_TIMESTAMP);
});

// --- X. resposta minima + prova negativa -----------------------------------

test("X. resposta contem apenas campos seguros (sem uid/senha/acesso)", async () => {
  const {deps} = harness();
  const result = await createHuman(deps, validRequest()) as unknown as JsonMap;
  // Contrato de resposta LOCKED: exatamente {ra, created}. Sem timestamp: o
  // callable nao conhece o commit time; consumidores leem users/{ra}.
  assert.deepEqual(Object.keys(result).sort(), ["created", "ra"]);
  assert.equal(result.ra, "9001");
  assert.equal(result.created, true);
  for (const leaked of [
    "updatedAt",
    "createdAt",
    "updated_at",
    "created_at",
    "uid",
    "auth_uid",
    "temporary_password",
    "password",
    "accessProfile",
    "accessProfileId",
    "claims",
    "roles",
  ]) {
    assert.ok(!(leaked in result), `${leaked} nao pode vazar na resposta`);
  }
});

test("prova negativa: documento criado nao contem Auth/acesso/treino/binomio/turno", async () => {
  const {deps, recorded} = harness();
  await createHuman(
    deps,
    validRequest({
      cpf: "12345678900",
      unit: "Canil Central",
      notes: "n",
    }),
  );
  const doc = onlyDoc(recorded);
  const forbidden = [
    "auth_uid",
    "authUid",
    "uid",
    "email",
    "password",
    "temporary_password",
    "accessProfile",
    "accessProfileId",
    "access_profile",
    "access_profile_id",
    "accessLevel",
    "access_scope",
    "access_role",
    "roles",
    "admin",
    "claims",
    "claim_role",
    "mobile_access",
    "web_access",
    "app_access",
    "inventory_manager",
    "is_k9_instructor",
    "training_instructor",
    "training_role",
    "specialties",
    "conductorRa",
    "handlerRa",
    "handlerId",
    "shift_group_id",
    "shift_label",
    "photoUrl",
  ];
  for (const key of forbidden) {
    assert.ok(!(key in doc), `documento nao pode conter ${key}`);
  }
});

test("todas as chaves gravadas sao pessoais ou metadados de servidor", async () => {
  const {deps, recorded} = harness();
  await createHuman(
    deps,
    validRequest({
      cpf: "12345678900",
      birthDate: "1990-05-10",
      phone: "11999998888",
      institutionalEmail: "silva@gcm.com.br",
      rank: "Sargento",
      cargo: "Condutor",
      unit: "Canil Central",
      team: "Alfa",
      admissionDate: "2015-03-01",
      notes: "n",
    }),
  );
  const doc = onlyDoc(recorded);
  const allowedDocumentKeys = new Set([
    "ra",
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
    ...SERVER_KEYS,
  ]);
  for (const key of Object.keys(doc)) {
    assert.ok(allowedDocumentKeys.has(key), `chave inesperada gravada: ${key}`);
  }
});
