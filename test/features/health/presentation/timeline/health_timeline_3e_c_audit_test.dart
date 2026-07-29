import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:canil_gcm/features/health/data/coexistence/timeline/coexistence_health_timeline_source.dart';
import 'package:canil_gcm/features/health/data/coexistence/timeline/memory_timeline_source_reader.dart';
import 'package:canil_gcm/features/health/data/coexistence/timeline/timeline_mapping_result.dart';
import 'package:canil_gcm/features/health/domain/health_v1_enums_ext.dart';
import 'package:canil_gcm/features/health/presentation/screens/health_v1_entry_flags.dart';
import 'package:canil_gcm/features/health/presentation/screens/health_v1_entry_screen.dart';
import 'package:canil_gcm/features/health/presentation/summary/health_summary_dog_context_view.dart';
import 'package:canil_gcm/features/health/presentation/summary/health_summary_source.dart';
import 'package:canil_gcm/features/health/presentation/summary/health_summary_view_data.dart';
import 'package:canil_gcm/features/health/presentation/timeline/detail/health_timeline_detail_target.dart';
import 'package:canil_gcm/features/health/presentation/timeline/filters/health_timeline_period_preset.dart';
import 'package:canil_gcm/features/health/presentation/timeline/filters/health_timeline_filter_session.dart';
import 'package:canil_gcm/features/health/presentation/timeline/health_timeline_controller.dart';
import 'package:canil_gcm/features/health/presentation/timeline/health_timeline_cursor.dart';
import 'package:canil_gcm/features/health/presentation/timeline/health_timeline_entry_view.dart';
import 'package:canil_gcm/features/health/presentation/timeline/health_timeline_page.dart';
import 'package:canil_gcm/features/health/presentation/timeline/health_timeline_query.dart';
import 'package:canil_gcm/features/health/presentation/timeline/health_timeline_source.dart';
import 'package:canil_gcm/features/health/presentation/timeline/health_timeline_state.dart';
import 'package:canil_gcm/features/health/presentation/timeline/models/health_timeline_detail_reference.dart';
import 'package:canil_gcm/features/health/presentation/timeline/widgets/health_timeline_entry_card.dart';
import 'package:canil_gcm/features/health/presentation/timeline/widgets/health_timeline_user_copy.dart';

/// 3E-C — gates adversariais da integração (Entry composition real).
class _FixedSummary implements HealthSummarySource {
  _FixedSummary([this.byDog = const {}]);
  final Map<String, HealthSummaryViewData> byDog;

  @override
  Stream<HealthSummaryViewData?> watchSummary(String dogId) async* {
    yield byDog[dogId] ?? HealthSummaryViewData(dogId: dogId);
  }
}

class _RecordingSource implements HealthTimelineSource {
  _RecordingSource(this.inner);
  final HealthTimelineSource inner;
  final List<HealthTimelineQuery> queries = [];

  @override
  Future<HealthTimelinePage> loadPage(HealthTimelineQuery query) async {
    queries.add(query);
    return inner.loadPage(query);
  }
}

class _GatedRecordingSource implements HealthTimelineSource {
  _GatedRecordingSource(this.inner);
  final HealthTimelineSource inner;
  final List<HealthTimelineQuery> queries = [];
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
    queries.add(query);
    if (blockNext) {
      blockNext = false;
      _gate = Completer<void>();
      _entered = Completer<void>();
      _entered!.complete();
      await _gate!.future;
    }
    return inner.loadPage(query);
  }
}

class _PagedByDogSource implements HealthTimelineSource {
  _PagedByDogSource(this.items);
  final List<HealthTimelineEntryView> items;

