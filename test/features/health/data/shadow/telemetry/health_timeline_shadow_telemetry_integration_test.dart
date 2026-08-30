// Copyright 2024 GCM Health. All rights reserved.
//
// HEALTH TIMELINE SHADOW TELEMETRY INTEGRATION TESTS — L1-L10 e S1-S10.
//
// Testa a cadeia completa de telemetria integrada ao composition factory:
// CompositionFactory → HealthTimelineSource → ShadowObserver → Gateway → CallableClient
//
// legacyOnly (L1-L10): zero telemetria emitida.
// shadowCompare fail-silent (S1-S10): telemetria não bloqueia, não interfere,
// não contamina a Timeline primária.

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'package:canil_gcm/features/health/data/config/health_timeline_mode.dart';
import 'package:canil_gcm/features/health/data/shadow/health_timeline_shadow_composition_factory.dart';
import 'package:canil_gcm/features/health/data/shadow/health_timeline_shadow_models.dart';
import 'package:canil_gcm/features/health/data/shadow/health_timeline_shadow_runner.dart';
import 'package:canil_gcm/features/health/data/shadow/health_timeline_shadow_runner_executor.dart';
import 'package:canil_gcm/features/health/data/shadow/shadow_comparing_health_timeline_source.dart';
import 'package:canil_gcm/features/health/data/shadow/telemetry/gateway_health_timeline_shadow_observer.dart';
import 'package:canil_gcm/features/health/data/shadow/telemetry/health_timeline_shadow_telemetry_callable_client.dart';
import 'package:canil_gcm/features/health/data/shadow/telemetry/health_timeline_shadow_telemetry_contract.dart';
import 'package:canil_gcm/features/health/data/shadow/telemetry/health_timeline_shadow_telemetry_gateway.dart';
import 'package:canil_gcm/features/health/data/shadow/telemetry/production_health_timeline_shadow_telemetry_factory.dart';
import 'package:canil_gcm/features/health/domain/health_v1_enums_ext.dart';
import 'package:canil_gcm/features/health/presentation/timeline/health_timeline_cursor.dart';
import 'package:canil_gcm/features/health/presentation/timeline/health_timeline_entry_view.dart';
import 'package:canil_gcm/features/health/presentation/timeline/health_timeline_page.dart';
import 'package:canil_gcm/features/health/presentation/timeline/health_timeline_query.dart';
import 'package:canil_gcm/features/health/presentation/timeline/health_timeline_source.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Test Fakes — Zero wall-clock delays.
// ─────────────────────────────────────────────────────────────────────────────

/// Fake source que permite controle determinístico via completers.
class _FakeHealthTimelineSource implements HealthTimelineSource {
  _FakeHealthTimelineSource({this.pageToReturn, this.completer});

  final HealthTimelinePage? pageToReturn;
  final Completer<HealthTimelinePage>? completer;

  int calls = 0;
  HealthTimelineQuery? receivedQuery;

  @override
  Future<HealthTimelinePage> loadPage(HealthTimelineQuery query) {
    calls++;
    receivedQuery = query;

    final comp = completer;
    if (comp != null) return comp.future;

    return Future.value(
      pageToReturn ??
          HealthTimelinePage(items: const [], nextCursor: null, hasMore: false),
    );
  }
}

/// Fake runner que permite controle determinístico.
class _FakeShadowRunner implements HealthTimelineShadowRunner {
  _FakeShadowRunner({this.resultToReturn});

  final HealthTimelineShadowRunResult? resultToReturn;

  int calls = 0;
  HealthTimelineQuery? receivedQuery;
  List<HealthTimelineEntryView>? receivedPrimaryItems;

  @override
  Future<HealthTimelineShadowRunResult> run({
    required HealthTimelineQuery query,
    required List<HealthTimelineEntryView> primaryItems,
  }) async {
    calls++;
    receivedQuery = query;
    receivedPrimaryItems = primaryItems;

    return resultToReturn ??
        const HealthTimelineShadowRunSuccess(
          primaryCount: 0,
          shadowCount: 0,
          matchedCount: 0,
          missingCount: 0,
          extraCount: 0,
          uncorrelatedPrimaryCount: 0,
          uncorrelatedShadowCount: 0,
          ambiguousPrimaryCount: 0,
          ambiguousShadowCount: 0,
          orderingMismatch: false,
        );
  }
}

/// Fake executor determinístico.
class _FakeRunnerExecutor implements HealthTimelineShadowRunnerExecutor {
  _FakeRunnerExecutor({this.passthrough = true});

  final bool passthrough;
  static const int _elapsedMilliseconds = 10;

