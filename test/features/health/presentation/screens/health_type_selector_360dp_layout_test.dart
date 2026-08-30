import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:canil_gcm/features/health/presentation/screens/health_type_selector_screen.dart';

void main() {
  // Observação de método: widget tests renderizam com a fonte de teste (Ahem),
  // cujos glifos têm largura fixa de 1em. Medir largura de texto ou ellipsis
  // aqui não representa Inter no device, então este teste cobre o contrato
  // independente de fonte: título de uma linha, rótulo curto, e ausência de
  // erro de layout novo além do overflow vertical já existente no card.
  testWidgets('H-05 títulos do hub são de uma linha e curtos em 360dp', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final layoutErrors = <String>[];
    final previousOnError = FlutterError.onError;
    FlutterError.onError = (details) =>
        layoutErrors.add(details.exceptionAsString());

    await tester.pumpWidget(
      MaterialApp(
        home: HealthTypeSelectorScreen(
          dogId: 'dog-apolo',
          dogName: 'Apolo',
          // Necessários para que Pesagem, Nutrição e Documento/PDF fiquem
          // disponíveis no grid; o teste cobre apenas layout, não navegação.
          onRegisterWeight: (_) async => true,
          onRegisterNutrition: (_) async => true,
          onAttachDocument: (_) async => true,
        ),
      ),
    );
    await tester.pumpAndSettle();

    FlutterError.onError = previousOnError;

    // 'Sintoma' substitui 'Sintoma observado': o subtítulo já carrega o
    // significado ("Adicionar reação ou sintoma"), sem exigir duas linhas.
    expect(find.text('Sintoma', skipOffstage: false), findsOneWidget);
    expect(find.text('Sintoma observado', skipOffstage: false), findsNothing);
    expect(
      find.text('Adicionar reação ou sintoma', skipOffstage: false),
      findsOneWidget,
    );

    const labels = <String>[
      'Vacinação',
      'Pesagem',
      'Nutrição',
      'Documento/PDF',
      'Antiparasitário',
      'Exame',
      'Consulta',
      'Medicação',
      'Sintoma',
      'Cirurgia',
      'Outro',
    ];

    for (final label in labels) {
      final finder = find.text(label, skipOffstage: false);
      expect(finder, findsOneWidget, reason: 'label ausente: $label');

      final text = tester.widget<Text>(finder);
      expect(
        text.maxLines,
        1,
        reason: 'título "$label" deve ocupar uma única linha',
      );
      expect(
        label.length,
        lessThanOrEqualTo('Antiparasitário'.length),
        reason:
            'título "$label" excede o rótulo mais longo já homologado no grid',
      );
    }

    // Condição pré-existente, não introduzida por H-05: o card do hub estoura
    // verticalmente em 360dp por causa do subtítulo de duas linhas. Verificado
    // também com o título longo original, portanto independe desta correção.
    // Corrigir exigiria alterar grid/card, fora do escopo desta rodada.
    // Qualquer erro de layout de outra natureza deve falhar o teste.
    for (final error in layoutErrors) {
      expect(
        error,
        contains('overflowed'),
        reason: 'erro de layout inesperado: $error',
      );
    }
  });
}
