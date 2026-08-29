import 'package:canil_gcm/core/theme/app_theme.dart';
import 'package:canil_gcm/features/health/presentation/nutrition/widgets/health_nutrition_history_timeline.dart';
import 'package:canil_gcm/features/health/presentation/nutrition/widgets/health_nutrition_period_visuals.dart';
import 'package:canil_gcm/features/health/presentation/timeline/widgets/health_timeline_marker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

HealthNutritionHistoryEntry _entry({
  required HealthNutritionPeriodGroup group,
  required String title,
  String when = 'Hoje · 07:00',
  String detail = '125 g oferecidos',
  bool isLegacy = false,
  String? statusLabel,
  Color? statusColor,
}) {
  return HealthNutritionHistoryEntry(
    group: group,
    title: title,
    whenLabel: when,
    detailLine: detail,
    isLegacy: isLegacy,
    statusLabel: statusLabel,
    statusColor: statusColor,
  );
}

Future<void> _pump(
  WidgetTester tester,
  List<HealthNutritionHistoryEntry> entries, {
  double width = 380,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        backgroundColor: AppTheme.background,
        body: SingleChildScrollView(
          child: SizedBox(
            width: width,
            child: HealthNutritionHistoryTimeline(entries: entries),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('timeline renderiza uma entrada por identidade visual', (
    tester,
  ) async {
    await _pump(tester, [
      _entry(group: HealthNutritionPeriodGroup.morning, title: 'Manhã'),
      _entry(
        group: HealthNutritionPeriodGroup.afternoon,
        title: 'Tarde',
        when: 'Hoje · 12:00',
      ),
      _entry(
        group: HealthNutritionPeriodGroup.night,
        title: 'Noite',
        when: 'Hoje · 23:00',
      ),
      _entry(
        group: HealthNutritionPeriodGroup.supplement,
        title: 'Suplemento',
        detail: '1 dose administrada',
      ),
    ]);

    expect(find.text('Manhã'), findsOneWidget);
    expect(find.text('Tarde'), findsOneWidget);
    expect(find.text('Noite'), findsOneWidget);
    expect(find.text('Suplemento'), findsOneWidget);

    // Cada entrada tem sua própria trilha/marcador.
    expect(find.byType(CustomPaint), findsWidgets);
  });

  testWidgets('cor do marcador acompanha o período, não a origem', (
    tester,
  ) async {
    await _pump(tester, [
      _entry(group: HealthNutritionPeriodGroup.morning, title: 'Manhã'),
      _entry(
        group: HealthNutritionPeriodGroup.night,
        title: 'Noite',
        // Legado: antes isso mudava a COR do ícone; agora é badge.
        isLegacy: true,
      ),
    ]);

    final painters = tester
        .widgetList<CustomPaint>(find.byType(CustomPaint))
        .map((w) => w.painter)
        .whereType<HealthTimelineRailPainter>()
        .toList();

    expect(painters.length, 2);
    expect(
      painters[0].accent,
      HealthNutritionPeriodVisuals.resolve(
        HealthNutritionPeriodGroup.morning,
      ).accent,
    );
    expect(
      painters[1].accent,
      HealthNutritionPeriodVisuals.resolve(
        HealthNutritionPeriodGroup.night,
      ).accent,
      reason: 'entrada legada mantém a cor do período',
    );
  });

  testWidgets('registro legado continua identificável por badge', (
    tester,
  ) async {
    await _pump(tester, [
      _entry(group: HealthNutritionPeriodGroup.morning, title: 'Manhã'),
      _entry(
        group: HealthNutritionPeriodGroup.afternoon,
        title: 'Tarde',
        isLegacy: true,
      ),
    ]);

    // Exatamente um badge: a informação de coexistência não foi perdida nem
    // duplicada ao trocar o canal de cor para badge.
    expect(find.text('legado'), findsOneWidget);
  });

  testWidgets('primeira e última entradas controlam as pontas da trilha', (
    tester,
  ) async {
    await _pump(tester, [
      _entry(group: HealthNutritionPeriodGroup.morning, title: 'Manhã'),
      _entry(group: HealthNutritionPeriodGroup.afternoon, title: 'Tarde'),
      _entry(group: HealthNutritionPeriodGroup.night, title: 'Noite'),
    ]);

    final painters = tester
        .widgetList<CustomPaint>(find.byType(CustomPaint))
        .map((w) => w.painter)
        .whereType<HealthTimelineRailPainter>()
        .toList();

    expect(painters.length, 3);
    expect(painters.first.isFirst, isTrue);
    expect(painters.first.isLast, isFalse);
    expect(painters[1].isFirst, isFalse);
    expect(painters[1].isLast, isFalse);
    expect(painters.last.isLast, isTrue);
  });

  testWidgets('horário e detalhe são exibidos', (tester) async {
    await _pump(tester, [
      _entry(
        group: HealthNutritionPeriodGroup.morning,
        title: 'Manhã',
        when: 'Hoje · 07:00',
        detail: '125 g oferecidos · consumo não informado',
      ),
    ]);

    expect(find.text('Hoje · 07:00'), findsOneWidget);
    expect(
      find.text('125 g oferecidos · consumo não informado'),
      findsOneWidget,
    );
  });

  testWidgets('status opcional aparece quando fornecido', (tester) async {
    await _pump(tester, [
      _entry(
        group: HealthNutritionPeriodGroup.morning,
        title: 'Manhã',
        statusLabel: 'Atrasada',
        statusColor: AppTheme.warning,
      ),
      _entry(group: HealthNutritionPeriodGroup.night, title: 'Noite'),
    ]);

    expect(find.text('Atrasada'), findsOneWidget);
  });

  testWidgets('largura estreita não estoura', (tester) async {
    await _pump(
      tester,
      width: 280,
      [
        _entry(
          group: HealthNutritionPeriodGroup.morning,
          title: 'Manhã',
          detail: '125 g oferecidos · consumo não informado',
          isLegacy: true,
        ),
      ],
    );

    expect(tester.takeException(), isNull);
  });

  testWidgets('lista vazia não renderiza trilha', (tester) async {
    await _pump(tester, const []);

    final painters = tester
        .widgetList<CustomPaint>(find.byType(CustomPaint))
        .map((w) => w.painter)
        .whereType<HealthTimelineRailPainter>();
    expect(painters, isEmpty);
  });
}