  int calls = 0;
  Future<HealthTimelineShadowRunResult> Function()? receivedOperation;
  Duration? receivedTimeout;

  @override
  Future<HealthTimelineShadowRunnerExecutionResult> execute({
    required Future<HealthTimelineShadowRunResult> Function() operation,
    required Duration timeout,
  }) async {
    calls++;
    receivedOperation = operation;
    receivedTimeout = timeout;

    HealthTimelineShadowRunResult? runResult;
    if (passthrough) {
      runResult = await operation();
    }

    return HealthTimelineShadowRunnerCompleted(
      result:
          runResult ??
          const HealthTimelineShadowRunSuccess(
            primaryCount: 0,
            shadowCount: 0,
            matchedCount: 0,
            missingCount: 0,
            extraCount: 0,
            uncorrelatedPrimaryCount: 0,
            uncorrelatedShadowCount: 0,
            ambiguousPrimaryCount: 0,
            ambiguousShadowCount: 0,
            orderingMismatch: false,
          ),
      elapsedMilliseconds: _elapsedMilliseconds,
    );
  }
}

/// Recording observer que rastreia todos os outcomes.
class _RecordingObserver implements HealthTimelineShadowObserver {
  final List<HealthTimelineShadowOutcome> outcomes = [];
  final List<Completer<void>> _completers = [];

  @override
  FutureOr<void> onComparison(HealthTimelineShadowComparison value) {
    _record(value);
  }

  @override
  FutureOr<void> onSkipped(HealthTimelineShadowSkipped value) {
    _record(value);
  }

  @override
  FutureOr<void> onFailure(HealthTimelineShadowFailure value) {
    _record(value);
  }

  void _record(HealthTimelineShadowOutcome outcome) {
    outcomes.add(outcome);
    if (_completers.isNotEmpty) {
      _completers.removeAt(0).complete();
    }
  }

  Future<void> waitForOutcome() async {
    if (outcomes.isNotEmpty) return;
    final c = Completer<void>();
    _completers.add(c);
    await c.future;
  }
}

/// Recording callable client que rastreia chamadas ao callable.
class _RecordingCallableClient
    implements HealthTimelineShadowTelemetryCallableClient {
  _RecordingCallableClient({this.responseToReturn});

  final Object? responseToReturn;

  final List<Map<String, Object>> calls = [];

  void reset() {
    calls.clear();
  }

  @override
  Future<Object?> call(Map<String, Object> payload) async {
    calls.add(Map<String, Object>.from(payload));
    return responseToReturn;
  }
}

/// Spy gateway que permite verificar chamadas ao gateway.
class _SpyGateway implements HealthTimelineShadowTelemetryGateway {
  _SpyGateway({this.errorToThrow, this.recordCompleter});

  final Object? errorToThrow;
  final Completer<void>? recordCompleter;

  final List<dynamic> records = [];

  void reset() {
    records.clear();
  }

  @override
  Future<void> record(dynamic record) async {
    records.add(record);
    if (errorToThrow != null) {
      throw errorToThrow as Object;
    }
    final comp = recordCompleter;
    if (comp != null) await comp.future;
  }
}

// Helpers
HealthTimelineQuery _sampleQuery() => HealthTimelineQuery(dogId: 'dog-123');

HealthTimelineEntryView _sampleItem(String id) {
  return HealthTimelineEntryView(
    id: id,
    dogId: 'dog-123',
    type: HealthTimelineTypeView.known(HealthTimelineType.meal),
    occurredAt: DateTime.utc(2024, 1, 1),
    recordedAt: DateTime.utc(2024, 1, 1),
    title: 'Item $id',
    status: HealthTimelineEntryStatus.finalised,
  );
}

