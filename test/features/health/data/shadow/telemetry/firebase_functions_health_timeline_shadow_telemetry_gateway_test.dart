// Copyright 2024 GCM Health. All rights reserved.
//
// Tests for FirebaseFunctionsHealthTimelineShadowTelemetryGateway.
//
// 15 test declarations covering:
// - Callable name exact
// - Payload sent exactly once
// - Payload is record.toJson()
// - Zero manual data wrapper
// - accepted true completes
// - null response fails
// - empty map fails
// - accepted missing fails
// - accepted false fails
// - accepted string fails
// - callable error propagates
// - zero retry after error
// - comparison maintains 13 keys
// - skipped maintains 3 keys
// - failure maintains 4 keys
// - zero prohibited fields

import 'package:flutter_test/flutter_test.dart';

import 'package:canil_gcm/features/health/data/shadow/health_timeline_shadow_models.dart';
import 'package:canil_gcm/features/health/data/shadow/telemetry/health_timeline_shadow_telemetry_callable_client.dart';
import 'package:canil_gcm/features/health/data/shadow/telemetry/health_timeline_shadow_telemetry_contract.dart';
import 'package:canil_gcm/features/health/data/shadow/telemetry/firebase_functions_health_timeline_shadow_telemetry_gateway.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Fake callable client that captures calls and returns controlled responses.
// ─────────────────────────────────────────────────────────────────────────────

