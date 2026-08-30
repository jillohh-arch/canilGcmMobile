/**
 * Testes do contrato Human Lifecycle V1 (adminDeactivateHuman /
 * adminReactivateHuman).
 *
 * Usa o runner nativo do Node (node:test), como os demais testes de writer
 * administrativo. As dependencias (autorizacao, transacao, leituras, Auth,
 * timestamp, auditoria, arrayUnion, deleteField) sao injetadas, portanto os
 * testes exercitam o contrato real — incluindo ORDEM cross-service e
 * COMPENSACAO — sem emulador e sem I/O.
 *
 * O harness registra a sequencia de efeitos em `recorded.effects`, o que permite
 * provar negativas fortes: "nenhuma mutacao antes da falha" e "compensacao
 * ocorreu na ordem correta" sao verificaveis, nao presumidas.
 */

import * as assert from "node:assert/strict";
import {test} from "node:test";
import {HttpsError} from "firebase-functions/v2/https";

import {
  ACTIVE_STATUS,
  AUDIT_ACTION,
  deactivateHuman,
  HumanLifecycleCaller,
  HumanLifecycleDeps,
  HumanLifecycleTransaction,
  INACTIVE_STATUS,
  isCurrentlyActive,
  LIFECYCLE_ERROR,
  reactivateHuman,
} from "../src/admin_human_lifecycle";

type JsonMap = Record<string, unknown>;

const CALLER: HumanLifecycleCaller = {
  uid: "uid-admin",
  email: "1234@gcm.com.br",
  ra: "1234",
  name: "Admin Teste",
};

const SERVER_TIMESTAMP = Symbol("serverTimestamp");
const DELETE_SENTINEL = Symbol("deleteField");
const BASE_MILLIS = 1_700_000_000_000;
const TARGET_RA = "9001";
const TARGET_UID = "uid-target";

/** Documento ATIVO canonico, com os dois espelhos de timestamp alinhados. */
function activeUser(overrides: JsonMap = {}): JsonMap {
  return {
    ra: TARGET_RA,
    name: "Joao da Silva",
    callsign: "Silva",
    auth_uid: TARGET_UID,
    active: true,
    status: ACTIVE_STATUS,
    // Dominios que devem ser PRESERVADOS pelo lifecycle:
    accessLevel: "gestor",
    access_profile: "gestor",
    roles: ["gestor", "instrutor_k9"],
    claim_role: "gestor",
    claim_updated_at: "CLAIM_UPDATED_SENTINEL",
    specialties: ["patrulha"],
    created_at: "CREATED_AT_SENTINEL",
    updated_at: {toMillis: () => BASE_MILLIS},
    updatedAt: {toMillis: () => BASE_MILLIS},
    ...overrides,
  };
}

/** Documento INATIVO canonico (estado produzido por uma desativacao). */
function inactiveUser(overrides: JsonMap = {}): JsonMap {
  return activeUser({
    active: false,
    status: INACTIVE_STATUS,
    deleted_at: "DELETED_AT_SENTINEL",
    deleted_by: "uid-outro-admin",
    delete_reason: "motivo anterior",
    deleted_reason: "motivo anterior",
    ...overrides,
  });
}

type Effect =
  | {kind: "authDisable"; uid: string; disabled: boolean}
  | {kind: "firestorePatch"; ra: string; patch: JsonMap}
  | {kind: "transaction"};

interface Recorded {
  authorizeCalls: number;
  effects: Effect[];
  auditEntries: Array<{
    action: string;
    caller: HumanLifecycleCaller;
    reason?: string;
  }>;
  activeShiftReads: string[];
  /** Leituras de active_shifts feitas DENTRO da transacao (guard D-1). */
  transactionShiftReads: string[];
  /** Leituras do estado `disabled` previo da conta de Auth (F-5). */
  authDisabledReads: string[];
  /** E-mails consultados pelo fallback canonico de resolucao de Auth. */
  emailLookups: string[];
  /**
   * Leituras de `users/{ra}` FORA de transacao. Deve ser 1 (pre-estado): uma
   * segunda indicaria que o read-after-commit voltou a existir.
   */
  userReads: number;
}

interface HarnessOptions {
  authorizeError?: HttpsError;
  /** Documento existente; `null` simula documento ausente. */
  user?: JsonMap | null;
  /** Documento de active_shifts/{ra}; `null` = ausente. */
  activeShift?: JsonMap | null;
  /**
   * Turno visto SOMENTE dentro da transacao. Simula o race D-1: o pre-check le
   * `activeShift` e a transacao le este outro valor.
   */
  activeShiftInTransaction?: JsonMap | null;
  /** Falha injetada na chamada de Auth. `enable`/`disable` selecionam a direcao. */
  authFailure?: {on: "disable" | "enable"; error: Error};
  /** Falha injetada na Nª transacao (1-indexed). */
  transactionFailure?: {onCall: number; error: Error};
  /** Estado `disabled` da conta de Auth ANTES da operacao. Default: false. */
  priorAuthDisabled?: boolean;
  /**
   * `true` => getAuthAccount(uid) retorna null com o uid presente no documento.
   * Simula DANGLING (A1.S1 CASE 2).
   */
  authAccountMissing?: boolean;
  /**
   * Conta encontrada pelo fallback de e-mail canonico quando o documento nao
   * tem alias de uid. `undefined` => nenhuma conta => ABSENT (CASE 1).
   */
  authByEmail?: {uid: string; disabled: boolean};
  /**
   * Escrita de um writer CONCORRENTE, aplicada ao documento imediatamente antes
   * da transacao de compensacao ler. Substitui as antigas opcoes de "versao":
   * o CAS de B1.R2 inspeciona ESTADO de lifecycle, nao timestamp, entao o teste
   * precisa mutar o documento de verdade.
   *
   * Um patch de Personnel/Access (ex.: `{telefone: "..."}`) NAO deve bloquear a
   * compensacao; um patch de lifecycle (ex.: `{active: false}`) DEVE bloquear.
   */
  concurrentWrite?: JsonMap;
}

function harness(options: HarnessOptions = {}): {
  deps: HumanLifecycleDeps;
  recorded: Recorded;
} {
  const recorded: Recorded = {
    authorizeCalls: 0,
    effects: [],
    auditEntries: [],
    activeShiftReads: [],
    transactionShiftReads: [],
    authDisabledReads: [],
    emailLookups: [],
    userReads: 0,
  };
  const user = options.user === undefined ? activeUser() : options.user;
  let transactionCalls = 0;
  let concurrentApplied = false;

/**
 * Estado REAL do documento. O harness aplica os patches de verdade (merge,
 * FieldValue.delete, arrayUnion), em vez de simular versoes.
 *
 * Isso e obrigatorio desde B1.R2: o CAS da compensacao passou a inspecionar o
 * ESTADO de lifecycle, nao um timestamp. Um harness que so trocasse `updated*`
 * nao exercitaria o guard real e poderia deixar o defeito passar verde.
 *
 * ======================================================================
 * IMPORTANTE — LIMITACAO CONHECIDA DESTE FAKE [B2.RB/RB-3]
 * ======================================================================
 * Este fake aplica `patchUser` EAGERLY (imediatamente) e NAO desfaz a escrita
 * se o callback da transacao lancar depois. O Firestore real DESCARTARIA a
 * escrita nesse caso.
 *
 * O fake permanece fiel SOMENTE enquanto `patchUser` for a ULTIMA operacao de
 * todo callback transacional — condicao verificada em B2.RB nos 5 call sites
 * atuais do modulo (todos os `fail()` posteriores ficam no `catch`, fora do
 * callback).
 *
 * SE algum codigo futuro puder lancar/validar APOS `patchUser` dentro de um
 * callback, este fake DEIXA de representar o rollback do Firestore e passara
 * verde sobre um estado que a producao teria descartado. Nesse momento e
 * obrigatorio bufferizar as escritas e so aplica-las no sucesso da transacao.
 * ======================================================================
 */
  let docState: JsonMap | null = user === null ? null : {...user};

  function applyPatch(patch: JsonMap): void {
    if (docState === null) return;
    for (const [key, value] of Object.entries(patch)) {
      if (value === DELETE_SENTINEL) {
        delete docState[key];
        continue;
      }
      if (
        typeof value === "object" &&
        value !== null &&
        "__arrayUnion" in (value as JsonMap)
      ) {
        const previous = Array.isArray(docState[key])
          ? (docState[key] as unknown[])
          : [];
        docState[key] = [...previous, (value as JsonMap).__arrayUnion];
        continue;
      }
      docState[key] = value;
    }
  }

  function snapshotOf(): {exists: boolean; data: JsonMap | null} {
    return {
      exists: docState !== null,
      data: docState === null ? null : {...docState},
    };
  }

  const deps: HumanLifecycleDeps = {
    authorize: async () => {
      recorded.authorizeCalls += 1;
      if (options.authorizeError) throw options.authorizeError;
      return CALLER;
    },
    getUser: async () => {
      recorded.userReads += 1;
      return snapshotOf();
    },
    getActiveShift: async (ra) => {
      recorded.activeShiftReads.push(ra);
      const shift =
        options.activeShift === undefined ? null : options.activeShift;
      return {exists: shift !== null, data: shift};
    },
    runTransaction: async (handler) => {
      transactionCalls += 1;
      const callIndex = transactionCalls;
      recorded.effects.push({kind: "transaction"});
      const failure = options.transactionFailure;
      if (failure && failure.onCall === callIndex) {
        throw failure.error;
      }
      const tx: HumanLifecycleTransaction = {
        getUser: async () => {
          // Antes de abrir a transacao de compensacao (2a), aplica a escrita do
          // writer concorrente, se o teste injetou uma. Assim o guard de
          // invariante ve o documento REAL que existiria nesse instante.
          if (callIndex >= 2 && options.concurrentWrite && !concurrentApplied) {
            concurrentApplied = true;
            applyPatch(options.concurrentWrite);
          }
          return snapshotOf();
        },
        getActiveShift: async (ra) => {
          recorded.transactionShiftReads.push(ra);
          const shift =
            options.activeShiftInTransaction === undefined
              ? options.activeShift === undefined
                ? null
                : options.activeShift
              : options.activeShiftInTransaction;
          return {exists: shift !== null, data: shift};
        },
        patchUser: (ra, patch) => {
          recorded.effects.push({kind: "firestorePatch", ra, patch});
          applyPatch(patch);
        },
      };
      return handler(tx);
    },
    getAuthAccount: async (uid) => {
      recorded.authDisabledReads.push(uid);
      // `authAccountMissing` simula DANGLING: o doc afirma o uid, o Auth nao tem.
      if (options.authAccountMissing) return null;
      // Default FIEL ao estado convergido: documento inativo => conta
      // desabilitada. Testes de drift sobrescrevem explicitamente.
      const disabled =
        options.priorAuthDisabled === undefined
          ? user !== null && user.active === false
          : options.priorAuthDisabled;
      return {uid, disabled};
    },
    findAuthAccountByEmail: async (email) => {
      recorded.emailLookups.push(email);
      if (options.authByEmail === undefined) return null;
      return options.authByEmail;
    },
    canonicalAuthEmail: (user, targetRa) =>
      typeof user.email === "string" && user.email.trim().length > 0
        ? user.email
        : `${targetRa}@gcm.com.br`,
    setAuthDisabled: async (uid, disabled) => {
      const failure = options.authFailure;
      if (failure) {
        const matches =
          (failure.on === "disable" && disabled) ||
          (failure.on === "enable" && !disabled);
        if (matches) throw failure.error;
      }
      recorded.effects.push({kind: "authDisable", uid, disabled});
    },
    serverTimestamp: () => SERVER_TIMESTAMP,
    auditEntry: (action, caller, reason) => {
      recorded.auditEntries.push({action, caller, reason});
      const entry: JsonMap = {action, by: caller.uid, by_ra: caller.ra};
      if (reason !== undefined) entry.reason = reason;
      return entry;
    },
    arrayUnion: (value) => ({__arrayUnion: value}),
    deleteField: () => DELETE_SENTINEL,
  };

  return {deps, recorded};
}

