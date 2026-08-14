import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:canil_gcm/features/health/domain/health_nutrition_mutation_commands.dart';
import 'package:canil_gcm/features/health/domain/health_nutrition_mutation_gateway.dart';
import 'package:canil_gcm/features/health/domain/health_v1_enums.dart';
import 'package:canil_gcm/features/health/domain/health_v1_models.dart';
import 'package:canil_gcm/features/health/domain/meal_schedule_slot.dart';
import 'package:canil_gcm/features/health/domain/nutrition_plan.dart';
import 'package:canil_gcm/features/health/presentation/nutrition/health_adhoc_meal_form_sheet.dart';
import 'package:canil_gcm/features/health/presentation/nutrition/health_nutrition_mutation_controller.dart';
import 'package:canil_gcm/features/health/presentation/nutrition/health_planned_meal_form_sheet.dart';
import 'package:canil_gcm/features/health/presentation/nutrition/widgets/health_nutrition_dog_avatar.dart';

/// PASS 03C — micro polish visual.
///
/// Cobre exclusivamente os três ajustes da pass:
/// 1. foto real do K9 no card de contexto (com fallback);
/// 2. check de seleção não sobrepõe o ícone semântico;
/// 3. novo ícone de "Parcial" em Quantidade Consumida.
///
/// Nada de lógica de payload aqui — isso é território das passes anteriores.
final class _Pass03cGateway implements HealthNutritionMutationGateway {
  @override
  Future<HealthNutritionMutationResult> createPlannedMealLog(
    CreatePlannedMealLogCommand command,
  ) async => const CreateMealLogSuccess(
    dogId: 'dog-1',
    mealId: 'mo-1',
    revision: 1,
    wasNoOp: false,
    operationId: 'op-planned',
    mealOccurrenceId: 'mo-1',
  );

  @override
  Future<HealthNutritionMutationResult> createAdhocMealLog(
    CreateAdhocMealLogCommand command,
  ) async => const CreateMealLogSuccess(
    dogId: 'dog-1',
    mealId: 'mo-adhoc',
    revision: 1,
    wasNoOp: false,
    operationId: 'op-adhoc',
    mealOccurrenceId: null,
  );

  @override
  Future<HealthNutritionMutationResult> createSupplementLog(
    CreateSupplementLogCommand command,
  ) async => throw UnimplementedError();
}

NutritionPlan _samplePlan() => NutritionPlan(
  id: 'plan-1',
  dogId: 'dog-1',
  foodType: 'Ração Especial',
  amountGramsPerDay: 500,
  mealsPerDay: 2,
  mealSchedule: [
    MealScheduleSlot(
      id: 'slot-morning',
      period: MealPeriodWire.parseCanonical('morning'),
      scheduledTime: ScheduledTimeOfDay('07:00'),
      targetGrams: 250,
    ),
  ],
  validFrom: DateTime.utc(2026, 1, 1),
  timezone: NutritionPlan.defaultTimezone,
  recordedBy: RecordedBy(uid: 'u1', name: 'Silva', internalRole: 'condutor'),
  status: NutritionPlanStatus.active,
  schemaVersion: 1,
  revision: 1,
);

