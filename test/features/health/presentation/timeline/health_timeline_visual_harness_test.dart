import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:canil_gcm/features/health/domain/health_v1_enums_ext.dart';
import 'package:canil_gcm/features/health/domain/health_v1_models.dart';
import 'package:canil_gcm/features/health/domain/health_v1_value_objects.dart';
import 'package:canil_gcm/features/health/presentation/timeline/health_timeline_controller.dart';
import 'package:canil_gcm/features/health/presentation/timeline/health_timeline_entry_view.dart';
import 'package:canil_gcm/features/health/presentation/timeline/health_timeline_query.dart';
import 'package:canil_gcm/features/health/presentation/timeline/health_timeline_source.dart';
import 'package:canil_gcm/features/health/presentation/timeline/widgets/health_timeline_day_section.dart';
import 'package:canil_gcm/features/health/presentation/timeline/widgets/health_timeline_entry_card.dart';
import 'package:canil_gcm/features/health/presentation/timeline/widgets/health_timeline_refresh_banner.dart';
import 'package:canil_gcm/features/health/presentation/timeline/widgets/health_timeline_view.dart';

import 'fake_health_timeline_source.dart';
import 'timeline_test_helpers.dart';

/// Harness isolado para evidência visual estrutural da Fase 3B.
///
/// Não cria rota de produção. Valida layout em 360/390/430 e estados
/// críticos sem dependência de encoding de PNG (pode falhar no CI Windows).
void main() {
  setUpAll(() {
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  final fixedNow = DateTime(2026, 7, 16, 14, 0);

  Future<void> pumpAt(
    WidgetTester tester, {
    required double width,
    required HealthTimelineController controller,
    ValueChanged<HealthTimelineEntryView>? onEntryTap,
    VoidCallback? onFilterRequested,
    int? activeFilterCount,
    bool? hasActiveFilters,
  }) async {
    tester.view.physicalSize = Size(width, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(size: Size(width, 1600)),
          child: Scaffold(
            backgroundColor: const Color(0xFF050D10),
            body: SizedBox(
              width: width,
              height: 1600,
              child: HealthTimelineView(
                controller: controller,
                contextLabel: 'Bono',
                now: () => fixedNow,
                onEntryTap: onEntryTap,
                onFilterRequested: onFilterRequested,
                activeFilterCount: activeFilterCount,
                hasActiveFilters: hasActiveFilters,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('evidência visual data 360/390/430', (tester) async {
    final source = FakeHealthTimelineSource();
    final controller = HealthTimelineController(source: source);
    addTearDown(controller.dispose);

    source.enqueuePage(
      pageOf([
        entry(
          id: '1',
          type: HealthTimelineType.consultation,
          title: 'Avaliação por claudicação',
          subtitle: 'Restrição operacional por 5 dias',
          professional: const ProfessionalIdentitySummary(
            name: 'Carlos Mendes',
            specialty: 'Clínica',
          ),
          recordedBy: RecordedBy(
            uid: 'u1',
            name: 'GCM Ragonha',
            internalRole: 'condutor',
          ),
          operationalImpact: OperationalImpact(
            level: OperationalImpactLevel.medium,
            description: 'Repouso relativo',
          ),
          hasAttachments: true,
          attachmentCount: 2,
          amendments: HealthTimelineAmendmentMetadata(
            hasAmendments: true,
            amendmentCount: 1,
          ),
          occurredAt: DateTime(2026, 7, 16, 14, 32),
        ),
        entry(
          id: '2',
          type: HealthTimelineType.weight,
          title: '29,8 kg',
          occurredAt: DateTime(2026, 7, 16, 10, 15),
          recordedBy: RecordedBy(
            uid: 'u2',
            name: 'GCM Silva',
            internalRole: 'condutor',
          ),
        ),
        entry(
          id: '3',
          type: HealthTimelineType.meal,
          title: 'Almoço',
          subtitle: '150 g consumidos',
          occurredAt: DateTime(2026, 7, 15, 13, 42),
        ),
        entry(
          id: '4',
          type: HealthTimelineType.vaccination,
          title: 'Vacina V10',
          subtitle: 'Dose anual aplicada',
          occurredAt: DateTime(2026, 7, 10, 9, 5),
        ),
        entry(
          id: '5',
          typeRaw: 'future_procedure_v9',
          title: 'Procedimento futuro',
          status: HealthTimelineEntryStatus.cancelled,
          occurredAt: DateTime(2026, 7, 10, 8, 0),
        ),
      ], nextCursorToken: 'more'),
    );

    await controller.setQuery(HealthTimelineQuery(dogId: 'dog-a'));

    for (final width in [360.0, 390.0, 430.0]) {
      await pumpAt(
        tester,
        width: width,
        controller: controller,
        onEntryTap: (_) {},
        onFilterRequested: () {},
      );

      expect(tester.takeException(), isNull);
      expect(find.text('HOJE'), findsOneWidget);
      expect(find.text('ONTEM'), findsOneWidget);
      expect(find.text('10 JUL 2026'), findsOneWidget);
      expect(find.text('CANCELADO'), findsOneWidget);
      expect(find.text('REGISTRO DE SAÚDE'), findsOneWidget);
      expect(find.textContaining('CARREGAR MAIS'), findsOneWidget);
      expect(find.byType(HealthTimelineEntryCard), findsWidgets);
      expect(find.byType(HealthTimelineEntryRow), findsWidgets);
      expect(find.textContaining('future_procedure'), findsNothing);
    }
  });

  testWidgets('evidência visual empty/error/offline/banner', (tester) async {
    // Empty
    {
      final source = FakeHealthTimelineSource()..enqueuePage(pageOf([]));
      final controller = HealthTimelineController(source: source);
      addTearDown(controller.dispose);
      await controller.setQuery(HealthTimelineQuery(dogId: 'dog-a'));
      await pumpAt(
        tester,
        width: 390,
        controller: controller,
        onFilterRequested: () {},
      );
      expect(find.textContaining('Nenhum registro de saúde'), findsOneWidget);
      expect(tester.takeException(), isNull);
    }

    // Error
    {
      final source = FakeHealthTimelineSource()
        ..enqueueError(const HealthTimelineSourceException('fail'));
      final controller = HealthTimelineController(source: source);
      addTearDown(controller.dispose);
      await controller.setQuery(HealthTimelineQuery(dogId: 'dog-a'));
      await pumpAt(tester, width: 390, controller: controller);
      expect(find.text('Tentar novamente'), findsOneWidget);
      expect(tester.takeException(), isNull);
    }

    // Offline
    {
      final source = FakeHealthTimelineSource()..enqueueOffline();
      final controller = HealthTimelineController(source: source);
      addTearDown(controller.dispose);
      await controller.setQuery(HealthTimelineQuery(dogId: 'dog-a'));
      await pumpAt(tester, width: 390, controller: controller);
      expect(find.textContaining('sem conexão'), findsOneWidget);
      expect(tester.takeException(), isNull);
    }

    // Refresh error banner with data
    {
      final source = FakeHealthTimelineSource()
        ..enqueuePage(
          pageOf([
            entry(
              id: 'keep',
              title: 'Mantido após refresh',
              occurredAt: DateTime(2026, 7, 16, 11),
            ),
          ]),
        );
      final controller = HealthTimelineController(source: source);
      addTearDown(controller.dispose);
      await controller.setQuery(HealthTimelineQuery(dogId: 'dog-a'));
      source.enqueueError(const HealthTimelineSourceException('refresh fail'));
      await controller.refresh();
      await pumpAt(tester, width: 390, controller: controller);
      expect(find.text('Mantido após refresh'), findsOneWidget);
      expect(find.byType(HealthTimelineRefreshBanner), findsOneWidget);
      expect(find.textContaining('Não foi possível atualizar'), findsOneWidget);
      expect(tester.takeException(), isNull);
    }
  });
}
