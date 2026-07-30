// Copyright 2024 GCM Health. All rights reserved.
//
// Tests for GatewayHealthTimelineShadowObserver.
//
// 8 test declarations covering:
// - O1: comparison mapped and recorded once
// - O2: skipped mapped and recorded once
// - O3: failure mapped and recorded once
// - O4: gateway sync throw absorbed
// - O5: gateway async throw absorbed
// - O6: mapper throw absorbed
// - O7: zero rethrow
// - O8: zero second attempt
// - O9: callbacks complete normally after failure
// - O10: zero original outcome retained in fake

import 'package:flutter_test/flutter_test.dart';

import 'package:canil_gcm/features/health/data/shadow/health_timeline_shadow_models.dart';
import 'package:canil_gcm/features/health/data/shadow/telemetry/health_timeline_shadow_telemetry_contract.dart';
import 'package:canil_gcm/features/health/data/shadow/telemetry/health_timeline_shadow_telemetry_gateway.dart';
import 'package:canil_gcm/features/health/data/shadow/telemetry/gateway_health_timeline_shadow_observer.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Fakes
// ─────────────────────────────────────────────────────────────────────────────

class FakeHealthTimelineShadowTelemetryGateway
    implements HealthTimelineShadowTelemetryGateway {
  final List<HealthTimelineShadowTelemetryRecord> _records = [];
  Object? _errorToThrow;

  List<HealthTimelineShadowTelemetryRecord> get records =>
      List.unmodifiable(_records);

  void clear() {
    _records.clear();
    _errorToThrow = null;
  }

  void whenError(Object error) {
    _errorToThrow = error;
  }

  @override
  Future<void> record(HealthTimelineShadowTelemetryRecord record) async {
    if (_errorToThrow != null) {
      throw _errorToThrow as Object;
    }
    _records.add(record);
  }
}

final class _SyncThrowGateway implements HealthTimelineShadowTelemetryGateway {
  int calls = 0;

  @override
  Future<void> record(HealthTimelineShadowTelemetryRecord record) {
    calls++;
    throw StateError('sync gateway failure');
  }
}

final class _AsyncThrowGateway implements HealthTimelineShadowTelemetryGateway {
  int calls = 0;

