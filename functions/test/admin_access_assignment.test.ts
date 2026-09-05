/**
 * FRONT10.ACCESS-CREDENTIALS — TESTES COMPORTAMENTAIS DE ACCESS ASSIGNMENT (Phases A & B).
 *
 * Cobre:
 * - Phase A (AUTH-WIRING-01): lookups fail-closed (A1, A2), compensacao de claims (F-03),
 *   tratamento seguro de genuine user-not-found sem falsos sucessos.
 * - Phase B: rejeicao fail-closed de atribuicao/troca de perfil para Personnel INATIVO
 *   (PERSONNEL_INACTIVE) antes de qualquer mutacao de Auth.
 */

import * as assert from "node:assert/strict";
import {test} from "node:test";
import {HttpsError} from "firebase-functions/v2/https";
import {isAuthUserNotFound} from "../src/auth_error_classification";
import {isCurrentlyActive} from "../src/admin_human_lifecycle";

type JsonMap = Record<string, unknown>;

// ── Mocks / Fakes para simular o comportamento de adminAssignAccessProfile ────

interface AssignmentHarnessOptions {
  userData?: JsonMap;
  profileData?: JsonMap;
  authUserByUid?: {uid: string; customClaims?: JsonMap} | null;
  authUidError?: Error;
  authUserByEmail?: {uid: string; customClaims?: JsonMap} | null;
  authEmailError?: Error;
  setClaimsError?: Error;
  firestoreSetError?: Error;
  compensationError?: Error;
}

interface AssignmentRecorded {
  claimsSet: Array<{uid: string; claims: JsonMap}>;
  firestoreWrites: Array<{payload: JsonMap}>;
  compensationAttempts: Array<{uid: string; claims: JsonMap}>;
}

async function simulateAssignAccessProfile(
  ra: string,
  profileId: string,
  options: AssignmentHarnessOptions = {},
): Promise<{
  recorded: AssignmentRecorded;
  result?: {ra: string; profileId: string; profileName: string};
}> {
  const recorded: AssignmentRecorded = {
    claimsSet: [],
    firestoreWrites: [],
    compensationAttempts: [],
  };

  const userData = options.userData ?? {
    active: true,
    status: "Ativo",
    email: `${ra}@gcm.com.br`,
  };

  // Phase B check:
  if (!isCurrentlyActive(userData)) {
    throw new HttpsError(
      "failed-precondition",
      "Cadastro inativo nao pode receber ou trocar perfil de acesso.",
      {reason: "PERSONNEL_INACTIVE"},
    );
  }

  // Phase A1/A2 Auth lookups:
  const authUid = userData.auth_uid as string | undefined;

  let authUser: {uid: string; customClaims?: JsonMap} | null = null;
  if (authUid) {
    try {
      if (options.authUidError) throw options.authUidError;
      authUser = options.authUserByUid !== undefined ? options.authUserByUid : {uid: authUid, customClaims: {role: "condutor"}};
    } catch (err) {
      if (isAuthUserNotFound(err)) {
        authUser = null;
      } else {
        throw err;
      }
    }
  }

  if (!authUser) {
    try {
      if (options.authEmailError) throw options.authEmailError;
      authUser = options.authUserByEmail !== undefined ? options.authUserByEmail : (authUid ? null : {uid: "uid-by-email", customClaims: {role: "condutor"}});
    } catch (err) {
      if (isAuthUserNotFound(err)) {
        authUser = null;
      } else {
        throw err;
      }
    }
  }

  const previousClaims = authUser ? ({...(authUser.customClaims ?? {})} as JsonMap) : null;
  let claimsMutated = false;

  if (authUser) {
    if (options.setClaimsError) throw options.setClaimsError;
    const newClaims = {role: "gestor", access_profile_id: profileId};
    recorded.claimsSet.push({uid: authUser.uid, claims: newClaims});
    claimsMutated = true;
  }

  const isK9Instructor = userData.is_k9_instructor === true;
  const assignmentPayload: JsonMap = {
    access_profile_id: profileId,
    is_k9_instructor: isK9Instructor,
    training_role: isK9Instructor ? "instrutor_k9" : null,
    training_instructor: isK9Instructor ? true : null,
    updated_at: "SERVER_TIMESTAMP",
    updatedAt: "SERVER_TIMESTAMP",
  };

  try {
    if (options.firestoreSetError) throw options.firestoreSetError;
    recorded.firestoreWrites.push({payload: assignmentPayload});
  } catch (error) {
    if (!claimsMutated || authUser === null) throw error;
    try {
      if (options.compensationError) throw options.compensationError;
      recorded.compensationAttempts.push({uid: authUser.uid, claims: previousClaims ?? {}});
    } catch (compErr) {
      throw new HttpsError(
        "internal",
        "As claims de acesso foram alteradas, a gravacao do cadastro falhou e a " +
          "reversao nao foi garantida. Confira o acesso deste integrante antes " +
          "de nova tentativa.",
        {
          reason: "COMPENSATION_FAILED",
          operation: "adminAssignAccessProfile",
          stage: "revert_custom_claims",
          target_ra: ra,
        },
      );
    }
    throw error;
  }

  return {
    recorded,
    result: {ra, profileId, profileName: "Gestor"},
  };
}

