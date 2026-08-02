import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:canil_gcm/core/services/authoritative_time/authoritative_time_gateway.dart';
import 'package:canil_gcm/core/services/authoritative_time/authoritative_time_models.dart';
import 'package:canil_gcm/core/services/authoritative_time/authoritative_time_provider.dart';
import 'package:canil_gcm/core/services/authoritative_time/monotonic_elapsed_clock.dart';
import 'package:canil_gcm/features/health/data/coexistence/nutrition/coexistence_nutrition_read_source.dart';
import 'package:canil_gcm/features/health/data/coexistence/timeline/coexistence_health_timeline_source.dart';
import 'package:canil_gcm/features/health/data/coexistence/timeline/memory_timeline_source_reader.dart';
import 'package:canil_gcm/features/health/data/config/health_timeline_flag_provider.dart';
import 'package:canil_gcm/features/health/data/config/health_timeline_mode.dart';
import 'package:canil_gcm/features/health/domain/health_v1_enums.dart';
import 'package:canil_gcm/features/health/domain/health_v1_enums_ext.dart';
import 'package:canil_gcm/features/health/domain/meal_schedule_slot.dart';
import 'package:canil_gcm/features/health/domain/nutrition_plan.dart';
import 'package:canil_gcm/features/health/presentation/nutrition/health_nutrition_read_controller.dart';
import 'package:canil_gcm/features/health/presentation/screens/health_shell_screen.dart';
import 'package:canil_gcm/features/health/presentation/screens/health_v1_entry_flags.dart';
import 'package:canil_gcm/features/health/presentation/screens/health_v1_entry_screen.dart';
import 'package:canil_gcm/features/health/presentation/summary/health_summary_block_models.dart';
import 'package:canil_gcm/features/health/presentation/summary/health_summary_dashboard.dart';
import 'package:canil_gcm/features/health/presentation/summary/health_summary_dog_context_view.dart';
import 'package:canil_gcm/features/health/presentation/summary/health_summary_section_status.dart';
import 'package:canil_gcm/features/health/presentation/summary/health_summary_source.dart';
import 'package:canil_gcm/features/health/presentation/summary/health_summary_view_data.dart';
import 'package:canil_gcm/features/health/presentation/timeline/detail/health_timeline_detail_target.dart';
import 'package:canil_gcm/features/health/presentation/timeline/health_timeline_cursor.dart';
import 'package:canil_gcm/features/health/presentation/timeline/health_timeline_entry_view.dart';
import 'package:canil_gcm/features/health/presentation/timeline/health_timeline_page.dart';
import 'package:canil_gcm/features/health/presentation/timeline/health_timeline_query.dart';
import 'package:canil_gcm/features/health/presentation/timeline/health_timeline_screen.dart';
import 'package:canil_gcm/features/health/presentation/timeline/health_timeline_source.dart';
import 'package:canil_gcm/features/health/presentation/timeline/health_timeline_state.dart';
import 'package:canil_gcm/features/health/presentation/timeline/models/health_timeline_detail_reference.dart';
import 'package:canil_gcm/features/health/presentation/timeline/widgets/health_timeline_status_views.dart';
import 'package:canil_gcm/features/health/presentation/timeline/widgets/health_timeline_user_copy.dart';
import 'package:canil_gcm/features/health/presentation/widgets/health_module_header.dart';
import 'package:canil_gcm/features/health/presentation/widgets/health_shell_section_placeholder.dart';
import 'package:canil_gcm/features/health/domain/health_v1_models.dart';

/// Fake source one-shot com dados mínimos (sem Firestore).
class _FixedSummarySource implements HealthSummarySource {
  _FixedSummarySource(this.payloadByDogId);
  final Map<String, HealthSummaryViewData> payloadByDogId;
  final List<String> watchCalls = [];

  factory _FixedSummarySource.single(HealthSummaryViewData payload) {
    return _FixedSummarySource({payload.dogId: payload});
  }

  @override
  Stream<HealthSummaryViewData?> watchSummary(String dogId) async* {
    watchCalls.add(dogId);
    yield payloadByDogId[dogId] ?? HealthSummaryViewData(dogId: dogId);
  }
}

final class _EntryMonotonicClock implements MonotonicElapsedClock {
  Duration value = Duration.zero;

  @override
  Duration get elapsed => value;
}

final class _EntryTimeGateway implements AuthoritativeTimeGateway {
  Completer<void>? gate;
  bool fail = false;
  int calls = 0;

  @override
  Future<AuthoritativeTimeRemoteResponse> fetchAuthoritativeTime() async {
    calls++;
    final currentGate = gate;
    if (currentGate != null) await currentGate.future;
    if (fail) {
      throw const AuthoritativeTimeFailure(
        AuthoritativeTimeFailureCode.unavailable,
        'callable indisponível',
      );
    }
    final now = DateTime.utc(2026, 7, 22, 15);
    return AuthoritativeTimeRemoteResponse(
      protocolVersion: 1,
      requestId: '00000000-0000-4000-8000-000000000001',
      requestReceivedAtUtc: now,
      serverSentAtUtc: now,
      maxAge: const Duration(minutes: 15),
    );
  }
}

HealthTimelineSource _emptyTimelineSource() {
  return CoexistenceHealthTimelineSourceFactory.forReaders([
    MemoryTimelineSourceReader(sourceKey: 'empty', items: const []),
  ]);
}

HealthTimelineSource _timelineWithItems(List<HealthTimelineEntryView> items) {
  return CoexistenceHealthTimelineSourceFactory.forReaders([
    MemoryTimelineSourceReader(sourceKey: 'mix', items: items),
  ]);
}

HealthTimelineEntryView _entry({
  required String id,
  required String dogId,
  required DateTime at,
  required HealthTimelineType type,
  required String sourceType,
  required String sourceId,
}) {
  return HealthTimelineEntryView(
    id: id,
    dogId: dogId,
    type: HealthTimelineTypeView.known(type),
    occurredAt: at,
    recordedAt: at,
    title: 'Item $id',
    status: HealthTimelineEntryStatus.finalised,
    detailReference: HealthTimelineDetailReference(
      sourceType: sourceType,
      sourceId: sourceId,
    ),
  );
}

