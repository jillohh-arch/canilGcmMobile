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
    HealthSummarySectionData<HealthSummaryNutritionTodayView> nutrition, {
    Size size = const Size(800, 600),
    double textScale = 1,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
          child: Scaffold(
            body: SingleChildScrollView(
              child: HealthSummaryNutritionCard(nutrition: nutrition),
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
      const HealthSummarySectionData.available(
        HealthSummaryNutritionTodayView(
          offeredAmount: 500,
          consumedAmount: null,
          plannedAmount: 500,
          mealsRecorded: 3,
          mealsPlanned: 3,
          unitLabel: 'g',
        ),
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
      const HealthSummarySectionData.available(
        HealthSummaryNutritionTodayView(
          offeredAmount: 500,
          consumedAmount: 250,
          plannedAmount: 500,
          unitLabel: 'g',
        ),
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
      const HealthSummarySectionData.available(
        HealthSummaryNutritionTodayView(
          offeredAmount: 700,
          consumedAmount: 650,
          plannedAmount: 500,
          unitLabel: 'g',
        ),
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
      const HealthSummarySectionData.available(
        HealthSummaryNutritionTodayView(
          offeredAmount: 500,
          consumedAmount: 250,
          plannedAmount: 0,
          unitLabel: 'g',
        ),
      ),
    );

    expect(find.text('Meta diária não informada'), findsOneWidget);
    expect(find.text('Oferecido: 500 g'), findsOneWidget);
    expect(find.text('Consumido: 250 g'), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsNothing);
  });

  testWidgets('available saudável não apresenta diagnóstico parcial', (
    tester,
  ) async {
    await pumpCard(
      tester,
      const HealthSummarySectionData.available(
        HealthSummaryNutritionTodayView(
          offeredAmount: 200,
          plannedAmount: 400,
          unitLabel: 'g',
        ),
      ),
    );

    expect(find.textContaining('parcialmente'), findsNothing);
  });

  testWidgets(
    'degraded preserva valor e diagnóstico acessível em 320dp text scale 1.5',
    (tester) async {
      const diagnostic =
          'Atualização parcial: administrações não puderam ser confirmadas.';
      final semantics = tester.ensureSemantics();

      await pumpCard(
        tester,
        const HealthSummarySectionData.degraded(
          HealthSummaryNutritionTodayView(
            offeredAmount: 200,
            consumedAmount: 150,
            plannedAmount: 400,
            mealsRecorded: 1,
            mealsPlanned: 2,
            unitLabel: 'g',
          ),
          message: diagnostic,
        ),
        size: const Size(320, 800),
        textScale: 1.5,
      );

      expect(find.text(diagnostic), findsOneWidget);
      expect(find.text('Meta diária: 400 g'), findsOneWidget);
      expect(find.text('Oferecido: 200 g de 400 g'), findsOneWidget);
      expect(find.bySemanticsLabel(diagnostic), findsOneWidget);
      expect(tester.takeException(), isNull);
      semantics.dispose();
    },
  );
}
