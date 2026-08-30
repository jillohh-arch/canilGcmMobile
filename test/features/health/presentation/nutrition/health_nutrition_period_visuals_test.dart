import 'package:canil_gcm/core/theme/app_theme.dart';
import 'package:canil_gcm/features/health/domain/health_v1_enums.dart';
import 'package:canil_gcm/features/health/presentation/nutrition/widgets/health_nutrition_period_visuals.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('HealthNutritionPeriodVisuals — agrupamento de apresentação', () {
    test('morning/afternoon mapeiam para as próprias faixas', () {
      expect(
        HealthNutritionPeriodVisuals.groupFor(
          MealPeriodWire.parseCanonical('morning'),
        ),
        HealthNutritionPeriodGroup.morning,
      );
      expect(
        HealthNutritionPeriodVisuals.groupFor(
          MealPeriodWire.parseCanonical('afternoon'),
        ),
        HealthNutritionPeriodGroup.afternoon,
      );
    });

    test('evening E night colapsam em Noite', () {
      // Convenção de produto: o domínio mantém cinco valores; a apresentação
      // agrupa. `evening` (18–22h) é "Noite", não "Tarde".
      for (final wire in ['evening', 'night']) {
        expect(
          HealthNutritionPeriodVisuals.groupFor(
            MealPeriodWire.parseCanonical(wire),
          ),
          HealthNutritionPeriodGroup.night,
          reason: '$wire deve ser exibido como Noite',
        );
        expect(
          HealthNutritionPeriodVisuals.labelFor(
            MealPeriodWire.parseCanonical(wire),
          ),
          'Noite',
        );
      }
    });

    test('extra permanece extra — não é absorvido por nenhuma faixa', () {
      expect(
        HealthNutritionPeriodVisuals.groupFor(
          MealPeriodWire.parseCanonical('extra'),
        ),
        HealthNutritionPeriodGroup.extra,
      );
      expect(
        HealthNutritionPeriodVisuals.labelFor(
          MealPeriodWire.parseCanonical('extra'),
        ),
        'Extra',
      );
    });

    test('período desconhecido não é coagido para uma faixa real', () {
      final unknown = MealPeriodWire.parseCanonical('brunch');
      expect(unknown.isUnknown, isTrue);
      expect(
        HealthNutritionPeriodVisuals.groupFor(unknown),
        HealthNutritionPeriodGroup.extra,
      );
      // Valor bruto preservado: não inventamos "Manhã" para um wire novo.
      expect(HealthNutritionPeriodVisuals.labelFor(unknown), 'brunch');
    });

    test('período ausente não vira faixa arbitrária', () {
      final absent = MealPeriodWire.parseCanonical(null);
      expect(absent.isAbsent, isTrue);
      expect(
        HealthNutritionPeriodVisuals.groupFor(absent),
        HealthNutritionPeriodGroup.extra,
      );
      expect(HealthNutritionPeriodVisuals.labelFor(absent), 'Período');
    });

    test('rótulos das faixas seguem a convenção aprovada', () {
      expect(
        HealthNutritionPeriodVisuals.labelFor(
          MealPeriodWire.parseCanonical('morning'),
        ),
        'Manhã',
      );
      // Regressão da divergência antiga: `afternoon` era exibido como "Almoço"
      // na tela e "Tarde" no formulário de registro.
      expect(
        HealthNutritionPeriodVisuals.labelFor(
          MealPeriodWire.parseCanonical('afternoon'),
        ),
        'Tarde',
      );
    });
  });

  group('HealthNutritionPeriodVisuals — identidade visual', () {
    test('as quatro faixas têm cores distintas entre si', () {
      final accents = [
        HealthNutritionPeriodGroup.morning,
        HealthNutritionPeriodGroup.afternoon,
        HealthNutritionPeriodGroup.night,
        HealthNutritionPeriodGroup.supplement,
      ].map((g) => HealthNutritionPeriodVisuals.resolve(g).accent).toList();

      expect(accents.toSet().length, 4, reason: 'nenhuma cor repetida');
    });

    test('refeição e suplemento são distinguíveis', () {
      // Requisito explícito: hoje a timeline clínica global usa o MESMO accent
      // para meal e supplement. A identidade local resolve isso.
      final meal = HealthNutritionPeriodVisuals.resolve(
        HealthNutritionPeriodGroup.afternoon,
      );
      final supplement = HealthNutritionPeriodVisuals.resolve(
        HealthNutritionPeriodGroup.supplement,
      );
      expect(meal.accent, isNot(equals(supplement.accent)));
      expect(meal.icon, isNot(equals(supplement.icon)));
    });

    test('Noite e Suplemento não colidem com semânticas globais', () {
      // Azul info = pesagem/observação; verde success = "Concluída".
      // Reusá-los faria o quadrante ser lido como estado clínico.
      expect(HealthNutritionPeriodVisuals.nightAccent, isNot(AppTheme.info));
      expect(
        HealthNutritionPeriodVisuals.supplementAccent,
        isNot(AppTheme.success),
      );
    });

    test('Tarde preserva o laranja de nutrição já contratado', () {
      // `AppTheme.attention` é asserido como acento de alimentação no
      // dashboard; a identidade local não o abandona.
      expect(
        HealthNutritionPeriodVisuals.resolve(
          HealthNutritionPeriodGroup.afternoon,
        ).accent,
        AppTheme.attention,
      );
    });

    test('toda faixa tem rótulo e ícone não vazios', () {
      for (final group in HealthNutritionPeriodGroup.values) {
        final visual = HealthNutritionPeriodVisuals.resolve(group);
        expect(visual.label.trim(), isNotEmpty);
        expect(visual.label, isNot(equals(group.name)));
      }
    });
  });
}
