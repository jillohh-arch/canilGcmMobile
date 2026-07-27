import 'package:flutter_test/flutter_test.dart';
import 'package:canil_gcm/features/health/data/config/health_timeline_mode.dart';
import 'package:canil_gcm/features/health/data/config/health_timeline_remote_config_client.dart';
import 'package:canil_gcm/features/health/data/config/remote_config_health_timeline_flag_provider.dart';

final class FakeHealthTimelineRemoteConfigClient
    implements HealthTimelineRemoteConfigClient {
  final List<String> calls = [];
  Duration? lastFetchTimeout;
  Duration? lastMinimumFetchInterval;
  Map<String, Object>? lastDefaults;
  HealthTimelineRemoteValue? returnValue;
  bool fetchResult = true;

  bool throwOnEnsureInitialized = false;
  bool throwOnSetConfigSettings = false;
  bool throwOnSetDefaults = false;
  bool throwOnFetchAndActivate = false;
  bool throwOnReadValue = false;
  Duration fetchDelay = Duration.zero;

  @override
  Future<void> ensureInitialized() async {
    calls.add('ensureInitialized');
    if (throwOnEnsureInitialized) {
      throw Exception('ensureInitialized_failed');
    }
  }

  @override
  Future<void> setConfigSettings({
    required Duration fetchTimeout,
    required Duration minimumFetchInterval,
  }) async {
    calls.add('setConfigSettings');
    lastFetchTimeout = fetchTimeout;
    lastMinimumFetchInterval = minimumFetchInterval;
    if (throwOnSetConfigSettings) {
      throw Exception('setConfigSettings_failed');
    }
  }

  @override
  Future<void> setDefaults(Map<String, Object> defaults) async {
    calls.add('setDefaults');
    lastDefaults = defaults;
    if (throwOnSetDefaults) {
      throw Exception('setDefaults_failed');
    }
  }

  @override
  Future<bool> fetchAndActivate() async {
    calls.add('fetchAndActivate');
    if (fetchDelay > Duration.zero) {
      await Future<void>.delayed(fetchDelay);
    }
    if (throwOnFetchAndActivate) {
      throw Exception('fetchAndActivate_failed');
    }
    return fetchResult;
  }

  @override
  HealthTimelineRemoteValue readValue(String key) {
    calls.add('readValue:$key');
    if (throwOnReadValue) {
      throw Exception('readValue_failed');
    }
    return returnValue ??
        const HealthTimelineRemoteValue(
          value: 'legacyOnly',
          source: HealthTimelineRemoteValueSource.defaultValue,
        );
  }
}

