/**
 * FRONT10.ACCESS-CREDENTIALS.D — TESTES DE INTEGRACAO DE SETK9INSTRUCTORROLE E CROSS-WRITER INVARIANTS.
 *
 * Cobre os cenarios da Secao 20 e 21:
 * - Instructor -> Profile preservation (5 e 6)
 * - Sem colisao de writers (7, 8, 9)
 * - Seguranca de Auth (10, 11, 12)
 * - Compensacao transacional de claims (13, 14)
 * - Convergencia de mirrors e timestamps (15, 16)
 * - Nao-conflacao de role_keys com flag direta is_k9_instructor (Secao 21)
 */

import * as assert from "node:assert/strict";
import { test } from "node:test";
import { HttpsError } from "firebase-functions/v2/https";
import { isAuthUserNotFound } from "../src/auth_error_classification";
import {
  composeEffectiveAccessClaims,
  JsonMap,
} from "../src/access_claims_composition";

interface InstructorHarnessOptions {
  userData?: JsonMap;
  profileData?: JsonMap;
  profileExists?: boolean;
  authUser?: { uid: string; customClaims?: JsonMap } | null;
  authError?: Error;
  setClaimsError?: Error;
  firestoreSetError?: Error;
  compensationError?: Error;
}

interface InstructorRecorded {
  claimsSet: Array<{ uid: string; claims: JsonMap }>;
  firestoreWrites: Array<{ payload: JsonMap }>;
  compensationAttempts: Array<{ uid: string; claims: JsonMap }>;
}

async function simulateSetK9InstructorRole(
  ra: string,
  enabled: boolean,
  options: InstructorHarnessOptions = {},
): Promise<{
  recorded: InstructorRecorded;
  result?: { ra: string; uid: string; enabled: boolean };
}> {
  const recorded: InstructorRecorded = {
    claimsSet: [],
    firestoreWrites: [],
    compensationAttempts: [],
  };

  const userData = options.userData ?? {
    active: true,
    status: "Ativo",
    email: `${ra}@gcm.com.br`,
    access_profile_id: "gestor",
    role: "gestor",
    claim_role: "gestor",
  };

  const authUid = userData.auth_uid as string | undefined;
  const email = (userData.email as string | undefined) ?? `${ra}@gcm.com.br`;

  let authUser: { uid: string; customClaims?: JsonMap } | null = null;
  try {
    if (options.authError) throw options.authError;
    authUser =
      options.authUser !== undefined
        ? options.authUser
        : {
            uid: authUid ?? "mock-uid-9001",
            customClaims: {
              ra,
              role: "gestor",
              roles: ["gestor"],
              access_profile_id: "gestor",
            },
          };
  } catch (err) {
    if (isAuthUserNotFound(err)) {
      authUser = null;
    } else {
      throw err;
    }
  }

  if (!authUser) {
    throw new HttpsError(
      "not-found",
      "Conta de autenticacao nao encontrada para este integrante.",
      { reason: "AUTH_IDENTITY_NOT_FOUND" },
    );
  }

  const currentProfileId = (userData.access_profile_id as string) ?? null;
  const currentScope = (userData.access_scope as "global" | "own_records") ?? null;
  let profileRoleKeys: string[] = [];
  let validProfileId: string | null = null;
  let validScope: "global" | "own_records" | null = null;

  if (currentProfileId) {
    const profileData = options.profileData;
    const exists =
      (options as JsonMap).profileExists !== false &&
      (profileData !== undefined ||
        currentProfileId === "gestor" ||
        currentProfileId === "administrador" ||
        currentProfileId === "operador_k9" ||
        currentProfileId === "almoxarifado");
    if (exists) {
      const pData = profileData ?? { status: "active", scope: currentScope ?? "global" };
      const status = (pData.status as string) ?? "active";
      const scope = (pData.scope as "global" | "own_records") ?? currentScope ?? "global";
      if (status === "active" && (scope === "global" || scope === "own_records")) {
        validProfileId = currentProfileId;
        validScope = scope;
        profileRoleKeys = pData.role_keys
          ? (pData.role_keys as string[])
          : [currentProfileId];
      }
    }
  }

  const previousClaims: JsonMap = { ...(authUser.customClaims ?? {}) };
  const nextClaims = composeEffectiveAccessClaims(
    previousClaims,
    ra,
    {
      profileId: validProfileId,
      roleKeys: profileRoleKeys,
      accessScope: validScope,
    },
    enabled,
  );

  if (options.setClaimsError) throw options.setClaimsError;
  recorded.claimsSet.push({ uid: authUser.uid, claims: nextClaims });

  const effectiveRoles = Array.from(
    new Set([...profileRoleKeys, ...(enabled ? ["instrutor_k9"] : [])]),
  ).sort();

  const baseClaimRole =
    (userData.claim_role as string) ?? (userData.role as string);
  const effectiveClaimRole = validProfileId
    ? ((baseClaimRole && baseClaimRole !== "instrutor_k9")
        ? baseClaimRole
        : (nextClaims.role as string | null))
    : null;

  const instructorFirestorePayload: JsonMap = {
    auth_uid: authUser.uid,
    email,
    is_k9_instructor: enabled,
    training_role: enabled ? "instrutor_k9" : null,
    training_instructor: enabled ? true : null,
    claim_role: effectiveClaimRole,
    role: effectiveClaimRole,
    roles: effectiveRoles,
    claim_refresh_required: true,
    claim_updated_at: "SERVER_TIMESTAMP",
    updated_at: "SERVER_TIMESTAMP",
    updatedAt: "SERVER_TIMESTAMP",
  };

  try {
    if (options.firestoreSetError) throw options.firestoreSetError;
    recorded.firestoreWrites.push({ payload: instructorFirestorePayload });
  } catch (firestoreError) {
    try {
      if (options.compensationError) throw options.compensationError;
      recorded.compensationAttempts.push({
        uid: authUser.uid,
        claims: previousClaims,
      });
    } catch (compensationError) {
      throw new HttpsError("internal", "Compensation failed", {
        reason: "COMPENSATION_FAILED",
        operation: "setK9InstructorRole",
        stage: "revert_custom_claims",
        target_ra: ra,
      });
    }
    throw firestoreError;
  }

  return {
    recorded,
    result: { ra, uid: authUser.uid, enabled },
  };
}

