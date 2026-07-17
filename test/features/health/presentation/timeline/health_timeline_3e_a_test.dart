import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:canil_gcm/features/health/data/coexistence/timeline/coexistence_health_timeline_source.dart';
import 'package:canil_gcm/features/health/data/coexistence/timeline/memory_timeline_source_reader.dart';
import 'package:canil_gcm/features/health/domain/health_v1_enums_ext.dart';
import 'package:canil_gcm/features/health/presentation/timeline/detail/health_timeline_detail_target.dart';
import 'package:canil_gcm/features/health/presentation/timeline/filters/health_timeline_filter_session.dart';
import 'package:canil_gcm/features/health/presentation/timeline/filters/health_timeline_period_preset.dart';
import 'package:canil_gcm/features/health/presentation/timeline/filters/health_timeline_quick_type_chips.dart';
import 'package:canil_gcm/features/health/presentation/timeline/health_timeline_controller.dart';
import 'package:canil_gcm/features/health/presentation/timeline/health_timeline_entry_view.dart';
import 'package:canil_gcm/features/health/presentation/timeline/health_timeline_query.dart';
import 'package:canil_gcm/features/health/presentation/timeline/health_timeline_screen.dart';
import 'package:canil_gcm/features/health/presentation/timeline/models/health_timeline_detail_reference.dart';
import 'package:canil_gcm/features/health/presentation/timeline/widgets/health_timeline_user_copy.dart';

HealthTimelineEntryView _e({
  required String id,
  required DateTime at,
  HealthTimelineType type = HealthTimelineType.consultation,
  HealthTimelineDetailReference? detail,
}) {
  return HealthTimelineEntryView(
    id: id,
    dogId: 'dog-a',
    type: HealthTimelineTypeView.known(type),
    occurredAt: at,
    recordedAt: at,
    title: 'Item $id',
    status: HealthTimelineEntryStatus.finalised,
    detailReference: detail,
  );
}

Future<
  ({HealthTimelineController controller, HealthTimelineFilterSession session})
>
_boot(WidgetTester tester, {List<HealthTimelineEntryView>? items}) async {
  final list =
      items ??
      [
        _e(
          id: 'weight_records:w1',
          at: DateTime.utc(2026, 5, 10),
          type: HealthTimelineType.weight,
          detail: const HealthTimelineDetailReference(
            sourceType: 'weight_records',
            sourceId: 'w1',
          ),
        ),
        _e(
          id: 'health_events:h1',
          at: DateTime.utc(2026, 5, 9),
          type: HealthTimelineType.consultation,
          detail: const HealthTimelineDetailReference(
            sourceType: 'health_events',
            sourceId: 'h1',
          ),
        ),
      ];
  final source = CoexistenceHealthTimelineSourceFactory.forReaders([
    MemoryTimelineSourceReader(sourceKey: 'mix', items: list),
  ]);
  final controller = HealthTimelineController(source: source);
  final session = HealthTimelineFilterSession(
    controller: controller,
    dogId: 'dog-a',
    now: () => DateTime(2026, 5, 15, 12),
  );
  await controller.setQuery(HealthTimelineQuery(dogId: 'dog-a'));
  return (controller: controller, session: session);
}