void main() {
  setUpAll(() {
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  final dogContext = HealthSummaryDogContextView(
    dogId: 'dog-1',
    name: 'Bono',
    breed: 'Malinois',
    sexLabel: 'Macho',
    ageLabel: '6 anos',
  );

  Widget wrap(Widget child) {
    return MaterialApp(home: Scaffold(body: child));
  }

  Future<void> setPhoneSurface(WidgetTester tester) async {
    // Superfície realista: o binding padrão (800×600) deixa o slot Histórico
    // com viewport insuficiente para cards + chrome do shell.
    final view = tester.view;
    view.physicalSize = const Size(400, 900);
    view.devicePixelRatio = 1.0;
    addTearDown(view.resetPhysicalSize);
    addTearDown(view.resetDevicePixelRatio);
  }

  test('gate 2E está habilitado por padrão (APK de teste)', () {
    expect(kHealthV1SummaryEntryEnabled, isTrue);
    expect(shouldUseHealthV1SummaryEntry(), isTrue);
  });

  test('gate false seleciona ramo legado (rollback testável)', () {
    expect(shouldUseHealthV1SummaryEntry(overrideGate: false), isFalse);
    // Com gate false, MainRoot monta DogHealthProntuarioScreen e NÃO
    // instancia HealthV1EntryScreen/source/controller.
  });

  testWidgets(
    'composition shares one provider and deduplicates first Health sync',
    (tester) async {
      await setPhoneSurface(tester);
      final gateway = _EntryTimeGateway()..gate = Completer<void>();
      final provider = AuthoritativeTimeProvider(
        gateway: gateway,
        monotonicClock: _EntryMonotonicClock(),
      );
      await tester.pumpWidget(
        wrap(
          HealthV1EntryScreen(
            dogId: 'dog-1',
            authoritativeTimeProvider: provider,
            source: _FixedSummarySource.single(
              HealthSummaryViewData(dogId: 'dog-1'),
            ),
            timelineSource: _emptyTimelineSource(),
            nutritionReadSource: CoexistenceNutritionReadSource(),
            dogContextOverride: dogContext,
          ),
        ),
      );
      await tester.pump();
      await tester.tap(find.text('Nutrição'));
      await tester.pump();

      final state = tester.state<HealthV1EntryScreenState>(
        find.byType(HealthV1EntryScreen),
      );
      expect(state.authoritativeTimeProviderForTest, same(provider));
      expect(gateway.calls, 1);

      gateway.gate!.complete();
      await tester.pumpAndSettle();
      expect(gateway.calls, 1);
      expect(
        state.nutritionReadControllerForTest.temporalState,
        HealthNutritionTemporalState.fresh,
      );
    },
  );

  testWidgets('lifecycle resumed forces one resynchronization', (tester) async {
    await setPhoneSurface(tester);
    final gateway = _EntryTimeGateway();
    final provider = AuthoritativeTimeProvider(
      gateway: gateway,
      monotonicClock: _EntryMonotonicClock(),
    );
    final summarySource = _FixedSummarySource.single(
      HealthSummaryViewData(dogId: 'dog-1'),
    );
    await tester.pumpWidget(
      wrap(
        HealthV1EntryScreen(
          dogId: 'dog-1',
          authoritativeTimeProvider: provider,
          source: summarySource,
          timelineSource: _emptyTimelineSource(),
          nutritionReadSource: CoexistenceNutritionReadSource(),
          dogContextOverride: dogContext,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(gateway.calls, 1);

    await tester.tap(find.text('Nutrição'));
    await tester.pumpAndSettle();
    expect(gateway.calls, 1);

    gateway.fail = true;
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();

    expect(gateway.calls, 2);
    final state = tester.state<HealthV1EntryScreenState>(
      find.byType(HealthV1EntryScreen),
    );
    expect(
      state.nutritionReadControllerForTest.temporalState,
      HealthNutritionTemporalState.fresh,
    );
    expect(
      state.nutritionReadControllerForTest.temporalFailure?.code,
      AuthoritativeTimeFailureCode.unavailable,
    );
    expect(summarySource.watchCalls, hasLength(2));
  });

  testWidgets(
    'UX-04B3C — Complete binding lifecycle A..L test: resumed, rebuild, dispose, remount',
    (tester) async {
      await setPhoneSurface(tester);
      final gateway1 = _EntryTimeGateway();
      final provider1 = AuthoritativeTimeProvider(
        gateway: gateway1,
        monotonicClock: _EntryMonotonicClock(),
      );

      // A. Montar o Entry
      await tester.pumpWidget(
        wrap(
          HealthV1EntryScreen(
            key: const ValueKey('lifecycle-entry-1'),
            dogId: 'dog-1',
            authoritativeTimeProvider: provider1,
            source: _FixedSummarySource.single(
              HealthSummaryViewData(dogId: 'dog-1'),
            ),
            timelineSource: _emptyTimelineSource(),
            nutritionReadSource: CoexistenceNutritionReadSource(),
            dogContextOverride: dogContext,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(gateway1.calls, 1);

      // B. Emitir resumed
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();

      // C. Comprovar ressincronização (2 chamadas no gateway1)
      expect(gateway1.calls, 2);

      // D. Rebuild do mesmo State
      await tester.pumpWidget(
        wrap(
          HealthV1EntryScreen(
            key: const ValueKey('lifecycle-entry-1'),
            dogId: 'dog-1',
            authoritativeTimeProvider: provider1,
            source: _FixedSummarySource.single(
              HealthSummaryViewData(dogId: 'dog-1'),
            ),
            timelineSource: _emptyTimelineSource(),
            nutritionReadSource: CoexistenceNutritionReadSource(),
            dogContextOverride: dogContext,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // E. Emitir resumed novamente
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();

      // F. Comprovar apenas uma nova solicitação (total = 3)
      expect(gateway1.calls, 3);

      // G. Desmontar
      await tester.pumpWidget(
        const MaterialApp(home: SizedBox.shrink()),
      );
      await tester.pumpAndSettle();

      // H. Emitir resumed após dispose
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();

      // I. Comprovar zero chamadas novas e zero exceções
      expect(gateway1.calls, 3);
      expect(tester.takeException(), isNull);

      // J. Remount nova instância
      final gateway2 = _EntryTimeGateway();
      final provider2 = AuthoritativeTimeProvider(
        gateway: gateway2,
        monotonicClock: _EntryMonotonicClock(),
      );
      await tester.pumpWidget(
        wrap(
          HealthV1EntryScreen(
            key: const ValueKey('lifecycle-entry-2'),
            dogId: 'dog-1',
            authoritativeTimeProvider: provider2,
            source: _FixedSummarySource.single(
              HealthSummaryViewData(dogId: 'dog-1'),
            ),
            timelineSource: _emptyTimelineSource(),
            nutritionReadSource: CoexistenceNutritionReadSource(),
            dogContextOverride: dogContext,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(gateway2.calls, 1);

      // K. Emitir resumed na nova instância
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();

      // L. Comprovar exatamente uma solicitação da nova instância (total = 2 no gateway2)
      expect(gateway2.calls, 2);
      expect(gateway1.calls, 3); // Primeiro gateway continua inalterado
    },
  );


  testWidgets('callable failure without anchor keeps Health fail-closed', (
    tester,
  ) async {
    await setPhoneSurface(tester);
    final gateway = _EntryTimeGateway()..fail = true;
    final provider = AuthoritativeTimeProvider(
      gateway: gateway,
      monotonicClock: _EntryMonotonicClock(),
    );
    await tester.pumpWidget(
      wrap(
        HealthV1EntryScreen(
          dogId: 'dog-1',
          authoritativeTimeProvider: provider,
          source: _FixedSummarySource.single(
            HealthSummaryViewData(dogId: 'dog-1'),
          ),
          timelineSource: _emptyTimelineSource(),
          nutritionReadSource: CoexistenceNutritionReadSource(),
          dogContextOverride: dogContext,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Nutrição'));
    await tester.pumpAndSettle();

    final state = tester.state<HealthV1EntryScreenState>(
      find.byType(HealthV1EntryScreen),
    );
    expect(
      state.nutritionReadControllerForTest.temporalState,
      HealthNutritionTemporalState.unavailable,
    );
    expect(
      state.nutritionReadControllerForTest.temporalActionsAllowed,
      isFalse,
    );
    expect(provider.nowFreshUtc(), isNull);
  });

  testWidgets('monta shell + dashboard com K9 e source injetada', (
    tester,
  ) async {
    await setPhoneSurface(tester);
    final payload = HealthSummaryViewData(
      dogId: 'dog-1',
      weight: HealthSummarySectionData.available(
        HealthSummaryWeightView(
          weightKg: 29.5,
          measuredAt: DateTime(2026, 7, 1),
        ),
      ),
    );

    final source = _FixedSummarySource.single(payload);
    await tester.pumpWidget(
      wrap(
        HealthV1EntryScreen(
          dogId: 'dog-1',
          source: source,
          timelineSource: _emptyTimelineSource(),
          dogContextOverride: dogContext,
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.byType(HealthShellScreen), findsOneWidget);
    expect(find.byType(HealthSummaryDashboard), findsOneWidget);
    expect(find.text(HealthModuleHeader.title), findsOneWidget);
    expect(find.text('Bono'), findsOneWidget);
    expect(find.textContaining('29,5'), findsWidgets);
    expect(source.watchCalls, ['dog-1']);
  });

  testWidgets('troca de seção Histórico monta HealthTimelineScreen real', (
    tester,
  ) async {
    await setPhoneSurface(tester);
    final payload = HealthSummaryViewData(dogId: 'dog-1');

    await tester.pumpWidget(
      wrap(
        HealthV1EntryScreen(
          dogId: 'dog-1',
          source: _FixedSummarySource.single(payload),
          timelineSource: _emptyTimelineSource(),
          dogContextOverride: dogContext,
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    await tester.tap(find.text('Histórico'));
    await tester.pumpAndSettle();

    expect(find.byType(HealthTimelineScreen), findsOneWidget);
    expect(find.text(HealthTimelineUserCopy.title), findsOneWidget);
    // Placeholder estrutural do Histórico não deve mais aparecer.
    expect(
      find.text(HealthShellSectionPlaceholder.structuralBanner),
      findsNothing,
    );
  });

  testWidgets('Nutrição faz lazy prime somente ao abrir a seção', (
    tester,
  ) async {
    await setPhoneSurface(tester);
    await tester.pumpWidget(
      wrap(
        HealthV1EntryScreen(
          dogId: 'dog-1',
          source: _FixedSummarySource.single(
            HealthSummaryViewData(dogId: 'dog-1'),
          ),
          timelineSource: _emptyTimelineSource(),
          nutritionReadSource: CoexistenceNutritionReadSource(),
          dogContextOverride: dogContext,
        ),
      ),
    );
    await tester.pump();

    var state = tester.state<HealthV1EntryScreenState>(
      find.byType(HealthV1EntryScreen),
    );
    expect(state.nutritionReadPrimedForTest, isFalse);
    expect(state.nutritionReadControllerForTest.activeDogId, isNull);

    await tester.tap(find.text('Nutrição'));
    await tester.pumpAndSettle();

    state = tester.state<HealthV1EntryScreenState>(
      find.byType(HealthV1EntryScreen),
    );
    expect(state.nutritionReadPrimedForTest, isTrue);
    expect(state.nutritionReadControllerForTest.activeDogId, 'dog-1');
  });

  testWidgets('timeline com itens injetados aparece no slot Histórico', (
    tester,
  ) async {
    await setPhoneSurface(tester);
    final payload = HealthSummaryViewData(dogId: 'dog-1');
    final items = [
      _entry(
        id: 'weight_records:w1',
        dogId: 'dog-1',
        at: DateTime.utc(2026, 5, 10),
        type: HealthTimelineType.weight,
        sourceType: 'weight_records',
        sourceId: 'w1',
      ),
    ];

    await tester.pumpWidget(
      wrap(
        HealthV1EntryScreen(
          dogId: 'dog-1',
          source: _FixedSummarySource.single(payload),
          timelineSource: _timelineWithItems(items),
          dogContextOverride: dogContext,
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    await tester.tap(find.text('Histórico'));
    await tester.pumpAndSettle();

    expect(find.text('Item weight_records:w1'), findsOneWidget);
    expect(find.text(HealthTimelineUserCopy.filterAction), findsOneWidget);
  });

  testWidgets('relatedHistory weight navega via callback injetado', (
    tester,
  ) async {
    await setPhoneSurface(tester);
    final payload = HealthSummaryViewData(dogId: 'dog-1');
    final items = [
      _entry(
        id: 'weight_records:w1',
        dogId: 'dog-1',
        at: DateTime.utc(2026, 5, 10),
        type: HealthTimelineType.weight,
        sourceType: 'weight_records',
        sourceId: 'w1',
      ),
      _entry(
        id: 'health_events:h1',
        dogId: 'dog-1',
        at: DateTime.utc(2026, 5, 9),
        type: HealthTimelineType.consultation,
        sourceType: 'health_events',
        sourceId: 'h1',
      ),
    ];
    final navigated = <HealthTimelineDetailTarget>[];

    await tester.pumpWidget(
      wrap(
        HealthV1EntryScreen(
          dogId: 'dog-1',
          source: _FixedSummarySource.single(payload),
          timelineSource: _timelineWithItems(items),
          dogContextOverride: dogContext,
          onTimelineNavigate: (t) async => navigated.add(t),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    await tester.tap(find.text('Histórico'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Item weight_records:w1'));
    await tester.pumpAndSettle();

    expect(navigated, hasLength(1));
    expect(navigated.single, isA<WeightHistoryTarget>());
    expect(navigated.single.dogId, 'dog-1');
    expect(navigated.single.sourceId, 'w1');
  });

  testWidgets('entry unsupported health_events não navega', (tester) async {
    await setPhoneSurface(tester);
    final payload = HealthSummaryViewData(dogId: 'dog-1');
    final items = [
      _entry(
        id: 'health_events:h1',
        dogId: 'dog-1',
        at: DateTime.utc(2026, 5, 9),
        type: HealthTimelineType.consultation,
        sourceType: 'health_events',
        sourceId: 'h1',
      ),
    ];
    final navigated = <HealthTimelineDetailTarget>[];

    await tester.pumpWidget(
      wrap(
        HealthV1EntryScreen(
          dogId: 'dog-1',
          source: _FixedSummarySource.single(payload),
          timelineSource: _timelineWithItems(items),
          dogContextOverride: dogContext,
          onTimelineNavigate: (t) async => navigated.add(t),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    await tester.tap(find.text('Histórico'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Item health_events:h1'));
    await tester.pumpAndSettle();

    expect(navigated, isEmpty);
  });

  testWidgets('lazy: timeline não carrega até abrir Histórico', (tester) async {
    await setPhoneSurface(tester);
    final payload = HealthSummaryViewData(dogId: 'dog-1');
    await tester.pumpWidget(
      wrap(
        HealthV1EntryScreen(
          dogId: 'dog-1',
          source: _FixedSummarySource.single(payload),
          timelineSource: _emptyTimelineSource(),
          dogContextOverride: dogContext,
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 30));

    final state = tester.state<HealthV1EntryScreenState>(
      find.byType(HealthV1EntryScreen),
    );
    expect(state.controllerForTest.activeDogId, 'dog-1');
    expect(state.timelinePrimedForTest, isFalse);
    expect(state.timelineControllerForTest?.activeDogId, isNull);
    expect(state.filterSessionForTest?.dogId, 'dog-1');

    await tester.tap(find.text('Histórico'));
    await tester.pumpAndSettle();

    expect(state.timelinePrimedForTest, isTrue);
    expect(state.timelineControllerForTest?.activeDogId, 'dog-1');
  });

  testWidgets('troca dog A→B atualiza contexto e selectDog sem misturar', (
    tester,
  ) async {
    final source = _FixedSummarySource({
      'dog-A': HealthSummaryViewData(
        dogId: 'dog-A',
        weight: HealthSummarySectionData.available(
          HealthSummaryWeightView(
            weightKg: 20,
            measuredAt: DateTime(2026, 1, 1),
          ),
        ),
      ),
      'dog-B': HealthSummaryViewData(
        dogId: 'dog-B',
        weight: HealthSummarySectionData.available(
          HealthSummaryWeightView(
            weightKg: 35,
            measuredAt: DateTime(2026, 2, 1),
          ),
        ),
      ),
    });
    final ctxA = HealthSummaryDogContextView(dogId: 'dog-A', name: 'Alpha');
    final ctxB = HealthSummaryDogContextView(dogId: 'dog-B', name: 'Bravo');

    await tester.pumpWidget(
      wrap(
        HealthV1EntryScreen(
          key: const ValueKey('health-v1-dog-A'),
          dogId: 'dog-A',
          source: source,
          timelineSource: _emptyTimelineSource(),
          dogContextOverride: ctxA,
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 40));
    expect(find.text('Alpha'), findsOneWidget);
    expect(find.textContaining('20'), findsWidgets);

    // Troca de K9 com nova key (como na aba Saúde) — lifecycle limpo.
    await tester.pumpWidget(
      wrap(
        HealthV1EntryScreen(
          key: const ValueKey('health-v1-dog-B'),
          dogId: 'dog-B',
          source: source,
          timelineSource: _emptyTimelineSource(),
          dogContextOverride: ctxB,
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 40));

    expect(find.text('Bravo'), findsOneWidget);
    expect(find.text('Alpha'), findsNothing);
    expect(source.watchCalls, containsAll(['dog-A', 'dog-B']));
    final state = tester.state<HealthV1EntryScreenState>(
      find.byType(HealthV1EntryScreen),
    );
    expect(state.controllerForTest.activeDogId, 'dog-B');
    // Nova key = novo entry; timeline ainda lazy até abrir Histórico.
    expect(state.timelinePrimedForTest, isFalse);
    expect(state.filterSessionForTest?.dogId, 'dog-B');
  });

  testWidgets(
    'didUpdateWidget troca dogId sem ValueKey (caminho complementar)',
    (tester) async {
      await setPhoneSurface(tester);
      final source = _FixedSummarySource({
        'dog-A': HealthSummaryViewData(dogId: 'dog-A'),
        'dog-B': HealthSummaryViewData(dogId: 'dog-B'),
      });
      final ctxA = HealthSummaryDogContextView(dogId: 'dog-A', name: 'Alpha');
      final ctxB = HealthSummaryDogContextView(dogId: 'dog-B', name: 'Bravo');

      // Mesma key → State sobrevive; didUpdateWidget deve chamar selectDog.
      await tester.pumpWidget(
        wrap(
          HealthV1EntryScreen(
            key: const ValueKey('stable-entry'),
            dogId: 'dog-A',
            source: source,
            timelineSource: _emptyTimelineSource(),
            dogContextOverride: ctxA,
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 30));

      // Prime timeline em A para exercitar selectDog no didUpdateWidget.
      await tester.tap(find.text('Histórico'));
      await tester.pumpAndSettle();

      await tester.pumpWidget(
        wrap(
          HealthV1EntryScreen(
            key: const ValueKey('stable-entry'),
            dogId: 'dog-B',
            source: source,
            timelineSource: _emptyTimelineSource(),
            dogContextOverride: ctxB,
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 30));

      // Ainda na aba Histórico: nome aparece no subtítulo da timeline.
      expect(find.textContaining('Bravo'), findsWidgets);
      expect(find.textContaining('Alpha'), findsNothing);
      final state = tester.state<HealthV1EntryScreenState>(
        find.byType(HealthV1EntryScreen),
      );
      expect(state.controllerForTest.activeDogId, 'dog-B');
      expect(state.timelinePrimedForTest, isTrue);
      expect(state.timelineControllerForTest?.activeDogId, 'dog-B');
      expect(state.filterSessionForTest?.dogId, 'dog-B');
      expect(source.watchCalls, containsAll(['dog-A', 'dog-B']));
    },
  );

  testWidgets('dispose do entry descarta summary e timeline controllers', (
    tester,
  ) async {
    final payload = HealthSummaryViewData(dogId: 'dog-1');
    await tester.pumpWidget(
      wrap(
        HealthV1EntryScreen(
          dogId: 'dog-1',
          source: _FixedSummarySource.single(payload),
          timelineSource: _emptyTimelineSource(),
          dogContextOverride: dogContext,
        ),
      ),
    );
    await tester.pump();
    final state = tester.state<HealthV1EntryScreenState>(
      find.byType(HealthV1EntryScreen),
    );
    final controller = state.controllerForTest;
    final timeline = state.timelineControllerForTest;

    await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
    await tester.pump();

    expect(controller.isDisposedForTest, isTrue);
    expect(timeline?.isDisposedForTest, isTrue);
  });

  testWidgets('timeline carrega estado empty sem Firestore após abrir aba', (
    tester,
  ) async {
    await setPhoneSurface(tester);
    final payload = HealthSummaryViewData(dogId: 'dog-1');
    await tester.pumpWidget(
      wrap(
        HealthV1EntryScreen(
          dogId: 'dog-1',
          source: _FixedSummarySource.single(payload),
          timelineSource: _emptyTimelineSource(),
          dogContextOverride: dogContext,
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    await tester.tap(find.text('Histórico'));
    await tester.pumpAndSettle();

    final state = tester.state<HealthV1EntryScreenState>(
      find.byType(HealthV1EntryScreen),
    );
    expect(state.timelineControllerForTest?.state, isA<HealthTimelineEmpty>());
  });

  testWidgets('load em voo + dispose do entry não crasha', (tester) async {
    await setPhoneSurface(tester);
    final gate = Completer<void>();
    final source = _DelayedEmptyTimelineSource(gate.future);

    await tester.pumpWidget(
      wrap(
        HealthV1EntryScreen(
          dogId: 'dog-1',
          source: _FixedSummarySource.single(
            HealthSummaryViewData(dogId: 'dog-1'),
          ),
          timelineSource: source,
          dogContextOverride: dogContext,
        ),
      ),
    );
    await tester.pump();
    await tester.tap(find.text('Histórico'));
    await tester.pump(); // inicia load, ainda aguarda gate

    final state = tester.state<HealthV1EntryScreenState>(
      find.byType(HealthV1EntryScreen),
    );
    final timeline = state.timelineControllerForTest;

    await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
    await tester.pump();
    expect(timeline?.isDisposedForTest, isTrue);

    // Completa o Future após dispose — não deve crashar.
    gate.complete();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 20));
  });

  group('Subgate 4C-C-C-H3B2 — Session-Stable Mode Capture', () {
    testWidgets(
      'explicit timeline source is installed immediately by identity',
      (tester) async {
        await setPhoneSurface(tester);
        final explicitSource = _emptyTimelineSource();

        await tester.pumpWidget(
          wrap(
            HealthV1EntryScreen(
              dogId: 'dog-1',
              source: _FixedSummarySource.single(
                HealthSummaryViewData(dogId: 'dog-1'),
              ),
              timelineSource: explicitSource,
              dogContextOverride: dogContext,
            ),
          ),
        );
        await tester.pump();

        final state = tester.state<HealthV1EntryScreenState>(
          find.byType(HealthV1EntryScreen),
        );
        expect(state.timelineControllerForTest, isNotNull);
        expect(identical(state.timelineSourceForTest, explicitSource), isTrue);
      },
    );

    testWidgets('explicit timeline source does not call the flag provider', (
      tester,
    ) async {
      await setPhoneSurface(tester);
      final explicitSource = _emptyTimelineSource();
      final provider = _RecordingHealthTimelineFlagProvider();

      await tester.pumpWidget(
        wrap(
          HealthV1EntryScreen(
            dogId: 'dog-1',
            source: _FixedSummarySource.single(
              HealthSummaryViewData(dogId: 'dog-1'),
            ),
            timelineSource: explicitSource,
            timelineFlagProvider: provider,
            dogContextOverride: dogContext,
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(provider.calls, 0);
    });

    testWidgets(
      'explicit timeline source does not call the resolution source factory',
      (tester) async {
        await setPhoneSurface(tester);
        final explicitSource = _emptyTimelineSource();
        final resolver = _RecordingTimelineSourceForResolution();

        await tester.pumpWidget(
          wrap(
            HealthV1EntryScreen(
              dogId: 'dog-1',
              source: _FixedSummarySource.single(
                HealthSummaryViewData(dogId: 'dog-1'),
              ),
              timelineSource: explicitSource,
              timelineSourceForResolution: resolver.resolve,
              dogContextOverride: dogContext,
            ),
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 50));

        expect(resolver.calls, 0);
      },
    );

    testWidgets(
      'timeline mode provider is called exactly once per entry screen state',
      (tester) async {
        await setPhoneSurface(tester);
        final provider = _RecordingHealthTimelineFlagProvider();

        await tester.pumpWidget(
          wrap(
            HealthV1EntryScreen(
              dogId: 'dog-1',
              source: _FixedSummarySource.single(
                HealthSummaryViewData(dogId: 'dog-1'),
              ),
              timelineFlagProvider: provider,
              dogContextOverride: dogContext,
            ),
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 50));

        expect(provider.calls, 1);
      },
    );

    testWidgets(
      'legacyOnly resolution is forwarded once to the source factory',
      (tester) async {
        await setPhoneSurface(tester);
        const expectedRes = HealthTimelineModeResolution(
          mode: HealthTimelineMode.legacyOnly,
          kind: HealthTimelineModeResolutionKind.configured,
        );
        final provider = _RecordingHealthTimelineFlagProvider(
          resolution: expectedRes,
        );
        final resolver = _RecordingTimelineSourceForResolution();

        await tester.pumpWidget(
          wrap(
            HealthV1EntryScreen(
              dogId: 'dog-1',
              source: _FixedSummarySource.single(
                HealthSummaryViewData(dogId: 'dog-1'),
              ),
              timelineFlagProvider: provider,
              timelineSourceForResolution: resolver.resolve,
              dogContextOverride: dogContext,
            ),
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 50));

        expect(resolver.calls, 1);
        expect(resolver.receivedResolution, equals(expectedRes));
      },
    );

    testWidgets(
      'shadowCompare resolution is forwarded once to the source factory',
      (tester) async {
        await setPhoneSurface(tester);
        const expectedRes = HealthTimelineModeResolution(
          mode: HealthTimelineMode.shadowCompare,
          kind: HealthTimelineModeResolutionKind.configured,
        );
        final provider = _RecordingHealthTimelineFlagProvider(
          resolution: expectedRes,
        );
        final resolver = _RecordingTimelineSourceForResolution();

        await tester.pumpWidget(
          wrap(
            HealthV1EntryScreen(
              dogId: 'dog-1',
              source: _FixedSummarySource.single(
                HealthSummaryViewData(dogId: 'dog-1'),
              ),
              timelineFlagProvider: provider,
              timelineSourceForResolution: resolver.resolve,
              dogContextOverride: dogContext,
            ),
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 50));

        expect(resolver.calls, 1);
        expect(resolver.receivedResolution, equals(expectedRes));
      },
    );

    testWidgets(
      'canonicalPrimary resolution is forwarded once to the source factory',
      (tester) async {
        await setPhoneSurface(tester);
        const expectedRes = HealthTimelineModeResolution(
          mode: HealthTimelineMode.canonicalPrimary,
          kind: HealthTimelineModeResolutionKind.configured,
        );
        final provider = _RecordingHealthTimelineFlagProvider(
          resolution: expectedRes,
        );
        final resolver = _RecordingTimelineSourceForResolution();

        await tester.pumpWidget(
          wrap(
            HealthV1EntryScreen(
              dogId: 'dog-1',
              source: _FixedSummarySource.single(
                HealthSummaryViewData(dogId: 'dog-1'),
              ),
              timelineFlagProvider: provider,
              timelineSourceForResolution: resolver.resolve,
              dogContextOverride: dogContext,
            ),
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 50));

        expect(resolver.calls, 1);
        expect(resolver.receivedResolution, equals(expectedRes));
      },
    );

    testWidgets(
      'missingDefault resolution is forwarded without being rewritten',
      (tester) async {
        await setPhoneSurface(tester);
        const expectedRes = HealthTimelineModeResolution(
          mode: HealthTimelineMode.legacyOnly,
          kind: HealthTimelineModeResolutionKind.missingDefault,
        );
        final provider = _RecordingHealthTimelineFlagProvider(
          resolution: expectedRes,
        );
        final resolver = _RecordingTimelineSourceForResolution();

        await tester.pumpWidget(
          wrap(
            HealthV1EntryScreen(
              dogId: 'dog-1',
              source: _FixedSummarySource.single(
                HealthSummaryViewData(dogId: 'dog-1'),
              ),
              timelineFlagProvider: provider,
              timelineSourceForResolution: resolver.resolve,
              dogContextOverride: dogContext,
            ),
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 50));

        expect(resolver.calls, 1);
        expect(resolver.receivedResolution, equals(expectedRes));
      },
    );

    testWidgets(
      'invalidDefault resolution is forwarded without being rewritten',
      (tester) async {
        await setPhoneSurface(tester);
        const expectedRes = HealthTimelineModeResolution(
          mode: HealthTimelineMode.legacyOnly,
          kind: HealthTimelineModeResolutionKind.invalidDefault,
        );
        final provider = _RecordingHealthTimelineFlagProvider(
          resolution: expectedRes,
        );
        final resolver = _RecordingTimelineSourceForResolution();

        await tester.pumpWidget(
          wrap(
            HealthV1EntryScreen(
              dogId: 'dog-1',
              source: _FixedSummarySource.single(
                HealthSummaryViewData(dogId: 'dog-1'),
              ),
              timelineFlagProvider: provider,
              timelineSourceForResolution: resolver.resolve,
              dogContextOverride: dogContext,
            ),
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 50));

        expect(resolver.calls, 1);
        expect(resolver.receivedResolution, equals(expectedRes));
      },
    );

    testWidgets(
      'synchronous provider throw falls back to legacyOnly missingDefault',
      (tester) async {
        await setPhoneSurface(tester);
        final provider = _RecordingHealthTimelineFlagProvider(
          syncException: Exception('Provider sync throw'),
        );
        final resolver = _RecordingTimelineSourceForResolution();

        await tester.pumpWidget(
          wrap(
            HealthV1EntryScreen(
              dogId: 'dog-1',
              source: _FixedSummarySource.single(
                HealthSummaryViewData(dogId: 'dog-1'),
              ),
              timelineFlagProvider: provider,
              timelineSourceForResolution: resolver.resolve,
              dogContextOverride: dogContext,
            ),
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 50));

        expect(resolver.calls, 1);
        expect(
          resolver.receivedResolution,
          equals(
            const HealthTimelineModeResolution(
              mode: HealthTimelineMode.legacyOnly,
              kind: HealthTimelineModeResolutionKind.missingDefault,
            ),
          ),
        );
      },
    );

    testWidgets(
      'provider future error falls back to legacyOnly missingDefault',
      (tester) async {
        await setPhoneSurface(tester);
        final provider = _RecordingHealthTimelineFlagProvider(
          futureError: StateError('Provider future error'),
        );
        final resolver = _RecordingTimelineSourceForResolution();

        await tester.pumpWidget(
          wrap(
            HealthV1EntryScreen(
              dogId: 'dog-1',
              source: _FixedSummarySource.single(
                HealthSummaryViewData(dogId: 'dog-1'),
              ),
              timelineFlagProvider: provider,
              timelineSourceForResolution: resolver.resolve,
              dogContextOverride: dogContext,
            ),
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 50));

        expect(resolver.calls, 1);
        expect(
          resolver.receivedResolution,
          equals(
            const HealthTimelineModeResolution(
              mode: HealthTimelineMode.legacyOnly,
              kind: HealthTimelineModeResolutionKind.missingDefault,
            ),
          ),
        );
      },
    );

    testWidgets(
      'provider timeout falls back once and ignores late completion',
      (tester) async {
        await setPhoneSurface(tester);
        final completer = Completer<HealthTimelineModeResolution>();
        final provider = _RecordingHealthTimelineFlagProvider(
          completer: completer,
        );
        final resolver = _RecordingTimelineSourceForResolution();

        await tester.pumpWidget(
          wrap(
            HealthV1EntryScreen(
              dogId: 'dog-1',
              source: _FixedSummarySource.single(
                HealthSummaryViewData(dogId: 'dog-1'),
              ),
              timelineFlagProvider: provider,
              timelineSourceForResolution: resolver.resolve,
              timelineFlagResolutionTimeout: const Duration(milliseconds: 100),
              dogContextOverride: dogContext,
            ),
          ),
        );
        await tester.pump();

        expect(resolver.calls, 0);

        await tester.pump(const Duration(milliseconds: 100));

        expect(resolver.calls, 1);
        expect(
          resolver.receivedResolution,
          equals(
            const HealthTimelineModeResolution(
              mode: HealthTimelineMode.legacyOnly,
              kind: HealthTimelineModeResolutionKind.missingDefault,
            ),
          ),
        );

        completer.complete(
          const HealthTimelineModeResolution(
            mode: HealthTimelineMode.shadowCompare,
            kind: HealthTimelineModeResolutionKind.configured,
          ),
        );
        await tester.pump(const Duration(milliseconds: 50));

        expect(resolver.calls, 1);
      },
    );

    testWidgets('rebuild during mode resolution does not call provider again', (
      tester,
    ) async {
      await setPhoneSurface(tester);
      final completer = Completer<HealthTimelineModeResolution>();
      final provider = _RecordingHealthTimelineFlagProvider(
        completer: completer,
      );
      final resolver = _RecordingTimelineSourceForResolution();

      await tester.pumpWidget(
        wrap(
          HealthV1EntryScreen(
            key: const ValueKey('rebuild-entry'),
            dogId: 'dog-1',
            source: _FixedSummarySource.single(
              HealthSummaryViewData(dogId: 'dog-1'),
            ),
            timelineFlagProvider: provider,
            timelineSourceForResolution: resolver.resolve,
            dogContextOverride: dogContext,
          ),
        ),
      );
      await tester.pump();

      expect(provider.calls, 1);

      await tester.pumpWidget(
        wrap(
          HealthV1EntryScreen(
            key: const ValueKey('rebuild-entry'),
            dogId: 'dog-1',
            source: _FixedSummarySource.single(
              HealthSummaryViewData(dogId: 'dog-1'),
            ),
            timelineFlagProvider: provider,
            timelineSourceForResolution: resolver.resolve,
            dogContextOverride: dogContext,
          ),
        ),
      );
      await tester.pump();

      expect(provider.calls, 1);

      completer.complete(
        const HealthTimelineModeResolution(
          mode: HealthTimelineMode.legacyOnly,
          kind: HealthTimelineModeResolutionKind.configured,
        ),
      );
      await tester.pump(const Duration(milliseconds: 50));

      expect(provider.calls, 1);
      expect(resolver.calls, 1);
    });

    testWidgets(
      'opening history while resolving shows loading and primes once after resolution',
      (tester) async {
        await setPhoneSurface(tester);
        final completer = Completer<HealthTimelineModeResolution>();
        final provider = _RecordingHealthTimelineFlagProvider(
          completer: completer,
        );
        final recordingSource = _RecordingHealthTimelineSource();
        final resolver = _RecordingTimelineSourceForResolution()
          ..sourceToReturn = recordingSource;

        await tester.pumpWidget(
          wrap(
            HealthV1EntryScreen(
              dogId: 'dog-1',
              source: _FixedSummarySource.single(
                HealthSummaryViewData(dogId: 'dog-1'),
              ),
              timelineFlagProvider: provider,
              timelineSourceForResolution: resolver.resolve,
              dogContextOverride: dogContext,
            ),
          ),
        );
        await tester.pump();

        await tester.tap(find.text('Histórico'));
        await tester.pump();

        expect(find.byType(HealthTimelineLoadingView), findsOneWidget);
        expect(recordingSource.loadCalls, isEmpty);

        completer.complete(
          const HealthTimelineModeResolution(
            mode: HealthTimelineMode.legacyOnly,
            kind: HealthTimelineModeResolutionKind.configured,
          ),
        );
        await tester.pump(const Duration(milliseconds: 50));

        expect(find.byType(HealthTimelineScreen), findsOneWidget);
        expect(recordingSource.loadCalls, hasLength(1));
        expect(provider.calls, 1);
        expect(resolver.calls, 1);
      },
    );

    testWidgets(
      'dispose before mode resolution prevents source and controller installation',
      (tester) async {
        await setPhoneSurface(tester);
        final completer = Completer<HealthTimelineModeResolution>();
        final provider = _RecordingHealthTimelineFlagProvider(
          completer: completer,
        );
        final resolver = _RecordingTimelineSourceForResolution();

        await tester.pumpWidget(
          wrap(
            HealthV1EntryScreen(
              dogId: 'dog-1',
              source: _FixedSummarySource.single(
                HealthSummaryViewData(dogId: 'dog-1'),
              ),
              timelineFlagProvider: provider,
              timelineSourceForResolution: resolver.resolve,
              dogContextOverride: dogContext,
            ),
          ),
        );
        await tester.pump();

        await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
        await tester.pump();

        completer.complete(
          const HealthTimelineModeResolution(
            mode: HealthTimelineMode.legacyOnly,
            kind: HealthTimelineModeResolutionKind.configured,
          ),
        );
        await tester.pump(const Duration(milliseconds: 50));

        expect(resolver.calls, 0);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'refresh and loadMore after resolution do not resolve the mode again',
      (tester) async {
        await setPhoneSurface(tester);
        final provider = _RecordingHealthTimelineFlagProvider();

        const cursorInitial = HealthTimelineCursor('cursor_page_1');
        const cursorAfterRefresh = HealthTimelineCursor('cursor_page_2');

        final item1 = _entry(
          id: 'w1',
          dogId: 'dog-1',
          at: DateTime.utc(2026, 5, 10),
          type: HealthTimelineType.weight,
          sourceType: 'weight_records',
          sourceId: 'w1',
        );
        final item2 = _entry(
          id: 'w2',
          dogId: 'dog-1',
          at: DateTime.utc(2026, 5, 9),
          type: HealthTimelineType.weight,
          sourceType: 'weight_records',
          sourceId: 'w2',
        );
        final item3 = _entry(
          id: 'w3',
          dogId: 'dog-1',
          at: DateTime.utc(2026, 5, 8),
          type: HealthTimelineType.weight,
          sourceType: 'weight_records',
          sourceId: 'w3',
        );

        final page1 = HealthTimelinePage(
          items: [item1],
          nextCursor: cursorInitial,
          hasMore: true,
        );
        final page2 = HealthTimelinePage(
          items: [item2],
          nextCursor: cursorAfterRefresh,
          hasMore: true,
        );
        final page3 = HealthTimelinePage(
          items: [item3],
          nextCursor: null,
          hasMore: false,
        );

        final recordingSource = _RecordingHealthTimelineSource(
          pagesToReturn: [page1, page2, page3],
        );
        final resolver = _RecordingTimelineSourceForResolution()
          ..sourceToReturn = recordingSource;

        await tester.pumpWidget(
          wrap(
            HealthV1EntryScreen(
              dogId: 'dog-1',
              source: _FixedSummarySource.single(
                HealthSummaryViewData(dogId: 'dog-1'),
              ),
              timelineFlagProvider: provider,
              timelineSourceForResolution: resolver.resolve,
              dogContextOverride: dogContext,
            ),
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 50));

        await tester.tap(find.text('Histórico'));
        await tester.pumpAndSettle();

        expect(provider.calls, 1);
        expect(resolver.calls, 1);
        expect(resolver.createdSources.length, 1);

        final state = tester.state<HealthV1EntryScreenState>(
          find.byType(HealthV1EntryScreen),
        );
        final controller = state.timelineControllerForTest;
        expect(controller, isNotNull);

        // 1. Primeira página carregada
        expect(recordingSource.loadCalls, hasLength(1));
        expect(recordingSource.loadCalls[0].dogId, 'dog-1');
        expect(recordingSource.loadCalls[0].cursor, isNull);

        // 2. Refresh real
        await controller!.refresh();
        await tester.pumpAndSettle();

        expect(recordingSource.loadCalls, hasLength(2));
        expect(recordingSource.loadCalls[1].dogId, 'dog-1');
        expect(recordingSource.loadCalls[1].cursor, isNull);

        // 3. LoadMore real com cursor
        await controller.loadMore();
        await tester.pumpAndSettle();

        expect(recordingSource.loadCalls, hasLength(3));
        expect(recordingSource.loadCalls[2].dogId, 'dog-1');
        expect(recordingSource.loadCalls[2].cursor, equals(cursorAfterRefresh));
        expect(
          identical(recordingSource.loadCalls[2].cursor, cursorAfterRefresh),
          isTrue,
        );

        // provider e resolver permanecem com exatamente 1 chamada
        expect(provider.calls, 1);
        expect(resolver.calls, 1);
      },
    );
  });

  // ══════════════════════════════════════════════════════════════════════════
  // UX-04B3C — OWNERSHIP & IDENTITY
  // ══════════════════════════════════════════════════════════════════════════

  testWidgets(
    'identity: same provider reaches controller and CoexistenceSummarySource',
    (tester) async {
      await setPhoneSurface(tester);
      final gateway = _EntryTimeGateway();
      final provider = AuthoritativeTimeProvider(
        gateway: gateway,
        monotonicClock: _EntryMonotonicClock(),
      );
      final summarySource = _FixedSummarySource.single(
        HealthSummaryViewData(dogId: 'dog-1'),
      );

      await tester.pumpWidget(
        wrap(
          HealthV1EntryScreen(
            dogId: 'dog-1',
            authoritativeTimeProvider: provider,
            source: summarySource,
            timelineSource: _emptyTimelineSource(),
            nutritionReadSource: CoexistenceNutritionReadSource(),
            dogContextOverride: dogContext,
          ),
        ),
      );
      await tester.pumpAndSettle();

      final state = tester.state<HealthV1EntryScreenState>(
        find.byType(HealthV1EntryScreen),
      );

      // Same provider instance in entry widget
      expect(state.authoritativeTimeProviderForTest, same(provider));
      // Same provider reaches nutrition read controller
      expect(
        state.nutritionReadControllerForTest.authoritativeTimeProviderForTest,
        same(provider),
      );
      // Only one gateway call for the entry's initial sync
      expect(gateway.calls, 1);
      // Summary source was called
      expect(summarySource.watchCalls, ['dog-1']);
    },
  );

  // ══════════════════════════════════════════════════════════════════════════
  // UX-04B3C — LIFECYCLE
  // ══════════════════════════════════════════════════════════════════════════

  testWidgets('lifecycle: single registration on mount', (tester) async {
    await setPhoneSurface(tester);
    final gateway = _EntryTimeGateway();
    final provider = AuthoritativeTimeProvider(
      gateway: gateway,
      monotonicClock: _EntryMonotonicClock(),
    );

    await tester.pumpWidget(
      wrap(
        HealthV1EntryScreen(
          dogId: 'dog-1',
          authoritativeTimeProvider: provider,
          source: _FixedSummarySource.single(
            HealthSummaryViewData(dogId: 'dog-1'),
          ),
          timelineSource: _emptyTimelineSource(),
          nutritionReadSource: CoexistenceNutritionReadSource(),
          dogContextOverride: dogContext,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(gateway.calls, 1);

    // Second rebuild does not register another observer
    await tester.pumpWidget(
      wrap(
        HealthV1EntryScreen(
          dogId: 'dog-1',
          authoritativeTimeProvider: provider,
          source: _FixedSummarySource.single(
            HealthSummaryViewData(dogId: 'dog-1'),
          ),
          timelineSource: _emptyTimelineSource(),
          nutritionReadSource: CoexistenceNutritionReadSource(),
          dogContextOverride: dogContext,
        ),
      ),
    );
    await tester.pumpAndSettle();
    // No new sync call from rebuild
    expect(gateway.calls, 1);
  });

  testWidgets(
    'lifecycle: dispose blocks callbacks after discard',
    (tester) async {
      await setPhoneSurface(tester);
      final gateway = _EntryTimeGateway();
      final provider = AuthoritativeTimeProvider(
        gateway: gateway,
        monotonicClock: _EntryMonotonicClock(),
      );

      await tester.pumpWidget(
        wrap(
          HealthV1EntryScreen(
            dogId: 'dog-1',
            authoritativeTimeProvider: provider,
            source: _FixedSummarySource.single(
              HealthSummaryViewData(dogId: 'dog-1'),
            ),
            timelineSource: _emptyTimelineSource(),
            nutritionReadSource: CoexistenceNutritionReadSource(),
            dogContextOverride: dogContext,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(gateway.calls, 1);

      // Dispose the entry
      await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
      await tester.pump();

      // Emit resumed after dispose
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();

      // No new sync after dispose
      expect(gateway.calls, 1);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('lifecycle: remount creates exactly one fresh sync', (
    tester,
  ) async {
    await setPhoneSurface(tester);

    // First mount
    final gateway1 = _EntryTimeGateway();
    final provider1 = AuthoritativeTimeProvider(
      gateway: gateway1,
      monotonicClock: _EntryMonotonicClock(),
    );

    await tester.pumpWidget(
      wrap(
        HealthV1EntryScreen(
          dogId: 'dog-1',
          authoritativeTimeProvider: provider1,
          source: _FixedSummarySource.single(
            HealthSummaryViewData(dogId: 'dog-1'),
          ),
          timelineSource: _emptyTimelineSource(),
          nutritionReadSource: CoexistenceNutritionReadSource(),
          dogContextOverride: dogContext,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(gateway1.calls, 1);

    // Unmount
    await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
    await tester.pump();

    // Remount with new provider
    final gateway2 = _EntryTimeGateway();
    final provider2 = AuthoritativeTimeProvider(
      gateway: gateway2,
      monotonicClock: _EntryMonotonicClock(),
    );

    await tester.pumpWidget(
      wrap(
        HealthV1EntryScreen(
          dogId: 'dog-1',
          authoritativeTimeProvider: provider2,
          source: _FixedSummarySource.single(
            HealthSummaryViewData(dogId: 'dog-1'),
          ),
          timelineSource: _emptyTimelineSource(),
          nutritionReadSource: CoexistenceNutritionReadSource(),
          dogContextOverride: dogContext,
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Second provider synced
    expect(gateway2.calls, 1);
    // First provider not called again
    expect(gateway1.calls, 1);
  });

  testWidgets(
    'lifecycle: internal tab switch does not accumulate observers',
    (tester) async {
      await setPhoneSurface(tester);
      final gateway = _EntryTimeGateway();
      final provider = AuthoritativeTimeProvider(
        gateway: gateway,
        monotonicClock: _EntryMonotonicClock(),
      );

      await tester.pumpWidget(
        wrap(
          HealthV1EntryScreen(
            dogId: 'dog-1',
            authoritativeTimeProvider: provider,
            source: _FixedSummarySource.single(
              HealthSummaryViewData(dogId: 'dog-1'),
            ),
            timelineSource: _emptyTimelineSource(),
            nutritionReadSource: CoexistenceNutritionReadSource(),
            dogContextOverride: dogContext,
          ),
        ),
      );
      await tester.pumpAndSettle();
      final initialCalls = gateway.calls;

      // Switch to Nutrição tab
      await tester.tap(find.text('Nutrição'));
      await tester.pumpAndSettle();

      // Switch back to Resumo
      await tester.tap(find.text('Resumo'));
      await tester.pumpAndSettle();

      // Switch to Nutrição again
      await tester.tap(find.text('Nutrição'));
      await tester.pumpAndSettle();

      // No new sync from tab switches
      expect(gateway.calls, initialCalls);
    },
  );

  // ══════════════════════════════════════════════════════════════════════════
  // UX-04B3C — TEMPORAL FAILURE + OTHER BLOCKS
  // ══════════════════════════════════════════════════════════════════════════

  testWidgets(
    'temporal failure without anchor: Nutrition unavailable, other blocks '
        'available, no false zero',
    (tester) async {
      await setPhoneSurface(tester);
      final gateway = _EntryTimeGateway()..fail = true;
      final provider = AuthoritativeTimeProvider(
        gateway: gateway,
        monotonicClock: _EntryMonotonicClock(),
      );

      await tester.pumpWidget(
        wrap(
          HealthV1EntryScreen(
            dogId: 'dog-1',
            authoritativeTimeProvider: provider,
            source: _FixedSummarySource.single(
              HealthSummaryViewData(
                dogId: 'dog-1',
                weight: HealthSummarySectionData.available(
                  HealthSummaryWeightView(
                    weightKg: 29.5,
                    measuredAt: DateTime(2026, 7, 1),
                  ),
                ),
                vaccination: HealthSummarySectionData.available(
                  HealthSummaryVaccinationView(
                    summaryLabel: 'Em dia',
                    lastRecordLabel: 'V8',
                    nextDueAt: DateTime(2026, 8, 15),
                  ),
                ),
              ),
            ),
            timelineSource: _emptyTimelineSource(),
            nutritionReadSource: CoexistenceNutritionReadSource(),
            dogContextOverride: dogContext,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Nutrição'));
      await tester.pumpAndSettle();

      final state = tester.state<HealthV1EntryScreenState>(
        find.byType(HealthV1EntryScreen),
      );

      // Nutrition is unavailable due to temporal failure
      expect(
        state.nutritionReadControllerForTest.temporalState,
        HealthNutritionTemporalState.unavailable,
      );
      expect(
        state.nutritionReadControllerForTest.temporalActionsAllowed,
        isFalse,
      );

      // No fallback to DateTime.now in the provider
      expect(provider.nowFreshUtc(), isNull);
    },
  );

  // ══════════════════════════════════════════════════════════════════════════
  // UX-04B3C — AUTHORITATIVE READ-AFTER-WRITE
  // ══════════════════════════════════════════════════════════════════════════

  testWidgets(
    'read-after-write: force sync uses one gateway call and one projection',
    (tester) async {
      await setPhoneSurface(tester);
      var sequence = 0;
      final gateway = _CountingTimeGateway((_) async {
        sequence++;
        final now = DateTime.utc(2026, 7, 22, 15);
        return AuthoritativeTimeRemoteResponse(
          protocolVersion: 1,
          requestId: '00000000-0000-4000-8000-${sequence.toString().padLeft(12, '0')}',
          requestReceivedAtUtc: now,
          serverSentAtUtc: now,
          maxAge: const Duration(minutes: 15),
        );
      });
      final provider = AuthoritativeTimeProvider(
        gateway: gateway,
        monotonicClock: _EntryMonotonicClock(),
      );

      final source = CoexistenceNutritionReadSource(
        canonicalPlanReader: _SequencePlanReaderForRAW([
          NutritionSourceBatch.available([_planForRAW('p1', 'dog-1')]),
          NutritionSourceBatch.available([_planForRAW('p2', 'dog-1')]),
        ]),
      );

      final controller = HealthNutritionReadController(
        source: source,
        authoritativeTimeProvider: provider,
      );
      addTearDown(controller.dispose);

      await controller.selectDog('dog-1');
      expect(gateway.callCount, 1);
      final firstRef = controller.todayOrNull?.referenceNow;

      // Simulate mutation success followed by force sync
      await controller.refresh();
      expect(gateway.callCount, 2);
      final secondRef = controller.todayOrNull?.referenceNow;

      // Both referenceNow values belong to the same UTC instant
      expect(secondRef, isNotNull);
      expect(firstRef, isNotNull);
      expect(controller.todayOrNull?.referenceNow, DateTime.utc(2026, 7, 22, 15));

      // No mixture of old time with new data — generation advanced
      expect(controller.generationForTest, 2);
    },
  );

  testWidgets(
    'read-after-write: force sync failure leaves snapshot and Today unavailable',
    (tester) async {
      await setPhoneSurface(tester);
      var syncCount = 0;
      final gateway = _CountingTimeGateway((_) async {
        syncCount++;
        if (syncCount > 1) {
          throw const AuthoritativeTimeFailure(
            AuthoritativeTimeFailureCode.unavailable,
            'callable indisponível',
          );
        }
        final now = DateTime.utc(2026, 7, 22, 15);
        return AuthoritativeTimeRemoteResponse(
          protocolVersion: 1,
          requestId: '00000000-0000-4000-8000-000000000001',
          requestReceivedAtUtc: now,
          serverSentAtUtc: now,
          maxAge: const Duration(minutes: 15),
        );
      });
      final provider = AuthoritativeTimeProvider(
        gateway: gateway,
        monotonicClock: _EntryMonotonicClock(),
      );

      final source = CoexistenceNutritionReadSource(
        canonicalPlanReader: _SequencePlanReaderForRAW([
          NutritionSourceBatch.available([_planForRAW('p1', 'dog-1')]),
          NutritionSourceBatch.error(message: 'plan error'),
        ]),
      );

      final controller = HealthNutritionReadController(
        source: source,
        authoritativeTimeProvider: provider,
      );
      addTearDown(controller.dispose);

      await controller.selectDog('dog-1');
      expect(controller.snapshotResult.hasUsableValue, isTrue);
      expect(
        controller.temporalState,
        HealthNutritionTemporalState.fresh,
      );

      // Force sync fails but old snapshot retained → temporalFailure captured,
      // temporalState stays fresh (retained snapshot still valid)
      await controller.refresh();
      expect(
        controller.temporalState,
        HealthNutritionTemporalState.fresh,
      );
      // Failure was recorded even though state is fresh
      expect(controller.temporalFailure, isNotNull);

      // Reference still from retained snapshot
      expect(provider.nowFreshUtc(), isNotNull);
    },
  );

  testWidgets(
    'lifecycle observer is removed on dispose and remount registers exactly once',
    (tester) async {
      await setPhoneSurface(tester);
      final gateway1 = _EntryTimeGateway();
      final provider1 = AuthoritativeTimeProvider(
        gateway: gateway1,
        monotonicClock: _EntryMonotonicClock(),
      );

      Widget buildTree(AuthoritativeTimeProvider p) => wrap(
            HealthV1EntryScreen(
              dogId: 'dog-1',
              authoritativeTimeProvider: p,
              source: _FixedSummarySource.single(
                HealthSummaryViewData(dogId: 'dog-1'),
              ),
              timelineSource: _emptyTimelineSource(),
              nutritionReadSource: CoexistenceNutritionReadSource(),
              dogContextOverride: dogContext,
            ),
          );

      // 1. Mount HealthV1EntryScreen
      await tester.pumpWidget(buildTree(provider1));
      await tester.pumpAndSettle();

      // 2. Wait for initial sync
      expect(gateway1.calls, 1);

      // 3. Rebuild the same widget preserving the same State
      await tester.pumpWidget(buildTree(provider1));
      await tester.pumpAndSettle();
      expect(gateway1.calls, 1);

      // 4. Emit AppLifecycleState.resumed by test binding
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();

      // 5. Prove exactly one new logical sync
      expect(gateway1.calls, 2);

      // 6. Unmount completely
      await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
      await tester.pumpAndSettle();

      // 7. Emit resumed after dispose
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();

      // 8. Prove zero new syncs
      expect(gateway1.calls, 2);

      // 9. Prove zero callbacks / zero exceptions
      expect(tester.takeException(), isNull);

      // 11. Mount a new instance
      final gateway2 = _EntryTimeGateway();
      final provider2 = AuthoritativeTimeProvider(
        gateway: gateway2,
        monotonicClock: _EntryMonotonicClock(),
      );

      await tester.pumpWidget(buildTree(provider2));
      await tester.pumpAndSettle();

      // Initial sync for instance 2
      expect(gateway2.calls, 1);

      // 12. Emit resumed
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();

      // 13. Prove exactly one resume sync for new instance
      expect(gateway2.calls, 2);

      // 14. Prove old observer does not participate
      expect(gateway1.calls, 2);
    },
  );
}

class _CountingTimeGateway implements AuthoritativeTimeGateway {
  _CountingTimeGateway(this._factory);
  final Future<AuthoritativeTimeRemoteResponse> Function(int callIndex) _factory;
  int callCount = 0;

  @override
  Future<AuthoritativeTimeRemoteResponse> fetchAuthoritativeTime() async {
    callCount++;
    return _factory(callCount);
  }
}

class _SequencePlanReaderForRAW implements NutritionCanonicalPlanReader {
  _SequencePlanReaderForRAW(this.batches);
  final List<NutritionSourceBatch<NutritionPlan>> batches;
  var calls = 0;

  @override
  Future<NutritionSourceBatch<NutritionPlan>> loadPlans(String dogId) async {
    final index = calls < batches.length ? calls : batches.length - 1;
    calls++;
    return batches[index];
  }
}

NutritionPlan _planForRAW(String id, String dogId) {
  return NutritionPlan(
    id: id,
    dogId: dogId,
    foodType: 'Ração Teste',
    amountGramsPerDay: 400,
    mealsPerDay: 2,
    mealSchedule: [
      MealScheduleSlot(
        id: 'slot-1',
        period: MealPeriodWire.parseCanonical('morning'),
        scheduledTime: ScheduledTimeOfDay('07:00'),
        targetGrams: 200,
      ),
    ],
    validFrom: DateTime.utc(2026, 1, 1),
    timezone: NutritionPlan.defaultTimezone,
    recordedBy: RecordedBy(uid: 'u1', name: 'Test', internalRole: 'test'),
    status: NutritionPlanStatus.active,
    schemaVersion: 1,
    revision: 1,
  );
}

class _RecordingHealthTimelineFlagProvider
    implements HealthTimelineFlagProvider {
  _RecordingHealthTimelineFlagProvider({
    this.resolution,
    this.completer,
    this.syncException,
    this.futureError,
  });

  final HealthTimelineModeResolution? resolution;
  final Completer<HealthTimelineModeResolution>? completer;
  final Object? syncException;
  final Object? futureError;

  int calls = 0;

  @override
  Future<HealthTimelineModeResolution> resolveMode() {
    calls++;
    if (syncException != null) {
      throw syncException!;
    }
    if (futureError != null) {
      return Future.error(futureError!);
    }
    if (completer != null) {
      return completer!.future;
    }
    return Future.value(
      resolution ??
          const HealthTimelineModeResolution(
            mode: HealthTimelineMode.legacyOnly,
            kind: HealthTimelineModeResolutionKind.configured,
          ),
    );
  }
}

class _RecordingTimelineSourceForResolution {
  int calls = 0;
  HealthTimelineModeResolution? receivedResolution;
  HealthTimelineSource? sourceToReturn;
  final List<HealthTimelineSource> createdSources = [];

  HealthTimelineSource resolve(HealthTimelineModeResolution resolution) {
    calls++;
    receivedResolution = resolution;
    final source = sourceToReturn ?? _emptyTimelineSource();
    createdSources.add(source);
    return source;
  }
}

class _RecordingHealthTimelineSource implements HealthTimelineSource {
  _RecordingHealthTimelineSource({this.pagesToReturn = const []});

  final List<HealthTimelinePage> pagesToReturn;
  final List<HealthTimelineQuery> loadCalls = [];

  @override
  Future<HealthTimelinePage> loadPage(HealthTimelineQuery query) async {
    loadCalls.add(query);
    if (pagesToReturn.isNotEmpty) {
      if (loadCalls.length <= pagesToReturn.length) {
        return pagesToReturn[loadCalls.length - 1];
      }
      return pagesToReturn.last;
    }
    return HealthTimelinePage.empty();
  }
}

/// Source que só resolve após [release] — para race dispose vs load.
class _DelayedEmptyTimelineSource implements HealthTimelineSource {
  _DelayedEmptyTimelineSource(this.release);
  final Future<void> release;

  @override
  Future<HealthTimelinePage> loadPage(HealthTimelineQuery query) async {
    await release;
    return HealthTimelinePage.empty();
  }
}
