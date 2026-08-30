import 'package:canil_gcm/core/theme/app_theme.dart';
import 'package:canil_gcm/features/health/domain/health_schedule_mutation_commands.dart';
import 'package:canil_gcm/features/health/domain/health_schedule_mutation_errors.dart';
import 'package:canil_gcm/features/health/domain/health_schedule_mutation_gateway.dart';
import 'package:canil_gcm/features/health/domain/health_v1_enums_ext.dart';
import 'package:canil_gcm/features/health/presentation/schedule/forms/health_schedule_item_form_screen.dart';
import 'package:canil_gcm/features/health/presentation/schedule/health_schedule_controller.dart';
import 'package:canil_gcm/features/health/presentation/schedule/health_schedule_item_view.dart';
import 'package:canil_gcm/features/health/presentation/schedule/health_schedule_mutation_controller.dart';
import 'package:canil_gcm/features/health/presentation/schedule/health_schedule_mutation_user_copy.dart';
import 'package:canil_gcm/features/health/presentation/schedule/health_schedule_query.dart';
import 'package:canil_gcm/features/health/presentation/schedule/health_schedule_view.dart';
import 'package:canil_gcm/features/health/presentation/schedule/widgets/health_schedule_user_copy.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

import 'fake_health_schedule_source.dart';
import 'schedule_test_helpers.dart';

class _UiGateway implements HealthScheduleMutationGateway {
  HealthScheduleMutationResult? next;
  final List<Object> commands = [];

  @override
  Future<HealthScheduleMutationResult> createManual(
    CreateManualScheduleItemCommand command,
  ) async {
    commands.add(command);
    return next ??
        HealthScheduleMutationSuccess(
          dogId: command.dogId,
          scheduleId: 'created-1',
          revision: const HealthScheduleRevision('1'),
          wasNoOp: false,
          lifecycleStatus: ScheduleLifecycleStatus.open,
          operationId: command.operationId,
        );
  }

  @override
  Future<HealthScheduleMutationResult> updateOpen(
    UpdateOpenScheduleItemCommand command,
  ) async {
    commands.add(command);
    return next ??
        HealthScheduleMutationSuccess(
          dogId: command.dogId,
          scheduleId: command.scheduleId,
          revision: const HealthScheduleRevision('2'),
          wasNoOp: false,
          lifecycleStatus: ScheduleLifecycleStatus.open,
          operationId: command.operationId,
        );
  }

  @override
  Future<HealthScheduleMutationResult> complete(
    CompleteScheduleItemCommand command,
  ) async {
    commands.add(command);
    return next ??
        HealthScheduleMutationSuccess(
          dogId: command.dogId,
          scheduleId: command.scheduleId,
          revision: const HealthScheduleRevision('2'),
          wasNoOp: false,
          lifecycleStatus: ScheduleLifecycleStatus.completed,
          operationId: command.operationId ?? 'c',
        );
  }

  @override
  Future<HealthScheduleMutationResult> cancel(
    CancelScheduleItemCommand command,
  ) async {
    commands.add(command);
    return next ??
        HealthScheduleMutationSuccess(
          dogId: command.dogId,
          scheduleId: command.scheduleId,
          revision: const HealthScheduleRevision('2'),
          wasNoOp: false,
          lifecycleStatus: ScheduleLifecycleStatus.cancelled,
          operationId: command.operationId,
        );
  }
}