void main() {
  group('GATE A/B — quick filters', () {
    test('Pesagens aplica só types weight e preserva period', () async {
      final source = CoexistenceHealthTimelineSourceFactory.forReaders([
        MemoryTimelineSourceReader(
          sourceKey: 'a',
          items: [
            _e(
              id: 'a:1',
              at: DateTime.utc(2026, 5, 1),
              type: HealthTimelineType.weight,
            ),
            _e(
              id: 'a:2',
              at: DateTime.utc(2026, 5, 2),
              type: HealthTimelineType.consultation,
            ),
          ],
        ),
      ]);
      final controller = HealthTimelineController(source: source);
      addTearDown(controller.dispose);
      final session = HealthTimelineFilterSession(
        controller: controller,
        dogId: 'dog-a',
        now: () => DateTime(2026, 5, 15),
      );
      final period = HealthTimelinePeriodPresets.resolve(
        HealthTimelinePeriodPreset.days30,
        now: DateTime(2026, 5, 15),
      );
      session.openDraft();
      session.setDraftPeriod(period, origin: HealthTimelinePeriodPreset.days30);
      await session.apply();

      await session.applyQuickType(HealthTimelineType.weight);
      expect(session.applied.types, {HealthTimelineType.weight});
      expect(session.applied.hasPeriod, isTrue);
      expect(session.isQuickTypeSelected(HealthTimelineType.weight), isTrue);
    });

    test('Todos limpa types e preserva período', () async {
      final source = CoexistenceHealthTimelineSourceFactory.forReaders([
        MemoryTimelineSourceReader(
          sourceKey: 'a',
          items: [_e(id: 'a:1', at: DateTime.utc(2026, 5, 1))],
        ),
      ]);
      final controller = HealthTimelineController(source: source);
      addTearDown(controller.dispose);
      final session = HealthTimelineFilterSession(
        controller: controller,
        dogId: 'dog-a',
        now: () => DateTime(2026, 5, 15),
      );
      final period = HealthTimelinePeriodPresets.resolve(
        HealthTimelinePeriodPreset.days30,
        now: DateTime(2026, 5, 15),
      );
      session.openDraft();
      session.setDraftPeriod(period, origin: HealthTimelinePeriodPreset.days30);
      session.setDraftTypes({HealthTimelineType.weight});
      await session.apply();

      await session.applyQuickAllTypes();
      expect(session.applied.types, isEmpty);
      expect(session.applied.hasPeriod, isTrue);
      expect(session.isQuickAllSelected, isTrue);
    });
  });

  group('GATE C — multi-type avançado', () {
    test('faixa rápida não seleciona tipo único enganoso', () async {
      final source = CoexistenceHealthTimelineSourceFactory.forReaders([
        MemoryTimelineSourceReader(
          sourceKey: 'a',
          items: [_e(id: 'a:1', at: DateTime.utc(2026, 5, 1))],
        ),
      ]);
      final controller = HealthTimelineController(source: source);
      addTearDown(controller.dispose);
      final session = HealthTimelineFilterSession(
        controller: controller,
        dogId: 'dog-a',
        now: () => DateTime(2026, 5, 1),
      );
      session.openDraft();
      session.setDraftTypes({
        HealthTimelineType.weight,
        HealthTimelineType.exam,
      });
      await session.apply();
      expect(session.hasAdvancedMultiTypeSelection, isTrue);
      expect(session.isQuickTypeSelected(HealthTimelineType.weight), isFalse);
      expect(session.isQuickAllSelected, isFalse);
    });
  });

  group('GATE D/E — screen composition', () {
    testWidgets('relatedHistory semantics + unsupported sem tap', (
      tester,
    ) async {
      final boot = await _boot(tester);
      addTearDown(boot.controller.dispose);
      final navigated = <HealthTimelineDetailTarget>[];

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: HealthTimelineScreen(
              controller: boot.controller,
              filterSession: boot.session,
              dogDisplayName: 'Bono',
              now: () => DateTime(2026, 5, 15, 12),
              onNavigate: (t) async => navigated.add(t),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text(HealthTimelineUserCopy.title), findsOneWidget);
      expect(find.text('Todos'), findsOneWidget);
      expect(find.text('Pesagens'), findsOneWidget);

      // Sem busca / KPI
      expect(find.byType(TextField), findsNothing);
      expect(find.text('Consultas'), findsWidgets); // chip rápido, não KPI card
      expect(find.textContaining('Em dia'), findsNothing);
      expect(find.textContaining('Alertas'), findsNothing);

      await tester.tap(find.text('Item weight_records:w1'));
      await tester.pumpAndSettle();
      expect(navigated, hasLength(1));
      expect(navigated.single, isA<WeightHistoryTarget>());
      expect(navigated.single.navigationActionLabel, 'Abrir histórico de peso');

      navigated.clear();
      await tester.tap(find.text('Item health_events:h1'));
      await tester.pumpAndSettle();
      expect(navigated, isEmpty);
    });
  });

  group('GATE F — footer institucional', () {
    testWidgets('footer só quando hasMore false', (tester) async {
      final items = [
        for (var i = 0; i < 5; i++)
          _e(
            id: 'a:$i',
            at: DateTime.utc(2026, 5, 1).add(Duration(hours: i)),
          ),
      ];
      final boot = await _boot(tester, items: items);
      addTearDown(boot.controller.dispose);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: HealthTimelineScreen(
              controller: boot.controller,
              filterSession: boot.session,
              dogDisplayName: 'Bono',
              now: () => DateTime(2026, 5, 15),
              onNavigate: (_) async {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // pageSize default 20, 5 items → hasMore false
      // Footer fica no fim do scroll (não rouba viewport dos cards).
      await tester.drag(find.byType(Scrollable).last, const Offset(0, -400));
      await tester.pumpAndSettle();
      expect(find.textContaining('rastreabilidade de origem'), findsOneWidget);
      expect(find.textContaining('Bono'), findsWidgets);
    });
  });

  group('GATE G/H — sem busca / sem KPI cards', () {
    testWidgets('quick chips presentes, search ausente', (tester) async {
      final boot = await _boot(tester);
      addTearDown(boot.controller.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: HealthTimelineScreen(
              controller: boot.controller,
              filterSession: boot.session,
              onNavigate: (_) async {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(HealthTimelineQuickTypeChips), findsOneWidget);
      expect(find.byType(TextField), findsNothing);
      expect(find.byType(SearchBar), findsNothing);
    });
  });

  group('GATE J — responsividade', () {
    testWidgets('360 sem overflow', (tester) async {
      final boot = await _boot(tester);
      addTearDown(boot.controller.dispose);
      await tester.binding.setSurfaceSize(const Size(360, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: HealthTimelineScreen(
              controller: boot.controller,
              filterSession: boot.session,
              dogDisplayName: 'Bono',
              onNavigate: (_) async {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  });
}
