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
  // Roles reflete a uniao deterministica
  assert.deepEqual(result.roles, ["condutor", "gestor", "instrutor_k9"]);
  // Claims de instrutor presentes
  assert.equal(result.instrutor_k9, true);
  assert.equal(result.training_role, "instrutor_k9");
  assert.equal(result.training_instructor, true);
  assert.equal(result.mobile_access, true);
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
  // Instrutor adicionado
  assert.deepEqual(nextClaims.roles, ["admin", "administrador", "condutor", "instrutor_k9"]);
  assert.equal(nextClaims.instrutor_k9, true);
  assert.equal(nextClaims.training_role, "instrutor_k9");
  assert.equal(nextClaims.training_instructor, true);
});

test("Phase D.6: Turn Instructor OFF -> Access Profile and base roles remain, only Instructor removed", () => {
  const existingClaims: JsonMap = {
    ra: "9001",
    access_profile_id: "gestor",
    role: "gestor",
    roles: ["condutor", "gestor", "instrutor_k9"],
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
  assert.deepEqual(nextClaims.roles, ["almoxarifado", "condutor", "instrutor_k9", "inventory_manager"]);
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
  assert.deepEqual(r1.roles, ["a_custom", "b_custom", "condutor", "gestor", "instrutor_k9"]);
});
