import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:mocktail/mocktail.dart';
import 'package:provider/provider.dart';

import 'package:canil_gcm/features/dogs/data/dog_service.dart';
import 'package:canil_gcm/features/dogs/presentation/screens/vaccination_history_screen.dart';
import 'package:canil_gcm/features/dogs/presentation/screens/weight_history_screen.dart';
import 'package:canil_gcm/features/health/data/coexistence/timeline/coexistence_health_timeline_source.dart';
import 'package:canil_gcm/features/health/data/coexistence/timeline/memory_timeline_source_reader.dart';
import 'package:canil_gcm/features/health/data/health_service.dart';
import 'package:canil_gcm/features/health/domain/health_v1_enums_ext.dart';
import 'package:canil_gcm/features/health/presentation/screens/health_v1_entry_screen.dart';
import 'package:canil_gcm/features/health/presentation/summary/health_summary_dog_context_view.dart';
import 'package:canil_gcm/features/health/presentation/summary/health_summary_source.dart';
import 'package:canil_gcm/features/health/presentation/summary/health_summary_view_data.dart';
import 'package:canil_gcm/features/health/presentation/timeline/detail/health_timeline_navigation_coordinator.dart';
import 'package:canil_gcm/features/health/presentation/timeline/filters/health_timeline_filter_session.dart';
import 'package:canil_gcm/features/health/presentation/timeline/health_timeline_controller.dart';
import 'package:canil_gcm/features/health/presentation/timeline/health_timeline_entry_view.dart';
import 'package:canil_gcm/features/health/presentation/timeline/health_timeline_screen.dart';
import 'package:canil_gcm/features/health/presentation/timeline/models/health_timeline_detail_reference.dart';
import 'package:canil_gcm/features/health/presentation/viewmodels/health_viewmodel.dart';
import 'package:canil_gcm/features/nutrition/presentation/screens/nutrition_full_screen.dart';
import 'package:canil_gcm/features/nutrition/presentation/viewmodels/nutrition_viewmodel.dart';

/// 3E-D2 — Navegação relatedHistory **real** (Navigator + tela destino).
///
/// Diferente de 3E-B/C: **não** injeta [HealthV1EntryScreen.onTimelineNavigate].
/// Prova: tap → resolver → coordinator → entry → push → widget destino na árvore.

class _FixedSummarySource implements HealthSummarySource {
  _FixedSummarySource.single(HealthSummaryViewData p)
    : payloadByDog = {p.dogId: p};
  final Map<String, HealthSummaryViewData> payloadByDog;

  @override
  Stream<HealthSummaryViewData?> watchSummary(String dogId) async* {
    yield payloadByDog[dogId] ?? HealthSummaryViewData(dogId: dogId);
  }
}

class _MockNutritionViewModel extends Mock implements NutritionViewModel {}

