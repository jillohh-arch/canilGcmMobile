/**
 * Relógio autoritativo genérico do sistema.
 *
 * Read-only: não acessa Firestore e não recebe contexto de Health/K9.
 */
import {CallableRequest, HttpsError} from "firebase-functions/v2/https";

const PROTOCOL_VERSION = 1;
const MAX_AGE_MS: 900000 = 900000;
const MAX_SUPPORTED_UTC_MS = 8_640_000_000_000_000;
const UUID_PATTERN =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

type JsonMap = Record<string, unknown>;

export interface SystemAuthoritativeTimeDeps {
  nowMs: () => number;
  requestId: () => string;
}

export interface SystemAuthoritativeTimeResponse {
  protocol_version: 1;
  request_id: string;
  request_received_at_utc_ms: number;
  server_sent_at_utc_ms: number;
  max_age_ms: 900000;
}

function appError(
  http: "invalid-argument" | "unauthenticated" | "internal",
  code: string,
  message: string,
): never {
  throw new HttpsError(http, message, {code});
}

function requireExactProtocol(data: unknown): void {
  if (!data || typeof data !== "object" || Array.isArray(data)) {
    appError("invalid-argument", "invalid_payload", "Payload inválido.");
  }
  const payload = data as JsonMap;
  const keys = Object.keys(payload);
  if (keys.length !== 1 || keys[0] !== "protocol_version") {
    appError(
      "invalid-argument",
      "invalid_payload",
      "Payload deve conter somente protocol_version.",
    );
  }
  if (!Number.isInteger(payload.protocol_version)) {
    appError(
      "invalid-argument",
      "invalid_protocol_version",
      "protocol_version deve ser inteiro.",
    );
  }
  if (payload.protocol_version !== PROTOCOL_VERSION) {
    appError(
      "invalid-argument",
      "unsupported_protocol_version",
      "Versão de protocolo não suportada.",
    );
  }
}

function requireRuntimeTimestamp(value: number): number {
  if (
    !Number.isSafeInteger(value) ||
    value < 0 ||
    value > MAX_SUPPORTED_UTC_MS
  ) {
    appError(
      "internal",
      "authoritative_time_integrity",
      "Falha de integridade temporal.",
    );
  }
  return value;
}

/** Handler puro/testável usado pelo export onCall. */
export async function runSystemAuthoritativeTimeNow(
  request: CallableRequest<unknown>,
  deps: SystemAuthoritativeTimeDeps,
): Promise<SystemAuthoritativeTimeResponse> {
  const requestReceivedAtUtcMs = requireRuntimeTimestamp(deps.nowMs());

  if (!request.auth) {
    appError("unauthenticated", "unauthenticated", "Autenticação obrigatória.");
  }
  requireExactProtocol(request.data);

  const requestId = deps.requestId().trim();
  if (!UUID_PATTERN.test(requestId)) {
    appError(
      "internal",
      "authoritative_time_integrity",
      "Falha de integridade da requisição.",
    );
  }

  const serverSentAtUtcMs = requireRuntimeTimestamp(deps.nowMs());
  if (serverSentAtUtcMs < requestReceivedAtUtcMs) {
    appError(
      "internal",
      "authoritative_time_integrity",
      "Falha de integridade temporal.",
    );
  }

  return {
    protocol_version: PROTOCOL_VERSION,
    request_id: requestId,
    request_received_at_utc_ms: requestReceivedAtUtcMs,
    server_sent_at_utc_ms: serverSentAtUtcMs,
    max_age_ms: MAX_AGE_MS,
  };
}