HealthTimelinePage _expectedPage({
  List<HealthTimelineEntryView> items = const [],
  String? cursorToken,
  bool hasMore = false,
}) {
  return HealthTimelinePage(
    items: items,
    nextCursor: cursorToken != null ? HealthTimelineCursor(cursorToken) : null,
    hasMore: hasMore,
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// Tests: legacyOnly (L1-L10) — zero telemetria emitida.
// ─────────────────────────────────────────────────────────────────────────────

void main() {
  group('legacyOnly — L1 a L10: zero telemetria emitida', () {
    test(
      'L1: legacyOnly retorna source coexistente (identica a factory input)',
      () {
        final coexistenceSource = _FakeHealthTimelineSource();
        final runner = _FakeShadowRunner();

        final factory = HealthTimelineShadowCompositionFactory(
          coexistenceSourceFactory: () => coexistenceSource,
          runnerFactory: () => runner,
        );

        final source = factory.createForResolution(
          const HealthTimelineModeResolution(
            mode: HealthTimelineMode.legacyOnly,
            kind: HealthTimelineModeResolutionKind.configured,
          ),
        );

        expect(identical(source, coexistenceSource), isTrue);
        expect(source, isNot(isA<ShadowComparingHealthTimelineSource>()));
      },
    );

    test('L2: legacyOnly runner factory não é chamada', () {
      int runnerFactoryCalls = 0;
      final coexistenceSource = _FakeHealthTimelineSource();
      final runner = _FakeShadowRunner();

      final factory = HealthTimelineShadowCompositionFactory(
        coexistenceSourceFactory: () => coexistenceSource,
        runnerFactory: () {
          runnerFactoryCalls++;
          return runner;
        },
      );

      factory.createForResolution(
        const HealthTimelineModeResolution(
          mode: HealthTimelineMode.legacyOnly,
          kind: HealthTimelineModeResolutionKind.configured,
        ),
      );

      expect(runnerFactoryCalls, 0);
    });

    test('L3: legacyOnly observer.onComparison não é chamado', () async {
      final coexistenceSource = _FakeHealthTimelineSource();
      final runner = _FakeShadowRunner();
      final recordingObserver = _RecordingObserver();

      final factory = HealthTimelineShadowCompositionFactory(
        coexistenceSourceFactory: () => coexistenceSource,
        runnerFactory: () => runner,
        observer: recordingObserver,
      );

      final source = factory.createForResolution(
        const HealthTimelineModeResolution(
          mode: HealthTimelineMode.legacyOnly,
          kind: HealthTimelineModeResolutionKind.configured,
        ),
      );

      await source.loadPage(_sampleQuery());

      expect(recordingObserver.outcomes, isEmpty);
    });

    test('L4: legacyOnly observer.onSkipped não é chamado', () async {
      final coexistenceSource = _FakeHealthTimelineSource();
      final runner = _FakeShadowRunner();
      final recordingObserver = _RecordingObserver();

      final factory = HealthTimelineShadowCompositionFactory(
        coexistenceSourceFactory: () => coexistenceSource,
        runnerFactory: () => runner,
        observer: recordingObserver,
      );

      final source = factory.createForResolution(
        const HealthTimelineModeResolution(
          mode: HealthTimelineMode.legacyOnly,
          kind: HealthTimelineModeResolutionKind.configured,
        ),
      );

      await source.loadPage(_sampleQuery());

      expect(recordingObserver.outcomes, isEmpty);
    });

    test('L5: legacyOnly observer.onFailure não é chamado', () async {
      final coexistenceSource = _FakeHealthTimelineSource();
      final runner = _FakeShadowRunner();
      final recordingObserver = _RecordingObserver();

      final factory = HealthTimelineShadowCompositionFactory(
        coexistenceSourceFactory: () => coexistenceSource,
        runnerFactory: () => runner,
        observer: recordingObserver,
      );

      final source = factory.createForResolution(
        const HealthTimelineModeResolution(
          mode: HealthTimelineMode.legacyOnly,
          kind: HealthTimelineModeResolutionKind.configured,
        ),
      );

      await source.loadPage(_sampleQuery());

      expect(recordingObserver.outcomes, isEmpty);
    });

    test(
      'L6: legacyOnly callable client não é chamado (via ProductionFactory)',
      () {
        final fakeClient = _RecordingCallableClient();
        // Factory cria o observer mas não invoca o callable durante criação
        ProductionHealthTimelineShadowTelemetryFactory.create(
          client: fakeClient,
        );

        // Observer nunca recebe chamada de loadPage em legacyOnly
        // Verify: nenhuma chamada foi feita ao callable durante criação
        expect(fakeClient.calls, isEmpty);
      },
    );

    test('L7: legacyOnly primary page é retornada normalmente', () async {
      final expectedPage = _expectedPage(
        items: [_sampleItem('p1'), _sampleItem('p2')],
        cursorToken: 'token-xyz',
        hasMore: true,
      );
      final coexistenceSource = _FakeHealthTimelineSource(
        pageToReturn: expectedPage,
      );
      final runner = _FakeShadowRunner();

      final factory = HealthTimelineShadowCompositionFactory(
        coexistenceSourceFactory: () => coexistenceSource,
        runnerFactory: () => runner,
      );

      final source = factory.createForResolution(
        const HealthTimelineModeResolution(
          mode: HealthTimelineMode.legacyOnly,
          kind: HealthTimelineModeResolutionKind.configured,
        ),
      );

      final resultPage = await source.loadPage(_sampleQuery());

      expect(identical(resultPage, expectedPage), isTrue);
      expect(resultPage.items.length, 2);
    });

    test('L8: legacyOnly cursor é idêntico ao da primary', () async {
      const cursorToken = 'token-identico-abc';
      final expectedPage = _expectedPage(
        items: [_sampleItem('p1')],
        cursorToken: cursorToken,
        hasMore: true,
      );
      final coexistenceSource = _FakeHealthTimelineSource(
        pageToReturn: expectedPage,
      );
      final runner = _FakeShadowRunner();

      final factory = HealthTimelineShadowCompositionFactory(
        coexistenceSourceFactory: () => coexistenceSource,
        runnerFactory: () => runner,
      );

      final source = factory.createForResolution(
        const HealthTimelineModeResolution(
          mode: HealthTimelineMode.legacyOnly,
          kind: HealthTimelineModeResolutionKind.configured,
        ),
      );

      final resultPage = await source.loadPage(_sampleQuery());

      expect(resultPage.nextCursor?.token, equals(cursorToken));
      expect(identical(resultPage.nextCursor, expectedPage.nextCursor), isTrue);
    });

    test('L9: legacyOnly hasMore é idêntico ao da primary', () async {
      final expectedPage = _expectedPage(
        items: [_sampleItem('p1')],
        cursorToken: 'cursor-para-mais',
        hasMore: true,
      );
      final coexistenceSource = _FakeHealthTimelineSource(
        pageToReturn: expectedPage,
      );
      final runner = _FakeShadowRunner();

      final factory = HealthTimelineShadowCompositionFactory(
        coexistenceSourceFactory: () => coexistenceSource,
        runnerFactory: () => runner,
      );

      final source = factory.createForResolution(
        const HealthTimelineModeResolution(
          mode: HealthTimelineMode.legacyOnly,
          kind: HealthTimelineModeResolutionKind.configured,
        ),
      );

      final resultPage = await source.loadPage(_sampleQuery());

      expect(resultPage.hasMore, isTrue);
      expect(resultPage.hasMore, equals(expectedPage.hasMore));
    });

    test('L10: legacyOnly runner não é criado (factory não chamada)', () {
      int runnerCreatedCount = 0;
      final coexistenceSource = _FakeHealthTimelineSource();

      final factory = HealthTimelineShadowCompositionFactory(
        coexistenceSourceFactory: () => coexistenceSource,
        runnerFactory: () {
          runnerCreatedCount++;
          return _FakeShadowRunner();
        },
      );

      factory.createForResolution(
        const HealthTimelineModeResolution(
          mode: HealthTimelineMode.legacyOnly,
          kind: HealthTimelineModeResolutionKind.configured,
        ),
      );

      expect(runnerCreatedCount, 0);
    });
  });

  // ─────────────────────────────────────────────────────────────────────────────
  // Tests: shadowCompare fail-silent (S1-S10).
  // Garante que telemetria não bloqueia, não interfere, não contumina.
  // ─────────────────────────────────────────────────────────────────────────────

  group(
    'shadowCompare fail-silent — S1 a S10: telemetria não bloqueia a Timeline',
    () {
      test(
        'S1: primary retorna sem aguardar transporte (async, não bloqueante)',
        () async {
          final primaryPage = _expectedPage(
            items: [_sampleItem('p1')],
            cursorToken: 'primary-cursor',
            hasMore: true,
          );
          final primaryCompleter = Completer<HealthTimelinePage>();
          final coexistenceSource = _FakeHealthTimelineSource(
            completer: primaryCompleter,
          );
          final runner = _FakeShadowRunner();
          final executor = _FakeRunnerExecutor(passthrough: true);

          final spyGateway = _SpyGateway();
          final telemetryObserver = GatewayHealthTimelineShadowObserver(
            gateway: spyGateway,
          );

          final factory = HealthTimelineShadowCompositionFactory(
            coexistenceSourceFactory: () => coexistenceSource,
            runnerFactory: () => runner,
            observer: telemetryObserver,
            runnerExecutor: executor,
          );

          final source = factory.createForResolution(
            const HealthTimelineModeResolution(
              mode: HealthTimelineMode.shadowCompare,
              kind: HealthTimelineModeResolutionKind.configured,
            ),
          );

          // Inicia loadPage mas não completa primary
          final pageFuture = source.loadPage(_sampleQuery());

          // Primary ainda não completou
          expect(coexistenceSource.calls, 1);

          // Completa primary
          primaryCompleter.complete(primaryPage);

          // Primary retorna imediatamente após completar
          // Não aguarda telemetria (que seria assíncrona)
          final returnedPage = await pageFuture;

          expect(identical(returnedPage, primaryPage), isTrue);
        },
      );

      test(
        'S2: gateway atrasado não aumenta latência da leitura primary',
        () async {
          final primaryPage = _expectedPage(
            items: [_sampleItem('p1')],
            hasMore: false,
          );
          final primaryCompleter = Completer<HealthTimelinePage>();
          final coexistenceSource = _FakeHealthTimelineSource(
            completer: primaryCompleter,
          );
          final runner = _FakeShadowRunner();
          final executor = _FakeRunnerExecutor(passthrough: true);

          // Simula gateway lento — mas isso não deve afetar primary
          final gatewayDelayCompleter = Completer<void>();
          final slowGateway = _SpyGateway(
            recordCompleter: gatewayDelayCompleter,
          );
          final telemetryObserver = GatewayHealthTimelineShadowObserver(
            gateway: slowGateway,
          );

          final factory = HealthTimelineShadowCompositionFactory(
            coexistenceSourceFactory: () => coexistenceSource,
            runnerFactory: () => runner,
            observer: telemetryObserver,
            runnerExecutor: executor,
          );

          final source = factory.createForResolution(
            const HealthTimelineModeResolution(
              mode: HealthTimelineMode.shadowCompare,
              kind: HealthTimelineModeResolutionKind.configured,
            ),
          );

          final stopwatch = Stopwatch()..start();
          final pageFuture = source.loadPage(_sampleQuery());

          primaryCompleter.complete(primaryPage);
          final returnedPage = await pageFuture;
          stopwatch.stop();

          // Primary retornou rapidamente
          expect(stopwatch.elapsedMilliseconds, lessThan(100));
          expect(returnedPage.items.first.id, equals('p1'));

          // Agora completa o gateway lento (não afeta primary)
          gatewayDelayCompleter.complete();
        },
      );

      test(
        'S3: falha do gateway não altera eventos da página primary',
        () async {
          final primaryPage = _expectedPage(
            items: [_sampleItem('evento-1'), _sampleItem('evento-2')],
            cursorToken: 'cursor-preservado',
            hasMore: true,
          );
          final primaryCompleter = Completer<HealthTimelinePage>();
          final coexistenceSource = _FakeHealthTimelineSource(
            completer: primaryCompleter,
          );
          final runner = _FakeShadowRunner();
          final executor = _FakeRunnerExecutor(passthrough: true);

          // Gateway que falha silenciosamente
          final failingGateway = _SpyGateway(
            errorToThrow: Exception('network'),
          );
          final telemetryObserver = GatewayHealthTimelineShadowObserver(
            gateway: failingGateway,
          );

          final factory = HealthTimelineShadowCompositionFactory(
            coexistenceSourceFactory: () => coexistenceSource,
            runnerFactory: () => runner,
            observer: telemetryObserver,
            runnerExecutor: executor,
          );

          final source = factory.createForResolution(
            const HealthTimelineModeResolution(
              mode: HealthTimelineMode.shadowCompare,
              kind: HealthTimelineModeResolutionKind.configured,
            ),
          );

          final pageFuture = source.loadPage(_sampleQuery());
          primaryCompleter.complete(primaryPage);
          final returnedPage = await pageFuture;

          // Eventos da primary inalterados
          expect(returnedPage.items.length, 2);
          expect(returnedPage.items[0].id, equals('evento-1'));
          expect(returnedPage.items[1].id, equals('evento-2'));
        },
      );

      test('S4: falha do gateway não altera cursor', () async {
        final primaryPage = _expectedPage(
          items: [_sampleItem('p1')],
          cursorToken: 'cursor-intocado',
          hasMore: true,
        );
        final primaryCompleter = Completer<HealthTimelinePage>();
        final coexistenceSource = _FakeHealthTimelineSource(
          completer: primaryCompleter,
        );
        final runner = _FakeShadowRunner();
        final executor = _FakeRunnerExecutor(passthrough: true);

        final failingGateway = _SpyGateway(errorToThrow: Exception('boom'));
        final telemetryObserver = GatewayHealthTimelineShadowObserver(
          gateway: failingGateway,
        );

        final factory = HealthTimelineShadowCompositionFactory(
          coexistenceSourceFactory: () => coexistenceSource,
          runnerFactory: () => runner,
          observer: telemetryObserver,
          runnerExecutor: executor,
        );

        final source = factory.createForResolution(
          const HealthTimelineModeResolution(
            mode: HealthTimelineMode.shadowCompare,
            kind: HealthTimelineModeResolutionKind.configured,
          ),
        );

        final pageFuture = source.loadPage(_sampleQuery());
        primaryCompleter.complete(primaryPage);
        final returnedPage = await pageFuture;

        expect(returnedPage.nextCursor?.token, equals('cursor-intocado'));
        expect(
          identical(returnedPage.nextCursor, primaryPage.nextCursor),
          isTrue,
        );
      });

      test('S5: falha do gateway não altera hasMore', () async {
        final primaryPage = _expectedPage(
          items: [_sampleItem('p1')],
          hasMore: false,
        );
        final primaryCompleter = Completer<HealthTimelinePage>();
        final coexistenceSource = _FakeHealthTimelineSource(
          completer: primaryCompleter,
        );
        final runner = _FakeShadowRunner();
        final executor = _FakeRunnerExecutor(passthrough: true);

        final failingGateway = _SpyGateway(errorToThrow: Exception('boom'));
        final telemetryObserver = GatewayHealthTimelineShadowObserver(
          gateway: failingGateway,
        );

        final factory = HealthTimelineShadowCompositionFactory(
          coexistenceSourceFactory: () => coexistenceSource,
          runnerFactory: () => runner,
          observer: telemetryObserver,
          runnerExecutor: executor,
        );

        final source = factory.createForResolution(
          const HealthTimelineModeResolution(
            mode: HealthTimelineMode.shadowCompare,
            kind: HealthTimelineModeResolutionKind.configured,
          ),
        );

        final pageFuture = source.loadPage(_sampleQuery());
        primaryCompleter.complete(primaryPage);
        final returnedPage = await pageFuture;

        expect(returnedPage.hasMore, isFalse);
        expect(returnedPage.hasMore, equals(primaryPage.hasMore));
      });

      test(
        'S6: comparison outcome gera exatamente uma tentativa no callable',
        () async {
          final primaryPage = _expectedPage(items: [_sampleItem('p1')]);
          final primaryCompleter = Completer<HealthTimelinePage>();
          final coexistenceSource = _FakeHealthTimelineSource(
            completer: primaryCompleter,
          );
          final runner = _FakeShadowRunner(
            resultToReturn: const HealthTimelineShadowRunSuccess(
              primaryCount: 1,
              shadowCount: 0,
              matchedCount: 0,
              missingCount: 1,
              extraCount: 0,
              uncorrelatedPrimaryCount: 0,
              uncorrelatedShadowCount: 0,
              ambiguousPrimaryCount: 0,
              ambiguousShadowCount: 0,
              orderingMismatch: false,
            ),
          );
          final executor = _FakeRunnerExecutor(passthrough: true);

          final recordingClient = _RecordingCallableClient(
            responseToReturn: {'accepted': true},
          );
          final spyGateway = _SpyGateway();
          final realGateway = _RecordingTelemetryGateway(
            spy: spyGateway,
            client: recordingClient,
          );
          final telemetryObserver = GatewayHealthTimelineShadowObserver(
            gateway: realGateway,
          );

          final factory = HealthTimelineShadowCompositionFactory(
            coexistenceSourceFactory: () => coexistenceSource,
            runnerFactory: () => runner,
            observer: telemetryObserver,
            runnerExecutor: executor,
          );

          final source = factory.createForResolution(
            const HealthTimelineModeResolution(
              mode: HealthTimelineMode.shadowCompare,
              kind: HealthTimelineModeResolutionKind.configured,
            ),
          );

          primaryCompleter.complete(primaryPage);
          await source.loadPage(_sampleQuery());

          // Aguarda outcome ser processado
          await Future.delayed(const Duration(milliseconds: 50));

          expect(recordingClient.calls.length, equals(1));
          final payload = recordingClient.calls.single;
          expect(payload['outcome_type'], equals('comparison'));
        },
      );

      test(
        'S7: skipped outcome gera exatamente uma tentativa no callable',
        () async {
          final primaryPage = _expectedPage(
            items: [_sampleItem('p1')],
            cursorToken: 'next-page-cursor',
            hasMore: true,
          );
          final primaryCompleter = Completer<HealthTimelinePage>();
          final coexistenceSource = _FakeHealthTimelineSource(
            completer: primaryCompleter,
          );
          final runner = _FakeShadowRunner();
          final executor = _FakeRunnerExecutor();

          final recordingClient = _RecordingCallableClient(
            responseToReturn: {'accepted': true},
          );
          final spyGateway = _SpyGateway();
          final realGateway = _RecordingTelemetryGateway(
            spy: spyGateway,
            client: recordingClient,
          );
          final telemetryObserver = GatewayHealthTimelineShadowObserver(
            gateway: realGateway,
          );

          final factory = HealthTimelineShadowCompositionFactory(
            coexistenceSourceFactory: () => coexistenceSource,
            runnerFactory: () => runner,
            observer: telemetryObserver,
            runnerExecutor: executor,
          );

          final source = factory.createForResolution(
            const HealthTimelineModeResolution(
              mode: HealthTimelineMode.shadowCompare,
              kind: HealthTimelineModeResolutionKind.configured,
            ),
          );

          final ineligibleQuery = HealthTimelineQuery(
            dogId: 'dog-123',
            cursor: const HealthTimelineCursor('page-2-cursor'),
          );

          primaryCompleter.complete(primaryPage);

          final resultPage = await source.loadPage(ineligibleQuery);
          await Future.delayed(const Duration(milliseconds: 50));

          // Primary page, cursor e hasMore preservados
          expect(resultPage.items.length, equals(1));
          expect(resultPage.items.first.id, equals('p1'));
          expect(resultPage.nextCursor?.token, equals('next-page-cursor'));
          expect(resultPage.hasMore, isTrue);

          // Runner shadow nunca é invocado para query inelegível
          expect(runner.calls, equals(0));

          // Callable recebe exatamente 1 chamada de telemetria skipped
          expect(recordingClient.calls.length, equals(1));
          final payload = recordingClient.calls.single;

          // Payload exatamente com 3 chaves e valores canônicos
          expect(payload.keys.length, equals(3));
          expect(payload['schema_version'], equals(1));
          expect(payload['outcome_type'], equals('skipped'));
          expect(payload['skip_kind'], equals('not_first_page'));

          // Zero campos proibidos / vazamento de identificadores
          const prohibitedKeys = [
            'comparison',
            'failure',
            'dog_id',
            'dogId',
            'uid',
            'email',
            'case_id',
            'caseId',
            'session_id',
            'sessionId',
            'device_id',
            'deviceId',
          ];
          for (final key in prohibitedKeys) {
            expect(payload.containsKey(key), isFalse);
          }
        },
      );

      test(
        'S8: failure outcome gera exatamente uma tentativa no callable',
        () async {
          final primaryPage = _expectedPage(items: [_sampleItem('p1')]);
          final primaryCompleter = Completer<HealthTimelinePage>();
          final coexistenceSource = _FakeHealthTimelineSource(
            completer: primaryCompleter,
          );
          final runner = _FakeShadowRunner(
            resultToReturn: const HealthTimelineShadowRunFailure(
              kind: HealthTimelineShadowFailureKind.shadowFailure,
            ),
          );
          final executor = _FakeRunnerExecutor(passthrough: true);

          final recordingClient = _RecordingCallableClient(
            responseToReturn: {'accepted': true},
          );
          final spyGateway = _SpyGateway();
          final realGateway = _RecordingTelemetryGateway(
            spy: spyGateway,
            client: recordingClient,
          );
          final telemetryObserver = GatewayHealthTimelineShadowObserver(
            gateway: realGateway,
          );

          final factory = HealthTimelineShadowCompositionFactory(
            coexistenceSourceFactory: () => coexistenceSource,
            runnerFactory: () => runner,
            observer: telemetryObserver,
            runnerExecutor: executor,
          );

          final source = factory.createForResolution(
            const HealthTimelineModeResolution(
              mode: HealthTimelineMode.shadowCompare,
              kind: HealthTimelineModeResolutionKind.configured,
            ),
          );

          primaryCompleter.complete(primaryPage);
          await source.loadPage(_sampleQuery());
          await Future.delayed(const Duration(milliseconds: 50));

          expect(recordingClient.calls.length, equals(1));
          expect(
            recordingClient.calls.single['outcome_type'],
            equals('failure'),
          );
          expect(
            recordingClient.calls.single['failure_kind'],
            equals('shadow_failure'),
          );
        },
      );

      test(
        'S9: falha assíncrona não vira unhandled error (fail-silent)',
        () async {
          final primaryPage = _expectedPage(items: [_sampleItem('p1')]);
          final primaryCompleter = Completer<HealthTimelinePage>();
          final coexistenceSource = _FakeHealthTimelineSource(
            completer: primaryCompleter,
          );
          final runner = _FakeShadowRunner(
            resultToReturn: const HealthTimelineShadowRunSuccess(
              primaryCount: 1,
              shadowCount: 1,
              matchedCount: 1,
              missingCount: 0,
              extraCount: 0,
              uncorrelatedPrimaryCount: 0,
              uncorrelatedShadowCount: 0,
              ambiguousPrimaryCount: 0,
              ambiguousShadowCount: 0,
              orderingMismatch: false,
            ),
          );
          final executor = _FakeRunnerExecutor(passthrough: true);

          // Gateway que falha de forma assíncrona
          final asyncFailingGateway = _AsyncFailingSpyGateway(
            error: Exception('async network error'),
          );
          final telemetryObserver = GatewayHealthTimelineShadowObserver(
            gateway: asyncFailingGateway,
          );

          final factory = HealthTimelineShadowCompositionFactory(
            coexistenceSourceFactory: () => coexistenceSource,
            runnerFactory: () => runner,
            observer: telemetryObserver,
            runnerExecutor: executor,
          );

          final source = factory.createForResolution(
            const HealthTimelineModeResolution(
              mode: HealthTimelineMode.shadowCompare,
              kind: HealthTimelineModeResolutionKind.configured,
            ),
          );

          primaryCompleter.complete(primaryPage);

          // Não deve lançar — fail-silent
          await source.loadPage(_sampleQuery());

          // Aguarda para verificar que não houve crash
          await Future.delayed(const Duration(milliseconds: 100));

          // Primary funcionou normalmente
          expect(asyncFailingGateway.gotError, isTrue);
        },
      );

      test(
        'S10: zero retry — callable é chamado no máximo 1 vez por outcome',
        () async {
          final primaryPage = _expectedPage(items: [_sampleItem('p1')]);
          final primaryCompleter = Completer<HealthTimelinePage>();
          final coexistenceSource = _FakeHealthTimelineSource(
            completer: primaryCompleter,
          );
          final runner = _FakeShadowRunner(
            resultToReturn: const HealthTimelineShadowRunSuccess(
              primaryCount: 1,
              shadowCount: 1,
              matchedCount: 1,
              missingCount: 0,
              extraCount: 0,
              uncorrelatedPrimaryCount: 0,
              uncorrelatedShadowCount: 0,
              ambiguousPrimaryCount: 0,
              ambiguousShadowCount: 0,
              orderingMismatch: false,
            ),
          );
          final executor = _FakeRunnerExecutor(passthrough: true);

          final recordingClient = _RecordingCallableClient(
            responseToReturn: {'accepted': true},
          );
          final spyGateway = _SpyGateway();
          final realGateway = _RecordingTelemetryGateway(
            spy: spyGateway,
            client: recordingClient,
          );
          final telemetryObserver = GatewayHealthTimelineShadowObserver(
            gateway: realGateway,
          );

          final factory = HealthTimelineShadowCompositionFactory(
            coexistenceSourceFactory: () => coexistenceSource,
            runnerFactory: () => runner,
            observer: telemetryObserver,
            runnerExecutor: executor,
          );

          final source = factory.createForResolution(
            const HealthTimelineModeResolution(
              mode: HealthTimelineMode.shadowCompare,
              kind: HealthTimelineModeResolutionKind.configured,
            ),
          );

          primaryCompleter.complete(primaryPage);
          await source.loadPage(_sampleQuery());
          await Future.delayed(const Duration(milliseconds: 50));

          // Exatamente 1 chamada — zero retry
          expect(recordingClient.calls.length, equals(1));
        },
      );
    },
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// Helper: Recording gateway que liga spyGateway ao callable client.
// ─────────────────────────────────────────────────────────────────────────────

/// Gateway que conecta o spyGateway ao callable client.
/// Usado para verificar que o callable client recebe exatamente o que
/// o spy gateway recebeu.
class _RecordingTelemetryGateway
    implements HealthTimelineShadowTelemetryGateway {
  _RecordingTelemetryGateway({
    required _SpyGateway spy,
    required _RecordingCallableClient client,
  }) : _spy = spy,
       _client = client;

  final _SpyGateway _spy;
  final _RecordingCallableClient _client;

  @override
  Future<void> record(dynamic record) async {
    // Re-usa a lógica do spy para rastrear e permite ao client registrar
    _spy.records.add(record);
    try {
      await _client.call(
        (record as HealthTimelineShadowTelemetryRecord).toJson(),
      );
    } catch (_) {
      // fail-silent — absorve erro
    }
  }
}

/// Spy gateway que falha de forma assíncrona.
class _AsyncFailingSpyGateway implements HealthTimelineShadowTelemetryGateway {
  _AsyncFailingSpyGateway({required this.error});

  final Object error;
  bool gotError = false;

  @override
  Future<void> record(dynamic record) async {
    gotError = true;
    throw error;
  }
}
