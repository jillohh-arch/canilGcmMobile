import * as assert from "assert";
import {HttpsError} from "firebase-functions/v2/https";
import {
  runSystemAuthoritativeTimeNow,
  SystemAuthoritativeTimeDeps,
} from "./system_authoritative_time_callable";

type JsonMap = Record<string, unknown>;

const MIN_SUPPORTED_UTC_MS = 0;
const MAX_SUPPORTED_UTC_MS = 8_640_000_000_000_000;
const OUTSIDE_JAVASCRIPT_SAFE_INTEGER = 9_007_199_254_740_992;

function request(data: unknown, authenticated = true): any {
  return {
    data,
    auth: authenticated ? {uid: "uid-test", token: {email: "operator@example.test"}} : undefined,
  };
}

function deps(
  times = [1_785_686_400_000, 1_785_686_400_002],
  id = "00000000-0000-4000-8000-000000000001",
):
SystemAuthoritativeTimeDeps {
  let index = 0;
  return {
    nowMs: () => times[Math.min(index++, times.length - 1)],
    requestId: () => id,
  };
}

async function rejectsCode(
  operation: () => Promise<unknown>,
  transport: string,
  detail: string,
): Promise<void> {
  await assert.rejects(operation, (error: unknown) => {
    const value = error as HttpsError;
    return value.code === transport &&
      (value.details as JsonMap | undefined)?.code === detail &&
      !String(value.message).toLowerCase().includes("stack");
  });
}

async function main(): Promise<void> {
  const valid = await runSystemAuthoritativeTimeNow(
    request({protocol_version: 1}),
    deps(),
  );

  assert.deepStrictEqual(valid, {
    protocol_version: 1,
    request_id: "00000000-0000-4000-8000-000000000001",
    request_received_at_utc_ms: 1_785_686_400_000,
    server_sent_at_utc_ms: 1_785_686_400_002,
    max_age_ms: 900_000,
  });
  assert.ok(Number.isInteger(valid.request_received_at_utc_ms));
  assert.ok(Number.isInteger(valid.server_sent_at_utc_ms));
  assert.ok(valid.server_sent_at_utc_ms >= valid.request_received_at_utc_ms);
  assert.strictEqual(valid.max_age_ms, 900_000);
  assert.deepStrictEqual(Object.keys(valid).sort(), [
    "max_age_ms",
    "protocol_version",
    "request_id",
    "request_received_at_utc_ms",
    "server_sent_at_utc_ms",
  ]);
  const serialized = JSON.stringify(valid);
  assert.ok(!serialized.includes("uid-test"));
  assert.ok(!serialized.includes("operator@example.test"));
  assert.ok(!serialized.toLowerCase().includes("dog"));

  const minimum = await runSystemAuthoritativeTimeNow(
    request({protocol_version: 1}),
    deps([MIN_SUPPORTED_UTC_MS, MIN_SUPPORTED_UTC_MS]),
  );
  assert.strictEqual(minimum.request_received_at_utc_ms, MIN_SUPPORTED_UTC_MS);
  assert.strictEqual(minimum.server_sent_at_utc_ms, MIN_SUPPORTED_UTC_MS);

  const maximum = await runSystemAuthoritativeTimeNow(
    request({protocol_version: 1}),
    deps([MAX_SUPPORTED_UTC_MS, MAX_SUPPORTED_UTC_MS]),
  );
  assert.strictEqual(maximum.request_received_at_utc_ms, MAX_SUPPORTED_UTC_MS);
  assert.strictEqual(maximum.server_sent_at_utc_ms, MAX_SUPPORTED_UTC_MS);

  await rejectsCode(
    () => runSystemAuthoritativeTimeNow(request({protocol_version: 1}, false), deps()),
    "unauthenticated",
    "unauthenticated",
  );
  await rejectsCode(
    () => runSystemAuthoritativeTimeNow(request({}), deps()),
    "invalid-argument",
    "invalid_payload",
  );
  await rejectsCode(
    () => runSystemAuthoritativeTimeNow(request({protocol_version: "1"}), deps()),
    "invalid-argument",
    "invalid_protocol_version",
  );
  await rejectsCode(
    () => runSystemAuthoritativeTimeNow(request({protocol_version: 2}), deps()),
    "invalid-argument",
    "unsupported_protocol_version",
  );
  await rejectsCode(
    () => runSystemAuthoritativeTimeNow(
      request({protocol_version: 1, uid: "forbidden"}),
      deps(),
    ),
    "invalid-argument",
    "invalid_payload",
  );
  await rejectsCode(
    () => runSystemAuthoritativeTimeNow(request({protocol_version: 1}), deps([2, 1])),
    "internal",
    "authoritative_time_integrity",
  );
  await rejectsCode(
    () => runSystemAuthoritativeTimeNow(request({protocol_version: 1}), deps([1, 2], "   ")),
    "internal",
    "authoritative_time_integrity",
  );
  await rejectsCode(
    () => runSystemAuthoritativeTimeNow(request({protocol_version: 1}), deps([1, 2], "not-a-uuid")),
    "internal",
    "authoritative_time_integrity",
  );
  await rejectsCode(
    () => runSystemAuthoritativeTimeNow(request({protocol_version: 1}), deps([1.5, 2])),
    "internal",
    "authoritative_time_integrity",
  );
  await rejectsCode(
    () => runSystemAuthoritativeTimeNow(
      request({protocol_version: 1}),
      deps([MIN_SUPPORTED_UTC_MS - 1, MIN_SUPPORTED_UTC_MS]),
    ),
    "internal",
    "authoritative_time_integrity",
  );
  await rejectsCode(
    () => runSystemAuthoritativeTimeNow(
      request({protocol_version: 1}),
      deps([MAX_SUPPORTED_UTC_MS + 1, MAX_SUPPORTED_UTC_MS + 1]),
    ),
    "internal",
    "authoritative_time_integrity",
  );
  await rejectsCode(
    () => runSystemAuthoritativeTimeNow(
      request({protocol_version: 1}),
      deps([OUTSIDE_JAVASCRIPT_SAFE_INTEGER, OUTSIDE_JAVASCRIPT_SAFE_INTEGER]),
    ),
    "internal",
    "authoritative_time_integrity",
  );
  await rejectsCode(
    () => runSystemAuthoritativeTimeNow(
      request({protocol_version: 1}),
      deps([1, MAX_SUPPORTED_UTC_MS + 1]),
    ),
    "internal",
    "authoritative_time_integrity",
  );
  await rejectsCode(
    () => runSystemAuthoritativeTimeNow(
      request({protocol_version: 1}),
      deps([MAX_SUPPORTED_UTC_MS + 1, MAX_SUPPORTED_UTC_MS]),
    ),
    "internal",
    "authoritative_time_integrity",
  );

  // O contrato de dependências não contém Firestore: o handler é inteiramente
  // determinístico com relógio e UUID injetados.
  assert.deepStrictEqual(Object.keys(deps()).sort(), ["nowMs", "requestId"]);
  console.log("system_authoritative_time_callable_test: ok");
}

void main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