class FakeHealthTimelineShadowTelemetryCallableClient
    implements HealthTimelineShadowTelemetryCallableClient {
  final List<Map<String, Object>> _calls = [];
  Object? _responseToReturn;
  Object? _errorToThrow;

  List<Map<String, Object>> get calls => List.unmodifiable(_calls);

  void clear() {
    _calls.clear();
    _responseToReturn = null;
    _errorToThrow = null;
  }

  void whenResponse(Object? response) {
    _responseToReturn = response;
    _errorToThrow = null;
  }

  void whenError(Exception error) {
    _errorToThrow = error;
    _responseToReturn = null;
  }

  @override
  Future<Object?> call(Map<String, Object> payload) async {
    _calls.add(Map<String, Object>.from(payload));
    if (_errorToThrow != null) {
      throw _errorToThrow!;
    }
    return _responseToReturn;
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Tests
// ─────────────────────────────────────────────────────────────────────────────

void main() {
  late FakeHealthTimelineShadowTelemetryCallableClient fakeClient;
  late FirebaseFunctionsHealthTimelineShadowTelemetryGateway gateway;

  setUp(() {
    fakeClient = FakeHealthTimelineShadowTelemetryCallableClient();
    gateway = FirebaseFunctionsHealthTimelineShadowTelemetryGateway(
      client: fakeClient,
    );
  });

  group('G1 — exposes and uses the exact production callable contract', () {
    test('exposes exact production region, callable name, and timeout', () {
      expect(
        FirebaseFunctionsHealthTimelineShadowTelemetryGateway.region,
        'southamerica-east1',
      );
      expect(
        FirebaseFunctionsHealthTimelineShadowTelemetryGateway.callableName,
        'healthTimelineRecordShadowTelemetry',
      );
      expect(
        FirebaseFunctionsHealthTimelineShadowTelemetryGateway.timeout,
        const Duration(seconds: 10),
      );
    });
  });

  group('G2 — one call', () {
    test('calls the callable exactly once per record', () async {
      fakeClient.whenResponse({'accepted': true});
      await gateway.record(
        const HealthTimelineShadowTelemetrySkipped(
          skipKind: HealthTimelineShadowSkipKind.unsupportedTypes,
        ),
      );
      expect(fakeClient.calls.length, 1);
    });

    test('G12 — zero retry after error', () async {
      fakeClient.whenError(Exception('network error'));
      await gateway
          .record(
            const HealthTimelineShadowTelemetrySkipped(
              skipKind: HealthTimelineShadowSkipKind.unsupportedTypes,
            ),
          )
          .catchError((_) {});
      expect(fakeClient.calls.length, 1);
    });
  });

  group('G3 — payload', () {
    test('G13 — comparison payload maintains 13 keys', () {
      fakeClient.whenResponse({'accepted': true});
      gateway.record(
        const HealthTimelineShadowTelemetryComparison(
          primaryCountBucket: HealthTimelineShadowCountBucket.twoToFive,
          shadowCountBucket: HealthTimelineShadowCountBucket.one,
          matchedCountBucket: HealthTimelineShadowCountBucket.zero,
          missingCountBucket: HealthTimelineShadowCountBucket.twoToFive,
          extraCountBucket: HealthTimelineShadowCountBucket.twoToFive,
          uncorrelatedPrimaryCountBucket: HealthTimelineShadowCountBucket.zero,
          uncorrelatedShadowCountBucket: HealthTimelineShadowCountBucket.zero,
          ambiguousPrimaryCountBucket: HealthTimelineShadowCountBucket.zero,
          ambiguousShadowCountBucket: HealthTimelineShadowCountBucket.zero,
          orderingMismatch: false,
          latencyBucket: HealthTimelineShadowLatencyBucket.atLeast5000,
        ),
      );
      final payload = fakeClient.calls.single;
      expect(payload.keys.length, 13);
      expect(payload['schema_version'], 1);
      expect(payload['outcome_type'], 'comparison');
    });

    test('G14 — skipped payload maintains 3 keys', () {
      fakeClient.whenResponse({'accepted': true});
      gateway.record(
        const HealthTimelineShadowTelemetrySkipped(
          skipKind: HealthTimelineShadowSkipKind.unsupportedProfessional,
        ),
      );
      final payload = fakeClient.calls.single;
      expect(payload.keys.length, 3);
      expect(payload['schema_version'], 1);
      expect(payload['outcome_type'], 'skipped');
      expect(payload['skip_kind'], 'unsupported_professional');
    });

    test('G15 — failure payload maintains 4 keys', () {
      fakeClient.whenResponse({'accepted': true});
      gateway.record(
        const HealthTimelineShadowTelemetryFailure(
          failureKind: HealthTimelineShadowFailureKind.comparatorFailure,
          latencyBucket: HealthTimelineShadowLatencyBucket.atLeast5000,
        ),
      );
      final payload = fakeClient.calls.single;
      expect(payload.keys.length, 4);
      expect(payload['schema_version'], 1);
      expect(payload['outcome_type'], 'failure');
      expect(payload['failure_kind'], 'comparator_failure');
      expect(payload['latency_bucket'], 'gte_5000');
    });

    test('G16 — zero prohibited fields in comparison', () {
      fakeClient.whenResponse({'accepted': true});
      const prohibitedKeys = [
        'dog_id',
        'dogId',
        'uid',
        'email',
        'ra',
        'case_id',
        'caseId',
        'event_id',
        'eventId',
        'document_id',
        'documentId',
        'source_id',
        'sourceId',
        'session_id',
        'sessionId',
        'device_id',
        'deviceId',
        'installation_id',
        'installationId',
        'app_version',
        'build_number',
        'platform',
        'environment',
        'recorded_at',
        'recordedAt',
      ];
      gateway.record(
        const HealthTimelineShadowTelemetryComparison(
          primaryCountBucket: HealthTimelineShadowCountBucket.twoToFive,
          shadowCountBucket: HealthTimelineShadowCountBucket.one,
          matchedCountBucket: HealthTimelineShadowCountBucket.zero,
          missingCountBucket: HealthTimelineShadowCountBucket.zero,
          extraCountBucket: HealthTimelineShadowCountBucket.zero,
          uncorrelatedPrimaryCountBucket: HealthTimelineShadowCountBucket.zero,
          uncorrelatedShadowCountBucket: HealthTimelineShadowCountBucket.zero,
          ambiguousPrimaryCountBucket: HealthTimelineShadowCountBucket.zero,
          ambiguousShadowCountBucket: HealthTimelineShadowCountBucket.zero,
          orderingMismatch: false,
          latencyBucket: HealthTimelineShadowLatencyBucket.lessThan100,
        ),
      );
      final payload = fakeClient.calls.single;
      for (final key in prohibitedKeys) {
        expect(
          payload.containsKey(key),
          isFalse,
          reason: 'prohibited key: $key',
        );
      }
    });
  });

  group('G4 — no manual wrapper', () {
    test('payload is record.toJson() directly', () {
      fakeClient.whenResponse({'accepted': true});
      const record = HealthTimelineShadowTelemetrySkipped(
        skipKind: HealthTimelineShadowSkipKind.notFirstPage,
      );
      final expectedJson = record.toJson();
      gateway.record(record);
      expect(fakeClient.calls.single, equals(expectedJson));
    });
  });

  group('G5 — accepted true completes', () {
    test('accepted true completes without error', () {
      fakeClient.whenResponse({'accepted': true});
      expect(
        () => gateway.record(
          const HealthTimelineShadowTelemetrySkipped(
            skipKind: HealthTimelineShadowSkipKind.unsupportedTypes,
          ),
        ),
        returnsNormally,
      );
    });
  });

  group('G6 — null response fails', () {
    test('null response throws', () {
      fakeClient.whenResponse(null);
      expect(
        () => gateway.record(
          const HealthTimelineShadowTelemetrySkipped(
            skipKind: HealthTimelineShadowSkipKind.notFirstPage,
          ),
        ),
        throwsA(isA<Exception>()),
      );
    });
  });

  group('G7 — empty map fails', () {
    test('empty map throws', () {
      fakeClient.whenResponse(<String, Object>{});
      expect(
        () => gateway.record(
          const HealthTimelineShadowTelemetrySkipped(
            skipKind: HealthTimelineShadowSkipKind.notFirstPage,
          ),
        ),
        throwsA(isA<Exception>()),
      );
    });
  });

  group('G8 — accepted missing fails', () {
    test('missing accepted field throws', () {
      fakeClient.whenResponse({'something': 'else'});
      expect(
        () => gateway.record(
          const HealthTimelineShadowTelemetrySkipped(
            skipKind: HealthTimelineShadowSkipKind.unsupportedTypes,
          ),
        ),
        throwsA(isA<Exception>()),
      );
    });
  });

  group('G9 — accepted false fails', () {
    test('accepted false throws', () {
      fakeClient.whenResponse({'accepted': false});
      expect(
        () => gateway.record(
          const HealthTimelineShadowTelemetrySkipped(
            skipKind: HealthTimelineShadowSkipKind.notFirstPage,
          ),
        ),
        throwsA(isA<Exception>()),
      );
    });
  });

  group('G10 — accepted string fails', () {
    test('accepted string throws', () {
      fakeClient.whenResponse({'accepted': 'true'});
      expect(
        () => gateway.record(
          const HealthTimelineShadowTelemetrySkipped(
            skipKind: HealthTimelineShadowSkipKind.notFirstPage,
          ),
        ),
        throwsA(isA<Exception>()),
      );
    });
  });

  group('G11 — callable error propagates', () {
    test('callable exception propagates to caller', () async {
      fakeClient.whenError(Exception('cloud function error'));
      await expectLater(
        gateway.record(
          const HealthTimelineShadowTelemetrySkipped(
            skipKind: HealthTimelineShadowSkipKind.unsupportedTypes,
          ),
        ),
        throwsA(isA<Exception>()),
      );
    });
  });
}
