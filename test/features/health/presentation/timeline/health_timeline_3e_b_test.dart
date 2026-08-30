import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:canil_gcm/features/app_shell/presentation/main_root_nav_metrics.dart';
import 'package:canil_gcm/features/health/data/coexistence/timeline/coexistence_health_timeline_source.dart';
import 'package:canil_gcm/features/health/data/coexistence/timeline/memory_timeline_source_reader.dart';
import 'package:canil_gcm/features/health/domain/health_v1_enums_ext.dart';
import 'package:canil_gcm/features/health/presentation/screens/health_v1_entry_screen.dart';
import 'package:canil_gcm/features/health/presentation/summary/health_summary_dashboard.dart';
import 'package:canil_gcm/features/health/presentation/summary/health_summary_dog_context_view.dart';
import 'package:canil_gcm/features/health/presentation/summary/health_summary_source.dart';
import 'package:canil_gcm/features/health/presentation/summary/health_summary_view_data.dart';
import 'package:canil_gcm/features/health/presentation/timeline/detail/health_timeline_detail_target.dart';
import 'package:canil_gcm/features/health/presentation/timeline/filters/health_timeline_period_preset.dart';
import 'package:canil_gcm/features/health/presentation/timeline/filters/health_timeline_quick_type_chips.dart';
import 'package:canil_gcm/features/health/presentation/timeline/filters/health_timeline_filter_session.dart';
import 'package:canil_gcm/features/health/presentation/timeline/health_timeline_controller.dart';
import 'package:canil_gcm/features/health/presentation/timeline/health_timeline_cursor.dart';
import 'package:canil_gcm/features/health/presentation/timeline/health_timeline_entry_view.dart';
import 'package:canil_gcm/features/health/presentation/timeline/health_timeline_page.dart';
import 'package:canil_gcm/features/health/presentation/timeline/health_timeline_query.dart';
import 'package:canil_gcm/features/health/presentation/timeline/health_timeline_screen.dart';
import 'package:canil_gcm/features/health/presentation/timeline/health_timeline_source.dart';
import 'package:canil_gcm/features/health/presentation/timeline/health_timeline_state.dart';
import 'package:canil_gcm/features/health/presentation/timeline/models/health_timeline_detail_reference.dart';
import 'package:canil_gcm/features/health/presentation/timeline/widgets/health_timeline_user_copy.dart';

/// Gates formais 3E-B A–L — integração controlada Entry → Shell → Timeline.
class _FixedSummarySource implements HealthSummarySource {
  _FixedSummarySource(this.payloadByDog);
  _FixedSummarySource.single(HealthSummaryViewData p)
    : payloadByDog = {p.dogId: p};

  final Map<String, HealthSummaryViewData> payloadByDog;

  @override
  Stream<HealthSummaryViewData?> watchSummary(String dogId) async* {
    yield payloadByDog[dogId] ?? HealthSummaryViewData(dogId: dogId);
  }
}

class _RecordingSource implements HealthTimelineSource {
  _RecordingSource(this._inner);
  final HealthTimelineSource _inner;
  final List<HealthTimelineQuery> queries = [];

  @override
  Future<HealthTimelinePage> loadPage(HealthTimelineQuery query) async {
    queries.add(query);
    return _inner.loadPage(query);
  }
}

class _GatedSource implements HealthTimelineSource {
  _GatedSource(this._inner);
  final HealthTimelineSource _inner;
  Completer<void>? _gate;
  Completer<void>? _entered;
  bool blockNext = false;

  Future<void> waitEntered() async {
    final e = _entered;
    if (e != null) await e.future;
  }

  void release() {
    final g = _gate;
    if (g != null && !g.isCompleted) g.complete();
  }

  @override
  Future<HealthTimelinePage> loadPage(HealthTimelineQuery query) async {
    if (blockNext) {
      blockNext = false;
      _gate = Completer<void>();
      _entered = Completer<void>();
      _entered!.complete();
      await _gate!.future;
    }
    return _inner.loadPage(query);
  }
}

class _PagedSource implements HealthTimelineSource {
  _PagedSource(this.items);
  final List<HealthTimelineEntryView> items;

