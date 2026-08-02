import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:canil_gcm/core/services/authoritative_time/authoritative_time_models.dart';
import 'package:canil_gcm/core/services/authoritative_time/firebase_functions_authoritative_time_gateway.dart';

Map<String, dynamic> validResponse() => {
  'protocol_version': 1,
  'request_id': '00000000-0000-4000-8000-000000000001',
  'request_received_at_utc_ms': 1_785_686_400_000,
  'server_sent_at_utc_ms': 1_785_686_400_002,
  'max_age_ms': 900_000,
};

void main() {
  test('uses exact callable, region and protocol request', () async {
    String? functionName;
    Map<String, dynamic>? payload;
    final gateway = FirebaseFunctionsAuthoritativeTimeGateway(
      invoker: (name, data) async {
        functionName = name;
        payload = data;
        return validResponse();
      },
    );

    final response = await gateway.fetchAuthoritativeTime();

    expect(
      FirebaseFunctionsAuthoritativeTimeGateway.region,
      'southamerica-east1',
    );
    expect(functionName, 'systemAuthoritativeTimeNow');
    expect(payload, const {'protocol_version': 1});
    expect(response, isA<AuthoritativeTimeRemoteResponse>());
    expect(response.requestId, '00000000-0000-4000-8000-000000000001');
  });

  test('maps unauthenticated without leaking Firebase exception', () async {
    final gateway = FirebaseFunctionsAuthoritativeTimeGateway(
      invoker: (_, _) async => throw FirebaseFunctionsException(
        code: 'unauthenticated',
        message: 'raw backend message',
      ),
    );

    await expectLater(
      gateway.fetchAuthoritativeTime(),
      throwsA(
        isA<AuthoritativeTimeFailure>().having(
          (failure) => failure.code,
          'code',
          AuthoritativeTimeFailureCode.unauthenticated,
        ),
      ),
    );
  });

  test('maps unavailable and deadline errors', () async {
    for (final code in ['unavailable', 'deadline-exceeded']) {
      final gateway = FirebaseFunctionsAuthoritativeTimeGateway(
        invoker: (_, _) async =>
            throw FirebaseFunctionsException(code: code, message: 'raw'),
      );
      await expectLater(
        gateway.fetchAuthoritativeTime(),
        throwsA(
          isA<AuthoritativeTimeFailure>().having(
            (failure) => failure.code,
            'code',
            AuthoritativeTimeFailureCode.unavailable,
          ),
        ),
      );
    }
  });

  test(
    'rejects non-map and malformed payload without local fallback',
    () async {
      final nonMap = FirebaseFunctionsAuthoritativeTimeGateway(
        invoker: (_, _) async => 'invalid',
      );
      final malformed = FirebaseFunctionsAuthoritativeTimeGateway(
        invoker: (_, _) async => {'protocol_version': 1},
      );

      await expectLater(
        nonMap.fetchAuthoritativeTime(),
        throwsA(isA<AuthoritativeTimeFailure>()),
      );
      await expectLater(
        malformed.fetchAuthoritativeTime(),
        throwsA(isA<AuthoritativeTimeFailure>()),
      );
    },
  );
}
