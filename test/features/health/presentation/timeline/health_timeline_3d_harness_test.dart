import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:canil_gcm/features/health/data/coexistence/timeline/coexistence_health_timeline_source.dart';
import 'package:canil_gcm/features/health/data/coexistence/timeline/memory_timeline_source_reader.dart';
import 'package:canil_gcm/features/health/domain/health_v1_enums_ext.dart';
import 'package:canil_gcm/features/health/presentation/timeline/detail/health_timeline_detail_target.dart';
import 'package:canil_gcm/features/health/presentation/timeline/filters/health_timeline_filter_session.dart';
import 'package:canil_gcm/features/health/presentation/timeline/health_timeline_controller.dart';
import 'package:canil_gcm/features/health/presentation/timeline/health_timeline_entry_view.dart';
import 'package:canil_gcm/features/health/presentation/timeline/health_timeline_interactive_host.dart';
import 'package:canil_gcm/features/health/presentation/timeline/health_timeline_query.dart';
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

void main() {
  group('GATE J — Harness completo', () {
    testWidgets('timeline + filtros + resolução isolados', (tester) async {
      final items = [
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
        _e(
          id: 'a:meal',
          at: DateTime.utc(2026, 5, 8),
          type: HealthTimelineType.meal,
          detail: const HealthTimelineDetailReference(
            sourceType: 'feeding_events',
            sourceId: 'f1',
          ),
        ),
      ];
      final source = CoexistenceHealthTimelineSourceFactory.forReaders([
        MemoryTimelineSourceReader(sourceKey: 'mix', items: items),
      ]);
      final controller = HealthTimelineController(source: source);
      addTearDown(controller.dispose);
      final session = HealthTimelineFilterSession(
        controller: controller,
        dogId: 'dog-a',
        now: () => DateTime(2026, 5, 15, 12),
      );
      final navigated = <HealthTimelineDetailTarget>[];

      await controller.setQuery(HealthTimelineQuery(dogId: 'dog-a'));

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: HealthTimelineInteractiveHost(
              controller: controller,
              filterSession: session,
              now: () => DateTime(2026, 5, 15, 12),
              onNavigate: (t) async => navigated.add(t),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // 1. timeline inicial
      expect(find.text('Item weight_records:w1'), findsOneWidget);
      expect(find.text(HealthTimelineUserCopy.filterAction), findsOneWidget);

      // 2–4. abrir filtros, tipo weight, aplicar
      await tester.tap(find.text(HealthTimelineUserCopy.filterAction));
      await tester.pumpAndSettle();
      expect(find.text('APLICAR FILTROS'), findsOneWidget);
      await tester.tap(find.text('Pesagem'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('APLICAR FILTROS'));
      await tester.pumpAndSettle();

      // 5. chips
      expect(find.text('PESAGEM'), findsWidgets);
      expect(find.text('Item weight_records:w1'), findsOneWidget);
      expect(find.text('Item health_events:h1'), findsNothing);

      // 6–7. empty filtrado + limpar (via session — determinístico)
      session.openDraft();
      session.setDraftTypes({HealthTimelineType.exam});
      await session.apply();
      await tester.pumpAndSettle();
      expect(
        find.text(HealthTimelineUserCopy.emptyWithFiltersMessage),
        findsOneWidget,
      );
      expect(find.text(HealthTimelineUserCopy.clearFilters), findsOneWidget);
      await tester.tap(find.text(HealthTimelineUserCopy.clearFilters));
      await tester.pumpAndSettle();
      expect(find.text('Item health_events:h1'), findsOneWidget);

      // 9. tap supported weight
      session.openDraft();
      session.setDraftTypes({HealthTimelineType.weight});
      await session.apply();
      await tester.pumpAndSettle();
      await tester.tap(find.text('Item weight_records:w1'));
      await tester.pumpAndSettle();
      expect(navigated, hasLength(1));
      expect(navigated.single, isA<WeightHistoryTarget>());
      expect(
        navigated.single.kind,
        HealthTimelineDestinationKind.relatedHistory,
      );

      // 10. unsupported health_events — sem navegação
      await session.clearApplied();
      await tester.pumpAndSettle();
      navigated.clear();
      await tester.tap(find.text('Item health_events:h1'));
      await tester.pumpAndSettle();
      expect(navigated, isEmpty);
    });

    testWidgets('sem overflow em 360', (tester) async {
      final source = CoexistenceHealthTimelineSourceFactory.forReaders([
        MemoryTimelineSourceReader(
          sourceKey: 'a',
          items: [_e(id: 'a:1', at: DateTime.utc(2026, 1, 1))],
        ),
      ]);
      final controller = HealthTimelineController(source: source);
      addTearDown(controller.dispose);
      await controller.setQuery(HealthTimelineQuery(dogId: 'dog-a'));
      final session = HealthTimelineFilterSession(
        controller: controller,
        dogId: 'dog-a',
        now: () => DateTime(2026, 1, 2),
      );
      session.openDraft();
      session.setDraftTypes({
        HealthTimelineType.weight,
        HealthTimelineType.meal,
        HealthTimelineType.exam,
      });
      await session.apply();

      await tester.binding.setSurfaceSize(const Size(360, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: HealthTimelineInteractiveHost(
              controller: controller,
              filterSession: session,
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
