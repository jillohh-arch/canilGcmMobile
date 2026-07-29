import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:canil_gcm/features/health/data/config/health_timeline_flag_provider.dart';
import 'package:canil_gcm/features/health/data/config/health_timeline_mode.dart';
import 'package:canil_gcm/features/health/data/config/health_timeline_remote_config_client.dart';
import 'package:canil_gcm/features/health/data/config/production_health_timeline_flag_provider_factory.dart';

final class _FakeClient implements HealthTimelineRemoteConfigClient {
  final List<String> calls = [];
  Duration? lastFetchTimeout;
  Duration? lastMinimumFetchInterval;
  HealthTimelineRemoteValue? returnValue;
  Completer<void>? fetchBlocker;
  bool throwOnFetchAndActivate = false;

  @override
  Future<void> ensureInitialized() async {
    calls.add('ensureInitialized');
  }

  @override
  Future<void> setConfigSettings({
    required Duration fetchTimeout,
    required Duration minimumFetchInterval,
  }) async {
    calls.add('setConfigSettings');
    lastFetchTimeout = fetchTimeout;
    lastMinimumFetchInterval = minimumFetchInterval;
  }

  @override
  Future<void> setDefaults(Map<String, Object> defaults) async {
    calls.add('setDefaults');
  }

  @override
  Future<bool> fetchAndActivate() async {
    calls.add('fetchAndActivate');
    if (fetchBlocker != null) {
      await fetchBlocker!.future;
    }
    if (throwOnFetchAndActivate) {
      throw Exception('fetchAndActivate_failed');
    }
    return true;
  }

  @override
  HealthTimelineRemoteValue readValue(String key) {
    calls.add('readValue:$key');
    return returnValue ??
        const HealthTimelineRemoteValue(
          value: 'legacyOnly',
          source: HealthTimelineRemoteValueSource.defaultValue,
        );
  }
}

/// Fake que lança diretamente em resolveMode para testar o catch do guard.
final class _ThrowingHealthTimelineFlagProvider
    implements HealthTimelineFlagProvider {
  const _ThrowingHealthTimelineFlagProvider();

  @override
  Future<HealthTimelineModeResolution> resolveMode() async {
    throw StateError('delegate failure');
  }
}