  @override
  Future<void> record(HealthTimelineShadowTelemetryRecord record) {
    calls++;
    return Future<void>.error(StateError('async gateway failure'));
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Tests
// ─────────────────────────────────────────────────────────────────────────────

void main() {
  late FakeHealthTimelineShadowTelemetryGateway fakeGateway;
  late GatewayHealthTimelineShadowObserver observer;

  setUp(() {
    fakeGateway = FakeHealthTimelineShadowTelemetryGateway();
    observer = GatewayHealthTimelineShadowObserver(gateway: fakeGateway);
  });

  group('O1 — comparison mapped and recorded once', () {
    test(
      'onComparison maps to record and calls gateway exactly once',
      () async {
        observer.onComparison(
          const HealthTimelineShadowComparison(
            primaryCount: 5,
            shadowCount: 3,
            matchedCount: 2,
            missingCount: 1,
            extraCount: 0,
            uncorrelatedPrimaryCount: 1,
            uncorrelatedShadowCount: 1,
            ambiguousPrimaryCount: 0,
            ambiguousShadowCount: 0,
            orderingMismatch: false,
            shadowLatencyMs: 150,
          ),
        );
        await pumpEventQueue();
        expect(fakeGateway.records.length, 1);
        expect(
          fakeGateway.records.single,
          isA<HealthTimelineShadowTelemetryComparison>(),
        );
      },
    );
  });

  group('O2 — skipped mapped and recorded once', () {
    test('onSkipped maps to record and calls gateway exactly once', () async {
      observer.onSkipped(
        const HealthTimelineShadowSkipped(
          skipKind: HealthTimelineShadowSkipKind.notFirstPage,
        ),
      );
      await pumpEventQueue();
      expect(fakeGateway.records.length, 1);
      expect(
        fakeGateway.records.single,
        isA<HealthTimelineShadowTelemetrySkipped>(),
      );
    });
  });

  group('O3 — failure mapped and recorded once', () {
    test('onFailure maps to record and calls gateway exactly once', () async {
      observer.onFailure(
        const HealthTimelineShadowFailure(
          failureKind: HealthTimelineShadowFailureKind.comparatorFailure,
          shadowLatencyMs: 6000,
        ),
      );
      await pumpEventQueue();
      expect(fakeGateway.records.length, 1);
      expect(
        fakeGateway.records.single,
        isA<HealthTimelineShadowTelemetryFailure>(),
      );
    });
  });

  group('O4 — gateway sync throw absorbed', () {
    test(
      'O7 — O8 — O9: sync throw is absorbed, no rethrow, zero retry',
      () async {
        final syncGateway = _SyncThrowGateway();
        final syncObserver = GatewayHealthTimelineShadowObserver(
          gateway: syncGateway,
        );

        syncObserver.onSkipped(
          const HealthTimelineShadowSkipped(
            skipKind: HealthTimelineShadowSkipKind.unsupportedTypes,
          ),
        );
        await pumpEventQueue();

        expect(syncGateway.calls, equals(1));
      },
    );
  });

  group('O5 — gateway async throw absorbed', () {
    test('async throw is absorbed and completes normally', () async {
      final asyncGateway = _AsyncThrowGateway();
      final asyncObserver = GatewayHealthTimelineShadowObserver(
        gateway: asyncGateway,
      );

      asyncObserver.onSkipped(
        const HealthTimelineShadowSkipped(
          skipKind: HealthTimelineShadowSkipKind.unsupportedProfessional,
        ),
      );
      await pumpEventQueue();

      expect(asyncGateway.calls, equals(1));
    });
  });

  group('O6 — mapper throw absorbed', () {
    test('mapper throw is absorbed and gateway is not called', () async {
      int mapperCallCount = 0;
      final observerWithFailingMapper = GatewayHealthTimelineShadowObserver(
        gateway: fakeGateway,
        mapper: (outcome) {
          mapperCallCount++;
          throw StateError('mapper failure');
        },
      );

      observerWithFailingMapper.onSkipped(
        const HealthTimelineShadowSkipped(
          skipKind: HealthTimelineShadowSkipKind.notFirstPage,
        ),
      );

      await pumpEventQueue();

      expect(mapperCallCount, equals(1));
      expect(fakeGateway.records, isEmpty);
    });
  });

  group('O9 — callbacks complete normally after failure', () {
    test('subsequent callbacks work after a failure', () async {
      fakeGateway.whenError(Exception('first error'));
      observer.onSkipped(
        const HealthTimelineShadowSkipped(
          skipKind: HealthTimelineShadowSkipKind.notFirstPage,
        ),
      );
      await pumpEventQueue();

      fakeGateway.clear();
      observer.onSkipped(
        const HealthTimelineShadowSkipped(
          skipKind: HealthTimelineShadowSkipKind.unsupportedTypes,
        ),
      );
      await pumpEventQueue();

      expect(fakeGateway.records.length, 1);
    });
  });

  group('O10 — zero original outcome retained', () {
    test('original outcome is not retained after mapping', () {
      observer.onComparison(
        const HealthTimelineShadowComparison(
          primaryCount: 5,
          shadowCount: 3,
          matchedCount: 2,
          missingCount: 1,
          extraCount: 0,
          uncorrelatedPrimaryCount: 1,
          uncorrelatedShadowCount: 1,
          ambiguousPrimaryCount: 0,
          ambiguousShadowCount: 0,
          orderingMismatch: false,
          shadowLatencyMs: 100,
        ),
      );

      // Only the mapped record is retained
      expect(fakeGateway.records.length, 1);
      expect(
        fakeGateway.records.single,
        isA<HealthTimelineShadowTelemetryComparison>(),
      );
      // The original HealthTimelineShadowComparison is not in the records
      expect(
        fakeGateway.records.single,
        isNot(isA<HealthTimelineShadowComparison>()),
      );
    });
  });
}
