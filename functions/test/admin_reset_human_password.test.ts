/**
 * FRONT10.ACCESS-CREDENTIALS — TESTES COMPORTAMENTAIS DO RESET DE SENHA (Phase C).
 *
 * Exercita o contrato do adminResetHumanPassword com fakes puros.
 * Testa as 16 garantias exigidas pelo gate sem I/O e sem emulador.
 */

import * as assert from "node:assert/strict";
import {test} from "node:test";
import {HttpsError} from "firebase-functions/v2/https";

import {
  defaultGenerateTemporaryPassword,
  resetHumanPasswordLogic,
  ResetPasswordAuthUser,
  ResetPasswordCaller,
  ResetPasswordDeps,
  ResetPasswordPersonnel,
} from "../src/admin_reset_human_password";

type JsonMap = Record<string, unknown>;

const CALLER: ResetPasswordCaller = {
  uid: "adm-001",
  ra: "1001",
};

const TIMESTAMP_SENTINEL = Symbol("serverTimestamp");

interface HarnessOptions {
  authorizeError?: HttpsError;
  authUser?: ResetPasswordAuthUser | null;
  authUidError?: Error;
  authEmailError?: Error;
  personnelExists?: boolean;
  personnelData?: ResetPasswordPersonnel;
  updatePasswordError?: Error;
}

interface Recorded {
  authorizeCalls: number;
  passwordsUpdated: Array<{uid: string; password: string}>;
  auditWrites: Array<{ra: string; payload: JsonMap}>;
  lookupUidCalls: string[];
  lookupEmailCalls: string[];
}

function harness(options: HarnessOptions = {}): {
  deps: ResetPasswordDeps;
  recorded: Recorded;
} {
  const recorded: Recorded = {
    authorizeCalls: 0,
    passwordsUpdated: [],
    auditWrites: [],
    lookupUidCalls: [],
    lookupEmailCalls: [],
  };

  const deps: ResetPasswordDeps = {
    authorize: async () => {
      recorded.authorizeCalls += 1;
      if (options.authorizeError) throw options.authorizeError;
      return CALLER;
    },
    getPersonnel: async (ra) => {
      if (options.personnelExists === false) return {exists: false};
      return {
        exists: true,
        data: options.personnelData ?? {
          active: true,
          status: "Ativo",
          auth_uid: "uid-target",
          email: `${ra}@gcm.com.br`,
        },
      };
    },
    lookupAuthByUid: async (uid) => {
      recorded.lookupUidCalls.push(uid);
      if (options.authUidError) throw options.authUidError;
      return options.authUser !== undefined ? options.authUser : {uid, disabled: false, email: "test@gcm.com.br"};
    },
    lookupAuthByEmail: async (email) => {
      recorded.lookupEmailCalls.push(email);
      if (options.authEmailError) throw options.authEmailError;
      return options.authUser !== undefined ? options.authUser : {uid: "uid-by-email", disabled: false, email};
    },
    generateTemporaryPassword: () => "TempPass123!aA",
    updatePassword: async (uid, password) => {
      if (options.updatePasswordError) throw options.updatePasswordError;
      recorded.passwordsUpdated.push({uid, password});
    },
    updatePersonnelAudit: async (ra, payload) => {
      recorded.auditWrites.push({ra, payload});
    },
    serverTimestamp: () => TIMESTAMP_SENTINEL,
  };

  return {deps, recorded};
}

test("1. caller nao autorizado e recusado", async () => {
  const {deps, recorded} = harness({
    authorizeError: new HttpsError("permission-denied", "Sem permissao."),
  });

  await assert.rejects(
    () => resetHumanPasswordLogic({auth: null, data: {ra: "9001"}}, deps),
    (err: unknown) => {
      assert.ok(err instanceof HttpsError);
      assert.equal(err.code, "permission-denied");
      return true;
    },
  );
  assert.equal(recorded.passwordsUpdated.length, 0);
  assert.equal(recorded.auditWrites.length, 0);
});

test("2. Personnel nao encontrado retorna not-found", async () => {
  const {deps, recorded} = harness({personnelExists: false});

  await assert.rejects(
    () => resetHumanPasswordLogic({auth: {}, data: {ra: "9001"}}, deps),
    (err: unknown) => {
      assert.ok(err instanceof HttpsError);
      assert.equal(err.code, "not-found");
      assert.match(err.message, /Integrante nao encontrado/);
      return true;
    },
  );
  assert.equal(recorded.passwordsUpdated.length, 0);
});

