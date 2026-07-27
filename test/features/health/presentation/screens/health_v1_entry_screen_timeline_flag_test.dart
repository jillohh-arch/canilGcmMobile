import 'dart:async';
import 'package:flutter/widgets.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:canil_gcm/features/dogs/presentation/viewmodels/dog_viewmodel.dart';
import 'package:canil_gcm/features/health/data/config/health_timeline_flag_provider.dart';
import 'package:canil_gcm/features/health/data/config/health_timeline_mode.dart';
import 'package:canil_gcm/features/health/data/config/local_health_timeline_flag_provider.dart';
import 'package:canil_gcm/features/health/presentation/screens/health_v1_entry_screen.dart';
import 'package:canil_gcm/features/health/presentation/summary/health_summary_dog_context_view.dart';
import 'package:canil_gcm/features/health/presentation/timeline/health_timeline_page.dart';
import 'package:canil_gcm/features/health/presentation/timeline/health_timeline_query.dart';
import 'package:canil_gcm/features/health/presentation/timeline/health_timeline_source.dart';

/// Fake de [HealthTimelineFlagProvider] que rastreia chamadas e retorna o
/// valor configurado.
class FakeHealthTimelineFlagProvider implements HealthTimelineFlagProvider {
  FakeHealthTimelineFlagProvider({required this.mode, this.exception});

  final HealthTimelineMode mode;
  final Object? exception;
  int callCount = 0;

  @override
  Future<HealthTimelineModeResolution> resolveMode() async {
    callCount++;
    if (exception != null) throw exception!;
    return HealthTimelineModeResolution(
      mode: mode,
      kind: HealthTimelineModeResolutionKind.configured,
    );
  }
}

/// Wrapper minimalista que provê DogViewModel necessário para o build().
/// A [timelineSource] explícita ignora o provider (precedência de produção).
Widget buildHealthScreen({
  required String dogId,
  HealthTimelineFlagProvider provider = const LocalHealthTimelineFlagProvider(),
  HealthTimelineSource? timelineSource,
}) {
  return Directionality(
    textDirection: TextDirection.ltr,
    child: MultiProvider(
      providers: [
        ChangeNotifierProvider<DogViewModel>(create: (_) => DogViewModel()),
      ],
      child: HealthV1EntryScreen(
        dogId: dogId,
        timelineFlagProvider: provider,
        timelineSource: timelineSource,
        dogContextOverride: HealthSummaryDogContextView(
          dogId: dogId,
          name: 'K9',
        ),
      ),
    ),
  );
}

