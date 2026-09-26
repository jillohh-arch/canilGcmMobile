/**
 * F10.AUTH-PROVISIONING-CREDENTIALS-R1 — TESTES UNITARIOS E DE CONTRATO DO PROVISIONAMENTO DE AUTH.
 *
 * Exercita o contrato do adminProvisionHumanAuth com fakes puros.
 * Testa criacao segura (disabled -> firestore -> enabled), idempotencia sem revelacao de senha,
 * deteccao de conflitos de identidade, rejeicao de inativos, autorizacao e ausencia de vazamento de credencial.
 */

import * as assert from "node:assert/strict";
import * as fs from "node:fs";
import * as path from "node:path";
import {test} from "node:test";
import {HttpsError} from "firebase-functions/v2/https";

import {
  defaultGenerateInitialPassword,
  provisionHumanAuthLogic,
  CreateAuthUserInput,
  ProvisionAuthCaller,
  ProvisionAuthPersonnel,
  ProvisionAuthUser,
  ProvisionHumanAuthDeps,
} from "../src/admin_provision_human_auth";

type JsonMap = Record<string, unknown>;

const CALLER: ProvisionAuthCaller = {
  uid: "adm-001",
  ra: "1001",
};

interface HarnessOptions {
  authEmailError?: Error;
  authUidError?: Error;
  authorizeError?: HttpsError;
  createAuthUserError?: Error;
  deleteAuthUserError?: Error;
  existingAuthUser?: ProvisionAuthUser | null;
  existingAuthUserByEmail?: ProvisionAuthUser | null;
  owningRaForUid?: string | null;
  personnelData?: ProvisionAuthPersonnel;
  personnelExists?: boolean;
  updateAuthUserError?: Error;
  updatePersonnelAuditError?: Error;
}

interface Recorded {
  authUsersCreated: CreateAuthUserInput[];
  authUsersDeleted: string[];
  authUsersUpdated: Array<{uid: string; patch: {disabled?: boolean}}>;
  auditWrites: Array<{ra: string; payload: JsonMap}>;
  authorizeCalls: number;
  lookupEmailCalls: string[];
  lookupPersonnelUidCalls: string[];
  lookupUidCalls: string[];
}

function harness(options: HarnessOptions = {}): {
  deps: ProvisionHumanAuthDeps;
  recorded: Recorded;
} {
  const recorded: Recorded = {
    authUsersCreated: [],
    authUsersDeleted: [],
    authUsersUpdated: [],
    auditWrites: [],
    authorizeCalls: 0,
    lookupEmailCalls: [],
    lookupPersonnelUidCalls: [],
    lookupUidCalls: [],
  };

  const deps: ProvisionHumanAuthDeps = {
    authorize: async () => {
      recorded.authorizeCalls += 1;
      if (options.authorizeError) throw options.authorizeError;
      return CALLER;
    },
    createAuthUser: async (input) => {
      if (options.createAuthUserError) throw options.createAuthUserError;
      recorded.authUsersCreated.push(input);
      return {
        disabled: input.disabled,
        displayName: input.displayName,
        email: input.email,
        uid: "uid-new-123",
      };
    },
    deleteAuthUser: async (uid) => {
      recorded.authUsersDeleted.push(uid);
      if (options.deleteAuthUserError) throw options.deleteAuthUserError;
    },
    generateInitialPassword: () => "StrongPass123!Aa",
    getPersonnel: async (ra) => {
      if (options.personnelExists === false) return {exists: false};
      return {
        exists: true,
        data: options.personnelData ?? {
          active: true,
          status: "Ativo",
          callsign: "Silva",
          name: "Silva Santos",
          email: `${ra}@gcm.com.br`,
        },
      };
    },
    lookupAuthByEmail: async (email) => {
      recorded.lookupEmailCalls.push(email);
      if (options.authEmailError) throw options.authEmailError;
      return options.existingAuthUserByEmail !== undefined
        ? options.existingAuthUserByEmail
        : null;
    },
    lookupAuthByUid: async (uid) => {
      recorded.lookupUidCalls.push(uid);
      if (options.authUidError) throw options.authUidError;
      return options.existingAuthUser !== undefined
        ? options.existingAuthUser
        : null;
    },
    lookupPersonnelByAuthUid: async (uid) => {
      recorded.lookupPersonnelUidCalls.push(uid);
      return options.owningRaForUid !== undefined
        ? options.owningRaForUid
        : null;
    },
    serverTimestamp: () => ({_seconds: 1700000000, _nanoseconds: 0}),
    updateAuthUser: async (uid, patch) => {
      if (options.updateAuthUserError) throw options.updateAuthUserError;
      recorded.authUsersUpdated.push({uid, patch});
    },
    updatePersonnelAudit: async (ra, payload) => {
      if (options.updatePersonnelAuditError) throw options.updatePersonnelAuditError;
      recorded.auditWrites.push({ra, payload});
    },
  };

  return {deps, recorded};
}

