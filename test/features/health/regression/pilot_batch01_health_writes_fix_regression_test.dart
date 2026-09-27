import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:canil_gcm/core/services/authoritative_time/authoritative_time_gateway.dart';
import 'package:canil_gcm/core/services/authoritative_time/authoritative_time_models.dart';
import 'package:canil_gcm/core/services/authoritative_time/authoritative_time_provider.dart';
import 'package:canil_gcm/core/services/authoritative_time/monotonic_elapsed_clock.dart';
import 'package:canil_gcm/core/theme/app_theme.dart';
import 'package:canil_gcm/features/health/data/coexistence/nutrition/coexistence_nutrition_read_source.dart';
import 'package:canil_gcm/features/health/domain/health_nutrition_mutation_commands.dart';
import 'package:canil_gcm/features/health/domain/health_nutrition_mutation_errors.dart';
import 'package:canil_gcm/features/health/domain/health_nutrition_mutation_gateway.dart';
import 'package:canil_gcm/features/health/domain/health_schedule_mutation_commands.dart';
import 'package:canil_gcm/features/health/domain/health_schedule_mutation_errors.dart';
import 'package:canil_gcm/features/health/domain/health_schedule_mutation_gateway.dart';
import 'package:canil_gcm/features/health/domain/health_v1_enums.dart';
import 'package:canil_gcm/features/health/domain/health_v1_enums_ext.dart';
import 'package:canil_gcm/features/health/domain/health_v1_models.dart';
import 'package:canil_gcm/features/health/domain/meal_occurrence.dart';
import 'package:canil_gcm/features/health/domain/meal_schedule_slot.dart';
import 'package:canil_gcm/features/health/domain/nutrition_plan.dart';
import 'package:canil_gcm/features/health/domain/nutrition_read_models.dart';
import 'package:canil_gcm/features/health/domain/supplement_log.dart';
import 'package:canil_gcm/features/health/presentation/nutrition/health_nutrition_mutation_controller.dart';
import 'package:canil_gcm/features/health/presentation/nutrition/health_nutrition_mutation_outcome.dart';
import 'package:canil_gcm/features/health/presentation/nutrition/health_nutrition_read_controller.dart';
import 'package:canil_gcm/features/health/presentation/schedule/forms/health_schedule_item_form_screen.dart';
import 'package:canil_gcm/features/health/presentation/schedule/health_schedule_controller.dart';
import 'package:canil_gcm/features/health/presentation/schedule/health_schedule_mutation_controller.dart';
import 'package:canil_gcm/features/health/presentation/schedule/health_schedule_mutation_user_copy.dart';
import 'package:canil_gcm/features/health/presentation/schedule/health_schedule_query.dart';
import 'package:canil_gcm/features/health/presentation/shared/forms/health_form_controller.dart';
import 'package:canil_gcm/features/health/presentation/shared/forms/health_form_status.dart';

import '../presentation/schedule/fake_health_schedule_source.dart';
import '../presentation/schedule/schedule_test_helpers.dart';

// ── Fakes & Test Helpers ───────────────────────────────────────────────────

final class _FakeMonotonicClock implements MonotonicElapsedClock {
  Duration value = Duration.zero;

  @override
  Duration get elapsed => value;

  void advance(Duration d) => value += d;
}

final class _MockTimeGateway implements AuthoritativeTimeGateway {
  _MockTimeGateway({this.onFetch});

  Future<AuthoritativeTimeRemoteResponse> Function()? onFetch;
  int calls = 0;

  @override
  Future<AuthoritativeTimeRemoteResponse> fetchAuthoritativeTime() {
    calls++;
    if (onFetch != null) return onFetch!();
    final base = DateTime.utc(2026, 7, 22, 12);
    return Future.value(
      AuthoritativeTimeRemoteResponse(
        protocolVersion: 1,
        requestId: '00000000-0000-4000-8000-000000000001',
        requestReceivedAtUtc: base,
        serverSentAtUtc: base,
        maxAge: const Duration(minutes: 15),
      ),
    );
  }
}