/** Payload valido de desativacao. */
function deactivatePayload(overrides: JsonMap = {}): JsonMap {
  return {
    ra: TARGET_RA,
    reason: "afastamento administrativo",
    expectedUpdatedAt: BASE_MILLIS,
    ...overrides,
  };
}

/** Payload valido de reativacao. */
function reactivatePayload(overrides: JsonMap = {}): JsonMap {
  return {
    ra: TARGET_RA,
    expectedUpdatedAt: BASE_MILLIS,
    ...overrides,
  };
}

async function expectFailure(
  operation: () => Promise<unknown>,
): Promise<HttpsError> {
  try {
    await operation();
  } catch (error) {
    assert.ok(error instanceof HttpsError, `esperado HttpsError, veio ${error}`);
    return error;
  }
  assert.fail("esperava falha, mas a operacao foi bem-sucedida");
}

/**
 * Falha de qualquer tipo. Usado onde o contrato exige que o erro ORIGINAL de
 * infraestrutura propague sem ser mascarado — nesse caso ele nao e HttpsError.
 */
async function expectAnyFailure(
  operation: () => Promise<unknown>,
): Promise<unknown> {
  try {
    await operation();
  } catch (error) {
    return error;
  }
  assert.fail("esperava falha, mas a operacao foi bem-sucedida");
}

function reasonOf(error: HttpsError): unknown {
  return (error.details as {reason?: unknown} | undefined)?.reason;
}

function patches(recorded: Recorded): Array<{ra: string; patch: JsonMap}> {
  return recorded.effects.filter(
    (effect): effect is {kind: "firestorePatch"; ra: string; patch: JsonMap} =>
      effect.kind === "firestorePatch",
  );
}

function authCalls(
  recorded: Recorded,
): Array<{kind: "authDisable"; uid: string; disabled: boolean}> {
  return recorded.effects.filter(
    (effect): effect is {kind: "authDisable"; uid: string; disabled: boolean} =>
      effect.kind === "authDisable",
  );
}

// ---------------------------------------------------------------------------
// A. AUTORIDADE / PAYLOAD
// ---------------------------------------------------------------------------

test("A1: desativacao autorizada por humans.archive chama authorize primeiro", async () => {
  const {deps, recorded} = harness();
  await deactivateHuman(deps, deactivatePayload());
  assert.equal(recorded.authorizeCalls, 1);
});

test("A2: permission denied impede qualquer efeito", async () => {
  const denied = new HttpsError("permission-denied", "Perfil sem permissao.");
  const {deps, recorded} = harness({authorizeError: denied});
  const error = await expectFailure(() =>
    deactivateHuman(deps, deactivatePayload()),
  );
  assert.equal(error.code, "permission-denied");
  assert.deepEqual(recorded.effects, []);
});

test("A3: permission denied tambem bloqueia reativacao", async () => {
  const denied = new HttpsError("permission-denied", "Perfil sem permissao.");
  const {deps, recorded} = harness({
    authorizeError: denied,
    user: inactiveUser(),
  });
  const error = await expectFailure(() =>
    reactivateHuman(deps, reactivatePayload()),
  );
  assert.equal(error.code, "permission-denied");
  assert.deepEqual(recorded.effects, []);
});

test("A4: RA nao numerico rejeitado sem efeito", async () => {
  const {deps, recorded} = harness();
  const error = await expectFailure(() =>
    deactivateHuman(deps, deactivatePayload({ra: "90A1"})),
  );
  assert.equal(error.code, "invalid-argument");
  assert.equal(reasonOf(error), LIFECYCLE_ERROR.invalidArgument);
  assert.deepEqual(recorded.effects, []);
});

test("A5: RA ausente rejeitado", async () => {
  const {deps} = harness();
  const error = await expectFailure(() =>
    deactivateHuman(deps, {reason: "motivo valido", expectedUpdatedAt: null}),
  );
  assert.equal(reasonOf(error), LIFECYCLE_ERROR.invalidArgument);
});

test("A6: reason ausente na desativacao e rejeitado", async () => {
  const {deps, recorded} = harness();
  const error = await expectFailure(() =>
    deactivateHuman(deps, {ra: TARGET_RA, expectedUpdatedAt: BASE_MILLIS}),
  );
  assert.equal(error.code, "invalid-argument");
  assert.equal(reasonOf(error), LIFECYCLE_ERROR.invalidArgument);
  assert.deepEqual(recorded.effects, []);
});

test("A7: reason curto/branco na desativacao e rejeitado", async () => {
  for (const reason of ["", "   ", "abc", "  a  "]) {
    const {deps, recorded} = harness();
    const error = await expectFailure(() =>
      deactivateHuman(deps, deactivatePayload({reason})),
    );
    assert.equal(reasonOf(error), LIFECYCLE_ERROR.invalidArgument);
    assert.deepEqual(recorded.effects, []);
  }
});

test("A8: reason non-string rejeitado", async () => {
  const {deps} = harness();
  const error = await expectFailure(() =>
    deactivateHuman(deps, deactivatePayload({reason: 42})),
  );
  assert.equal(reasonOf(error), LIFECYCLE_ERROR.invalidArgument);
});

test("A9: expectedUpdatedAt ausente rejeitado nas duas operacoes", async () => {
  const deactivate = harness();
  const errorA = await expectFailure(() =>
    deactivateHuman(deactivate.deps, {ra: TARGET_RA, reason: "motivo valido"}),
  );
  assert.equal(reasonOf(errorA), LIFECYCLE_ERROR.invalidArgument);

  const reactivate = harness({user: inactiveUser()});
  const errorB = await expectFailure(() =>
    reactivateHuman(reactivate.deps, {ra: TARGET_RA}),
  );
  assert.equal(reasonOf(errorB), LIFECYCLE_ERROR.invalidArgument);
});

test("A10: expectedUpdatedAt ISO/Date/Timestamp recusado (contrato externo e epoch millis)", async () => {
  for (const value of ["2026-08-29T00:00:00Z", {toMillis: () => BASE_MILLIS}, true]) {
    const {deps, recorded} = harness();
    const error = await expectFailure(() =>
      deactivateHuman(deps, deactivatePayload({expectedUpdatedAt: value})),
    );
    assert.equal(reasonOf(error), LIFECYCLE_ERROR.invalidArgument);
    assert.deepEqual(recorded.effects, []);
  }
});

test("A11: chave desconhecida no payload e recusada (fail closed)", async () => {
  for (const extra of ["active", "status", "roles", "disabled", "actor"]) {
    const {deps, recorded} = harness();
    const error = await expectFailure(() =>
      deactivateHuman(deps, deactivatePayload({[extra]: "x"})),
    );
    assert.equal(reasonOf(error), LIFECYCLE_ERROR.invalidArgument);
    assert.deepEqual(recorded.effects, []);
  }
});

test("A12: target inexistente => NOT_FOUND sem efeito", async () => {
  const {deps, recorded} = harness({user: null});
  const error = await expectFailure(() =>
    deactivateHuman(deps, deactivatePayload()),
  );
  assert.equal(error.code, "not-found");
  assert.equal(reasonOf(error), LIFECYCLE_ERROR.notFound);
  assert.deepEqual(recorded.effects, []);
});

// ---------------------------------------------------------------------------
// B. DESATIVAR — caminho de sucesso
// ---------------------------------------------------------------------------

test("B1: desativacao bem-sucedida retorna estado canonico", async () => {
  const {deps} = harness();
  const result = await deactivateHuman(deps, deactivatePayload());
  assert.deepEqual(result, {
    ra: TARGET_RA,
    active: false,
    status: INACTIVE_STATUS,
    authState: "updated",
    reconciliationOnly: false,
  });
});

test("B2: escreve active=false e status=Inativo", async () => {
  const {deps, recorded} = harness();
  await deactivateHuman(deps, deactivatePayload());
  const [written] = patches(recorded);
  assert.equal(written.ra, TARGET_RA);
  assert.equal(written.patch.active, false);
  assert.equal(written.patch.status, INACTIVE_STATUS);
});

test("B3: usa vocabulario canonico deleted_* com o motivo informado", async () => {
  const {deps, recorded} = harness();
  await deactivateHuman(deps, deactivatePayload({reason: "  afastado por sindicancia  "}));
  const [{patch}] = patches(recorded);
  assert.equal(patch.deleted_at, SERVER_TIMESTAMP);
  assert.equal(patch.deleted_by, CALLER.uid);
  // Motivo trimado, espelhado nos dois aliases canonicos.
  assert.equal(patch.delete_reason, "afastado por sindicancia");
  assert.equal(patch.deleted_reason, "afastado por sindicancia");
});

test("B4: NAO escreve o vocabulario paralelo deactivated_*/archived_at", async () => {
  const {deps, recorded} = harness();
  await deactivateHuman(deps, deactivatePayload());
  const [{patch}] = patches(recorded);
  for (const forbidden of [
    "deactivated_at",
    "deactivated_by",
    "deactivate_reason",
    "reactivated_at",
    "reactivated_by",
    "archived_at",
    "archived",
  ]) {
    assert.ok(
      !(forbidden in patch),
      `campo legado ${forbidden} nao deve ser escrito`,
    );
  }
});

test("B5: preserva acesso, roles, claims e Personnel (nao aparecem no patch)", async () => {
  const {deps, recorded} = harness();
  await deactivateHuman(deps, deactivatePayload());
  const [{patch}] = patches(recorded);
  for (const preserved of [
    "roles",
    "role",
    "accessLevel",
    "access_profile",
    "access_profile_id",
    "accessScope",
    "claims",
    "claim_role",
    "claim_updated_at",
    "specialties",
    "name",
    "callsign",
    "cargo",
    "unit",
    "email",
    "auth_uid",
    "created_at",
  ]) {
    assert.ok(
      !(preserved in patch),
      `campo preservado ${preserved} nao deve ser tocado`,
    );
  }
});

test("B6: bombeia AMBOS os espelhos updated_at e updatedAt", async () => {
  const {deps, recorded} = harness();
  await deactivateHuman(deps, deactivatePayload());
  const [{patch}] = patches(recorded);
  assert.equal(patch.updated_at, SERVER_TIMESTAMP);
  assert.equal(patch.updatedAt, SERVER_TIMESTAMP);
});

test("B7: desabilita a conta de Auth", async () => {
  const {deps, recorded} = harness();
  await deactivateHuman(deps, deactivatePayload());
  assert.deepEqual(authCalls(recorded), [
    {kind: "authDisable", uid: TARGET_UID, disabled: true},
  ]);
});

test("B8: audit server-side com ator do caller e motivo", async () => {
  const {deps, recorded} = harness();
  await deactivateHuman(deps, deactivatePayload({reason: "motivo auditado"}));
  assert.equal(recorded.auditEntries.length, 1);
  const [entry] = recorded.auditEntries;
  assert.equal(entry.action, "deactivated");
  assert.equal(entry.caller.uid, CALLER.uid);
  assert.equal(entry.caller.ra, CALLER.ra);
  assert.equal(entry.reason, "motivo auditado");
  const [{patch}] = patches(recorded);
  assert.deepEqual(patch.audit_trail, {
    __arrayUnion: {
      action: "deactivated",
      by: CALLER.uid,
      by_ra: CALLER.ra,
      reason: "motivo auditado",
    },
  });
});

