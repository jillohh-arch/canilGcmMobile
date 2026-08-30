// ignore_for_file: avoid_print

import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:integration_test/integration_test.dart';

import 'package:canil_gcm/features/health/data/nutrition/firebase_functions_health_nutrition_mutation_gateway.dart';
import 'package:canil_gcm/features/health/data/coexistence/nutrition/coexistence_nutrition_read_source_factory.dart';
import 'package:canil_gcm/features/health/domain/health_v1_enums.dart';
import 'package:canil_gcm/features/health/domain/health_v1_models.dart';
import 'package:canil_gcm/features/health/domain/meal_schedule_slot.dart';
import 'package:canil_gcm/features/health/domain/nutrition_plan.dart';
import 'package:canil_gcm/features/health/presentation/nutrition/health_nutrition_mutation_controller.dart';
import 'package:canil_gcm/features/health/presentation/nutrition/health_nutrition_read_controller.dart';
import 'package:canil_gcm/features/health/presentation/nutrition/health_nutrition_today_screen.dart';
import 'package:canil_gcm/features/health/presentation/nutrition/health_planned_meal_form_sheet.dart';

void main() {
  final enabled =
      const bool.fromEnvironment('HEALTH_NUTRITION_UI_E2E') ||
      Platform.environment['HEALTH_NUTRITION_UI_E2E'] == '1';
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('UI -> controller -> Functions -> Firestore -> UI refresh', (
    tester,
  ) async {
    if (!enabled) return;
    GoogleFonts.config.allowRuntimeFetching = false;
    const host = '127.0.0.1';
    final dogId = const String.fromEnvironment('HEALTH_NUTRITION_E2E_DOG');
    final email = const String.fromEnvironment('HEALTH_NUTRITION_E2E_EMAIL');
    final password = const String.fromEnvironment(
      'HEALTH_NUTRITION_E2E_PASSWORD',
    );
    assert(dogId.startsWith('dog-gate5c2a-'));

    // Android já registra o DEFAULT via google-services. A chamada sem options
    // anexa o Dart app ao default nativo em vez de tentar recriá-lo.
    print('GATE5C2A_STAGE firebase-init:start');
    await Firebase.initializeApp().timeout(const Duration(seconds: 15));
    print('GATE5C2A_STAGE firebase-init:ok');
    await FirebaseAuth.instance.useAuthEmulator(
      host,
      9099,
      automaticHostMapping: false,
    );
    FirebaseFirestore.instance.useFirestoreEmulator(
      host,
      8080,
      automaticHostMapping: false,
    );
    final functions = FirebaseFunctions.instanceFor(
      region: 'southamerica-east1',
    );
    functions.useFunctionsEmulator(
      host,
      5001,
      automaticHostMapping: false,
    );
    print('GATE5C2A_STAGE auth-signin:start');
    await FirebaseAuth.instance.signInWithEmailAndPassword(
      email: email,
      password: password,
    ).timeout(const Duration(seconds: 15));
    print('GATE5C2A_STAGE auth-signin:ok');

    var refreshCount = 0;
    Map<String, dynamic>? submittedPayload;
    final controller = HealthNutritionMutationController(
      gateway: FirebaseFunctionsHealthNutritionMutationGateway(
        invoker: (functionName, data) async {
          submittedPayload = Map<String, dynamic>.from(data);
          try {
            final result = await functions.httpsCallable(functionName).call(data);
            return Map<String, dynamic>.from(result.data as Map);
          } on FirebaseFunctionsException catch (error) {
            print(
              'GATE5C2A_CALLABLE_ERROR code=${error.code} '
              'message=${error.message} details=${error.details}',
            );
            rethrow;
          }
        },
      ),
      onRefreshAfterSuccess: () async {
        refreshCount++;
        await FirebaseFirestore.instance
            .collection('dogs')
            .doc(dogId)
            .collection('meal_logs')
            .get();
      },
    );
    final plan = NutritionPlan(
      id: 'plan-ui',
      dogId: dogId,
      foodType: 'Ração E2E',
      amountGramsPerDay: 600,
      mealsPerDay: 2,
      mealSchedule: [
        MealScheduleSlot(
          id: 'slot-am',
          period: MealPeriodWire.parseCanonical('morning'),
          scheduledTime: ScheduledTimeOfDay('08:00'),
          targetGrams: 300,
        ),
        MealScheduleSlot(
          id: 'slot-pm',
          period: MealPeriodWire.parseCanonical('night'),
          scheduledTime: ScheduledTimeOfDay('20:00'),
          targetGrams: 300,
        ),
      ],
      validFrom: DateTime.utc(2020),
      timezone: 'America/Sao_Paulo',
      recordedBy: RecordedBy(
        uid: 'seed',
        name: 'Seed E2E',
        internalRole: 'condutor',
      ),
      status: NutritionPlanStatus.active,
      schemaVersion: 1,
      revision: 1,
    );
    final serviceDate = DateTime.now().toUtc().subtract(
      const Duration(hours: 3),
    );
    final date =
        '${serviceDate.year.toString().padLeft(4, '0')}-'
        '${serviceDate.month.toString().padLeft(2, '0')}-'
        '${serviceDate.day.toString().padLeft(2, '0')}';

    print('GATE5C2A_STAGE pump-form:start');
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: HealthPlannedMealFormSheet(
            dogDisplayName: 'Rex Emulator',
            plan: plan,
            slot: plan.mealSchedule.first,
            localServiceDate: date,
            controller: controller,
            onRefreshRequested: () async {},
            // O Pixel pode estar alguns minutos adiantado em relação ao host
            // que executa o Functions Emulator; mantenha o evento inequivocamente passado.
            clock: () => DateTime.now().toUtc().subtract(
              const Duration(minutes: 5),
            ),
          ),
        ),
      ),
    );
    // A folha mantem animacoes de cursor/progresso capazes de impedir settle
    // indefinidamente em aparelho real. Um pump delimitado basta para layout.
    await tester.pump(const Duration(seconds: 1));
    print('GATE5C2A_STAGE pump-form:ok');
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Quantidade oferecida (g)'),
      '300',
    );
    final button = find.widgetWithText(FilledButton, 'REGISTRAR REFEIÇÃO');
    await tester.scrollUntilVisible(
      button,
      250,
      scrollable: find.byType(Scrollable).last,
    );
    print('GATE5C2A_STAGE submit:start');
    await tester.tap(button);
    for (var i = 0; i < 100; i++) {
      await tester.pump(const Duration(milliseconds: 100));
      if (refreshCount == 1) break;
    }
    print('GATE5C2A_STAGE submit:refresh=$refreshCount');
    expect(refreshCount, 1);
    final meals = await FirebaseFirestore.instance
        .collection('dogs')
        .doc(dogId)
        .collection('meal_logs')
        .where('planned_meal_id', isEqualTo: 'slot-am')
        .get();
    expect(meals.docs, hasLength(1));
    expect(meals.docs.single.data()['offered_grams'], 300);
    expect(meals.docs.single.data()['consumed_grams'], isNull);
    expect(meals.docs.single.data()['recorded_by'], isNotNull);
    final meal = meals.docs.single;
    expect(meal.data()['meal_occurrence_id'], meal.id);
    expect(meal.data()['period'], 'morning');
    expect(meal.data()['scheduled_for'], isNotNull);
    expect(meal.data()['prescription_amount_at_time'], 300);
    expect(meal.data()['recorded_at'], isNotNull);
    expect(meal.data()['revision'], 1);
    expect(meal.data()['schema_version'], 1);
    expect(meal.data()['source'], 'mobile_callable');
    expect(meal.data()['attachment_refs'], isEmpty);
    expect(
      await FirebaseFirestore.instance
          .collection('dogs')
          .doc(dogId)
          .collection('feeding_events')
          .get()
          .then((s) => s.size),
      0,
    );
    expect(submittedPayload, isNotNull);
    final replay = await functions
        .httpsCallable('healthNutritionCreateMealLog')
        .call(Map<String, dynamic>.from(submittedPayload!));
    final replayData = Map<String, dynamic>.from(replay.data as Map);
    expect(replayData['wasNoOp'], isTrue);
    expect(replayData['mealId'], meal.id);
    expect(
      await FirebaseFirestore.instance
          .collection('dogs')
          .doc(dogId)
          .collection('meal_logs')
          .get()
          .then((snapshot) => snapshot.size),
      1,
    );
    final readController = HealthNutritionReadController(
      source: CoexistenceNutritionReadSourceFactory.forFirestore(
        firestore: FirebaseFirestore.instance,
      ),
      clock: () => DateTime.now().toUtc().subtract(
        const Duration(minutes: 5),
      ),
    );
    await readController.selectDog(dogId);
    print(
      'GATE5C2A_READ snapshot=${readController.snapshotResult.status} '
      'message=${readController.snapshotResult.message} '
      'today=${readController.todayResult?.status} '
      'todayMessage=${readController.todayResult?.message}',
    );
    expect(readController.todayOrNull, isNotNull);
    expect(readController.todayOrNull!.mealsRecorded, 1);
    expect(readController.todayOrNull!.schedule, hasLength(2));
    await tester.pumpWidget(
      MaterialApp(
        key: UniqueKey(),
        home: Scaffold(
          body: HealthNutritionTodayScreen(
            controller: readController,
            mutationController: controller,
            dogDisplayName: 'Rex Emulator',
          ),
        ),
      ),
    );
    await tester.pump(const Duration(seconds: 1));
    final uiTexts = tester
        .widgetList<Text>(find.byType(Text, skipOffstage: false))
        .map((widget) => widget.data)
        .whereType<String>()
        .toList();
    expect(
      find.text('Concluída', skipOffstage: false),
      findsOneWidget,
      reason: 'UI texts: $uiTexts',
    );
    // Há dois slots; somente o segundo continua pendente e conserva CTA.
    expect(
      find.text('Registrar refeição', skipOffstage: false),
      findsOneWidget,
    );
    expect(find.text('300 g', skipOffstage: false), findsWidgets);
    readController.dispose();
    expect(
      await FirebaseFirestore.instance
          .collection('dogs')
          .doc(dogId)
          .collection('feedings')
          .get()
          .then((s) => s.size),
      0,
    );
  });
}