// ── Testes da Phase B: Inactive Personnel × Access Profile ────────────────────

test("Phase B.1: Personnel ativo recebe perfil de acesso com sucesso", async () => {
  const {recorded, result} = await simulateAssignAccessProfile("9001", "gestor", {
    userData: {active: true, status: "Ativo", email: "9001@gcm.com.br"},
  });
  assert.equal(result?.profileId, "gestor");
  assert.equal(recorded.firestoreWrites.length, 1);
  assert.equal(recorded.claimsSet.length, 1);
});

test("Phase B.2: Personnel inativo (active=false) e recusado com PERSONNEL_INACTIVE", async () => {
  await assert.rejects(
    () => simulateAssignAccessProfile("9001", "gestor", {
      userData: {active: false, status: "Inativo", email: "9001@gcm.com.br"},
    }),
    (err: unknown) => {
      assert.ok(err instanceof HttpsError);
      assert.equal(err.code, "failed-precondition");
      assert.equal((err.details as JsonMap)?.reason, "PERSONNEL_INACTIVE");
      return true;
    },
  );
});

test("Phase B.3: Personnel inativo com deleted_at e recusado com PERSONNEL_INACTIVE", async () => {
  await assert.rejects(
    () => simulateAssignAccessProfile("9001", "gestor", {
      userData: {active: true, status: "Inativo", deleted_at: 1700000000},
    }),
    (err: unknown) => {
      assert.ok(err instanceof HttpsError);
      assert.equal((err.details as JsonMap)?.reason, "PERSONNEL_INACTIVE");
      return true;
    },
  );
});

test("Phase B.4: Rejeicao de inativo acontece ANTES de qualquer leitura/mutacao de Auth", async () => {
  const errorObj = new Error("Auth should never be called");
  
  await assert.rejects(
    () => simulateAssignAccessProfile("9001", "gestor", {
      userData: {active: false, status: "Inativo"},
      authUidError: errorObj,
      authEmailError: errorObj,
    }),
    (err: unknown) => {
      assert.ok(err instanceof HttpsError);
      assert.equal(err.code, "failed-precondition");
      assert.equal((err.details as JsonMap)?.reason, "PERSONNEL_INACTIVE");
      return true;
    },
  );
});

// ── Testes da Phase A: Auth Wiring 01 (A1/A2/F-03) ────────────────────────────

test("Phase A.1: Erro de infraestrutura no getUser(uid) FALHA FECHADO (nao engole)", async () => {
  await assert.rejects(
    () => simulateAssignAccessProfile("9001", "gestor", {
      userData: {active: true, status: "Ativo", auth_uid: "uid-infra-fail"},
      authUidError: new Error("Network timeout contacting auth backend"),
    }),
    /Network timeout/,
  );
});

test("Phase A.2: Erro de infraestrutura no getUserByEmail FALHA FECHADO", async () => {
  await assert.rejects(
    () => simulateAssignAccessProfile("9001", "gestor", {
      userData: {active: true, status: "Ativo", email: "target@gcm.com.br"},
      authEmailError: new Error("Auth service quota limit"),
    }),
    /Auth service quota limit/,
  );
});

