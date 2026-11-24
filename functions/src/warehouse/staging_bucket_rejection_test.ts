// R2 — Explicit staging-bucket rejection tests (OD-02 / warehouse_domain).
import * as assert from "assert";
import {
  isWarehouseAuthorizedBucket,
  validateWarehousePhotoUrl,
  CANONICAL_WAREHOUSE_STORAGE_BUCKET,
} from "./warehouse_domain";

function deleteEnv(...keys: string[]) {
  const saved: Record<string, string | undefined> = {};
  for (const k of keys) { saved[k] = process.env[k]; delete process.env[k]; }
  return () => {
    for (const k of keys) {
      if (saved[k] === undefined) delete process.env[k];
      else process.env[k] = saved[k];
    }
  };
}

function expectRejected(url: string, label: string) {
  assert.throws(() => validateWarehousePhotoUrl(url), (err: any) => err.code === "invalid-argument", label);
}

const ENV_KEYS = ["FUNCTIONS_EMULATOR", "FIREBASE_STORAGE_EMULATOR_HOST", "STORAGE_EMULATOR_HOST", "FIREBASE_EMULATOR_HUB", "GCLOUD_PROJECT", "FIREBASE_CONFIG"];
const restoreProd = deleteEnv(...ENV_KEYS);

// 1. Both staging bucket hostnames are rejected, in every URL form.
const stagingUrls = [
  "https://k9-ops-staging.firebasestorage.app/inventory_items/material-1/photo.jpg",
  "https://firebasestorage.googleapis.com/v0/b/k9-ops-staging.firebasestorage.app/o/inventory_items%2Fmaterial-1%2Fphoto.jpg",
  "https://firebasestorage.googleapis.com/v0/b/k9-ops-staging.appspot.com/o/inventory_items%2Fmaterial-1%2Fphoto.jpg",
  "gs://k9-ops-staging.firebasestorage.app/inventory_items/material-1/pic.webp",
  "gs://k9-ops-staging.appspot.com/inventory_items/material-1/pic.webp",
  "https://storage.googleapis.com/k9-ops-staging.appspot.com/inventory_items/material-1/photo.png",
];

for (const url of stagingUrls) {
  expectRejected(url, "staging URL must be rejected in production mode: " + url);
}

// 2. The staging bucket names never pass the predicate directly.
assert.equal(isWarehouseAuthorizedBucket("k9-ops-staging.firebasestorage.app"), false);
assert.equal(isWarehouseAuthorizedBucket("k9-ops-staging.appspot.com"), false);
assert.equal(isWarehouseAuthorizedBucket("K9-OPS-STAGING.firebasestorage.app"), false, "case-insensitive");

// 3. Production canonical buckets are still accepted.
const productionUrls = [
  "gs://canil-gcm.firebasestorage.app/inventory_items/material-1/photo.jpg",
  "gs://canil-gcm.appspot.com/inventory_items/material-1/photo.jpg",
  "https://firebasestorage.googleapis.com/v0/b/canil-gcm.firebasestorage.app/o/inventory_items%2Fmaterial-1%2Fphoto.jpg",
];
for (const url of productionUrls) {
  assert.doesNotThrow(() => validateWarehousePhotoUrl(url), "production URL must pass: " + url);
}
assert.equal(isWarehouseAuthorizedBucket(CANONICAL_WAREHOUSE_STORAGE_BUCKET), true);

// 4. An emulator runtime whose GCLOUD_PROJECT points at staging must NOT
//    authorize staging buckets through the GCLOUD_PROJECT branch.
const restoreEmuStaging = deleteEnv("FUNCTIONS_EMULATOR", "GCLOUD_PROJECT", "FIREBASE_CONFIG");
process.env.FUNCTIONS_EMULATOR = "true";
process.env.GCLOUD_PROJECT = "k9-ops-staging";
try {
  assert.equal(isWarehouseAuthorizedBucket("k9-ops-staging.appspot.com"), false,
    "emulator runtime must not extend the allowlist to staging buckets");
} finally {
  restoreEmuStaging();
}

restoreProd();
console.log("staging bucket rejection: all checks passed");

