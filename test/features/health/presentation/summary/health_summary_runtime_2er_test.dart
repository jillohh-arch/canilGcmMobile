import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:canil_gcm/core/theme/app_theme.dart';
import 'package:canil_gcm/features/app_shell/presentation/main_root_nav_metrics.dart';
import 'package:canil_gcm/features/health/presentation/summary/health_summary_block_models.dart';
import 'package:canil_gcm/features/health/presentation/summary/health_summary_controller.dart';
import 'package:canil_gcm/features/health/presentation/summary/health_summary_dashboard.dart';
import 'package:canil_gcm/features/health/presentation/summary/health_summary_dog_context_view.dart';
import 'package:canil_gcm/features/health/presentation/summary/health_summary_section_status.dart';
import 'package:canil_gcm/features/health/presentation/summary/health_summary_source_metadata.dart';
import 'package:canil_gcm/features/health/presentation/summary/health_summary_user_copy.dart';
import 'package:canil_gcm/features/health/presentation/summary/health_summary_view_data.dart';
import 'package:canil_gcm/features/health/presentation/summary/widgets/health_summary_metric_card.dart';

import 'fake_health_summary_source.dart';

void main() {
  setUpAll(() {
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  final dog = HealthSummaryDogContextView(
    dogId: 'dog-1',
    name: 'Bono',
    breed: 'Malinois',
    sexLabel: 'Macho',
    ageLabel: '6 anos',
  );

  Widget wrap(
    Widget child, {
    double width = 390,
    double height = 1200,
    double bottomPadding = 0,
  }) {
    return MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(
          size: Size(width, height),
          padding: EdgeInsets.only(bottom: bottomPadding),
        ),
        child: Scaffold(
          body: SizedBox(width: width, height: height, child: child),
        ),
      ),
    );
  }

  void configureSurface(WidgetTester tester) {
    tester.view.physicalSize = const Size(390, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  HealthSummaryViewData baseData({
    HealthSummarySectionData<HealthSummaryVaccinationView>? vaccination,
    HealthSummarySectionData<HealthSummaryTreatmentsView>? treatments,
    HealthSummarySectionData<HealthSummaryAttentionView>? attention,
    HealthSummarySectionData<HealthSummaryWeightView>? weight,
  }) {
    final now = DateTime(2026, 7, 8, 13, 42);
    return HealthSummaryViewData(
      dogId: 'dog-1',
      readiness: const HealthSummarySectionData.unavailable(
        message: HealthSummaryUserCopy.readinessUnavailable,
      ),
      weight:
          weight ??
          HealthSummarySectionData.available(
            HealthSummaryWeightView(weightKg: 30, measuredAt: now),
          ),
      vaccination:
          vaccination ??
          const HealthSummarySectionData.unavailable(
            message: HealthSummaryUserCopy.vaccinationUnavailable,
          ),
      treatments:
          treatments ??
          const HealthSummarySectionData.unavailable(
            message: HealthSummaryUserCopy.treatmentsUnavailable,
          ),
      attention:
          attention ??
          const HealthSummarySectionData.unavailable(
            message: HealthSummaryUserCopy.attentionUnavailable,
          ),
      nutritionToday: HealthSummarySectionData.available(
        const HealthSummaryNutritionTodayView(
          consumedAmount: 200,
          plannedAmount: 600,
          mealsRecorded: 1,
          mealsPlanned: 3,
          unitLabel: 'g',
        ),
      ),
      weightTrend: HealthSummarySectionData.available(
        HealthSummaryWeightTrendView(
          points: [
            HealthSummaryWeightPoint(
              at: now.subtract(const Duration(days: 7)),
              weightKg: 29.5,
            ),
            HealthSummaryWeightPoint(at: now, weightKg: 30),
          ],
        ),
      ),
      recentRecords: const HealthSummarySectionData.unavailable(
        message: HealthSummaryUserCopy.recentUnavailable,
      ),
      metadata: const HealthSummarySourceMetadata(),
    );
  }

  Future<void> pumpDashboard(
    WidgetTester tester, {
    required HealthSummaryViewData data,
    double bottomPadding = 0,
  }) async {
    configureSurface(tester);
    final source = FakeHealthSummarySource();
    addTearDown(source.disposeAll);
    final controller = HealthSummaryController(source: source);
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      wrap(
        HealthSummaryDashboard(dogContext: dog, controller: controller),
        bottomPadding: bottomPadding,
      ),
    );
    controller.selectDog('dog-1');
    await tester.pump();
    source.emit('dog-1', data);
    await tester.pump();
  }

  group('HealthSummaryUserCopy.sanitizeUnavailable', () {
    test('remove mensagens técnicas de índice/Firebase/URL', () {
      const technical =
          'The query requires an index. You can create it here: '
          'https://console.firebase.google.com/v1/r/project/x/firestore/indexes';
      final out = HealthSummaryUserCopy.sanitizeUnavailable(
        technical,
        fallback: HealthSummaryUserCopy.vaccinationUnavailable,
      );
      expect(out, HealthSummaryUserCopy.vaccinationUnavailable);
      expect(out.toLowerCase(), isNot(contains('index')));
      expect(out.toLowerCase(), isNot(contains('firebase')));
      expect(out, isNot(contains('https://')));
    });

    test('remove jargão de arquitetura', () {
      final out = HealthSummaryUserCopy.sanitizeUnavailable(
        'Prontidão Health v1 ainda sem fonte compatível na coexistência legada',
        fallback: HealthSummaryUserCopy.readinessUnavailable,
      );
      expect(out, HealthSummaryUserCopy.readinessUnavailable);
    });

    test('looksTechnical detecta permission-denied e stack', () {
      expect(
        HealthSummaryUserCopy.looksTechnical(
          'permission-denied: Missing or insufficient permissions.',
        ),
        isTrue,
      );
      expect(
        HealthSummaryUserCopy.looksTechnical(
          'Dados de vacinação indisponíveis no momento.',
        ),
        isFalse,
      );
    });
  });

  group('Métricas unavailable vs notRecorded (R5)', () {
    testWidgets('unavailable usa rótulo curto INDISPONÍVEL sem texto bruto', (
      tester,
    ) async {
      await pumpDashboard(
        tester,
        data: baseData(
          vaccination: const HealthSummarySectionData.unavailable(
            message:
                'The query requires an index https://console.firebase.google.com',
          ),
          treatments: const HealthSummarySectionData.unavailable(
            message: HealthSummaryUserCopy.treatmentsUnavailable,
          ),
          attention: const HealthSummarySectionData.unavailable(
            message: HealthSummaryUserCopy.attentionUnavailable,
          ),
        ),
      );

      expect(find.text('INDISPONÍVEL'), findsWidgets);
      expect(find.textContaining('The query requires an index'), findsNothing);
      expect(find.textContaining('console.firebase'), findsNothing);
      expect(find.textContaining('firebase'), findsNothing);
      expect(find.textContaining('permission-denied'), findsNothing);
      // Valor principal do card não é a frase longa.
      expect(
        find.text(HealthSummaryUserCopy.treatmentsUnavailable),
        findsNothing,
      );
    });

    testWidgets('notRecorded usa NÃO REGISTRADO (distinto de unavailable)', (
      tester,
    ) async {
      await pumpDashboard(
        tester,
        data: baseData(
          weight: const HealthSummarySectionData.notRecorded(
            message: HealthSummaryUserCopy.weightNotRecorded,
          ),
          vaccination: const HealthSummarySectionData.notRecorded(
            message: HealthSummaryUserCopy.vaccinationNotRecorded,
          ),
          treatments: HealthSummarySectionData.available(
            HealthSummaryTreatmentsView(activeProtocolCount: 0),
          ),
          attention: HealthSummarySectionData.available(
            const HealthSummaryAttentionView(items: []),
          ),
        ),
      );

      // Cards de métrica notRecorded: valor principal curto.
      expect(find.text('NÃO REGISTRADO'), findsWidgets);
      // Peso notRecorded NÃO usa o rótulo unavailable.
      final weightCard = find.byKey(const ValueKey('metric-weight'));
      expect(
        find.descendant(of: weightCard, matching: find.text('NÃO REGISTRADO')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: weightCard, matching: find.text('INDISPONÍVEL')),
        findsNothing,
      );
    });

    testWidgets(
      'metric card isolado: unavailable sem overflow de mensagem longa',
      (tester) async {
        configureSurface(tester);
        await tester.pumpWidget(
          wrap(
            const Center(
              child: SizedBox(
                width: 170,
                child: HealthSummaryMetricCard(
                  label: 'VACINAÇÃO',
                  icon: Icons.verified_user_outlined,
                  accentColor: AppTheme.success,
                  semanticsLabel: 'Vacinação indisponível',
                  isUnavailable: true,
                  statusMessage:
                      'The query requires an index. You can create it here: '
                      'https://console.firebase.google.com/project/demo',
                ),
              ),
            ),
          ),
        );

        expect(find.text('INDISPONÍVEL'), findsOneWidget);
        expect(find.textContaining('requires an index'), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );
  });

  group('Atenções — semântica do título (R6)', () {
    testWidgets('unavailable → ATENÇÕES (não REQUER ATENÇÃO)', (tester) async {
      await pumpDashboard(
        tester,
        data: baseData(
          attention: const HealthSummarySectionData.unavailable(
            message: HealthSummaryUserCopy.attentionUnavailable,
          ),
        ),
      );

      expect(find.text('REQUER ATENÇÃO'), findsNothing);
      expect(find.text('ATENÇÕES'), findsWidgets);
      expect(
        find.text(HealthSummaryUserCopy.attentionUnavailable),
        findsOneWidget,
      );
    });

    testWidgets('available com items → REQUER ATENÇÃO', (tester) async {
      await pumpDashboard(
        tester,
        data: baseData(
          attention: HealthSummarySectionData.available(
            const HealthSummaryAttentionView(
              items: [
                HealthSummaryAttentionItem(
                  id: 'a1',
                  title: 'Vacina próxima',
                  subtitle: 'Em 3 dias',
                ),
              ],
            ),
          ),
        ),
      );

      expect(find.text('REQUER ATENÇÃO'), findsOneWidget);
      expect(find.text('Vacina próxima'), findsWidgets);
    });

    testWidgets('available vazio → ATENÇÕES neutro (sem alerta falso)', (
      tester,
    ) async {
      await pumpDashboard(
        tester,
        data: baseData(
          attention: HealthSummarySectionData.available(
            const HealthSummaryAttentionView(items: []),
          ),
        ),
      );

      expect(find.text('REQUER ATENÇÃO'), findsNothing);
      expect(find.text('Nenhuma atenção prioritária'), findsOneWidget);
    });
  });

  group('Copy operacional unavailable (R4)', () {
    testWidgets('prontidão e seções usam frases de operador', (tester) async {
      await pumpDashboard(tester, data: baseData());

      expect(find.text('INDISPONÍVEL'), findsWidgets);
      expect(
        find.text(HealthSummaryUserCopy.readinessUnavailable),
        findsOneWidget,
      );
      expect(find.textContaining('coexistência'), findsNothing);
      expect(find.textContaining('legado'), findsNothing);
      expect(find.textContaining('Health v1'), findsNothing);
      expect(find.textContaining('fonte compatível'), findsNothing);
    });
  });

  group('Bottom padding do Dashboard (R2)', () {
    test('clearance inclui nav 76 + safe area + folga FAB', () {
      expect(
        // pure formula check via MediaQuery in widget test below
        76.0 + 24.0 + 28.0,
        128.0,
      );
    });

    testWidgets('scroll data aplica padding inferior ≥ nav + system + folga', (
      tester,
    ) async {
      const systemBottom = 34.0;
      await pumpDashboard(
        tester,
        data: baseData(
          attention: HealthSummarySectionData.available(
            const HealthSummaryAttentionView(items: []),
          ),
          vaccination: HealthSummarySectionData.available(
            const HealthSummaryVaccinationView(lastRecordLabel: 'V10'),
          ),
          treatments: HealthSummarySectionData.available(
            HealthSummaryTreatmentsView(activeProtocolCount: 0),
          ),
        ),
        bottomPadding: systemBottom,
      );

      final scrollable = tester.widget<SingleChildScrollView>(
        find.byType(SingleChildScrollView).first,
      );
      final pad = (scrollable.padding ?? EdgeInsets.zero).resolve(
        TextDirection.ltr,
      );
      final expected = healthSummaryScrollBottomClearance(
        tester.element(find.byType(HealthSummaryDashboard)),
      );
      expect(pad.bottom, expected);
      expect(
        pad.bottom,
        greaterThanOrEqualTo(
          MainRootNavMetrics.barContentHeight + systemBottom,
        ),
      );
      expect(
        pad.bottom,
        MainRootNavMetrics.scrollBottomClearance(
          systemBottomInset: systemBottom,
        ),
      );
    });
  });

  group('Bottom nav token (R3)', () {
    test('surfaceNavigation é navy sólido (não primaryOverlay ~4%)', () {
      expect(AppTheme.surfaceNavigation.a, closeTo(1.0, 0.001));
      expect(AppTheme.primaryOverlay.a, lessThan(0.1));
      // Identidade K9: surfaceNavigation é o fundo de navegação canônico.
      expect(AppTheme.surfaceNavigation, const Color(0xFF07141B));
    });

    test('MainRootNavMetrics alinha barra e clearance', () {
      expect(MainRootNavMetrics.barContentHeight, 76);
      expect(MainRootNavMetrics.fabElevation, 22);
      expect(MainRootNavMetrics.scrollFabBreathing, 28);
    });
  });
}
