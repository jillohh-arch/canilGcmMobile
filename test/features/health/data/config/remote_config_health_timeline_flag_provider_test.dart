import 'dart:async';

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
  bool throwOnFetchAsTimeout = false;

  /// Completer que bloqueia o fetchAndActivate até ser completado.
  Completer<void>? fetchBlocker;

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
    if (fetchBlocker != null) {
      await fetchBlocker!.future;
    }
    if (fetchDelay > Duration.zero) {
      await Future<void>.delayed(fetchDelay);
    }
    if (throwOnFetchAsTimeout) {
      throw TimeoutException('fetch exceeded timeout');
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
    // ─────────────────────────────────────────────────────────────────────────
    // C1: resolveMode retorna antes de fetch pendente concluir
    // ─────────────────────────────────────────────────────────────────────────
    test('C1 — resolveMode retorna antes de fetch pendente concluir', () async {
      final client = FakeHealthTimelineRemoteConfigClient();
      final fetchBlocker = Completer<void>();
      client.fetchBlocker = fetchBlocker;

      final provider = RemoteConfigHealthTimelineFlagProvider(
        client: client,
        fetchTimeout: const Duration(seconds: 3),
        minimumFetchInterval: const Duration(hours: 1),
      );

      // Inicia resolve — fetch fica bloqueado no completer
      final future = provider.resolveMode();

      // Microtask checkpoint: deixa o body async do resolveMode rodar
      // até o ponto de _startRefreshIfNeeded(), que chama fetchAndActivate
      await Future<void>.delayed(Duration.zero);

      // readValue já foi chamado
      expect(client.calls, contains('readValue:health_timeline_mode'));

      // fetchAndActivate foi chamado (background, mas síncrono no body async)
      expect(client.calls.contains('fetchAndActivate'), isTrue);

      // Prova de cache-first: read ANTES de fetch
      expect(
        client.calls.indexOf('readValue:health_timeline_mode'),
        lessThan(client.calls.indexOf('fetchAndActivate')),
      );

      // Libera o fetch e aguarda
      fetchBlocker.complete();
      await future;

      // Resolução veio do readValue feito antes do fetch
      final res = await provider.resolveMode();
      expect(res.mode, equals(HealthTimelineMode.legacyOnly));
    });

    // ─────────────────────────────────────────────────────────────────────────
    // C2: ordem cache-first — read ocorre antes de fetch
    // ─────────────────────────────────────────────────────────────────────────
    test('C2 — ordem cache-first: read ocorre antes de fetch', () async {
      final client = FakeHealthTimelineRemoteConfigClient();
      final fetchBlocker = Completer<void>();
      client.fetchBlocker = fetchBlocker;

      final provider = RemoteConfigHealthTimelineFlagProvider(
        client: client,
        fetchTimeout: const Duration(seconds: 3),
        minimumFetchInterval: const Duration(hours: 1),
      );

      await provider.resolveMode();

      // A ordem correta: prepare → read → fetch
      // readValue DEVE aparecer ANTES de fetchAndActivate
      expect(
        client.calls.indexOf('readValue:health_timeline_mode'),
        lessThan(client.calls.indexOf('fetchAndActivate')),
      );

      fetchBlocker.complete();
    });

    // ─────────────────────────────────────────────────────────────────────────
    // C3: valor novo ativado só aparece na próxima resolução
    // ─────────────────────────────────────────────────────────────────────────
    test('C3 — valor novo ativado só aparece na próxima resolução', () async {
      final client = FakeHealthTimelineRemoteConfigClient()
        ..returnValue = const HealthTimelineRemoteValue(
          value: 'legacyOnly',
          source: HealthTimelineRemoteValueSource.remoteValue,
        );

      final fetchBlocker = Completer<void>();
      client.fetchBlocker = fetchBlocker;

      final provider = RemoteConfigHealthTimelineFlagProvider(
        client: client,
        fetchTimeout: const Duration(seconds: 3),
        minimumFetchInterval: const Duration(hours: 1),
      );

      // Primeira resolução: legacyOnly
      final res1 = await provider.resolveMode();
      expect(res1.mode, equals(HealthTimelineMode.legacyOnly));
      expect(res1.kind, equals(HealthTimelineModeResolutionKind.configured));

      fetchBlocker.complete();

      // Simula que o fetch ativou um novo valor no cache
      // Na próxima resolução, o readValue verá o novo valor
      client.returnValue = const HealthTimelineRemoteValue(
        value: 'shadowCompare',
        source: HealthTimelineRemoteValueSource.remoteValue,
      );

      // Segunda resolução: shadowCompare
      final res2 = await provider.resolveMode();
      expect(res2.mode, equals(HealthTimelineMode.shadowCompare));
      expect(res2.kind, equals(HealthTimelineModeResolutionKind.configured));
    });

    // ─────────────────────────────────────────────────────────────────────────
    // C4: duas resoluções simultâneas iniciam apenas um fetch
    // ─────────────────────────────────────────────────────────────────────────
    test('C4 — duas resoluções simultâneas iniciam apenas um fetch', () async {
      final client = FakeHealthTimelineRemoteConfigClient()
        ..returnValue = const HealthTimelineRemoteValue(
          value: 'legacyOnly',
          source: HealthTimelineRemoteValueSource.remoteValue,
        );

      final fetchBlocker = Completer<void>();
      client.fetchBlocker = fetchBlocker;

      final provider = RemoteConfigHealthTimelineFlagProvider(
        client: client,
        fetchTimeout: const Duration(seconds: 3),
        minimumFetchInterval: const Duration(hours: 1),
      );

      // Duas resoluções concorrentes — body async ainda não rodou
      final res1Future = provider.resolveMode();
      final res2Future = provider.resolveMode();

      // Microtask checkpoint: deixa o body async das duas rodar
      await Future<void>.delayed(Duration.zero);

      // Ambas as chamadas passaram pelo readValue
      expect(
        client.calls.where((c) => c == 'readValue:health_timeline_mode').length,
        equals(2),
      );

      // Mas fetchAndActivate foi chamado apenas uma vez (dedupe)
      expect(
        client.calls.where((c) => c == 'fetchAndActivate').length,
        equals(1),
      );

      // Libera o fetch
      fetchBlocker.complete();

      // Ambas as resoluções completam
      final res1 = await res1Future;
      final res2 = await res2Future;

      expect(res1.mode, equals(HealthTimelineMode.legacyOnly));
      expect(res2.mode, equals(HealthTimelineMode.legacyOnly));
    });

    // ─────────────────────────────────────────────────────────────────────────
    // C5: após fetch concluir, nova resolução pode iniciar novo refresh
    // ─────────────────────────────────────────────────────────────────────────
    test(
      'C5 — após fetch concluir, nova resolução pode iniciar novo refresh',
      () async {
        final client = FakeHealthTimelineRemoteConfigClient()
          ..returnValue = const HealthTimelineRemoteValue(
            value: 'legacyOnly',
            source: HealthTimelineRemoteValueSource.remoteValue,
          );

        final fetchBlocker1 = Completer<void>();
        client.fetchBlocker = fetchBlocker1;

        final provider = RemoteConfigHealthTimelineFlagProvider(
          client: client,
          fetchTimeout: const Duration(seconds: 3),
          minimumFetchInterval: const Duration(hours: 1),
        );

        // Primeira resolução: fetch fica bloqueado
        await provider.resolveMode();
        expect(
          client.calls.where((c) => c == 'fetchAndActivate').length,
          equals(1),
        );
        fetchBlocker1.complete();

        // Segunda resolução: fetchBlocker2 bloqueia novo fetch
        final fetchBlocker2 = Completer<void>();
        client.fetchBlocker = fetchBlocker2;

        await provider.resolveMode();

        // Dois fetchAndActivate totais — o segundo fetch foi possível porque
        // o primeiro já tinha concluído e _refreshInFlight era null
        expect(
          client.calls.where((c) => c == 'fetchAndActivate').length,
          equals(2),
        );

        fetchBlocker2.complete();
      },
    );

    // ─────────────────────────────────────────────────────────────────────────
    // C6: fetch exception não produz unhandled async error
    // ─────────────────────────────────────────────────────────────────────────
    test('C6 — fetch exception não produz unhandled async error', () async {
      final client = FakeHealthTimelineRemoteConfigClient()
        ..throwOnFetchAndActivate = true
        ..returnValue = const HealthTimelineRemoteValue(
          value: 'legacyOnly',
          source: HealthTimelineRemoteValueSource.remoteValue,
        );

      final provider = RemoteConfigHealthTimelineFlagProvider(
        client: client,
        fetchTimeout: const Duration(seconds: 3),
        minimumFetchInterval: const Duration(hours: 1),
      );

      // Deve completar sem exceptions
      final res = await provider.resolveMode();
      expect(res.mode, equals(HealthTimelineMode.legacyOnly));
      expect(res.kind, equals(HealthTimelineModeResolutionKind.configured));
    });

    // ─────────────────────────────────────────────────────────────────────────
    // C7: fetch TimeoutException não produz unhandled async error
    // ─────────────────────────────────────────────────────────────────────────
    test(
      'C7 — fetch TimeoutException não produz unhandled async error',
      () async {
        final client = FakeHealthTimelineRemoteConfigClient()
          ..throwOnFetchAsTimeout = true
          ..returnValue = const HealthTimelineRemoteValue(
            value: 'shadowCompare',
            source: HealthTimelineRemoteValueSource.remoteValue,
          );

        final provider = RemoteConfigHealthTimelineFlagProvider(
          client: client,
          fetchTimeout: const Duration(milliseconds: 50),
          minimumFetchInterval: const Duration(hours: 1),
        );

        // Deve completar sem exceptions — a TimeoutException é capturada
        final res = await provider.resolveMode();
        expect(res.mode, equals(HealthTimelineMode.shadowCompare));
        expect(res.kind, equals(HealthTimelineModeResolutionKind.configured));
      },
    );

    // ─────────────────────────────────────────────────────────────────────────
    // C8: falha de readValue não inicia refresh
    // ─────────────────────────────────────────────────────────────────────────
    test('C8 — falha de readValue não inicia refresh', () async {
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

      // readValue É chamado (mas lança), a exceção é capturada internamente.
      // fetchAndActivate NÃO é chamado porque o refresh é iniciado APÓS a leitura.
      expect(client.calls, contains('readValue:health_timeline_mode'));
      expect(client.calls.contains('fetchAndActivate'), isFalse);
    });

    // ─────────────────────────────────────────────────────────────────────────
    // C9: defaultValue retorna legacyOnly imediatamente
    // ─────────────────────────────────────────────────────────────────────────
    test('C9 — defaultValue retorna legacyOnly imediatamente', () async {
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

    // ─────────────────────────────────────────────────────────────────────────
    // C10: remote shadowCompare cacheado retorna shadowCompare imediatamente
    // ─────────────────────────────────────────────────────────────────────────
    test(
      'C10 — remote shadowCompare cacheado retorna shadowCompare imediatamente',
      () async {
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
      },
    );

    // ─────────────────────────────────────────────────────────────────────────
    // C11: dedupe rastreia o future fonte real, não o wrapper de timeout
    // ─────────────────────────────────────────────────────────────────────────
    test('C11 — dedupe rastreia o future fonte, não wrapper — fetch lento com '
        'Completer: duas chamadas durante block = 1 fetch, depois block completa '
        '-> terceira chamada = 2º fetch', () async {
      final client = FakeHealthTimelineRemoteConfigClient()
        ..returnValue = const HealthTimelineRemoteValue(
          value: 'legacyOnly',
          source: HealthTimelineRemoteValueSource.remoteValue,
        );

      final fetchBlocker = Completer<void>();
      client.fetchBlocker = fetchBlocker;

      final provider = RemoteConfigHealthTimelineFlagProvider(
        client: client,
        fetchTimeout: const Duration(seconds: 3),
        minimumFetchInterval: const Duration(hours: 1),
      );

      // Duas resoluções concorrentes — ambas encontram _refreshInFlight == null
      final res1Future = provider.resolveMode();
      final res2Future = provider.resolveMode();

      // Microtask checkpoint: deixa o body async das duas rodar
      await Future<void>.delayed(Duration.zero);

      // fetchAndActivate foi chamado APENAS uma vez (dedupe ativo)
      expect(
        client.calls.where((c) => c == 'fetchAndActivate').length,
        equals(1),
      );

      // Completa o blocker — primeiro fetch termina
      fetchBlocker.complete();

      // Aguarda as duas resoluções pendentes
      await res1Future;
      await res2Future;

      // Terceira resolução — _refreshInFlight já é null, novo fetch iniciado
      final fetchBlocker2 = Completer<void>();
      client.fetchBlocker = fetchBlocker2;

      await provider.resolveMode();

      // Segundo fetchAndActivate foi chamado
      expect(
        client.calls.where((c) => c == 'fetchAndActivate').length,
        equals(2),
      );

      fetchBlocker2.complete();
    });

    // ═══════════════════════════════════════════════════════════════════════════
    // TESTES PRESERVADOS
    // ═══════════════════════════════════════════════════════════════════════════

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

    test(
      'ordem cache-first: ensure -> settings -> defaults -> read -> fetch',
      () async {
        final client = FakeHealthTimelineRemoteConfigClient();
        final fetchBlocker = Completer<void>();
        client.fetchBlocker = fetchBlocker;

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
            'readValue:health_timeline_mode',
            'fetchAndActivate',
          ]),
        );

        // Confirma: read ANTES de fetch
        expect(
          client.calls.indexOf('readValue:health_timeline_mode'),
          lessThan(client.calls.indexOf('fetchAndActivate')),
        );

        fetchBlocker.complete();
      },
    );

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

    test(
      'fetch exception com cache remoto válido — resolução vem do read antes '
      'do fetch, fetch error é ignorado',
      () async {
        final client = FakeHealthTimelineRemoteConfigClient()
          ..throwOnFetchAndActivate = true
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

        // Resolução vem do valor local LIDO ANTES do fetch
        expect(res.mode, equals(HealthTimelineMode.shadowCompare));
        expect(res.kind, equals(HealthTimelineModeResolutionKind.configured));
      },
    );

    test(
      'fetch TimeoutException com cache remoto válido — resolução vem do read '
      'antes do fetch',
      () async {
        final client = FakeHealthTimelineRemoteConfigClient()
          ..throwOnFetchAsTimeout = true
          ..returnValue = const HealthTimelineRemoteValue(
            value: 'canonicalPrimary',
            source: HealthTimelineRemoteValueSource.remoteValue,
          );
        final provider = RemoteConfigHealthTimelineFlagProvider(
          client: client,
          fetchTimeout: const Duration(milliseconds: 50),
          minimumFetchInterval: const Duration(hours: 1),
        );

        final res = await provider.resolveMode();

        // Resolução vem do valor local LIDO ANTES do fetch
        expect(res.mode, equals(HealthTimelineMode.canonicalPrimary));
        expect(res.kind, equals(HealthTimelineModeResolutionKind.configured));
      },
    );

    test('fetch retorna false com valor remoto — resolução vem do read antes '
        'do fetch', () async {
      final client = FakeHealthTimelineRemoteConfigClient()
        ..fetchResult = false
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

      // Resolução vem do valor local LIDO ANTES do fetch
      expect(res.mode, equals(HealthTimelineMode.legacyOnly));
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