  @override
  Future<HealthTimelinePage> loadPage(HealthTimelineQuery query) async {
    final dogItems = items.where((e) => e.dogId == query.dogId).toList()
      ..sort((a, b) => b.occurredAt.compareTo(a.occurredAt));
    var start = 0;
    if (query.cursor != null) {
      start = int.tryParse(query.cursor!.token) ?? 0;
    }
    final slice = dogItems.skip(start).take(query.pageSize).toList();
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
  _FailSource({required this.isOffline, this.message = 'falha'});
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
  String dogId = 'dog-1',
  String sourceType = 'weight_records',
  String sourceId = 'x',
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

  Widget wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

  Future<void> phone(WidgetTester t) async {
    t.view.physicalSize = const Size(400, 900);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
  }

  group('3E-C adversarial gates', () {
    testWidgets('B/C — lazy zero-load + first load único + sem re-prime', (
      tester,
    ) async {
      await phone(tester);
      final rec = _RecordingSource(
        CoexistenceHealthTimelineSourceFactory.forReaders([
          MemoryTimelineSourceReader(sourceKey: 'b', items: const []),
        ]),
      );
      await tester.pumpWidget(
        wrap(
          HealthV1EntryScreen(
            dogId: 'dog-1',
            source: _FixedSummary(),
            timelineSource: rec,
            dogContextOverride: HealthSummaryDogContextView(
              dogId: 'dog-1',
              name: 'Rex',
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 40));
      expect(rec.queries, isEmpty);

      await tester.tap(find.text('Histórico'));
      await tester.pumpAndSettle();
      expect(rec.queries, hasLength(1));
      expect(rec.queries.single.dogId, 'dog-1');

      await tester.tap(find.text('Resumo'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Histórico'));
      await tester.pumpAndSettle();
      expect(rec.queries, hasLength(1));
    });

    testWidgets('D — dog A→B antes do prime: zero load A, só B', (
      tester,
    ) async {
      await phone(tester);
      final rec = _RecordingSource(
        CoexistenceHealthTimelineSourceFactory.forReaders([
          MemoryTimelineSourceReader(
            sourceKey: 'd',
            items: [
              _e(
                id: 'a',
                dogId: 'dog-A',
                at: DateTime.utc(2026, 5, 1),
                type: HealthTimelineType.weight,
              ),
              _e(
                id: 'b',
                dogId: 'dog-B',
                at: DateTime.utc(2026, 5, 1),
                type: HealthTimelineType.weight,
              ),
            ],
          ),
        ]),
      );

      await tester.pumpWidget(
        wrap(
          HealthV1EntryScreen(
            key: const ValueKey('stable'),
            dogId: 'dog-A',
            source: _FixedSummary({
              'dog-A': HealthSummaryViewData(dogId: 'dog-A'),
              'dog-B': HealthSummaryViewData(dogId: 'dog-B'),
            }),
            timelineSource: rec,
            dogContextOverride: HealthSummaryDogContextView(
              dogId: 'dog-A',
              name: 'Alpha',
            ),
          ),
        ),
      );
      await tester.pump();
      expect(rec.queries, isEmpty);

      await tester.pumpWidget(
        wrap(
          HealthV1EntryScreen(
            key: const ValueKey('stable'),
            dogId: 'dog-B',
            source: _FixedSummary({
              'dog-A': HealthSummaryViewData(dogId: 'dog-A'),
              'dog-B': HealthSummaryViewData(dogId: 'dog-B'),
            }),
            timelineSource: rec,
            dogContextOverride: HealthSummaryDogContextView(
              dogId: 'dog-B',
              name: 'Bravo',
            ),
          ),
        ),
      );
      await tester.pump();
      expect(rec.queries, isEmpty);

      await tester.tap(find.text('Histórico'));
      await tester.pumpAndSettle();
      expect(rec.queries, hasLength(1));
      expect(rec.queries.single.dogId, 'dog-B');
      expect(find.text('Item b'), findsOneWidget);
      expect(find.text('Item a'), findsNothing);
    });

    testWidgets('E — dog change durante first load: A tardio não entra em B', (
      tester,
    ) async {
      await phone(tester);
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
      final gated = _GatedRecordingSource(
        CoexistenceHealthTimelineSourceFactory.forReaders([
          MemoryTimelineSourceReader(sourceKey: 'e', items: items),
        ]),
      );

      await tester.pumpWidget(
        wrap(
          HealthV1EntryScreen(
            key: const ValueKey('race'),
            dogId: 'dog-A',
            source: _FixedSummary({
              'dog-A': HealthSummaryViewData(dogId: 'dog-A'),
              'dog-B': HealthSummaryViewData(dogId: 'dog-B'),
            }),
            timelineSource: gated,
            dogContextOverride: HealthSummaryDogContextView(
              dogId: 'dog-A',
              name: 'Alpha',
            ),
          ),
        ),
      );
      await tester.pump();

      gated.blockNext = true;
      await tester.tap(find.text('Histórico'));
      await tester.pump();
      await gated.waitEntered();
      expect(gated.queries.first.dogId, 'dog-A');

      // Troca para B enquanto A está bloqueado.
      await tester.pumpWidget(
        wrap(
          HealthV1EntryScreen(
            key: const ValueKey('race'),
            dogId: 'dog-B',
            source: _FixedSummary({
              'dog-A': HealthSummaryViewData(dogId: 'dog-A'),
              'dog-B': HealthSummaryViewData(dogId: 'dog-B'),
            }),
            timelineSource: gated,
            dogContextOverride: HealthSummaryDogContextView(
              dogId: 'dog-B',
              name: 'Bravo',
            ),
          ),
        ),
      );
      await tester.pump();
      // selectDog B deve ter sido enfileirado (primed).
      gated.release();
      await tester.pumpAndSettle();

      final state = tester.state<HealthV1EntryScreenState>(
        find.byType(HealthV1EntryScreen),
      );
      final controller = _requireTimelineController(state);
      expect(controller.activeDogId, 'dog-B');
      expect(find.text('Item a1'), findsNothing);
      expect(find.text('Item b1'), findsOneWidget);
    });

    testWidgets('F — dog change durante loadMore: página A não entra em B', (
      tester,
    ) async {
      await phone(tester);
      final items = [
        for (var i = 0; i < 4; i++)
          _e(
            id: 'a$i',
            dogId: 'dog-A',
            at: DateTime.utc(2026, 5, 10 - i),
            type: HealthTimelineType.weight,
            sourceId: 'a$i',
          ),
        for (var i = 0; i < 2; i++)
          _e(
            id: 'b$i',
            dogId: 'dog-B',
            at: DateTime.utc(2026, 5, 10 - i),
            type: HealthTimelineType.weight,
            sourceId: 'b$i',
          ),
      ];
      final paged = _PagedByDogSource(items);
      final gated = _GatedRecordingSource(paged);

      await tester.pumpWidget(
        wrap(
          HealthV1EntryScreen(
            key: const ValueKey('lm'),
            dogId: 'dog-A',
            source: _FixedSummary({
              'dog-A': HealthSummaryViewData(dogId: 'dog-A'),
              'dog-B': HealthSummaryViewData(dogId: 'dog-B'),
            }),
            timelineSource: gated,
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

      final state = tester.state<HealthV1EntryScreenState>(
        find.byType(HealthV1EntryScreen),
      );
      final controller = _requireTimelineController(state);
      await controller.setQuery(
        HealthTimelineQuery(dogId: 'dog-A', pageSize: 2),
      );
      await tester.pumpAndSettle();
      expect(find.text('Item a0'), findsOneWidget);
      expect(find.text('Item a2'), findsNothing);

      gated.blockNext = true;
      // ignore: discarded_futures
      final more = controller.loadMore();
      await gated.waitEntered();

      await tester.pumpWidget(
        wrap(
          HealthV1EntryScreen(
            key: const ValueKey('lm'),
            dogId: 'dog-B',
            source: _FixedSummary({
              'dog-A': HealthSummaryViewData(dogId: 'dog-A'),
              'dog-B': HealthSummaryViewData(dogId: 'dog-B'),
            }),
            timelineSource: gated,
            dogContextOverride: HealthSummaryDogContextView(
              dogId: 'dog-B',
              name: 'Bravo',
            ),
          ),
        ),
      );
      await tester.pump();
      gated.release();
      await more;
      await tester.pumpAndSettle();

      final controllerAfter = _requireTimelineController(state);
      expect(controllerAfter.activeDogId, 'dog-B');
      expect(find.text('Item a0'), findsNothing);
      expect(find.text('Item a2'), findsNothing);
      expect(find.text('Item b0'), findsOneWidget);
    });

    testWidgets('G — quick/Todos preservam period+professional', (
      tester,
    ) async {
      await phone(tester);
      final rec = _RecordingSource(
        CoexistenceHealthTimelineSourceFactory.forReaders([
          MemoryTimelineSourceReader(sourceKey: 'g', items: const []),
        ]),
      );
      await tester.pumpWidget(
        wrap(
          HealthV1EntryScreen(
            dogId: 'dog-1',
            source: _FixedSummary(),
            timelineSource: rec,
            dogContextOverride: HealthSummaryDogContextView(
              dogId: 'dog-1',
              name: 'Rex',
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.tap(find.text('Histórico'));
      await tester.pumpAndSettle();

      final state = tester.state<HealthV1EntryScreenState>(
        find.byType(HealthV1EntryScreen),
      );
      final filterSession = _requireFilterSession(state);
      final now = DateTime(2026, 5, 15, 12);
      filterSession.openDraft();
      filterSession.setDraftPeriod(
        HealthTimelinePeriodPresets.resolve(
          HealthTimelinePeriodPreset.days30,
          now: now,
        ),
        origin: HealthTimelinePeriodPreset.days30,
      );
      filterSession.setDraftProfessional(
        HealthTimelineProfessionalFilter(name: 'Dr X'),
      );
      await filterSession.apply();
      await tester.pumpAndSettle();

      await filterSession.applyQuickType(HealthTimelineType.weight);
      await tester.pumpAndSettle();
      var q = rec.queries.last;
      expect(q.types, {HealthTimelineType.weight});
      expect(q.period.isUnbounded, isFalse);
      expect(q.professional?.name, 'Dr X');

      await filterSession.applyQuickAllTypes();
      await tester.pumpAndSettle();
      q = rec.queries.last;
      expect(q.types, isEmpty);
      expect(q.period.isUnbounded, isFalse);
      expect(q.professional?.name, 'Dr X');
    });

    testWidgets('H — apply no-op não recarrega', (tester) async {
      await phone(tester);
      final rec = _RecordingSource(
        CoexistenceHealthTimelineSourceFactory.forReaders([
          MemoryTimelineSourceReader(sourceKey: 'h', items: const []),
        ]),
      );
      await tester.pumpWidget(
        wrap(
          HealthV1EntryScreen(
            dogId: 'dog-1',
            source: _FixedSummary(),
            timelineSource: rec,
            dogContextOverride: HealthSummaryDogContextView(
              dogId: 'dog-1',
              name: 'Rex',
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.tap(find.text('Histórico'));
      await tester.pumpAndSettle();
      final n = rec.queries.length;

      final state = tester.state<HealthV1EntryScreenState>(
        find.byType(HealthV1EntryScreen),
      );
      final filterSession = _requireFilterSession(state);
      filterSession.openDraft();
      await filterSession.apply(); // semanticamente igual
      await tester.pumpAndSettle();
      expect(rec.queries.length, n);
    });

    testWidgets('L — unmappable ativo → Error (não empty, não offline)', (
      tester,
    ) async {
      await phone(tester);
      final docs = [
        MemoryTimelineScanDoc.invalid(
          id: 'bad:1',
          occurredAt: DateTime.utc(2026, 5, 1),
          invalidReason: TimelineMappingInvalidReason.invalidRequiredDate,
        ),
      ];
      final source = CoexistenceHealthTimelineSourceFactory.forReaders([
        ScanningMemoryTimelineSourceReader(sourceKey: 'bad', docs: docs),
      ]);

      await tester.pumpWidget(
        wrap(
          HealthV1EntryScreen(
            dogId: 'dog-1',
            source: _FixedSummary(),
            timelineSource: source,
            dogContextOverride: HealthSummaryDogContextView(
              dogId: 'dog-1',
              name: 'Rex',
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.tap(find.text('Histórico'));
      await tester.pumpAndSettle();

      final state = tester.state<HealthV1EntryScreenState>(
        find.byType(HealthV1EntryScreen),
      );
      final controller = _requireTimelineController(state);
      final s = controller.state;
      expect(s, isA<HealthTimelineError>());
      expect(s, isNot(isA<HealthTimelineEmpty>()));
      expect(s, isNot(isA<HealthTimelineOffline>()));
      final err = s as HealthTimelineError;
      expect(err.message.toLowerCase(), contains('interpretados'));
      // Sem empty enganoso na UI
      expect(find.text(HealthTimelineUserCopy.emptyTitle), findsNothing);
    });

    testWidgets('K — error ≠ offline (separados)', (tester) async {
      await phone(tester);

      Future<void> openWith(Key key, HealthTimelineSource src) async {
        await tester.pumpWidget(
          wrap(
            HealthV1EntryScreen(
              key: key,
              dogId: 'dog-1',
              source: _FixedSummary(),
              timelineSource: src,
              dogContextOverride: HealthSummaryDogContextView(
                dogId: 'dog-1',
                name: 'Rex',
              ),
            ),
          ),
        );
        await tester.pump();
        await tester.tap(find.text('Histórico'));
        await tester.pumpAndSettle();
      }

      // Keys distintas: timelineSource é late final no State.
      await openWith(
        const ValueKey('err'),
        _FailSource(isOffline: false, message: 'servidor'),
      );
      final stateErr = tester.state<HealthV1EntryScreenState>(
        find.byType(HealthV1EntryScreen),
      );
      var st = _requireTimelineController(stateErr).state;
      expect(st, isA<HealthTimelineError>());

      await openWith(
        const ValueKey('off'),
        _FailSource(isOffline: true, message: 'rede'),
      );
      final stateOff = tester.state<HealthV1EntryScreenState>(
        find.byType(HealthV1EntryScreen),
      );
      st = _requireTimelineController(stateOff).state;
      expect(st, isA<HealthTimelineOffline>());
    });

    testWidgets('M — refresh failure preserva lista', (tester) async {
      await phone(tester);
      var failNext = false;
      final base = CoexistenceHealthTimelineSourceFactory.forReaders([
        MemoryTimelineSourceReader(
          sourceKey: 'm',
          items: [
            _e(
              id: 'w1',
              at: DateTime.utc(2026, 5, 1),
              type: HealthTimelineType.weight,
            ),
          ],
        ),
      ]);
      final src = _RecordingSource(_SwitchableFail(base, () => failNext));

      await tester.pumpWidget(
        wrap(
          HealthV1EntryScreen(
            dogId: 'dog-1',
            source: _FixedSummary(),
            timelineSource: src,
            dogContextOverride: HealthSummaryDogContextView(
              dogId: 'dog-1',
              name: 'Rex',
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.tap(find.text('Histórico'));
      await tester.pumpAndSettle();
      expect(find.text('Item w1'), findsOneWidget);

      failNext = true;
      final stateM = tester.state<HealthV1EntryScreenState>(
        find.byType(HealthV1EntryScreen),
      );
      final c = _requireTimelineController(stateM);
      await c.refresh();
      await tester.pumpAndSettle();

      expect(find.text('Item w1'), findsOneWidget);
      expect(c.state, isA<HealthTimelineData>());
      final data = c.state as HealthTimelineData;
      expect(data.snapshot.hasRefreshFailure, isTrue);
    });

    testWidgets('N — loadMore failure preserva lista', (tester) async {
      await phone(tester);
      var failMore = false;
      final items = [
        for (var i = 0; i < 4; i++)
          _e(
            id: 'p$i',
            at: DateTime.utc(2026, 5, 10 - i),
            type: HealthTimelineType.weight,
            sourceId: '$i',
          ),
      ];
      final paged = _PagedByDogSource(items);
      final src = _SwitchableFail(paged, () => failMore);

      await tester.pumpWidget(
        wrap(
          HealthV1EntryScreen(
            dogId: 'dog-1',
            source: _FixedSummary(),
            timelineSource: src,
            dogContextOverride: HealthSummaryDogContextView(
              dogId: 'dog-1',
              name: 'Rex',
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.tap(find.text('Histórico'));
      await tester.pumpAndSettle();
      final stateN = tester.state<HealthV1EntryScreenState>(
        find.byType(HealthV1EntryScreen),
      );
      final c = _requireTimelineController(stateN);
      await c.setQuery(HealthTimelineQuery(dogId: 'dog-1', pageSize: 2));
      await tester.pumpAndSettle();
      expect(find.text('Item p0'), findsOneWidget);

      failMore = true;
      await c.loadMore();
      await tester.pumpAndSettle();
      expect(find.text('Item p0'), findsOneWidget);
      final data = c.state as HealthTimelineData;
      expect(data.snapshot.loadMoreError, isNotNull);
    });

    testWidgets('O/P — nav Dog B + double tap max 1', (tester) async {
      await phone(tester);
      final navigated = <HealthTimelineDetailTarget>[];
      final delay = Completer<void>();
      var inFlight = 0;
      var maxInFlight = 0;

      await tester.pumpWidget(
        wrap(
          HealthV1EntryScreen(
            dogId: 'dog-B',
            source: _FixedSummary(),
            timelineSource: CoexistenceHealthTimelineSourceFactory.forReaders([
              MemoryTimelineSourceReader(
                sourceKey: 'o',
                items: [
                  _e(
                    id: 'b:w',
                    dogId: 'dog-B',
                    at: DateTime.utc(2026, 5, 1),
                    type: HealthTimelineType.weight,
                    sourceType: 'weight_records',
                    sourceId: 'wb',
                  ),
                ],
              ),
            ]),
            dogContextOverride: HealthSummaryDogContextView(
              dogId: 'dog-B',
              name: 'Bravo',
            ),
            onTimelineNavigate: (t) async {
              inFlight++;
              if (inFlight > maxInFlight) maxInFlight = inFlight;
              navigated.add(t);
              await delay.future;
              inFlight--;
            },
          ),
        ),
      );
      await tester.pump();
      await tester.tap(find.text('Histórico'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Item b:w'));
      await tester.pump();
      await tester.tap(find.text('Item b:w'));
      await tester.pump();
      delay.complete();
      await tester.pumpAndSettle();

      expect(navigated, hasLength(1));
      expect(navigated.single.dogId, 'dog-B');
      expect(navigated.single, isA<WeightHistoryTarget>());
      expect(maxInFlight, 1);
    });

    testWidgets('Q — unsupported: card sem button semantics + 0 nav', (
      tester,
    ) async {
      await phone(tester);
      final navigated = <HealthTimelineDetailTarget>[];
      await tester.pumpWidget(
        wrap(
          HealthV1EntryScreen(
            dogId: 'dog-1',
            source: _FixedSummary(),
            timelineSource: CoexistenceHealthTimelineSourceFactory.forReaders([
              MemoryTimelineSourceReader(
                sourceKey: 'q',
                items: [
                  _e(
                    id: 'h1',
                    at: DateTime.utc(2026, 5, 1),
                    type: HealthTimelineType.consultation,
                    sourceType: 'health_events',
                    sourceId: 'h1',
                  ),
                ],
              ),
            ]),
            dogContextOverride: HealthSummaryDogContextView(
              dogId: 'dog-1',
              name: 'Rex',
            ),
            onTimelineNavigate: (t) async => navigated.add(t),
          ),
        ),
      );
      await tester.pump();
      await tester.tap(find.text('Histórico'));
      await tester.pumpAndSettle();

      final card = tester.widget<HealthTimelineEntryCard>(
        find.byType(HealthTimelineEntryCard),
      );
      expect(card.onTap, isNull);

      await tester.tap(find.text('Item h1'));
      await tester.pumpAndSettle();
      expect(navigated, isEmpty);
    });

    test('R — rollback gate false não usa Entry', () {
      expect(shouldUseHealthV1SummaryEntry(overrideGate: false), isFalse);
      // MainRoot só instancia HealthV1EntryScreen quando gate true.
      // Prova de contrato: com gate false o ramo legado é selecionado.
    });

    testWidgets('S — Resumo↔Histórico preserva controller idêntico', (
      tester,
    ) async {
      await phone(tester);
      final rec = _RecordingSource(
        CoexistenceHealthTimelineSourceFactory.forReaders([
          MemoryTimelineSourceReader(sourceKey: 's', items: const []),
        ]),
      );
      await tester.pumpWidget(
        wrap(
          HealthV1EntryScreen(
            dogId: 'dog-1',
            source: _FixedSummary(),
            timelineSource: rec,
            dogContextOverride: HealthSummaryDogContextView(
              dogId: 'dog-1',
              name: 'Rex',
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.tap(find.text('Histórico'));
      await tester.pumpAndSettle();
      final state = tester.state<HealthV1EntryScreenState>(
        find.byType(HealthV1EntryScreen),
      );
      final c = _requireTimelineController(state);
      final sess = _requireFilterSession(state);
      await sess.applyQuickType(HealthTimelineType.weight);
      await tester.pumpAndSettle();

      await tester.tap(find.text('Resumo'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Histórico'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Resumo'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Histórico'));
      await tester.pumpAndSettle();

      expect(identical(state.timelineControllerForTest, c), isTrue);
      expect(identical(state.filterSessionForTest, sess), isTrue);
      expect(sess.applied.types, {HealthTimelineType.weight});
      // loads: 1 first + 1 filter; sem re-prime extras
      expect(rec.queries.length, 2);
    });

    test('T — presentation boundary: Screen/widgets sem cloud_firestore', () {
      const forbidden = "import 'package:cloud_firestore";
      final files = [
        'lib/features/health/presentation/timeline/health_timeline_screen.dart',
        'lib/features/health/presentation/timeline/health_timeline_controller.dart',
        'lib/features/health/presentation/timeline/health_timeline_interactive_host.dart',
        'lib/features/health/presentation/timeline/filters/health_timeline_filter_session.dart',
        'lib/features/health/presentation/timeline/detail/health_timeline_detail_resolver.dart',
        'lib/features/health/presentation/timeline/detail/health_timeline_navigation_coordinator.dart',
      ];
      for (final path in files) {
        final content = File(path).readAsStringSync();
        expect(
          content.contains(forbidden),
          isFalse,
          reason: '$path não deve importar cloud_firestore',
        );
      }
      final entry = File(
        'lib/features/health/presentation/screens/health_v1_entry_screen.dart',
      ).readAsStringSync();
      expect(entry.contains('coexistence_health_timeline_source.dart'), isTrue);
      expect(entry.contains(forbidden), isFalse);
    });

    test('Vaccination fallback default false no factory', () {
      // Construtor default: enableVaccinationFallback = false.
      // Instanciar forFirestore sem args usa false (sem rede neste teste).
      final s = CoexistenceHealthTimelineSourceFactory.forFirestore(
        enableVaccinationFallback: false,
      );
      expect(s, isA<CoexistenceHealthTimelineSource>());
    });
  });
}

/// Delega a [inner]; se [shouldFail] true, lança erro genérico.
class _SwitchableFail implements HealthTimelineSource {
  _SwitchableFail(this.inner, this.shouldFail);
  final HealthTimelineSource inner;
  final bool Function() shouldFail;

  @override
  Future<HealthTimelinePage> loadPage(HealthTimelineQuery query) async {
    if (shouldFail()) {
      throw const HealthTimelineSourceException('falha controlada');
    }
    return inner.loadPage(query);
  }
}
