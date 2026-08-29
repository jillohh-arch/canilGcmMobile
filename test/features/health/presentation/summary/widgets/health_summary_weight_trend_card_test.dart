import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:canil_gcm/features/health/presentation/summary/health_summary_block_models.dart';
import 'package:canil_gcm/features/health/presentation/summary/health_summary_section_status.dart';
import 'package:canil_gcm/features/health/presentation/summary/widgets/health_summary_weight_trend_card.dart';

/// WEIGHT-01E-R — o card NÃO é autoridade de peso atual.
///
/// O defeito removido: sem `currentWeight` canônico, o card promovia o último
/// ponto da série (`points.last`) como se fosse o peso atual. A série é
/// ordenada apenas por `at` e seus pontos não carregam `entityId`/`recordedAt`,
/// então esse caminho não podia representar o desempate canônico — e
/// transformava ausência de autoridade em um número aparentemente factual.
void main() {
  HealthSummaryWeightPoint point(int day, double kg) =>
      HealthSummaryWeightPoint(at: DateTime.utc(2026, 8, day), weightKg: kg);

  Future<void> pump(
    WidgetTester tester, {
    required HealthSummarySectionData<HealthSummaryWeightTrendView> trend,
    HealthSummarySectionData<HealthSummaryWeightView>? current,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: HealthSummaryWeightTrendCard(
            weightTrend: trend,
            currentWeight: current,
          ),
        ),
      ),
    );
    await tester.pump();
  }

  final trendWithPoints = HealthSummarySectionData.available(
    HealthSummaryWeightTrendView(
      points: [point(1, 30.0), point(2, 31.0), point(3, 39.9)],
    ),
  );

  testWidgets('sem currentWeight canônico não promove series.last', (
    tester,
  ) async {
    await pump(tester, trend: trendWithPoints);

    // 39,9 é o último ponto da série: não pode aparecer como peso atual.
    expect(find.textContaining('39,9'), findsNothing);
    expect(find.textContaining('39.9'), findsNothing);
    // Nenhum outro ponto é promovido no lugar dele.
    expect(find.textContaining('31,0'), findsNothing);
    expect(find.textContaining('30,0'), findsNothing);
  });

  testWidgets('currentWeight canônico vence o último ponto da série', (
    tester,
  ) async {
    await pump(
      tester,
      trend: trendWithPoints,
      current: HealthSummarySectionData.available(
        HealthSummaryWeightView(
          weightKg: 24.5,
          measuredAt: DateTime.utc(2026, 8, 3),
        ),
      ),
    );

    // O canônico (24,5) é exibido, não o endpoint da série (39,9).
    expect(find.textContaining('24,5'), findsWidgets);
    expect(find.textContaining('39,9'), findsNothing);
  });

  testWidgets('estado indisponível não fabrica peso a partir da série', (
    tester,
  ) async {
    await pump(
      tester,
      trend: trendWithPoints,
      current: const HealthSummarySectionData.unavailable(),
    );

    expect(find.textContaining('39,9'), findsNothing);
  });

  testWidgets('série continua desenhando o gráfico', (tester) async {
    // A ordenação cronológica da série permanece legítima como apresentação;
    // o gate remove apenas seu uso como autoridade de peso atual.
    await pump(tester, trend: trendWithPoints);
    expect(find.byType(CustomPaint), findsWidgets);
  });
}
