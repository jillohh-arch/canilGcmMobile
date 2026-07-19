import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:canil_gcm/features/health/data/coexistence/nutrition/coexistence_nutrition_read_source.dart';
import 'package:canil_gcm/features/health/data/coexistence/timeline/coexistence_health_timeline_source.dart';
import 'package:canil_gcm/features/health/data/coexistence/timeline/memory_timeline_source_reader.dart';
import 'package:canil_gcm/features/health/domain/health_v1_enums_ext.dart';
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
import 'package:canil_gcm/features/health/presentation/timeline/health_timeline_entry_view.dart';
import 'package:canil_gcm/features/health/presentation/timeline/health_timeline_page.dart';
import 'package:canil_gcm/features/health/presentation/timeline/health_timeline_query.dart';
import 'package:canil_gcm/features/health/presentation/timeline/health_timeline_screen.dart';
import 'package:canil_gcm/features/health/presentation/timeline/health_timeline_source.dart';
import 'package:canil_gcm/features/health/presentation/timeline/health_timeline_state.dart';
import 'package:canil_gcm/features/health/presentation/timeline/models/health_timeline_detail_reference.dart';
import 'package:canil_gcm/features/health/presentation/timeline/widgets/health_timeline_user_copy.dart';
import 'package:canil_gcm/features/health/presentation/widgets/health_module_header.dart';
import 'package:canil_gcm/features/health/presentation/widgets/health_shell_section_placeholder.dart';

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
    expect(state.timelineControllerForTest.activeDogId, isNull);
    expect(state.filterSessionForTest.dogId, 'dog-1');

    await tester.tap(find.text('Histórico'));
    await tester.pumpAndSettle();

    expect(state.timelinePrimedForTest, isTrue);
    expect(state.timelineControllerForTest.activeDogId, 'dog-1');
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
    expect(state.filterSessionForTest.dogId, 'dog-B');
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
      expect(state.timelineControllerForTest.activeDogId, 'dog-B');
      expect(state.filterSessionForTest.dogId, 'dog-B');
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
    expect(timeline.isDisposedForTest, isTrue);
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
    expect(state.timelineControllerForTest.state, isA<HealthTimelineEmpty>());
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
    expect(timeline.isDisposedForTest, isTrue);

    // Completa o Future após dispose — não deve crashar.
    gate.complete();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 20));
  });
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
