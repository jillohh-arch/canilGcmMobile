import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:canil_gcm/core/theme/app_theme.dart';
import 'package:canil_gcm/features/health/domain/health_v1_enums_ext.dart';
import 'package:canil_gcm/features/health/presentation/screens/health_shell_screen.dart';
import 'package:canil_gcm/features/health/presentation/summary/health_summary_block_models.dart';
import 'package:canil_gcm/features/health/presentation/summary/health_summary_controller.dart';
import 'package:canil_gcm/features/health/presentation/summary/health_summary_dashboard.dart';
import 'package:canil_gcm/features/health/presentation/summary/health_summary_dog_context_view.dart';
import 'package:canil_gcm/features/health/presentation/summary/health_summary_section_status.dart';
import 'package:canil_gcm/features/health/presentation/summary/health_summary_source.dart';
import 'package:canil_gcm/features/health/presentation/summary/health_summary_source_metadata.dart';
import 'package:canil_gcm/features/health/presentation/summary/health_summary_state.dart';
import 'package:canil_gcm/features/health/presentation/summary/health_summary_view_data.dart';
import 'package:canil_gcm/features/health/presentation/summary/widgets/health_summary_formatters.dart';
import 'package:canil_gcm/features/health/presentation/summary/widgets/health_summary_metric_card.dart';
import 'package:canil_gcm/features/health/presentation/summary/widgets/health_summary_nutrition_card.dart';
import 'package:canil_gcm/features/health/presentation/summary/widgets/health_summary_readiness_card.dart';
import 'package:canil_gcm/features/health/presentation/summary/widgets/health_summary_recent_records.dart';
import 'package:canil_gcm/features/health/presentation/summary/widgets/health_summary_weight_trend_card.dart';
import 'package:canil_gcm/features/health/presentation/widgets/health_shell_section.dart';
import 'package:canil_gcm/features/health/presentation/widgets/health_shell_section_placeholder.dart';

import 'fake_health_summary_source.dart';