final class _MockNutritionGateway implements HealthNutritionMutationGateway {
  HealthNutritionMutationResult? next;
  int plannedCalls = 0;
  int adhocCalls = 0;
  int supplementCalls = 0;
  Duration delay = Duration.zero;

  @override
  Future<HealthNutritionMutationResult> createPlannedMealLog(
    CreatePlannedMealLogCommand command,
  ) async {
    plannedCalls++;
    if (delay > Duration.zero) await Future<void>.delayed(delay);
    return next ??
        CreateMealLogSuccess(
          dogId: command.dogId,
          mealId: 'mo-planned-1',
          revision: 1,
          wasNoOp: false,
          operationId: command.operationId,
          mealOccurrenceId: 'occ-1',
        );
  }

  @override
  Future<HealthNutritionMutationResult> createAdhocMealLog(
    CreateAdhocMealLogCommand command,
  ) async {
    adhocCalls++;
    if (delay > Duration.zero) await Future<void>.delayed(delay);
    return next ??
        CreateMealLogSuccess(
          dogId: command.dogId,
          mealId: 'mo-adhoc-1',
          revision: 1,
          wasNoOp: false,
          operationId: command.operationId,
          mealOccurrenceId: 'occ-2',
        );
  }

  @override
  Future<HealthNutritionMutationResult> createSupplementLog(
    CreateSupplementLogCommand command,
  ) async {
    supplementCalls++;
    if (delay > Duration.zero) await Future<void>.delayed(delay);
    return next ??
        CreateSupplementLogSuccess(
          dogId: command.dogId,
          supplementLogId: 'supp-1',
          revision: 1,
          wasNoOp: false,
          operationId: command.operationId,
        );
  }
}

final class _MockScheduleGateway implements HealthScheduleMutationGateway {
  HealthScheduleMutationResult? next;
  Future<HealthScheduleMutationResult> Function(
    CreateManualScheduleItemCommand,
  )?
  onCreate;
  int createCalls = 0;

  @override
  Future<HealthScheduleMutationResult> createManual(
    CreateManualScheduleItemCommand command,
  ) async {
    createCalls++;
    if (onCreate != null) return onCreate!(command);
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
  ) async => throw UnimplementedError();

  @override
  Future<HealthScheduleMutationResult> complete(
    CompleteScheduleItemCommand command,
  ) async => throw UnimplementedError();

  @override
  Future<HealthScheduleMutationResult> cancel(
    CancelScheduleItemCommand command,
  ) async => throw UnimplementedError();
}

final class _StaticPlanReader implements NutritionCanonicalPlanReader {
  _StaticPlanReader(this.plans);
  final List<NutritionPlan> plans;

  @override
  Future<NutritionSourceBatch<NutritionPlan>> loadPlans(String dogId) async {
    return NutritionSourceBatch.available(plans);
  }
}

NutritionPlan _dummyPlan(String id, String dogId) {
  final actor = RecordedBy(uid: 'u1', name: 'Admin', internalRole: 'admin');
  return NutritionPlan(
    id: id,
    dogId: dogId,
    foodType: 'Ração Especial',
    amountGramsPerDay: 300,
    mealsPerDay: 1,
    mealSchedule: [
      MealScheduleSlot(
        id: 'slot-1',
        period: MealPeriodWire.parseCanonical('morning'),
        scheduledTime: ScheduledTimeOfDay('08:00'),
        targetGrams: 300,
      ),
    ],
    validFrom: DateTime.utc(2026, 1, 1),
    timezone: NutritionPlan.defaultTimezone,
    recordedBy: actor,
    status: NutritionPlanStatus.active,
    schemaVersion: 1,
    revision: 1,
  );
}

// ── Tests ──────────────────────────────────────────────────────────────────