// ── Testes de Contrato e Seguranca ──────────────────────────────────

test("1. caller nao autenticado ou sem permissao e recusado", async () => {
  const {deps} = harness({
    authorizeError: new HttpsError("permission-denied", "Acesso negado."),
  });
  await assert.rejects(
    () => provisionHumanAuthLogic({auth: null, data: {ra: "9001"}}, deps),
    (err: unknown) => {
      assert.ok(err instanceof HttpsError);
      assert.equal(err.code, "permission-denied");
      return true;
    },
  );
});

test("2. payload malformado ou RA invalido e recusado", async () => {
  const {deps} = harness();
  await assert.rejects(
    () => provisionHumanAuthLogic({auth: {}, data: null}, deps),
    (err: unknown) => err instanceof HttpsError && err.code === "invalid-argument",
  );
  await assert.rejects(
    () => provisionHumanAuthLogic({auth: {}, data: {ra: ""}}, deps),
    (err: unknown) => err instanceof HttpsError && err.code === "invalid-argument",
  );
  await assert.rejects(
    () => provisionHumanAuthLogic({auth: {}, data: {ra: "abc"}}, deps),
    (err: unknown) => err instanceof HttpsError && err.code === "invalid-argument",
  );
  await assert.rejects(
    () => provisionHumanAuthLogic({auth: {}, data: {ra: "12"}}, deps),
    (err: unknown) => err instanceof HttpsError && err.code === "invalid-argument",
  );
});

test("3. integrante inexistente no Firestore retorna not-found", async () => {
  const {deps} = harness({personnelExists: false});
  await assert.rejects(
    () => provisionHumanAuthLogic({auth: {}, data: {ra: "9001"}}, deps),
    (err: unknown) => {
      assert.ok(err instanceof HttpsError);
      assert.equal(err.code, "not-found");
      assert.equal((err.details as JsonMap)?.reason, "PERSONNEL_NOT_FOUND");
      return true;
    },
  );
});

test("4. integrante inativo ou arquivado e recusado fail-closed via isCurrentlyActive", async () => {
  // Teste com active: false
  const h1 = harness({personnelData: {active: false, status: "Inativo"}});
  await assert.rejects(
    () => provisionHumanAuthLogic({auth: {}, data: {ra: "9001"}}, h1.deps),
    (err: unknown) => err instanceof HttpsError && err.code === "failed-precondition",
  );

  // Teste com deleted_at
  const h2 = harness({personnelData: {active: true, deleted_at: "2026-01-01"}});
  await assert.rejects(
    () => provisionHumanAuthLogic({auth: {}, data: {ra: "9001"}}, h2.deps),
    (err: unknown) => err instanceof HttpsError && err.code === "failed-precondition",
  );

  // Teste com archived_at
  const h3 = harness({personnelData: {active: true, archived_at: "2026-01-01"}});
  await assert.rejects(
    () => provisionHumanAuthLogic({auth: {}, data: {ra: "9001"}}, h3.deps),
    (err: unknown) => err instanceof HttpsError && err.code === "failed-precondition",
  );
});