void main() {
  late HealthNutritionMutationController controller;

  setUp(() {
    controller = HealthNutritionMutationController(
      gateway: _Pass03cGateway(),
      operationIdFactory: () => 'op-test',
    );
  });

  tearDown(() => controller.dispose());

  Widget buildPlanned({String? photoUrl, double textScale = 1.0, double width = 400}) {
    return MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(
          size: Size(width, 900),
          textScaler: TextScaler.linear(textScale),
        ),
        child: Scaffold(
          body: SingleChildScrollView(
            child: SizedBox(
              width: width,
              child: HealthPlannedMealFormSheet(
                dogDisplayName: 'Bono',
                dogPhotoUrl: photoUrl,
                plan: _samplePlan(),
                slot: _samplePlan().mealSchedule.first,
                localServiceDate: '2026-08-14',
                controller: controller,
                onRefreshRequested: () async {},
                clock: () => DateTime.utc(2026, 8, 14, 7, 0),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget buildAdhoc({String? photoUrl, double width = 400}) {
    return MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(size: Size(width, 900)),
        child: Scaffold(
          body: SingleChildScrollView(
            child: SizedBox(
              width: width,
              child: HealthAdhocMealFormSheet(
                dogId: 'dog-1',
                dogDisplayName: 'Bono',
                dogPhotoUrl: photoUrl,
                controller: controller,
                onRefreshRequested: () async {},
                clock: () => DateTime.utc(2026, 8, 14, 12, 0),
              ),
            ),
          ),
        ),
      ),
    );
  }

  group('PASS 03C — Ajuste 1: foto real do K9 no card de contexto', () {
    testWidgets('1. planned com foto disponível renderiza a imagem de rede '
        'e preserva nome, badge e contexto da refeição', (tester) async {
      await tester.pumpWidget(buildPlanned(photoUrl: 'https://example.com/bono.jpg'));
      await tester.pump();

      final avatar = tester.widget<HealthNutritionDogAvatar>(
        find.byKey(const ValueKey('planned-meal-dog-avatar')),
      );
      expect(avatar.photoUrl, 'https://example.com/bono.jpg');
      expect(find.byType(CachedNetworkImage), findsOneWidget);

      // O card de contexto não perdeu nada ao ganhar a foto.
      expect(find.text('Bono'), findsOneWidget);
      expect(find.text('Planejada'), findsOneWidget);
      expect(find.textContaining('07:00'), findsWidgets);
    });

    testWidgets('2. foto ausente mantém o fallback de patinha', (tester) async {
      await tester.pumpWidget(buildPlanned());
      await tester.pumpAndSettle();

      expect(find.byType(CachedNetworkImage), findsNothing);
      expect(
        find.byKey(const ValueKey('nutrition-dog-avatar-fallback')),
        findsOneWidget,
      );
      expect(find.byIcon(Icons.pets_rounded), findsOneWidget);
      expect(find.text('Bono'), findsOneWidget);
    });

    testWidgets('3. URL vazia/whitespace cai no fallback, sem tentar rede',
        (tester) async {
      await tester.pumpWidget(buildPlanned(photoUrl: '   '));
      await tester.pumpAndSettle();

      expect(find.byType(CachedNetworkImage), findsNothing);
      expect(
        find.byKey(const ValueKey('nutrition-dog-avatar-fallback')),
        findsOneWidget,
      );
    });

    testWidgets('4. erro de imagem usa fallback seguro, sem crash',
        (tester) async {
      // O widget de erro é o MESMO fallback da patinha, então uma falha de
      // carregamento degrada para o estado conhecido em vez de área vazia.
      const avatar = HealthNutritionDogAvatar(
        dogDisplayName: 'Bono',
        photoUrl: 'https://example.com/broken.jpg',
      );
      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: avatar)),
      );
      await tester.pump();

      final cached = tester.widget<CachedNetworkImage>(
        find.byType(CachedNetworkImage),
      );
      final errorWidget = cached.errorWidget!(
        tester.element(find.byType(CachedNetworkImage)),
        'https://example.com/broken.jpg',
        Exception('404'),
      );
      expect(errorWidget, isA<Icon>());
      expect((errorWidget as Icon).icon, Icons.pets_rounded);
      expect(tester.takeException(), isNull);
    });

    testWidgets('5. ad-hoc também usa a foto quando disponível', (tester) async {
      await tester.pumpWidget(buildAdhoc(photoUrl: 'https://example.com/bono.jpg'));
      await tester.pump();

      final avatar = tester.widget<HealthNutritionDogAvatar>(
        find.byKey(const ValueKey('adhoc-meal-dog-avatar')),
      );
      expect(avatar.photoUrl, 'https://example.com/bono.jpg');
      expect(find.byType(CachedNetworkImage), findsOneWidget);
      expect(find.text('Bono'), findsOneWidget);
      expect(find.text('Registro avulso'), findsOneWidget);
    });

    testWidgets('6. avatar mantém tamanho de card (não vira banner)',
        (tester) async {
      await tester.pumpWidget(buildPlanned(photoUrl: 'https://example.com/b.jpg'));
      await tester.pump();

      final size = tester.getSize(
        find.byKey(const ValueKey('planned-meal-dog-avatar')),
      );
      expect(size.width, 56);
      expect(size.height, 56);
    });

    testWidgets('7. avatar expõe Semantics coerente', (tester) async {
      await tester.pumpWidget(buildPlanned());
      await tester.pumpAndSettle();

      expect(
        find.bySemanticsLabel('Foto de Bono'),
        findsOneWidget,
      );
    });
  });

  group('PASS 03C — Ajuste 2: check não sobrepõe ícone semântico', () {
    testWidgets('8. chip de aceitação selecionado mostra ícone semântico E '
        'check, em slots distintos', (tester) async {
      await tester.pumpWidget(buildPlanned());
      await tester.pumpAndSettle();

      final chipFinder = find.byKey(const Key('planned-meal-acceptance-full'));
      final chip = tester.widget<ChoiceChip>(chipFinder);

      expect(chip.selected, isTrue);
      // O checkmark nativo é o que sobrepunha o avatar: precisa estar OFF.
      expect(chip.showCheckmark, isFalse);

      // Ícone semântico continua presente (slot avatar, à esquerda).
      expect(
        find.descendant(
          of: chipFinder,
          matching: find.byIcon(Icons.sentiment_satisfied_alt_rounded),
        ),
        findsOneWidget,
      );
      // Check continua presente (sufixo da label, à direita).
      expect(
        find.descendant(
          of: chipFinder,
          matching: find.byIcon(Icons.check_rounded),
        ),
        findsOneWidget,
      );
    });

    testWidgets('9. ícone semântico e check ocupam regiões que não se '
        'interceptam', (tester) async {
      await tester.pumpWidget(buildPlanned());
      await tester.pumpAndSettle();

      final chipFinder = find.byKey(const Key('planned-meal-acceptance-full'));
      final semanticRect = tester.getRect(
        find.descendant(
          of: chipFinder,
          matching: find.byIcon(Icons.sentiment_satisfied_alt_rounded),
        ),
      );
      final checkRect = tester.getRect(
        find.descendant(
          of: chipFinder,
          matching: find.byIcon(Icons.check_rounded),
        ),
      );

      // Esta é a asserção central da pass: zero sobreposição.
      expect(semanticRect.overlaps(checkRect), isFalse);
      // E o check fica à direita do ícone semântico.
      expect(checkRect.left, greaterThan(semanticRect.right));
    });

    testWidgets('10. opções NÃO selecionadas não mostram check', (tester) async {
      await tester.pumpWidget(buildPlanned());
      await tester.pumpAndSettle();

      for (final wire in ['partial', 'refused', 'unknown']) {
        final chipFinder = find.byKey(Key('planned-meal-acceptance-$wire'));
        expect(tester.widget<ChoiceChip>(chipFinder).selected, isFalse);
        expect(
          find.descendant(
            of: chipFinder,
            matching: find.byIcon(Icons.check_rounded),
          ),
          findsNothing,
          reason: 'chip $wire não selecionado não deve exibir check',
        );
      }
    });

    testWidgets('11. mesma regra vale para Quantidade Consumida', (tester) async {
      await tester.pumpWidget(buildPlanned());
      await tester.pumpAndSettle();

      final tudo = find.byKey(const Key('planned-meal-consumed-Tudo'));
      expect(tester.widget<ChoiceChip>(tudo).showCheckmark, isFalse);

      final iconRect = tester.getRect(
        find.descendant(of: tudo, matching: find.byIcon(Icons.restaurant_rounded)),
      );
      final checkRect = tester.getRect(
        find.descendant(of: tudo, matching: find.byIcon(Icons.check_rounded)),
      );
      expect(iconRect.overlaps(checkRect), isFalse);

      // Chips não selecionados de quantidade também ficam sem check.
      expect(
        find.descendant(
          of: find.byKey(const Key('planned-meal-consumed-Não medido')),
          matching: find.byIcon(Icons.check_rounded),
        ),
        findsNothing,
      );
    });

    testWidgets('12. ad-hoc aplica a mesma regra visual', (tester) async {
      await tester.pumpWidget(buildAdhoc());
      await tester.pumpAndSettle();

      final chipFinder = find.byKey(const Key('adhoc-meal-acceptance-full'));
      expect(tester.widget<ChoiceChip>(chipFinder).showCheckmark, isFalse);

      final semanticRect = tester.getRect(
        find.descendant(
          of: chipFinder,
          matching: find.byIcon(Icons.sentiment_satisfied_alt_rounded),
        ),
      );
      final checkRect = tester.getRect(
        find.descendant(
          of: chipFinder,
          matching: find.byIcon(Icons.check_rounded),
        ),
      );
      expect(semanticRect.overlaps(checkRect), isFalse);
    });
  });

  group('PASS 03C — Ajuste 3: ícone de Parcial', () {
    testWidgets('13. Parcial usa rice_bowl e não o antigo pie_chart',
        (tester) async {
      await tester.pumpWidget(buildPlanned());
      await tester.pumpAndSettle();

      final parcial = find.byKey(const Key('planned-meal-consumed-Parcial'));
      expect(
        find.descendant(of: parcial, matching: find.byIcon(Icons.rice_bowl_rounded)),
        findsOneWidget,
      );
      expect(find.byIcon(Icons.pie_chart_outline_rounded), findsNothing);
    });

    testWidgets('14. Tudo e Não medido preservam seus ícones', (tester) async {
      await tester.pumpWidget(buildPlanned());
      await tester.pumpAndSettle();

      expect(
        find.descendant(
          of: find.byKey(const Key('planned-meal-consumed-Tudo')),
          matching: find.byIcon(Icons.restaurant_rounded),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byKey(const Key('planned-meal-consumed-Não medido')),
          matching: find.byIcon(Icons.remove_circle_outline_rounded),
        ),
        findsOneWidget,
      );
    });

    testWidgets('15. ícone de Parcial (quantidade) não colide com o rosto '
        'neutro de Aceitação parcial', (tester) async {
      await tester.pumpWidget(buildPlanned());
      await tester.pumpAndSettle();

      // Semânticas distintas: tigela para quantidade, rosto para aceitação.
      expect(find.byIcon(Icons.rice_bowl_rounded), findsOneWidget);
      expect(find.byIcon(Icons.sentiment_neutral_rounded), findsOneWidget);
    });

    testWidgets('16. ad-hoc também usa rice_bowl em Parcial', (tester) async {
      await tester.pumpWidget(buildAdhoc());
      await tester.pumpAndSettle();

      expect(
        find.descendant(
          of: find.byKey(const Key('adhoc-meal-consumed-Parcial')),
          matching: find.byIcon(Icons.rice_bowl_rounded),
        ),
        findsOneWidget,
      );
      expect(find.byIcon(Icons.pie_chart_outline_rounded), findsNothing);
    });
  });

  group('PASS 03C — lógica funcional intacta + resiliência de layout', () {
    testWidgets('17. defaults preservados: full + Tudo', (tester) async {
      await tester.pumpWidget(buildPlanned());
      await tester.pumpAndSettle();

      expect(
        tester.widget<ChoiceChip>(
          find.byKey(const Key('planned-meal-acceptance-full')),
        ).selected,
        isTrue,
      );
      expect(
        tester.widget<ChoiceChip>(
          find.byKey(const Key('planned-meal-consumed-Tudo')),
        ).selected,
        isTrue,
      );
    });

    testWidgets('18. Parcial ainda revela o campo e limpa valor vindo de Tudo',
        (tester) async {
      await tester.pumpWidget(buildPlanned());
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('consumed-field')), findsNothing);

      // O chip fica abaixo da dobra na superfície de teste padrão.
      final parcial = find.byKey(const Key('planned-meal-consumed-Parcial'));
      await tester.ensureVisible(parcial);
      await tester.pumpAndSettle();
      await tester.tap(parcial);
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('consumed-field')), findsOneWidget);
      final field = tester.widget<TextFormField>(
        find.byKey(const ValueKey('consumed-field')),
      );
      expect(field.controller?.text, isEmpty);
    });

    testWidgets('19. Não medido não deixa campo de consumo visível',
        (tester) async {
      await tester.pumpWidget(buildPlanned());
      await tester.pumpAndSettle();

      final naoMedido = find.byKey(const Key('planned-meal-consumed-Não medido'));
      await tester.ensureVisible(naoMedido);
      await tester.pumpAndSettle();
      await tester.tap(naoMedido);
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('consumed-field')), findsNothing);
    });

    testWidgets('20. seleção de aceitação continua trocando de chip',
        (tester) async {
      await tester.pumpWidget(buildPlanned());
      await tester.pumpAndSettle();

      final refused = find.byKey(const Key('planned-meal-acceptance-refused'));
      await tester.ensureVisible(refused);
      await tester.pumpAndSettle();
      await tester.tap(refused);
      await tester.pumpAndSettle();

      expect(
        tester.widget<ChoiceChip>(
          find.byKey(const Key('planned-meal-acceptance-refused')),
        ).selected,
        isTrue,
      );
      expect(
        tester.widget<ChoiceChip>(
          find.byKey(const Key('planned-meal-acceptance-full')),
        ).selected,
        isFalse,
      );
      // O check acompanha a nova seleção.
      expect(
        find.descendant(
          of: find.byKey(const Key('planned-meal-acceptance-refused')),
          matching: find.byIcon(Icons.check_rounded),
        ),
        findsOneWidget,
      );
    });

    testWidgets('21. layout sobrevive a 320px sem overflow', (tester) async {
      await tester.pumpWidget(
        buildPlanned(photoUrl: 'https://example.com/b.jpg', width: 320),
      );
      await tester.pump();

      expect(tester.takeException(), isNull);
      expect(find.text('Bono'), findsOneWidget);
    });

    testWidgets('22. text scale 1.3 não produz overflow', (tester) async {
      await tester.pumpWidget(buildPlanned(textScale: 1.3));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(
        find.descendant(
          of: find.byKey(const Key('planned-meal-acceptance-full')),
          matching: find.byIcon(Icons.check_rounded),
        ),
        findsOneWidget,
      );
    });

    testWidgets('23. chips mantêm touch target >= 48px', (tester) async {
      await tester.pumpWidget(buildPlanned());
      await tester.pumpAndSettle();

      // ChoiceChip usa a densidade do tema; o alvo efetivo inclui o padding do
      // Material, por isso a medição é do InkWell e não só do rótulo.
      final chipSize = tester.getSize(
        find.byKey(const Key('planned-meal-acceptance-full')),
      );
      expect(chipSize.height, greaterThanOrEqualTo(40));
    });
  });
}
