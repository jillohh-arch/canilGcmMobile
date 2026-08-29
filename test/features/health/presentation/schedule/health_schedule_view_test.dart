import 'package:canil_gcm/features/health/domain/health_v1_enums_ext.dart';
import 'package:canil_gcm/features/health/presentation/schedule/health_schedule_controller.dart';
import 'package:canil_gcm/features/health/presentation/schedule/health_schedule_query.dart';
import 'package:canil_gcm/features/health/presentation/schedule/health_schedule_source.dart';
import 'package:canil_gcm/features/health/presentation/schedule/health_schedule_state.dart';
import 'package:canil_gcm/features/health/presentation/schedule/health_schedule_view.dart';
import 'package:canil_gcm/features/health/presentation/schedule/widgets/health_schedule_user_copy.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

import 'fake_health_schedule_source.dart';
import 'schedule_test_helpers.dart';

void main() {
  setUpAll(() {
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  late FakeHealthScheduleSource source;
  late DateTime clockNow;
  late HealthScheduleController controller;

  setUp(() {
    source = FakeHealthScheduleSource();
    clockNow = scheduleTestNow;
    controller = HealthScheduleController(
      source: source,
      temporalPolicy: testSchedulePolicy(),
      clock: () => clockNow,
    );
  });

  tearDown(() {
    controller.dispose();
    source.reset();
  });

  Widget wrap(Widget child, {double width = 390}) {
    return MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(size: Size(width, 844)),
        child: Scaffold(
          body: SizedBox(width: width, height: 844, child: child),
        ),
      ),
    );
  }

  HealthScheduleView view() => HealthScheduleView(
    controller: controller,
    dogDisplayName: 'Rex',
    recomputeInterval: Duration.zero,
    now: () => clockNow,
  );

  group('estados', () {
    testWidgets('loading sem dados falsos', (tester) async {
      source.holdResponses = true;
      final future = controller.setQuery(HealthScheduleQuery(dogId: 'dog-a'));
      await tester.pumpWidget(wrap(view()));
      await tester.pump();

      expect(
        find.bySemanticsLabel(HealthScheduleUserCopy.loadingMessage),
        findsOneWidget,
      );
      expect(find.text(HealthScheduleUserCopy.emptyTitle), findsNothing);
      expect(find.text('V10'), findsNothing);

      source.completeNext(schedulePage(const []));
      await future;
      await tester.pump();
    });

    testWidgets('empty profissional', (tester) async {
      source.enqueuePage(schedulePage(const []));
      await controller.setQuery(HealthScheduleQuery(dogId: 'dog-a'));
      await tester.pumpWidget(wrap(view()));
      await tester.pump();

      expect(find.text(HealthScheduleUserCopy.emptyTitle), findsOneWidget);
      expect(find.text(HealthScheduleUserCopy.emptyMessage), findsOneWidget);
      expect(find.textContaining('Registrar'), findsNothing);
    });

    testWidgets('error com retry', (tester) async {
      source.enqueueError(
        const HealthScheduleSourceException('falha de leitura'),
      );
      await controller.setQuery(HealthScheduleQuery(dogId: 'dog-a'));
      await tester.pumpWidget(wrap(view()));
      await tester.pump();

      expect(find.text(HealthScheduleUserCopy.errorTitle), findsOneWidget);
      expect(find.text('falha de leitura'), findsOneWidget);
      expect(find.text(HealthScheduleUserCopy.retryLabel), findsOneWidget);

      source.enqueuePage(schedulePage(const []));
      await tester.tap(find.text(HealthScheduleUserCopy.retryLabel));
      await tester.pumpAndSettle();
      expect(find.text(HealthScheduleUserCopy.emptyTitle), findsOneWidget);
    });

    testWidgets('data: KPIs, seções e itens', (tester) async {
      source.enqueuePage(
        schedulePage([
          scheduleItem(
            id: 'over',
            title: 'Vacina atrasada',
            scheduleType: ScheduleType.vaccination,
            scheduledFor: scheduleTestNow.subtract(const Duration(days: 3)),
            dueUntil: scheduleTestNow.subtract(const Duration(hours: 1)),
          ),
          scheduleItem(
            id: 'tod',
            title: 'Consulta hoje',
            scheduleType: ScheduleType.consultation,
            scheduledFor: scheduleTestNow.add(const Duration(hours: 4)),
          ),
          scheduleItem(
            id: 'up',
            title: 'Pesagem próxima',
            scheduleType: ScheduleType.weighing,
            scheduledFor: scheduleTestNow.add(const Duration(days: 2)),
          ),
          scheduleItem(
            id: 'prog',
            title: 'Exame programado',
            scheduleType: ScheduleType.exam,
            scheduledFor: scheduleTestNow.add(const Duration(days: 30)),
          ),
        ]),
      );
      await controller.setQuery(HealthScheduleQuery(dogId: 'dog-a'));
      await tester.pumpWidget(wrap(view()));
      await tester.pumpAndSettle();

      expect(find.text(HealthScheduleUserCopy.title), findsOneWidget);
      expect(find.textContaining('Rex'), findsOneWidget);
      expect(
        find.text(HealthScheduleUserCopy.sectionAttention),
        findsOneWidget,
      );
      expect(find.text(HealthScheduleUserCopy.sectionToday), findsOneWidget);
      expect(find.text(HealthScheduleUserCopy.sectionUpcoming), findsOneWidget);
      expect(find.text('Vacina atrasada'), findsOneWidget);
      expect(find.text('Consulta hoje'), findsOneWidget);
      expect(find.text('Pesagem próxima'), findsOneWidget);
      // KPIs labels (sempre no topo)
      expect(find.text(HealthScheduleUserCopy.kpiOverdue), findsOneWidget);
      expect(find.text(HealthScheduleUserCopy.kpiUpcoming), findsOneWidget);
      // Contagens derivadas (fonte única no controller; ListView lazy não monta tudo)
      final data = controller.state as HealthScheduleData;
      expect(data.groups.overdue, hasLength(1));
      expect(data.groups.today, hasLength(1));
      expect(data.groups.upcoming, hasLength(1));
      expect(data.groups.scheduled, hasLength(1));
      expect(data.items.map((e) => e.id).toSet(), {
        'over',
        'tod',
        'up',
        'prog',
      });
    });
  });

  group('prioridade e filtros', () {
    testWidgets('atrasados aparecem antes de programados no scroll', (
      tester,
    ) async {
      source.enqueuePage(
        schedulePage([
          scheduleItem(
            id: 'prog',
            title: 'Programado Z',
            scheduledFor: scheduleTestNow.add(const Duration(days: 40)),
          ),
          scheduleItem(
            id: 'over',
            title: 'Atrasado A',
            scheduledFor: scheduleTestNow.subtract(const Duration(days: 2)),
            dueUntil: scheduleTestNow.subtract(const Duration(hours: 1)),
          ),
        ]),
      );
      await controller.setQuery(HealthScheduleQuery(dogId: 'dog-a'));
      await tester.pumpWidget(wrap(view()));
      await tester.pumpAndSettle();

      final overdueY = tester.getTopLeft(find.text('Atrasado A')).dy;
      final scheduledY = tester.getTopLeft(find.text('Programado Z')).dy;
      expect(overdueY, lessThan(scheduledY));
    });

    testWidgets('filtro Vacinas oculta outros tipos', (tester) async {
      source.enqueuePage(
        schedulePage([
          scheduleItem(
            id: 'v',
            title: 'Só vacina',
            scheduleType: ScheduleType.vaccination,
            scheduledFor: scheduleTestNow.add(const Duration(days: 2)),
          ),
          scheduleItem(
            id: 'w',
            title: 'Só peso',
            scheduleType: ScheduleType.weighing,
            scheduledFor: scheduleTestNow.add(const Duration(days: 2)),
          ),
        ]),
      );
      await controller.setQuery(HealthScheduleQuery(dogId: 'dog-a'));
      await tester.pumpWidget(wrap(view()));
      await tester.pumpAndSettle();

      expect(find.text('Só vacina'), findsOneWidget);
      expect(find.text('Só peso'), findsOneWidget);

      await tester.tap(find.text('Vacinas'));
      await tester.pumpAndSettle();

      expect(find.text('Só vacina'), findsOneWidget);
      expect(find.text('Só peso'), findsNothing);
    });
  });

  group('responsividade', () {
    for (final width in [360.0, 390.0, 412.0]) {
      testWidgets('largura $width sem overflow', (tester) async {
        source.enqueuePage(
          schedulePage([
            scheduleItem(
              id: '1',
              title:
                  'Item com título bastante longo para forçar ellipsis visual',
              scheduledFor: scheduleTestNow.add(const Duration(days: 1)),
            ),
          ]),
        );
        await controller.setQuery(HealthScheduleQuery(dogId: 'dog-a'));
        await tester.pumpWidget(wrap(view(), width: width));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      });
    }
  });

  group('refresh e k9', () {
    testWidgets('refresh com falha preserva itens', (tester) async {
      source.enqueuePage(
        schedulePage([
          scheduleItem(
            id: 'keep',
            title: 'Item visível',
            scheduledFor: scheduleTestNow.add(const Duration(days: 1)),
          ),
        ]),
      );
      await controller.setQuery(HealthScheduleQuery(dogId: 'dog-a'));
      await tester.pumpWidget(wrap(view()));
      await tester.pumpAndSettle();
      expect(find.text('Item visível'), findsOneWidget);

      source.enqueueError(
        const HealthScheduleSourceException('refresh falhou'),
      );
      await controller.refresh();
      await tester.pumpAndSettle();

      expect(find.text('Item visível'), findsOneWidget);
      expect(find.textContaining('refresh falhou'), findsOneWidget);
    });

    testWidgets('troca de K9 remove itens do cão anterior', (tester) async {
      source.enqueuePage(
        schedulePage([
          scheduleItem(
            id: 'a1',
            dogId: 'dog-a',
            title: 'Item A',
            scheduledFor: scheduleTestNow.add(const Duration(days: 1)),
          ),
        ]),
      );
      await controller.selectDog('dog-a');
      await tester.pumpWidget(wrap(view()));
      await tester.pumpAndSettle();
      expect(find.text('Item A'), findsOneWidget);

      source.enqueuePage(
        schedulePage([
          scheduleItem(
            id: 'b1',
            dogId: 'dog-b',
            title: 'Item B',
            scheduledFor: scheduleTestNow.add(const Duration(days: 1)),
          ),
        ]),
      );
      await controller.selectDog('dog-b');
      await tester.pumpAndSettle();

      expect(find.text('Item A'), findsNothing);
      expect(find.text('Item B'), findsOneWidget);
    });
  });

  group('reavaliação temporal na UI', () {
    testWidgets('tick de recompute muda seção sem nova leitura', (
      tester,
    ) async {
      var loads = 0;
      source.handler = (q) async {
        loads++;
        return schedulePage([
          scheduleItem(
            id: 't',
            title: 'Item temporal',
            scheduledFor: scheduleTestNow.add(const Duration(hours: 5)),
          ),
        ]);
      };
      await controller.setQuery(HealthScheduleQuery(dogId: 'dog-a'));
      await tester.pumpWidget(wrap(view()));
      await tester.pumpAndSettle();
      expect(find.text(HealthScheduleUserCopy.sectionToday), findsOneWidget);
      final loadsAfter = loads;

      clockNow = scheduleTestNow.add(const Duration(hours: 6));
      controller.recomputeTemporalStates();
      await tester.pump();

      expect(loads, loadsAfter);
      expect(find.text(HealthScheduleUserCopy.sectionToday), findsNothing);
      expect(find.text(HealthScheduleUserCopy.sectionPending), findsOneWidget);
      expect(find.text('Item temporal'), findsOneWidget);
    });

    testWidgets('dispose cancela recompute periódico sem exceção', (
      tester,
    ) async {
      source.enqueuePage(
        schedulePage([
          scheduleItem(
            id: '1',
            scheduledFor: scheduleTestNow.add(const Duration(days: 1)),
          ),
        ]),
      );
      await controller.setQuery(HealthScheduleQuery(dogId: 'dog-a'));
      await tester.pumpWidget(
        wrap(
          HealthScheduleView(
            controller: controller,
            dogDisplayName: 'Rex',
            recomputeInterval: const Duration(milliseconds: 50),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 120));
      expect(tester.takeException(), isNull);
    });
  });
}