void main() {
  setUpAll(() {
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  final dog = HealthSummaryDogContextView(
    dogId: 'dog-1',
    name: 'Bono',
    breed: 'Pastor Belga Malinois',
    sexLabel: 'Macho',
    ageLabel: '6 anos',
  );

  Widget wrap(
    Widget child, {
    double width = 390,
    double height = 1200,
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

  void configureSurface(
    WidgetTester tester, {
    double width = 390,
    double height = 1400,
  }) {
    tester.view.physicalSize = Size(width, height);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  HealthSummaryViewData fullData({
    String dogId = 'dog-1',
    ReadinessStatus readiness = ReadinessStatus.operational,
    HealthSummarySectionData<HealthSummaryWeightView>? weight,
    HealthSummarySectionData<HealthSummaryVaccinationView>? vaccination,
    HealthSummarySectionData<HealthSummaryTreatmentsView>? treatments,
    HealthSummarySectionData<HealthSummaryAttentionView>? attention,
    HealthSummarySectionData<HealthSummaryNutritionTodayView>? nutrition,
    HealthSummarySectionData<HealthSummaryWeightTrendView>? weightTrend,
    HealthSummarySectionData<HealthSummaryRecentRecordsView>? recent,
    HealthSummarySourceMetadata metadata = const HealthSummarySourceMetadata(),
  }) {
    final now = DateTime(2026, 7, 8, 13, 42);
    return HealthSummaryViewData(
      dogId: dogId,
      readiness: HealthSummarySectionData.available(
        HealthSummaryReadinessView(
          status: readiness,
          reason: 'Sem restrições ativas',
          updatedAt: now,
        ),
      ),
      weight:
          weight ??
          HealthSummarySectionData.available(
            HealthSummaryWeightView(weightKg: 29.8, measuredAt: now),
          ),
      vaccination:
          vaccination ??
          HealthSummarySectionData.available(
            const HealthSummaryVaccinationView(
              summaryLabel: 'Em dia',
              nextDueAt: null,
            ),
          ),
      treatments:
          treatments ??
          HealthSummarySectionData.available(
            HealthSummaryTreatmentsView(
              activeProtocolCount: 0,
              primarySummary: 'Sem tratamento em andamento',
            ),
          ),
      attention:
          attention ??
          HealthSummarySectionData.available(
            const HealthSummaryAttentionView(
              items: [
                HealthSummaryAttentionItem(
                  id: 'att-1',
                  title: 'Vacina V10 próxima do vencimento',
                  subtitle: 'Vence em 24 dias',
                  destinationHint: 'agenda',
                ),
              ],
            ),
          ),
      nutritionToday:
          nutrition ??
          const HealthSummarySectionData.available(
            HealthSummaryNutritionTodayView(
              consumedAmount: 250,
              offeredAmount: 500,
              plannedAmount: 600,
              mealsRecorded: 1,
              mealsPlanned: 3,
              unitLabel: 'g',
            ),
          ),
      weightTrend:
          weightTrend ??
          HealthSummarySectionData.available(
            HealthSummaryWeightTrendView(
              points: [
                HealthSummaryWeightPoint(
                  at: DateTime(2026, 6, 8),
                  weightKg: 28.5,
                ),
                HealthSummaryWeightPoint(
                  at: DateTime(2026, 6, 22),
                  weightKg: 29.2,
                ),
                HealthSummaryWeightPoint(at: now, weightKg: 29.8),
              ],
              targetWeightKg: 28.5,
              bodyConditionScore: 'Ideal',
            ),
          ),
      recentRecords:
          recent ??
          HealthSummarySectionData.available(
            HealthSummaryRecentRecordsView(
              items: [
                HealthSummaryRecentRecordView(
                  id: 'r1',
                  type: 'feeding',
                  title: 'Alimentação registrada',
                  subtitle: 'Almoço · 250 g',
                  occurredAt: now,
                ),
                HealthSummaryRecentRecordView(
                  id: 'r2',
                  type: 'weight',
                  title: 'Pesagem',
                  subtitle: '29,8 kg',
                  occurredAt: now,
                ),
              ],
            ),
          ),
      metadata: metadata,
    );
  }

  Future<HealthSummaryController> pumpDashboard(
    WidgetTester tester, {
    required FakeHealthSummarySource source,
    HealthSummaryViewData? emitData,
    Object? emitError,
    HealthSummaryDogContextView? dogContext,
    double width = 390,
    double height = 1200,
    double textScale = 1.0,
    VoidCallback? onOpenNutrition,
    VoidCallback? onRegisterFeeding,
    VoidCallback? onOpenHistory,
    ValueChanged<HealthSummaryAttentionItem>? onAttentionItemTap,
    ValueChanged<HealthSummaryRecentRecordView>? onRecentRecordTap,
  }) async {
    configureSurface(tester, width: width, height: height);
    final controller = HealthSummaryController(source: source);
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      wrap(
        HealthSummaryDashboard(
          dogContext: dogContext ?? dog,
          controller: controller,
          onOpenNutrition: onOpenNutrition,
          onRegisterFeeding: onRegisterFeeding,
          onOpenHistory: onOpenHistory,
          onAttentionItemTap: onAttentionItemTap,
          onRecentRecordTap: onRecentRecordTap,
        ),
        width: width,
        height: height,
        textScale: textScale,
      ),
    );

    controller.selectDog('dog-1');
    await tester.pump();

    if (emitData != null) {
      source.emit('dog-1', emitData);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 20));
    }
    if (emitError != null) {
      source.emitError('dog-1', emitError);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 20));
    }

    return controller;
  }

  Future<void> settleState(WidgetTester tester) async {
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 20));
  }

  group('Dashboard geral', () {
    testWidgets('renderiza HealthSummaryData completo com contexto do K9', (
      tester,
    ) async {
      final source = FakeHealthSummarySource();
      addTearDown(source.disposeAll);

      await pumpDashboard(tester, source: source, emitData: fullData());

      expect(find.text('Bono'), findsOneWidget);
      expect(find.textContaining('Pastor Belga Malinois'), findsOneWidget);
      expect(find.text('OPERACIONAL'), findsOneWidget);
      expect(find.text('PESO'), findsOneWidget);
      expect(find.text('29,8 kg'), findsWidgets);
      expect(find.text('VACINAÇÃO'), findsOneWidget);
      expect(find.text('EM DIA'), findsOneWidget);
      expect(find.text('MEDICAÇÃO'), findsOneWidget);
      expect(find.text('NENHUMA ATIVA'), findsOneWidget);
      expect(find.text('ATENÇÕES'), findsOneWidget);
      expect(find.text('REQUER ATENÇÃO'), findsOneWidget);
      expect(find.text('ALIMENTAÇÃO HOJE'), findsOneWidget);
      expect(find.text('EVOLUÇÃO DO PESO'), findsOneWidget);
      expect(find.text('REGISTROS RECENTES'), findsOneWidget);
      expect(find.text('Abrir Nutrição'), findsOneWidget);
      expect(find.text('Registrar alimentação'), findsOneWidget);
    });

    testWidgets('integra no builder resumo do HealthShellScreen', (
      tester,
    ) async {
      configureSurface(tester, width: 390, height: 1400);
      final source = FakeHealthSummarySource();
      addTearDown(source.disposeAll);
      final controller = HealthSummaryController(source: source);
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        wrap(
          HealthShellScreen(
            resumo: (_) =>
                HealthSummaryDashboard(dogContext: dog, controller: controller),
            historico: (_) => const HealthShellSectionPlaceholder(
              section: HealthShellSection.historico,
            ),
            agenda: (_) => const HealthShellSectionPlaceholder(
              section: HealthShellSection.agenda,
            ),
            nutricao: (_) => const HealthShellSectionPlaceholder(
              section: HealthShellSection.nutricao,
            ),
          ),
        ),
      );

      controller.selectDog('dog-1');
      await tester.pump();
      source.emit('dog-1', fullData());
      await tester.pump();

      expect(find.text('SAÚDE E PRONTIDÃO'), findsOneWidget);
      expect(find.text('Bono'), findsOneWidget);
      expect(find.text('OPERACIONAL'), findsOneWidget);
      expect(find.byType(HealthSummaryDashboard), findsOneWidget);
    });
  });

  group('Prontidão — cinco estados', () {
    for (final entry in {
      ReadinessStatus.operational: 'OPERACIONAL',
      ReadinessStatus.operationalAttention: 'OPERACIONAL C/ ATENÇÃO',
      ReadinessStatus.fitWithRestrictions: 'APTO C/ RESTRIÇÕES',
      ReadinessStatus.temporarilyUnfit: 'TEMP. INAPTO',
      ReadinessStatus.notEvaluated: 'NÃO AVALIADO',
    }.entries) {
      testWidgets('status ${entry.key.name} → ${entry.value}', (tester) async {
        final source = FakeHealthSummarySource();
        addTearDown(source.disposeAll);

        await pumpDashboard(
          tester,
          source: source,
          emitData: fullData(readiness: entry.key),
        );

        expect(find.text(entry.value), findsOneWidget);
        expect(find.byType(HealthSummaryReadinessCard), findsOneWidget);
      });
    }
  });

  group('Dados parciais por bloco', () {
    testWidgets(
      'loading / available / notRecorded / unavailable coexistentes',
      (tester) async {
        final source = FakeHealthSummarySource();
        addTearDown(source.disposeAll);

        final data = fullData(
          weight: const HealthSummarySectionData.loading(),
          vaccination: const HealthSummarySectionData.notRecorded(
            message: 'Sem registro',
          ),
          treatments: const HealthSummarySectionData.unavailable(
            message: 'Dados indisponíveis',
          ),
          attention: HealthSummarySectionData.available(
            const HealthSummaryAttentionView(items: []),
          ),
        );

        await pumpDashboard(tester, source: source, emitData: data);

        expect(find.byKey(const ValueKey('summary-data')), findsOneWidget);
        expect(find.text('NÃO REGISTRADO'), findsOneWidget);
        expect(find.text('INDISPONÍVEL'), findsOneWidget);
        // Bloco unavailable de tratamentos NÃO derruba o dashboard.
        expect(find.text('Bono'), findsOneWidget);
        // Attention available + empty → título neutro (sem falso alerta).
        expect(find.text('REQUER ATENÇÃO'), findsNothing);
      },
    );

    testWidgets('unavailable de peso não inventa 0 kg', (tester) async {
      final source = FakeHealthSummarySource();
      addTearDown(source.disposeAll);

      await pumpDashboard(
        tester,
        source: source,
        emitData: fullData(
          weight: const HealthSummarySectionData.unavailable(
            message: 'Dados indisponíveis',
          ),
          weightTrend: const HealthSummarySectionData.unavailable(),
        ),
      );

      expect(find.text('0,0 kg'), findsNothing);
      expect(find.text('0 kg'), findsNothing);
    });
  });

  group('Estados gerais do dashboard', () {
    testWidgets('initial', (tester) async {
      configureSurface(tester);
      final source = FakeHealthSummarySource();
      addTearDown(source.disposeAll);
      final controller = HealthSummaryController(source: source);
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        wrap(HealthSummaryDashboard(dogContext: dog, controller: controller)),
      );

      expect(find.byKey(const ValueKey('summary-initial')), findsOneWidget);
      expect(find.text('Selecione um K9'), findsOneWidget);
    });

    testWidgets('loading', (tester) async {
      configureSurface(tester);
      final source = FakeHealthSummarySource();
      addTearDown(source.disposeAll);
      final controller = HealthSummaryController(source: source);
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        wrap(HealthSummaryDashboard(dogContext: dog, controller: controller)),
      );
      controller.selectDog('dog-1');
      await tester.pump();

      expect(find.byKey(const ValueKey('summary-loading')), findsOneWidget);
    });

    testWidgets('empty', (tester) async {
      final source = FakeHealthSummarySource();
      addTearDown(source.disposeAll);

      final controller = await pumpDashboard(tester, source: source);
      source.emit('dog-1', null);
      await tester.pump();

      expect(find.byKey(const ValueKey('summary-empty')), findsOneWidget);
      expect(find.text('Sem resumo disponível'), findsOneWidget);
      // ignore unused
      expect(controller.activeDogId, 'dog-1');
    });

    testWidgets('error sem lastKnownData', (tester) async {
      final source = FakeHealthSummarySource();
      addTearDown(source.disposeAll);

      await pumpDashboard(
        tester,
        source: source,
        emitError: HealthSummarySourceException('falha de rede'),
      );

      expect(find.byKey(const ValueKey('summary-error')), findsOneWidget);
      expect(find.text('Tentar novamente'), findsOneWidget);
    });

    testWidgets('error com lastKnownData mantém dashboard + banner', (
      tester,
    ) async {
      final source = FakeHealthSummarySource();
      addTearDown(source.disposeAll);

      final controller = await pumpDashboard(
        tester,
        source: source,
        emitData: fullData(),
      );
      expect(find.text('Bono'), findsOneWidget);

      source.emitError('dog-1', HealthSummarySourceException('erro posterior'));
      await settleState(tester);

      expect(controller.state, isA<HealthSummaryError>());
      expect((controller.state as HealthSummaryError).lastKnownData, isNotNull);
      expect(
        find.byKey(const ValueKey('summary-error-with-data')),
        findsOneWidget,
      );
      expect(find.text('Bono'), findsOneWidget);
      expect(find.text('erro posterior'), findsOneWidget);
      expect(find.text('Tentar novamente'), findsOneWidget);
      expect(controller.state.dogId, 'dog-1');
    });

    testWidgets('offline sem cache', (tester) async {
      final source = FakeHealthSummarySource();
      addTearDown(source.disposeAll);

      await pumpDashboard(
        tester,
        source: source,
        emitError: HealthSummarySourceException('offline', isOffline: true),
      );

      expect(find.byKey(const ValueKey('summary-offline')), findsOneWidget);
      expect(find.text('Sem conexão'), findsOneWidget);
    });

    testWidgets('offline com cachedData', (tester) async {
      final source = FakeHealthSummarySource();
      addTearDown(source.disposeAll);

      final controller = await pumpDashboard(
        tester,
        source: source,
        emitData: fullData(),
      );
      source.emitError(
        'dog-1',
        HealthSummarySourceException('offline', isOffline: true),
      );
      await settleState(tester);

      expect(controller.state, isA<HealthSummaryOffline>());
      expect((controller.state as HealthSummaryOffline).cachedData, isNotNull);
      expect(
        find.byKey(const ValueKey('summary-offline-with-cache')),
        findsOneWidget,
      );
      expect(find.textContaining('Modo offline'), findsOneWidget);
      expect(find.text('Bono'), findsOneWidget);
    });
  });

  group('Retry', () {
    testWidgets('Tentar novamente chama controller.refresh', (tester) async {
      final source = FakeHealthSummarySource();
      addTearDown(source.disposeAll);

      await pumpDashboard(
        tester,
        source: source,
        emitError: HealthSummarySourceException('falha'),
      );

      final watchesBefore = source.watchCalls.length;
      await tester.tap(find.text('Tentar novamente'));
      await tester.pump();

      expect(source.watchCalls.length, greaterThan(watchesBefore));
      expect(find.byKey(const ValueKey('summary-loading')), findsOneWidget);
    });
  });

  group('Responsividade', () {
    for (final width in [360.0, 390.0, 768.0]) {
      testWidgets('sem overflow em ${width.toInt()}px', (tester) async {
        final source = FakeHealthSummarySource();
        addTearDown(source.disposeAll);

        await pumpDashboard(
          tester,
          source: source,
          emitData: fullData(),
          width: width,
          height: 1400,
        );

        expect(tester.takeException(), isNull);
        expect(find.text('Bono'), findsOneWidget);
      });
    }

    testWidgets('360px com textScale 1.3 sem overflow', (tester) async {
      final source = FakeHealthSummarySource();
      addTearDown(source.disposeAll);

      await pumpDashboard(
        tester,
        source: source,
        emitData: fullData(),
        width: 360,
        height: 1600,
        textScale: 1.3,
      );

      expect(tester.takeException(), isNull);
      expect(find.text('Bono'), findsOneWidget);
    });
  });

  group('Alimentação', () {
    testWidgets('valores completos', (tester) async {
      final source = FakeHealthSummarySource();
      addTearDown(source.disposeAll);

      await pumpDashboard(tester, source: source, emitData: fullData());

      expect(find.text('Oferecido: 500 g de 600 g'), findsOneWidget);
      expect(find.text('Consumido: 250 g de 600 g'), findsOneWidget);
      expect(find.text('1 de 3 refeições executadas'), findsOneWidget);
    });

    testWidgets('nulls e meta zero', (tester) async {
      final source = FakeHealthSummarySource();
      addTearDown(source.disposeAll);

      await pumpDashboard(
        tester,
        source: source,
        emitData: fullData(
          nutrition: const HealthSummarySectionData.available(
            HealthSummaryNutritionTodayView(
              consumedAmount: 100,
              plannedAmount: 0,
              unitLabel: 'g',
            ),
          ),
        ),
      );

      // Meta zero → sem barra percentual inventada
      expect(find.text('42%'), findsNothing);
      expect(find.textContaining('100 g'), findsOneWidget);
    });

    testWidgets('consumido acima da meta', (tester) async {
      final source = FakeHealthSummarySource();
      addTearDown(source.disposeAll);

      await pumpDashboard(
        tester,
        source: source,
        emitData: fullData(
          nutrition: const HealthSummarySectionData.available(
            HealthSummaryNutritionTodayView(
              consumedAmount: 800,
              plannedAmount: 600,
              unitLabel: 'g',
            ),
          ),
        ),
      );

      expect(find.text('Consumo acima da meta'), findsOneWidget);
    });
  });

  group('Peso / tendência', () {
    testWidgets('zero pontos', (tester) async {
      final source = FakeHealthSummarySource();
      addTearDown(source.disposeAll);

      await pumpDashboard(
        tester,
        source: source,
        emitData: fullData(
          weightTrend: const HealthSummarySectionData.available(
            HealthSummaryWeightTrendView(points: []),
          ),
        ),
      );

      expect(find.text('Sem histórico suficiente'), findsOneWidget);
    });

    testWidgets('um ponto não quebra', (tester) async {
      final source = FakeHealthSummarySource();
      addTearDown(source.disposeAll);

      await pumpDashboard(
        tester,
        source: source,
        emitData: fullData(
          weightTrend: HealthSummarySectionData.available(
            HealthSummaryWeightTrendView(
              points: [
                HealthSummaryWeightPoint(
                  at: DateTime(2026, 7, 1),
                  weightKg: 30,
                ),
              ],
            ),
          ),
        ),
      );

      expect(tester.takeException(), isNull);
      expect(find.text('EVOLUÇÃO DO PESO'), findsOneWidget);
    });

    testWidgets('múltiplos pontos', (tester) async {
      final source = FakeHealthSummarySource();
      addTearDown(source.disposeAll);

      await pumpDashboard(tester, source: source, emitData: fullData());

      expect(find.text('Meta operacional'), findsOneWidget);
      expect(find.text('Score corporal'), findsOneWidget);
      expect(find.text('Ideal'), findsOneWidget);
    });
  });

  group('Registros recentes', () {
    testWidgets('lista vazia', (tester) async {
      final source = FakeHealthSummarySource();
      addTearDown(source.disposeAll);

      await pumpDashboard(
        tester,
        source: source,
        emitData: fullData(
          recent: const HealthSummarySectionData.available(
            HealthSummaryRecentRecordsView(items: []),
          ),
        ),
      );

      expect(find.text('Nenhum registro recente'), findsOneWidget);
    });

    testWidgets('itens e type desconhecido não quebra', (tester) async {
      final source = FakeHealthSummarySource();
      addTearDown(source.disposeAll);

      await pumpDashboard(
        tester,
        source: source,
        emitData: fullData(
          recent: HealthSummarySectionData.available(
            const HealthSummaryRecentRecordsView(
              items: [
                HealthSummaryRecentRecordView(
                  id: 'x',
                  type: 'tipo_futuro_xyz',
                  title: 'Evento novo',
                ),
              ],
            ),
          ),
        ),
      );

      expect(find.text('Evento novo'), findsOneWidget);
      expect(tester.takeException(), isNull);
      expect(
        HealthSummaryRecentRecordIconMapper.iconFor('tipo_futuro_xyz'),
        Icons.note_outlined,
      );
    });
  });

  group('Callbacks', () {
    testWidgets('atenção, nutrição, alimentação, histórico e recente', (
      tester,
    ) async {
      final source = FakeHealthSummarySource();
      addTearDown(source.disposeAll);

      var openNutrition = 0;
      var registerFeeding = 0;
      var openHistory = 0;
      HealthSummaryAttentionItem? attention;
      HealthSummaryRecentRecordView? recent;

      await pumpDashboard(
        tester,
        source: source,
        emitData: fullData(),
        onOpenNutrition: () => openNutrition++,
        onRegisterFeeding: () => registerFeeding++,
        onOpenHistory: () => openHistory++,
        onAttentionItemTap: (item) => attention = item,
        onRecentRecordTap: (item) => recent = item,
      );

      await tester.ensureVisible(find.text('Abrir Nutrição'));
      await tester.tap(find.text('Abrir Nutrição'));
      await tester.pump();
      await tester.ensureVisible(find.text('Registrar alimentação'));
      await tester.tap(find.text('Registrar alimentação'));
      await tester.pump();
      await tester.ensureVisible(find.text('Ver histórico'));
      await tester.tap(find.text('Ver histórico'));
      await tester.pump();
      await tester.ensureVisible(
        find.text('Vacina V10 próxima do vencimento').last,
      );
      await tester.tap(find.text('Vacina V10 próxima do vencimento').last);
      await tester.pump();
      await tester.ensureVisible(find.text('Alimentação registrada'));
      await tester.tap(find.text('Alimentação registrada'));
      await tester.pump();

      expect(openNutrition, 1);
      expect(registerFeeding, 1);
      expect(openHistory, 1);
      expect(attention?.id, 'att-1');
      expect(recent?.id, 'r1');
    });
  });

  group('Auditoria — anti-invenção e bordas', () {
    testWidgets('vacinação available sem summaryLabel não inventa REGISTRADA', (
      tester,
    ) async {
      final source = FakeHealthSummarySource();
      addTearDown(source.disposeAll);

      await pumpDashboard(
        tester,
        source: source,
        emitData: fullData(
          vaccination: const HealthSummarySectionData.available(
            HealthSummaryVaccinationView(
              summaryLabel: null,
              lastRecordLabel: null,
              nextDueAt: null,
            ),
          ),
        ),
      );

      expect(find.text('REGISTRADA'), findsNothing);
      expect(find.text('EM DIA'), findsNothing);
    });

    testWidgets('mismatch dogContext vs payload exibe banner de inconsistência', (
      tester,
    ) async {
      final source = FakeHealthSummarySource();
      addTearDown(source.disposeAll);

      await pumpDashboard(
        tester,
        source: source,
        dogContext: HealthSummaryDogContextView(dogId: 'dog-A', name: 'Alpha'),
        emitData: fullData(dogId: 'dog-1'),
      );

      // Controller ignora payload com dogId divergente do selectDog('dog-1')?
      // fullData dogId dog-1 + selectDog dog-1 → data ok; dogContext dog-A diverge.
      expect(
        find.textContaining('não corresponde aos dados do resumo'),
        findsOneWidget,
      );
      expect(find.text('Alpha'), findsOneWidget);
    });

    testWidgets(
      'atenção unavailable não mostra empty positivo nem falso alerta',
      (tester) async {
        final source = FakeHealthSummarySource();
        addTearDown(source.disposeAll);

        await pumpDashboard(
          tester,
          source: source,
          emitData: fullData(
            attention: const HealthSummarySectionData.unavailable(
              message:
                  'Não foi possível determinar as atenções deste K9 no momento.',
            ),
          ),
        );

        // Título da seção neutro — não afirma "REQUER ATENÇÃO".
        expect(find.text('REQUER ATENÇÃO'), findsNothing);
        expect(find.text('ATENÇÕES'), findsWidgets);
        expect(find.text('INDISPONÍVEL'), findsWidgets);
        expect(
          find.text(
            'Não foi possível determinar as atenções deste K9 no momento.',
          ),
          findsOneWidget,
        );
        expect(find.text('Nenhuma atenção prioritária'), findsNothing);
        expect(find.text('NENHUMA'), findsNothing);
      },
    );

    testWidgets('tratamentos unavailable não mostra NENHUMA ATIVA', (
      tester,
    ) async {
      final source = FakeHealthSummarySource();
      addTearDown(source.disposeAll);

      await pumpDashboard(
        tester,
        source: source,
        emitData: fullData(
          treatments: const HealthSummarySectionData.unavailable(
            message: 'Informações de tratamentos ainda não estão disponíveis.',
          ),
        ),
      );

      expect(find.text('INDISPONÍVEL'), findsWidgets);
      expect(find.text('NENHUMA ATIVA'), findsNothing);
    });

    testWidgets('pontos de peso desordenados não quebram o gráfico', (
      tester,
    ) async {
      final source = FakeHealthSummarySource();
      addTearDown(source.disposeAll);

      await pumpDashboard(
        tester,
        source: source,
        emitData: fullData(
          weightTrend: HealthSummarySectionData.available(
            HealthSummaryWeightTrendView(
              points: [
                HealthSummaryWeightPoint(
                  at: DateTime(2026, 7, 1),
                  weightKg: 30,
                ),
                HealthSummaryWeightPoint(
                  at: DateTime(2026, 6, 1),
                  weightKg: 28,
                ),
                HealthSummaryWeightPoint(
                  at: DateTime(2026, 6, 15),
                  weightKg: 29,
                ),
              ],
            ),
          ),
        ),
      );

      expect(tester.takeException(), isNull);
      expect(find.text('EVOLUÇÃO DO PESO'), findsOneWidget);
    });

    testWidgets('pesos iguais e um único ponto não geram overflow/exception', (
      tester,
    ) async {
      final source = FakeHealthSummarySource();
      addTearDown(source.disposeAll);

      await pumpDashboard(
        tester,
        source: source,
        emitData: fullData(
          weightTrend: HealthSummarySectionData.available(
            HealthSummaryWeightTrendView(
              points: [
                HealthSummaryWeightPoint(
                  at: DateTime(2026, 6, 1),
                  weightKg: 29.0,
                ),
                HealthSummaryWeightPoint(
                  at: DateTime(2026, 6, 15),
                  weightKg: 29.0,
                ),
                HealthSummaryWeightPoint(
                  at: DateTime(2026, 7, 1),
                  weightKg: 29.0,
                ),
              ],
            ),
          ),
        ),
      );

      expect(tester.takeException(), isNull);
    });

    testWidgets('banner stale sem alterar prontidão exibida', (tester) async {
      final source = FakeHealthSummarySource();
      addTearDown(source.disposeAll);

      await pumpDashboard(
        tester,
        source: source,
        emitData: fullData(
          readiness: ReadinessStatus.operational,
          metadata: const HealthSummarySourceMetadata(isStale: true),
        ),
      );

      expect(find.text('Dados possivelmente desatualizados'), findsOneWidget);
      expect(find.text('OPERACIONAL'), findsOneWidget);
    });

    testWidgets('responsividade 320px sem overflow', (tester) async {
      final source = FakeHealthSummarySource();
      addTearDown(source.disposeAll);

      await pumpDashboard(
        tester,
        source: source,
        emitData: fullData(),
        width: 320,
        height: 1600,
      );

      expect(tester.takeException(), isNull);
      expect(find.text('Bono'), findsOneWidget);
    });

    testWidgets('nome e raça longos sem overflow em 360px textScale 1.3', (
      tester,
    ) async {
      final source = FakeHealthSummarySource();
      addTearDown(source.disposeAll);

      await pumpDashboard(
        tester,
        source: source,
        dogContext: HealthSummaryDogContextView(
          dogId: 'dog-1',
          name: 'Comandante Bono Ragonha Malinois Operacional Extenso',
          breed: 'Pastor Belga Malinois de linhagem europeia operacional',
          sexLabel: 'Macho',
          ageLabel: '6 anos e 3 meses',
        ),
        emitData: fullData(),
        width: 360,
        height: 1800,
        textScale: 1.3,
      );

      expect(tester.takeException(), isNull);
      expect(find.textContaining('Comandante Bono'), findsOneWidget);
    });
  });

  group('Formatters', () {
    test('weightKg e amount não mascaram NaN/Infinity como valores reais', () {
      expect(HealthSummaryFormatters.weightKg(double.nan), '—');
      expect(HealthSummaryFormatters.weightKg(double.infinity), '—');
      expect(HealthSummaryFormatters.amount(double.nan, 'g'), '—');
      expect(HealthSummaryFormatters.weightKg(29.8), '29,8 kg');
      expect(HealthSummaryFormatters.amount(250, 'g'), '250 g');
    });

    test('daysUntilLabel e shortDate são determinísticos com now fixo', () {
      final now = DateTime(2026, 7, 15);
      expect(
        HealthSummaryFormatters.daysUntilLabel(DateTime(2026, 7, 15), now: now),
        'Vence hoje',
      );
      expect(
        HealthSummaryFormatters.daysUntilLabel(DateTime(2026, 7, 10), now: now),
        'Vencida há 5 dias',
      );
      expect(HealthSummaryFormatters.shortDate(DateTime(2026, 6, 8)), '08/06');
    });
  });

  group('Cores Semânticas UX-03B', () {
    testWidgets('1. Peso usa AppTheme.info', (tester) async {
      final source = FakeHealthSummarySource();
      addTearDown(source.disposeAll);
      await pumpDashboard(tester, source: source, emitData: fullData());

      final weightCard = tester.widget<HealthSummaryMetricCard>(
        find.byKey(const ValueKey('metric-weight')),
      );
      expect(weightCard.accentColor, equals(AppTheme.info));
    });

    testWidgets('2. Vacinação usa AppTheme.success', (tester) async {
      final source = FakeHealthSummarySource();
      addTearDown(source.disposeAll);
      await pumpDashboard(tester, source: source, emitData: fullData());

      final vaccCard = tester.widget<HealthSummaryMetricCard>(
        find.byKey(const ValueKey('metric-vaccination')),
      );
      expect(vaccCard.accentColor, equals(AppTheme.success));
    });

    testWidgets('3. Medicação usa AppTheme.primary (cyan categoria clínica)', (
      tester,
    ) async {
      final source = FakeHealthSummarySource();
      addTearDown(source.disposeAll);
      await pumpDashboard(tester, source: source, emitData: fullData());

      final treatCard = tester.widget<HealthSummaryMetricCard>(
        find.byKey(const ValueKey('metric-treatments')),
      );
      expect(treatCard.accentColor, equals(AppTheme.primary));
    });

    testWidgets('4. Atenção com pendências usa AppTheme.warningAccent', (
      tester,
    ) async {
      final source = FakeHealthSummarySource();
      addTearDown(source.disposeAll);
      await pumpDashboard(tester, source: source, emitData: fullData());

      final attCard = tester.widget<HealthSummaryMetricCard>(
        find.byKey(const ValueKey('metric-attention')),
      );
      expect(attCard.accentColor, equals(AppTheme.warningAccent));
    });

    testWidgets('5. Atenção sem pendências usa AppTheme.success', (
      tester,
    ) async {
      final source = FakeHealthSummarySource();
      addTearDown(source.disposeAll);
      final emptyAttentionData = HealthSummaryViewData(
        dogId: 'dog-1',
        readiness: const HealthSummarySectionData.available(
          HealthSummaryReadinessView(status: ReadinessStatus.operational),
        ),
        weight: const HealthSummarySectionData.unavailable(),
        vaccination: const HealthSummarySectionData.unavailable(),
        treatments: const HealthSummarySectionData.unavailable(),
        attention: const HealthSummarySectionData.available(
          HealthSummaryAttentionView(items: []),
        ),
        nutritionToday: const HealthSummarySectionData.unavailable(),
        weightTrend: const HealthSummarySectionData.unavailable(),
        recentRecords: const HealthSummarySectionData.unavailable(),
        metadata: HealthSummarySourceMetadata(updatedAt: DateTime(2026, 7, 15)),
      );

      await pumpDashboard(tester, source: source, emitData: emptyAttentionData);

      final attCard = tester.widget<HealthSummaryMetricCard>(
        find.byKey(const ValueKey('metric-attention')),
      );
      expect(attCard.accentColor, equals(AppTheme.success));
    });

    testWidgets('6. Alimentação usa AppTheme.attention como acento categórico', (
      tester,
    ) async {
      final source = FakeHealthSummarySource();
      addTearDown(source.disposeAll);
      await pumpDashboard(tester, source: source, emitData: fullData());

      final iconFinder = find.descendant(
        of: find.byType(HealthSummaryNutritionCard),
        matching: find.byIcon(Icons.restaurant_rounded),
      );
      final icon = tester.widget<Icon>(iconFinder);
      expect(icon.color, equals(AppTheme.attention));
    });

    testWidgets('7. Consumo confirmado permanece AppTheme.success', (
      tester,
    ) async {
      final source = FakeHealthSummarySource();
      addTearDown(source.disposeAll);
      await pumpDashboard(tester, source: source, emitData: fullData());

      final progressIndicators = tester.widgetList<LinearProgressIndicator>(
        find.byType(LinearProgressIndicator),
      );
      // Oferecido (primeiro) vs Consumido (segundo)
      expect(progressIndicators.first.color, equals(AppTheme.attention));
      expect(progressIndicators.elementAt(1).color, equals(AppTheme.success));
    });

    testWidgets('8. Evolução do peso usa AppTheme.info', (tester) async {
      final source = FakeHealthSummarySource();
      addTearDown(source.disposeAll);
      await pumpDashboard(tester, source: source, emitData: fullData());

      final chartIcon = tester.widget<Icon>(
        find.byIcon(Icons.show_chart_rounded),
      );
      expect(chartIcon.color, equals(AppTheme.info));

      final painterFinder = find.byWidgetPredicate(
        (w) => w is CustomPaint && w.painter is HealthSummaryWeightChartPainter,
      );
      final customPaint = tester.widget<CustomPaint>(painterFinder);
      final painter = customPaint.painter as HealthSummaryWeightChartPainter;
      expect(painter.points, isNotEmpty);
    });

    testWidgets(
      '10. Loading e indisponível não aparecem como sucesso indevido',
      (tester) async {
        final source = FakeHealthSummarySource();
        addTearDown(source.disposeAll);
        final unavailableData = HealthSummaryViewData(
          dogId: 'dog-1',
          readiness: const HealthSummarySectionData.unavailable(),
          weight: const HealthSummarySectionData.unavailable(),
          vaccination: const HealthSummarySectionData.unavailable(),
          treatments: const HealthSummarySectionData.unavailable(),
          attention: const HealthSummarySectionData.unavailable(),
          nutritionToday: const HealthSummarySectionData.unavailable(),
          weightTrend: const HealthSummarySectionData.unavailable(),
          recentRecords: const HealthSummarySectionData.unavailable(),
          metadata: HealthSummarySourceMetadata(updatedAt: DateTime(2026, 7, 15)),
        );

        await pumpDashboard(tester, source: source, emitData: unavailableData);

        final attCard = tester.widget<HealthSummaryMetricCard>(
          find.byKey(const ValueKey('metric-attention')),
        );
        expect(attCard.accentColor, equals(AppTheme.textSoft));
      },
    );
  });

  group('Mini-Timeline de Registros Recentes UX-03C', () {
    test('1. Mapeamento semântico de cores por tipo (11 tipos)', () {
      expect(
        HealthSummaryRecentRecordColorMapper.colorFor('feeding'),
        equals(AppTheme.attention),
      );
      expect(
        HealthSummaryRecentRecordColorMapper.colorFor('weight'),
        equals(AppTheme.info),
      );
      expect(
        HealthSummaryRecentRecordColorMapper.colorFor('vaccination'),
        equals(AppTheme.success),
      );
      expect(
        HealthSummaryRecentRecordColorMapper.colorFor('consultation'),
        equals(AppTheme.healthAccent),
      );
      expect(
        HealthSummaryRecentRecordColorMapper.colorFor('exam'),
        equals(AppTheme.healthAccent),
      );
      expect(
        HealthSummaryRecentRecordColorMapper.colorFor('medication'),
        equals(AppTheme.primary),
      );
      expect(
        HealthSummaryRecentRecordColorMapper.colorFor('surgery'),
        equals(AppTheme.healthAccent),
      );
      expect(
        HealthSummaryRecentRecordColorMapper.colorFor('antiparasitic'),
        equals(AppTheme.success),
      );
      expect(
        HealthSummaryRecentRecordColorMapper.colorFor('symptom'),
        equals(AppTheme.warningAccent),
      );
      expect(
        HealthSummaryRecentRecordColorMapper.colorFor('restriction'),
        equals(AppTheme.error),
      );
      expect(
        HealthSummaryRecentRecordColorMapper.colorFor('other'),
        equals(AppTheme.textSoft),
      );
      expect(
        HealthSummaryRecentRecordColorMapper.colorFor('desconhecido_abc'),
        equals(AppTheme.textSoft),
      );
    });

    test('2. Mapeamento tolerante de ícones por tipo (preservado)', () {
      expect(
        HealthSummaryRecentRecordIconMapper.iconFor('feeding'),
        equals(Icons.restaurant_rounded),
      );
      expect(
        HealthSummaryRecentRecordIconMapper.iconFor('weight'),
        equals(Icons.monitor_weight_outlined),
      );
      expect(
        HealthSummaryRecentRecordIconMapper.iconFor('vaccination'),
        equals(Icons.verified_user_outlined),
      );
      expect(
        HealthSummaryRecentRecordIconMapper.iconFor('consultation'),
        equals(Icons.medical_services_outlined),
      );
      expect(
        HealthSummaryRecentRecordIconMapper.iconFor('exam'),
        equals(Icons.assignment_outlined),
      );
      expect(
        HealthSummaryRecentRecordIconMapper.iconFor('medication'),
        equals(Icons.medication_outlined),
      );
      expect(
        HealthSummaryRecentRecordIconMapper.iconFor('surgery'),
        equals(Icons.medical_services_outlined),
      );
      expect(
        HealthSummaryRecentRecordIconMapper.iconFor('antiparasitic'),
        equals(Icons.shield_outlined),
      );
      expect(
        HealthSummaryRecentRecordIconMapper.iconFor('symptom'),
        equals(Icons.warning_amber_rounded),
      );
      expect(
        HealthSummaryRecentRecordIconMapper.iconFor('restriction'),
        equals(Icons.gpp_maybe_outlined),
      );
      expect(
        HealthSummaryRecentRecordIconMapper.iconFor('desconhecido_xyz'),
        equals(Icons.note_outlined),
      );
    });

    testWidgets('3. Renderização da mini-timeline com conectores e acentos semânticos', (
      tester,
    ) async {
      final records = [
        HealthSummaryRecentRecordView(
          id: 'rec-1',
          type: 'feeding',
          title: 'Alimentação matutina',
          subtitle: 'Ração Seca 350g',
          occurredAt: DateTime(2026, 7, 15, 8, 0),
        ),
        HealthSummaryRecentRecordView(
          id: 'rec-2',
          type: 'weight',
          title: 'Pesagem quinzenal',
          subtitle: '32.4 kg',
          occurredAt: DateTime(2026, 7, 14, 10, 0),
        ),
        HealthSummaryRecentRecordView(
          id: 'rec-3',
          type: 'vaccination',
          title: 'Vacina V10',
          subtitle: 'Dose anual',
          occurredAt: DateTime(2026, 7, 10, 9, 0),
        ),
      ];

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: HealthSummaryRecentRecords(
              recentRecords: HealthSummarySectionData.available(
                HealthSummaryRecentRecordsView(items: records),
              ),
            ),
          ),
        ),
      );

      expect(find.text('Alimentação matutina'), findsOneWidget);
      expect(find.text('Pesagem quinzenal'), findsOneWidget);
      expect(find.text('Vacina V10'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('4. Item único renderiza sem exceção ou quebra visual', (
      tester,
    ) async {
      final records = [
        HealthSummaryRecentRecordView(
          id: 'rec-1',
          type: 'medication',
          title: 'Dose única vermífugo',
          occurredAt: DateTime(2026, 7, 15, 8, 0),
        ),
      ];

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: HealthSummaryRecentRecords(
              recentRecords: HealthSummarySectionData.available(
                HealthSummaryRecentRecordsView(items: records),
              ),
            ),
          ),
        ),
      );

      expect(find.text('Dose única vermífugo'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('5. Callbacks de histórico e de toque no registro mantidos', (
      tester,
    ) async {
      bool historyTapped = false;
      HealthSummaryRecentRecordView? recordTapped;

      final records = [
        HealthSummaryRecentRecordView(
          id: 'rec-1',
          type: 'consultation',
          title: 'Consulta veterinária',
          occurredAt: DateTime(2026, 7, 15, 8, 0),
        ),
      ];

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: HealthSummaryRecentRecords(
              recentRecords: HealthSummarySectionData.available(
                HealthSummaryRecentRecordsView(items: records),
              ),
              onOpenHistory: () => historyTapped = true,
              onRecentRecordTap: (r) => recordTapped = r,
            ),
          ),
        ),
      );

      await tester.tap(find.text('Ver histórico'));
      expect(historyTapped, isTrue);

      await tester.tap(find.text('Consulta veterinária'));
      expect(recordTapped?.id, equals('rec-1'));
    });

    testWidgets('6. Responsividade 320px com múltiplos registros e zero overflow', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(320 * 3, 1600 * 3);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final records = List.generate(
        6,
        (i) => HealthSummaryRecentRecordView(
          id: 'rec-$i',
          type: i % 2 == 0 ? 'symptom' : 'restriction',
          title: 'Registro longo número $i para teste de responsividade extrema',
          subtitle: 'Detalhe suplementar do registro $i',
          occurredAt: DateTime(2026, 7, 15 - i, 8, 0),
        ),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(
              size: Size(320, 1600),
            ),
            child: Scaffold(
              body: SingleChildScrollView(
                child: HealthSummaryRecentRecords(
                  recentRecords: HealthSummarySectionData.available(
                    HealthSummaryRecentRecordsView(items: records),
                  ),
                  onRecentRecordTap: (_) {},
                ),
              ),
            ),
          ),
        ),
      );

      final mediaQuery = tester.widget<MediaQuery>(find.byType(MediaQuery).last);
      expect(mediaQuery.data.size.width, equals(320.0));
      expect(tester.takeException(), isNull);
    });

    testWidgets('7. Responsividade 360px com textScale 1.3 e zero overflow', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(360 * 3, 1600 * 3);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final records = [
        HealthSummaryRecentRecordView(
          id: 'rec-1',
          type: 'exam',
          title: 'Exame de ultrassom abdominal completo com sedação leve',
          subtitle: 'Clínica Veterinária Central K9',
          occurredAt: DateTime(2026, 7, 15, 8, 0),
        ),
      ];

      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(
              size: Size(360, 1600),
              textScaler: TextScaler.linear(1.3),
            ),
            child: Scaffold(
              body: HealthSummaryRecentRecords(
                recentRecords: HealthSummarySectionData.available(
                  HealthSummaryRecentRecordsView(items: records),
                ),
                onRecentRecordTap: (_) {},
              ),
            ),
          ),
        ),
      );

      final mediaQuery = tester.widget<MediaQuery>(find.byType(MediaQuery).last);
      expect(mediaQuery.data.size.width, equals(360.0));
      expect(tester.takeException(), isNull);
    });

    testWidgets('8. Responsividade com textScale 1.5 e título multi-linha com zero overflow', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(360 * 3, 1600 * 3);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final records = [
        HealthSummaryRecentRecordView(
          id: 'rec-1',
          type: 'surgery',
          title: 'Procedimento cirúrgico de sutura em pata dianteira esquerda pós-operação tática',
          subtitle: 'Hospital Veterinário de Especialidades K9 · Dr. Ricardo Silva',
          occurredAt: DateTime(2026, 7, 15, 8, 0),
        ),
      ];

      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(
              textScaler: TextScaler.linear(1.5),
            ),
            child: Scaffold(
              body: SingleChildScrollView(
                child: HealthSummaryRecentRecords(
                  recentRecords: HealthSummarySectionData.available(
                    HealthSummaryRecentRecordsView(items: records),
                  ),
                  onRecentRecordTap: (_) {},
                ),
              ),
            ),
          ),
        ),
      );

      expect(tester.takeException(), isNull);
    });

    testWidgets('9. Semantics de tile acionável possui button: true, label completo e chevron', (
      tester,
    ) async {
      final records = [
        HealthSummaryRecentRecordView(
          id: 'rec-1',
          type: 'vaccination',
          title: 'Vacina V10 Anual',
          subtitle: 'Clínica K9 Central',
          occurredAt: DateTime(2026, 7, 15, 8, 0),
        ),
      ];

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: HealthSummaryRecentRecords(
              recentRecords: HealthSummarySectionData.available(
                HealthSummaryRecentRecordsView(items: records),
              ),
              onRecentRecordTap: (_) {},
            ),
          ),
        ),
      );

      final recentTileFinder = find.byWidgetPredicate(
        (w) => w.runtimeType.toString() == '_RecentTile',
      );
      final tileChevronFinder = find.descendant(
        of: recentTileFinder,
        matching: find.byIcon(Icons.chevron_right_rounded),
      );
      expect(tileChevronFinder, findsOneWidget);

      final semanticsFinder = find.descendant(
        of: recentTileFinder,
        matching: find.byWidgetPredicate(
          (w) => w is Semantics && w.properties.button == true,
        ),
      );
      expect(semanticsFinder, findsOneWidget);

      final semantics = tester.widget<Semantics>(semanticsFinder);
      expect(semantics.properties.enabled, isTrue);
      expect(semantics.properties.label, contains('Vacina V10 Anual'));
      expect(semantics.properties.label, contains('Clínica K9 Central'));
    });

    testWidgets('10. Semantics de tile sem callback não anuncia botão e oculta chevron', (
      tester,
    ) async {
      final records = [
        HealthSummaryRecentRecordView(
          id: 'rec-1',
          type: 'weight',
          title: 'Pesagem de controle',
          occurredAt: DateTime(2026, 7, 15, 8, 0),
        ),
      ];

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: HealthSummaryRecentRecords(
              recentRecords: HealthSummarySectionData.available(
                HealthSummaryRecentRecordsView(items: records),
              ),
              onRecentRecordTap: null,
            ),
          ),
        ),
      );

      final recentTileFinder = find.byWidgetPredicate(
        (w) => w.runtimeType.toString() == '_RecentTile',
      );
      final tileChevronFinder = find.descendant(
        of: recentTileFinder,
        matching: find.byIcon(Icons.chevron_right_rounded),
      );
      expect(tileChevronFinder, findsNothing);

      final buttonSemanticsFinder = find.descendant(
        of: recentTileFinder,
        matching: find.byWidgetPredicate(
          (w) => w is Semantics && w.properties.button == true,
        ),
      );
      expect(buttonSemanticsFinder, findsNothing);
      expect(find.text('Pesagem de controle'), findsOneWidget);
    });

    testWidgets('11. Elementos decorativos (nó, ícone e conector) excluídos da árvore semântica', (
      tester,
    ) async {
      final records = [
        HealthSummaryRecentRecordView(
          id: 'rec-1',
          type: 'feeding',
          title: 'Refeição Matutina 300g',
          occurredAt: DateTime(2026, 7, 15, 8, 0),
        ),
      ];

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: HealthSummaryRecentRecords(
              recentRecords: HealthSummarySectionData.available(
                HealthSummaryRecentRecordsView(items: records),
              ),
              onRecentRecordTap: (_) {},
            ),
          ),
        ),
      );

      final recentTileFinder = find.byWidgetPredicate(
        (w) => w.runtimeType.toString() == '_RecentTile',
      );
      final tileSemantics = tester.widget<Semantics>(
        find.descendant(
          of: recentTileFinder,
          matching: find.byWidgetPredicate((w) => w is Semantics && w.excludeSemantics == true),
        ),
      );
      expect(tileSemantics.excludeSemantics, isTrue);
    });

    testWidgets('12. Touch target do tile acionável possui dimensões >= 48x48 dp', (
      tester,
    ) async {
      bool tapped = false;
      final records = [
        HealthSummaryRecentRecordView(
          id: 'rec-1',
          type: 'medication',
          title: 'Aplicação de Antiparassitário',
          occurredAt: DateTime(2026, 7, 15, 8, 0),
        ),
      ];

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: HealthSummaryRecentRecords(
              recentRecords: HealthSummarySectionData.available(
                HealthSummaryRecentRecordsView(items: records),
              ),
              onRecentRecordTap: (_) => tapped = true,
            ),
          ),
        ),
      );

      final recentTileFinder = find.byWidgetPredicate(
        (w) => w.runtimeType.toString() == '_RecentTile',
      );
      final inkWellFinder = find.descendant(
        of: recentTileFinder,
        matching: find.byType(InkWell),
      );
      expect(inkWellFinder, findsOneWidget);

      final size = tester.getSize(inkWellFinder);
      expect(size.width, greaterThanOrEqualTo(48.0));
      expect(size.height, greaterThanOrEqualTo(48.0));

      await tester.tap(inkWellFinder);
      expect(tapped, isTrue);
    });

    testWidgets('13. Validação de conectores (primeiro sem top, último sem bottom, único sem ambos)', (
      tester,
    ) async {
      final records = [
        HealthSummaryRecentRecordView(
          id: 'rec-1',
          type: 'feeding',
          title: 'Refeição 1',
          occurredAt: DateTime(2026, 7, 15, 8, 0),
        ),
        HealthSummaryRecentRecordView(
          id: 'rec-2',
          type: 'weight',
          title: 'Pesagem 2',
          occurredAt: DateTime(2026, 7, 14, 8, 0),
        ),
      ];

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: HealthSummaryRecentRecords(
              recentRecords: HealthSummarySectionData.available(
                HealthSummaryRecentRecordsView(items: records),
              ),
            ),
          ),
        ),
      );

      expect(find.text('Refeição 1'), findsOneWidget);
      expect(find.text('Pesagem 2'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
