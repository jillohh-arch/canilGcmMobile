/**
 * FRONT10.ACCESS-CREDENTIALS.D — TESTES DE COMPOSICAO DETERMINISTICA DE CLAIMS (Phase D).
 *
 * Cobre a matriz de testes exigida pela Secao 20 e 21:
 * - Profile -> Instructor preservation (1 a 4)
 * - Instructor -> Profile preservation (5 e 6)
 * - Separacao estrita de autoridades / sem colisao de writers (7 a 9, 21)
 * - Preservacao de claims nao gerenciadas e determinismo
 */

import * as assert from "node:assert/strict";
import { test } from "node:test";
import {
  composeEffectiveAccessClaims,
  JsonMap,
} from "../src/access_claims_composition";

test("Phase D.1: Instructor OFF + profile Gestor -> correct base claims", () => {
  const result = composeEffectiveAccessClaims(
    {},
    "9001",
    {
      profileId: "gestor",
      roleKeys: ["gestor"],
      accessScope: "global",
    },
    false,
  );

  assert.equal(result.ra, "9001");
  assert.equal(result.access_profile_id, "gestor");
  assert.equal(result.role, "gestor");
  assert.deepEqual(result.roles, ["gestor"]);
  assert.equal(result.instrutor_k9, undefined);
  assert.equal(result.training_role, undefined);
  assert.equal(result.training_instructor, undefined);
  assert.equal(result.mobile_access, false);
});

test("Phase D.2: Instructor ON + profile Gestor -> base claims + Instructor functional claims", () => {
  const result = composeEffectiveAccessClaims(
    {},
    "9001",
    {
      profileId: "gestor",
      roleKeys: ["gestor"],
      accessScope: "global",
    },
    true,
  );

  assert.equal(result.ra, "9001");
  assert.equal(result.access_profile_id, "gestor");
  // Invariante critico: a singular role continua sendo a de gestor, NUNCA sobreposta
  assert.equal(result.role, "gestor");
  // Roles reflete a uniao deterministica SEM fabricar condutor
  assert.deepEqual(result.roles, ["gestor", "instrutor_k9"]);
  // Claims de instrutor presentes
  assert.equal(result.instrutor_k9, true);
  assert.equal(result.training_role, "instrutor_k9");
  assert.equal(result.training_instructor, true);
  assert.equal(result.mobile_access, false);
});

test("Phase D.3: Change profile Gestor -> Operador while Instructor ON preserves Instructor qualification", () => {
  const previousClaims: JsonMap = {
    ra: "9001",
    access_profile_id: "gestor",
    role: "gestor",
    roles: ["condutor", "gestor", "instrutor_k9"],
    instrutor_k9: true,
    training_role: "instrutor_k9",
    training_instructor: true,
  };

  const nextClaims = composeEffectiveAccessClaims(
    previousClaims,
    "9001",
    {
      profileId: "operador_k9",
      roleKeys: ["operador_k9", "condutor"],
      accessScope: "global",
    },
    true, // Instructor continua ON
  );

  assert.equal(nextClaims.access_profile_id, "operador_k9");
  assert.equal(nextClaims.role, "condutor");
  // Perfil antigo ("gestor") foi retirado de roles; novo perfil e instrutor presentes
  assert.deepEqual(nextClaims.roles, ["condutor", "instrutor_k9", "operador_k9"]);
  // Claims de instrutor continuam ativas
  assert.equal(nextClaims.instrutor_k9, true);
  assert.equal(nextClaims.training_role, "instrutor_k9");
  assert.equal(nextClaims.training_instructor, true);
});

test("Phase D.4: Change profile while Instructor OFF -> no Instructor claim magically appears", () => {
  const previousClaims: JsonMap = {
    ra: "9001",
    access_profile_id: "operador_k9",
    role: "condutor",
    roles: ["condutor", "operador_k9"],
  };

  const nextClaims = composeEffectiveAccessClaims(
    previousClaims,
    "9001",
    {
      profileId: "gestor",
      roleKeys: ["gestor"],
      accessScope: "global",
    },
    false, // Instructor OFF
  );

  assert.equal(nextClaims.access_profile_id, "gestor");
  assert.equal(nextClaims.role, "gestor");
  assert.deepEqual(nextClaims.roles, ["gestor"]);
  assert.equal(nextClaims.instrutor_k9, undefined);
  assert.equal(nextClaims.training_role, undefined);
  assert.equal(nextClaims.training_instructor, undefined);
});

