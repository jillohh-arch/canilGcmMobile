import 'package:canil_gcm/core/theme/app_theme.dart';
import 'package:canil_gcm/features/health/domain/health_schedule_item.dart';
import 'package:canil_gcm/features/health/domain/health_v1_enums_ext.dart';
import 'package:canil_gcm/features/health/presentation/schedule/health_schedule_controller.dart';
import 'package:canil_gcm/features/health/presentation/schedule/health_schedule_query.dart';
import 'package:canil_gcm/features/health/presentation/schedule/health_schedule_state.dart';
import 'package:canil_gcm/features/health/presentation/schedule/health_schedule_view.dart';
import 'package:canil_gcm/features/health/presentation/schedule/widgets/health_schedule_user_copy.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

import 'fake_health_schedule_source.dart';
import 'schedule_test_helpers.dart';

/// Harness isolado de evidência visual estrutural da Agenda (Fase 4B).
///
/// Não entra em produção. Valida layout em 360/390/412 com dataset
/// representativo (overdue/pending/today/upcoming/scheduled).
///
/// PNG pixel-perfect omitido de propósito (mesmo padrão do harness Timeline
/// 3B: encoding/font async pode falhar no CI Windows).
void main() {
  setUpAll(() {
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  Future<void> pumpHarness(
    WidgetTester tester, {
    required double width,
    required HealthScheduleController controller,
  }) async {
    const height = 1400.0;
    tester.view.physicalSize = Size(width, height);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(size: Size(width, height)),
          child: Scaffold(
            backgroundColor: AppTheme.background,
            body: SizedBox(
              width: width,
              height: height,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                child: HealthScheduleView(
                  controller: controller,
                  dogDisplayName: 'K9 Visual Test',
                  recomputeInterval: Duration.zero,
                  now: () => scheduleTestNow,
                  bottomPadding: 24,
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  List<HealthScheduleItem> scheduleDataSet() {
    final now = scheduleTestNow;
    return [
      scheduleItem(
        id: 'over',
        title: 'Pesagem em atraso',
        scheduleType: ScheduleType.weighing,
        notes: 'Última realizada há 35 dias',
        scheduledFor: now.subtract(const Duration(days: 3)),
        dueUntil: now.subtract(const Duration(hours: 2)),
        assignedToName: 'Condutor Teste',
      ),
      scheduleItem(
        id: 'pend',
        title: 'Dose noturna — Condroprotetor',
        scheduleType: ScheduleType.dose,
        notes: 'Via oral',
        scheduledFor: now.subtract(const Duration(minutes: 20)),
        dueUntil: now.add(const Duration(hours: 4)),
      ),
      scheduleItem(
        id: 'tod',
        title: 'Consulta veterinária preventiva',
        scheduleType: ScheduleType.consultation,
        notes: 'Annual check-up',
        scheduledFor: now.add(const Duration(hours: 5)),
        assignedToName: 'Dr. Carlos Henrique',
      ),
      scheduleItem(
        id: 'up',
        title: 'Vacina V10',
        scheduleType: ScheduleType.vaccination,
        notes: 'Reforço anual',
        scheduledFor: now.add(const Duration(days: 3)),
      ),
      scheduleItem(
        id: 'sch',
        title: 'Hemograma completo',
        scheduleType: ScheduleType.exam,
        notes: 'Laboratório parceiro',
        scheduledFor: now.add(const Duration(days: 28)),
      ),
    ];
  }

  testWidgets('evidência visual data 360/390/412', (tester) async {
    final source = FakeHealthScheduleSource();
    final controller = HealthScheduleController(
      source: source,
      temporalPolicy: testSchedulePolicy(),
      clock: () => scheduleTestNow,
    );
    addTearDown(controller.dispose);

    source.handler = (_) async => schedulePage(scheduleDataSet());
    await controller.setQuery(HealthScheduleQuery(dogId: 'dog-visual'));

    for (final width in [360.0, 390.0, 412.0]) {
      await pumpHarness(tester, width: width, controller: controller);

      expect(tester.takeException(), isNull);
      expect(find.text(HealthScheduleUserCopy.title), findsOneWidget);
      expect(find.textContaining('K9 Visual Test'), findsOneWidget);
      expect(
        find.text(HealthScheduleUserCopy.sectionAttention),
        findsOneWidget,
      );
      expect(find.text(HealthScheduleUserCopy.sectionPending), findsOneWidget);
      expect(find.text(HealthScheduleUserCopy.sectionToday), findsOneWidget);
      expect(find.text(HealthScheduleUserCopy.kpiPending), findsOneWidget);
      expect(find.text(HealthScheduleUserCopy.kpiOverdue), findsOneWidget);
      expect(find.text(HealthScheduleUserCopy.kpiPendingHint), findsOneWidget);
      expect(find.text('Pesagem em atraso'), findsOneWidget);
      expect(find.text('Dose noturna — Condroprotetor'), findsOneWidget);
      expect(find.text('Consulta veterinária preventiva'), findsOneWidget);
      // Sem botões mortos de write
      expect(find.textContaining('Registrar'), findsNothing);
      expect(find.textContaining('Adicionar'), findsNothing);
      expect(find.textContaining('Calendário'), findsNothing);
      final data = controller.state as HealthScheduleData;
      expect(data.groups.overdue, hasLength(1));
      expect(data.groups.pending, hasLength(1));
      expect(data.groups.today, hasLength(1));
      expect(data.groups.upcoming, hasLength(1));
      expect(data.groups.scheduled, hasLength(1));
    }
  });

  testWidgets('evidência visual empty 390', (tester) async {
    final source = FakeHealthScheduleSource();
    final controller = HealthScheduleController(
      source: source,
      temporalPolicy: testSchedulePolicy(),
      clock: () => scheduleTestNow,
    );
    addTearDown(controller.dispose);
    source.enqueuePage(schedulePage(const []));
    await controller.setQuery(HealthScheduleQuery(dogId: 'dog-visual'));
    await pumpHarness(tester, width: 390, controller: controller);
    expect(find.text(HealthScheduleUserCopy.emptyTitle), findsOneWidget);
    expect(find.text(HealthScheduleUserCopy.emptyMessage), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('KPIs usam grid 2x2 em 360 e legenda sem 7 dias', (tester) async {
    final source = FakeHealthScheduleSource();
    final controller = HealthScheduleController(
      source: source,
      temporalPolicy: testSchedulePolicy(),
      clock: () => scheduleTestNow,
    );
    addTearDown(controller.dispose);
    source.handler = (_) async => schedulePage(scheduleDataSet());
    await controller.setQuery(HealthScheduleQuery(dogId: 'dog-visual'));
    await pumpHarness(tester, width: 360, controller: controller);

    expect(find.text('Próximos'), findsWidgets);
    expect(find.textContaining('7 dias'), findsNothing);
    expect(find.text(HealthScheduleUserCopy.kpiUpcomingHint), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