// ── Testes de Integracao ──────────────────────────────────────────────────────

test("Phase D.11 (Cenario 5): Perfil gestor + ligar Instrutor mantem perfil e escopo intactos", async () => {
  const { recorded, result } = await simulateSetK9InstructorRole("9001", true, {
    userData: {
      access_profile_id: "gestor",
      access_scope: "global",
      role: "gestor",
      claim_role: "gestor",
    },
  });

  assert.equal(result?.enabled, true);
  const write = recorded.firestoreWrites[0].payload;
  assert.equal(write.is_k9_instructor, true);
  assert.equal(write.training_role, "instrutor_k9");
  assert.equal(write.training_instructor, true);
  // Base role e claim_role preservados como gestor, NUNCA sobrepostos por instrutor_k9
  assert.equal(write.role, "gestor");
  assert.equal(write.claim_role, "gestor");
  assert.deepEqual(write.roles, ["gestor", "instrutor_k9"]);

  // Claims
  const claims = recorded.claimsSet[0].claims;
  assert.equal(claims.role, "gestor");
  assert.equal(claims.instrutor_k9, true);
  assert.equal(claims.training_role, "instrutor_k9");
  assert.equal(claims.access_profile_id, "gestor");
});

test("Phase D.12 (Cenario 6): Desligar Instrutor remove claims de instrutor e mantem perfil base", async () => {
  const { recorded, result } = await simulateSetK9InstructorRole("9001", false, {
    userData: {
      access_profile_id: "gestor",
      is_k9_instructor: true,
      training_role: "instrutor_k9",
      role: "gestor",
      claim_role: "gestor",
    },
    authUser: {
      uid: "uid-gestor",
      customClaims: {
        ra: "9001",
        access_profile_id: "gestor",
        role: "gestor",
        roles: ["condutor", "gestor", "instrutor_k9"],
        instrutor_k9: true,
        training_role: "instrutor_k9",
        training_instructor: true,
      },
    },
  });

  assert.equal(result?.enabled, false);
  const write = recorded.firestoreWrites[0].payload;
  assert.equal(write.is_k9_instructor, false);
  assert.equal(write.training_role, null);
  assert.equal(write.training_instructor, null);
  assert.equal(write.role, "gestor");
  assert.equal(write.claim_role, "gestor");
  assert.deepEqual(write.roles, ["gestor"]);

  // Claims
  const claims = recorded.claimsSet[0].claims;
  assert.equal(claims.role, "gestor");
  assert.equal(claims.instrutor_k9, undefined);
  assert.equal(claims.training_role, undefined);
  assert.equal(claims.training_instructor, undefined);
  assert.deepEqual(claims.roles, ["gestor"]);
});