test("Phase D.5: Profile assigned + turn Instructor ON -> same Access Profile, added Instructor claims", () => {
  const existingClaims: JsonMap = {
    ra: "9001",
    access_profile_id: "administrador",
    role: "admin",
    admin: true,
    access_scope: "global",
    roles: ["admin"],
  };

  const nextClaims = composeEffectiveAccessClaims(
    existingClaims,
    "9001",
    {
      profileId: "administrador",
      roleKeys: ["admin"],
      accessScope: "global",
    },
    true, // Ligar Instrutor
  );

  // Perfil e escopo base preservados
  assert.equal(nextClaims.access_profile_id, "administrador");
  assert.equal(nextClaims.access_scope, "global");
  assert.equal(nextClaims.admin, true);
  assert.equal(nextClaims.role, "admin");
  // Instrutor adicionado sem fabricar condutor
  assert.deepEqual(nextClaims.roles, ["admin", "administrador", "instrutor_k9"]);
  assert.equal(nextClaims.instrutor_k9, true);
  assert.equal(nextClaims.training_role, "instrutor_k9");
  assert.equal(nextClaims.training_instructor, true);
});

test("Phase D.6: Turn Instructor OFF -> Access Profile and base roles remain, only Instructor removed", () => {
  const existingClaims: JsonMap = {
    ra: "9001",
    access_profile_id: "gestor",
    role: "gestor",
    roles: ["gestor", "instrutor_k9"],
    instrutor_k9: true,
    training_role: "instrutor_k9",
    training_instructor: true,
    access_scope: "global",
  };

  const nextClaims = composeEffectiveAccessClaims(
    existingClaims,
    "9001",
    {
      profileId: "gestor",
      roleKeys: ["gestor"],
      accessScope: "global",
    },
    false, // Desligar Instrutor
  );

  assert.equal(nextClaims.access_profile_id, "gestor");
  assert.equal(nextClaims.access_scope, "global");
  assert.equal(nextClaims.role, "gestor");
  assert.deepEqual(nextClaims.roles, ["gestor"]);
  assert.equal(nextClaims.instrutor_k9, undefined);
  assert.equal(nextClaims.training_role, undefined);
  assert.equal(nextClaims.training_instructor, undefined);
});

test("Phase D.7: Preserva claims nao gerenciadas (unrelated/identity/custom claims)", () => {
  const existingClaims: JsonMap = {
    custom_system_claim: "k9_special_unit",
    external_provider_id: 12345,
    roles: ["gestor", "equipe_resgate"], // "equipe_resgate" e papel nao gerenciado pelo Front 10
  };

  const nextClaims = composeEffectiveAccessClaims(
    existingClaims,
    "9001",
    {
      profileId: "gestor",
      roleKeys: ["gestor"],
      accessScope: "global",
    },
    true,
  );

  assert.equal(nextClaims.custom_system_claim, "k9_special_unit");
  assert.equal(nextClaims.external_provider_id, 12345);
  // "equipe_resgate" preservada junto com as novas roles
  assert.ok(Array.isArray(nextClaims.roles));
  assert.ok((nextClaims.roles as string[]).includes("equipe_resgate"));
  assert.ok((nextClaims.roles as string[]).includes("gestor"));
  assert.ok((nextClaims.roles as string[]).includes("instrutor_k9"));
});

test("Phase D.8: Almoxarifado + Instructor ON compoe inventory_manager e instrutor_k9", () => {
  const nextClaims = composeEffectiveAccessClaims(
    {},
    "9002",
    {
      profileId: "almoxarifado",
      roleKeys: ["almoxarifado", "inventory_manager"],
      accessScope: "global",
    },
    true,
  );

  assert.equal(nextClaims.role, "inventory_manager");
  assert.equal(nextClaims.inventory_manager, true);
  assert.equal(nextClaims.instrutor_k9, true);
  assert.deepEqual(nextClaims.roles, ["almoxarifado", "instrutor_k9", "inventory_manager"]);
});

test("Phase D.9 (Secao 21): Profile contendo instrutor_k9 em role_keys (perfil legado)", () => {
  const nextClaims = composeEffectiveAccessClaims(
    {},
    "9003",
    {
      profileId: "instrutor_k9",
      roleKeys: ["instrutor_k9", "instrutor", "adestrador"],
      accessScope: "global",
    },
    false, // Flag direta false, mas o perfil legado e de instrutor
  );

  assert.equal(nextClaims.role, "instrutor_k9");
  assert.equal(nextClaims.access_profile_id, "instrutor_k9");
  assert.equal(nextClaims.instrutor_k9, true);
  assert.ok((nextClaims.roles as string[]).includes("instrutor_k9"));
});

test("Phase D.10: Determinismo na composicao de roles e sort estavel", () => {
  const r1 = composeEffectiveAccessClaims(
    { roles: ["b_custom", "a_custom"] },
    "9001",
    { profileId: "gestor", roleKeys: ["gestor"], accessScope: "global" },
    true,
  );

  const r2 = composeEffectiveAccessClaims(
    { roles: ["a_custom", "b_custom"] },
    "9001",
    { profileId: "gestor", roleKeys: ["gestor"], accessScope: "global" },
    true,
  );

  assert.deepEqual(r1.roles, r2.roles);
  assert.deepEqual(r1.roles, ["a_custom", "b_custom", "gestor", "instrutor_k9"]);
});

// ── Novos Casos de Seguranca CT-I2-03 (Secoes 4, 5, 7, 10, 11) ───────────────

