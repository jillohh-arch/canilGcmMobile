import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:canil_gcm/core/theme/app_theme.dart';
import 'package:canil_gcm/features/health/domain/health_nutrition_mutation_commands.dart';
import 'package:canil_gcm/features/health/domain/health_nutrition_mutation_gateway.dart';
import 'package:canil_gcm/features/health/domain/health_v1_enums.dart';
import 'package:canil_gcm/features/health/domain/health_v1_models.dart';
import 'package:canil_gcm/features/health/domain/meal_schedule_slot.dart';
import 'package:canil_gcm/features/health/domain/nutrition_plan.dart';
import 'package:canil_gcm/features/health/presentation/nutrition/health_adhoc_meal_form_sheet.dart';
import 'package:canil_gcm/features/health/presentation/nutrition/health_nutrition_mutation_controller.dart';
import 'package:canil_gcm/features/health/presentation/nutrition/health_planned_meal_form_sheet.dart';
import 'package:canil_gcm/features/health/presentation/nutrition/widgets/health_nutrition_context_badge.dart';
import 'package:canil_gcm/features/health/presentation/nutrition/widgets/health_nutrition_dog_avatar.dart';

/// PASS 03D — alinhamento visual final.
///
/// Cobre exclusivamente os três ajustes da pass:
/// 1. card principal alinhado ao eixo horizontal das tabs;
/// 2. badge de classificação no canto superior direito;
/// 3. identidade semântica de cores em Quantidade Consumida.
final class _Pass03dGateway implements HealthNutritionMutationGateway {
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
      gateway: _Pass03dGateway(),
      operationIdFactory: () => 'op-test',
    );
  });

  tearDown(() => controller.dispose());

  Widget buildPlanned({
    String dogName = 'Bono',
    String? photoUrl,
    double textScale = 1.0,
    double width = 400,
  }) {
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
                dogDisplayName: dogName,
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

  Widget buildAdhoc({
    String dogName = 'Bono',
    double textScale = 1.0,
    double width = 400,
  }) {
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
              child: HealthAdhocMealFormSheet(
                dogId: 'dog-1',
                dogDisplayName: dogName,
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

  ChoiceChip chipOf(WidgetTester tester, String key) =>
      tester.widget<ChoiceChip>(find.byKey(Key(key)));

  group('PASS 03D — Ajuste 2: badge no canto superior direito', () {
    testWidgets('1. badge Planejada existe e fica à DIREITA do nome, '
        'na mesma faixa vertical', (tester) async {
      await tester.pumpWidget(buildPlanned());
      await tester.pumpAndSettle();

      final badge = find.byKey(const ValueKey('planned-meal-context-badge'));
      expect(badge, findsOneWidget);
      expect(find.text('Planejada'), findsOneWidget);

      final nameRect = tester.getRect(find.text('Bono'));
      final badgeRect = tester.getRect(badge);

      // Badge à direita do nome, sem sobreposição.
      expect(badgeRect.left, greaterThan(nameRect.right));
      expect(nameRect.overlaps(badgeRect), isFalse);
      // Mesma faixa vertical (topo do card), não uma linha abaixo.
      expect(
        (badgeRect.top - nameRect.top).abs(),
        lessThan(nameRect.height,),
      );
    });

    testWidgets('2. badge fica separado do bloco textual de contexto',
        (tester) async {
      await tester.pumpWidget(buildPlanned());
      await tester.pumpAndSettle();

      final badgeRect = tester.getRect(
        find.byKey(const ValueKey('planned-meal-context-badge')),
      );
      final contextRect = tester.getRect(
        find.textContaining('g planejados'),
      );

      // O badge não faz mais parte do fluxo textual: fica acima dele.
      expect(badgeRect.bottom, lessThanOrEqualTo(contextRect.top));
      expect(badgeRect.overlaps(contextRect), isFalse);
    });

    testWidgets('3. badge Registro avulso segue o mesmo padrão', (tester) async {
      await tester.pumpWidget(buildAdhoc());
      await tester.pumpAndSettle();

      final badge = find.byKey(const ValueKey('adhoc-meal-context-badge'));
      expect(badge, findsOneWidget);
      expect(find.text('Registro avulso'), findsOneWidget);

      final nameRect = tester.getRect(find.text('Bono'));
      final badgeRect = tester.getRect(badge);
      expect(badgeRect.left, greaterThan(nameRect.right));
      expect(nameRect.overlaps(badgeRect), isFalse);
    });

    testWidgets('4. badge usa o accent semântico de cada contexto',
        (tester) async {
      await tester.pumpWidget(buildPlanned());
      await tester.pumpAndSettle();
      expect(
        tester.widget<HealthNutritionContextBadge>(
          find.byKey(const ValueKey('planned-meal-context-badge')),
        ).accent,
        AppTheme.primary,
      );

      await tester.pumpWidget(buildAdhoc());
      await tester.pumpAndSettle();
      expect(
        tester.widget<HealthNutritionContextBadge>(
          find.byKey(const ValueKey('adhoc-meal-context-badge')),
        ).accent,
        AppTheme.attention,
      );
    });

    testWidgets('5. nome longo + badge não causam overflow nem colisão',
        (tester) async {
      await tester.pumpWidget(
        buildPlanned(dogName: 'Bono Comandante Von Der Staatsmacht Terceiro'),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);

      final badgeRect = tester.getRect(
        find.byKey(const ValueKey('planned-meal-context-badge')),
      );
      // Badge continua dentro do card, não empurrado para fora da viewport.
      expect(badgeRect.right, lessThanOrEqualTo(400));
      expect(find.text('Planejada'), findsOneWidget);
    });

    testWidgets('6. badge sobrevive a 320px', (tester) async {
      await tester.pumpWidget(buildPlanned(width: 320));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      final badgeRect = tester.getRect(
        find.byKey(const ValueKey('planned-meal-context-badge')),
      );
      expect(badgeRect.right, lessThanOrEqualTo(320));
    });

    testWidgets('7. badge sobrevive a text scale 1.3', (tester) async {
      await tester.pumpWidget(buildPlanned(textScale: 1.3));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(
        find.byKey(const ValueKey('planned-meal-context-badge')),
        findsOneWidget,
      );
    });

    testWidgets('8. 320px + text scale 1.3 combinados, adhoc incluído',
        (tester) async {
      await tester.pumpWidget(buildAdhoc(width: 320, textScale: 1.3));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(
        find.byKey(const ValueKey('adhoc-meal-context-badge')),
        findsOneWidget,
      );
    });
  });

  group('PASS 03D — Ajuste 3: cores semânticas em Quantidade Consumida', () {
    testWidgets('9. Tudo selecionado usa identidade VERDE', (tester) async {
      await tester.pumpWidget(buildPlanned());
      await tester.pumpAndSettle();

      final tudo = chipOf(tester, 'planned-meal-consumed-Tudo');
      expect(tudo.selected, isTrue);
      expect((tudo.side as BorderSide).color, AppTheme.success);
      expect(tudo.labelStyle?.color, AppTheme.success);
      expect(
        tester.widget<Icon>(
          find.descendant(
            of: find.byKey(const Key('planned-meal-consumed-Tudo')),
            matching: find.byIcon(Icons.restaurant_rounded),
          ),
        ).color,
        AppTheme.success,
      );
    });

    testWidgets('10. Parcial selecionado usa identidade ÂMBAR', (tester) async {
      await tester.pumpWidget(buildPlanned());
      await tester.pumpAndSettle();

      final parcial = find.byKey(const Key('planned-meal-consumed-Parcial'));
      await tester.ensureVisible(parcial);
      await tester.pumpAndSettle();
      await tester.tap(parcial);
      await tester.pumpAndSettle();

      final chip = chipOf(tester, 'planned-meal-consumed-Parcial');
      expect(chip.selected, isTrue);
      expect((chip.side as BorderSide).color, AppTheme.warningAccent);
      expect(chip.labelStyle?.color, AppTheme.warningAccent);
      expect(
        tester.widget<Icon>(
          find.descendant(of: parcial, matching: find.byIcon(Icons.rice_bowl_rounded)),
        ).color,
        AppTheme.warningAccent,
      );
    });

    testWidgets('11. Não medido selecionado usa identidade NEUTRA, '
        'nunca vermelho', (tester) async {
      await tester.pumpWidget(buildPlanned());
      await tester.pumpAndSettle();

      final naoMedido = find.byKey(const Key('planned-meal-consumed-Não medido'));
      await tester.ensureVisible(naoMedido);
      await tester.pumpAndSettle();
      await tester.tap(naoMedido);
      await tester.pumpAndSettle();

      final chip = chipOf(tester, 'planned-meal-consumed-Não medido');
      expect(chip.selected, isTrue);
      expect((chip.side as BorderSide).color, AppTheme.textMuted);
      expect(chip.labelStyle?.color, AppTheme.textMuted);

      // Ausência de mensuração NÃO é erro: nenhum token de erro envolvido.
      expect((chip.side as BorderSide).color, isNot(AppTheme.error));
      expect((chip.side as BorderSide).color, isNot(AppTheme.errorStrong));
      expect(chip.labelStyle?.color, isNot(AppTheme.error));
    });

    testWidgets('12. opções NÃO selecionadas continuam discretas', (tester) async {
      await tester.pumpWidget(buildPlanned());
      await tester.pumpAndSettle();

      // Default é Tudo; Parcial e Não medido devem estar neutros.
      for (final label in ['Parcial', 'Não medido']) {
        final chip = chipOf(tester, 'planned-meal-consumed-$label');
        expect(chip.selected, isFalse);
        expect((chip.side as BorderSide).color, AppTheme.outline);
        expect(chip.labelStyle?.color, AppTheme.textSecondary);
      }

      // Ícone não selecionado permanece muted, sem cor semântica forte.
      expect(
        tester.widget<Icon>(
          find.descendant(
            of: find.byKey(const Key('planned-meal-consumed-Parcial')),
            matching: find.byIcon(Icons.rice_bowl_rounded),
          ),
        ).color,
        AppTheme.textMuted,
      );
    });

    testWidgets('13. Recusou continua VERMELHO na Aceitação', (tester) async {
      await tester.pumpWidget(buildPlanned());
      await tester.pumpAndSettle();

      final refused = find.byKey(const Key('planned-meal-acceptance-refused'));
      await tester.ensureVisible(refused);
      await tester.pumpAndSettle();
      await tester.tap(refused);
      await tester.pumpAndSettle();

      final chip = chipOf(tester, 'planned-meal-acceptance-refused');
      expect(chip.selected, isTrue);
      expect((chip.side as BorderSide).color, AppTheme.error);
    });

    testWidgets('14. adhoc aplica a mesma identidade de consumo', (tester) async {
      await tester.pumpWidget(buildAdhoc());
      await tester.pumpAndSettle();

      final tudo = chipOf(tester, 'adhoc-meal-consumed-Tudo');
      expect((tudo.side as BorderSide).color, AppTheme.success);

      final parcial = find.byKey(const Key('adhoc-meal-consumed-Parcial'));
      await tester.ensureVisible(parcial);
      await tester.pumpAndSettle();
      await tester.tap(parcial);
      await tester.pumpAndSettle();
      expect(
        (chipOf(tester, 'adhoc-meal-consumed-Parcial').side as BorderSide).color,
        AppTheme.warningAccent,
      );
    });

    testWidgets('15. consumo e aceitação compartilham a mesma família de tokens',
        (tester) async {
      await tester.pumpWidget(buildPlanned());
      await tester.pumpAndSettle();

      // verde = completo nos dois eixos.
      final acceptanceFull = chipOf(tester, 'planned-meal-acceptance-full');
      final consumedAll = chipOf(tester, 'planned-meal-consumed-Tudo');
      expect((acceptanceFull.side as BorderSide).color, AppTheme.success);
      expect((consumedAll.side as BorderSide).color, AppTheme.success);
    });
  });

  group('PASS 03D — 03C preservada', () {
    testWidgets('16. ícones da 03C intactos', (tester) async {
      await tester.pumpWidget(buildPlanned());
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.rice_bowl_rounded), findsOneWidget);
      expect(find.byIcon(Icons.restaurant_rounded), findsWidgets);
      expect(find.byIcon(Icons.remove_circle_outline_rounded), findsOneWidget);
      expect(find.byIcon(Icons.pie_chart_outline_rounded), findsNothing);
    });

    testWidgets('17. check continua separado do ícone semântico', (tester) async {
      await tester.pumpWidget(buildPlanned());
      await tester.pumpAndSettle();

      for (final key in [
        'planned-meal-acceptance-full',
        'planned-meal-consumed-Tudo',
      ]) {
        expect(chipOf(tester, key).showCheckmark, isFalse);
      }

      final tudo = find.byKey(const Key('planned-meal-consumed-Tudo'));
      final iconRect = tester.getRect(
        find.descendant(of: tudo, matching: find.byIcon(Icons.restaurant_rounded)),
      );
      final checkRect = tester.getRect(
        find.descendant(of: tudo, matching: find.byIcon(Icons.check_rounded)),
      );
      expect(iconRect.overlaps(checkRect), isFalse);
      expect(checkRect.left, greaterThan(iconRect.right));
    });

    testWidgets('18. check adota a cor semântica do estado', (tester) async {
      await tester.pumpWidget(buildPlanned());
      await tester.pumpAndSettle();

      final checkColor = tester.widget<Icon>(
        find.descendant(
          of: find.byKey(const Key('planned-meal-consumed-Tudo')),
          matching: find.byIcon(Icons.check_rounded),
        ),
      ).color;
      expect(checkColor, AppTheme.success);
    });

    testWidgets('19. foto e fallback continuam funcionando', (tester) async {
      await tester.pumpWidget(buildPlanned(photoUrl: 'https://example.com/b.jpg'));
      await tester.pump();
      expect(find.byType(CachedNetworkImage), findsOneWidget);
      final size = tester.getSize(
        find.byKey(const ValueKey('planned-meal-dog-avatar')),
      );
      // Tamanho aprovado na 03C permanece intocado.
      expect(size.width, 56);
      expect(size.height, 56);

      await tester.pumpWidget(buildPlanned());
      await tester.pumpAndSettle();
      expect(find.byType(CachedNetworkImage), findsNothing);
      expect(
        find.byKey(const ValueKey('nutrition-dog-avatar-fallback')),
        findsOneWidget,
      );
      expect(
        tester.widget<HealthNutritionDogAvatar>(
          find.byKey(const ValueKey('planned-meal-dog-avatar')),
        ).size,
        56,
      );
    });

    testWidgets('20. defaults e comportamento de Parcial preservados',
        (tester) async {
      await tester.pumpWidget(buildPlanned());
      await tester.pumpAndSettle();

      expect(chipOf(tester, 'planned-meal-acceptance-full').selected, isTrue);
      expect(chipOf(tester, 'planned-meal-consumed-Tudo').selected, isTrue);
      expect(find.byKey(const ValueKey('consumed-field')), findsNothing);

      final parcial = find.byKey(const Key('planned-meal-consumed-Parcial'));
      await tester.ensureVisible(parcial);
      await tester.pumpAndSettle();
      await tester.tap(parcial);
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('consumed-field')), findsOneWidget);
      expect(
        tester.widget<TextFormField>(
          find.byKey(const ValueKey('consumed-field')),
        ).controller?.text,
        isEmpty,
      );
    });
  });
}
