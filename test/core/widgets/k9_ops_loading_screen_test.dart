import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:canil_gcm/core/widgets/k9_ops_loading_screen.dart';
import 'package:canil_gcm/core/widgets/k9_ops_loading_stage.dart';
import 'package:canil_gcm/core/widgets/k9_ops_loading_visual.dart';

void main() {
  /// Envolve o widget em um MaterialApp, opcionalmente com movimento reduzido.
  Widget wrap(Widget child, {bool disableAnimations = false}) {
    return MaterialApp(
      home: Builder(
        builder: (context) {
          final mediaQuery = MediaQuery.of(context);
          return MediaQuery(
            data: mediaQuery.copyWith(disableAnimations: disableAnimations),
            child: child,
          );
        },
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

  group('K9OpsLoadingScreen — asset injetável e fallback oficial', () {
    testWidgets(
      'sem visual customizado: renderiza o fallback oficial K9OpsLoadingVisual',
      (tester) async {
        await tester.pumpWidget(wrap(const K9OpsLoadingScreen()));

        expect(find.byType(K9OpsLoadingVisual), findsOneWidget);
        expect(find.byType(Image), findsOneWidget);
      },
    );

    testWidgets(
      'com visual customizado: o override continua sendo respeitado',
      (tester) async {
        await tester.pumpWidget(
          wrap(
            const K9OpsLoadingScreen(
              visual: SizedBox(
                key: Key('malinois-override'),
                width: 100,
                height: 100,
              ),
            ),
          ),
        );

        expect(find.byKey(const Key('malinois-override')), findsOneWidget);
        expect(find.byType(K9OpsLoadingVisual), findsNothing);
      },
    );

    testWidgets('ausência de dependência Lottie: opera sem erros', (
      tester,
    ) async {
      await tester.pumpWidget(wrap(const K9OpsLoadingScreen()));

      expect(tester.takeException(), isNull);
    });

    testWidgets('não gera overflow em viewport mobile estreita (320x568)', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(320, 568);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(wrap(const K9OpsLoadingScreen(progress: 0.5)));

      expect(tester.takeException(), isNull);
    });
  });

  group('K9OpsLoadingScreen — reduced motion e mídia animada', () {
    testWidgets(
      'aplica configuracao com movimento reduzido ativado (disableAnimations = true): usa PNG estatico',
      (tester) async {
        await tester.pumpWidget(
          wrap(const K9OpsLoadingScreen(), disableAnimations: true),
        );

        expect(find.text('INICIALIZANDO SISTEMA...'), findsOneWidget);
        expect(find.byType(K9OpsLoadingVisual), findsOneWidget);

        final image = tester.widget<Image>(find.byType(Image));
        final provider = image.image as AssetImage;
        expect(
          provider.assetName,
          'assets/images/k9_ops_loading_dog_static_v1.png',
        );
      },
    );

    testWidgets(
      'com movimento permitido (disableAnimations = false): prefere Animated WebP',
      (tester) async {
        await tester.pumpWidget(
          wrap(const K9OpsLoadingScreen(), disableAnimations: false),
        );

        expect(find.byType(K9OpsLoadingVisual), findsOneWidget);

        final image = tester.widget<Image>(find.byType(Image));
        final provider = image.image as AssetImage;
        expect(
          provider.assetName,
          'assets/images/k9_ops_loading_dog_animated.webp',
        );
      },
    );

    testWidgets(
      'K9OpsLoadingVisual com assetPath customizado respeita o caminho informado',
      (tester) async {
        await tester.pumpWidget(
          wrap(
            const K9OpsLoadingVisual(assetPath: 'assets/images/custom_dog.png'),
          ),
        );

        final image = tester.widget<Image>(find.byType(Image));
        final provider = image.image as AssetImage;
        expect(provider.assetName, 'assets/images/custom_dog.png');
      },
    );
  });
}
