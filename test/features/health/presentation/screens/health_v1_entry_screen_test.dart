import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:canil_gcm/features/health/presentation/screens/health_shell_screen.dart';
import 'package:canil_gcm/features/health/presentation/screens/health_v1_entry_flags.dart';
import 'package:canil_gcm/features/health/presentation/screens/health_v1_entry_screen.dart';
import 'package:canil_gcm/features/health/presentation/summary/health_summary_block_models.dart';
import 'package:canil_gcm/features/health/presentation/summary/health_summary_dashboard.dart';
import 'package:canil_gcm/features/health/presentation/summary/health_summary_dog_context_view.dart';
import 'package:canil_gcm/features/health/presentation/summary/health_summary_section_status.dart';
import 'package:canil_gcm/features/health/presentation/summary/health_summary_source.dart';
import 'package:canil_gcm/features/health/presentation/summary/health_summary_view_data.dart';
import 'package:canil_gcm/features/health/presentation/widgets/health_module_header.dart';
import 'package:canil_gcm/features/health/presentation/widgets/health_shell_section_placeholder.dart';

/// Fake source one-shot com dados mínimos (sem Firestore).
class _FixedSummarySource implements HealthSummarySource {
  _FixedSummarySource(this.payloadByDogId);
  final Map<String, HealthSummaryViewData> payloadByDogId;
  final List<String> watchCalls = [];

  factory _FixedSummarySource.single(HealthSummaryViewData payload) {
    return _FixedSummarySource({payload.dogId: payload});
  }

  @override
  Stream<HealthSummaryViewData?> watchSummary(String dogId) async* {
    watchCalls.add(dogId);
    yield payloadByDogId[dogId] ?? HealthSummaryViewData(dogId: dogId);
  }
}

