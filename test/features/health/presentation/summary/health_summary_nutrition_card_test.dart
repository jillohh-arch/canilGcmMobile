import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:canil_gcm/core/theme/app_theme.dart';
import 'package:canil_gcm/features/health/presentation/summary/health_summary_block_models.dart';
import 'package:canil_gcm/features/health/presentation/summary/health_summary_section_status.dart';
import 'package:canil_gcm/features/health/presentation/summary/widgets/health_summary_nutrition_card.dart';

void main() {
  setUpAll(() {
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  Future<void> pumpCard(
    WidgetTester tester,
    HealthSummaryNutritionTodayView view,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: HealthSummaryNutritionCard(
              nutrition: HealthSummarySectionData.available(view),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('oferta conhecida nunca preenche consumo desconhecido', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();

    await pumpCard(
      tester,
      const HealthSummaryNutritionTodayView(
        offeredAmount: 500,
        consumedAmount: null,
        plannedAmount: 500,
        mealsRecorded: 3,
        mealsPlanned: 3,
        unitLabel: 'g',
      ),
    );

    expect(find.text('Oferecido: 500 g de 500 g'), findsOneWidget);
    expect(find.text('Consumo não informado'), findsOneWidget);
    expect(find.text('3 de 3 refeições executadas'), findsOneWidget);
    final bars = tester.widgetList<LinearProgressIndicator>(
      find.byType(LinearProgressIndicator),
    );
    expect(bars, hasLength(1));
    expect(bars.single.value, 1);
    expect(bars.single.color, AppTheme.attention);
    expect(
      find.bySemanticsLabel(
        'Oferecido, 500 gramas de uma meta de 500 gramas, 100 por cento.',
      ),
      findsOneWidget,
    );
    expect(
      find.bySemanticsLabel('Consumido, quantidade não informada.'),
      findsOneWidget,
    );
    semantics.dispose();
  });

  testWidgets('oferecido e consumido usam cálculos e cores independentes', (
    tester,
  ) async {
    await pumpCard(
      tester,
      const HealthSummaryNutritionTodayView(
        offeredAmount: 500,
        consumedAmount: 250,
        plannedAmount: 500,
        unitLabel: 'g',
      ),
    );

    expect(find.text('Oferecido: 500 g de 500 g'), findsOneWidget);
    expect(find.text('Consumido: 250 g de 500 g'), findsOneWidget);
    final bars = tester
        .widgetList<LinearProgressIndicator>(
          find.byType(LinearProgressIndicator),
        )
        .toList();
    expect(bars, hasLength(2));
    expect(bars[0].value, 1);
    expect(bars[0].color, AppTheme.attention);
    expect(bars[1].value, 0.5);
    expect(bars[1].color, AppTheme.success);
  });

  testWidgets('excesso preserva texto e limita indicadores a cem por cento', (
    tester,
  ) async {
    await pumpCard(
      tester,
      const HealthSummaryNutritionTodayView(
        offeredAmount: 700,
        consumedAmount: 650,
        plannedAmount: 500,
        unitLabel: 'g',
      ),
    );

    expect(find.text('Oferecido: 700 g de 500 g'), findsOneWidget);
    expect(find.text('Consumido: 650 g de 500 g'), findsOneWidget);
    for (final bar in tester.widgetList<LinearProgressIndicator>(
      find.byType(LinearProgressIndicator),
    )) {
      expect(bar.value, 1);
    }
  });

  testWidgets('meta inválida não cria percentuais artificiais', (tester) async {
    await pumpCard(
      tester,
      const HealthSummaryNutritionTodayView(
        offeredAmount: 500,
        consumedAmount: 250,
        plannedAmount: 0,
        unitLabel: 'g',
      ),
    );

    expect(find.text('Meta diária não informada'), findsOneWidget);
    expect(find.text('Oferecido: 500 g'), findsOneWidget);
    expect(find.text('Consumido: 250 g'), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsNothing);
  });
}