test("B9: auto-desativacao rejeitada sem qualquer efeito", async () => {
  const {deps, recorded} = harness({user: activeUser({ra: CALLER.ra})});
  const error = await expectFailure(() =>
    deactivateHuman(deps, deactivatePayload({ra: CALLER.ra})),
  );
  assert.equal(error.code, "failed-precondition");
  assert.equal(reasonOf(error), LIFECYCLE_ERROR.selfDeactivationForbidden);
  assert.deepEqual(recorded.effects, []);
  // Nem sequer leu o turno: a rejeicao precede qualquer I/O de estado.
  assert.deepEqual(recorded.activeShiftReads, []);
});

test("B10: desativar quem ja esta inativo => ALREADY_IN_STATE sem efeito", async () => {
  const {deps, recorded} = harness({user: inactiveUser()});
  const error = await expectFailure(() =>
    deactivateHuman(deps, deactivatePayload()),
  );
  assert.equal(reasonOf(error), LIFECYCLE_ERROR.alreadyInState);
  assert.deepEqual(recorded.effects, []);
});

/**
 * B11 — historico deste teste, que e instrutivo:
 *
 *   B1     : assertava sucesso com `authDisabled:false` — ou seja, congelava
 *            "marcar inativo sem bloquear login" como comportamento correto.
 *            Esse era o defeito I-1.
 *   B1.R1  : passou a exigir falha fechada (AUTH_IDENTITY_MISSING).
 *   B1.R2  : PRE1 provou que Personnel sem Auth e estado CANONICO — Human
 *            Create V1 o produz deliberadamente. Falhar fechado tornava todo
 *            cadastro do Create V1 impossivel de desativar. Agora a operacao
 *            SUCEDE, com Auth como NO-OP, e o resultado declara explicitamente
 *            que nao havia acesso a suspender (A1.S1 CASE 1).
 *
 * A diferenca em relacao ao B1 e essencial: la o sucesso MENTIA sobre o efeito
 * (dizia ter suspenso acesso de quem tinha conta ativa); aqui o sucesso e
 * verdadeiro, porque nao existe conta alguma.
 */
test("B11: sem conta de Auth a desativacao SUCEDE com Auth NO-OP", async () => {
  const user = activeUser();
  delete user.auth_uid;
  const {deps, recorded} = harness({user});
  const result = await deactivateHuman(deps, deactivatePayload());
  assert.equal(result.authState, "not_provisioned");
  assert.equal(result.active, false);
  // Lifecycle persistido normalmente...
  assert.equal(patches(recorded).length, 1);
  // ...e nenhuma chamada de Auth: nada foi criado nem mutado.
  assert.deepEqual(authCalls(recorded), []);
});

test("B12: com conta habilitada, a desativacao reporta authState=updated", async () => {
  const {deps} = harness({priorAuthDisabled: false});
  const result = await deactivateHuman(deps, deactivatePayload());
  assert.equal(result.authState, "updated");
  assert.equal(result.reconciliationOnly, false);
});

// ---------------------------------------------------------------------------
// C. ACTIVE SHIFT
// ---------------------------------------------------------------------------

test("C1: turno ativo bloqueia a desativacao com discriminator ACTIVE_SHIFT", async () => {
  const {deps} = harness({activeShift: {status: "active"}});
  const error = await expectFailure(() =>
    deactivateHuman(deps, deactivatePayload()),
  );
  assert.equal(error.code, "failed-precondition");
  assert.equal(reasonOf(error), LIFECYCLE_ERROR.activeShift);
});

test("C2: ACTIVE_SHIFT produz ZERO mutacao em Firestore e em Auth", async () => {
  const {deps, recorded} = harness({activeShift: {status: "active"}});
  await expectFailure(() => deactivateHuman(deps, deactivatePayload()));
  assert.deepEqual(recorded.effects, []);
  assert.deepEqual(recorded.auditEntries, []);
});

test("C3: ACTIVE_SHIFT e STALE_WRITE sao distinguiveis apesar do mesmo code", async () => {
  const shift = harness({activeShift: {status: "active"}});
  const shiftError = await expectFailure(() =>
    deactivateHuman(shift.deps, deactivatePayload()),
  );
  const stale = harness();
  const staleError = await expectFailure(() =>
    deactivateHuman(stale.deps, deactivatePayload({expectedUpdatedAt: 1})),
  );

  // Mesmo code Firebase...
  assert.equal(shiftError.code, "failed-precondition");
  assert.equal(staleError.code, "failed-precondition");
  // ...e discriminadores diferentes e estaveis.
  assert.equal(reasonOf(shiftError), LIFECYCLE_ERROR.activeShift);
  assert.equal(reasonOf(staleError), LIFECYCLE_ERROR.staleWrite);
  assert.notEqual(reasonOf(shiftError), reasonOf(staleError));
});

test("C4: turno ausente ou nao-ativo nao bloqueia", async () => {
  for (const shift of [
    null,
    {status: "closed"},
    {status: "finished"},
    {},
    {status: 42},
  ]) {
    const {deps, recorded} = harness({activeShift: shift as JsonMap | null});
    await deactivateHuman(deps, deactivatePayload());
    assert.equal(patches(recorded).length, 1, `turno ${JSON.stringify(shift)}`);
  }
});

test("C5: o guard le exatamente active_shifts/{ra} do alvo (doc unico)", async () => {
  const {deps, recorded} = harness();
  await deactivateHuman(deps, deactivatePayload());
  assert.deepEqual(recorded.activeShiftReads, [TARGET_RA]);
});

test("C6: reativacao NAO consulta turno ativo", async () => {
  const {deps, recorded} = harness({user: inactiveUser()});
  await reactivateHuman(deps, reactivatePayload());
  assert.deepEqual(recorded.activeShiftReads, []);
});

// ---------------------------------------------------------------------------
// D. OCC — max(updated_at, updatedAt)
// ---------------------------------------------------------------------------

test("D1: expectedUpdatedAt obsoleto rejeita com STALE_WRITE e zero efeito", async () => {
  const {deps, recorded} = harness();
  const error = await expectFailure(() =>
    deactivateHuman(deps, deactivatePayload({expectedUpdatedAt: BASE_MILLIS - 1})),
  );
  assert.equal(error.code, "failed-precondition");
  assert.equal(reasonOf(error), LIFECYCLE_ERROR.staleWrite);
  assert.deepEqual(recorded.effects, []);
  assert.deepEqual(authCalls(recorded), []);
});

test("D2: autoridade e o MAIS NOVO quando updated_at > updatedAt", async () => {
  const newer = BASE_MILLIS + 60_000;
  const user = activeUser({
    updated_at: {toMillis: () => newer},
    updatedAt: {toMillis: () => BASE_MILLIS},
  });

  // O espelho mais antigo NAO autoriza: seria lost update silencioso.
  const staleHarness = harness({user});
  const error = await expectFailure(() =>
    deactivateHuman(staleHarness.deps, deactivatePayload({expectedUpdatedAt: BASE_MILLIS})),
  );
  assert.equal(reasonOf(error), LIFECYCLE_ERROR.staleWrite);
  assert.deepEqual(staleHarness.recorded.effects, []);

  // O mais novo autoriza.
  const okHarness = harness({user});
  await deactivateHuman(okHarness.deps, deactivatePayload({expectedUpdatedAt: newer}));
  assert.equal(patches(okHarness.recorded).length, 1);
});

test("D3: autoridade e o MAIS NOVO quando updatedAt > updated_at", async () => {
  const newer = BASE_MILLIS + 90_000;
  const user = activeUser({
    updated_at: {toMillis: () => BASE_MILLIS},
    updatedAt: {toMillis: () => newer},
  });

  const staleHarness = harness({user});
  const error = await expectFailure(() =>
    deactivateHuman(staleHarness.deps, deactivatePayload({expectedUpdatedAt: BASE_MILLIS})),
  );
  assert.equal(reasonOf(error), LIFECYCLE_ERROR.staleWrite);

  const okHarness = harness({user});
  await deactivateHuman(okHarness.deps, deactivatePayload({expectedUpdatedAt: newer}));
  assert.equal(patches(okHarness.recorded).length, 1);
});

test("D4: documento sem espelho algum exige expectedUpdatedAt null", async () => {
  const user = activeUser();
  delete user.updated_at;
  delete user.updatedAt;

  const okHarness = harness({user});
  await deactivateHuman(okHarness.deps, deactivatePayload({expectedUpdatedAt: null}));
  assert.equal(patches(okHarness.recorded).length, 1);

  const staleHarness = harness({user});
  const error = await expectFailure(() =>
    deactivateHuman(staleHarness.deps, deactivatePayload({expectedUpdatedAt: BASE_MILLIS})),
  );
  assert.equal(reasonOf(error), LIFECYCLE_ERROR.staleWrite);
});

test("D5: expectedUpdatedAt null contra documento com timestamp e stale", async () => {
  const {deps, recorded} = harness();
  const error = await expectFailure(() =>
    deactivateHuman(deps, deactivatePayload({expectedUpdatedAt: null})),
  );
  assert.equal(reasonOf(error), LIFECYCLE_ERROR.staleWrite);
  assert.deepEqual(recorded.effects, []);
});

test("D6: OCC e REVALIDADA dentro da transacao", async () => {
  // A pre-checagem passa; a transacao le o documento e revalida. Provamos que a
  // leitura transacional acontece exigindo que o patch so ocorra depois dela.
  const {deps, recorded} = harness();
  await deactivateHuman(deps, deactivatePayload());
  const kinds = recorded.effects.map((effect) => effect.kind);
  assert.deepEqual(kinds, ["authDisable", "transaction", "firestorePatch"]);
});

test("D7: OCC stale na reativacao rejeita sem tocar Auth", async () => {
  const {deps, recorded} = harness({user: inactiveUser()});
  const error = await expectFailure(() =>
    reactivateHuman(deps, reactivatePayload({expectedUpdatedAt: 1})),
  );
  assert.equal(reasonOf(error), LIFECYCLE_ERROR.staleWrite);
  assert.deepEqual(recorded.effects, []);
});

// ---------------------------------------------------------------------------
// E. REATIVAR
// ---------------------------------------------------------------------------

test("E1: reativacao bem-sucedida retorna estado canonico", async () => {
  const {deps} = harness({user: inactiveUser()});
  const result = await reactivateHuman(deps, reactivatePayload());
  assert.deepEqual(result, {
    ra: TARGET_RA,
    active: true,
    status: ACTIVE_STATUS,
    authState: "updated",
    reconciliationOnly: false,
  });
});

test("E2: escreve active=true e status=Ativo (valor canonico do Create V1)", async () => {
  const {deps, recorded} = harness({user: inactiveUser()});
  await reactivateHuman(deps, reactivatePayload());
  const [{patch}] = patches(recorded);
  assert.equal(patch.active, true);
  assert.equal(patch.status, ACTIVE_STATUS);
  assert.equal(patch.status, "Ativo");
});

test("E3: NAO aceita status arbitrario do caller", async () => {
  const {deps} = harness({user: inactiveUser()});
  const error = await expectFailure(() =>
    reactivateHuman(deps, reactivatePayload({status: "Ferias"})),
  );
  assert.equal(reasonOf(error), LIFECYCLE_ERROR.invalidArgument);
});

