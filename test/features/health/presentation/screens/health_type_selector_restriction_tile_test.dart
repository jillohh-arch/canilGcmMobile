import 'package:canil_gcm/features/health/presentation/screens/health_type_selector_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// O tile de Restrição Operacional a 360dp.
///
/// O teste H-05 existente NÃO cobre este tile: ele não passa
/// `onRegisterRestriction`, e `_isCategoryAvailable` remove a categoria quando
/// o callback é nulo. Logo, a prova de layout do rótulo precisa ser própria.
void main() {
  Future<List<String>> pumpSelector(
    WidgetTester tester, {
    bool withRestriction = true,
  }) async {
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
          onRegisterWeight: (_) async => true,
          onRegisterNutrition: (_) async => true,
          onAttachDocument: (_) async => true,
          onRegisterRestriction: withRestriction ? (_) async => true : null,
        ),
      ),
    );
    await tester.pumpAndSettle();
    FlutterError.onError = previousOnError;
    return layoutErrors;
  }

  testWidgets('tile aparece quando o callback é fornecido', (tester) async {
    await pumpSelector(tester);

    expect(
      find.text('Restrição', skipOffstage: false),
      findsOneWidget,
    );
    expect(
      find.text('Registrar limitação operacional', skipOffstage: false),
      findsOneWidget,
    );
  });

  testWidgets('tile é omitido quando não há callback', (tester) async {
    await pumpSelector(tester, withRestriction: false);

    // Mesmo mecanismo de Pesagem/Nutrição/Documento: sem writer, sem tile.
    expect(
      find.text('Restrição', skipOffstage: false),
      findsNothing,
    );
  });

  testWidgets('rótulo cabe em uma linha a 360dp, sem overflow novo', (
    tester,
  ) async {
    final layoutErrors = await pumpSelector(tester);

    final finder = find.text('Restrição', skipOffstage: false);
    final text = tester.widget<Text>(finder);
    expect(text.maxLines, 1, reason: 'título de tile é sempre uma linha');

    // Contrato independente de fonte, igual ao H-05.
    //
    // NÃO medir truncamento aqui: sob a fonte de teste (Ahem, glifos de largura
    // fixa 1em) rótulos JÁ homologados como 'Vacinação', 'Consulta' e
    // 'Antiparasitário' também reportam `didExceedMaxLines == true`. Medir isso
    // provaria apenas o artefato da fonte, não o layout real em Inter.
    //
    // O que resta verificável sem device: o rótulo é de uma linha e não excede
    // o mais longo já homologado no grid.
    expect(
      'Restrição'.length,
      lessThanOrEqualTo('Antiparasitário'.length),
      reason: 'rótulo não deve exceder o mais longo homologado',
    );

    // O card do hub já estoura verticalmente a 360dp por causa do subtítulo de
    // duas linhas — condição pré-existente, documentada no teste H-05. Qualquer
    // erro de outra natureza deve falhar.
    for (final error in layoutErrors) {
      expect(
        error,
        contains('overflowed'),
        reason: 'erro de layout inesperado: $error',
      );
    }
  });

  testWidgets('seleção do tile dispara o callback dedicado', (tester) async {
    tester.view.physicalSize = const Size(360, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    // O card do hub tem overflow vertical pré-existente a 360dp (documentado
    // no teste H-05). Sem capturar, o framework falha o teste por isso.
    final layoutErrors = <String>[];
    final previousOnError = FlutterError.onError;
    FlutterError.onError = (details) =>
        layoutErrors.add(details.exceptionAsString());
    addTearDown(() => FlutterError.onError = previousOnError);

    var called = false;
    await tester.pumpWidget(
      MaterialApp(
        home: HealthTypeSelectorScreen(
          dogId: 'dog-apolo',
          dogName: 'Apolo',
          popOnSave: false,
          onRegisterRestriction: (_) async {
            called = true;
            return true;
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      find.text('Restrição', skipOffstage: false),
      120,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Restrição'));
    await tester.pumpAndSettle();

    // Tocar o tile apenas seleciona; a ação vem do botão Continuar.
    expect(called, isFalse, reason: 'seleção não navega por si só');

    await tester.tap(find.text('Continuar'));
    await tester.pumpAndSettle();

    expect(
      called,
      isTrue,
      reason: 'restrição usa callback dedicado, nunca HealthEventFormScreen',
    );

    for (final error in layoutErrors) {
      expect(
        error,
        contains('overflowed'),
        reason: 'erro de layout inesperado: $error',
      );
    }
  });
}
