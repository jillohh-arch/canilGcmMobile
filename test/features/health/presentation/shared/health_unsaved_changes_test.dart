import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:canil_gcm/features/health/presentation/shared/forms/health_form_controller.dart';
import 'package:canil_gcm/features/health/presentation/shared/forms/health_form_scaffold.dart';
import 'package:canil_gcm/features/health/presentation/shared/forms/health_unsaved_changes.dart';
import 'package:canil_gcm/features/health/presentation/shared/widgets/health_form_actions.dart';
import 'package:canil_gcm/features/health/presentation/shared/widgets/health_form_section.dart';

void main() {
  setUpAll(() {
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  Future<void> openForm(
    WidgetTester tester, {
    required HealthFormController controller,
    required String bodyText,
    String title = 'Formulário',
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            return Scaffold(
              body: Center(
                child: TextButton(
                  onPressed: () {
                    Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => HealthFormScaffold(
                          title: title,
                          controller: controller,
                          body: Text(bodyText),
                        ),
                      ),
                    );
                  },
                  child: const Text('open'),
                ),
              ),
            );
          },
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  group('AppBar back', () {
    testWidgets('pristine fecha direto sem diálogo', (tester) async {
      final controller = HealthFormController();
      addTearDown(controller.dispose);

      await openForm(tester, controller: controller, bodyText: 'form-body');
      expect(find.text('form-body'), findsOneWidget);

      await tester.tap(find.byIcon(Icons.arrow_back_ios_new_rounded));
      await tester.pumpAndSettle();

      expect(find.text('form-body'), findsNothing);
      expect(find.text('Alterações não salvas'), findsNothing);
      expect(find.text('open'), findsOneWidget);
    });

    testWidgets('dirty + cancelar permanece na rota', (tester) async {
      final controller = HealthFormController();
      addTearDown(controller.dispose);
      controller.markDirty();

      await openForm(tester, controller: controller, bodyText: 'dirty-form');

      await tester.tap(find.byIcon(Icons.arrow_back_ios_new_rounded));
      await tester.pumpAndSettle();
      expect(find.text('Alterações não salvas'), findsOneWidget);

      await tester.tap(find.text('Continuar editando'));
      await tester.pumpAndSettle();

      expect(find.text('dirty-form'), findsOneWidget);
      expect(find.text('Alterações não salvas'), findsNothing);
      expect(find.text('open'), findsNothing);
    });

    testWidgets('dirty + confirmar fecha somente a rota atual', (tester) async {
      final controller = HealthFormController();
      addTearDown(controller.dispose);
      controller.markDirty();

      await openForm(
        tester,
        controller: controller,
        bodyText: 'dirty-form-leave',
      );

      await tester.tap(find.byIcon(Icons.arrow_back_ios_new_rounded));
      await tester.pumpAndSettle();
      expect(find.text('Alterações não salvas'), findsOneWidget);

      await tester.tap(find.text('Sair sem salvar'));
      await tester.pumpAndSettle();

      expect(find.text('dirty-form-leave'), findsNothing);
      expect(find.text('Alterações não salvas'), findsNothing);
      expect(find.text('open'), findsOneWidget);
    });

    testWidgets('submitting bloqueia AppBar sem diálogo e sem pop', (
      tester,
    ) async {
      final controller = HealthFormController();
      addTearDown(controller.dispose);
      final release = Completer<void>();

      await openForm(
        tester,
        controller: controller,
        bodyText: 'submitting-form',
      );

      final submitFuture = controller.submit(action: () => release.future);
      await tester.pump();
      expect(controller.isSubmitting, isTrue);

      await tester.tap(find.byIcon(Icons.arrow_back_ios_new_rounded));
      await tester.pumpAndSettle();

      expect(find.text('submitting-form'), findsOneWidget);
      expect(find.text('Alterações não salvas'), findsNothing);

      release.complete();
      await submitFuture;
    });
  });

  group('System back / maybePop', () {
    testWidgets('dirty + cancelar via maybePop permanece', (tester) async {
      final controller = HealthFormController();
      addTearDown(controller.dispose);
      controller.markDirty();

      await openForm(tester, controller: controller, bodyText: 'guarded-dirty');

      final navigator = tester.state<NavigatorState>(
        find.byType(Navigator).first,
      );
      await navigator.maybePop();
      await tester.pumpAndSettle();

      expect(find.text('Alterações não salvas'), findsOneWidget);
      await tester.tap(find.text('Continuar editando'));
      await tester.pumpAndSettle();

      expect(find.text('guarded-dirty'), findsOneWidget);
      expect(find.text('open'), findsNothing);
    });

    testWidgets('dirty + confirmar via maybePop fecha uma rota', (
      tester,
    ) async {
      final controller = HealthFormController();
      addTearDown(controller.dispose);
      controller.markDirty();

      await openForm(
        tester,
        controller: controller,
        bodyText: 'guarded-confirm',
      );

      final navigator = tester.state<NavigatorState>(
        find.byType(Navigator).first,
      );
      await navigator.maybePop();
      await tester.pumpAndSettle();
      expect(find.text('Alterações não salvas'), findsOneWidget);

      await tester.tap(find.text('Sair sem salvar'));
      await tester.pumpAndSettle();

      expect(find.text('guarded-confirm'), findsNothing);
      expect(find.text('Alterações não salvas'), findsNothing);
      expect(find.text('open'), findsOneWidget);
    });

    testWidgets('pristine maybePop fecha sem diálogo', (tester) async {
      final controller = HealthFormController();
      addTearDown(controller.dispose);

      await openForm(
        tester,
        controller: controller,
        bodyText: 'pristine-maybe',
      );

      final navigator = tester.state<NavigatorState>(
        find.byType(Navigator).first,
      );
      await navigator.maybePop();
      await tester.pumpAndSettle();

      expect(find.text('pristine-maybe'), findsNothing);
      expect(find.text('Alterações não salvas'), findsNothing);
      expect(find.text('open'), findsOneWidget);
    });

    testWidgets('submitting maybePop não abre diálogo e não perde form', (
      tester,
    ) async {
      final controller = HealthFormController();
      addTearDown(controller.dispose);
      final release = Completer<void>();

      await openForm(
        tester,
        controller: controller,
        bodyText: 'submitting-maybe',
      );

      final submitFuture = controller.submit(action: () => release.future);
      await tester.pump();

      final navigator = tester.state<NavigatorState>(
        find.byType(Navigator).first,
      );
      await navigator.maybePop();
      await tester.pumpAndSettle();

      expect(find.text('submitting-maybe'), findsOneWidget);
      expect(find.text('Alterações não salvas'), findsNothing);

      release.complete();
      await submitFuture;
    });

    testWidgets('back concorrente não abre diálogo duplicado', (tester) async {
      final controller = HealthFormController();
      addTearDown(controller.dispose);
      controller.markDirty();

      await openForm(
        tester,
        controller: controller,
        bodyText: 'reentrancy-form',
      );

      final navigator = tester.state<NavigatorState>(
        find.byType(Navigator).first,
      );
      // Dois pops em sequência rápida antes do usuário responder.
      unawaited(navigator.maybePop());
      unawaited(navigator.maybePop());
      await tester.pumpAndSettle();

      expect(find.text('Alterações não salvas'), findsOneWidget);
      expect(find.text('Sair sem salvar'), findsOneWidget);

      await tester.tap(find.text('Continuar editando'));
      await tester.pumpAndSettle();
      expect(find.text('reentrancy-form'), findsOneWidget);
    });
  });

  group('HealthUnsavedChangesGuard isolado', () {
    testWidgets('bloqueia pop do sistema quando dirty', (tester) async {
      final controller = HealthFormController();
      addTearDown(controller.dispose);
      controller.markDirty();

      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) {
              return Scaffold(
                body: Center(
                  child: TextButton(
                    onPressed: () {
                      Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => HealthUnsavedChangesGuard(
                            controller: controller,
                            child: const Scaffold(
                              body: Center(child: Text('guarded')),
                            ),
                          ),
                        ),
                      );
                    },
                    child: const Text('open'),
                  ),
                ),
              );
            },
          ),
        ),
      );

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      final navigator = tester.state<NavigatorState>(
        find.byType(Navigator).first,
      );
      await navigator.maybePop();
      await tester.pumpAndSettle();

      expect(find.text('guarded'), findsOneWidget);
      expect(find.text('Alterações não salvas'), findsOneWidget);

      await tester.tap(find.text('Continuar editando'));
      await tester.pumpAndSettle();
      expect(find.text('guarded'), findsOneWidget);
    });
  });

  testWidgets('HealthFormActions desabilita botão durante submit', (
    tester,
  ) async {
    final controller = HealthFormController();
    addTearDown(controller.dispose);
    final gate = Completer<void>();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: HealthFormActions(
            controller: controller,
            onSubmit: () {},
            submitLabel: 'SALVAR REGISTRO',
          ),
        ),
      ),
    );

    expect(find.text('SALVAR REGISTRO'), findsOneWidget);

    final future = controller.submit(action: () => gate.future);
    await tester.pump();

    expect(find.text('SALVANDO...'), findsOneWidget);
    final button = tester.widget<ElevatedButton>(find.byType(ElevatedButton));
    expect(button.onPressed, isNull);

    gate.complete();
    await future;
    await tester.pump();
  });

  testWidgets('HealthFormSection renderiza título e filho', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: HealthFormSection(
            title: 'Dados principais',
            child: Text('conteudo-secao'),
          ),
        ),
      ),
    );

    expect(find.text('DADOS PRINCIPAIS'), findsOneWidget);
    expect(find.text('conteudo-secao'), findsOneWidget);
  });
}