void main() {
  setUpAll(() {
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  group('GATE: CT3.F20.PILOT-BATCH01-HEALTH-WRITES-FIX-R1 — Regression Pack', () {
    // ══════════════════════════════════════════════════════════════════════════
    // 1. TRUSTED TIME REGRESSION
    // ══════════════════════════════════════════════════════════════════════════
    group('1. Trusted Time', () {
      test('1.1 successful resolution returns fresh authoritative time', () async {
        final clock = _FakeMonotonicClock();
        final base = DateTime.utc(2026, 7, 22, 12);
        final gateway = _MockTimeGateway(
          onFetch: () async {
            clock.advance(const Duration(milliseconds: 100));
            return AuthoritativeTimeRemoteResponse(
              protocolVersion: 1,
              requestId: '00000000-0000-4000-8000-000000000001',
              requestReceivedAtUtc: base,
              serverSentAtUtc: base.add(const Duration(milliseconds: 20)),
              maxAge: const Duration(minutes: 15),
            );
          },
        );
        final provider = AuthoritativeTimeProvider(
          gateway: gateway,
          monotonicClock: clock,
        );

        final result = await provider.synchronize();
        expect(result, isA<AuthoritativeTimeSyncSuccess>());
        expect(provider.status, AuthoritativeTimeStatus.fresh);
        expect(provider.nowFreshUtc(), isNotNull);
        expect(provider.nowUtc(), isNotNull);
      });

      test('1.2 timeout fails closed after maximumRoundTrip and resets inFlight', () {
        fakeAsync((async) {
          final clock = _FakeMonotonicClock();
          final completer = Completer<AuthoritativeTimeRemoteResponse>();
          final gateway = _MockTimeGateway(onFetch: () => completer.future);
          final provider = AuthoritativeTimeProvider(
            gateway: gateway,
            monotonicClock: clock,
          );

          AuthoritativeTimeSyncResult? syncResult;
          provider.synchronize().then((r) => syncResult = r);
          expect(provider.status, AuthoritativeTimeStatus.synchronizing);

          // Avança tempo além de maximumRoundTrip (10s)
          async.elapse(const Duration(seconds: 11));

          expect(syncResult, isA<AuthoritativeTimeSyncFailure>());
          final failure = (syncResult as AuthoritativeTimeSyncFailure).failure;
          expect(failure.code, AuthoritativeTimeFailureCode.unavailable);
          expect(provider.status, AuthoritativeTimeStatus.failed);
          expect(provider.nowFreshUtc(), isNull);

          // InFlight foi limpo: próxima chamada tenta sincronizar novamente
          gateway.onFetch = () async => AuthoritativeTimeRemoteResponse(
            protocolVersion: 1,
            requestId: '00000000-0000-4000-8000-000000000002',
            requestReceivedAtUtc: DateTime.utc(2026, 7, 22, 12),
            serverSentAtUtc: DateTime.utc(2026, 7, 22, 12),
            maxAge: const Duration(minutes: 15),
          );

          AuthoritativeTimeSyncResult? recovered;
          provider.synchronize().then((r) => recovered = r);
          async.elapse(const Duration(milliseconds: 100));

          expect(recovered, isA<AuthoritativeTimeSyncSuccess>());
          expect(provider.status, AuthoritativeTimeStatus.fresh);
        });
      });

      test('1.3 network failure maps to unavailable and fails closed', () async {
        final clock = _FakeMonotonicClock();
        final gateway = _MockTimeGateway(
          onFetch: () async => throw const AuthoritativeTimeFailure(
            AuthoritativeTimeFailureCode.unavailable,
            'Sem conexão com o servidor de horário.',
          ),
        );
        final provider = AuthoritativeTimeProvider(
          gateway: gateway,
          monotonicClock: clock,
        );

        final result = await provider.synchronize();
        expect(result, isA<AuthoritativeTimeSyncFailure>());
        expect(provider.status, AuthoritativeTimeStatus.failed);
        expect(provider.nowFreshUtc(), isNull);
        expect(provider.nowReadOnlyUtc(), isNull);
      });

      test('1.4 cached valid time is reused without calling gateway again', () async {
        final clock = _FakeMonotonicClock();
        final gateway = _MockTimeGateway();
        final provider = AuthoritativeTimeProvider(
          gateway: gateway,
          monotonicClock: clock,
        );

        await provider.synchronize();
        expect(gateway.calls, 1);

        // Avança 2 minutos (dentro da freshWindow de 5 min)
        clock.advance(const Duration(minutes: 2));
        final secondResult = await provider.synchronize(force: false);

        expect(secondResult, isA<AuthoritativeTimeSyncSuccess>());
        expect(gateway.calls, 1); // Não chamou o gateway novamente
        expect(provider.status, AuthoritativeTimeStatus.fresh);
      });

      test('1.5 stale time blocks mutations while allowing read-only access', () async {
        final clock = _FakeMonotonicClock();
        final gateway = _MockTimeGateway();
        final provider = AuthoritativeTimeProvider(
          gateway: gateway,
          monotonicClock: clock,
        );

        await provider.synchronize();

        // Avança 6 minutos (passou a freshWindow de 5 min, mas dentro de maxAge de 15 min)
        clock.advance(const Duration(minutes: 6));

        expect(provider.status, AuthoritativeTimeStatus.stale);
        expect(provider.nowFreshUtc(), isNull); // Bloqueia mutações
        expect(provider.nowUtc(), isNull);
        expect(provider.nowReadOnlyUtc(), isNotNull); // Permite consulta
      });

      test('1.6 UI recovers from synchronizing when authoritative time fails', () {
        fakeAsync((async) {
          final clock = _FakeMonotonicClock();
          final completer = Completer<AuthoritativeTimeRemoteResponse>();
          final gateway = _MockTimeGateway(onFetch: () => completer.future);
          final provider = AuthoritativeTimeProvider(
            gateway: gateway,
            monotonicClock: clock,
          );
          final source = CoexistenceNutritionReadSource(
            canonicalPlanReader: _StaticPlanReader([_dummyPlan('p1', 'dog-1')]),
          );
          final controller = HealthNutritionReadController(
            source: source,
            authoritativeTimeProvider: provider,
          );

          controller.selectDog('dog-1');
          expect(controller.isLoading, isTrue);
          expect(
            controller.temporalState,
            HealthNutritionTemporalState.synchronizing,
          );

          // Simula timeout da sincronização temporal (10s)
          async.elapse(const Duration(seconds: 11));

          // Não pode ficar preso em synchronizing!
          expect(controller.isLoading, isFalse);
          expect(
            controller.temporalState,
            HealthNutritionTemporalState.unavailable,
          );
          expect(controller.temporalActionsAllowed, isFalse);
          expect(
            controller.temporalDiagnosticTitle,
            'Horário confiável indisponível',
          );
          // Snapshot carregado para leitura
          expect(controller.snapshotResult.valueOrNull, isNotNull);

          controller.dispose();
        });
      });
    });

    // ══════════════════════════════════════════════════════════════════════════
    // 2. NUTRITION WRITES REGRESSION
    // ══════════════════════════════════════════════════════════════════════════
    group('2. Nutrition Writes', () {
      late _MockNutritionGateway nutritionGateway;
      late HealthNutritionMutationController mutationController;

      setUp(() {
        nutritionGateway = _MockNutritionGateway();
        mutationController = HealthNutritionMutationController(
          gateway: nutritionGateway,
        );
      });

      tearDown(() {
        mutationController.dispose();
      });

      test('2.1 valid registration of planned meal, adhoc meal and supplement', () async {
        // Planned meal
        final mealOutcome = await mutationController.createPlannedMeal(
          dogId: 'dog-1',
          planId: 'p1',
          plannedMealId: 'slot-1',
          offeredGrams: 300,
          acceptance: MealAcceptanceWire.parse('full'),
          fedAt: DateTime.utc(2026, 7, 22, 11),
        );
        expect(mealOutcome, isA<HealthNutritionMutationUiSuccess>());
        expect(nutritionGateway.plannedCalls, 1);

        // Adhoc meal
        final adhocOutcome = await mutationController.createAdhocMeal(
          dogId: 'dog-1',
          period: MealPeriodWire.parseCanonical('afternoon'),
          offeredGrams: 100,
          acceptance: MealAcceptanceWire.parse('full'),
          fedAt: DateTime.utc(2026, 7, 22, 15),
        );
        expect(adhocOutcome, isA<HealthNutritionMutationUiSuccess>());
        expect(nutritionGateway.adhocCalls, 1);

        // Supplement
        final suppOutcome = await mutationController.createSupplement(
          dogId: 'dog-1',
          supplementName: 'Ômega 3',
          dose: 1,
          unit: SupplementDoseUnit.parse('tablet'),
          administeredAt: DateTime.utc(2026, 7, 22, 12),
        );
        expect(suppOutcome, isA<HealthNutritionMutationUiSuccess>());
        expect(nutritionGateway.supplementCalls, 1);
      });

      test('2.2 trusted-time unavailable blocks temporal actions fail-closed', () async {
        final clock = _FakeMonotonicClock();
        final gateway = _MockTimeGateway(
          onFetch: () async => throw const AuthoritativeTimeFailure(
            AuthoritativeTimeFailureCode.unavailable,
            'Indisponível',
          ),
        );
        final provider = AuthoritativeTimeProvider(
          gateway: gateway,
          monotonicClock: clock,
        );
        final source = CoexistenceNutritionReadSource(
          canonicalPlanReader: _StaticPlanReader([_dummyPlan('p1', 'dog-1')]),
        );
        final controller = HealthNutritionReadController(
          source: source,
          authoritativeTimeProvider: provider,
        );

        await controller.selectDog('dog-1');

        expect(controller.temporalActionsAllowed, isFalse);
        expect(
          controller.temporalState,
          HealthNutritionTemporalState.unavailable,
        );
        expect(controller.todayResult?.isError, isTrue);
        expect(
          controller.todayResult?.code,
          'authoritative_time_unavailable',
        );

        controller.dispose();
      });

      test('2.3 midnight/timezone boundary (America/Sao_Paulo UTC-3)', () {
        const tz = 'America/Sao_Paulo';

        // 23:59:00 em São Paulo em 2026-07-22 corresponde a 2026-07-23T02:59:00Z em UTC
        final instantDay1 = DateTime.utc(2026, 7, 23, 2, 59, 0);
        final serviceDate1 = LocalServiceDate.fromInstant(instantDay1, timezone: tz);
        expect(serviceDate1.toString(), '2026-07-22');

        // 00:01:00 em São Paulo em 2026-07-23 corresponde a 2026-07-23T03:01:00Z em UTC
        final instantDay2 = DateTime.utc(2026, 7, 23, 3, 1, 0);
        final serviceDate2 = LocalServiceDate.fromInstant(instantDay2, timezone: tz);
        expect(serviceDate2.toString(), '2026-07-23');

        // Occurrence keys criadas a partir desses instantes pertencem a dias distintos
        final occKey1 = MealOccurrenceKey(
          dogId: 'dog-1',
          planId: 'p1',
          plannedMealId: 'slot-1',
          localServiceDate: serviceDate1,
        );
        final occKey2 = MealOccurrenceKey(
          dogId: 'dog-1',
          planId: 'p1',
          plannedMealId: 'slot-1',
          localServiceDate: serviceDate2,
        );
        expect(occKey1.localServiceDate, isNot(equals(occKey2.localServiceDate)));
      });

      test('2.4 duplicate submit is blocked while request is in flight', () async {
        nutritionGateway.delay = const Duration(milliseconds: 50);

        final future1 = mutationController.createPlannedMeal(
          dogId: 'dog-1',
          planId: 'p1',
          plannedMealId: 'slot-1',
          offeredGrams: 300,
          acceptance: MealAcceptanceWire.parse('full'),
          fedAt: DateTime.utc(2026, 7, 22, 11),
        );
        final future2 = mutationController.createPlannedMeal(
          dogId: 'dog-1',
          planId: 'p1',
          plannedMealId: 'slot-1',
          offeredGrams: 300,
          acceptance: MealAcceptanceWire.parse('full'),
          fedAt: DateTime.utc(2026, 7, 22, 11),
        );

        final outcome1 = await future1;
        final outcome2 = await future2;

        expect(outcome1, isA<HealthNutritionMutationUiSuccess>());
        expect(outcome2, isA<HealthNutritionMutationUiBlocked>());
        expect(nutritionGateway.plannedCalls, 1);
      });
    });

    // ══════════════════════════════════════════════════════════════════════════
    // 3. AGENDA WRITES REGRESSION
    // ══════════════════════════════════════════════════════════════════════════
    group('3. Agenda Writes & "SALVANDO..." Recovery', () {
      late FakeHealthScheduleSource scheduleSource;
      late HealthScheduleController scheduleController;
      late _MockScheduleGateway scheduleGateway;
      late HealthScheduleMutationController mutationController;

      setUp(() {
        scheduleSource = FakeHealthScheduleSource();
        scheduleController = HealthScheduleController(
          source: scheduleSource,
          temporalPolicy: testSchedulePolicy(),
          clock: () => scheduleTestNow,
        );
        scheduleGateway = _MockScheduleGateway();
        mutationController = HealthScheduleMutationController(
          gateway: scheduleGateway,
          scheduleController: scheduleController,
          operationIdFactory: () => 'op-reg-1',
        );
      });

      tearDown(() {
        mutationController.dispose();
        scheduleController.dispose();
        scheduleSource.reset();
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

      testWidgets('3.1 successful save completes and closes the form', (tester) async {
        scheduleSource.enqueuePage(schedulePage(const []));
        await scheduleController.setQuery(HealthScheduleQuery(dogId: 'dog-1'));

        await tester.pumpWidget(
          wrap(
            HealthScheduleItemFormScreen(
              mode: HealthScheduleItemFormMode.create,
              dogId: 'dog-1',
              mutationController: mutationController,
            ),
          ),
        );
        await tester.pump();

        // Preenche título
        await tester.enterText(
          find.byKey(const ValueKey('schedule-form-title')),
          'Vermifugação Semestral',
        );
        await tester.pump();

        // Toca em SALVAR
        await tester.tap(find.text(HealthScheduleMutationUserCopy.saveLabel));
        await tester.pumpAndSettle();

        expect(scheduleGateway.createCalls, 1);
        // O formulário fechou (não encontra mais o título do formulário)
        expect(
          find.text(HealthScheduleMutationUserCopy.createFormTitle),
          findsNothing,
        );
      });

      testWidgets(
        '3.2 backend failure shows error, preserves inputs, and resets button from SALVANDO... to SALVAR',
        (tester) async {
          scheduleSource.enqueuePage(schedulePage(const []));
          await scheduleController.setQuery(HealthScheduleQuery(dogId: 'dog-1'));

          scheduleGateway.next = const HealthScheduleMutationErrorResult(
            HealthScheduleMutationOffline(
              'Sem conexão para mutar a agenda.',
            ),
          );

          await tester.pumpWidget(
            wrap(
              HealthScheduleItemFormScreen(
                mode: HealthScheduleItemFormMode.create,
                dogId: 'dog-1',
                mutationController: mutationController,
              ),
            ),
          );
          await tester.pump();

          // Digita título e observações
          await tester.enterText(
            find.byKey(const ValueKey('schedule-form-title')),
            'Consulta Ortopédica',
          );
          await tester.pump();

          // Toca em SALVAR
          await tester.tap(find.text(HealthScheduleMutationUserCopy.saveLabel));
          await tester.pumpAndSettle();

          // Botão NÃO pode ficar preso em 'SALVANDO...'!
          expect(find.text(HealthScheduleMutationUserCopy.savingLabel), findsNothing);
          expect(find.text(HealthScheduleMutationUserCopy.saveLabel), findsOneWidget);

          // Dados preservados no input
          expect(find.text('Consulta Ortopédica'), findsOneWidget);

          // Mensagem de erro exibida no banner
          expect(
            find.textContaining('Sem conexão'),
            findsOneWidget,
          );

          // Permite retry: agora configura sucesso no gateway
          scheduleGateway.next = null;
          await tester.tap(find.text(HealthScheduleMutationUserCopy.saveLabel));
          await tester.pumpAndSettle();

          expect(scheduleGateway.createCalls, 2);
          // Fechou após sucesso no retry
          expect(
            find.text(HealthScheduleMutationUserCopy.createFormTitle),
            findsNothing,
          );
        },
      );

      testWidgets(
        '3.3 timeout during save resets SALVANDO... and allows retry without losing input',
        (tester) async {
          scheduleSource.enqueuePage(schedulePage(const []));
          await scheduleController.setQuery(HealthScheduleQuery(dogId: 'dog-1'));

          final completer = Completer<HealthScheduleMutationResult>();
          scheduleGateway.onCreate = (cmd) => completer.future;

          await tester.pumpWidget(
            wrap(
              HealthScheduleItemFormScreen(
                mode: HealthScheduleItemFormMode.create,
                dogId: 'dog-1',
                mutationController: mutationController,
              ),
            ),
          );
          await tester.pump();

          // Preenche formulário
          await tester.enterText(
            find.byKey(const ValueKey('schedule-form-title')),
            'Exame de Sangue',
          );
          await tester.pump();

          // Toca em SALVAR
          await tester.tap(find.text(HealthScheduleMutationUserCopy.saveLabel));
          await tester.pump();

          // Logo após o toque, o botão mostra SALVANDO...
          expect(
            find.text(HealthScheduleMutationUserCopy.savingLabel),
            findsOneWidget,
          );

          // Simula o timeout do formulário (25 segundos)
          await tester.pump(const Duration(seconds: 26));
          await tester.pumpAndSettle();

          // Botão retornou para SALVAR e NÃO está mais em SALVANDO...
          expect(
            find.text(HealthScheduleMutationUserCopy.savingLabel),
            findsNothing,
          );
          expect(
            find.text(HealthScheduleMutationUserCopy.saveLabel),
            findsOneWidget,
          );

          // O texto original foi mantido (sem perda de trabalho do operador)
          expect(find.text('Exame de Sangue'), findsOneWidget);

          // Banner de erro de timeout exibido
          expect(
            find.textContaining('Tempo limite esgotado'),
            findsOneWidget,
          );

          // Completa o backend e permite nova tentativa com sucesso
          scheduleGateway.onCreate = null;
          await tester.tap(find.text(HealthScheduleMutationUserCopy.saveLabel));
          await tester.pumpAndSettle();

          expect(scheduleGateway.createCalls, 2);
          // Formulário salvo e fechado com sucesso
          expect(
            find.text(HealthScheduleMutationUserCopy.createFormTitle),
            findsNothing,
          );
        },
      );

      test('3.4 HealthFormController guarantees no stuck submitting state on any error', () async {
        final form = HealthFormController();
        form.markDirty();

        // Timeout na action
        final timeoutCompleter = Completer<void>();
        final okTimeout = await form.submit(
          timeout: const Duration(milliseconds: 50),
          action: () => timeoutCompleter.future,
        );

        expect(okTimeout, isFalse);
        expect(form.isSubmitting, isFalse);
        expect(form.status, HealthFormStatus.error);
        expect(form.isDirty, isTrue);

        // Exceção genérica síncrona/assíncrona
        final okError = await form.submit(
          action: () async => throw Exception('falha de rede'),
        );

        expect(okError, isFalse);
        expect(form.isSubmitting, isFalse);
        expect(form.status, HealthFormStatus.error);
        expect(form.isDirty, isTrue);

        form.dispose();
      });
    });
  });
}
