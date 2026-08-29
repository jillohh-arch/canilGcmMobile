import 'package:flutter_test/flutter_test.dart';

import 'package:canil_gcm/core/services/authoritative_time/authoritative_time_models.dart';

const minSupportedUtcMs = 0;
const maxSupportedUtcMs = 8_640_000_000_000_000;
const outsideJavaScriptSafeInteger = 9_007_199_254_740_992;

Map<String, dynamic> validResponse({
  Object protocol = 1,
  Object requestId = '00000000-0000-4000-8000-000000000001',
  Object received = 1_785_686_400_000,
  Object sent = 1_785_686_400_002,
  Object maxAge = 900_000,
}) {
  return {
    'protocol_version': protocol,
    'request_id': requestId,
    'request_received_at_utc_ms': received,
    'server_sent_at_utc_ms': sent,
    'max_age_ms': maxAge,
  };
}

void main() {
  test('parses exact protocol v1 response', () {
    final parsed = AuthoritativeTimeRemoteResponse.fromMap(validResponse());

    expect(parsed.protocolVersion, 1);
    expect(parsed.requestId, '00000000-0000-4000-8000-000000000001');
    expect(parsed.requestReceivedAtUtc.isUtc, isTrue);
    expect(parsed.serverSentAtUtc.isUtc, isTrue);
    expect(parsed.maxAge, const Duration(minutes: 15));
  });

  test('accepts the common JavaScript and Dart timestamp boundaries', () {
    final minimum = AuthoritativeTimeRemoteResponse.fromMap(
      validResponse(received: minSupportedUtcMs, sent: minSupportedUtcMs),
    );
    final maximum = AuthoritativeTimeRemoteResponse.fromMap(
      validResponse(received: maxSupportedUtcMs, sent: maxSupportedUtcMs),
    );

    expect(
      minimum.requestReceivedAtUtc.millisecondsSinceEpoch,
      minSupportedUtcMs,
    );
    expect(minimum.serverSentAtUtc.millisecondsSinceEpoch, minSupportedUtcMs);
    expect(
      maximum.requestReceivedAtUtc.millisecondsSinceEpoch,
      maxSupportedUtcMs,
    );
    expect(maximum.serverSentAtUtc.millisecondsSinceEpoch, maxSupportedUtcMs);
  });

  test('rejects timestamps outside the common transport range', () {
    for (final response in [
      validResponse(received: minSupportedUtcMs - 1, sent: minSupportedUtcMs),
      validResponse(
        received: maxSupportedUtcMs + 1,
        sent: maxSupportedUtcMs + 1,
      ),
      validResponse(
        received: outsideJavaScriptSafeInteger,
        sent: outsideJavaScriptSafeInteger,
      ),
      validResponse(received: 1, sent: maxSupportedUtcMs + 1),
      validResponse(received: maxSupportedUtcMs + 1, sent: maxSupportedUtcMs),
    ]) {
      expect(
        () => AuthoritativeTimeRemoteResponse.fromMap(response),
        throwsA(isA<AuthoritativeTimeFailure>()),
      );
    }
  });

  test('rejects unknown protocol', () {
    expect(
      () => AuthoritativeTimeRemoteResponse.fromMap(validResponse(protocol: 2)),
      throwsA(isA<AuthoritativeTimeFailure>()),
    );
  });

  test('rejects missing and extra fields', () {
    final missing = validResponse()..remove('request_id');
    final extra = validResponse()..['uid'] = 'forbidden';

    expect(
      () => AuthoritativeTimeRemoteResponse.fromMap(missing),
      throwsA(isA<AuthoritativeTimeFailure>()),
    );
    expect(
      () => AuthoritativeTimeRemoteResponse.fromMap(extra),
      throwsA(isA<AuthoritativeTimeFailure>()),
    );
  });

  test('rejects non-integer wire values', () {
    for (final response in [
      validResponse(protocol: 1.0),
      validResponse(received: 1_785_686_400_000.0),
      validResponse(sent: '1785686400002'),
      validResponse(maxAge: 900_000.0),
    ]) {
      expect(
        () => AuthoritativeTimeRemoteResponse.fromMap(response),
        throwsA(isA<AuthoritativeTimeFailure>()),
      );
    }
  });

  test('rejects regressive backend timestamps', () {
    expect(
      () => AuthoritativeTimeRemoteResponse.fromMap(
        validResponse(received: 2000, sent: 1999),
      ),
      throwsA(isA<AuthoritativeTimeFailure>()),
    );
  });

  test('rejects invalid max age and blank request id', () {
    expect(
      () => AuthoritativeTimeRemoteResponse.fromMap(
        validResponse(maxAge: 899_999),
      ),
      throwsA(isA<AuthoritativeTimeFailure>()),
    );
    expect(
      () => AuthoritativeTimeRemoteResponse.fromMap(
        validResponse(requestId: '   '),
      ),
      throwsA(isA<AuthoritativeTimeFailure>()),
    );
    expect(
      () => AuthoritativeTimeRemoteResponse.fromMap(
        validResponse(requestId: 'not-a-uuid'),
      ),
      throwsA(isA<AuthoritativeTimeFailure>()),
    );
  });
}
