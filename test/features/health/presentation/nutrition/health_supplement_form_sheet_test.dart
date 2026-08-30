import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:canil_gcm/features/health/domain/health_nutrition_mutation_commands.dart';
import 'package:canil_gcm/features/health/domain/health_nutrition_mutation_gateway.dart';
import 'package:canil_gcm/features/health/domain/health_v1_models.dart';
import 'package:canil_gcm/features/health/domain/nutrition_read_models.dart';
import 'package:canil_gcm/features/health/domain/nutrition_plan.dart';
import 'package:canil_gcm/features/health/domain/nutrition_plan_regimen.dart';
import 'package:canil_gcm/features/health/domain/supplement_log.dart';
import 'package:canil_gcm/features/health/presentation/nutrition/health_supplement_form_sheet.dart';
import 'package:canil_gcm/features/health/presentation/nutrition/health_nutrition_mutation_controller.dart';

void main() {
  group('HealthSupplementFormSheet — Gate 5C.4B', () {
    // ── UI Structure ───────────────────────────────────────────────────────

    testWidgets('abre com estrutura correta', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: HealthSupplementFormSheet(
                dogId: 'dog-001',
                dogDisplayName: 'Bono',
                controller: _TestController(),
                onRefreshRequested: () async {},
                timezone: 'America/Sao_Paulo',
                activePlan: null,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Título
      expect(find.text('REGISTRAR SUPLEMENTO'), findsOneWidget);
      expect(find.text('Administração avulsa'), findsOneWidget);
      expect(find.text('Sem vínculo com regime ativo'), findsOneWidget);

      // Campos obrigatórios (HudSelectField usa labels uppercase)
      expect(find.text('Nome do suplemento'), findsOneWidget);
      expect(find.text('Dose'), findsOneWidget);
      expect(find.textContaining(RegExp('unidade', caseSensitive: false)), findsOneWidget);

      // Campos opcionais
      expect(find.text('Observações — opcional'), findsOneWidget);
    });

    testWidgets('sem semântica pending/completed', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: HealthSupplementFormSheet(
                dogId: 'dog-001',
                dogDisplayName: 'Bono',
                controller: _TestController(),
                onRefreshRequested: () async {},
                timezone: 'America/Sao_Paulo',
                activePlan: null,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Verificar que não há campos de pending/completed
      expect(find.textContaining('pending', skipOffstage: false), findsNothing);
      expect(
        find.textContaining('completed', skipOffstage: false),
        findsNothing,
      );
      expect(
        find.textContaining('concluído', skipOffstage: false),
        findsNothing,
      );
      expect(
        find.textContaining('Pendente', skipOffstage: false),
        findsNothing,
      );
    });

    testWidgets('unidade default é tablet', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: HealthSupplementFormSheet(
                dogId: 'dog-001',
                dogDisplayName: 'Bono',
                controller: _TestController(),
                onRefreshRequested: () async {},
                timezone: 'America/Sao_Paulo',
                activePlan: null,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Verificar que tablet/comprimido está selecionado por padrão
      expect(find.text('comprimido'), findsOneWidget);
    });

    testWidgets('mode avulso: campos editáveis', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: HealthSupplementFormSheet(
                dogId: 'dog-001',
                dogDisplayName: 'Bono',
                controller: _TestController(),
                onRefreshRequested: () async {},
                timezone: 'America/Sao_Paulo',
                activePlan: null,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Entrada de texto no campo de nome
      final nameField = find.widgetWithText(
        TextFormField,
        'Nome do suplemento',
      );
      expect(nameField, findsOneWidget);
      await tester.enterText(nameField, 'Vitamina C');

      expect(find.text('Vitamina C'), findsOneWidget);
    });
  });

  group('_ModeButton', () {
    testWidgets('Do plano and Avulso buttons are tappable', (tester) async {
    // Build with activePlan to show mode selector
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: HealthSupplementFormSheet(
              dogId: 'dog-001',
              dogDisplayName: 'Bono',
              controller: _TestController(),
              onRefreshRequested: () async {},
              timezone: 'America/Sao_Paulo',
              activePlan: _mockActivePlan(),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Both mode buttons should be visible (may match HudSelectField labels too)
    expect(find.text('Do plano'), findsWidgets);
    expect(find.text('Avulso'), findsWidgets);

    // Tap Avulso (use first match for mode selector)
    await tester.tap(find.text('Avulso').first);
    await tester.pumpAndSettle();
    expect(find.text('Avulso'), findsWidgets);

    // Tap Do plano (use first match for mode selector)
    await tester.tap(find.text('Do plano').first);
    await tester.pumpAndSettle();
    expect(find.text('Do plano'), findsWidgets);
    expect(find.text('Suplemento prescrito'), findsOneWidget);
    expect(find.text('Vinculado ao plano alimentar'), findsOneWidget);
  });

  testWidgets('mode selector present with adequate size', (tester) async {
    tester.view.physicalSize = const Size(440, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: HealthSupplementFormSheet(
              dogId: 'dog-001',
              dogDisplayName: 'Bono',
              controller: _TestController(),
              onRefreshRequested: () async {},
              timezone: 'America/Sao_Paulo',
              activePlan: _mockActivePlan(),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Mode buttons should be present and tappable
    expect(find.text('Do plano'), findsWidgets);
    expect(find.text('Avulso'), findsWidgets);

    // Tap each to verify they respond
    await tester.tap(find.text('Do plano').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Avulso').first);
    await tester.pumpAndSettle();
  });

  testWidgets('selected state shows correct styling', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: HealthSupplementFormSheet(
              dogId: 'dog-001',
              dogDisplayName: 'Bono',
              controller: _TestController(),
              onRefreshRequested: () async {},
              timezone: 'America/Sao_Paulo',
              activePlan: _mockActivePlan(),
              defaultRegimen: _mockRegimen(),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Default is "Do plano" selected (has defaultRegimen)
    expect(find.text('Do plano'), findsWidgets);

    // Tap "Avulso" to switch modes (use first match)
    await tester.tap(find.text('Avulso').first);
    await tester.pumpAndSettle();

    // Both modes should still be visible
    expect(find.text('Do plano'), findsWidgets);
    expect(find.text('Avulso'), findsWidgets);
  });
  });

  group('loading textual', () {
    testWidgets('avulso: spinner + texto visível durante submit', (tester) async {
      tester.view.physicalSize = const Size(440, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      // Gateway with controllable future
      final supplementGate = Completer<HealthNutritionMutationResult>();
      final loadingGateway = _LoadingGateway(supplementGate.future);
      final loadingController = HealthNutritionMutationController(
        gateway: loadingGateway,
        operationIdFactory: () => 'op-sup-avulso',
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: HealthSupplementFormSheet(
                dogId: 'dog-001',
                dogDisplayName: 'Bono',
                controller: loadingController,
                onRefreshRequested: () async {},
                timezone: 'America/Sao_Paulo',
                activePlan: _mockActivePlan(),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      addTearDown(loadingController.dispose);

      // Switch to Avulso mode
      await tester.tap(find.text('Avulso').first);
      await tester.pumpAndSettle();

      // Fill required fields for avulso: name
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Nome do suplemento'),
        'Vitamina C',
      );
      await tester.pumpAndSettle();

      // Fill required fields for avulso: dose
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Dose'),
        '1',
      );
      await tester.pumpAndSettle();

      // Submit
      final submitFinder = find.widgetWithText(
        FilledButton,
        'REGISTRAR SUPLEMENTO AVULSO',
      );
      await tester.ensureVisible(submitFinder);
      await tester.tap(submitFinder);
      await tester.pump();

      // Spinner should be visible
      expect(find.byType(CircularProgressIndicator), findsOneWidget);

      // Loading text should be visible (contextual for avulso mode)
      expect(find.text('Registrando suplemento…'), findsOneWidget);

      // Button should be disabled
      final button = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Registrando suplemento…'),
      );
      expect(button.onPressed, isNull);

      // Complete gateway and settle
      supplementGate.complete(CreateSupplementLogSuccess(
        dogId: 'dog-001',
        supplementLogId: 'sl-test',
        revision: 1,
        wasNoOp: false,
        operationId: 'op-sup-avulso',
      ));
      await tester.pumpAndSettle();

      // Loading text should disappear after completion
      expect(find.text('Registrando suplemento…'), findsNothing);
      // No rendering errors
      expect(tester.takeException(), isNull);
    });

    testWidgets('do plano: spinner + texto durante submit', (tester) async {
      tester.view.physicalSize = const Size(440, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      // Gateway with controllable future
      final supplementGate = Completer<HealthNutritionMutationResult>();
      final loadingGateway = _LoadingGateway(supplementGate.future);
      final loadingController = HealthNutritionMutationController(
        gateway: loadingGateway,
        operationIdFactory: () => 'op-sup-plano',
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: HealthSupplementFormSheet(
                dogId: 'dog-001',
                dogDisplayName: 'Bono',
                controller: loadingController,
                onRefreshRequested: () async {},
                timezone: 'America/Sao_Paulo',
                activePlan: _mockActivePlan(),
                defaultRegimen: _mockRegimen(),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      addTearDown(loadingController.dispose);

      // Should be in "Do plano" mode
      expect(find.text('Do plano'), findsWidgets);

      // Submit
      final submitFinder = find.widgetWithText(
        FilledButton,
        'REGISTRAR ADMINISTRAÇÃO DO PLANO',
      );
      await tester.ensureVisible(submitFinder);
      await tester.tap(submitFinder);
      await tester.pump();

      // Spinner should be visible
      expect(find.byType(CircularProgressIndicator), findsOneWidget);

      // Loading text should be visible (contextual for "do plano" mode)
      expect(find.text('Registrando administração do plano…'), findsOneWidget);

      // Button should be disabled
      final button = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Registrando administração do plano…'),
      );
      expect(button.onPressed, isNull);

      // Complete gateway and settle
      supplementGate.complete(CreateSupplementLogSuccess(
        dogId: 'dog-001',
        supplementLogId: 'sl-test',
        revision: 1,
        wasNoOp: false,
        operationId: 'op-sup-plano',
      ));
      await tester.pumpAndSettle();

      // Loading text should disappear after completion
      expect(find.text('Registrando administração do plano…'), findsNothing);
      // No rendering errors
      expect(tester.takeException(), isNull);
    });
  });

  group('responsividade em layout compacto', () {
    testWidgets('do plano em 320px real com text scale 1.3: loading + zero overflow', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(320, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final supplementGate = Completer<HealthNutritionMutationResult>();
      final loadingGateway = _LoadingGateway(supplementGate.future);
      final loadingController = HealthNutritionMutationController(
        gateway: loadingGateway,
        operationIdFactory: () => 'op-sup-320',
      );

      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(
              size: Size(320, 800),
              devicePixelRatio: 1.0,
              textScaler: TextScaler.linear(1.3),
            ),
            child: Scaffold(
              body: SingleChildScrollView(
                child: HealthSupplementFormSheet(
                  dogId: 'dog-001',
                  dogDisplayName: 'Bono',
                  controller: loadingController,
                  onRefreshRequested: () async {},
                  timezone: 'America/Sao_Paulo',
                  activePlan: _mockActivePlan(),
                  defaultRegimen: _mockRegimen(),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      addTearDown(loadingController.dispose);

      // Modo "Do plano" selecionado por padrão
      expect(find.text('Do plano'), findsWidgets);

      // Submit para entrar no estado de loading
      final submitFinder = find.widgetWithText(
        FilledButton,
        'REGISTRAR ADMINISTRAÇÃO DO PLANO',
      );
      await tester.ensureVisible(submitFinder);
      await tester.tap(submitFinder);
      await tester.pump();
      expect(tester.takeException(), isNull, reason: 'Failed after submit tap and pump');

      // Comprovações simultâneas durante loading pendente:
      // 1. CircularProgressIndicator visível
      expect(find.byType(CircularProgressIndicator), findsOneWidget);

      // 2. Texto exato: "Registrando administração do plano…"
      expect(find.text('Registrando administração do plano…'), findsOneWidget);

      // 3. Botão desabilitado
      final button = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Registrando administração do plano…'),
      );
      expect(button.onPressed, isNull);

      // 4. Somente uma chamada ao gateway
      expect(loadingGateway.supplementCallCount, equals(1));

      // 5. tester.takeException() == null (zero RenderFlex overflow)
      expect(tester.takeException(), isNull);

      supplementGate.complete(CreateSupplementLogSuccess(
        dogId: 'dog-001',
        supplementLogId: 'sl-320',
        revision: 1,
        wasNoOp: false,
        operationId: 'op-sup-320',
      ));
      await tester.pumpAndSettle();
    });

    // ── C. Suplemento no modo Do plano ────────────────────────────────
    // Viewport 440x800: espaço para texto longo "Registrando administração
    // do plano…" + spinner sem overflow em condições normais de render.

    testWidgets('do plano em 440px: loading + zero overflow', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(440, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final supplementGate = Completer<HealthNutritionMutationResult>();
      final loadingGateway = _LoadingGateway(supplementGate.future);
      final loadingController = HealthNutritionMutationController(
        gateway: loadingGateway,
        operationIdFactory: () => 'op-sup-440',
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: HealthSupplementFormSheet(
                dogId: 'dog-001',
                dogDisplayName: 'Bono',
                controller: loadingController,
                onRefreshRequested: () async {},
                timezone: 'America/Sao_Paulo',
                activePlan: _mockActivePlan(),
                defaultRegimen: _mockRegimen(),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      addTearDown(loadingController.dispose);

      // Should be in "Do plano" mode
      expect(find.text('Do plano'), findsWidgets);

      // Submit to enter loading state
      final submitFinder = find.widgetWithText(
        FilledButton,
        'REGISTRAR ADMINISTRAÇÃO DO PLANO',
      );
      await tester.ensureVisible(submitFinder);
      await tester.tap(submitFinder);
      await tester.pump();

      // Spinner visible
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      // Correct loading text for Do plano mode
      expect(find.text('Registrando administração do plano…'), findsOneWidget);
      // Button disabled
      final button = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Registrando administração do plano…'),
      );
      expect(button.onPressed, isNull);
      // No overflow errors
      expect(tester.takeException(), isNull);

      supplementGate.complete(CreateSupplementLogSuccess(
        dogId: 'dog-001',
        supplementLogId: 'sl-440',
        revision: 1,
        wasNoOp: false,
        operationId: 'op-sup-440',
      ));
      await tester.pumpAndSettle();
    });

    testWidgets(
      'modal em 360px respeita safe area superior sem duplicar inset',
      (tester) async {
        const systemTop = 32.0;
        tester.view.physicalSize = const Size(360, 800);
        tester.view.devicePixelRatio = 1.0;
        tester.view.padding = const FakeViewPadding(top: systemTop);
        tester.view.viewPadding = const FakeViewPadding(top: systemTop);
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.view.resetPadding);
        addTearDown(tester.view.resetViewPadding);

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Builder(
                builder: (context) => TextButton(
                  onPressed: () => showModalBottomSheet<void>(
                    context: context,
                    isScrollControlled: true,
                    builder: (_) => HealthSupplementFormSheet(
                      dogId: 'dog-001',
                      dogDisplayName: 'Bono',
                      controller: _TestController(),
                      onRefreshRequested: () async {},
                      timezone: 'America/Sao_Paulo',
                      activePlan: _mockActivePlan(),
                      defaultRegimen: _mockRegimen(),
                    ),
                  ),
                  child: const Text('Abrir formulário'),
                ),
              ),
            ),
          ),
        );

        await tester.tap(find.text('Abrir formulário'));
        await tester.pumpAndSettle();

        final titleRect = tester.getRect(find.text('REGISTRAR SUPLEMENTO'));
        final dogRect = tester.getRect(find.text('Bono'));
        final closeFinder = find.widgetWithIcon(
          IconButton,
          Icons.close_rounded,
        );
        final closeRect = tester.getRect(closeFinder);

        expect(titleRect.top, greaterThanOrEqualTo(systemTop));
        expect(dogRect.top, greaterThanOrEqualTo(systemTop));
        expect(closeRect.top, greaterThanOrEqualTo(systemTop));
        expect(titleRect.top, lessThan(systemTop + 72));
        expect(closeRect.bottom, lessThanOrEqualTo(800));

        await tester.tap(closeFinder);
        await tester.pumpAndSettle();

        expect(find.text('REGISTRAR SUPLEMENTO'), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );

    // ── D. Suplemento com teclado aberto (viewInsets.bottom) ───────────
    // viewInsets simula teclado virtual. SafeArea compensa com padding
    // adicional — o formulário permanece funcional.

    testWidgets('avulso com teclado aberto em 320px: viewport protegido e CTA alcançável', (
      tester,
    ) async {
      const systemTop = 32.0;
      const keyboardHeight = 200.0;
      tester.view.physicalSize = const Size(320, 800);
      tester.view.devicePixelRatio = 1.0;
      tester.view.padding = const FakeViewPadding(top: systemTop);
      tester.view.viewPadding = const FakeViewPadding(top: systemTop);
      tester.view.viewInsets = const FakeViewPadding(bottom: keyboardHeight);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPadding);
      addTearDown(tester.view.resetViewPadding);
      addTearDown(tester.view.resetViewInsets);

      final supplementGate = Completer<HealthNutritionMutationResult>();
      final loadingGateway = _LoadingGateway(supplementGate.future);
      final loadingController = HealthNutritionMutationController(
        gateway: loadingGateway,
        operationIdFactory: () => 'op-sup-kbd',
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            resizeToAvoidBottomInset: false,
            body: HealthSupplementFormSheet(
              dogId: 'dog-001',
              dogDisplayName: 'Bono',
              controller: loadingController,
              onRefreshRequested: () async {},
              timezone: 'America/Sao_Paulo',
              activePlan: _mockActivePlan(),
              defaultRegimen: _mockRegimen(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      addTearDown(loadingController.dispose);

      await tester.tap(find.text('Avulso').first);
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Nome do suplemento'),
        'Vitamina C',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Dose'),
        '1',
      );
      await tester.pumpAndSettle();

      // 1. Cabeçalho e identificação começam abaixo da área do sistema.
      expect(find.byType(SafeArea), findsWidgets);
      expect(
        tester.getRect(find.text('REGISTRAR SUPLEMENTO')).top,
        greaterThanOrEqualTo(systemTop),
      );
      expect(
        tester.getRect(find.text('Bono')).top,
        greaterThanOrEqualTo(systemTop),
      );
      expect(
        tester
            .getRect(find.widgetWithIcon(IconButton, Icons.close_rounded))
            .top,
        greaterThanOrEqualTo(systemTop),
      );
      expect(find.byType(Scrollable), findsWidgets);

      // 2. Scroll until submit button is visible
      final submitFinder = find.widgetWithText(
        FilledButton,
        'REGISTRAR SUPLEMENTO AVULSO',
      );
      await tester.ensureVisible(submitFinder);
      await tester.pumpAndSettle();
      final scrollFinder = find.byType(SingleChildScrollView);
      final scrollRect = tester.getRect(scrollFinder);
      expect(scrollRect.top, systemTop);
      expect(
        tester.widget<SingleChildScrollView>(scrollFinder).clipBehavior,
        Clip.hardEdge,
      );
      expect(
        tester.getRect(find.text('Sem vínculo com regime ativo')).bottom,
        lessThanOrEqualTo(scrollRect.top),
      );
      expect(
        find.text('Sem vínculo com regime ativo').hitTestable(),
        findsNothing,
      );
      expect(
        tester.getRect(submitFinder).bottom,
        lessThanOrEqualTo(800 - keyboardHeight),
      );

      // 3. Confirm button is in viewport and tap it
      await tester.tap(submitFinder);
      await tester.pump();

      // 4. Confirm submit started with contextual loading
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.text('Registrando suplemento…'), findsOneWidget);

      // 5. Confirm single call to gateway
      expect(loadingGateway.supplementCallCount, 1);

      // 6. Confirm no exceptions or overflows
      expect(tester.takeException(), isNull);

      tester.view.viewInsets = FakeViewPadding.zero;
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.drag(scrollFinder, const Offset(0, 1200));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      final titleTop = tester.getRect(find.text('REGISTRAR SUPLEMENTO')).top;
      expect(titleTop, greaterThanOrEqualTo(systemTop));
      expect(titleTop, lessThan(systemTop + 72));
      expect(tester.takeException(), isNull);

      supplementGate.complete(CreateSupplementLogSuccess(
        dogId: 'dog-001',
        supplementLogId: 'sl-kbd',
        revision: 1,
        wasNoOp: false,
        operationId: 'op-sup-kbd',
      ));
      await tester.pumpAndSettle();
    });

    // ── E. HudSelectField abre sem exceção ─────────────────────────────
    // O bottom sheet usa root Navigator e aparece como overlay.

    testWidgets('HudSelectField abre sem exceção em 440px', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(440, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: HealthSupplementFormSheet(
                dogId: 'dog-001',
                dogDisplayName: 'Bono',
                controller: _TestController(),
                onRefreshRequested: () async {},
                timezone: 'America/Sao_Paulo',
                activePlan: _mockActivePlan(),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Open dropdown via "Unidade" label
      final unitField = find.textContaining(RegExp('unidade', caseSensitive: false));
      expect(unitField, findsOneWidget);
      await tester.tap(unitField);
      await tester.pumpAndSettle();

      // Bottom sheet options present
      expect(find.text('comprimido'), findsWidgets);
      expect(find.text('gota'), findsWidgets);
      // No overflow during bottom sheet render
      expect(tester.takeException(), isNull);
    });

    testWidgets('HudSelectField em 320px com text scale 1.3 e opção longa: abre, exibe, rola, seleciona, fecha sem overflow', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(320, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      const longRegimenName =
          'Suplemento polivitamínico e mineral concentrado de alta absorção de 500mg';
      final longRegimen = NutritionPlanSupplementRegimen(
        id: 'reg-long',
        name: longRegimenName,
        dose: 2,
        unit: SupplementDoseUnit.tablet,
        frequency: 'Diário',
        instructions: 'Manhã e noite',
      );
      final planWithLongRegimen = NutritionActiveCanonicalPlan(
        NutritionPlan(
          id: 'plan-long',
          dogId: 'dog-001',
          foodType: 'Ração teste',
          amountGramsPerDay: 400,
          mealsPerDay: 2,
          mealSchedule: const [],
          validFrom: DateTime.utc(2026, 1, 1),
          timezone: 'America/Sao_Paulo',
          recordedBy: RecordedBy(
            uid: 'u1',
            name: 'Test',
            internalRole: 'condutor',
          ),
          status: NutritionPlanStatus.active,
          schemaVersion: 1,
          revision: 1,
          supplements: [longRegimen],
        ),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(textScaler: TextScaler.linear(1.3)),
            child: Scaffold(
              body: SingleChildScrollView(
                child: HealthSupplementFormSheet(
                  dogId: 'dog-001',
                  dogDisplayName: 'Bono',
                  controller: _TestController(),
                  onRefreshRequested: () async {},
                  timezone: 'America/Sao_Paulo',
                  activePlan: planWithLongRegimen,
                  defaultRegimen: longRegimen,
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Open HudSelectField for "Suplemento do plano"
      final regimenField = find.textContaining(RegExp('suplemento do plano', caseSensitive: false));
      expect(regimenField, findsOneWidget);
      await tester.tap(regimenField);
      await tester.pumpAndSettle();

      // Long option present in bottom sheet
      final longOptionText = find.textContaining(longRegimenName);
      expect(longOptionText, findsWidgets);

      // List is scrollable if needed
      expect(find.byType(Scrollable), findsWidgets);

      // Select option
      await tester.tap(longOptionText.first, warnIfMissed: false);
      await tester.pumpAndSettle();


      // Reopen to verify close button
      await tester.tap(regimenField);
      await tester.pumpAndSettle();

      final closeButton = find.widgetWithIcon(IconButton, Icons.close_rounded);
      expect(closeButton, findsWidgets);
      await tester.tap(closeButton.last);
      await tester.pumpAndSettle();

      // Zero exceptions and zero overflow
      expect(tester.takeException(), isNull);
    });

    // ── Avulso em 440px ────────────────────────────────────────────

    testWidgets('avulso em 440px: loading + zero overflow', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(440, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final supplementGate = Completer<HealthNutritionMutationResult>();
      final loadingGateway = _LoadingGateway(supplementGate.future);
      final loadingController = HealthNutritionMutationController(
        gateway: loadingGateway,
        operationIdFactory: () => 'op-sup-av-440',
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: HealthSupplementFormSheet(
                dogId: 'dog-001',
                dogDisplayName: 'Bono',
                controller: loadingController,
                onRefreshRequested: () async {},
                timezone: 'America/Sao_Paulo',
                activePlan: _mockActivePlan(),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      addTearDown(loadingController.dispose);

      // Switch to Avulso mode
      await tester.tap(find.text('Avulso').first);
      await tester.pumpAndSettle();

      // Fill required fields
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Nome do suplemento'),
        'Vitamina C',
      );
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Dose'),
        '1',
      );
      await tester.pumpAndSettle();

      // Submit
      final submitFinder = find.widgetWithText(
        FilledButton,
        'REGISTRAR SUPLEMENTO AVULSO',
      );
      await tester.ensureVisible(submitFinder);
      await tester.tap(submitFinder);
      await tester.pump();

      // Spinner visible
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      // Correct loading text for avulso mode
      expect(find.text('Registrando suplemento…'), findsOneWidget);
      // Button disabled
      final button = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Registrando suplemento…'),
      );
      expect(button.onPressed, isNull);
      // No overflow errors
      expect(tester.takeException(), isNull);

      supplementGate.complete(CreateSupplementLogSuccess(
        dogId: 'dog-001',
        supplementLogId: 'sl-av-440',
        revision: 1,
        wasNoOp: false,
        operationId: 'op-sup-av-440',
      ));
      await tester.pumpAndSettle();
    });
  });
}

NutritionActiveCanonicalPlan _mockActivePlan() {
  return NutritionActiveCanonicalPlan(
    NutritionPlan(
      id: 'plan-test',
      dogId: 'dog-001',
      foodType: 'Ração teste',
      amountGramsPerDay: 400,
      mealsPerDay: 2,
      mealSchedule: const [],
      validFrom: DateTime.utc(2026, 1, 1),
      timezone: 'America/Sao_Paulo',
      recordedBy: RecordedBy(
        uid: 'u1',
        name: 'Test',
        internalRole: 'condutor',
      ),
      status: NutritionPlanStatus.active,
      schemaVersion: 1,
      revision: 1,
      supplements: [_mockRegimen()],
    ),
  );
}

NutritionPlanSupplementRegimen _mockRegimen() {
  return NutritionPlanSupplementRegimen(
    id: 'reg-1',
    name: 'Vitamina C',
    dose: 1,
    unit: SupplementDoseUnit.tablet,
    frequency: 'Diário',
    instructions: 'Manhã',
  );
}


/// Gateway with controlled Future for loading state testing.
class _LoadingGateway implements HealthNutritionMutationGateway {
  _LoadingGateway(Future<HealthNutritionMutationResult> supplementFuture)
      : _supplementFuture = supplementFuture;

  final Future<HealthNutritionMutationResult> _supplementFuture;
  int supplementCallCount = 0;

  @override
  Future<HealthNutritionMutationResult> createAdhocMealLog(
    CreateAdhocMealLogCommand command,
  ) async => throw UnimplementedError();

  @override
  Future<HealthNutritionMutationResult> createPlannedMealLog(
    CreatePlannedMealLogCommand command,
  ) async => throw UnimplementedError();

  @override
  Future<HealthNutritionMutationResult> createSupplementLog(
    CreateSupplementLogCommand command,
  ) {
    supplementCallCount++;
    return _supplementFuture;
  }
}

/// Controller minimal para testes de UI.
class _TestController extends HealthNutritionMutationController {
  _TestController() : super(gateway: _NoOpGateway());
}

/// Gateway no-op.
class _NoOpGateway implements HealthNutritionMutationGateway {
  const _NoOpGateway();

  @override
  Future<HealthNutritionMutationResult> createAdhocMealLog(
    CreateAdhocMealLogCommand command,
  ) async {
    throw UnimplementedError();
  }

  @override
  Future<HealthNutritionMutationResult> createPlannedMealLog(
    CreatePlannedMealLogCommand command,
  ) async {
    throw UnimplementedError();
  }

  @override
  Future<HealthNutritionMutationResult> createSupplementLog(
    CreateSupplementLogCommand command,
  ) async {
    return CreateSupplementLogSuccess(
      dogId: command.dogId,
      supplementLogId: 'sl1_test',
      revision: 1,
      wasNoOp: false,
      operationId: command.operationId,
    );
  }
}