HealthTimelineEntryView _e({
  required String id,
  required DateTime at,
  required HealthTimelineType type,
  required String sourceType,
  required String sourceId,
  String dogId = 'dog-1',
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

/// Helper de promoção null-safety para getters de teste.
HealthTimelineController _requireTimelineController(
  HealthV1EntryScreenState state,
) {
  final controller = state.timelineControllerForTest;
  expect(controller, isNotNull);
  return controller!;
}

HealthTimelineFilterSession _requireFilterSession(
  HealthV1EntryScreenState state,
) {
  final session = state.filterSessionForTest;
  expect(session, isNotNull);
  return session!;
}

void main() {
  setUpAll(() {
    GoogleFonts.config.allowRuntimeFetching = false;
    registerFallbackValue('');
  });

  final dogContext = HealthSummaryDogContextView(
    dogId: 'dog-1',
    name: 'Rex',
    breed: 'Malinois',
  );

  final timelineItems = [
    _e(
      id: 'weight_records:w1',
      at: DateTime.utc(2026, 5, 10, 10),
      type: HealthTimelineType.weight,
      sourceType: 'weight_records',
      sourceId: 'w1',
    ),
    _e(
      id: 'feeding_events:f1',
      at: DateTime.utc(2026, 5, 9, 12),
      type: HealthTimelineType.meal,
      sourceType: 'feeding_events',
      sourceId: 'f1',
    ),
    _e(
      id: 'vacinas:v1',
      at: DateTime.utc(2026, 5, 8, 9),
      type: HealthTimelineType.vaccination,
      sourceType: 'vacinas',
      sourceId: 'v1',
    ),
    _e(
      id: 'health_events:h1',
      at: DateTime.utc(2026, 5, 7, 8),
      type: HealthTimelineType.consultation,
      sourceType: 'health_events',
      sourceId: 'h1',
    ),
  ];

  _MockNutritionViewModel buildNutritionMock() {
    final mock = _MockNutritionViewModel();
    when(() => mock.historyLoading).thenReturn(true);
    when(() => mock.totalFeedings90d).thenReturn(0);
    when(() => mock.addListener(any())).thenReturn(null);
    when(() => mock.removeListener(any())).thenReturn(null);
    when(() => mock.dispose()).thenReturn(null);
    when(
      () => mock.loadForDog(any(), forceReload: any(named: 'forceReload')),
    ).thenAnswer((_) async {});
    when(() => mock.loadFullHistory(any())).thenAnswer((_) async {});
    return mock;
  }

  Widget wrapProductionNav(Widget child) {
    final fake = FakeFirebaseFirestore();
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<HealthViewModel>(
          create: (_) => HealthViewModel.withServices(
            HealthService(firestore: fake),
            DogService(firestore: fake),
          ),
        ),
        ChangeNotifierProvider<NutritionViewModel>.value(
          value: buildNutritionMock(),
        ),
      ],
      child: MaterialApp(home: Scaffold(body: child)),
    );
  }

  Future<void> setPhoneSurface(WidgetTester tester) async {
    final view = tester.view;
    view.physicalSize = const Size(400, 1100);
    view.devicePixelRatio = 1.0;
    addTearDown(view.resetPhysicalSize);
    addTearDown(view.resetDevicePixelRatio);
  }

  Future<void> openHistorico(WidgetTester tester) async {
    await setPhoneSurface(tester);
    await tester.pumpWidget(
      wrapProductionNav(
        HealthV1EntryScreen(
          dogId: 'dog-1',
          source: _FixedSummarySource.single(
            HealthSummaryViewData(dogId: 'dog-1'),
          ),
          timelineSource: CoexistenceHealthTimelineSourceFactory.forReaders([
            MemoryTimelineSourceReader(sourceKey: 'd2', items: timelineItems),
          ]),
          dogContextOverride: dogContext,
          // SEM onTimelineNavigate — força path de produção (Navigator real).
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 40));
    await tester.tap(find.text('Histórico'));
    await tester.pumpAndSettle();
    expect(find.byType(HealthTimelineScreen), findsOneWidget);
  }

  Future<void> tapCardAndExpectDestination(
    WidgetTester tester, {
    required String cardTitle,
    required Type destinationType,
    required String expectedDogId,
  }) async {
    final card = find.text(cardTitle);
    expect(card, findsOneWidget);
    await tester.scrollUntilVisible(
      card,
      120,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pump();
    await tester.tap(card);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 80));

    expect(find.byType(destinationType), findsOneWidget);

    if (destinationType == WeightHistoryScreen) {
      final w = tester.widget<WeightHistoryScreen>(
        find.byType(WeightHistoryScreen),
      );
      expect(w.dog.id, expectedDogId);
    } else if (destinationType == NutritionFullScreen) {
      final n = tester.widget<NutritionFullScreen>(
        find.byType(NutritionFullScreen),
      );
      expect(n.dog.id, expectedDogId);
    } else if (destinationType == VaccinationHistoryScreen) {
      final v = tester.widget<VaccinationHistoryScreen>(
        find.byType(VaccinationHistoryScreen),
      );
      expect(v.dog.id, expectedDogId);
    }
  }

  Future<void> popBackToHistorico(WidgetTester tester) async {
    // Telas legado usam back custom (não AppBar/CupertinoBackButton).
    final dest = find.byWidgetPredicate(
      (w) =>
          w is WeightHistoryScreen ||
          w is NutritionFullScreen ||
          w is VaccinationHistoryScreen,
    );
    expect(dest, findsOneWidget);
    Navigator.of(tester.element(dest)).pop();
    await tester.pumpAndSettle();
    expect(find.byType(HealthTimelineScreen), findsOneWidget);
  }

  group('GATE A — Weight real navigation', () {
    testWidgets('tap weight abre WeightHistoryScreen com dog correto', (
      tester,
    ) async {
      await openHistorico(tester);
      await tapCardAndExpectDestination(
        tester,
        cardTitle: 'Item weight_records:w1',
        destinationType: WeightHistoryScreen,
        expectedDogId: 'dog-1',
      );
    });
  });

  group('GATE B — Nutrition real navigation', () {
    testWidgets('tap feeding abre NutritionFullScreen com dog correto', (
      tester,
    ) async {
      await openHistorico(tester);
      await tapCardAndExpectDestination(
        tester,
        cardTitle: 'Item feeding_events:f1',
        destinationType: NutritionFullScreen,
        expectedDogId: 'dog-1',
      );
    });
  });

  group('GATE C — Vaccination real navigation', () {
    testWidgets('tap vacinação abre VaccinationHistoryScreen com dog correto', (
      tester,
    ) async {
      await openHistorico(tester);
      await tapCardAndExpectDestination(
        tester,
        cardTitle: 'Item vacinas:v1',
        destinationType: VaccinationHistoryScreen,
        expectedDogId: 'dog-1',
      );
    });
  });

  group('GATE D+E — Dog + back preservation', () {
    testWidgets('back retorna ao Histórico com filtros/timeline vivos', (
      tester,
    ) async {
      await openHistorico(tester);

      final entryState = tester.state<HealthV1EntryScreenState>(
        find.byType(HealthV1EntryScreen),
      );
      final timelineBefore = _requireTimelineController(entryState);
      final sessionBefore = _requireFilterSession(entryState);
      final filterCountBefore = sessionBefore.activeFilterCount;

      await tapCardAndExpectDestination(
        tester,
        cardTitle: 'Item weight_records:w1',
        destinationType: WeightHistoryScreen,
        expectedDogId: 'dog-1',
      );

      await popBackToHistorico(tester);

      final entryAfter = tester.state<HealthV1EntryScreenState>(
        find.byType(HealthV1EntryScreen),
      );
      expect(
        identical(entryAfter.timelineControllerForTest, timelineBefore),
        isTrue,
      );
      expect(identical(entryAfter.filterSessionForTest, sessionBefore), isTrue);
      expect(sessionBefore.activeFilterCount, filterCountBefore);
      expect(find.text('Item weight_records:w1'), findsOneWidget);
    });
  });

  group('GATE F — Double tap', () {
    testWidgets('dois taps rápidos → no máximo uma tela destino', (
      tester,
    ) async {
      await openHistorico(tester);

      final card = find.text('Item weight_records:w1');
      await tester.scrollUntilVisible(
        card,
        120,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pump();
      await tester.tap(card);
      // Segundo tap enquanto busy — pode falhar hit-test se a rota já cobriu
      // o card; o coordinator garante no máximo uma navegação.
      await tester.tap(card, warnIfMissed: false);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 80));

      expect(find.byType(WeightHistoryScreen), findsOneWidget);
    });
  });

  group('GATE G — Unsupported consultation health_events', () {
    testWidgets('health_events consultation não navega', (tester) async {
      await openHistorico(tester);
      final card = find.text('Item health_events:h1');
      await tester.scrollUntilVisible(
        card,
        120,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pump();
      await tester.tap(card);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 80));

      expect(find.byType(WeightHistoryScreen), findsNothing);
      expect(find.byType(NutritionFullScreen), findsNothing);
      expect(find.byType(VaccinationHistoryScreen), findsNothing);
      expect(find.byType(HealthTimelineScreen), findsOneWidget);
    });
  });

  group('GATE 3E-D3 — Vacinação via health_events (CRUD mobile)', () {
    testWidgets('tap health_events vaccination abre VaccinationHistoryScreen', (
      tester,
    ) async {
      await setPhoneSurface(tester);
      final items = [
        _e(
          id: 'health_events:hv1',
          at: DateTime.utc(2026, 5, 11, 9),
          type: HealthTimelineType.vaccination,
          sourceType: 'health_events',
          sourceId: 'hv1',
        ),
      ];
      await tester.pumpWidget(
        wrapProductionNav(
          HealthV1EntryScreen(
            dogId: 'dog-1',
            source: _FixedSummarySource.single(
              HealthSummaryViewData(dogId: 'dog-1'),
            ),
            timelineSource: CoexistenceHealthTimelineSourceFactory.forReaders([
              MemoryTimelineSourceReader(sourceKey: 'd3', items: items),
            ]),
            dogContextOverride: dogContext,
          ),
        ),
      );
      await tester.pump();
      await tester.tap(find.text('Histórico'));
      await tester.pumpAndSettle();

      await tapCardAndExpectDestination(
        tester,
        cardTitle: 'Item health_events:hv1',
        destinationType: VaccinationHistoryScreen,
        expectedDogId: 'dog-1',
      );
    });
  });

  group('GATE H — Dog não resolvido no catálogo', () {
    testWidgets('target com dogId sem catálogo ainda navega (fallback)', (
      tester,
    ) async {
      await setPhoneSurface(tester);
      final orphanItems = [
        _e(
          id: 'weight_records:orphan',
          dogId: 'dog-missing',
          at: DateTime.utc(2026, 5, 10),
          type: HealthTimelineType.weight,
          sourceType: 'weight_records',
          sourceId: 'orphan',
        ),
      ];
      await tester.pumpWidget(
        wrapProductionNav(
          HealthV1EntryScreen(
            dogId: 'dog-missing',
            source: _FixedSummarySource.single(
              HealthSummaryViewData(dogId: 'dog-missing'),
            ),
            timelineSource: CoexistenceHealthTimelineSourceFactory.forReaders([
              MemoryTimelineSourceReader(sourceKey: 'h', items: orphanItems),
            ]),
            dogContextOverride: HealthSummaryDogContextView(
              dogId: 'dog-missing',
              name: 'Ghost',
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.tap(find.text('Histórico'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Item weight_records:orphan'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 80));

      expect(find.byType(WeightHistoryScreen), findsOneWidget);
      final w = tester.widget<WeightHistoryScreen>(
        find.byType(WeightHistoryScreen),
      );
      expect(w.dog.id, 'dog-missing');
      expect(w.dog.name, 'Ghost');
    });
  });

  group('GATE I — Coordinator release after failure', () {
    testWidgets('falha no navigate libera busy e aceita próximo tap', (
      tester,
    ) async {
      var calls = 0;
      final errors = <Object>[];
      final coordinator = HealthTimelineNavigationCoordinator(
        onNavigate: (target) async {
          calls++;
          if (calls == 1) {
            throw StateError('simulated nav failure');
          }
        },
        onNavigateError: (e, _) => errors.add(e),
      );

      final entry = _e(
        id: 'weight_records:w1',
        at: DateTime.utc(2026, 5, 10),
        type: HealthTimelineType.weight,
        sourceType: 'weight_records',
        sourceId: 'w1',
      );

      await coordinator.onEntryTap(entry);
      expect(coordinator.isBusy, isFalse);
      expect(calls, 1);
      expect(errors, hasLength(1));

      await coordinator.onEntryTap(entry);
      expect(coordinator.isBusy, isFalse);
      expect(calls, 2);
    });
  });

  group('GATE — três destinos em sequência', () {
    testWidgets('weight → back → nutrition → back → vaccination', (
      tester,
    ) async {
      await openHistorico(tester);

      await tapCardAndExpectDestination(
        tester,
        cardTitle: 'Item weight_records:w1',
        destinationType: WeightHistoryScreen,
        expectedDogId: 'dog-1',
      );
      await popBackToHistorico(tester);

      await tapCardAndExpectDestination(
        tester,
        cardTitle: 'Item feeding_events:f1',
        destinationType: NutritionFullScreen,
        expectedDogId: 'dog-1',
      );
      await popBackToHistorico(tester);

      await tapCardAndExpectDestination(
        tester,
        cardTitle: 'Item vacinas:v1',
        destinationType: VaccinationHistoryScreen,
        expectedDogId: 'dog-1',
      );
    });
  });
}