test("5. criacao efetiva segue ciclo seguro (disabled: true -> grava Firestore -> disabled: false)", async () => {
  const {deps, recorded} = harness();
  const res = await provisionHumanAuthLogic({auth: {}, data: {ra: "9001"}}, deps);

  assert.equal(res.created, true);
  assert.equal(res.auth_uid, "uid-new-123");
  assert.equal(res.email, "9001@gcm.com.br");
  assert.equal(res.initial_password, "StrongPass123!Aa");
  assert.equal(res.ra, "9001");

  // 1. Criado inicialmente com disabled: true
  assert.equal(recorded.authUsersCreated.length, 1);
  assert.equal(recorded.authUsersCreated[0].disabled, true);
  assert.equal(recorded.authUsersCreated[0].email, "9001@gcm.com.br");

  // 2. Gravado no Firestore com auth_uid e auditoria
  assert.equal(recorded.auditWrites.length, 1);
  assert.equal(recorded.auditWrites[0].ra, "9001");
  assert.equal(recorded.auditWrites[0].payload.auth_uid, "uid-new-123");
  assert.equal(recorded.auditWrites[0].payload.auth_provisioned_by, "1001");

  // 3. Habilitado APOS a gravacao no Firestore
  assert.equal(recorded.authUsersUpdated.length, 1);
  assert.equal(recorded.authUsersUpdated[0].uid, "uid-new-123");
  assert.deepEqual(recorded.authUsersUpdated[0].patch, {disabled: false});
});

test("6. senha inicial NUNCA e gravada no Firestore nem na trilha de auditoria", async () => {
  const {deps, recorded} = harness();
  const res = await provisionHumanAuthLogic({auth: {}, data: {ra: "9001"}}, deps);

  const writePayload = JSON.stringify(recorded.auditWrites);
  assert.ok(!writePayload.includes(res.initial_password!));
  assert.ok(!writePayload.includes("StrongPass123!Aa"));
  assert.ok(!writePayload.includes("password"));
});

test("7. chamada idempotente com conta ja vinculada NAO recria e NUNCA retorna senha", async () => {
  const {deps, recorded} = harness({
    personnelData: {
      active: true,
      auth_uid: "uid-existing-456",
      status: "Ativo",
    },
    existingAuthUser: {
      disabled: false,
      email: "9001@gcm.com.br",
      uid: "uid-existing-456",
    },
  });

  const res = await provisionHumanAuthLogic({auth: {}, data: {ra: "9001"}}, deps);

  assert.equal(res.created, false);
  assert.equal(res.auth_uid, "uid-existing-456");
  assert.equal(res.email, "9001@gcm.com.br");
  assert.equal(res.initial_password, undefined);

  // Nao criou usuario novo
  assert.equal(recorded.authUsersCreated.length, 0);
});

test("8. idempotencia com conta previa desabilitada reativa no Auth sem revelar senha", async () => {
  const {deps, recorded} = harness({
    personnelData: {
      active: true,
      auth_uid: "uid-disabled-789",
      status: "Ativo",
    },
    existingAuthUser: {
      disabled: true,
      email: "9001@gcm.com.br",
      uid: "uid-disabled-789",
    },
  });

  const res = await provisionHumanAuthLogic({auth: {}, data: {ra: "9001"}}, deps);

  assert.equal(res.created, false);
  assert.equal(res.auth_uid, "uid-disabled-789");
  assert.equal(res.initial_password, undefined);

  // Garantiu que reabilitou
  assert.equal(recorded.authUsersUpdated.length, 1);
  assert.equal(recorded.authUsersUpdated[0].uid, "uid-disabled-789");
  assert.deepEqual(recorded.authUsersUpdated[0].patch, {disabled: false});
});

test("9. conflito de identidade: UID aponta para conta com e-mail de outro RA -> fail-closed", async () => {
  const {deps} = harness({
    personnelData: {
      active: true,
      auth_uid: "uid-wrong-email",
      status: "Ativo",
    },
    existingAuthUser: {
      disabled: false,
      email: "outro_integrante@gcm.com.br",
      uid: "uid-wrong-email",
    },
  });

  await assert.rejects(
    () => provisionHumanAuthLogic({auth: {}, data: {ra: "9001"}}, deps),
    (err: unknown) => {
      assert.ok(err instanceof HttpsError);
      assert.equal(err.code, "already-exists");
      assert.equal((err.details as JsonMap)?.reason, "IDENTITY_CONFLICT");
      return true;
    },
  );
});

test("10. conflito de identidade: UID no doc difere de conta encontrada por e-mail -> fail-closed", async () => {
  const {deps} = harness({
    personnelData: {
      active: true,
      auth_uid: "uid-doc-a",
      status: "Ativo",
    },
    existingAuthUser: null, // lookup by uid-doc-a fails
    existingAuthUserByEmail: {
      disabled: false,
      email: "9001@gcm.com.br",
      uid: "uid-auth-b", // different UID
    },
  });

  await assert.rejects(
    () => provisionHumanAuthLogic({auth: {}, data: {ra: "9001"}}, deps),
    (err: unknown) => {
      assert.ok(err instanceof HttpsError);
      assert.equal(err.code, "already-exists");
      assert.equal((err.details as JsonMap)?.reason, "IDENTITY_CONFLICT");
      return true;
    },
  );
});