void main() {
  setUpAll(() {
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  final dogContext = HealthSummaryDogContextView(
    dogId: 'dog-1',
    name: 'Bono',
    breed: 'Malinois',
    sexLabel: 'Macho',
    ageLabel: '6 anos',
  );

  Widget wrap(Widget child) {
    return MaterialApp(
      home: Scaffold(body: SizedBox(width: 400, height: 900, child: child)),
    );
  }

  test('gate 2E está habilitado por padrão (APK de teste)', () {
    expect(kHealthV1SummaryEntryEnabled, isTrue);
    expect(shouldUseHealthV1SummaryEntry(), isTrue);
  });

  test('gate false seleciona ramo legado (rollback testável)', () {
    expect(shouldUseHealthV1SummaryEntry(overrideGate: false), isFalse);
    // Com gate false, MainRoot monta DogHealthProntuarioScreen e NÃO
    // instancia HealthV1EntryScreen/source/controller.
  });

  testWidgets('monta shell + dashboard com K9 e source injetada', (
    tester,
  ) async {
    final payload = HealthSummaryViewData(
      dogId: 'dog-1',
      weight: HealthSummarySectionData.available(
        HealthSummaryWeightView(
          weightKg: 29.5,
          measuredAt: DateTime(2026, 7, 1),
        ),
      ),
    );

    final source = _FixedSummarySource.single(payload);
    await tester.pumpWidget(
      wrap(
        HealthV1EntryScreen(
          dogId: 'dog-1',
          source: source,
          dogContextOverride: dogContext,
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.byType(HealthShellScreen), findsOneWidget);
    expect(find.byType(HealthSummaryDashboard), findsOneWidget);
    expect(find.text(HealthModuleHeader.title), findsOneWidget);
    expect(find.text('Bono'), findsOneWidget);
    expect(find.textContaining('29,5'), findsWidgets);
    expect(source.watchCalls, ['dog-1']);
  });

  testWidgets('troca de seção interna Histórico usa placeholder', (
    tester,
  ) async {
    final payload = HealthSummaryViewData(dogId: 'dog-1');

    await tester.pumpWidget(
      wrap(
        HealthV1EntryScreen(
          dogId: 'dog-1',
          source: _FixedSummarySource.single(payload),
          dogContextOverride: dogContext,
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    await tester.tap(find.text('Histórico'));
    await tester.pumpAndSettle();

    expect(
      find.text(HealthShellSectionPlaceholder.structuralBanner),
      findsOneWidget,
    );
  });

  testWidgets('selectDog é chamado com dogId do entry', (tester) async {
    final payload = HealthSummaryViewData(dogId: 'dog-1');
    await tester.pumpWidget(
      wrap(
        HealthV1EntryScreen(
          dogId: 'dog-1',
          source: _FixedSummarySource.single(payload),
          dogContextOverride: dogContext,
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 30));

    final state = tester.state<HealthV1EntryScreenState>(
      find.byType(HealthV1EntryScreen),
    );
    expect(state.controllerForTest.activeDogId, 'dog-1');
  });

  testWidgets('troca dog A→B atualiza contexto e selectDog sem misturar', (
    tester,
  ) async {
    final source = _FixedSummarySource({
      'dog-A': HealthSummaryViewData(
        dogId: 'dog-A',
        weight: HealthSummarySectionData.available(
          HealthSummaryWeightView(
            weightKg: 20,
            measuredAt: DateTime(2026, 1, 1),
          ),
        ),
      ),
      'dog-B': HealthSummaryViewData(
        dogId: 'dog-B',
        weight: HealthSummarySectionData.available(
          HealthSummaryWeightView(
            weightKg: 35,
            measuredAt: DateTime(2026, 2, 1),
          ),
        ),
      ),
    });
    final ctxA = HealthSummaryDogContextView(dogId: 'dog-A', name: 'Alpha');
    final ctxB = HealthSummaryDogContextView(dogId: 'dog-B', name: 'Bravo');

    await tester.pumpWidget(
      wrap(
        HealthV1EntryScreen(
          key: const ValueKey('health-v1-dog-A'),
          dogId: 'dog-A',
          source: source,
          dogContextOverride: ctxA,
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 40));
    expect(find.text('Alpha'), findsOneWidget);
    expect(find.textContaining('20'), findsWidgets);

    // Troca de K9 com nova key (como na aba Saúde) — lifecycle limpo.
    await tester.pumpWidget(
      wrap(
        HealthV1EntryScreen(
          key: const ValueKey('health-v1-dog-B'),
          dogId: 'dog-B',
          source: source,
          dogContextOverride: ctxB,
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 40));

    expect(find.text('Bravo'), findsOneWidget);
    expect(find.text('Alpha'), findsNothing);
    expect(source.watchCalls, containsAll(['dog-A', 'dog-B']));
    final state = tester.state<HealthV1EntryScreenState>(
      find.byType(HealthV1EntryScreen),
    );
    expect(state.controllerForTest.activeDogId, 'dog-B');
  });

  testWidgets(
    'didUpdateWidget troca dogId sem ValueKey (caminho complementar)',
    (tester) async {
      final source = _FixedSummarySource({
        'dog-A': HealthSummaryViewData(dogId: 'dog-A'),
        'dog-B': HealthSummaryViewData(dogId: 'dog-B'),
      });
      final ctxA = HealthSummaryDogContextView(dogId: 'dog-A', name: 'Alpha');
      final ctxB = HealthSummaryDogContextView(dogId: 'dog-B', name: 'Bravo');

      // Mesma key → State sobrevive; didUpdateWidget deve chamar selectDog.
      await tester.pumpWidget(
        wrap(
          HealthV1EntryScreen(
            key: const ValueKey('stable-entry'),
            dogId: 'dog-A',
            source: source,
            dogContextOverride: ctxA,
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 30));

      await tester.pumpWidget(
        wrap(
          HealthV1EntryScreen(
            key: const ValueKey('stable-entry'),
            dogId: 'dog-B',
            source: source,
            dogContextOverride: ctxB,
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 30));

      expect(find.text('Bravo'), findsOneWidget);
      expect(find.text('Alpha'), findsNothing);
      final state = tester.state<HealthV1EntryScreenState>(
        find.byType(HealthV1EntryScreen),
      );
      expect(state.controllerForTest.activeDogId, 'dog-B');
      expect(source.watchCalls, containsAll(['dog-A', 'dog-B']));
    },
  );

  testWidgets('dispose do entry descarta o controller', (tester) async {
    final payload = HealthSummaryViewData(dogId: 'dog-1');
    await tester.pumpWidget(
      wrap(
        HealthV1EntryScreen(
          dogId: 'dog-1',
          source: _FixedSummarySource.single(payload),
          dogContextOverride: dogContext,
        ),
      ),
    );
    await tester.pump();
    final state = tester.state<HealthV1EntryScreenState>(
      find.byType(HealthV1EntryScreen),
    );
    final controller = state.controllerForTest;

    await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
    await tester.pump();

    expect(controller.isDisposedForTest, isTrue);
  });
}