test("E4: limpa os markers canonicos deleted_*", async () => {
  const {deps, recorded} = harness({user: inactiveUser()});
  await reactivateHuman(deps, reactivatePayload());
  const [{patch}] = patches(recorded);
  for (const marker of [
    "deleted_at",
    "deleted_by",
    "delete_reason",
    "deleted_reason",
  ]) {
    assert.equal(patch[marker], DELETE_SENTINEL, `${marker} deve ser removido`);
  }
});

test("E5: NAO cria aliases paralelos reactivated_*", async () => {
  const {deps, recorded} = harness({user: inactiveUser()});
  await reactivateHuman(deps, reactivatePayload({reason: "retorno de licenca"}));
  const [{patch}] = patches(recorded);
  for (const forbidden of [
    "reactivated_at",
    "reactivated_by",
    "deactivated_at",
    "deactivated_by",
    "deactivate_reason",
  ]) {
    assert.ok(!(forbidden in patch), `${forbidden} nao deve ser escrito`);
  }
});

test("E6: reabilita a conta de Auth", async () => {
  const {deps, recorded} = harness({user: inactiveUser()});
  await reactivateHuman(deps, reactivatePayload());
  assert.deepEqual(authCalls(recorded), [
    {kind: "authDisable", uid: TARGET_UID, disabled: false},
  ]);
});

test("E7: NAO restaura snapshot: perfil/roles/claims ausentes do patch", async () => {
  const {deps, recorded} = harness({
    user: inactiveUser({
      roles: ["gestor"],
      access_profile: "gestor",
      claim_role: "gestor",
    }),
  });
  await reactivateHuman(deps, reactivatePayload());
  const [{patch}] = patches(recorded);
  for (const preserved of [
    "roles",
    "role",
    "accessLevel",
    "access_profile",
    "access_profile_id",
    "claims",
    "claim_role",
    "claim_updated_at",
    "specialties",
    "auth_uid",
    "email",
  ]) {
    assert.ok(
      !(preserved in patch),
      `${preserved} nao deve ser reescrito na reativacao`,
    );
  }
  // O conjunto de chaves escritas e fechado e verificavel.
  assert.deepEqual(
    Object.keys(patch).sort(),
    [
      "active",
      "audit_trail",
      "delete_reason",
      "deleted_at",
      "deleted_by",
      "deleted_reason",
      "status",
      "updated_at",
      "updatedAt",
    ].sort(),
  );
});

test("E8: reason ausente e aceito na reativacao", async () => {
  const {deps, recorded} = harness({user: inactiveUser()});
  await reactivateHuman(deps, reactivatePayload());
  assert.equal(recorded.auditEntries.length, 1);
  assert.equal(recorded.auditEntries[0].action, "reactivated");
  assert.equal(recorded.auditEntries[0].reason, undefined);
});

test("E9: reason fornecido na reativacao e validado", async () => {
  const {deps, recorded} = harness({user: inactiveUser()});
  await reactivateHuman(deps, reactivatePayload({reason: "retorno autorizado"}));
  assert.equal(recorded.auditEntries[0].reason, "retorno autorizado");

  for (const invalid of ["abc", "  ", 42]) {
    const bad = harness({user: inactiveUser()});
    const error = await expectFailure(() =>
      reactivateHuman(bad.deps, reactivatePayload({reason: invalid})),
    );
    assert.equal(reasonOf(error), LIFECYCLE_ERROR.invalidArgument);
    assert.deepEqual(bad.recorded.effects, []);
  }
});

test("E10: bombeia AMBOS os espelhos na reativacao", async () => {
  const {deps, recorded} = harness({user: inactiveUser()});
  await reactivateHuman(deps, reactivatePayload());
  const [{patch}] = patches(recorded);
  assert.equal(patch.updated_at, SERVER_TIMESTAMP);
  assert.equal(patch.updatedAt, SERVER_TIMESTAMP);
});

test("E11: audit server-side na reativacao", async () => {
  const {deps, recorded} = harness({user: inactiveUser()});
  await reactivateHuman(deps, reactivatePayload());
  const [{patch}] = patches(recorded);
  assert.deepEqual(patch.audit_trail, {
    __arrayUnion: {action: "reactivated", by: CALLER.uid, by_ra: CALLER.ra},
  });
});

test("E12: reativar quem ja esta ativo => ALREADY_IN_STATE sem efeito", async () => {
  const {deps, recorded} = harness({user: activeUser()});
  const error = await expectFailure(() =>
    reactivateHuman(deps, reactivatePayload()),
  );
  assert.equal(reasonOf(error), LIFECYCLE_ERROR.alreadyInState);
  assert.deepEqual(recorded.effects, []);
});

test("E13: reativacao de alvo inexistente => NOT_FOUND", async () => {
  const {deps, recorded} = harness({user: null});
  const error = await expectFailure(() =>
    reactivateHuman(deps, reactivatePayload()),
  );
  assert.equal(error.code, "not-found");
  assert.equal(reasonOf(error), LIFECYCLE_ERROR.notFound);
  assert.deepEqual(recorded.effects, []);
});

// ---------------------------------------------------------------------------
// F. FALHA CROSS-SERVICE E COMPENSACAO
// ---------------------------------------------------------------------------

test("F1: Auth disable falha antes do Firestore => documento intacto", async () => {
  const {deps, recorded} = harness({
    authFailure: {on: "disable", error: new Error("auth indisponivel")},
  });
  const error = await expectFailure(() =>
    deactivateHuman(deps, deactivatePayload()),
  );
  assert.equal(error.code, "internal");
  assert.equal(reasonOf(error), LIFECYCLE_ERROR.authOperationFailed);
  // Nenhuma escrita no Firestore e nenhuma transacao aberta.
  assert.deepEqual(patches(recorded), []);
  assert.deepEqual(recorded.effects, []);
});

test("F2: Firestore falha apos Auth disable => compensa reabilitando a conta", async () => {
  const {deps, recorded} = harness({
    transactionFailure: {onCall: 1, error: new Error("firestore indisponivel")},
    authFailure: undefined,
  });
  await expectAnyFailure(() => deactivateHuman(deps, deactivatePayload()));

  const auth = authCalls(recorded);
  assert.equal(auth.length, 2, "esperado disable + compensacao enable");
  assert.deepEqual(auth[0], {
    kind: "authDisable",
    uid: TARGET_UID,
    disabled: true,
  });
  assert.deepEqual(auth[1], {
    kind: "authDisable",
    uid: TARGET_UID,
    disabled: false,
  });
  // Nada foi persistido no documento.
  assert.deepEqual(patches(recorded), []);
});

test("F3: falha do Firestore NAO e reportada como sucesso", async () => {
  const {deps} = harness({
    transactionFailure: {onCall: 1, error: new Error("firestore indisponivel")},
  });
  const error = await expectAnyFailure(() =>
    deactivateHuman(deps, deactivatePayload()),
  );
  // O erro ORIGINAL de infraestrutura propaga cru; nao ha mascaramento nem
  // conversao em sucesso aparente.
  assert.ok(error instanceof Error);
  assert.match(error.message, /firestore indisponivel/);
});

test("F4: Firestore falha E compensacao de Auth falha => COMPENSATION_FAILED explicito", async () => {
  const {deps, recorded} = harness({
    transactionFailure: {onCall: 1, error: new Error("firestore indisponivel")},
    authFailure: {on: "enable", error: new Error("auth tambem caiu")},
  });
  const error = await expectFailure(() =>
    deactivateHuman(deps, deactivatePayload()),
  );
  assert.equal(error.code, "internal");
  assert.equal(reasonOf(error), LIFECYCLE_ERROR.compensationFailed);
  // A mensagem declara o estado divergente e os DOIS erros.
  assert.match(error.message, /divergente/i);
  assert.match(error.message, /firestore indisponivel/);
  assert.match(error.message, /auth tambem caiu/);
  assert.deepEqual(patches(recorded), []);
});

test("F5: reativacao commita Firestore ANTES de habilitar Auth", async () => {
  const {deps, recorded} = harness({user: inactiveUser()});
  await reactivateHuman(deps, reactivatePayload());
  const kinds = recorded.effects.map((effect) => effect.kind);
  assert.deepEqual(kinds, ["transaction", "firestorePatch", "authDisable"]);
});

test("F6: Auth enable falha apos commit => compensa documento para inativo", async () => {
  const {deps, recorded} = harness({
    user: inactiveUser(),
    authFailure: {on: "enable", error: new Error("auth indisponivel")},
  });
  const error = await expectFailure(() =>
    reactivateHuman(deps, reactivatePayload()),
  );
  assert.equal(error.code, "internal");
  assert.equal(reasonOf(error), LIFECYCLE_ERROR.authOperationFailed);

  const written = patches(recorded);
  assert.equal(written.length, 2, "esperado commit + compensacao");
  // Commit original ativou...
  assert.equal(written[0].patch.active, true);
  assert.equal(written[0].patch.status, ACTIVE_STATUS);
  // ...e a compensacao devolveu ao estado seguro (inativo).
  assert.equal(written[1].patch.active, false);
  assert.equal(written[1].patch.status, INACTIVE_STATUS);
  assert.equal(written[1].patch.updated_at, SERVER_TIMESTAMP);
  assert.equal(written[1].patch.updatedAt, SERVER_TIMESTAMP);
});

test("F7: compensacao da reativacao e auditada", async () => {
  const {deps, recorded} = harness({
    user: inactiveUser(),
    authFailure: {on: "enable", error: new Error("auth indisponivel")},
  });
  await expectFailure(() => reactivateHuman(deps, reactivatePayload()));
  const actions = recorded.auditEntries.map((entry) => entry.action);
  assert.deepEqual(actions, ["reactivated", "reactivation_compensated"]);
});

test("F8: reativacao com Auth E compensacao falhando => COMPENSATION_FAILED", async () => {
  const {deps} = harness({
    user: inactiveUser(),
    authFailure: {on: "enable", error: new Error("auth indisponivel")},
    transactionFailure: {onCall: 2, error: new Error("compensacao falhou")},
  });
  const error = await expectFailure(() =>
    reactivateHuman(deps, reactivatePayload()),
  );
  assert.equal(error.code, "internal");
  assert.equal(reasonOf(error), LIFECYCLE_ERROR.compensationFailed);
  assert.match(error.message, /divergente/i);
  assert.match(error.message, /auth indisponivel/);
  assert.match(error.message, /compensacao falhou/);
});

test("F9: nenhuma operacao retorna sucesso em estado parcial", async () => {
  // Desativacao com Firestore quebrado.
  const a = harness({
    transactionFailure: {onCall: 1, error: new Error("x")},
  });
  await expectAnyFailure(() => deactivateHuman(a.deps, deactivatePayload()));

  // Reativacao com Auth quebrado.
  const b = harness({
    user: inactiveUser(),
    authFailure: {on: "enable", error: new Error("y")},
  });
  await expectFailure(() => reactivateHuman(b.deps, reactivatePayload()));
  // Ambas falharam: nenhum `assert.fail` acima significa que nenhuma retornou.
});

test("F10: chamadas de Auth ocorrem FORA do callback da transacao", async () => {
  // Se Auth fosse chamado dentro do callback, um retry duplicaria o efeito.
  // Provamos a fronteira: na desativacao, o disable precede a abertura da
  // transacao; na reativacao, o enable sucede o patch.
  const deact = harness();
  await deactivateHuman(deact.deps, deactivatePayload());
  const deactKinds = deact.recorded.effects.map((effect) => effect.kind);
  assert.ok(
    deactKinds.indexOf("authDisable") < deactKinds.indexOf("transaction"),
  );

  const react = harness({user: inactiveUser()});
  await reactivateHuman(react.deps, reactivatePayload());
  const reactKinds = react.recorded.effects.map((effect) => effect.kind);
  assert.ok(
    reactKinds.indexOf("authDisable") > reactKinds.indexOf("firestorePatch"),
  );
});