test("11. conflito de identidade: doc sem auth_uid, e-mail existe no Auth e pertence a OUTRO RA -> fail-closed", async () => {
  const {deps} = harness({
    personnelData: {
      active: true,
      status: "Ativo",
    },
    existingAuthUser: null,
    existingAuthUserByEmail: {
      disabled: false,
      email: "9001@gcm.com.br",
      uid: "uid-foreign",
    },
    owningRaForUid: "9999", // owned by RA 9999
  });

  await assert.rejects(
    () => provisionHumanAuthLogic({auth: {}, data: {ra: "9001"}}, deps),
    (err: unknown) => {
      assert.ok(err instanceof HttpsError);
      assert.equal(err.code, "already-exists");
      assert.equal((err.details as JsonMap)?.reason, "IDENTITY_CONFLICT");
      return true;
    },
  );
});

test("12. falha de persistencia no Firestore aciona deleteAuthUser compensatorio e conta nunca fica ativa", async () => {
  const {deps, recorded} = harness({
    updatePersonnelAuditError: new Error("Firestore down"),
  });

  await assert.rejects(
    () => provisionHumanAuthLogic({auth: {}, data: {ra: "9001"}}, deps),
    (err: unknown) => {
      assert.ok(err instanceof HttpsError);
      assert.equal(err.code, "internal");
      assert.equal((err.details as JsonMap)?.reason, "AUTH_PROVISION_PERSISTENCE_FAILED");
      return true;
    },
  );

  // Compensacao tentou deletar a conta
  assert.equal(recorded.authUsersDeleted.length, 1);
  assert.equal(recorded.authUsersDeleted[0], "uid-new-123");

  // NUNCA chamou updateAuthUser({disabled: false})
  assert.equal(recorded.authUsersUpdated.length, 0);
});

test("13. falha ao ativar Auth apos commit Firestore reporta erro e nao reporta sucesso", async () => {
  const {deps} = harness({
    updateAuthUserError: new Error("Auth update service unavailable"),
  });

  await assert.rejects(
    () => provisionHumanAuthLogic({auth: {}, data: {ra: "9001"}}, deps),
    (err: unknown) => {
      assert.ok(err instanceof HttpsError);
      assert.equal(err.code, "internal");
      assert.equal((err.details as JsonMap)?.reason, "AUTH_ACTIVATION_FAILED");
      return true;
    },
  );
});

test("14. defaultGenerateInitialPassword produz senha com comprimento >= 16 e satisfaz requisitos de complexidade", () => {
  const pwd = defaultGenerateInitialPassword();
  assert.ok(pwd.length >= 16, `Senha muito curta: ${pwd.length}`);
  assert.match(pwd, /[A-Z]/, "Falta maiuscula");
  assert.match(pwd, /[a-z]/, "Falta minuscula");
  assert.match(pwd, /[0-9]/, "Falta numero");
  assert.match(pwd, /[^A-Za-z0-9]/, "Falta simbolo");
});

test("15. entrypoint do Functions exporta adminProvisionHumanAuth e delega para provisionHumanAuthLogic", () => {
  const indexPath = path.resolve(__dirname, "../../../src/index.ts");
  const content = fs.readFileSync(indexPath, "utf8");
  assert.match(content, /export const adminProvisionHumanAuth = onCall\(/);
  assert.match(content, /provisionHumanAuthLogic\(/);
});

test("16. wiring de producao de adminProvisionHumanAuth usa Timestamp concreto e nao sentinel", () => {
  const indexPath = path.resolve(__dirname, "../../../src/index.ts");
  const content = fs.readFileSync(indexPath, "utf8");
  const fnMatch = content.match(/function buildAdminProvisionHumanAuthDeps\(\): ProvisionHumanAuthDeps \{([\s\S]*?)\n\}/);
  assert.ok(fnMatch, "buildAdminProvisionHumanAuthDeps nao encontrada");
  const fnBody = fnMatch[1];
  assert.match(fnBody, /admin\.firestore\.Timestamp\.now\(\)/);
  assert.doesNotMatch(fnBody, /FieldValue\.serverTimestamp\(\)/);
});