void main() {
  group('RemoteConfigHealthTimelineFlagProvider', () {
    test('construtor valida argumentos de tempo', () {
      final client = FakeHealthTimelineRemoteConfigClient();
      expect(
        () => RemoteConfigHealthTimelineFlagProvider(
          client: client,
          fetchTimeout: Duration.zero,
          minimumFetchInterval: const Duration(hours: 1),
        ),
        throwsArgumentError,
      );
      expect(
        () => RemoteConfigHealthTimelineFlagProvider(
          client: client,
          fetchTimeout: const Duration(seconds: 3),
          minimumFetchInterval: const Duration(seconds: -1),
        ),
        throwsArgumentError,
      );
    });

    test('ordem ensure -> settings -> defaults -> fetch -> read', () async {
      final client = FakeHealthTimelineRemoteConfigClient();
      final provider = RemoteConfigHealthTimelineFlagProvider(
        client: client,
        fetchTimeout: const Duration(seconds: 3),
        minimumFetchInterval: const Duration(hours: 1),
      );

      await provider.resolveMode();

      expect(
        client.calls,
        equals([
          'ensureInitialized',
          'setConfigSettings',
          'setDefaults',
          'fetchAndActivate',
          'readValue:health_timeline_mode',
        ]),
      );
    });

    test('encaminhamento exato de fetchTimeout', () async {
      final client = FakeHealthTimelineRemoteConfigClient();
      final provider = RemoteConfigHealthTimelineFlagProvider(
        client: client,
        fetchTimeout: const Duration(seconds: 4),
        minimumFetchInterval: const Duration(minutes: 30),
      );

      await provider.resolveMode();

      expect(client.lastFetchTimeout, equals(const Duration(seconds: 4)));
    });

    test('encaminhamento exato de minimumFetchInterval', () async {
      final client = FakeHealthTimelineRemoteConfigClient();
      final provider = RemoteConfigHealthTimelineFlagProvider(
        client: client,
        fetchTimeout: const Duration(seconds: 3),
        minimumFetchInterval: const Duration(hours: 12),
      );

      await provider.resolveMode();

      expect(
        client.lastMinimumFetchInterval,
        equals(const Duration(hours: 12)),
      );
    });

    test(
      'default enviado com chave health_timeline_mode e valor legacyOnly',
      () async {
        final client = FakeHealthTimelineRemoteConfigClient();
        final provider = RemoteConfigHealthTimelineFlagProvider(
          client: client,
          fetchTimeout: const Duration(seconds: 3),
          minimumFetchInterval: const Duration(hours: 1),
        );

        await provider.resolveMode();

        expect(
          client.lastDefaults,
          equals({'health_timeline_mode': 'legacyOnly'}),
        );
      },
    );

    test('remote legacyOnly -> configured', () async {
      final client = FakeHealthTimelineRemoteConfigClient()
        ..returnValue = const HealthTimelineRemoteValue(
          value: 'legacyOnly',
          source: HealthTimelineRemoteValueSource.remoteValue,
        );
      final provider = RemoteConfigHealthTimelineFlagProvider(
        client: client,
        fetchTimeout: const Duration(seconds: 3),
        minimumFetchInterval: const Duration(hours: 1),
      );

      final res = await provider.resolveMode();

      expect(res.mode, equals(HealthTimelineMode.legacyOnly));
      expect(res.kind, equals(HealthTimelineModeResolutionKind.configured));
      expect(res.wasDefaulted, isFalse);
    });

    test('remote shadowCompare -> configured', () async {
      final client = FakeHealthTimelineRemoteConfigClient()
        ..returnValue = const HealthTimelineRemoteValue(
          value: 'shadowCompare',
          source: HealthTimelineRemoteValueSource.remoteValue,
        );
      final provider = RemoteConfigHealthTimelineFlagProvider(
        client: client,
        fetchTimeout: const Duration(seconds: 3),
        minimumFetchInterval: const Duration(hours: 1),
      );

      final res = await provider.resolveMode();

      expect(res.mode, equals(HealthTimelineMode.shadowCompare));
      expect(res.kind, equals(HealthTimelineModeResolutionKind.configured));
      expect(res.wasDefaulted, isFalse);
    });

    test('remote canonicalPrimary -> configured', () async {
      final client = FakeHealthTimelineRemoteConfigClient()
        ..returnValue = const HealthTimelineRemoteValue(
          value: 'canonicalPrimary',
          source: HealthTimelineRemoteValueSource.remoteValue,
        );
      final provider = RemoteConfigHealthTimelineFlagProvider(
        client: client,
        fetchTimeout: const Duration(seconds: 3),
        minimumFetchInterval: const Duration(hours: 1),
      );

      final res = await provider.resolveMode();

      expect(res.mode, equals(HealthTimelineMode.canonicalPrimary));
      expect(res.kind, equals(HealthTimelineModeResolutionKind.configured));
      expect(res.wasDefaulted, isFalse);
    });

    test('remote desconhecido -> legacyOnly + invalidDefault', () async {
      final client = FakeHealthTimelineRemoteConfigClient()
        ..returnValue = const HealthTimelineRemoteValue(
          value: 'UNKNOWN_VALUE',
          source: HealthTimelineRemoteValueSource.remoteValue,
        );
      final provider = RemoteConfigHealthTimelineFlagProvider(
        client: client,
        fetchTimeout: const Duration(seconds: 3),
        minimumFetchInterval: const Duration(hours: 1),
      );

      final res = await provider.resolveMode();

      expect(res.mode, equals(HealthTimelineMode.legacyOnly));
      expect(res.kind, equals(HealthTimelineModeResolutionKind.invalidDefault));
      expect(res.wasDefaulted, isTrue);
    });

    test('source default -> legacyOnly + missingDefault', () async {
      final client = FakeHealthTimelineRemoteConfigClient()
        ..returnValue = const HealthTimelineRemoteValue(
          value: 'legacyOnly',
          source: HealthTimelineRemoteValueSource.defaultValue,
        );
      final provider = RemoteConfigHealthTimelineFlagProvider(
        client: client,
        fetchTimeout: const Duration(seconds: 3),
        minimumFetchInterval: const Duration(hours: 1),
      );

      final res = await provider.resolveMode();

      expect(res.mode, equals(HealthTimelineMode.legacyOnly));
      expect(res.kind, equals(HealthTimelineModeResolutionKind.missingDefault));
      expect(res.wasDefaulted, isTrue);
    });

    test('source static -> legacyOnly + missingDefault', () async {
      final client = FakeHealthTimelineRemoteConfigClient()
        ..returnValue = const HealthTimelineRemoteValue(
          value: 'canonicalPrimary',
          source: HealthTimelineRemoteValueSource.staticValue,
        );
      final provider = RemoteConfigHealthTimelineFlagProvider(
        client: client,
        fetchTimeout: const Duration(seconds: 3),
        minimumFetchInterval: const Duration(hours: 1),
      );

      final res = await provider.resolveMode();

      expect(res.mode, equals(HealthTimelineMode.legacyOnly));
      expect(res.kind, equals(HealthTimelineModeResolutionKind.missingDefault));
      expect(res.wasDefaulted, isTrue);
    });

    test('fetch exception com cache remoto válido -> usa cache', () async {
      final client = FakeHealthTimelineRemoteConfigClient()
        ..throwOnFetchAndActivate = true
        ..returnValue = const HealthTimelineRemoteValue(
          value: 'canonicalPrimary',
          source: HealthTimelineRemoteValueSource.remoteValue,
        );
      final provider = RemoteConfigHealthTimelineFlagProvider(
        client: client,
        fetchTimeout: const Duration(seconds: 3),
        minimumFetchInterval: const Duration(hours: 1),
      );

      final res = await provider.resolveMode();

      expect(res.mode, equals(HealthTimelineMode.canonicalPrimary));
      expect(res.kind, equals(HealthTimelineModeResolutionKind.configured));
    });

    test('fetch timeout com cache remoto válido -> usa cache', () async {
      final client = FakeHealthTimelineRemoteConfigClient()
        ..fetchDelay = const Duration(milliseconds: 500)
        ..returnValue = const HealthTimelineRemoteValue(
          value: 'shadowCompare',
          source: HealthTimelineRemoteValueSource.remoteValue,
        );
      final provider = RemoteConfigHealthTimelineFlagProvider(
        client: client,
        fetchTimeout: const Duration(milliseconds: 50),
        minimumFetchInterval: const Duration(hours: 1),
      );

      final res = await provider.resolveMode();

      expect(res.mode, equals(HealthTimelineMode.shadowCompare));
      expect(res.kind, equals(HealthTimelineModeResolutionKind.configured));
    });

    test('fetch retorna false com valor remoto -> lê e usa valor', () async {
      final client = FakeHealthTimelineRemoteConfigClient()
        ..fetchResult = false
        ..returnValue = const HealthTimelineRemoteValue(
          value: 'canonicalPrimary',
          source: HealthTimelineRemoteValueSource.remoteValue,
        );
      final provider = RemoteConfigHealthTimelineFlagProvider(
        client: client,
        fetchTimeout: const Duration(seconds: 3),
        minimumFetchInterval: const Duration(hours: 1),
      );

      final res = await provider.resolveMode();

      expect(res.mode, equals(HealthTimelineMode.canonicalPrimary));
      expect(res.kind, equals(HealthTimelineModeResolutionKind.configured));
    });

    test('falha em ensureInitialized -> default seguro', () async {
      final client = FakeHealthTimelineRemoteConfigClient()
        ..throwOnEnsureInitialized = true;
      final provider = RemoteConfigHealthTimelineFlagProvider(
        client: client,
        fetchTimeout: const Duration(seconds: 3),
        minimumFetchInterval: const Duration(hours: 1),
      );

      final res = await provider.resolveMode();

      expect(res.mode, equals(HealthTimelineMode.legacyOnly));
      expect(res.kind, equals(HealthTimelineModeResolutionKind.missingDefault));
      expect(client.calls, equals(['ensureInitialized']));
    });

    test('falha em setConfigSettings -> default seguro', () async {
      final client = FakeHealthTimelineRemoteConfigClient()
        ..throwOnSetConfigSettings = true;
      final provider = RemoteConfigHealthTimelineFlagProvider(
        client: client,
        fetchTimeout: const Duration(seconds: 3),
        minimumFetchInterval: const Duration(hours: 1),
      );

      final res = await provider.resolveMode();

      expect(res.mode, equals(HealthTimelineMode.legacyOnly));
      expect(res.kind, equals(HealthTimelineModeResolutionKind.missingDefault));
      expect(client.calls, equals(['ensureInitialized', 'setConfigSettings']));
    });

    test('falha em setDefaults -> default seguro', () async {
      final client = FakeHealthTimelineRemoteConfigClient()
        ..throwOnSetDefaults = true;
      final provider = RemoteConfigHealthTimelineFlagProvider(
        client: client,
        fetchTimeout: const Duration(seconds: 3),
        minimumFetchInterval: const Duration(hours: 1),
      );

      final res = await provider.resolveMode();

      expect(res.mode, equals(HealthTimelineMode.legacyOnly));
      expect(res.kind, equals(HealthTimelineModeResolutionKind.missingDefault));
      expect(
        client.calls,
        equals(['ensureInitialized', 'setConfigSettings', 'setDefaults']),
      );
    });

    test('falha em readValue -> default seguro', () async {
      final client = FakeHealthTimelineRemoteConfigClient()
        ..throwOnReadValue = true;
      final provider = RemoteConfigHealthTimelineFlagProvider(
        client: client,
        fetchTimeout: const Duration(seconds: 3),
        minimumFetchInterval: const Duration(hours: 1),
      );

      final res = await provider.resolveMode();

      expect(res.mode, equals(HealthTimelineMode.legacyOnly));
      expect(res.kind, equals(HealthTimelineModeResolutionKind.missingDefault));
    });
  });
}