// ---------------------------------------------------------------------------
// G. HELPER isCurrentlyActive
// ---------------------------------------------------------------------------

// ---------------------------------------------------------------------------
// R1-D. ACTIVE SHIFT RACE (finding B2/D-1)
// ---------------------------------------------------------------------------

test("R1-D1: turno aberto APOS o precheck e capturado na transacao => ACTIVE_SHIFT", async () => {
  // Race: T0 precheck sem turno, T1 turno abre, T2 transacao commitaria.
  const {deps, recorded} = harness({
    activeShift: null,
    activeShiftInTransaction: {status: "active"},
  });
  const error = await expectFailure(() =>
    deactivateHuman(deps, deactivatePayload()),
  );
  assert.equal(error.code, "failed-precondition");
  assert.equal(reasonOf(error), LIFECYCLE_ERROR.activeShift);
  // Nenhum estado de lifecycle foi persistido.
  assert.deepEqual(patches(recorded), []);
});

test("R1-D2: o guard transacional aborta e o Auth volta ao estado anterior", async () => {
  const {deps, recorded} = harness({
    activeShift: null,
    activeShiftInTransaction: {status: "active"},
    priorAuthDisabled: false,
  });
  await expectFailure(() => deactivateHuman(deps, deactivatePayload()));
  // disable seguido de restauracao para o valor previo.
  assert.deepEqual(authCalls(recorded), [
    {kind: "authDisable", uid: TARGET_UID, disabled: true},
    {kind: "authDisable", uid: TARGET_UID, disabled: false},
  ]);
});

test("R1-D3: getActiveShift e chamado DENTRO da transacao", async () => {
  const {deps, recorded} = harness();
  await deactivateHuman(deps, deactivatePayload());
  assert.deepEqual(recorded.transactionShiftReads, [TARGET_RA]);
});

test("R1-D4: leitura transacional do turno precede a escrita", async () => {
  const {deps, recorded} = harness();
  await deactivateHuman(deps, deactivatePayload());
  const kinds = recorded.effects.map((effect) => effect.kind);
  // authDisable -> transaction -> firestorePatch, e o read do turno acontece
  // dentro da transacao antes do patch (provado por R1-D1 abortar o patch).
  assert.deepEqual(kinds, ["authDisable", "transaction", "firestorePatch"]);
  assert.equal(recorded.transactionShiftReads.length, 1);
});

// ---------------------------------------------------------------------------
// R1-F. AUTH PRIOR STATE (finding B2/F-5)
// ---------------------------------------------------------------------------

test("R1-F1: prior disabled=false => compensacao restaura false", async () => {
  const {deps, recorded} = harness({
    priorAuthDisabled: false,
    transactionFailure: {onCall: 1, error: new Error("firestore indisponivel")},
  });
  await expectAnyFailure(() => deactivateHuman(deps, deactivatePayload()));
  const auth = authCalls(recorded);
  assert.equal(auth.length, 2);
  assert.equal(auth[1].disabled, false);
});

/**
 * R1-F2 (revisto em B1.R2): a garantia F-5 ficou MAIS forte, nao mais fraca.
 *
 * Em B1.R1 a conta era desabilitada incondicionalmente e a compensacao tinha de
 * restaurar `priorAuthDisabled`. Agora uma conta que JA esta desabilitada nunca
 * e mutada — portanto nao existe nada a compensar, e e estruturalmente
 * impossivel que um caminho de erro a habilite.
 */
test("R1-F2: conta ja desabilitada nunca e mutada, logo nada a compensar", async () => {
  const {deps, recorded} = harness({
    priorAuthDisabled: true,
    transactionFailure: {onCall: 1, error: new Error("firestore indisponivel")},
  });
  await expectAnyFailure(() => deactivateHuman(deps, deactivatePayload()));
  // ZERO chamadas de Auth: nem mutacao, nem compensacao.
  assert.deepEqual(authCalls(recorded), []);
});

test("R1-F2b: desativacao com conta ja desabilitada reporta already_converged", async () => {
  const {deps, recorded} = harness({priorAuthDisabled: true});
  const result = await deactivateHuman(deps, deactivatePayload());
  assert.equal(result.authState, "already_converged");
  assert.deepEqual(authCalls(recorded), []);
  // O lifecycle do Firestore ainda transiciona normalmente.
  assert.equal(patches(recorded).length, 1);
});

test("R1-F3: o estado previo de Auth e lido ANTES de qualquer mutacao", async () => {
  const {deps, recorded} = harness();
  await deactivateHuman(deps, deactivatePayload());
  assert.deepEqual(recorded.authDisabledReads, [TARGET_UID]);
  // A leitura precede o primeiro efeito registrado.
  assert.equal(recorded.effects[0].kind, "authDisable");
});

test("R1-F4: uid presente com conta inexistente => DANGLING, zero mutacao", async () => {
  const {deps, recorded} = harness({
    authAccountMissing: true,
  });
  const error = await expectFailure(() =>
    deactivateHuman(deps, deactivatePayload()),
  );
  assert.equal(error.code, "failed-precondition");
  assert.equal(reasonOf(error), LIFECYCLE_ERROR.authIdentityNotFound);
  assert.deepEqual(recorded.effects, []);
});

// ---------------------------------------------------------------------------
// R1-I. AUTH IDENTITY REQUIRED (finding B2/I-1)
// ---------------------------------------------------------------------------

/**
 * R1-I1/I2 (revistos em B1.R2 sob A1.S1): a ausencia de alias de uid deixou de
 * ser erro. Antes de concluir ABSENT, o modulo ainda tenta o fallback canonico
 * por e-mail — o mesmo de adminAssignAccessProfile. So a ausencia nos DOIS
 * caminhos caracteriza CASE 1.
 */
test("R1-I1: sem alias, o fallback canonico por e-mail e consultado antes de concluir ABSENT", async () => {
  const user = activeUser();
  delete user.auth_uid;
  const {deps, recorded} = harness({user});
  await deactivateHuman(deps, deactivatePayload());
  // Nao leu por uid (nao havia) e consultou o e-mail canonico.
  assert.deepEqual(recorded.authDisabledReads, []);
  assert.deepEqual(recorded.emailLookups, [`${TARGET_RA}@gcm.com.br`]);
});

test("R1-I1b: quando o documento tem `email`, ele e a identidade consultada", async () => {
  const user = activeUser({email: "silva.9001@gcm.com.br"});
  delete user.auth_uid;
  const {deps, recorded} = harness({user});
  await deactivateHuman(deps, deactivatePayload());
  assert.deepEqual(recorded.emailLookups, ["silva.9001@gcm.com.br"]);
});

test("R1-I2: sem alias mas COM conta pelo e-mail => tratado como PRESENT", async () => {
  const user = activeUser();
  delete user.auth_uid;
  const {deps, recorded} = harness({
    user,
    authByEmail: {uid: "uid-por-email", disabled: false},
  });
  const result = await deactivateHuman(deps, deactivatePayload());
  // A conta existe: o acesso E suspenso, apesar de o documento nao espelhar o uid.
  assert.equal(result.authState, "updated");
  assert.deepEqual(authCalls(recorded), [
    {kind: "authDisable", uid: "uid-por-email", disabled: true},
  ]);
});

test("R1-I2b: sem e-mail no documento, o fallback usa o padrao institucional do RA", async () => {
  const user = activeUser();
  delete user.auth_uid;
  delete user.email;
  const {deps, recorded} = harness({user});
  await deactivateHuman(deps, deactivatePayload());
  // Deriva <ra>@gcm.com.br, NUNCA institutional_email.
  assert.deepEqual(recorded.emailLookups, [`${TARGET_RA}@gcm.com.br`]);
});

test("R1-I2c: institutional_email NAO e usado como identidade de Auth", async () => {
  const user = activeUser();
  delete user.auth_uid;
  delete user.email;
  user.institutional_email = "outro.endereco@prefeitura.gov.br";
  const {deps, recorded} = harness({user});
  await deactivateHuman(deps, deactivatePayload());
  assert.deepEqual(recorded.emailLookups, [`${TARGET_RA}@gcm.com.br`]);
  assert.ok(
    !recorded.emailLookups.includes("outro.endereco@prefeitura.gov.br"),
    "institutional_email pertence a Personnel, nao a conta de acesso",
  );
});

test("R1-I3: aliases authUid/uid sao aceitos como identidade", async () => {
  for (const alias of ["authUid", "uid"]) {
    const user = activeUser();
    delete user.auth_uid;
    user[alias] = TARGET_UID;
    const {deps, recorded} = harness({user});
    await deactivateHuman(deps, deactivatePayload());
    assert.equal(patches(recorded).length, 1, `alias ${alias}`);
  }
});

// ---------------------------------------------------------------------------
// R1-G1. EXACT REACTIVATION RESTORE (finding B2/G-1)
// ---------------------------------------------------------------------------

test("R1-G1a: compensacao restaura EXATAMENTE os deleted_* originais", async () => {
  const user = inactiveUser({
    deleted_at: "ORIGINAL_A",
    deleted_by: "ORIGINAL_B",
    delete_reason: "ORIGINAL_C",
    deleted_reason: "ORIGINAL_D",
  });
  const {deps, recorded} = harness({
    user,
    authFailure: {on: "enable", error: new Error("auth indisponivel")},
  });
  await expectFailure(() => reactivateHuman(deps, reactivatePayload()));

  const written = patches(recorded);
  assert.equal(written.length, 2, "commit + compensacao");
  const compensation = written[1].patch;
  // Valores ORIGINAIS restaurados, nao apagados nem substituidos.
  assert.equal(compensation.deleted_at, "ORIGINAL_A");
  assert.equal(compensation.deleted_by, "ORIGINAL_B");
  assert.equal(compensation.delete_reason, "ORIGINAL_C");
  assert.equal(compensation.deleted_reason, "ORIGINAL_D");
  assert.equal(compensation.active, false);
  assert.equal(compensation.status, INACTIVE_STATUS);
});

test("R1-G1b: campo originalmente AUSENTE volta a ficar ausente, nao null", async () => {
  const user = inactiveUser();
  // Estado legado: inativo sem os aliases redundantes.
  delete user.deleted_reason;
  delete user.delete_reason;
  const {deps, recorded} = harness({
    user,
    authFailure: {on: "enable", error: new Error("auth indisponivel")},
  });
  await expectFailure(() => reactivateHuman(deps, reactivatePayload()));

  const compensation = patches(recorded)[1].patch;
  // Ausente antes => removido na restauracao (delete sentinel), nunca null.
  assert.equal(compensation.deleted_reason, DELETE_SENTINEL);
  assert.equal(compensation.delete_reason, DELETE_SENTINEL);
  assert.notEqual(compensation.deleted_reason, null);
  // Presentes antes => valor original.
  assert.equal(compensation.deleted_at, "DELETED_AT_SENTINEL");
});

test("R1-G1c: compensacao nao toca acesso, roles, claims nem Personnel", async () => {
  const {deps, recorded} = harness({
    user: inactiveUser(),
    authFailure: {on: "enable", error: new Error("auth indisponivel")},
  });
  await expectFailure(() => reactivateHuman(deps, reactivatePayload()));
  const compensation = patches(recorded)[1].patch;
  for (const preserved of [
    "roles",
    "accessLevel",
    "access_profile",
    "claim_role",
    "claim_updated_at",
    "specialties",
    "name",
    "auth_uid",
  ]) {
    assert.ok(!(preserved in compensation), `${preserved} nao deve ser tocado`);
  }
  // Conjunto de chaves fechado: lifecycle + espelhos + audit.
  assert.deepEqual(
    Object.keys(compensation).sort(),
    [
      "active",
      "status",
      "deleted_at",
      "deleted_by",
      "delete_reason",
      "deleted_reason",
      "updated_at",
      "updatedAt",
      "audit_trail",
    ].sort(),
  );
});