test("Phase D.13 (Cenarios 8 e 9): setK9InstructorRole NUNCA sobrescreve access_profile_id nem escopo", async () => {
  const { recorded } = await simulateSetK9InstructorRole("9001", true, {
    userData: {
      access_profile_id: "administrador",
      access_scope: "own_records",
      role: "admin",
      claim_role: "admin",
    },
  });

  const write = recorded.firestoreWrites[0].payload;
  // A escrita nao deve conter chaves de perfil de acesso
  assert.equal(write.access_profile_id, undefined);
  assert.equal(write.access_scope, undefined);
  assert.equal(write.role, "admin");
});

test("Phase D.14 (Cenario 10): Auth identity ausente retorna AUTH_IDENTITY_NOT_FOUND", async () => {
  await assert.rejects(
    () =>
      simulateSetK9InstructorRole("9001", true, {
        authError: { code: "auth/user-not-found" } as unknown as Error,
      }),
    (err: unknown) => {
      assert.ok(err instanceof HttpsError);
      assert.equal(err.code, "not-found");
      assert.equal(
        ((err as HttpsError).details as JsonMap)?.reason,
        "AUTH_IDENTITY_NOT_FOUND",
      );
      return true;
    },
  );
});

test("Phase D.15 (Cenarios 11 e 12): Falha de infraestrutura do Auth FALHA FECHADO", async () => {
  await assert.rejects(
    () =>
      simulateSetK9InstructorRole("9001", true, {
        authError: new Error("Network timeout to IAM"),
      }),
    /Network timeout to IAM/,
  );
});

test("Phase D.16 (Cenario 13): Falha no Firestore apos mutacao de claims dispara COMPENSACAO", async () => {
  let caughtError: unknown = null;
  const initialClaims: JsonMap = {
    role: "gestor",
    roles: ["gestor"],
  };

  try {
    await simulateSetK9InstructorRole("9001", true, {
      authUser: { uid: "uid-test", customClaims: initialClaims },
      firestoreSetError: new Error("Firestore quota exceeded"),
    });
  } catch (err) {
    caughtError = err;
  }

  assert.ok(caughtError instanceof Error);
  assert.match((caughtError as Error).message, /Firestore quota exceeded/);
});

test("Phase D.17 (Cenario 14): Falha na compensacao retorna COMPENSATION_FAILED sem expor claims", async () => {
  await assert.rejects(
    () =>
      simulateSetK9InstructorRole("9001", true, {
        authUser: { uid: "uid-test", customClaims: { role: "gestor", secret_field: "private" } },
        firestoreSetError: new Error("Firestore down"),
        compensationError: new Error("Rollback failed"),
      }),
    (err: unknown) => {
      assert.ok(err instanceof HttpsError);
      assert.equal((err as HttpsError).code, "internal");
      const details = ((err as HttpsError).details as JsonMap);
      assert.equal(details?.reason, "COMPENSATION_FAILED");
      assert.equal(details?.operation, "setK9InstructorRole");
      assert.equal(details?.target_ra, "9001");
      assert.equal(details?.previousClaims, undefined);
      assert.equal(details?.claims, undefined);
      assert.equal(details?.customClaims, undefined);
      return true;
    },
  );
});

test("Phase D.18 (Cenario 16): updated_at e updatedAt sao ambos gravados no payload", async () => {
  const { recorded } = await simulateSetK9InstructorRole("9001", true);
  const write = recorded.firestoreWrites[0].payload;
  assert.equal(write.updated_at, "SERVER_TIMESTAMP");
  assert.equal(write.updatedAt, "SERVER_TIMESTAMP");
});

// ── Novos Testes de Integracao CT-I2-03 (Secoes 4, 5, 8, 11) ─────────────────