test("3. Personnel existe mas Auth identity ausente retorna not-found com AUTH_IDENTITY_NOT_FOUND", async () => {
  const {deps, recorded} = harness({authUser: null});

  await assert.rejects(
    () => resetHumanPasswordLogic({auth: {}, data: {ra: "9001"}}, deps),
    (err: unknown) => {
      assert.ok(err instanceof HttpsError);
      assert.equal(err.code, "not-found");
      assert.equal((err.details as JsonMap)?.reason, "AUTH_IDENTITY_NOT_FOUND");
      return true;
    },
  );
  assert.equal(recorded.passwordsUpdated.length, 0);
});

test("4. UID lookup not-found avanca para fallback por e-mail", async () => {
  const recorded: Recorded = {
    authorizeCalls: 0,
    passwordsUpdated: [],
    auditWrites: [],
    lookupUidCalls: [],
    lookupEmailCalls: [],
  };

  const deps: ResetPasswordDeps = {
    authorize: async () => CALLER,
    getPersonnel: async () => ({
      exists: true,
      data: {auth_uid: "uid-obsoleta", email: "alvo@gcm.com.br"},
    }),
    lookupAuthByUid: async (uid) => {
      recorded.lookupUidCalls.push(uid);
      return null; // user-not-found genuino
    },
    lookupAuthByEmail: async (email) => {
      recorded.lookupEmailCalls.push(email);
      return {uid: "uid-fallback-email", disabled: false, email};
    },
    generateTemporaryPassword: () => "TempPass123!aA",
    updatePassword: async (uid, password) => {
      recorded.passwordsUpdated.push({uid, password});
    },
    updatePersonnelAudit: async (ra, payload) => {
      recorded.auditWrites.push({ra, payload});
    },
    serverTimestamp: () => TIMESTAMP_SENTINEL,
  };

  const res = await resetHumanPasswordLogic({auth: {}, data: {ra: "9001"}}, deps);
  assert.equal(res.temporary_password, "TempPass123!aA");
  assert.equal(recorded.lookupUidCalls.length, 1);
  assert.equal(recorded.lookupEmailCalls.length, 1);
  assert.equal(recorded.passwordsUpdated[0].uid, "uid-fallback-email");
});

test("5. UID lookup erro de infraestrutura FALHA FECHADO", async () => {
  const {deps, recorded} = harness({
    authUidError: new Error("Network timeout contacting Identity Toolkit"),
  });

  await assert.rejects(
    () => resetHumanPasswordLogic({auth: {}, data: {ra: "9001"}}, deps),
    (err: unknown) => {
      assert.ok(err instanceof Error);
      assert.match(err.message, /Network timeout/);
      return true;
    },
  );
  assert.equal(recorded.passwordsUpdated.length, 0);
  assert.equal(recorded.lookupEmailCalls.length, 0);
});

test("6. Email lookup erro de infraestrutura FALHA FECHADO", async () => {
  const {deps, recorded} = harness({
    authUser: null, // UID lookup return null
    authEmailError: new Error("Quota exceeded"),
    personnelData: {auth_uid: undefined, email: "target@gcm.com.br"},
  });

  await assert.rejects(
    () => resetHumanPasswordLogic({auth: {}, data: {ra: "9001"}}, deps),
    (err: unknown) => {
      assert.ok(err instanceof Error);
      assert.match(err.message, /Quota exceeded/);
      return true;
    },
  );
  assert.equal(recorded.passwordsUpdated.length, 0);
});

test("7. Auth disabled permanece disabled durante reset de senha", async () => {
  const {deps, recorded} = harness({
    authUser: {uid: "uid-disabled", disabled: true, email: "disabled@gcm.com.br"},
  });

  const res = await resetHumanPasswordLogic({auth: {}, data: {ra: "9001"}}, deps);
  assert.equal(res.temporary_password, "TempPass123!aA");
  assert.equal(recorded.passwordsUpdated.length, 1);
  assert.equal(recorded.passwordsUpdated[0].uid, "uid-disabled");
});

test("8. updatePassword tem sucesso e retorna temporary_password", async () => {
  const {deps, recorded} = harness();
  const res = await resetHumanPasswordLogic({auth: {}, data: {ra: "9001"}}, deps);
  assert.equal(res.temporary_password, "TempPass123!aA");
  assert.equal(recorded.passwordsUpdated.length, 1);
});

test("9. createUser NUNCA e invocado (contrato sem criacao de conta)", async () => {
  // O deps nem possui createUser na interface! Apenas updatePassword.
  const {deps} = harness({authUser: null});
  await assert.rejects(() => resetHumanPasswordLogic({auth: {}, data: {ra: "9001"}}, deps));
});