test("R1-G1d: espelhos da compensacao refletem a compensacao, nao a versao antiga", async () => {
  const {deps, recorded} = harness({
    user: inactiveUser(),
    authFailure: {on: "enable", error: new Error("auth indisponivel")},
  });
  await expectFailure(() => reactivateHuman(deps, reactivatePayload()));
  const compensation = patches(recorded)[1].patch;
  assert.equal(compensation.updated_at, SERVER_TIMESTAMP);
  assert.equal(compensation.updatedAt, SERVER_TIMESTAMP);
});

// ---------------------------------------------------------------------------
// R2-G2. COMPENSATION CAS POR INVARIANTE DE LIFECYCLE (findings G-2 / RA-1)
//
// B2.RA provou que `read-after-commit` NAO identifica autoria: um writer que
// escrevesse entre o commit e a releitura teria a SUA versao adotada como
// `producedVersion`, aprovando o CAS e permitindo clobber. O mecanismo agora
// compara o ESTADO DE LIFECYCLE, nao um timestamp global — e por isso escritas
// concorrentes em Personnel/Access deixam de ser falsos conflitos.
// ---------------------------------------------------------------------------

const AUTH_ENABLE_FAILS = {
  on: "enable" as const,
  error: new Error("auth indisponivel"),
};

test("R2-G2a: lifecycle intacto apos o commit => compensacao permitida", async () => {
  const {deps, recorded} = harness({
    user: inactiveUser(),
    authFailure: AUTH_ENABLE_FAILS,
  });
  const error = await expectFailure(() =>
    reactivateHuman(deps, reactivatePayload()),
  );
  assert.equal(reasonOf(error), LIFECYCLE_ERROR.authOperationFailed);
  assert.equal(patches(recorded).length, 2, "commit + compensacao");
});

test("R2-G2b: writer concorrente de LIFECYCLE => ZERO write, COMPENSATION_FAILED", async () => {
  const {deps, recorded} = harness({
    user: inactiveUser(),
    authFailure: AUTH_ENABLE_FAILS,
    // Outra sessao desativou o integrante entre o nosso commit e a compensacao.
    concurrentWrite: {active: false, status: INACTIVE_STATUS},
  });
  const error = await expectFailure(() =>
    reactivateHuman(deps, reactivatePayload()),
  );
  assert.equal(error.code, "internal");
  assert.equal(reasonOf(error), LIFECYCLE_ERROR.compensationFailed);
  assert.equal(patches(recorded).length, 1, "somente o commit da reativacao");
});

test("R2-G2c: marker deleted_* reintroduzido por outro writer tambem bloqueia", async () => {
  const {deps, recorded} = harness({
    user: inactiveUser(),
    authFailure: AUTH_ENABLE_FAILS,
    concurrentWrite: {deleted_at: "OUTRO_WRITER"},
  });
  const error = await expectFailure(() =>
    reactivateHuman(deps, reactivatePayload()),
  );
  assert.equal(reasonOf(error), LIFECYCLE_ERROR.compensationFailed);
  assert.equal(patches(recorded).length, 1);
});

test("R2-G2d: writer concorrente de PERSONNEL nao bloqueia a compensacao", async () => {
  const {deps, recorded} = harness({
    user: inactiveUser(),
    authFailure: AUTH_ENABLE_FAILS,
    // Alteracao legitima de Personnel: irrelevante para o dominio lifecycle.
    concurrentWrite: {telefone: "11999998888", unit: "GCM Centro"},
  });
  const error = await expectFailure(() =>
    reactivateHuman(deps, reactivatePayload()),
  );
  // A compensacao ACONTECE: um timestamp global teria produzido falso conflito.
  assert.equal(reasonOf(error), LIFECYCLE_ERROR.authOperationFailed);
  assert.equal(patches(recorded).length, 2);
});

test("R2-G2e: writer concorrente de ACCESS nao bloqueia a compensacao", async () => {
  const {deps, recorded} = harness({
    user: inactiveUser(),
    authFailure: AUTH_ENABLE_FAILS,
    concurrentWrite: {access_profile: "operador_k9", claim_role: "condutor"},
  });
  const error = await expectFailure(() =>
    reactivateHuman(deps, reactivatePayload()),
  );
  assert.equal(reasonOf(error), LIFECYCLE_ERROR.authOperationFailed);
  assert.equal(patches(recorded).length, 2);
});

test("R2-G2f: a compensacao NAO sobrescreve os campos do writer concorrente", async () => {
  const {deps, recorded} = harness({
    user: inactiveUser(),
    authFailure: AUTH_ENABLE_FAILS,
    concurrentWrite: {telefone: "11999998888", access_profile: "operador_k9"},
  });
  await expectFailure(() => reactivateHuman(deps, reactivatePayload()));
  const compensation = patches(recorded)[1].patch;
  // O patch toca somente lifecycle + espelhos + audit.
  assert.ok(!("telefone" in compensation));
  assert.ok(!("access_profile" in compensation));
  assert.deepEqual(
    Object.keys(compensation).sort(),
    [
      "active",
      "status",
      "deleted_at",
      "deleted_by",
      "delete_reason",
      "deleted_reason",
      "updated_at",
      "updatedAt",
      "audit_trail",
    ].sort(),
  );
});

test("R2-G2g: recusa por concorrencia de lifecycle e reportada como tal", async () => {
  const {deps} = harness({
    user: inactiveUser(),
    authFailure: {on: "enable", error: new Error("auth caiu")},
    concurrentWrite: {active: false},
  });
  const error = await expectFailure(() =>
    reactivateHuman(deps, reactivatePayload()),
  );
  assert.match(error.message, /concurrent lifecycle modification/i);
  assert.match(error.message, /RECUSADA|Nada foi sobrescrito/i);
  // O erro original de Auth e preservado.
  assert.match(error.message, /auth caiu/);
});

test("R2-G2h: a compensacao LE o documento antes de escrever (CAS real)", async () => {
  const {deps, recorded} = harness({
    user: inactiveUser(),
    authFailure: AUTH_ENABLE_FAILS,
  });
  await expectFailure(() => reactivateHuman(deps, reactivatePayload()));
  const transactions = recorded.effects.filter(
    (effect) => effect.kind === "transaction",
  );
  assert.equal(transactions.length, 2);
});

test("R2-G2i: read-after-commit deixou de existir como prova de autoria", async () => {
  // Antes havia uma releitura EXTRA de users/{ra} entre o commit e o Auth,
  // usada para derivar `producedVersion`. Ela foi removida: agora o unico
  // getUser fora de transacao e o pre-state.
  const {deps, recorded} = harness({user: inactiveUser()});
  await reactivateHuman(deps, reactivatePayload());
  assert.equal(recorded.userReads, 1, "somente a leitura de pre-estado");
});

// ---------------------------------------------------------------------------
// R1-K. AUDIT DA COMPENSACAO
// ---------------------------------------------------------------------------

test("R1-K1: compensacao recusada por concorrencia nao grava audit", async () => {
  const {deps, recorded} = harness({
    user: inactiveUser(),
    authFailure: AUTH_ENABLE_FAILS,
    concurrentWrite: {active: false},
  });
  await expectFailure(() => reactivateHuman(deps, reactivatePayload()));
  assert.deepEqual(
    recorded.auditEntries.map((entry) => entry.action),
    ["reactivated"],
  );
});

// ---------------------------------------------------------------------------
// R2-NA. NO-AUTH LIFECYCLE (A1.S1 CASE 1)
// ---------------------------------------------------------------------------

/** Documento de Personnel sem qualquer vinculo de Auth (padrao Create V1). */
function personnelWithoutAuth(overrides: JsonMap = {}): JsonMap {
  const user = activeUser(overrides);
  delete user.auth_uid;
  return user;
}

test("R2-NA1: ativo + ABSENT => desativacao sucede, zero chamada de Auth", async () => {
  const {deps, recorded} = harness({user: personnelWithoutAuth()});
  const result = await deactivateHuman(deps, deactivatePayload());
  assert.equal(result.authState, "not_provisioned");
  const [{patch}] = patches(recorded);
  assert.equal(patch.active, false);
  assert.equal(patch.status, INACTIVE_STATUS);
  assert.deepEqual(authCalls(recorded), []);
});

test("R2-NA2: inativo + ABSENT => reativacao sucede, zero chamada de Auth", async () => {
  const user = personnelWithoutAuth({
    active: false,
    status: INACTIVE_STATUS,
    deleted_at: "X",
    deleted_by: "Y",
    delete_reason: "Z",
    deleted_reason: "Z",
  });
  const {deps, recorded} = harness({user});
  const result = await reactivateHuman(deps, reactivatePayload());
  assert.equal(result.authState, "not_provisioned");
  const [{patch}] = patches(recorded);
  assert.equal(patch.active, true);
  assert.equal(patch.status, ACTIVE_STATUS);
  assert.equal(patch.deleted_at, DELETE_SENTINEL);
  assert.deepEqual(authCalls(recorded), []);
});

test("R2-NA3: ativo + ABSENT => reativacao e ALREADY_IN_STATE", async () => {
  const {deps, recorded} = harness({user: personnelWithoutAuth()});
  const error = await expectFailure(() =>
    reactivateHuman(deps, reactivatePayload()),
  );
  assert.equal(reasonOf(error), LIFECYCLE_ERROR.alreadyInState);
  assert.deepEqual(recorded.effects, []);
});

test("R2-NA4: inativo + ABSENT => desativacao e ALREADY_IN_STATE", async () => {
  const user = personnelWithoutAuth({active: false, status: INACTIVE_STATUS});
  const {deps, recorded} = harness({user});
  const error = await expectFailure(() =>
    deactivateHuman(deps, deactivatePayload()),
  );
  assert.equal(reasonOf(error), LIFECYCLE_ERROR.alreadyInState);
  assert.deepEqual(recorded.effects, []);
});

test("R2-NA5: nenhuma operacao cria conta de Auth", async () => {
  // A interface de deps nao expoe createUser: a impossibilidade e ESTRUTURAL.
  const {deps} = harness({user: personnelWithoutAuth()});
  assert.ok(!("createAuthAccount" in deps));
  assert.ok(!("createUser" in deps));
  await deactivateHuman(deps, deactivatePayload());
});

test("R2-NA6: no-auth produz audit lifecycle NORMAL, nao de reconciliacao", async () => {
  const {deps, recorded} = harness({user: personnelWithoutAuth()});
  await deactivateHuman(deps, deactivatePayload());
  assert.deepEqual(
    recorded.auditEntries.map((entry) => entry.action),
    ["deactivated"],
  );
});

// ---------------------------------------------------------------------------
// R2-DG. DANGLING UID (A1.S1 CASE 2)
// ---------------------------------------------------------------------------

test("R2-DG1: uid presente + conta inexistente => desativacao FAIL CLOSED", async () => {
  const {deps, recorded} = harness({authAccountMissing: true});
  const error = await expectFailure(() =>
    deactivateHuman(deps, deactivatePayload()),
  );
  assert.equal(error.code, "failed-precondition");
  assert.equal(reasonOf(error), LIFECYCLE_ERROR.authIdentityNotFound);
  assert.deepEqual(recorded.effects, []);
});