  @override
  Future<HealthTimelinePage> loadPage(HealthTimelineQuery query) async {
    final dogItems = items.where((e) => e.dogId == query.dogId).toList();
    var start = 0;
    if (query.cursor != null) {
      final token = int.tryParse(query.cursor!.token) ?? 0;
      start = token;
    }
    final pageSize = query.pageSize;
    final slice = dogItems.skip(start).take(pageSize).toList();
    final next = start + slice.length;
    final hasMore = next < dogItems.length;
    return HealthTimelinePage(
      items: slice,
      hasMore: hasMore,
      nextCursor: hasMore ? HealthTimelineCursor('$next') : null,
    );
  }
}

class _FailSource implements HealthTimelineSource {
  _FailSource({required this.isOffline, this.message = 'falha teste'});
  final bool isOffline;
  final String message;

  @override
  Future<HealthTimelinePage> loadPage(HealthTimelineQuery query) async {
    throw HealthTimelineSourceException(message, isOffline: isOffline);
  }
}

HealthTimelineEntryView _e({
  required String id,
  required DateTime at,
  required HealthTimelineType type,
  String sourceType = 'weight_records',
  String sourceId = 'x',
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
  });

  final dogContext = HealthSummaryDogContextView(dogId: 'dog-1', name: 'Rex');

  Widget wrap(Widget child) {
    return MaterialApp(home: Scaffold(body: child));
  }

  Future<void> setPhoneSurface(WidgetTester tester) async {
    final view = tester.view;
    view.physicalSize = const Size(400, 900);
    view.devicePixelRatio = 1.0;
    addTearDown(view.resetPhysicalSize);
    addTearDown(view.resetDevicePixelRatio);
  }

  Future<HealthV1EntryScreenState> openHistorico(
    WidgetTester tester, {
    required Widget entry,
  }) async {
    await setPhoneSurface(tester);
    await tester.pumpWidget(wrap(entry));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 40));
    await tester.tap(find.text('Histórico'));
    await tester.pumpAndSettle();
    return tester.state<HealthV1EntryScreenState>(
      find.byType(HealthV1EntryScreen),
    );
  }

  group('GATE A — Composition singleton', () {
    testWidgets('rebuild/aba não recria controller nem session', (
      tester,
    ) async {
      final recording = _RecordingSource(
        CoexistenceHealthTimelineSourceFactory.forReaders([
          MemoryTimelineSourceReader(sourceKey: 'a', items: const []),
        ]),
      );
      final state = await openHistorico(
        tester,
        entry: HealthV1EntryScreen(
          dogId: 'dog-1',
          source: _FixedSummarySource.single(
            HealthSummaryViewData(dogId: 'dog-1'),
          ),
          timelineSource: recording,
          dogContextOverride: dogContext,
        ),
      );

      final c1 = _requireTimelineController(state);
      final s1 = _requireFilterSession(state);
      final loadsAfterFirst = recording.queries.length;
      expect(loadsAfterFirst, 1);

      await tester.tap(find.text('Resumo'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Histórico'));
      await tester.pumpAndSettle();

      expect(identical(state.timelineControllerForTest, c1), isTrue);
      expect(identical(state.filterSessionForTest, s1), isTrue);
      // Sem second first-load desnecessário.
      expect(recording.queries.length, loadsAfterFirst);
    });
  });

  group('GATE B — First load único', () {
    testWidgets('lazy: 0 loads antes da aba; 1 ao abrir', (tester) async {
      final recording = _RecordingSource(
        CoexistenceHealthTimelineSourceFactory.forReaders([
          MemoryTimelineSourceReader(sourceKey: 'b', items: const []),
        ]),
      );
      await setPhoneSurface(tester);
      await tester.pumpWidget(
        wrap(
          HealthV1EntryScreen(
            dogId: 'dog-1',
            source: _FixedSummarySource.single(
              HealthSummaryViewData(dogId: 'dog-1'),
            ),
            timelineSource: recording,
            dogContextOverride: dogContext,
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 40));
      expect(recording.queries, isEmpty);

      await tester.tap(find.text('Histórico'));
      await tester.pumpAndSettle();
      expect(recording.queries, hasLength(1));
      expect(recording.queries.single.dogId, 'dog-1');
    });
  });

  group('GATE C — Estado entre abas', () {
    testWidgets('filtros preservados ao voltar do Resumo', (tester) async {
      final recording = _RecordingSource(
        CoexistenceHealthTimelineSourceFactory.forReaders([
          MemoryTimelineSourceReader(
            sourceKey: 'c',
            items: [
              _e(
                id: 'w1',
                at: DateTime.utc(2026, 5, 10),
                type: HealthTimelineType.weight,
              ),
              _e(
                id: 'c1',
                at: DateTime.utc(2026, 5, 9),
                type: HealthTimelineType.consultation,
                sourceType: 'health_events',
                sourceId: 'h1',
              ),
            ],
          ),
        ]),
      );
      final state = await openHistorico(
        tester,
        entry: HealthV1EntryScreen(
          dogId: 'dog-1',
          source: _FixedSummarySource.single(
            HealthSummaryViewData(dogId: 'dog-1'),
          ),
          timelineSource: recording,
          dogContextOverride: dogContext,
        ),
      );

      final filterSession = _requireFilterSession(state);
      await filterSession.applyQuickType(HealthTimelineType.weight);
      await tester.pumpAndSettle();
      expect(filterSession.applied.types, {HealthTimelineType.weight});

      await tester.tap(find.text('Resumo'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Histórico'));
      await tester.pumpAndSettle();

      expect(filterSession.applied.types, {HealthTimelineType.weight});
      expect(find.text('Item w1'), findsOneWidget);
      expect(find.text('Item c1'), findsNothing);
    });
  });

  group('GATE D — Dog change', () {
    testWidgets('A→B isola query e remove itens A', (tester) async {
      final items = [
        _e(
          id: 'a1',
          dogId: 'dog-A',
          at: DateTime.utc(2026, 5, 10),
          type: HealthTimelineType.weight,
        ),
        _e(
          id: 'b1',
          dogId: 'dog-B',
          at: DateTime.utc(2026, 5, 10),
          type: HealthTimelineType.weight,
        ),
      ];
      final recording = _RecordingSource(
        CoexistenceHealthTimelineSourceFactory.forReaders([
          MemoryTimelineSourceReader(sourceKey: 'd', items: items),
        ]),
      );

      await setPhoneSurface(tester);
      await tester.pumpWidget(
        wrap(
          HealthV1EntryScreen(
            key: const ValueKey('stable'),
            dogId: 'dog-A',
            source: _FixedSummarySource({
              'dog-A': HealthSummaryViewData(dogId: 'dog-A'),
              'dog-B': HealthSummaryViewData(dogId: 'dog-B'),
            }),
            timelineSource: recording,
            dogContextOverride: HealthSummaryDogContextView(
              dogId: 'dog-A',
              name: 'Alpha',
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.tap(find.text('Histórico'));
      await tester.pumpAndSettle();
      expect(find.text('Item a1'), findsOneWidget);

      await tester.pumpWidget(
        wrap(
          HealthV1EntryScreen(
            key: const ValueKey('stable'),
            dogId: 'dog-B',
            source: _FixedSummarySource({
              'dog-A': HealthSummaryViewData(dogId: 'dog-A'),
              'dog-B': HealthSummaryViewData(dogId: 'dog-B'),
            }),
            timelineSource: recording,
            dogContextOverride: HealthSummaryDogContextView(
              dogId: 'dog-B',
              name: 'Bravo',
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final state = tester.state<HealthV1EntryScreenState>(
        find.byType(HealthV1EntryScreen),
      );
      final controller = _requireTimelineController(state);
      expect(controller.activeDogId, 'dog-B');
      expect(find.text('Item a1'), findsNothing);
      expect(find.text('Item b1'), findsOneWidget);
      expect(recording.queries.last.dogId, 'dog-B');
    });
  });

  group('GATE E — Filters reais', () {
    testWidgets('quick Pesagens → types weight', (tester) async {
      final recording = _RecordingSource(
        CoexistenceHealthTimelineSourceFactory.forReaders([
          MemoryTimelineSourceReader(
            sourceKey: 'e',
            items: [
              _e(
                id: 'w',
                at: DateTime.utc(2026, 5, 1),
                type: HealthTimelineType.weight,
              ),
              _e(
                id: 'c',
                at: DateTime.utc(2026, 5, 2),
                type: HealthTimelineType.consultation,
                sourceType: 'health_events',
                sourceId: 'h',
              ),
            ],
          ),
        ]),
      );
      final state = await openHistorico(
        tester,
        entry: HealthV1EntryScreen(
          dogId: 'dog-1',
          source: _FixedSummarySource.single(
            HealthSummaryViewData(dogId: 'dog-1'),
          ),
          timelineSource: recording,
          dogContextOverride: dogContext,
        ),
      );

      final filterSession = _requireFilterSession(state);
      await filterSession.applyQuickType(HealthTimelineType.weight);
      await tester.pumpAndSettle();
      final q = recording.queries.last;
      expect(q.types, {HealthTimelineType.weight});
      expect(find.text('Item w'), findsOneWidget);
      expect(find.text('Item c'), findsNothing);
    });

    testWidgets('advanced weight+exam + 30d + clear', (tester) async {
      final recording = _RecordingSource(
        CoexistenceHealthTimelineSourceFactory.forReaders([
          MemoryTimelineSourceReader(sourceKey: 'e2', items: const []),
        ]),
      );
      final state = await openHistorico(
        tester,
        entry: HealthV1EntryScreen(
          dogId: 'dog-1',
          source: _FixedSummarySource.single(
            HealthSummaryViewData(dogId: 'dog-1'),
          ),
          timelineSource: recording,
          dogContextOverride: dogContext,
        ),
      );

      final filterSession = _requireFilterSession(state);
      final now = DateTime(2026, 5, 15, 12);
      filterSession.openDraft();
      filterSession.setDraftTypes({
        HealthTimelineType.weight,
        HealthTimelineType.exam,
      });
      filterSession.setDraftPeriod(
        HealthTimelinePeriodPresets.resolve(
          HealthTimelinePeriodPreset.days30,
          now: now,
        ),
        origin: HealthTimelinePeriodPreset.days30,
      );
      await filterSession.apply();
      await tester.pumpAndSettle();

      final q = recording.queries.last;
      expect(q.types, {HealthTimelineType.weight, HealthTimelineType.exam});
      expect(q.period.isUnbounded, isFalse);

      await filterSession.clearApplied();
      await tester.pumpAndSettle();
      final cleared = recording.queries.last;
      expect(cleared.types, isEmpty);
      expect(cleared.period.isUnbounded, isTrue);
    });
  });

  group('GATE F — Navegação real', () {
    testWidgets('weight/nutrition/vaccination targets', (tester) async {
      final items = [
        _e(
          id: 'weight_records:w1',
          at: DateTime.utc(2026, 5, 10),
          type: HealthTimelineType.weight,
          sourceType: 'weight_records',
          sourceId: 'w1',
        ),
        _e(
          id: 'vacinas:v1',
          at: DateTime.utc(2026, 5, 9),
          type: HealthTimelineType.vaccination,
          sourceType: 'vacinas',
          sourceId: 'v1',
        ),
        _e(
          id: 'feeding_events:f1',
          at: DateTime.utc(2026, 5, 8),
          type: HealthTimelineType.meal,
          sourceType: 'feeding_events',
          sourceId: 'f1',
        ),
      ];
      final navigated = <HealthTimelineDetailTarget>[];
      await openHistorico(
        tester,
        entry: HealthV1EntryScreen(
          dogId: 'dog-1',
          source: _FixedSummarySource.single(
            HealthSummaryViewData(dogId: 'dog-1'),
          ),
          timelineSource: CoexistenceHealthTimelineSourceFactory.forReaders([
            MemoryTimelineSourceReader(sourceKey: 'f', items: items),
          ]),
          dogContextOverride: dogContext,
          onTimelineNavigate: (t) async => navigated.add(t),
        ),
      );

      await tester.tap(find.text('Item weight_records:w1'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Item vacinas:v1'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Item feeding_events:f1'));
      await tester.pumpAndSettle();

      expect(navigated, hasLength(3));
      expect(navigated[0], isA<WeightHistoryTarget>());
      expect(navigated[1], isA<VaccinationHistoryTarget>());
      expect(navigated[2], isA<NutritionHistoryTarget>());
      expect(navigated.every((t) => t.dogId == 'dog-1'), isTrue);
    });
  });

  group('GATE G — Unsupported', () {
    testWidgets('health_events não navega', (tester) async {
      final navigated = <HealthTimelineDetailTarget>[];
      await openHistorico(
        tester,
        entry: HealthV1EntryScreen(
          dogId: 'dog-1',
          source: _FixedSummarySource.single(
            HealthSummaryViewData(dogId: 'dog-1'),
          ),
          timelineSource: CoexistenceHealthTimelineSourceFactory.forReaders([
            MemoryTimelineSourceReader(
              sourceKey: 'g',
              items: [
                _e(
                  id: 'health_events:h1',
                  at: DateTime.utc(2026, 5, 9),
                  type: HealthTimelineType.consultation,
                  sourceType: 'health_events',
                  sourceId: 'h1',
                ),
              ],
            ),
          ]),
          dogContextOverride: dogContext,
          onTimelineNavigate: (t) async => navigated.add(t),
        ),
      );

      await tester.tap(find.text('Item health_events:h1'));
      await tester.pumpAndSettle();
      expect(navigated, isEmpty);
    });
  });

  group('GATE H — Lifecycle dispose async', () {
    testWidgets('dispose durante load sem crash', (tester) async {
      final gate = Completer<void>();
      final source = _GatedSource(
        CoexistenceHealthTimelineSourceFactory.forReaders([
          MemoryTimelineSourceReader(sourceKey: 'h', items: const []),
        ]),
      )..blockNext = true;

      await setPhoneSurface(tester);
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
      await tester.pump();
      await source.waitEntered();

      final timelineState = tester.state<HealthV1EntryScreenState>(
        find.byType(HealthV1EntryScreen),
      );
      final timeline = _requireTimelineController(timelineState);

      await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
      await tester.pump();
      expect(timeline.isDisposedForTest, isTrue);

      source.release();
      gate.complete();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 20));
    });
  });

  group('GATE I — Failure semantics', () {
    testWidgets('error genérico', (tester) async {
      await openHistorico(
        tester,
        entry: HealthV1EntryScreen(
          dogId: 'dog-1',
          source: _FixedSummarySource.single(
            HealthSummaryViewData(dogId: 'dog-1'),
          ),
          timelineSource: _FailSource(isOffline: false, message: 'boom'),
          dogContextOverride: dogContext,
        ),
      );
      final state = tester.state<HealthV1EntryScreenState>(
        find.byType(HealthV1EntryScreen),
      );
      final controller = _requireTimelineController(state);
      expect(controller.state, isA<HealthTimelineError>());
    });

    testWidgets('offline distinto', (tester) async {
      await openHistorico(
        tester,
        entry: HealthV1EntryScreen(
          dogId: 'dog-1',
          source: _FixedSummarySource.single(
            HealthSummaryViewData(dogId: 'dog-1'),
          ),
          timelineSource: _FailSource(isOffline: true),
          dogContextOverride: dogContext,
        ),
      );
      final state = tester.state<HealthV1EntryScreenState>(
        find.byType(HealthV1EntryScreen),
      );
      final controller = _requireTimelineController(state);
      expect(controller.state, isA<HealthTimelineOffline>());
    });
  });

  group('GATE J — Pagination', () {
    testWidgets('loadMore página 2 sem duplicar', (tester) async {
      final items = [
        for (var i = 0; i < 4; i++)
          _e(
            id: 'p$i',
            at: DateTime.utc(2026, 5, 10 - i),
            type: HealthTimelineType.weight,
            sourceId: 'p$i',
          ),
      ];
      final paged = _PagedSource(items);

      await setPhoneSurface(tester);
      await tester.pumpWidget(
        wrap(
          HealthV1EntryScreen(
            dogId: 'dog-1',
            source: _FixedSummarySource.single(
              HealthSummaryViewData(dogId: 'dog-1'),
            ),
            timelineSource: paged,
            dogContextOverride: dogContext,
          ),
        ),
      );
      await tester.pump();

      // pageSize default 20 would load all — force small page via prime+setQuery.
      final state = tester.state<HealthV1EntryScreenState>(
        find.byType(HealthV1EntryScreen),
      );
      final filterSession = _requireFilterSession(state);
      final controller = _requireTimelineController(state);
      filterSession.updatePageSize(2);
      await tester.tap(find.text('Histórico'));
      // After prime selectDog uses default pageSize from session constructor (20).
      // Override: apply empty to push pageSize 2.
      await filterSession.clearApplied();
      await tester.pumpAndSettle();

      // Re-set query with pageSize 2 via session update + setQuery path
      await controller.setQuery(
        HealthTimelineQuery(dogId: 'dog-1', pageSize: 2),
      );
      await tester.pumpAndSettle();

      expect(find.text('Item p0'), findsOneWidget);
      expect(find.text('Item p1'), findsOneWidget);
      expect(find.text('Item p2'), findsNothing);

      await controller.loadMore();
      await tester.pumpAndSettle();

      expect(find.text('Item p0'), findsOneWidget);
      expect(find.text('Item p2'), findsOneWidget);
      expect(find.text('Item p3'), findsOneWidget);
      // sem duplicata do primeiro
      expect(find.text('Item p0'), findsOneWidget);
    });
  });

  group('GATE K — Race loadMore + filter', () {
    testWidgets('filtro novo descarta página antiga em voo', (tester) async {
      final items = [
        _e(
          id: 'w1',
          at: DateTime.utc(2026, 5, 10),
          type: HealthTimelineType.weight,
        ),
        _e(
          id: 'c1',
          at: DateTime.utc(2026, 5, 9),
          type: HealthTimelineType.consultation,
          sourceType: 'health_events',
          sourceId: 'h1',
        ),
      ];
      final inner = CoexistenceHealthTimelineSourceFactory.forReaders([
        MemoryTimelineSourceReader(sourceKey: 'k', items: items),
      ]);
      final gated = _GatedSource(inner);

      final state = await openHistorico(
        tester,
        entry: HealthV1EntryScreen(
          dogId: 'dog-1',
          source: _FixedSummarySource.single(
            HealthSummaryViewData(dogId: 'dog-1'),
          ),
          timelineSource: gated,
          dogContextOverride: dogContext,
        ),
      );

      // Bloqueia próximo load (loadMore simulado via setQuery).
      gated.blockNext = true;
      final filterSession = _requireFilterSession(state);
      final controller = _requireTimelineController(state);
      // ignore: discarded_futures
      final pending = controller.setQuery(
        HealthTimelineQuery(dogId: 'dog-1', types: {HealthTimelineType.weight}),
      );
      await gated.waitEntered();

      // Filtro “rápido” vence com exam (query nova libera gate desligado).
      gated.blockNext = false;
      await filterSession.applyQuickType(HealthTimelineType.exam);
      await tester.pumpAndSettle();

      gated.release();
      await pending;
      await tester.pumpAndSettle();

      final active = controller.activeQuery;
      expect(active?.types, {HealthTimelineType.exam});
      // Itens weight da query antiga não devem dominar se filter exam venceu.
      expect(find.text('Item w1'), findsNothing);
    });
  });

  group('GATE L — Shell coexistence', () {
    testWidgets('Resumo continua após Histórico', (tester) async {
      await openHistorico(
        tester,
        entry: HealthV1EntryScreen(
          dogId: 'dog-1',
          source: _FixedSummarySource.single(
            HealthSummaryViewData(dogId: 'dog-1'),
          ),
          timelineSource: CoexistenceHealthTimelineSourceFactory.forReaders([
            MemoryTimelineSourceReader(sourceKey: 'l', items: const []),
          ]),
          dogContextOverride: dogContext,
        ),
      );

      final state = tester.state<HealthV1EntryScreenState>(
        find.byType(HealthV1EntryScreen),
      );
      final timeline = _requireTimelineController(state);

      await tester.tap(find.text('Resumo'));
      await tester.pumpAndSettle();
      expect(find.byType(HealthSummaryDashboard), findsOneWidget);
      expect(find.text('Rex'), findsWidgets);
      // IndexedStack pode deixar a aba offstage; controller permanece o mesmo.
      expect(
        find.byType(HealthTimelineScreen, skipOffstage: false),
        findsOneWidget,
      );
      expect(identical(state.timelineControllerForTest, timeline), isTrue);
      expect(state.timelinePrimedForTest, isTrue);
    });
  });

  group('GATE — Bottom padding / FAB clearance', () {
    testWidgets('bottomPadding usa MainRootNavMetrics', (tester) async {
      await openHistorico(
        tester,
        entry: HealthV1EntryScreen(
          dogId: 'dog-1',
          source: _FixedSummarySource.single(
            HealthSummaryViewData(dogId: 'dog-1'),
          ),
          timelineSource: CoexistenceHealthTimelineSourceFactory.forReaders([
            MemoryTimelineSourceReader(sourceKey: 'pad', items: const []),
          ]),
          dogContextOverride: dogContext,
        ),
      );

      final screen = tester.widget<HealthTimelineScreen>(
        find.byType(HealthTimelineScreen),
      );
      final expected = MainRootNavMetrics.scrollBottomClearance(
        systemBottomInset: 0,
      );
      expect(screen.bottomPadding, expected);
      expect(
        screen.bottomPadding,
        greaterThanOrEqualTo(MainRootNavMetrics.barContentHeight),
      );
    });
  });

  group('GATE — Dog change + navegação', () {
    testWidgets('após A→B naviga com dogId B', (tester) async {
      final navigated = <HealthTimelineDetailTarget>[];
      final items = [
        _e(
          id: 'a:w',
          dogId: 'dog-A',
          at: DateTime.utc(2026, 5, 10),
          type: HealthTimelineType.weight,
          sourceType: 'weight_records',
          sourceId: 'wa',
        ),
        _e(
          id: 'b:w',
          dogId: 'dog-B',
          at: DateTime.utc(2026, 5, 10),
          type: HealthTimelineType.weight,
          sourceType: 'weight_records',
          sourceId: 'wb',
        ),
      ];

      await setPhoneSurface(tester);
      await tester.pumpWidget(
        wrap(
          HealthV1EntryScreen(
            key: const ValueKey('nav-dog'),
            dogId: 'dog-A',
            source: _FixedSummarySource({
              'dog-A': HealthSummaryViewData(dogId: 'dog-A'),
              'dog-B': HealthSummaryViewData(dogId: 'dog-B'),
            }),
            timelineSource: CoexistenceHealthTimelineSourceFactory.forReaders([
              MemoryTimelineSourceReader(sourceKey: 'n', items: items),
            ]),
            dogContextOverride: HealthSummaryDogContextView(
              dogId: 'dog-A',
              name: 'Alpha',
            ),
            onTimelineNavigate: (t) async => navigated.add(t),
          ),
        ),
      );
      await tester.pump();
      await tester.tap(find.text('Histórico'));
      await tester.pumpAndSettle();

      await tester.pumpWidget(
        wrap(
          HealthV1EntryScreen(
            key: const ValueKey('nav-dog'),
            dogId: 'dog-B',
            source: _FixedSummarySource({
              'dog-A': HealthSummaryViewData(dogId: 'dog-A'),
              'dog-B': HealthSummaryViewData(dogId: 'dog-B'),
            }),
            timelineSource: CoexistenceHealthTimelineSourceFactory.forReaders([
              MemoryTimelineSourceReader(sourceKey: 'n', items: items),
            ]),
            dogContextOverride: HealthSummaryDogContextView(
              dogId: 'dog-B',
              name: 'Bravo',
            ),
            onTimelineNavigate: (t) async => navigated.add(t),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Item b:w'));
      await tester.pumpAndSettle();
      expect(navigated, hasLength(1));
      expect(navigated.single.dogId, 'dog-B');
      expect(navigated.single, isA<WeightHistoryTarget>());
    });
  });

  group('GATE — UI presence', () {
    testWidgets(
      'TimelineScreen + quick chips + título sem Bono hardcoded prod',
      (tester) async {
        await openHistorico(
          tester,
          entry: HealthV1EntryScreen(
            dogId: 'dog-1',
            source: _FixedSummarySource.single(
              HealthSummaryViewData(dogId: 'dog-1'),
            ),
            timelineSource: CoexistenceHealthTimelineSourceFactory.forReaders([
              MemoryTimelineSourceReader(sourceKey: 'ui', items: const []),
            ]),
            dogContextOverride: dogContext,
          ),
        );
        expect(find.byType(HealthTimelineScreen), findsOneWidget);
        expect(find.byType(HealthTimelineQuickTypeChips), findsOneWidget);
        expect(find.text(HealthTimelineUserCopy.title), findsOneWidget);
        expect(find.textContaining('Rex'), findsWidgets);
      },
    );
  });
}