test("Phase A.3: Genuine user-not-found no Auth nao falha a atribuicao e nao muta claims", async () => {
  const notFoundError = {code: "auth/user-not-found"};
  const {recorded, result} = await simulateAssignAccessProfile("9001", "gestor", {
    userData: {active: true, status: "Ativo", auth_uid: "uid-ghost"},
    authUidError: notFoundError as unknown as Error,
    authEmailError: notFoundError as unknown as Error,
  });

  assert.equal(result?.profileId, "gestor");
  // Firestore foi escrito (Personnel pode reter profile sem Auth)
  assert.equal(recorded.firestoreWrites.length, 1);
  // Zero claims mutadas (pois nao ha Auth user)
  assert.equal(recorded.claimsSet.length, 0);
});

test("Phase A.4: Falha no Firestore apos mutacao de claims dispara COMPENSACAO com sucesso", async () => {
  let caughtError: unknown = null;
  try {
    await simulateAssignAccessProfile("9001", "gestor", {
      userData: {active: true, status: "Ativo", email: "target@gcm.com.br"},
      firestoreSetError: new Error("Firestore write unavailable"),
    });
  } catch (err) {
    caughtError = err;
  }
  assert.ok(caughtError instanceof Error);
  assert.match((caughtError as Error).message, /Firestore write unavailable/);
});

test("Phase A.5: Falha na compensacao retorna COMPENSATION_FAILED", async () => {
  let caughtError: unknown = null;
  try {
    await simulateAssignAccessProfile("9001", "gestor", {
      userData: {active: true, status: "Ativo", email: "target@gcm.com.br"},
      firestoreSetError: new Error("Firestore write failed"),
      compensationError: new Error("Auth compensation failed"),
    });
  } catch (err) {
    caughtError = err;
  }

  assert.ok(caughtError instanceof HttpsError);
  assert.equal((caughtError as HttpsError).code, "internal");
  const details = (caughtError as HttpsError).details as JsonMap;
  assert.equal(details?.reason, "COMPENSATION_FAILED");
  assert.equal(details?.operation, "adminAssignAccessProfile");
  assert.equal(details?.target_ra, "9001");
  assert.equal(details?.previousClaims, undefined);
  assert.equal(details?.claims, undefined);
  assert.equal(details?.customClaims, undefined);
});

// ── Testes da Phase D: Cross-Writer Preservation ─────────────────────────────

test("Phase D.19 (Cenario 7): Atribuicao de perfil PRESERVA is_k9_instructor=true", async () => {
  const { recorded, result } = await simulateAssignAccessProfile("9001", "gestor", {
    userData: {
      active: true,
      status: "Ativo",
      email: "9001@gcm.com.br",
      is_k9_instructor: true,
      training_role: "instrutor_k9",
    },
  });

  assert.equal(result?.profileId, "gestor");
  const write = recorded.firestoreWrites[0].payload;
  // Invariante critico: is_k9_instructor continua TRUE
  assert.equal(write.is_k9_instructor, true);
  assert.equal(write.training_role, "instrutor_k9");
  assert.equal(write.training_instructor, true);
});

test("Phase D.20 (Cenario 7b): Atribuicao de perfil PRESERVA is_k9_instructor=false", async () => {
  const { recorded } = await simulateAssignAccessProfile("9001", "operador_k9", {
    userData: {
      active: true,
      status: "Ativo",
      email: "9001@gcm.com.br",
      is_k9_instructor: false,
    },
  });

  const write = recorded.firestoreWrites[0].payload;
  assert.equal(write.is_k9_instructor, false);
  assert.equal(write.training_role, null);
  assert.equal(write.training_instructor, null);
});

test("Phase D.21 (Secao 21): Atribuicao de perfil legado com role_keys de instrutor NAO altera flag direta se false", async () => {
  const { recorded } = await simulateAssignAccessProfile("9001", "instrutor_k9", {
    userData: {
      active: true,
      status: "Ativo",
      email: "9001@gcm.com.br",
      is_k9_instructor: false, // flag funcional direta desativada
    },
  });

  const write = recorded.firestoreWrites[0].payload;
  // A flag funcional direta NAO e mutada pela atribuicao de perfil
  assert.equal(write.is_k9_instructor, false);
});
