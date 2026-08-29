import * as assert from "assert";
import {DecodedIdToken} from "firebase-admin/auth";
import {isAdminAccessLevel, isAdminToken, isAdminUserRecord, profileGrantsPermission} from "./index";

type JsonMap = Record<string, unknown>;

function token(overrides: JsonMap = {}): DecodedIdToken {
  return {aud: "canil-gcm", auth_time: 0, exp: 0, firebase: {identities: {}, sign_in_provider: "custom"},
    iat: 0, iss: "test", sub: "uid", uid: "uid", ...overrides} as DecodedIdToken;
}

function profile(health: unknown, extra: JsonMap = {}): JsonMap {
  return {status: "active", permissions: {health}, ...extra};
}

async function test(name: string, fn: () => void) {
  fn();
  console.log(`ok - permission ${name}`);
}

async function main() {
  await test("admin token bypass variants", () => {
    assert.strictEqual(isAdminToken(token({admin: true})), true);
    assert.strictEqual(isAdminToken(token({role: "administrador"})), true);
    assert.strictEqual(isAdminToken(token({roles: ["admin_master"]})), true);
    assert.strictEqual(isAdminToken(token({role: "gestor"})), false);
  });
  await test("users admin access levels retain bypass", () => {
    assert.strictEqual(isAdminAccessLevel("admin"), true);
    assert.strictEqual(isAdminAccessLevel("Administrador"), true);
    assert.strictEqual(isAdminAccessLevel("gestor"), false);
    assert.strictEqual(isAdminUserRecord({admin: true}), true);
    assert.strictEqual(isAdminUserRecord({access_level: "administrador"}), true);
    assert.strictEqual(isAdminUserRecord({accessLevel: "gestor", admin: false}), false);
  });
  await test("manager with explicit capability is allowed", () => {
    assert.strictEqual(profileGrantsPermission(profile({manage_nutrition_plan: true}), "health", "manage_nutrition_plan"), true);
  });
  await test("manager without capability is denied", () => {
    assert.strictEqual(profileGrantsPermission(profile({view: true, edit: true}), "health", "manage_nutrition_plan"), false);
  });
  await test("operator create/edit does not imply plan management", () => {
    assert.strictEqual(profileGrantsPermission(profile({view: true, create: true, edit: true}), "health", "manage_nutrition_plan"), false);
  });
  await test("instructor create/edit does not imply plan management", () => {
    assert.strictEqual(profileGrantsPermission(profile({create: true, edit: true}), "health", "manage_nutrition_plan"), false);
  });
  await test("missing and inactive profiles fail closed", () => {
    assert.strictEqual(profileGrantsPermission({}, "health", "manage_nutrition_plan"), false);
    assert.strictEqual(profileGrantsPermission(profile({manage_nutrition_plan: true}, {status: "inactive"}), "health", "manage_nutrition_plan"), false);
  });
  await test("malformed permissions fail closed", () => {
    assert.strictEqual(profileGrantsPermission({status: "active", permissions: "invalid"}, "health", "manage_nutrition_plan"), false);
    assert.strictEqual(profileGrantsPermission(profile(["manage_nutrition_plan"]), "health", "manage_nutrition_plan"), false);
  });
  await test("only literal true grants capability", () => {
    for (const value of [false, "true", 1, null]) {
      assert.strictEqual(profileGrantsPermission(profile({manage_nutrition_plan: value}), "health", "manage_nutrition_plan"), false);
    }
  });
  await test("custom profile follows the same explicit model", () => {
    assert.strictEqual(profileGrantsPermission(profile({view: true}, {id: "custom_clinical"}), "health", "manage_nutrition_plan"), false);
    assert.strictEqual(profileGrantsPermission(profile({manage_nutrition_plan: true}, {id: "custom_clinical"}), "health", "manage_nutrition_plan"), true);
  });
  console.log("health_nutrition_permission_test: all passed");
}

void main().catch((error) => {console.error(error); process.exitCode = 1;});
