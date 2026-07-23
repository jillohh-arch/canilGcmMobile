import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:canil_gcm/core/theme/app_theme.dart';
import 'package:canil_gcm/core/widgets/k9_ops_loading_screen.dart';
import 'package:canil_gcm/core/widgets/k9_ops_loading_stage.dart';

void main() {
  /// Envolve o widget em um MaterialApp, opcionalmente com movimento reduzido.
  Widget wrap(Widget child, {bool disableAnimations = false}) {
    return MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(disableAnimations: disableAnimations),
        child: child,
      ),
    );
  }

  group('K9OpsLoadingScreen — estrutura visual', () {
    testWidgets('exibe título e footer institucional', (tester) async {
      await tester.pumpWidget(wrap(const K9OpsLoadingScreen()));

      expect(find.text('INICIALIZANDO SISTEMA...'), findsOneWidget);
      expect(find.text('K9 OPS • INTELLIGENCE IN MOTION'), findsOneWidget);
    });

    testWidgets('exibe as duas etapas oficiais do Mobile', (tester) async {
      await tester.pumpWidget(wrap(const K9OpsLoadingScreen()));

      expect(find.text('Validando acesso'), findsOneWidget);
      expect(find.text('Sincronizando módulos'), findsOneWidget);
    });

    testWidgets('exibe versão quando fornecida', (tester) async {
      await tester.pumpWidget(
        wrap(const K9OpsLoadingScreen(version: 'v1.0.0')),
      );

      expect(find.text('v1.0.0'), findsOneWidget);
    });

    testWidgets('exibe mensagem de status explícita quando fornecida', (
      tester,
    ) async {
      await tester.pumpWidget(
        wrap(const K9OpsLoadingScreen(message: 'Finalizando inicialização...')),
      );

      expect(find.text('Finalizando inicialização...'), findsOneWidget);
    });

    testWidgets('não duplica rótulo de etapa como status por padrão', (
      tester,
    ) async {
      await tester.pumpWidget(
        wrap(
          const K9OpsLoadingScreen(stage: K9OpsLoadingStage.validatingAccess),
        ),
      );

      // "Validando acesso" aparece só como etapa, não também como status.
      expect(find.text('Validando acesso'), findsOneWidget);
    });
  });

  group('K9OpsLoadingScreen — estágios', () {
    testWidgets('validatingAccess não marca etapas como concluídas', (
      tester,
    ) async {
      await tester.pumpWidget(
        wrap(
          const K9OpsLoadingScreen(stage: K9OpsLoadingStage.validatingAccess),
        ),
      );

      expect(find.byIcon(Icons.check_rounded), findsNothing);
    });

    testWidgets('syncingModules marca a primeira etapa como concluída', (
      tester,
    ) async {
      await tester.pumpWidget(
        wrap(const K9OpsLoadingScreen(stage: K9OpsLoadingStage.syncingModules)),
      );

      expect(find.byIcon(Icons.check_rounded), findsOneWidget);
    });

    testWidgets('ready marca todas as etapas como concluídas', (tester) async {
      await tester.pumpWidget(
        wrap(const K9OpsLoadingScreen(stage: K9OpsLoadingStage.ready)),
      );

      expect(find.byIcon(Icons.check_rounded), findsNWidgets(2));
    });

    testWidgets('error exibe mensagem e não exibe etapas', (tester) async {
      await tester.pumpWidget(
        wrap(
          const K9OpsLoadingScreen(
            stage: K9OpsLoadingStage.error,
            errorMessage: 'Falha de conexão',
          ),
        ),
      );

      expect(find.text('Falha de conexão'), findsOneWidget);
      expect(find.byIcon(Icons.error_outline_rounded), findsOneWidget);
      expect(find.text('Validando acesso'), findsNothing);
    });

    testWidgets('error exibe retry quando callback fornecido', (tester) async {
      var retried = false;
      await tester.pumpWidget(
        wrap(
          K9OpsLoadingScreen(
            stage: K9OpsLoadingStage.error,
            onRetry: () => retried = true,
          ),
        ),
      );

      expect(find.text('Tentar novamente'), findsOneWidget);
      await tester.tap(find.text('Tentar novamente'));
      expect(retried, isTrue);
    });

    testWidgets('error sem callback não exibe retry', (tester) async {
      await tester.pumpWidget(
        wrap(const K9OpsLoadingScreen(stage: K9OpsLoadingStage.error)),
      );

      expect(find.text('Tentar novamente'), findsNothing);
    });
  });

  group('K9OpsLoadingScreen — progresso', () {
    testWidgets('exibe percentual quando progress é fornecido', (tester) async {
      await tester.pumpWidget(wrap(const K9OpsLoadingScreen(progress: 0.45)));

      expect(find.text('45%'), findsOneWidget);
    });

    testWidgets('não exibe percentual em modo indeterminado', (tester) async {
      await tester.pumpWidget(wrap(const K9OpsLoadingScreen()));

      expect(find.textContaining('%'), findsNothing);
    });

    testWidgets('clampa progress acima de 1.0 para 100%', (tester) async {
      await tester.pumpWidget(wrap(const K9OpsLoadingScreen(progress: 1.5)));

      expect(find.text('100%'), findsOneWidget);
    });

    testWidgets('progress reflete no LinearProgressIndicator', (tester) async {
      await tester.pumpWidget(wrap(const K9OpsLoadingScreen(progress: 0.7)));

      final indicator = tester.widget<LinearProgressIndicator>(
        find.byType(LinearProgressIndicator),
      );
      expect(indicator.value, closeTo(0.7, 0.001));
    });
  });

  group('K9OpsLoadingScreen — asset injetável', () {
    testWidgets('usa marcador neutro quando visual é null', (tester) async {
      await tester.pumpWidget(wrap(const K9OpsLoadingScreen()));

      expect(find.byIcon(Icons.pets_rounded), findsOneWidget);
    });

    testWidgets('renderiza visual injetado no lugar do marcador', (
      tester,
    ) async {
      await tester.pumpWidget(
        wrap(
          const K9OpsLoadingScreen(
            visual: SizedBox(key: Key('malinois'), width: 100, height: 100),
          ),
        ),
      );

      expect(find.byKey(const Key('malinois')), findsOneWidget);
      expect(find.byIcon(Icons.pets_rounded), findsNothing);
    });
  });

  group('K9OpsLoadingScreen — reduced motion', () {
    testWidgets('aplica configuracao com movimento reduzido ativado (disableAnimations = true)', (tester) async {
      await tester.pumpWidget(
        wrap(const K9OpsLoadingScreen(), disableAnimations: true),
      );

      expect(find.text('INICIALIZANDO SISTEMA...'), findsOneWidget);
      final icon = tester.widget<Icon>(find.byIcon(Icons.pets_rounded));
      expect(icon.color, equals(AppTheme.primary.withAlpha(110)));
    });

    testWidgets('aplica opacidade padrao quando movimento nao e reduzido (disableAnimations = false)', (tester) async {
      await tester.pumpWidget(
        wrap(const K9OpsLoadingScreen(), disableAnimations: false),
      );

      final icon = tester.widget<Icon>(find.byIcon(Icons.pets_rounded));
      expect(icon.color, equals(AppTheme.primary.withAlpha(140)));
    });
  });
}