void main() {
  group('ProductionHealthTimelineFlagProviderFactory', () {
    test('F1 — defaults produtivos encaminham fetchTimeout de 1 minuto '
        'e minimumFetchInterval de 1 hora', () async {
      final client = _FakeClient()
        ..returnValue = const HealthTimelineRemoteValue(
          value: 'legacyOnly',
          source: HealthTimelineRemoteValueSource.remoteValue,
        );

      final provider = ProductionHealthTimelineFlagProviderFactory.forClient(
        client: client,
      );

      await provider.resolveMode();

      expect(client.lastFetchTimeout, equals(const Duration(minutes: 1)));
      expect(client.lastMinimumFetchInterval, equals(const Duration(hours: 1)));
    });

    test('F2 — durations customizadas são encaminhadas exatamente', () async {
      final client = _FakeClient()
        ..returnValue = const HealthTimelineRemoteValue(
          value: 'legacyOnly',
          source: HealthTimelineRemoteValueSource.remoteValue,
        );

      final provider = ProductionHealthTimelineFlagProviderFactory.forClient(
        client: client,
        fetchTimeout: const Duration(seconds: 30),
        minimumFetchInterval: const Duration(minutes: 15),
      );

      await provider.resolveMode();

      expect(client.lastFetchTimeout, equals(const Duration(seconds: 30)));
      expect(
        client.lastMinimumFetchInterval,
        equals(const Duration(minutes: 15)),
      );
    });

    test(
      'F3 — remote legacyOnly/configured atravessa o guard inalterado',
      () async {
        final client = _FakeClient()
          ..returnValue = const HealthTimelineRemoteValue(
            value: 'legacyOnly',
            source: HealthTimelineRemoteValueSource.remoteValue,
          );

        final provider = ProductionHealthTimelineFlagProviderFactory.forClient(
          client: client,
        );

        final res = await provider.resolveMode();

        expect(res.mode, equals(HealthTimelineMode.legacyOnly));
        expect(res.kind, equals(HealthTimelineModeResolutionKind.configured));
      },
    );

    test('F4 — defaultValue retorna legacyOnly/missingDefault', () async {
      final client = _FakeClient()
        ..returnValue = const HealthTimelineRemoteValue(
          value: 'legacyOnly',
          source: HealthTimelineRemoteValueSource.defaultValue,
        );

      final provider = ProductionHealthTimelineFlagProviderFactory.forClient(
        client: client,
      );

      final res = await provider.resolveMode();

      expect(res.mode, equals(HealthTimelineMode.legacyOnly));
      expect(res.kind, equals(HealthTimelineModeResolutionKind.missingDefault));
    });

    test('F5 — staticValue retorna legacyOnly/missingDefault', () async {
      final client = _FakeClient()
        ..returnValue = const HealthTimelineRemoteValue(
          value: 'legacyOnly',
          source: HealthTimelineRemoteValueSource.staticValue,
        );

      final provider = ProductionHealthTimelineFlagProviderFactory.forClient(
        client: client,
      );

      final res = await provider.resolveMode();

      expect(res.mode, equals(HealthTimelineMode.legacyOnly));
      expect(res.kind, equals(HealthTimelineModeResolutionKind.missingDefault));
    });

    test(
      'F6 — remote shadowCompare é bloqueado para legacyOnly/invalidDefault',
      () async {
        final client = _FakeClient()
          ..returnValue = const HealthTimelineRemoteValue(
            value: 'shadowCompare',
            source: HealthTimelineRemoteValueSource.remoteValue,
          );

        final provider = ProductionHealthTimelineFlagProviderFactory.forClient(
          client: client,
        );

        final res = await provider.resolveMode();

        expect(res.mode, equals(HealthTimelineMode.legacyOnly));
        expect(
          res.kind,
          equals(HealthTimelineModeResolutionKind.invalidDefault),
        );
      },
    );

    test(
      'F7 — remote canonicalPrimary é bloqueado para legacyOnly/invalidDefault',
      () async {
        final client = _FakeClient()
          ..returnValue = const HealthTimelineRemoteValue(
            value: 'canonicalPrimary',
            source: HealthTimelineRemoteValueSource.remoteValue,
          );

        final provider = ProductionHealthTimelineFlagProviderFactory.forClient(
          client: client,
        );

        final res = await provider.resolveMode();

        expect(res.mode, equals(HealthTimelineMode.legacyOnly));
        expect(
          res.kind,
          equals(HealthTimelineModeResolutionKind.invalidDefault),
        );
      },
    );

    test(
      'F8 — remote wire value desconhecido permanece legacyOnly/invalidDefault',
      () async {
        final client = _FakeClient()
          ..returnValue = const HealthTimelineRemoteValue(
            value: 'unknownFutureMode',
            source: HealthTimelineRemoteValueSource.remoteValue,
          );

        final provider = ProductionHealthTimelineFlagProviderFactory.forClient(
          client: client,
        );

        final res = await provider.resolveMode();

        expect(res.mode, equals(HealthTimelineMode.legacyOnly));
        expect(
          res.kind,
          equals(HealthTimelineModeResolutionKind.invalidDefault),
        );
      },
    );

    test('F9 — refresh background ainda é iniciado mesmo quando '
        'shadowCompare é bloqueado pelo guard', () async {
      final fetchBlocker = Completer<void>();
      final client = _FakeClient()
        ..fetchBlocker = fetchBlocker
        ..returnValue = const HealthTimelineRemoteValue(
          value: 'shadowCompare',
          source: HealthTimelineRemoteValueSource.remoteValue,
        );

      final provider = ProductionHealthTimelineFlagProviderFactory.forClient(
        client: client,
      );

      final res = await provider.resolveMode();

      // Guard bloqueou shadowCompare.
      expect(res.mode, equals(HealthTimelineMode.legacyOnly));
      expect(res.kind, equals(HealthTimelineModeResolutionKind.invalidDefault));

      // fetchAndActivate foi chamado (refresh background iniciado).
      expect(
        client.calls.where((c) => c == 'fetchAndActivate').length,
        equals(1),
      );

      // Liberar o blocker para não deixar future pendente no teste.
      fetchBlocker.complete();
    });

    test(
      'F10 — delegate exception retorna legacyOnly/missingDefault',
      () async {
        final provider =
            ProductionHealthTimelineFlagProviderFactory.withLegacyOnlyLock(
              delegate: const _ThrowingHealthTimelineFlagProvider(),
            );

        final resolution = await provider.resolveMode();

        expect(resolution.mode, equals(HealthTimelineMode.legacyOnly));
        expect(
          resolution.kind,
          equals(HealthTimelineModeResolutionKind.missingDefault),
        );
      },
    );
  });
}