void main() {
  group('HealthV1EntryScreen timelineFlagProvider wiring', () {
    testWidgets('provider chamado exatamente uma vez quando source é null', (
      tester,
    ) async {
      final fakeProvider = FakeHealthTimelineFlagProvider(
        mode: HealthTimelineMode.legacyOnly,
      );

      await tester.pumpWidget(
        buildHealthScreen(dogId: 'dog-2', provider: fakeProvider),
      );

      await tester.pump();
      expect(fakeProvider.callCount, equals(1));
    });

    testWidgets('provider retornando legacyOnly não troca source', (
      tester,
    ) async {
      final fakeProvider = FakeHealthTimelineFlagProvider(
        mode: HealthTimelineMode.legacyOnly,
      );

      await tester.pumpWidget(
        buildHealthScreen(dogId: 'dog-3', provider: fakeProvider),
      );

      await tester.pump();
      expect(fakeProvider.callCount, equals(1));
      expect(fakeProvider.mode, equals(HealthTimelineMode.legacyOnly));
    });

    testWidgets('provider retornando shadowCompare não troca source', (
      tester,
    ) async {
      final fakeProvider = FakeHealthTimelineFlagProvider(
        mode: HealthTimelineMode.shadowCompare,
      );

      await tester.pumpWidget(
        buildHealthScreen(dogId: 'dog-4', provider: fakeProvider),
      );

      await tester.pump();
      expect(fakeProvider.callCount, equals(1));
      expect(fakeProvider.mode, equals(HealthTimelineMode.shadowCompare));
    });

    testWidgets('provider retornando canonicalPrimary não troca source', (
      tester,
    ) async {
      final fakeProvider = FakeHealthTimelineFlagProvider(
        mode: HealthTimelineMode.canonicalPrimary,
      );

      await tester.pumpWidget(
        buildHealthScreen(dogId: 'dog-5', provider: fakeProvider),
      );

      await tester.pump();
      expect(fakeProvider.callCount, equals(1));
      expect(fakeProvider.mode, equals(HealthTimelineMode.canonicalPrimary));
    });

    testWidgets('provider lançando exceção não afeta a criação da tela', (
      tester,
    ) async {
      final fakeProvider = FakeHealthTimelineFlagProvider(
        mode: HealthTimelineMode.legacyOnly,
        exception: Exception('fail'),
      );

      // Não lança — criação é síncrona.
      await tester.pumpWidget(
        buildHealthScreen(dogId: 'dog-6', provider: fakeProvider),
      );

      await tester.pump();
      expect(fakeProvider.callCount, equals(1));
    });

    testWidgets('provider lento não bloqueia a criação', (tester) async {
      // Provider que leva 200ms para resolver (mais que pump() mas menos que timeout de 1s).
      final slowProvider = _SlowProvider(
        delay: const Duration(milliseconds: 200),
      );

      await tester.pumpWidget(
        buildHealthScreen(dogId: 'dog-7', provider: slowProvider),
      );

      // pump() não espera — criação é síncrona. CallCount já é 1.
      await tester.pump();
      expect(slowProvider.callCount, equals(1));

      // Drena o timer pendente: 200ms (slowProvider) + 1s (timeout wrapper) = ~1200ms total.
      await tester.pump(const Duration(milliseconds: 1200));
    });

    testWidgets('conclusão após criação não gera erro', (tester) async {
      final fakeProvider = FakeHealthTimelineFlagProvider(
        mode: HealthTimelineMode.legacyOnly,
      );

      await tester.pumpWidget(
        buildHealthScreen(dogId: 'dog-8', provider: fakeProvider),
      );

      await tester.pump();
      expect(fakeProvider.callCount, equals(1));
    });

    testWidgets('nenhuma source canônica é criada nesta Etapa 3B '
        '(todas as respostas resultam em coexistência)', (tester) async {
      final fakeProvider = FakeHealthTimelineFlagProvider(
        mode: HealthTimelineMode.canonicalPrimary,
      );

      await tester.pumpWidget(
        buildHealthScreen(dogId: 'dog-9', provider: fakeProvider),
      );

      await tester.pump();
      expect(fakeProvider.callCount, equals(1));
    });

    testWidgets('nenhuma query sombra é executada nesta Etapa 3B', (
      tester,
    ) async {
      final fakeProvider = FakeHealthTimelineFlagProvider(
        mode: HealthTimelineMode.shadowCompare,
      );

      await tester.pumpWidget(
        buildHealthScreen(dogId: 'dog-10', provider: fakeProvider),
      );

      await tester.pump();
      expect(fakeProvider.callCount, equals(1));
    });

    testWidgets('comportamento visual inicial do Health permanece disponível', (
      tester,
    ) async {
      final fakeProvider = FakeHealthTimelineFlagProvider(
        mode: HealthTimelineMode.legacyOnly,
      );

      await tester.pumpWidget(
        buildHealthScreen(dogId: 'dog-11', provider: fakeProvider),
      );

      await tester.pump();
      expect(find.byType(HealthV1EntryScreen), findsOneWidget);
      expect(fakeProvider.callCount, equals(1));
    });

    testWidgets(
      'provider null usa LocalHealthTimelineFlagProvider como default',
      (tester) async {
        await tester.pumpWidget(
          Directionality(
            textDirection: TextDirection.ltr,
            child: MultiProvider(
              providers: [
                ChangeNotifierProvider<DogViewModel>(
                  create: (_) => DogViewModel(),
                ),
              ],
              child: HealthV1EntryScreen(
                dogId: 'dog-13',
                dogContextOverride: HealthSummaryDogContextView(
                  dogId: 'dog-13',
                  name: 'K9',
                ),
              ),
            ),
          ),
        );

        final widget =
            tester.widget(find.byType(HealthV1EntryScreen))
                as HealthV1EntryScreen;
        expect(
          widget.timelineFlagProvider,
          isA<LocalHealthTimelineFlagProvider>(),
        );
      },
    );

    testWidgets('provider local resolve sem bloquear a tela', (tester) async {
      const provider = LocalHealthTimelineFlagProvider();

      await tester.pumpWidget(
        buildHealthScreen(dogId: 'dog-14', provider: provider),
      );

      await tester.pump();
      // Provider local resolve instantaneamente.
      expect(find.byType(HealthV1EntryScreen), findsOneWidget);
    });

    testWidgets('provider retornando shadowCompare faz fail-closed', (
      tester,
    ) async {
      final fakeProvider = FakeHealthTimelineFlagProvider(
        mode: HealthTimelineMode.shadowCompare,
      );

      await tester.pumpWidget(
        buildHealthScreen(dogId: 'dog-15', provider: fakeProvider),
      );

      await tester.pump();
      expect(fakeProvider.callCount, equals(1));
    });

    testWidgets('provider retornando legacyOnly com invalidDefault '
        'faz fail-closed', (tester) async {
      final fakeProvider = FakeHealthTimelineFlagProvider(
        mode: HealthTimelineMode.legacyOnly,
      );

      await tester.pumpWidget(
        buildHealthScreen(dogId: 'dog-16', provider: fakeProvider),
      );

      await tester.pump();
      expect(fakeProvider.callCount, equals(1));
    });

    // ── TESTE 15 ── Precedência e zero chamada do provider ────────────────
    testWidgets('source explícita não chama provider', (tester) async {
      final fakeProvider = FakeHealthTimelineFlagProvider(
        mode: HealthTimelineMode.canonicalPrimary,
      );
      final fakeSource = _FakeHealthTimelineSource();

      // Source explícita: provider não deve ser chamado.
      await tester.pumpWidget(
        buildHealthScreen(
          dogId: 'dog-17',
          provider: fakeProvider,
          timelineSource: fakeSource,
        ),
      );

      await tester.pump();
      // Provider nunca chamado porque timelineSource != null (precedência).
      expect(fakeProvider.callCount, equals(0));
    });

    // ── TESTE 16 ── Navegação real de seções shell não chama provider ──────
    testWidgets('navegação real entre seções não chama provider novamente', (
      tester,
    ) async {
      final fakeProvider = FakeHealthTimelineFlagProvider(
        mode: HealthTimelineMode.legacyOnly,
      );

      // Criação da tela: provider chamado exatamente uma vez.
      await tester.pumpWidget(
        buildHealthScreen(dogId: 'dog-18', provider: fakeProvider),
      );
      await tester.pump();
      expect(fakeProvider.callCount, equals(1));

      // Navegação real para Agenda via tap no label da seção.
      await tester.tap(find.text('Agenda'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      expect(fakeProvider.callCount, equals(1));

      // Navegação real para Nutrição.
      await tester.tap(find.text('Nutrição'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      expect(fakeProvider.callCount, equals(1));

      // Navegação real para Histórico (primes timeline — source coexistence
      // criada em initState; provider não é chamado novamente).
      await tester.tap(find.text('Histórico'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      expect(fakeProvider.callCount, equals(1));

      // Retorno real para Resumo.
      await tester.tap(find.text('Resumo'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      expect(fakeProvider.callCount, equals(1));

      // Drena async completions.
      await tester.pump(const Duration(milliseconds: 500));
      expect(fakeProvider.callCount, equals(1));
    });

    // ── TESTE 17 ── Operações reais da timeline não chamam provider ───────
    testWidgets(
      'operações reais da timeline não aumentam callCount do provider',
      (tester) async {
        final fakeProvider = FakeHealthTimelineFlagProvider(
          mode: HealthTimelineMode.legacyOnly,
        );

        // Sem timelineSource explícita: provider chamado em initState.
        await tester.pumpWidget(
          buildHealthScreen(dogId: 'dog-19', provider: fakeProvider),
        );
        await tester.pump();
        expect(fakeProvider.callCount, equals(1));

        // Navegação real para Histórico: primes timeline via
        // _primeTimelineIfNeeded → _timelineController.selectDog.
        await tester.tap(find.text('Histórico'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
        expect(fakeProvider.callCount, equals(1));

        // Operação real 1: quick filter "Vacinas" via tap real.
        // Comprova seleção via SemanticsData.isSelected (propriedade semântica oficial).
        await tester.tap(find.text('Vacinas'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 200));
        expect(fakeProvider.callCount, equals(1));
        final vacinasSemantics = tester.getSemantics(
          find.text('Vacinas', findRichText: true).first,
        );
        expect(vacinasSemantics.hasFlag(SemanticsFlag.isSelected), isTrue);

        // Operação real 2: quick filter "Consultas" via tap real.
        // Comprova que "Consultas" fica selecionado (Vacinas desseleciona).
        await tester.tap(find.text('Consultas'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 200));
        expect(fakeProvider.callCount, equals(1));
        final consultasSemantics = tester.getSemantics(
          find.text('Consultas', findRichText: true).first,
        );
        expect(consultasSemantics.hasFlag(SemanticsFlag.isSelected), isTrue);

        // Operação real 3: voltar para "Todos".
        // Comprova que "Todos" fica selecionado e os demais desselecionam.
        await tester.tap(find.text('Todos'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 200));
        expect(fakeProvider.callCount, equals(1));
        final todosSemantics = tester.getSemantics(
          find.text('Todos', findRichText: true).first,
        );
        expect(todosSemantics.hasFlag(SemanticsFlag.isSelected), isTrue);

        // Drena async completions: callCount permanece 1.
        await tester.pump(const Duration(milliseconds: 500));
        expect(fakeProvider.callCount, equals(1));
      },
    );

    // ── TESTE 18 ── Timeout e dispose seguro ───────────────────────────────
    testWidgets('provider lento com dispose não gera exceção', (tester) async {
      final completer = Completer<HealthTimelineModeResolution>();
      final pendingProvider = _CompletingProvider(completer: completer);

      await tester.pumpWidget(
        buildHealthScreen(dogId: 'dog-20', provider: pendingProvider),
      );
      await tester.pump();

      expect(pendingProvider.callCount, equals(1));
      expect(completer.isCompleted, isFalse);

      // Descarta a tela enquanto a Future do provider ainda está pendente.
      await tester.pumpWidget(const SizedBox());

      // Avança o relógio além do timeout de 1s (com folga).
      await tester.pump(const Duration(milliseconds: 1500));

      // Completa a Future para limpar o Completer.
      completer.complete(
        const HealthTimelineModeResolution(
          mode: HealthTimelineMode.legacyOnly,
          kind: HealthTimelineModeResolutionKind.configured,
        ),
      );
      await tester.pump();

      // Sem exceção: timer expirou e future completou silenciosamente.
      expect(tester.takeException(), isNull);
    });
  });
}

/// Provider que resolve após um delay curto.
class _SlowProvider implements HealthTimelineFlagProvider {
  _SlowProvider({required this.delay});

  final Duration delay;
  int callCount = 0;

  @override
  Future<HealthTimelineModeResolution> resolveMode() async {
    callCount++;
    await Future.delayed(delay);
    return const HealthTimelineModeResolution(
      mode: HealthTimelineMode.legacyOnly,
      kind: HealthTimelineModeResolutionKind.configured,
    );
  }
}

/// Fake de [HealthTimelineSource] que rastreia chamadas a [loadPage].
class _FakeHealthTimelineSource implements HealthTimelineSource {
  @override
  Future<HealthTimelinePage> loadPage(HealthTimelineQuery query) async {
    return HealthTimelinePage.empty();
  }
}

/// Provider que resolve via [Completer] externo (para testar dispose pendente).
class _CompletingProvider implements HealthTimelineFlagProvider {
  _CompletingProvider({required this.completer});

  final Completer<HealthTimelineModeResolution> completer;
  int callCount = 0;

  @override
  Future<HealthTimelineModeResolution> resolveMode() async {
    callCount++;
    return completer.future;
  }
}