test("R2-DG2: uid presente + conta inexistente => reativacao FAIL CLOSED", async () => {
  const {deps, recorded} = harness({
    user: inactiveUser(),
    authAccountMissing: true,
  });
  const error = await expectFailure(() =>
    reactivateHuman(deps, reactivatePayload()),
  );
  assert.equal(reasonOf(error), LIFECYCLE_ERROR.authIdentityNotFound);
  assert.deepEqual(recorded.effects, []);
});

test("R2-DG3: DANGLING nao e confundido com ABSENT", async () => {
  // ABSENT sucede...
  const absent = harness({user: personnelWithoutAuth()});
  await deactivateHuman(absent.deps, deactivatePayload());
  // ...e DANGLING falha, apesar de ambos "nao terem conta".
  const dangling = harness({authAccountMissing: true});
  const error = await expectFailure(() =>
    deactivateHuman(dangling.deps, deactivatePayload()),
  );
  assert.equal(reasonOf(error), LIFECYCLE_ERROR.authIdentityNotFound);
  assert.notEqual(reasonOf(error), LIFECYCLE_ERROR.alreadyInState);
});

// ---------------------------------------------------------------------------
// R2-RC. RECONCILIACAO DE DRIFT GLOBAL (finding RA-2)
// ---------------------------------------------------------------------------

test("R2-RC1: inativo + Auth ENABLED => desativacao reconcilia o Auth", async () => {
  // O drift perigoso: formalmente inativo, mas ainda conseguindo entrar.
  const {deps, recorded} = harness({
    user: inactiveUser(),
    priorAuthDisabled: false,
  });
  const result = await deactivateHuman(deps, deactivatePayload());
  assert.equal(result.reconciliationOnly, true);
  assert.equal(result.authState, "updated");
  assert.deepEqual(authCalls(recorded), [
    {kind: "authDisable", uid: TARGET_UID, disabled: true},
  ]);
});

test("R2-RC2: a reconciliacao NAO sobrescreve os deleted_* originais", async () => {
  const {deps, recorded} = harness({
    user: inactiveUser({
      deleted_at: "ORIGINAL_A",
      deleted_by: "ORIGINAL_B",
      delete_reason: "motivo original",
      deleted_reason: "motivo original",
    }),
    priorAuthDisabled: false,
  });
  await deactivateHuman(deps, deactivatePayload({reason: "corrigindo acesso"}));
  const [{patch}] = patches(recorded);
  // Nenhum campo de lifecycle e tocado: so espelhos + auditoria.
  for (const field of [
    "active",
    "status",
    "deleted_at",
    "deleted_by",
    "delete_reason",
    "deleted_reason",
  ]) {
    assert.ok(!(field in patch), `${field} nao deve ser reescrito`);
  }
  assert.deepEqual(Object.keys(patch).sort(), [
    "audit_trail",
    "updatedAt",
    "updated_at",
  ]);
});

test("R2-RC3: ativo + Auth DISABLED => reativacao reconcilia o Auth", async () => {
  const {deps, recorded} = harness({priorAuthDisabled: true});
  const result = await reactivateHuman(deps, reactivatePayload());
  assert.equal(result.reconciliationOnly, true);
  assert.deepEqual(authCalls(recorded), [
    {kind: "authDisable", uid: TARGET_UID, disabled: false},
  ]);
});

test("R2-RC4: a reconciliacao de reativacao NAO reescreve o lifecycle", async () => {
  const {deps, recorded} = harness({priorAuthDisabled: true});
  await reactivateHuman(deps, reactivatePayload());
  const [{patch}] = patches(recorded);
  assert.ok(!("active" in patch));
  assert.ok(!("status" in patch));
  assert.deepEqual(Object.keys(patch).sort(), [
    "audit_trail",
    "updatedAt",
    "updated_at",
  ]);
});

test("R2-RC5: reconciliacao usa acoes de audit DISTINTAS", async () => {
  const disable = harness({user: inactiveUser(), priorAuthDisabled: false});
  await deactivateHuman(disable.deps, deactivatePayload());
  assert.deepEqual(
    disable.recorded.auditEntries.map((entry) => entry.action),
    [AUDIT_ACTION.authReconciledDisabled],
  );
  // NUNCA "deactivated": nao houve transicao de Personnel.
  assert.notEqual(
    disable.recorded.auditEntries[0].action,
    AUDIT_ACTION.deactivated,
  );

  const enable = harness({priorAuthDisabled: true});
  await reactivateHuman(enable.deps, reactivatePayload());
  assert.deepEqual(
    enable.recorded.auditEntries.map((entry) => entry.action),
    [AUDIT_ACTION.authReconciledEnabled],
  );
  assert.notEqual(
    enable.recorded.auditEntries[0].action,
    AUDIT_ACTION.reactivated,
  );
});

test("R2-RC6: reconciliacao de desativacao NAO exige guard de turno", async () => {
  // Nao estamos afastando ninguem: o integrante ja esta formalmente inativo.
  // Recusar por turno aberto deixaria o acesso indevido no ar.
  const {deps, recorded} = harness({
    user: inactiveUser(),
    priorAuthDisabled: false,
    activeShift: {status: "active"},
  });
  const result = await deactivateHuman(deps, deactivatePayload());
  assert.equal(result.reconciliationOnly, true);
  assert.deepEqual(recorded.activeShiftReads, []);
});

test("R2-RC7: ALREADY_IN_STATE somente quando Personnel E Auth convergem", async () => {
  // Inativo + desabilitado => convergido => ALREADY.
  const converged = harness({user: inactiveUser(), priorAuthDisabled: true});
  const error = await expectFailure(() =>
    deactivateHuman(converged.deps, deactivatePayload()),
  );
  assert.equal(reasonOf(error), LIFECYCLE_ERROR.alreadyInState);

  // Inativo + habilitado => NAO convergido => reconcilia em vez de recusar.
  const drifted = harness({user: inactiveUser(), priorAuthDisabled: false});
  const result = await deactivateHuman(drifted.deps, deactivatePayload());
  assert.equal(result.reconciliationOnly, true);
});

test("R2-RC8: ativo + Auth enabled => reativacao permanece ALREADY_IN_STATE", async () => {
  const {deps, recorded} = harness({priorAuthDisabled: false});
  const error = await expectFailure(() =>
    reactivateHuman(deps, reactivatePayload()),
  );
  assert.equal(reasonOf(error), LIFECYCLE_ERROR.alreadyInState);
  assert.deepEqual(recorded.effects, []);
});

// ---------------------------------------------------------------------------
// RB1. AUTH_APPLIED_AUDIT_FAILED (finding B2.RB/RB-1)
//
// Cenario: Personnel JA inativo + conta ainda habilitada (o drift perigoso).
// A reconciliacao desabilita a conta com sucesso e a escrita de auditoria falha.
// A politica mantem a conta desabilitada de proposito — logo NAO houve
// compensacao, e rotular como COMPENSATION_FAILED diria ao caller que a
// operacao nao teve efeito, quando o acesso FOI suspenso.
// ---------------------------------------------------------------------------

/** Harness do cenario RB-1: drift + falha na escrita de auditoria. */
function auditFailureOnReconciliation() {
  return harness({
    user: inactiveUser({
      deleted_at: "ORIGINAL_A",
      deleted_by: "ORIGINAL_B",
      delete_reason: "motivo original",
      deleted_reason: "motivo original",
    }),
    priorAuthDisabled: false,
    transactionFailure: {onCall: 1, error: new Error("firestore indisponivel")},
  });
}

test("RB1-1: Auth aplicado + audit falha => AUTH_APPLIED_AUDIT_FAILED", async () => {
  const {deps} = auditFailureOnReconciliation();
  const error = await expectFailure(() =>
    deactivateHuman(deps, deactivatePayload()),
  );
  assert.equal(error.code, "internal");
  assert.equal(reasonOf(error), LIFECYCLE_ERROR.authAppliedAuditFailed);
});

test("RB1-2: esse caminho NAO usa mais COMPENSATION_FAILED", async () => {
  const {deps} = auditFailureOnReconciliation();
  const error = await expectFailure(() =>
    deactivateHuman(deps, deactivatePayload()),
  );
  assert.notEqual(reasonOf(error), LIFECYCLE_ERROR.compensationFailed);
  // A mensagem afirma que o acesso FOI suspenso, nao que nada aconteceu.
  assert.match(error.message, /acesso foi suspenso/i);
  assert.match(error.message, /permanece desabilitada/i);
  assert.match(error.message, /Atualize os dados/i);
});

test("RB1-3: a conta permanece desabilitada", async () => {
  const {deps, recorded} = auditFailureOnReconciliation();
  await expectFailure(() => deactivateHuman(deps, deactivatePayload()));
  assert.deepEqual(authCalls(recorded), [
    {kind: "authDisable", uid: TARGET_UID, disabled: true},
  ]);
});

test("RB1-4: nenhuma chamada de re-enable acontece", async () => {
  const {deps, recorded} = auditFailureOnReconciliation();
  await expectFailure(() => deactivateHuman(deps, deactivatePayload()));
  const reEnables = authCalls(recorded).filter(
    (call) => call.disabled === false,
  );
  assert.deepEqual(
    reEnables,
    [],
    "reabilitar devolveria acesso a alguem formalmente inativo",
  );
});

test("RB1-5: os deleted_* originais permanecem preservados", async () => {
  const {deps, recorded} = auditFailureOnReconciliation();
  await expectFailure(() => deactivateHuman(deps, deactivatePayload()));
  // A transacao falhou: nenhum patch chegou a ser emitido.
  assert.deepEqual(patches(recorded), []);
  // E nenhum campo de lifecycle seria tocado nem no caminho de sucesso (R2-RC2).
});

test("RB1-6: details declaram inequivocamente o que foi aplicado", async () => {
  const {deps} = auditFailureOnReconciliation();
  const error = await expectFailure(() =>
    deactivateHuman(deps, deactivatePayload()),
  );
  const details = error.details as Record<string, unknown>;
  assert.equal(details.reason, LIFECYCLE_ERROR.authAppliedAuditFailed);
  assert.equal(details.authApplied, true);
  assert.equal(details.authDisabled, true);
  assert.equal(details.personnelChanged, false);
});

test("RB1-7: chamada subsequente ja convergida e nao destrutiva", async () => {
  // Depois do RB-1, o estado real e: Personnel inativo + Auth desabilitado.
  // Um retry do caller deve ser inofensivo.
  const {deps, recorded} = harness({
    user: inactiveUser({
      deleted_at: "ORIGINAL_A",
      deleted_by: "ORIGINAL_B",
      delete_reason: "motivo original",
      deleted_reason: "motivo original",
    }),
    priorAuthDisabled: true,
  });
  const error = await expectFailure(() =>
    deactivateHuman(deps, deactivatePayload()),
  );
  assert.equal(reasonOf(error), LIFECYCLE_ERROR.alreadyInState);
  // Zero efeito: nao habilita, nao desabilita, nao escreve.
  assert.deepEqual(recorded.effects, []);
});