void main() {
  setUpAll(() {
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  late FakeHealthScheduleSource source;
  late HealthScheduleController schedule;
  late _UiGateway gateway;
  late HealthScheduleMutationController mutation;
  late DateTime clockNow;

  setUp(() {
    source = FakeHealthScheduleSource();
    clockNow = scheduleTestNow;
    schedule = HealthScheduleController(
      source: source,
      temporalPolicy: testSchedulePolicy(),
      clock: () => clockNow,
    );
    gateway = _UiGateway();
    mutation = HealthScheduleMutationController(
      gateway: gateway,
      scheduleController: schedule,
      operationIdFactory: () => 'stable-op-1',
    );
  });

  tearDown(() {
    mutation.dispose();
    schedule.dispose();
    source.reset();
  });

  Widget wrap(Widget child) {
    return MaterialApp(
      scaffoldMessengerKey: GlobalKey<ScaffoldMessengerState>(),
      locale: const Locale('pt', 'BR'),
      supportedLocales: const [Locale('pt', 'BR'), Locale('en', 'US')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      theme: ThemeData(
        scaffoldBackgroundColor: AppTheme.background,
        colorScheme: ColorScheme.dark(
          primary: AppTheme.primary,
          surface: AppTheme.surfacePanel,
        ),
      ),
      home: Scaffold(body: SizedBox(width: 390, height: 844, child: child)),
    );
  }

  Future<void> pumpAgenda(WidgetTester tester) async {
    await tester.pumpWidget(
      wrap(
        HealthScheduleView(
          controller: schedule,
          mutationController: mutation,
          dogDisplayName: 'Rex',
          recomputeInterval: Duration.zero,
          now: () => clockNow,
        ),
      ),
    );
    await tester.pump();
  }

  group('empty + create entry', () {
    testWidgets('empty state mostra CTA adicionar', (tester) async {
      source.enqueuePage(schedulePage(const []));
      await schedule.setQuery(HealthScheduleQuery(dogId: 'dog-a'));
      await pumpAgenda(tester);

      expect(find.text(HealthScheduleUserCopy.emptyTitle), findsOneWidget);
      expect(find.byKey(const ValueKey('schedule-add-button')), findsWidgets);
      expect(
        find.text(HealthScheduleMutationUserCopy.addToSchedule),
        findsWidgets,
      );
    });

    testWidgets('formulário create valida título e salva', (tester) async {
      source.enqueuePage(schedulePage(const []));
      await schedule.setQuery(HealthScheduleQuery(dogId: 'dog-a'));
      // refresh após create
      source.enqueuePage(
        schedulePage([
          scheduleItem(
            id: 'created-1',
            title: 'Vacina V10',
            revision: const HealthScheduleRevision('1'),
          ),
        ]),
      );

      await tester.pumpWidget(
        wrap(
          HealthScheduleItemFormScreen(
            mode: HealthScheduleItemFormMode.create,
            dogId: 'dog-a',
            mutationController: mutation,
          ),
        ),
      );
      await tester.pump();

      expect(
        find.text(HealthScheduleMutationUserCopy.createFormTitle),
        findsOneWidget,
      );
      // Hierarquia: título antes do tipo; timezone amigável; sem dropdown genérico.
      expect(find.byKey(const ValueKey('schedule-form-title')), findsOneWidget);
      expect(find.byKey(const ValueKey('schedule-form-type')), findsOneWidget);
      expect(find.byType(DropdownButtonFormField<ScheduleType>), findsNothing);
      expect(
        find.text(HealthScheduleMutationUserCopy.fieldTimezoneHint),
        findsOneWidget,
      );
      expect(find.textContaining('America/Sao_Paulo'), findsNothing);

      // Bottom sheet de tipos com ícones
      await tester.tap(find.byKey(const ValueKey('schedule-form-type')));
      await tester.pumpAndSettle();
      expect(
        find.text(HealthScheduleMutationUserCopy.typeSheetTitle),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('schedule-type-option-vaccination')),
        findsOneWidget,
      );
      await tester.tap(
        find.byKey(const ValueKey('schedule-type-option-vaccination')),
      );
      await tester.pumpAndSettle();
      expect(find.text('Vacinação'), findsWidgets);

      // submit sem título → erro
      await tester.tap(find.text(HealthScheduleMutationUserCopy.saveLabel));
      await tester.pump();
      expect(
        find.text(HealthScheduleMutationUserCopy.titleRequired),
        findsOneWidget,
      );
      expect(gateway.commands, isEmpty);

      await tester.enterText(
        find.byKey(const ValueKey('schedule-form-title')),
        'Vacina V10',
      );
      await tester.pump();

      await tester.tap(find.text(HealthScheduleMutationUserCopy.saveLabel));
      await tester.pumpAndSettle();

      expect(gateway.commands, hasLength(1));
      final cmd = gateway.commands.single as CreateManualScheduleItemCommand;
      expect(cmd.scheduleType, ScheduleType.vaccination);
      expect(cmd.title, 'Vacina V10');
      expect(cmd.operationId, 'stable-op-1');
      expect(cmd.timezone, 'America/Sao_Paulo');
    });
  });

  group('menu contextual', () {
    testWidgets('manual open mostra edit/complete/cancel', (tester) async {
      source.enqueuePage(
        schedulePage([
          scheduleItem(
            id: 'm1',
            title: 'Item manual',
            sourceType: ScheduleSourceType.manual,
            revision: const HealthScheduleRevision('1'),
          ),
        ]),
      );
      await schedule.setQuery(HealthScheduleQuery(dogId: 'dog-a'));
      await pumpAgenda(tester);

      expect(
        find.byKey(const ValueKey('schedule-item-actions')),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const ValueKey('schedule-item-actions')));
      await tester.pumpAndSettle();

      expect(
        find.text(HealthScheduleMutationUserCopy.actionEdit),
        findsOneWidget,
      );
      expect(
        find.text(HealthScheduleMutationUserCopy.actionComplete),
        findsOneWidget,
      );
      expect(
        find.text(HealthScheduleMutationUserCopy.actionCancel),
        findsOneWidget,
      );
    });

    testWidgets('automático open sem edit/cancel', (tester) async {
      source.enqueuePage(
        schedulePage([
          scheduleItem(
            id: 'a1',
            title: 'Dose protocolo',
            sourceType: ScheduleSourceType.treatmentProtocol,
            revision: const HealthScheduleRevision('1'),
          ),
        ]),
      );
      await schedule.setQuery(HealthScheduleQuery(dogId: 'dog-a'));
      await pumpAgenda(tester);

      await tester.tap(find.byKey(const ValueKey('schedule-item-actions')));
      await tester.pumpAndSettle();

      expect(
        find.text(HealthScheduleMutationUserCopy.actionEdit),
        findsNothing,
      );
      expect(
        find.text(HealthScheduleMutationUserCopy.actionCancel),
        findsNothing,
      );
      expect(
        find.text(HealthScheduleMutationUserCopy.actionComplete),
        findsOneWidget,
      );
      expect(
        find.text(HealthScheduleMutationUserCopy.generatedAutomatically),
        findsOneWidget,
      );
    });

    testWidgets('terminal sem menu de ações', (tester) async {
      source.enqueuePage(
        schedulePage([
          scheduleItem(
            id: 'done',
            title: 'Feito',
            status: ScheduleLifecycleStatus.completed,
            completedAt: scheduleTestNow,
            revision: const HealthScheduleRevision('2'),
          ),
        ]),
      );
      await schedule.setQuery(HealthScheduleQuery(dogId: 'dog-a'));
      await pumpAgenda(tester);

      expect(find.byKey(const ValueKey('schedule-item-actions')), findsNothing);
    });
  });

  group('complete + cancel flows', () {
    testWidgets('confirmação complete e sucesso', (tester) async {
      source.enqueuePage(
        schedulePage([
          scheduleItem(
            id: 'c1',
            title: 'Consulta',
            revision: const HealthScheduleRevision('1'),
          ),
        ]),
      );
      await schedule.setQuery(HealthScheduleQuery(dogId: 'dog-a'));
      // pós-complete: lista open vazia
      source.enqueuePage(schedulePage(const []));

      await pumpAgenda(tester);
      await tester.tap(find.byKey(const ValueKey('schedule-item-actions')));
      await tester.pumpAndSettle();
      await tester.tap(
        find.text(HealthScheduleMutationUserCopy.actionComplete),
      );
      await tester.pumpAndSettle();

      expect(
        find.text(HealthScheduleMutationUserCopy.completeTitle),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const ValueKey('schedule-complete-confirm')));
      await tester.pumpAndSettle();

      expect(
        gateway.commands.whereType<CompleteScheduleItemCommand>(),
        hasLength(1),
      );
    });

    testWidgets('cancel exige motivo', (tester) async {
      source.enqueuePage(
        schedulePage([
          scheduleItem(
            id: 'x1',
            title: 'Banho',
            revision: const HealthScheduleRevision('1'),
          ),
        ]),
      );
      await schedule.setQuery(HealthScheduleQuery(dogId: 'dog-a'));
      source.enqueuePage(schedulePage(const []));

      await pumpAgenda(tester);
      await tester.tap(find.byKey(const ValueKey('schedule-item-actions')));
      await tester.pumpAndSettle();
      await tester.tap(find.text(HealthScheduleMutationUserCopy.actionCancel));
      await tester.pumpAndSettle();

      expect(
        find.text(HealthScheduleMutationUserCopy.cancelSheetTitle),
        findsOneWidget,
      );

      // confirmar sem motivo
      await tester.tap(find.byKey(const ValueKey('schedule-cancel-confirm')));
      await tester.pump();
      expect(
        find.text(HealthScheduleMutationUserCopy.cancelReasonRequired),
        findsOneWidget,
      );
      expect(gateway.commands, isEmpty);

      await tester.enterText(
        find.byKey(const ValueKey('schedule-cancel-reason')),
        'Duplicado',
      );
      await tester.tap(find.byKey(const ValueKey('schedule-cancel-confirm')));
      await tester.pumpAndSettle();

      final cancel = gateway.commands.single as CancelScheduleItemCommand;
      expect(cancel.cancelReason, 'Duplicado');
    });

    testWidgets('conflict mostra mensagem e não sobrescreve silenciosamente', (
      tester,
    ) async {
      source.enqueuePage(
        schedulePage([
          scheduleItem(
            id: 'e1',
            title: 'Editar me',
            revision: const HealthScheduleRevision('1'),
          ),
        ]),
      );
      await schedule.setQuery(HealthScheduleQuery(dogId: 'dog-a'));
      // refresh após conflict
      source.enqueuePage(
        schedulePage([
          scheduleItem(
            id: 'e1',
            title: 'Versão remota',
            revision: const HealthScheduleRevision('5'),
          ),
        ]),
      );

      gateway.next = const HealthScheduleMutationErrorResult(
        HealthScheduleMutationConflict(),
      );

      await tester.pumpWidget(
        wrap(
          HealthScheduleItemFormScreen(
            mode: HealthScheduleItemFormMode.edit,
            dogId: 'dog-a',
            mutationController: mutation,
            item: HealthScheduleItemView.fromDomain(
              scheduleItem(
                id: 'e1',
                title: 'Editar me',
                revision: const HealthScheduleRevision('1'),
              ),
              policy: testSchedulePolicy(),
              now: scheduleTestNow,
            ),
          ),
        ),
      );
      await tester.pump();

      await tester.enterText(
        find.byKey(const ValueKey('schedule-form-title')),
        'Tentativa local',
      );
      await tester.tap(find.text(HealthScheduleMutationUserCopy.saveLabel));
      await tester.pumpAndSettle();

      expect(find.textContaining('outra sessão'), findsOneWidget);
      // form permanece (dirty) — não fechou com sucesso silencioso
      expect(
        find.text(HealthScheduleMutationUserCopy.editFormTitle),
        findsOneWidget,
      );
    });
  });
}