test("CT-I2-03 Integration Case 1: Personnel sem access_profile_id + ligar Instrutor -> zero base authorization", async () => {
  const { recorded, result } = await simulateSetK9InstructorRole("9020", true, {
    userData: {
      active: true,
      status: "Ativo",
      email: "9020@gcm.com.br",
      // Sem access_profile_id nem role
    },
    authUser: {
      uid: "uid-9020",
      customClaims: {},
    },
  });

  assert.equal(result?.enabled, true);
  const write = recorded.firestoreWrites[0].payload;
  assert.equal(write.is_k9_instructor, true);
  assert.equal(write.training_role, "instrutor_k9");
  assert.equal(write.training_instructor, true);
  // Invariante: sem perfil, NENHUMA role singular base e fabricada
  assert.equal(write.role, null);
  assert.equal(write.claim_role, null);
  assert.deepEqual(write.roles, ["instrutor_k9"]);
  // Invariante: NENHUM perfil ou escopo e gravado
  assert.equal(write.access_profile_id, undefined);
  assert.equal(write.access_scope, undefined);

  // Claims
  const claims = recorded.claimsSet[0].claims;
  assert.equal(claims.role, null);
  assert.equal(claims.access_profile_id, null);
  assert.equal(claims.access_scope, null);
  assert.equal(claims.admin, false);
  assert.equal(claims.web_access, false);
  assert.equal(claims.mobile_access, false);
  assert.deepEqual(claims.roles, ["instrutor_k9"]);
  assert.equal(claims.instrutor_k9, true);
  assert.equal(claims.training_role, "instrutor_k9");
  assert.equal(claims.training_instructor, true);
});

test("CT-I2-03 Integration Case 2: Personnel sem access_profile_id + desligar Instrutor -> zero base authorization", async () => {
  const { recorded, result } = await simulateSetK9InstructorRole("9020", false, {
    userData: {
      active: true,
      status: "Ativo",
      email: "9020@gcm.com.br",
      is_k9_instructor: true,
      training_role: "instrutor_k9",
    },
    authUser: {
      uid: "uid-9020",
      customClaims: {
        roles: ["instrutor_k9"],
        instrutor_k9: true,
      },
    },
  });

  assert.equal(result?.enabled, false);
  const write = recorded.firestoreWrites[0].payload;
  assert.equal(write.is_k9_instructor, false);
  assert.equal(write.training_role, null);
  assert.equal(write.training_instructor, null);
  assert.equal(write.role, null);
  assert.equal(write.claim_role, null);
  assert.deepEqual(write.roles, []);

  const claims = recorded.claimsSet[0].claims;
  assert.equal(claims.role, null);
  assert.equal(claims.access_profile_id, null);
  assert.deepEqual(claims.roles, []);
  assert.equal(claims.instrutor_k9, undefined);
});

test("CT-I2-03 Integration Case 3: Perfil referenciado inexistente nao sintetiza operador", async () => {
  const { recorded } = await simulateSetK9InstructorRole("9021", true, {
    userData: {
      access_profile_id: "missing_profile_xyz",
      email: "9021@gcm.com.br",
    },
    profileExists: false,
  });

  const write = recorded.firestoreWrites[0].payload;
  // Perfil nao existe -> autorizacao base indisponivel -> role null
  assert.equal(write.role, null);
  assert.equal(write.claim_role, null);
  assert.deepEqual(write.roles, ["instrutor_k9"]);

  const claims = recorded.claimsSet[0].claims;
  assert.equal(claims.role, null);
  assert.equal(claims.access_profile_id, null);
  assert.deepEqual(claims.roles, ["instrutor_k9"]);
});

test("CT-I2-03 Integration Case 4: Perfil referenciado inativo nao sintetiza operador", async () => {
  const { recorded } = await simulateSetK9InstructorRole("9022", true, {
    userData: {
      access_profile_id: "profile_inativo",
      email: "9022@gcm.com.br",
    },
    profileData: {
      status: "inactive",
      scope: "global",
      role_keys: ["operador_k9"],
    },
  });

  const write = recorded.firestoreWrites[0].payload;
  assert.equal(write.role, null);
  assert.equal(write.claim_role, null);
  assert.deepEqual(write.roles, ["instrutor_k9"]);

  const claims = recorded.claimsSet[0].claims;
  assert.equal(claims.role, null);
  assert.equal(claims.access_profile_id, null);
  assert.deepEqual(claims.roles, ["instrutor_k9"]);
});
