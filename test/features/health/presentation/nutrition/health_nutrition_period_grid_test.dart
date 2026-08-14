import 'package:canil_gcm/core/theme/app_theme.dart';
import 'package:canil_gcm/features/health/presentation/nutrition/widgets/health_nutrition_period_grid.dart';
import 'package:canil_gcm/features/health/presentation/nutrition/widgets/health_nutrition_period_visuals.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

HealthNutritionSlotEntry _slot({
  String time = '07:00',
  String status = 'Pendente',
  Color color = AppTheme.warningAccent,
  double? grams = 125,
  VoidCallback? onRegister,
  List<HealthNutritionFactLine> facts = const [],
  String? conflictMessage,
  String? measurementNote,
}) {
  return HealthNutritionSlotEntry(
    timeLabel: time,
    statusLabel: status,
    statusColor: color,
    targetGrams: grams,
    onRegister: onRegister,
    executedFacts: facts,
    conflictMessage: conflictMessage,
    measurementNote: measurementNote,
  );
}

HealthNutritionQuadrantData _quadrant(
  HealthNutritionPeriodGroup group, {
  List<HealthNutritionSlotEntry> slots = const [],
  String? summaryLine,
  String? emptyLabel,
  VoidCallback? onAction,
  String ctaLabel = 'Registrar refeição',
}) {
  return HealthNutritionQuadrantData(
    group: group,
    slots: slots,
    summaryLine: summaryLine,
    emptyLabel: emptyLabel,
    onAction: onAction,
    ctaLabel: ctaLabel,
  );
}