test("CT-I2-03 Case 1: Personnel sem access_profile_id + ligar Instrutor -> zero base authorization fabricada", () => {
  const result = composeEffectiveAccessClaims(
    {},
    "9010",
    {
      profileId: null,
      roleKeys: [],
      accessScope: null,
    },
    true, // Ligar Instrutor
  );

  assert.equal(result.ra, "9010");
  assert.equal(result.access_profile_id, null);
  assert.equal(result.access_scope, null);
  assert.equal(result.role, null);
  assert.equal(result.admin, false);
  assert.equal(result.inventory_manager, undefined);
  assert.equal(result.web_access, false);
  assert.equal(result.mobile_access, false);
  assert.deepEqual(result.roles, ["instrutor_k9"]);
  assert.equal(result.instrutor_k9, true);
  assert.equal(result.training_role, "instrutor_k9");
  assert.equal(result.training_instructor, true);

  // Invariante critico: NENHUM condutor ou operador fabricado
  assert.ok(!result.roles.includes("condutor"));
  assert.ok(!result.roles.includes("operador_k9"));
});

test("CT-I2-03 Case 2: Personnel sem access_profile_id + desligar Instrutor -> zero base authorization", () => {
  const result = composeEffectiveAccessClaims(
    {
      roles: ["instrutor_k9"],
      instrutor_k9: true,
    },
    "9010",
    {
      profileId: null,
      roleKeys: [],
      accessScope: null,
    },
    false, // Desligar Instrutor
  );

  assert.equal(result.access_profile_id, null);
  assert.equal(result.access_scope, null);
  assert.equal(result.role, null);
  assert.deepEqual(result.roles, []);
  assert.equal(result.instrutor_k9, undefined);
  assert.equal(result.training_role, undefined);
  assert.equal(result.training_instructor, undefined);
});

test("CT-I2-03 Case 3: Perfil referenciado inexistente/ausente trata base authorization como indisponivel", () => {
  const result = composeEffectiveAccessClaims(
    {},
    "9011",
    {
      profileId: null,
      roleKeys: [],
      accessScope: null,
    },
    true,
  );

  assert.equal(result.access_profile_id, null);
  assert.equal(result.access_scope, null);
  assert.equal(result.role, null);
  assert.deepEqual(result.roles, ["instrutor_k9"]);
  assert.equal(result.instrutor_k9, true);
});

test("CT-I2-03 Case 4 / Secao 7: Limpeza de claims proprietarias obsoletas preservando claims nao pertencentes", () => {
  const staleClaims: JsonMap = {
    ra: "9012",
    access_profile_id: "administrador",
    access_scope: "global",
    admin: true,
    role: "admin",
    roles: ["admin", "administrador", "resgate_k9"], // "resgate_k9" e nao-gerenciada
    custom_tenant: "k9_sp",
    unrelated_external_id: "ext-99",
  };

  // Sem perfil valido
  const result = composeEffectiveAccessClaims(
    staleClaims,
    "9012",
    {
      profileId: null,
      roleKeys: [],
      accessScope: null,
    },
    false,
  );

  // Chaves proprietarias foram purgadas
  assert.equal(result.access_profile_id, null);
  assert.equal(result.access_scope, null);
  assert.equal(result.admin, false);
  assert.equal(result.role, null);
  assert.equal(result.web_access, false);
  // Unrelated claims preservadas
  assert.equal(result.custom_tenant, "k9_sp");
  assert.equal(result.unrelated_external_id, "ext-99");
  // Apenas role nao gerenciada preservada
  assert.deepEqual(result.roles, ["resgate_k9"]);
});

test("Secao 10: Auditoria de preservacao de roles em mudanca de perfil (Admin -> Almoxarifado)", () => {
  const oldAdminClaims: JsonMap = {
    ra: "9013",
    access_profile_id: "administrador",
    access_scope: "global",
    admin: true,
    role: "admin",
    roles: ["admin", "admin_master", "administrador", "ti", "instrutor_k9", "custom_audit_unit"],
    instrutor_k9: true,
    training_role: "instrutor_k9",
    training_instructor: true,
  };

  const nextClaims = composeEffectiveAccessClaims(
    oldAdminClaims,
    "9013",
    {
      profileId: "almoxarifado",
      roleKeys: ["almoxarifado", "inventory_manager", "estoque"],
      accessScope: "global",
    },
    true, // Mantem Instrutor
  );

  assert.equal(nextClaims.access_profile_id, "almoxarifado");
  assert.equal(nextClaims.role, "inventory_manager");
  assert.equal(nextClaims.admin, false);
  assert.equal(nextClaims.inventory_manager, true);
  assert.equal(nextClaims.instrutor_k9, true);

  // Todas as roles de administrador ("admin", "admin_master", "administrador", "ti") foram expurgadas!
  assert.deepEqual(nextClaims.roles, [
    "almoxarifado",
    "custom_audit_unit",
    "estoque",
    "instrutor_k9",
    "inventory_manager",
  ]);
});
