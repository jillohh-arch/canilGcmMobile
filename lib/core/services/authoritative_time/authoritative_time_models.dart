enum AuthoritativeTimeStatus {
  neverSynchronized,
  synchronizing,
  fresh,
  stale,
  expired,
  failed,
}

enum AuthoritativeTimeSource { systemAuthoritativeTimeNow }

enum AuthoritativeTimeFailureCode {
  unauthenticated,
  unavailable,
  invalidResponse,
  invalidMeasurement,
  excessiveRoundTrip,
  excessiveUncertainty,
  regressiveAnchor,
  invalidated,
  unexpected,
}

final class AuthoritativeTimeFailure implements Exception {
  const AuthoritativeTimeFailure(this.code, this.message);

  final AuthoritativeTimeFailureCode code;
  final String message;

  @override
  String toString() => 'AuthoritativeTimeFailure($code, $message)';
}

final class AuthoritativeTimeRemoteResponse {
  const AuthoritativeTimeRemoteResponse({
    required this.protocolVersion,
    required this.requestId,
    required this.requestReceivedAtUtc,
    required this.serverSentAtUtc,
    required this.maxAge,
  });

  static const int supportedProtocolVersion = 1;
  static const Duration requiredMaxAge = Duration(minutes: 15);

  final int protocolVersion;
  final String requestId;
  final DateTime requestReceivedAtUtc;
  final DateTime serverSentAtUtc;
  final Duration maxAge;

  factory AuthoritativeTimeRemoteResponse.fromMap(Map<String, dynamic> raw) {
    const requiredKeys = <String>{
      'protocol_version',
      'request_id',
      'request_received_at_utc_ms',
      'server_sent_at_utc_ms',
      'max_age_ms',
    };
    if (raw.keys.toSet().difference(requiredKeys).isNotEmpty ||
        requiredKeys.difference(raw.keys.toSet()).isNotEmpty) {
      throw const AuthoritativeTimeFailure(
        AuthoritativeTimeFailureCode.invalidResponse,
        'Resposta temporal possui campos ausentes ou desconhecidos.',
      );
    }

    final protocol = _requiredInt(raw, 'protocol_version');
    if (protocol != supportedProtocolVersion) {
      throw const AuthoritativeTimeFailure(
        AuthoritativeTimeFailureCode.invalidResponse,
        'Versão do protocolo temporal não suportada.',
      );
    }
    final requestIdRaw = raw['request_id'];
    if (requestIdRaw is! String ||
        !_uuidPattern.hasMatch(requestIdRaw.trim())) {
      throw const AuthoritativeTimeFailure(
        AuthoritativeTimeFailureCode.invalidResponse,
        'request_id temporal inválido.',
      );
    }

    final receivedMs = _requiredInt(raw, 'request_received_at_utc_ms');
    final sentMs = _requiredInt(raw, 'server_sent_at_utc_ms');
    final maxAgeMs = _requiredInt(raw, 'max_age_ms');
    if (receivedMs < 0 || sentMs < receivedMs) {
      throw const AuthoritativeTimeFailure(
        AuthoritativeTimeFailureCode.invalidResponse,
        'Timestamps temporais fora de ordem.',
      );
    }
    if (maxAgeMs != requiredMaxAge.inMilliseconds) {
      throw const AuthoritativeTimeFailure(
        AuthoritativeTimeFailureCode.invalidResponse,
        'max_age_ms temporal inválido.',
      );
    }

    try {
      return AuthoritativeTimeRemoteResponse(
        protocolVersion: protocol,
        requestId: requestIdRaw.trim(),
        requestReceivedAtUtc: DateTime.fromMillisecondsSinceEpoch(
          receivedMs,
          isUtc: true,
        ),
        serverSentAtUtc: DateTime.fromMillisecondsSinceEpoch(
          sentMs,
          isUtc: true,
        ),
        maxAge: Duration(milliseconds: maxAgeMs),
      );
    } on RangeError {
      throw const AuthoritativeTimeFailure(
        AuthoritativeTimeFailureCode.invalidResponse,
        'Timestamp temporal fora do intervalo suportado.',
      );
    }
  }

  static int _requiredInt(Map<String, dynamic> raw, String key) {
    final value = raw[key];
    if (value is! int) {
      throw AuthoritativeTimeFailure(
        AuthoritativeTimeFailureCode.invalidResponse,
        '$key deve ser inteiro.',
      );
    }
    return value;
  }

  static final RegExp _uuidPattern = RegExp(
    r'^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
    caseSensitive: false,
  );
}

final class AuthoritativeTimeSnapshot {
  const AuthoritativeTimeSnapshot({
    required this.anchorServerUtcAtReceive,
    required this.anchorMonotonicElapsed,
    required this.synchronizedServerUtc,
    required this.roundTrip,
    required this.serverProcessing,
    required this.networkRoundTrip,
    required this.uncertainty,
    required this.maxAge,
    required this.requestId,
    required this.source,
    required this.status,
  });

  final DateTime anchorServerUtcAtReceive;
  final Duration anchorMonotonicElapsed;
  final DateTime synchronizedServerUtc;
  final Duration roundTrip;
  final Duration serverProcessing;
  final Duration networkRoundTrip;
  final Duration uncertainty;
  final Duration maxAge;
  final String requestId;
  final AuthoritativeTimeSource source;
  final AuthoritativeTimeStatus status;

  AuthoritativeTimeSnapshot copyWithStatus(AuthoritativeTimeStatus value) {
    return AuthoritativeTimeSnapshot(
      anchorServerUtcAtReceive: anchorServerUtcAtReceive,
      anchorMonotonicElapsed: anchorMonotonicElapsed,
      synchronizedServerUtc: synchronizedServerUtc,
      roundTrip: roundTrip,
      serverProcessing: serverProcessing,
      networkRoundTrip: networkRoundTrip,
      uncertainty: uncertainty,
      maxAge: maxAge,
      requestId: requestId,
      source: source,
      status: value,
    );
  }
}

sealed class AuthoritativeTimeSyncResult {
  const AuthoritativeTimeSyncResult();
}

final class AuthoritativeTimeSyncSuccess extends AuthoritativeTimeSyncResult {
  const AuthoritativeTimeSyncSuccess(this.snapshot);

  final AuthoritativeTimeSnapshot snapshot;
}

final class AuthoritativeTimeSyncFailure extends AuthoritativeTimeSyncResult {
  const AuthoritativeTimeSyncFailure(this.failure, {this.retainedSnapshot});

  final AuthoritativeTimeFailure failure;
  final AuthoritativeTimeSnapshot? retainedSnapshot;
}