test("RB1-8: o novo reason NAO vaza para outros caminhos", async () => {
  // Transicao normal bem-sucedida.
  const normal = harness({priorAuthDisabled: false});
  await deactivateHuman(normal.deps, deactivatePayload());

  // Falha de Firestore na transicao normal continua COMPENSATION_FAILED-free
  // (propaga o erro cru) e jamais usa o reason novo.
  const transition = harness({
    priorAuthDisabled: false,
    transactionFailure: {onCall: 1, error: new Error("x")},
  });
  const transitionError = await expectAnyFailure(() =>
    deactivateHuman(transition.deps, deactivatePayload()),
  );
  if (transitionError instanceof HttpsError) {
    assert.notEqual(
      reasonOf(transitionError),
      LIFECYCLE_ERROR.authAppliedAuditFailed,
    );
  }

  // Compensacao recusada por concorrencia continua COMPENSATION_FAILED.
  const concurrent = harness({
    user: inactiveUser(),
    authFailure: AUTH_ENABLE_FAILS,
    concurrentWrite: {active: false},
  });
  const concurrentError = await expectFailure(() =>
    reactivateHuman(concurrent.deps, reactivatePayload()),
  );
  assert.equal(reasonOf(concurrentError), LIFECYCLE_ERROR.compensationFailed);
  assert.notEqual(
    reasonOf(concurrentError),
    LIFECYCLE_ERROR.authAppliedAuditFailed,
  );
});

// ---------------------------------------------------------------------------
// R4. AUTH_ENABLE_REVERTED_AUDIT_FAILED — caso espelho [B1.R4]
//
// Personnel JA ativo + conta desabilitada. A reconciliacao habilita a conta, a
// escrita de auditoria falha, e a compensacao desabilita de volta COM SUCESSO.
// Nenhum acesso fica concedido — logo NAO e COMPENSATION_FAILED.
// ---------------------------------------------------------------------------

/** Harness do caso espelho: drift permissivo + falha de auditoria. */
function auditFailureOnReactivateReconciliation() {
  return harness({
    // Personnel ativo (fixture default) com a conta desabilitada.
    priorAuthDisabled: true,
    transactionFailure: {onCall: 1, error: new Error("firestore indisponivel")},
  });
}

test("R4-1: enable + audit falha + reversao OK => AUTH_ENABLE_REVERTED_AUDIT_FAILED", async () => {
  const {deps} = auditFailureOnReactivateReconciliation();
  const error = await expectFailure(() =>
    reactivateHuman(deps, reactivatePayload()),
  );
  assert.equal(error.code, "internal");
  assert.equal(
    reasonOf(error),
    LIFECYCLE_ERROR.authEnableRevertedAuditFailed,
  );
});

test("R4-2: o reason NAO e COMPENSATION_FAILED", async () => {
  const {deps} = auditFailureOnReactivateReconciliation();
  const error = await expectFailure(() =>
    reactivateHuman(deps, reactivatePayload()),
  );
  assert.notEqual(reasonOf(error), LIFECYCLE_ERROR.compensationFailed);
  // A mensagem afirma reversao bem-sucedida, nao rollback falho.
  assert.match(error.message, /foi revertida/i);
  assert.match(error.message, /permanece desabilitada/i);
  assert.match(error.message, /Atualize os dados/i);
  // E nao sugere que o acesso possa ter ficado concedido.
  assert.ok(!/nao pude ser desabilitada/i.test(error.message));
});

test("R4-3: o estado final de Auth e disabled", async () => {
  const {deps, recorded} = auditFailureOnReactivateReconciliation();
  await expectFailure(() => reactivateHuman(deps, reactivatePayload()));
  const auth = authCalls(recorded);
  assert.equal(auth[auth.length - 1].disabled, true, "ultima mutacao desabilita");
});

test("R4-4: a compensacao chamou updateUser(disabled=true)", async () => {
  const {deps, recorded} = auditFailureOnReactivateReconciliation();
  await expectFailure(() => reactivateHuman(deps, reactivatePayload()));
  assert.deepEqual(authCalls(recorded), [
    {kind: "authDisable", uid: TARGET_UID, disabled: false},
    {kind: "authDisable", uid: TARGET_UID, disabled: true},
  ]);
});

test("R4-5: o lifecycle de Personnel nao foi alterado", async () => {
  const {deps, recorded} = auditFailureOnReactivateReconciliation();
  await expectFailure(() => reactivateHuman(deps, reactivatePayload()));
  // A transacao falhou: nenhum patch emitido, nenhum campo de lifecycle tocado.
  assert.deepEqual(patches(recorded), []);
});

test("R4-6: nenhum sucesso e retornado", async () => {
  const {deps} = auditFailureOnReactivateReconciliation();
  // expectFailure ja falha o teste se a operacao retornar.
  const error = await expectFailure(() =>
    reactivateHuman(deps, reactivatePayload()),
  );
  assert.ok(error instanceof HttpsError);
});

test("R4-7: detalhes declaram tentativa + reversao", async () => {
  const {deps} = auditFailureOnReactivateReconciliation();
  const error = await expectFailure(() =>
    reactivateHuman(deps, reactivatePayload()),
  );
  const details = error.details as Record<string, unknown>;
  assert.equal(details.reason, LIFECYCLE_ERROR.authEnableRevertedAuditFailed);
  assert.equal(details.authEnableAttempted, true);
  assert.equal(details.authReverted, true);
  assert.equal(details.authDisabled, true);
  assert.equal(details.personnelChanged, false);
});

test("R4-8: retry entra de novo em RECONCILIATION, nao em ALREADY_IN_STATE", async () => {
  // Estado apos o R4: Personnel ativo + Auth desabilitado. Nada escondido.
  const {deps, recorded} = harness({priorAuthDisabled: true});
  const result = await reactivateHuman(deps, reactivatePayload());
  assert.equal(result.reconciliationOnly, true);
  assert.equal(result.authState, "updated");
  assert.deepEqual(authCalls(recorded), [
    {kind: "authDisable", uid: TARGET_UID, disabled: false},
  ]);
});

test("R4-9: se a REVERSAO falhar, o reason volta a ser COMPENSATION_FAILED", async () => {
  // Este teste e o que separa "compensacao funcionou" de "compensacao falhou".
  const {deps} = harness({
    priorAuthDisabled: true,
    transactionFailure: {onCall: 1, error: new Error("firestore indisponivel")},
    // A reversao (disable) tambem falha.
    authFailure: {on: "disable", error: new Error("auth caiu")},
  });
  const error = await expectFailure(() =>
    reactivateHuman(deps, reactivatePayload()),
  );
  assert.equal(reasonOf(error), LIFECYCLE_ERROR.compensationFailed);
  assert.notEqual(
    reasonOf(error),
    LIFECYCLE_ERROR.authEnableRevertedAuditFailed,
  );
  // Aqui sim o estado e divergente e a mensagem precisa dizer isso.
  assert.match(error.message, /Estado divergente/i);
  assert.match(error.message, /acesso concedido sem auditoria/i);
});

test("R4-10: AUTH_APPLIED_AUDIT_FAILED continua exclusivo da desativacao", async () => {
  // O reason restritivo nao aparece no caminho permissivo.
  const mirror = auditFailureOnReactivateReconciliation();
  const mirrorError = await expectFailure(() =>
    reactivateHuman(mirror.deps, reactivatePayload()),
  );
  assert.notEqual(
    reasonOf(mirrorError),
    LIFECYCLE_ERROR.authAppliedAuditFailed,
  );

  // E o reason permissivo nao aparece no caminho restritivo.
  const restrictive = auditFailureOnReconciliation();
  const restrictiveError = await expectFailure(() =>
    deactivateHuman(restrictive.deps, deactivatePayload()),
  );
  assert.equal(
    reasonOf(restrictiveError),
    LIFECYCLE_ERROR.authAppliedAuditFailed,
  );
  assert.notEqual(
    reasonOf(restrictiveError),
    LIFECYCLE_ERROR.authEnableRevertedAuditFailed,
  );
});

test("R4-11: o reason novo nao aparece em transicoes normais", async () => {
  // Transicao normal de reativacao bem-sucedida.
  const ok = harness({user: inactiveUser()});
  await reactivateHuman(ok.deps, reactivatePayload());

  // Transicao normal com falha de Auth: usa AUTH_OPERATION_FAILED.
  const authFail = harness({
    user: inactiveUser(),
    authFailure: AUTH_ENABLE_FAILS,
  });
  const error = await expectFailure(() =>
    reactivateHuman(authFail.deps, reactivatePayload()),
  );
  assert.equal(reasonOf(error), LIFECYCLE_ERROR.authOperationFailed);
  assert.notEqual(
    reasonOf(error),
    LIFECYCLE_ERROR.authEnableRevertedAuditFailed,
  );
});

// ---------------------------------------------------------------------------
// RB4. PRESENCA != TRUTHINESS no CAS de lifecycle (finding B2.RB/RB-4)
// ---------------------------------------------------------------------------

test("RB4-1: deleted_at:null esta PRESENTE e bloqueia a compensacao", async () => {
  const {deps, recorded} = harness({
    user: inactiveUser(),
    authFailure: AUTH_ENABLE_FAILS,
    // Writer concorrente reintroduz a chave com valor null. `null` e um valor
    // presente: o invariante exige AUSENCIA.
    concurrentWrite: {deleted_at: null},
  });
  const error = await expectFailure(() =>
    reactivateHuman(deps, reactivatePayload()),
  );
  assert.equal(reasonOf(error), LIFECYCLE_ERROR.compensationFailed);
  assert.match(error.message, /concurrent lifecycle modification/i);
  // Somente o commit da reativacao; a compensacao NAO escreveu.
  assert.equal(patches(recorded).length, 1);
});

test("RB4-2: delete_reason:\"\" esta PRESENTE e bloqueia a compensacao", async () => {
  const {deps, recorded} = harness({
    user: inactiveUser(),
    authFailure: AUTH_ENABLE_FAILS,
    concurrentWrite: {delete_reason: ""},
  });
  const error = await expectFailure(() =>
    reactivateHuman(deps, reactivatePayload()),
  );
  assert.equal(reasonOf(error), LIFECYCLE_ERROR.compensationFailed);
  assert.equal(patches(recorded).length, 1);
});

test("RB4-3: falsy em active/status tambem bloqueia", async () => {
  for (const concurrentWrite of [
    {active: false},
    {status: ""},
    {status: "Ferias"},
  ]) {
    const {deps, recorded} = harness({
      user: inactiveUser(),
      authFailure: AUTH_ENABLE_FAILS,
      concurrentWrite,
    });
    const error = await expectFailure(() =>
      reactivateHuman(deps, reactivatePayload()),
    );
    assert.equal(
      reasonOf(error),
      LIFECYCLE_ERROR.compensationFailed,
      JSON.stringify(concurrentWrite),
    );
    assert.equal(patches(recorded).length, 1);
  }
});

test("R2-RC9: reconciliacao valida OCC contra o documento carregado", async () => {
  const {deps, recorded} = harness({
    user: inactiveUser(),
    priorAuthDisabled: false,
  });
  const error = await expectFailure(() =>
    deactivateHuman(deps, deactivatePayload({expectedUpdatedAt: 1})),
  );
  assert.equal(reasonOf(error), LIFECYCLE_ERROR.staleWrite);
  assert.deepEqual(recorded.effects, []);
});

// ---------------------------------------------------------------------------
// G. HELPER isCurrentlyActive
// ---------------------------------------------------------------------------

test("G1: isCurrentlyActive reconhece todos os sinais de arquivamento", async () => {
  assert.equal(isCurrentlyActive({active: true, status: "Ativo"}), true);
  assert.equal(isCurrentlyActive({}), true);
  assert.equal(isCurrentlyActive({active: false}), false);
  assert.equal(isCurrentlyActive({deleted_at: "x"}), false);
  assert.equal(isCurrentlyActive({archived_at: "x"}), false);
  assert.equal(isCurrentlyActive({status: "Inativo"}), false);
  assert.equal(isCurrentlyActive({status: "inativo"}), false);
  assert.equal(isCurrentlyActive({status: "inactive"}), false);
  // Valores nulos explicitos nao sao marcadores.
  assert.equal(isCurrentlyActive({deleted_at: null, archived_at: null}), true);
});
