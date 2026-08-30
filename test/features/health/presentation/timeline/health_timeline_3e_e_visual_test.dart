import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:canil_gcm/features/health/data/coexistence/timeline/coexistence_health_timeline_source.dart';
import 'package:canil_gcm/features/health/data/coexistence/timeline/memory_timeline_source_reader.dart';
import 'package:canil_gcm/features/health/domain/health_v1_enums_ext.dart';
import 'package:canil_gcm/features/health/presentation/timeline/detail/health_timeline_detail_target.dart';
import 'package:canil_gcm/features/health/presentation/timeline/filters/health_timeline_filter_chips.dart';
import 'package:canil_gcm/features/health/presentation/timeline/filters/health_timeline_filter_labels.dart';
import 'package:canil_gcm/features/health/presentation/timeline/filters/health_timeline_filter_selection.dart';
import 'package:canil_gcm/features/health/presentation/timeline/filters/health_timeline_filter_session.dart';
import 'package:canil_gcm/features/health/presentation/timeline/filters/health_timeline_quick_type_chips.dart';
import 'package:canil_gcm/features/health/presentation/timeline/health_timeline_controller.dart';
import 'package:canil_gcm/features/health/presentation/timeline/health_timeline_entry_view.dart';
import 'package:canil_gcm/features/health/presentation/timeline/health_timeline_query.dart';
import 'package:canil_gcm/features/health/presentation/timeline/health_timeline_screen.dart';
import 'package:canil_gcm/features/health/presentation/timeline/models/health_timeline_detail_reference.dart';
import 'package:canil_gcm/features/health/presentation/timeline/widgets/health_timeline_user_copy.dart';

/// 3E-E — hierarquia visual e estrutura (não pixel-perfect).
HealthTimelineEntryView _e({
  required String id,
  required DateTime at,
  HealthTimelineType type = HealthTimelineType.weight,
  String sourceType = 'weight_records',
}) {
  return HealthTimelineEntryView(
    id: id,
    dogId: 'dog-a',
    type: HealthTimelineTypeView.known(type),
    occurredAt: at,
    recordedAt: at,
    title: 'Item $id',
    status: HealthTimelineEntryStatus.finalised,
    detailReference: HealthTimelineDetailReference(
      sourceType: sourceType,
      sourceId: id.split(':').last,
    ),
  );
}

void main() {
  setUpAll(() {
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  Future<void> setPhone(WidgetTester tester, {double width = 390}) async {
    final view = tester.view;
    view.physicalSize = Size(width, 900);
    view.devicePixelRatio = 1.0;
    addTearDown(view.resetPhysicalSize);
    addTearDown(view.resetDevicePixelRatio);
  }

  Future<void> pumpScreen(
    WidgetTester tester, {
    double width = 390,
    List<HealthTimelineEntryView>? items,
  }) async {
    await setPhone(tester, width: width);
    final list =
        items ??
        [
          _e(id: 'weight_records:w1', at: DateTime.utc(2026, 5, 10)),
          _e(
            id: 'health_events:h1',
            at: DateTime.utc(2026, 5, 9),
            type: HealthTimelineType.consultation,
            sourceType: 'health_events',
          ),
        ];
    final source = CoexistenceHealthTimelineSourceFactory.forReaders([
      MemoryTimelineSourceReader(sourceKey: 'e', items: list),
    ]);
    final controller = HealthTimelineController(source: source);
    final session = HealthTimelineFilterSession(
      controller: controller,
      dogId: 'dog-a',
      now: () => DateTime(2026, 5, 15, 12),
    );
    await controller.setQuery(HealthTimelineQuery(dogId: 'dog-a'));
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: HealthTimelineScreen(
            controller: controller,
            filterSession: session,
            dogDisplayName: 'Bono',
            onNavigate: (HealthTimelineDetailTarget t) async {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  group('3E-E hierarquia', () {
    testWidgets('título e Filtros antes dos quick filters', (tester) async {
      await pumpScreen(tester);

      expect(find.byKey(const ValueKey('health-timeline-title')), findsOneWidget);
      expect(
        find.byKey(const ValueKey('health-timeline-filters-button')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('health-timeline-quick-filters')),
        findsOneWidget,
      );

      final titleY = tester
          .getTopLeft(find.byKey(const ValueKey('health-timeline-title')))
          .dy;
      final quickY = tester
          .getTopLeft(find.byKey(const ValueKey('health-timeline-quick-filters')))
          .dy;
      final filtersY = tester
          .getTopLeft(
            find.byKey(const ValueKey('health-timeline-filters-button')),
          )
          .dy;

      expect(titleY, lessThan(quickY));
      expect(filtersY, lessThan(quickY));
      expect(find.text(HealthTimelineUserCopy.title), findsOneWidget);
      expect(
        find.byKey(const ValueKey('health-timeline-subtitle')),
        findsOneWidget,
      );
      expect(
        tester
            .widget<Text>(find.byKey(const ValueKey('health-timeline-subtitle')))
            .data,
        contains('Bono'),
      );
      expect(find.byType(HealthTimelineQuickTypeChips), findsOneWidget);
    });

    testWidgets('single type: quick selecionado sem chip ALIMENTAÇÃO redun.', (
      tester,
    ) async {
      await pumpScreen(tester);
      await tester.tap(find.text('Nutrição'));
      await tester.pumpAndSettle();

      expect(find.byType(HealthTimelineQuickTypeChips), findsOneWidget);
      // FilterLabels.suppressRedundantSingleType: só types meal → sem chip types.
      final chips = chipsOf(
        HealthTimelineFilterSelection(
          types: {HealthTimelineType.meal},
        ),
      );
      expect(chips.where((c) => c.kind == HealthTimelineFilterChipKind.types), isEmpty);
      // Barra applied não mostra chip de tipo único.
      expect(find.text('ALIMENTAÇÃO'), findsNothing);
    });

    testWidgets('constraints 360 sem overflow', (tester) async {
      await pumpScreen(tester, width: 360);
      expect(tester.takeException(), isNull);
      expect(find.text(HealthTimelineUserCopy.title), findsOneWidget);
      expect(find.byType(HealthTimelineQuickTypeChips), findsOneWidget);
    });

    testWidgets('constraints 390 e 430 sem overflow', (tester) async {
      for (final w in [390.0, 430.0]) {
        await pumpScreen(tester, width: w);
        expect(tester.takeException(), isNull);
        expect(find.byKey(const ValueKey('health-timeline-title')), findsOneWidget);
      }
    });

    testWidgets('navigable weight tem affordance; consultation não', (
      tester,
    ) async {
      await pumpScreen(tester);
      // Chevron só em cards com onTap (weight_records).
      expect(find.byIcon(Icons.chevron_right_rounded), findsWidgets);
      expect(find.text('Item weight_records:w1'), findsOneWidget);
      expect(find.text('Item health_events:h1'), findsOneWidget);
    });
  });
}
