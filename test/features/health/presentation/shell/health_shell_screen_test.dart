import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:canil_gcm/features/health/presentation/screens/health_shell_screen.dart';
import 'package:canil_gcm/features/health/presentation/widgets/health_module_header.dart';
import 'package:canil_gcm/features/health/presentation/widgets/health_section_navigation.dart';
import 'package:canil_gcm/features/health/presentation/widgets/health_shell_section.dart';
import 'package:canil_gcm/features/health/presentation/widgets/health_shell_section_placeholder.dart';

void main() {
  setUpAll(() {
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  Widget wrap(
    Widget child, {
    double width = 390,
    double height = 844,
    double textScale = 1.0,
  }) {
    return MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(
          size: Size(width, height),
          textScaler: TextScaler.linear(textScale),
        ),
        child: Scaffold(
          body: SizedBox(width: width, height: height, child: child),
        ),
      ),
    );
  }

  HealthShellScreen shell({
    VoidCallback? onRegister,
    ValueChanged<HealthShellSection>? onSectionChanged,
    Widget Function(BuildContext)? resumo,
    Widget Function(BuildContext)? historico,
    Widget Function(BuildContext)? agenda,
    Widget Function(BuildContext)? nutricao,
  }) {
    return HealthShellScreen(
      onRegister: onRegister,
      onSectionChanged: onSectionChanged,
      resumo: resumo ?? (_) => const Text('conteudo-resumo'),
      historico: historico ?? (_) => const Text('conteudo-historico'),
      agenda: agenda ?? (_) => const Text('conteudo-agenda'),
      nutricao: nutricao ?? (_) => const Text('conteudo-nutricao'),
    );
  }

  group('HealthShellScreen — navegação', () {
    testWidgets('Resumo selecionado inicialmente e conteúdo visível', (
      tester,
    ) async {
      await tester.pumpWidget(wrap(shell()));

      final state = tester.state<HealthShellScreenState>(
        find.byType(HealthShellScreen),
      );
      expect(state.selectedSection, HealthShellSection.resumo);
      expect(find.text('conteudo-resumo'), findsOneWidget);
      expect(find.text(HealthModuleHeader.title), findsOneWidget);
      expect(find.text(HealthModuleHeader.subtitle), findsOneWidget);
    });

    testWidgets('troca entre as quatro seções exibe conteúdo correto', (
      tester,
    ) async {
      final selections = <HealthShellSection>[];

      await tester.pumpWidget(wrap(shell(onSectionChanged: selections.add)));

      Future<void> expectSection(
        HealthShellSection section,
        String body,
      ) async {
        await tester.tap(find.text(section.label));
        await tester.pumpAndSettle();
        final state = tester.state<HealthShellScreenState>(
          find.byType(HealthShellScreen),
        );
        expect(state.selectedSection, section);
        expect(find.text(body), findsOneWidget);
      }

      await expectSection(HealthShellSection.historico, 'conteudo-historico');
      await expectSection(HealthShellSection.agenda, 'conteudo-agenda');
      await expectSection(HealthShellSection.nutricao, 'conteudo-nutricao');
      await expectSection(HealthShellSection.resumo, 'conteudo-resumo');

      expect(selections, [
        HealthShellSection.historico,
        HealthShellSection.agenda,
        HealthShellSection.nutricao,
        HealthShellSection.resumo,
      ]);
    });

    testWidgets(
      'tap em seção muda exatamente uma seleção; retap não re-notifica',
      (tester) async {
        final selections = <HealthShellSection>[];
        await tester.pumpWidget(wrap(shell(onSectionChanged: selections.add)));

        final state = tester.state<HealthShellScreenState>(
          find.byType(HealthShellScreen),
        );
        expect(state.selectedSection, HealthShellSection.resumo);

        await tester.tap(find.text('Histórico'));
        await tester.pumpAndSettle();
        expect(state.selectedSection, HealthShellSection.historico);
        expect(find.text('conteudo-historico'), findsOneWidget);
        expect(selections, [HealthShellSection.historico]);

        await tester.tap(find.text('Histórico'));
        await tester.pumpAndSettle();
        expect(selections, [HealthShellSection.historico]);
      },
    );
  });

  group('HealthShellScreen — lazy init e preservação', () {
    testWidgets('somente Resumo monta na abertura; demais sob demanda', (
      tester,
    ) async {
      final inits = <HealthShellSection, int>{
        for (final s in HealthShellSection.navigationOrder) s: 0,
      };

      Widget probe(HealthShellSection section, String label) {
        return _InitProbe(
          key: ValueKey('probe-$label'),
          section: section,
          label: label,
          onInit: () => inits[section] = (inits[section] ?? 0) + 1,
        );
      }

      await tester.pumpWidget(
        wrap(
          shell(
            resumo: (_) => probe(HealthShellSection.resumo, 'resumo'),
            historico: (_) => probe(HealthShellSection.historico, 'historico'),
            agenda: (_) => probe(HealthShellSection.agenda, 'agenda'),
            nutricao: (_) => probe(HealthShellSection.nutricao, 'nutricao'),
          ),
        ),
      );
      await tester.pump();

      final state = tester.state<HealthShellScreenState>(
        find.byType(HealthShellScreen),
      );
      expect(state.visitedSectionsForTest, {HealthShellSection.resumo});
      expect(inits[HealthShellSection.resumo], 1);
      expect(inits[HealthShellSection.historico], 0);
      expect(inits[HealthShellSection.agenda], 0);
      expect(inits[HealthShellSection.nutricao], 0);
      expect(find.text('area-resumo'), findsOneWidget);

      await tester.tap(find.text('Histórico'));
      await tester.pumpAndSettle();
      expect(inits[HealthShellSection.historico], 1);
      expect(state.visitedSectionsForTest, {
        HealthShellSection.resumo,
        HealthShellSection.historico,
      });

      await tester.tap(find.text('Agenda'));
      await tester.pumpAndSettle();
      expect(inits[HealthShellSection.agenda], 1);

      await tester.tap(find.text('Nutrição'));
      await tester.pumpAndSettle();
      expect(inits[HealthShellSection.nutricao], 1);

      // Voltar não remonta Resumo.
      await tester.tap(find.text('Resumo'));
      await tester.pumpAndSettle();
      expect(inits[HealthShellSection.resumo], 1);
      expect(inits[HealthShellSection.historico], 1);
    });

    testWidgets('estado interno de área A sobrevive a ida e volta de B', (
      tester,
    ) async {
      await tester.pumpWidget(
        wrap(
          shell(resumo: (_) => const _ToggleProbe(key: Key('probe-resumo'))),
        ),
      );

      expect(find.text('estado: off'), findsOneWidget);
      await tester.tap(find.text('Alternar'));
      await tester.pump();
      expect(find.text('estado: on'), findsOneWidget);

      await tester.tap(find.text('Histórico'));
      await tester.pumpAndSettle();
      expect(find.text('conteudo-historico'), findsOneWidget);

      await tester.tap(find.text('Resumo'));
      await tester.pumpAndSettle();
      expect(find.text('estado: on'), findsOneWidget);
    });
  });

  group('HealthShellScreen — Registrar', () {
    testWidgets('callback chamado uma vez por toque', (tester) async {
      var taps = 0;
      await tester.pumpWidget(wrap(shell(onRegister: () => taps++)));

      expect(find.text('Registrar'), findsOneWidget);
      await tester.tap(find.text('Registrar'));
      await tester.pump();
      expect(taps, 1);

      await tester.tap(find.text('Registrar'));
      await tester.pump();
      expect(taps, 2);
    });

    testWidgets('sem callback o botão não dispara ação', (tester) async {
      await tester.pumpWidget(wrap(shell()));

      expect(find.text('Registrar'), findsOneWidget);
      await tester.tap(find.text('Registrar'));
      await tester.pump();
      expect(find.text('conteudo-resumo'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('HealthShellScreen — placeholders', () {
    testWidgets('placeholder só aparece se o caller o injetar', (tester) async {
      await tester.pumpWidget(
        wrap(
          HealthShellScreen(
            resumo: (_) => const HealthShellSectionPlaceholder(
              section: HealthShellSection.resumo,
            ),
            historico: (_) => const Text('h'),
            agenda: (_) => const Text('a'),
            nutricao: (_) => const Text('n'),
          ),
        ),
      );

      expect(
        find.text(HealthShellSectionPlaceholder.structuralBanner),
        findsOneWidget,
      );
      expect(find.textContaining('não é conteúdo clínico'), findsOneWidget);
    });
  });

  group('HealthShellScreen — responsividade', () {
    for (final width in [360.0, 390.0, 768.0]) {
      testWidgets('sem overflow em ${width.toInt()}px', (tester) async {
        await tester.binding.setSurfaceSize(Size(width, 800));
        addTearDown(() => tester.binding.setSurfaceSize(null));

        await tester.pumpWidget(wrap(shell(), width: width, height: 800));
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
        expect(find.byType(HealthSectionNavigation), findsOneWidget);
        expect(find.text('Resumo'), findsOneWidget);
        expect(find.text('Histórico'), findsOneWidget);
        expect(find.text('Agenda'), findsOneWidget);
        expect(find.text('Nutrição'), findsOneWidget);
        expect(find.byType(HealthModuleHeader), findsOneWidget);
      });
    }

    testWidgets('sem overflow com textScale 1.3 em 360px', (tester) async {
      await tester.binding.setSurfaceSize(const Size(360, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        wrap(shell(), width: 360, height: 800, textScale: 1.3),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text(HealthModuleHeader.title), findsOneWidget);
      expect(find.text('Resumo'), findsOneWidget);
      expect(find.text('Nutrição'), findsOneWidget);
    });
  });
}

/// Conta initState para provar montagem lazy.
class _InitProbe extends StatefulWidget {
  final HealthShellSection section;
  final String label;
  final VoidCallback onInit;

  const _InitProbe({
    super.key,
    required this.section,
    required this.label,
    required this.onInit,
  });

  @override
  State<_InitProbe> createState() => _InitProbeState();
}

class _InitProbeState extends State<_InitProbe> {
  @override
  void initState() {
    super.initState();
    widget.onInit();
  }

  @override
  Widget build(BuildContext context) {
    return Center(child: Text('area-${widget.label}'));
  }
}

/// Widget de prova para preservação de estado (sem dados clínicos).
class _ToggleProbe extends StatefulWidget {
  const _ToggleProbe({super.key});

  @override
  State<_ToggleProbe> createState() => _ToggleProbeState();
}

class _ToggleProbeState extends State<_ToggleProbe> {
  bool _on = false;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(_on ? 'estado: on' : 'estado: off'),
        TextButton(
          onPressed: () => setState(() => _on = !_on),
          child: const Text('Alternar'),
        ),
      ],
    );
  }
}