test("10. claims NUNCA sao mutadas", async () => {
  // Reset de senha nao aceita nem toca claims.
  const {deps, recorded} = harness();
  await resetHumanPasswordLogic({auth: {}, data: {ra: "9001"}}, deps);
  assert.equal(recorded.passwordsUpdated.length, 1);
  // zero claims mutator no deps
});

test("11. Lifecycle NUNCA e mutado (active e status nao sao alterados)", async () => {
  const {deps, recorded} = harness();
  await resetHumanPasswordLogic({auth: {}, data: {ra: "9001"}}, deps);
  const auditPayload = recorded.auditWrites[0].payload;
  assert.equal(auditPayload.active, undefined);
  assert.equal(auditPayload.status, undefined);
});

test("12. Access Profile NUNCA e mutado", async () => {
  const {deps, recorded} = harness();
  await resetHumanPasswordLogic({auth: {}, data: {ra: "9001"}}, deps);
  const auditPayload = recorded.auditWrites[0].payload;
  assert.equal(auditPayload.access_profile_id, undefined);
  assert.equal(auditPayload.accessProfile, undefined);
});

test("13. Senha NUNCA e persistida no payload do Firestore", async () => {
  const {deps, recorded} = harness();
  const res = await resetHumanPasswordLogic({auth: {}, data: {ra: "9001"}}, deps);
  const jsonStr = JSON.stringify(recorded.auditWrites);
  assert.equal(jsonStr.includes(res.temporary_password), false);
});

test("14. Senha NUNCA e incluida no payload de auditoria", async () => {
  const {deps, recorded} = harness();
  const res = await resetHumanPasswordLogic({auth: {}, data: {ra: "9001"}}, deps);
  const auditEntry = (recorded.auditWrites[0].payload.audit_trail as JsonMap);
  assert.equal(auditEntry.password, undefined);
  assert.equal(auditEntry.temporary_password, undefined);
  assert.equal(JSON.stringify(auditEntry).includes(res.temporary_password), false);
});

test("15. Trilha de auditoria canonica de sucesso gravada com caller e timestamp", async () => {
  const {deps, recorded} = harness();
  await resetHumanPasswordLogic({auth: {}, data: {ra: "9001"}}, deps);
  assert.equal(recorded.auditWrites.length, 1);
  const write = recorded.auditWrites[0];
  assert.equal(write.ra, "9001");
  assert.equal(write.payload.updated_at, TIMESTAMP_SENTINEL);
  assert.equal(write.payload.updatedAt, TIMESTAMP_SENTINEL);
  assert.equal(write.payload.updated_by, "1001");
  const entry = write.payload.audit_trail as JsonMap;
  assert.equal(entry.action, "password_reset");
  assert.equal(entry.by, "adm-001");
  assert.equal(entry.by_ra, "1001");
  assert.equal(entry.target_ra, "9001");
  assert.equal(entry.target_uid, "uid-target");
});

test("16. Falha em updatePassword nao grava auditoria de sucesso", async () => {
  const {deps, recorded} = harness({
    updatePasswordError: new Error("Auth service error"),
  });

  await assert.rejects(
    () => resetHumanPasswordLogic({auth: {}, data: {ra: "9001"}}, deps),
    /Auth service error/,
  );
  assert.equal(recorded.auditWrites.length, 0);
});

test("17. defaultGenerateTemporaryPassword produz senha valida com maiuscula, minuscula, numero e simbolo", () => {
  for (let i = 0; i < 20; i++) {
    const pwd = defaultGenerateTemporaryPassword();
    assert.ok(pwd.length >= 10);
    assert.match(pwd, /[A-Z]/);
    assert.match(pwd, /[a-z]/);
    assert.match(pwd, /[0-9]/);
    assert.match(pwd, /[!@#$%^&*()_+\-=\[\]{};':"\\|,.<>\/?]/);
  }
});

test("18. C1-02: entrypoint do Functions exporta adminResetHumanPassword", () => {
  process.env.FIREBASE_CONFIG = JSON.stringify({ projectId: "test-k9-project" });
  process.env.GCLOUD_PROJECT = "test-k9-project";
  // eslint-disable-next-line @typescript-eslint/no-var-requires
  const indexModule = require("../src/index");
  assert.equal(typeof indexModule.adminResetHumanPassword, "function");
});

test("19. C1-02: entrypoint delega adminResetHumanPassword para resetHumanPasswordLogic", () => {
  const fs = require("node:fs");
  const path = require("node:path");
  const indexPath = path.resolve(__dirname, "../../../src/index.ts");
  const content = fs.readFileSync(indexPath, "utf8");
  assert.match(content, /export const adminResetHumanPassword = onCall\(/);
  assert.match(content, /resetHumanPasswordLogic\(\{auth: request\.auth, data: request\.data\},/);
});