Future<void> _pump(
  WidgetTester tester, {
  required List<HealthNutritionQuadrantData> quadrants,
  List<HealthNutritionSlotEntry> extraSlots = const [],
  double width = 380,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        backgroundColor: AppTheme.background,
        body: SingleChildScrollView(
          child: SizedBox(
            width: width,
            child: HealthNutritionPeriodGrid(
              quadrants: quadrants,
              extraSlots: extraSlots,
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('plano padrão manhã/tarde/noite renderiza as três faixas', (
    tester,
  ) async {
    await _pump(
      tester,
      quadrants: [
        _quadrant(
          HealthNutritionPeriodGroup.morning,
          slots: [_slot(time: '07:00')],
        ),
        _quadrant(
          HealthNutritionPeriodGroup.afternoon,
          slots: [_slot(time: '12:00')],
        ),
        _quadrant(
          HealthNutritionPeriodGroup.night,
          slots: [_slot(time: '23:00', grams: 250)],
        ),
      ],
    );

    expect(find.text('MANHÃ'), findsOneWidget);
    expect(find.text('TARDE'), findsOneWidget);
    expect(find.text('NOITE'), findsOneWidget);
    expect(find.textContaining('07:00'), findsOneWidget);
    expect(find.textContaining('250 g previstos'), findsOneWidget);
  });

  testWidgets('quadrante de suplemento tem identidade e CTA próprios', (
    tester,
  ) async {
    var taps = 0;
    await _pump(
      tester,
      quadrants: [
        _quadrant(
          HealthNutritionPeriodGroup.supplement,
          summaryLine: '2 regimes previstos · 1 administração hoje',
          ctaLabel: 'Registrar suplemento',
          onAction: () => taps++,
        ),
      ],
    );

    expect(find.text('SUPLEMENTO'), findsOneWidget);
    expect(
      find.text('2 regimes previstos · 1 administração hoje'),
      findsOneWidget,
    );

    await tester.tap(find.text('Registrar suplemento'));
    await tester.pumpAndSettle();
    expect(taps, 1, reason: 'CTA do suplemento aciona o handler existente');
  });

  testWidgets(
    'suplemento NÃO inventa status pendente/concluído',
    (tester) async {
      // O contrato de suplemento proíbe inferir que uma administração completou
      // uma frequência prescrita. O quadrante mostra contagem, não status.
      await _pump(
        tester,
        quadrants: [
          _quadrant(
            HealthNutritionPeriodGroup.supplement,
            summaryLine: '1 regime previsto · 0 administrações hoje',
            ctaLabel: 'Registrar suplemento',
            onAction: () {},
          ),
        ],
      );

      expect(find.text('Pendente'), findsNothing);
      expect(find.text('Concluída'), findsNothing);
      expect(find.text('Atrasada'), findsNothing);
    },
  );

  testWidgets('extra não desaparece — vai para linha compacta', (tester) async {
    await _pump(
      tester,
      quadrants: [
        _quadrant(
          HealthNutritionPeriodGroup.morning,
          slots: [_slot(time: '07:00')],
        ),
      ],
      extraSlots: [_slot(time: '16:30', grams: 80, status: 'Pendente')],
    );

    expect(find.textContaining('16:30'), findsOneWidget);
    expect(find.textContaining('80 g'), findsOneWidget);
    expect(find.textContaining('Extra'), findsOneWidget);
  });

  testWidgets('mais de um slot na mesma faixa não perde informação', (
    tester,
  ) async {
    await _pump(
      tester,
      quadrants: [
        _quadrant(
          HealthNutritionPeriodGroup.morning,
          slots: [
            _slot(time: '06:00', grams: 100),
            _slot(time: '09:30', grams: 150),
          ],
          summaryLine: '2 refeições nesta faixa',
        ),
      ],
    );

    // Nenhum horário é escondido pelo agrupamento.
    expect(find.textContaining('06:00'), findsOneWidget);
    expect(find.textContaining('09:30'), findsOneWidget);
    expect(find.text('2 refeições nesta faixa'), findsOneWidget);
  });

  testWidgets('faixa sem refeição prevista é honesta', (tester) async {
    await _pump(
      tester,
      quadrants: [
        _quadrant(
          HealthNutritionPeriodGroup.night,
          emptyLabel: 'Sem refeição prevista',
        ),
      ],
    );

    expect(find.text('Sem refeição prevista'), findsOneWidget);
    // Sem slot não há CTA: nada a registrar contra um horário inexistente.
    expect(find.text('Registrar refeição'), findsNothing);
  });

  testWidgets('fatos da refeição executada são preservados', (tester) async {
    await _pump(
      tester,
      quadrants: [
        _quadrant(
          HealthNutritionPeriodGroup.morning,
          slots: [
            _slot(
              status: 'Concluída',
              color: AppTheme.success,
              facts: const [
                HealthNutritionFactLine(label: 'Oferecido', value: '125 g'),
                HealthNutritionFactLine(
                  label: 'Consumido',
                  value: 'Não informado',
                ),
                HealthNutritionFactLine(
                  label: 'Aceitação',
                  value: 'Aceitou tudo',
                ),
              ],
              measurementNote: 'Quantidade consumida não medida',
            ),
          ],
        ),
      ],
    );

    expect(find.text('125 g'), findsOneWidget);
    expect(find.text('Não informado'), findsOneWidget);
    expect(find.text('Aceitou tudo'), findsOneWidget);
    expect(find.text('Quantidade consumida não medida'), findsOneWidget);
  });

  testWidgets('completed + consumed null mostra resumo compacto de no máximo 2 linhas', (
    tester,
  ) async {
    await _pump(
      tester,
      quadrants: [
        _quadrant(
          HealthNutritionPeriodGroup.morning,
          slots: [
            _slot(
              status: 'Concluída',
              color: AppTheme.success,
              facts: const [
                HealthNutritionFactLine(label: '', value: '125 g oferecidos'),
                HealthNutritionFactLine(
                  label: '',
                  value: 'Aceitou tudo • consumo não medido',
                ),
              ],
            ),
          ],
        ),
      ],
    );

    expect(find.text('125 g oferecidos'), findsOneWidget);
    expect(find.text('Aceitou tudo • consumo não medido'), findsOneWidget);
  });

  testWidgets('completed + consumed medido mostra resumo compacto', (
    tester,
  ) async {
    await _pump(
      tester,
      quadrants: [
        _quadrant(
          HealthNutritionPeriodGroup.afternoon,
          slots: [
            _slot(
              status: 'Concluída',
              color: AppTheme.success,
              facts: const [
                HealthNutritionFactLine(label: '', value: '125 g consumidos'),
                HealthNutritionFactLine(label: '', value: 'Aceitou tudo'),
              ],
            ),
          ],
        ),
      ],
    );

    expect(find.text('125 g consumidos'), findsOneWidget);
    expect(find.text('Aceitou tudo'), findsOneWidget);
  });

  testWidgets('conflito de integridade é anunciado e bloqueia o CTA', (
    tester,
  ) async {
    await _pump(
      tester,
      quadrants: [
        _quadrant(
          HealthNutritionPeriodGroup.morning,
          slots: [
            _slot(
              status: 'Dados inconsistentes',
              color: AppTheme.error,
              conflictMessage:
                  'Execução duplicada detectada. '
                  'Ação temporariamente indisponível.',
            ),
          ],
        ),
      ],
    );

    expect(find.text('Dados inconsistentes'), findsOneWidget);
    expect(
      find.bySemanticsLabel(
        'Execução duplicada detectada. Ação temporariamente indisponível.',
      ),
      findsOneWidget,
    );
    expect(find.text('Registrar refeição'), findsNothing);
  });

  testWidgets('CTA desabilitado quando o gating nega a ação', (tester) async {
    await _pump(
      tester,
      quadrants: [
        _quadrant(
          HealthNutritionPeriodGroup.morning,
          // onRegister null = gating fail-closed da tela.
          slots: [_slot()],
        ),
      ],
    );

    expect(find.text('Registrar refeição'), findsNothing);
  });

  testWidgets('CTA aciona o handler e respeita alvo de toque de 48px', (
    tester,
  ) async {
    var taps = 0;
    await _pump(
      tester,
      quadrants: [
        _quadrant(
          HealthNutritionPeriodGroup.morning,
          slots: [_slot(onRegister: () => taps++)],
        ),
      ],
    );

    final cta = find.widgetWithText(OutlinedButton, 'Registrar refeição');
    expect(cta, findsOneWidget);
    expect(tester.getSize(cta).height, greaterThanOrEqualTo(48));

    await tester.tap(cta);
    await tester.pumpAndSettle();
    expect(taps, 1);
  });

  testWidgets('largura reduzida degrada para coluna única sem overflow', (
    tester,
  ) async {
    await _pump(
      tester,
      width: 280,
      quadrants: [
        _quadrant(
          HealthNutritionPeriodGroup.morning,
          slots: [_slot(onRegister: () {})],
        ),
        _quadrant(
          HealthNutritionPeriodGroup.afternoon,
          slots: [_slot(time: '12:00', onRegister: () {})],
        ),
        _quadrant(
          HealthNutritionPeriodGroup.night,
          slots: [_slot(time: '23:00', onRegister: () {})],
        ),
        _quadrant(
          HealthNutritionPeriodGroup.supplement,
          summaryLine: '1 regime previsto',
          ctaLabel: 'Registrar suplemento',
          onAction: () {},
        ),
      ],
    );

    expect(tester.takeException(), isNull);
    expect(find.text('MANHÃ'), findsOneWidget);
    expect(find.text('SUPLEMENTO'), findsOneWidget);
  });

  testWidgets('360dp com text scale 1.3 não estoura', (tester) async {
    tester.view.physicalSize = const Size(360, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(1.3)),
          child: Scaffold(
            body: SingleChildScrollView(
              child: HealthNutritionPeriodGrid(
                quadrants: [
                  _quadrant(
                    HealthNutritionPeriodGroup.morning,
                    slots: [_slot(onRegister: () {})],
                  ),
                  _quadrant(
                    HealthNutritionPeriodGroup.supplement,
                    summaryLine: '2 regimes previstos',
                    ctaLabel: 'Registrar suplemento',
                    onAction: () {},
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
  });
}
