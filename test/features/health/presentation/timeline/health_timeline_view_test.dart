import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:canil_gcm/features/health/domain/health_v1_enums_ext.dart';
import 'package:canil_gcm/features/health/domain/health_v1_models.dart';
import 'package:canil_gcm/features/health/domain/health_v1_value_objects.dart';
import 'package:canil_gcm/features/health/presentation/timeline/health_timeline_controller.dart';
import 'package:canil_gcm/features/health/presentation/timeline/health_timeline_entry_view.dart';
import 'package:canil_gcm/features/health/presentation/timeline/health_timeline_query.dart';
import 'package:canil_gcm/features/health/presentation/timeline/health_timeline_source.dart';
import 'package:canil_gcm/features/health/presentation/timeline/widgets/health_timeline_entry_card.dart';
import 'package:canil_gcm/features/health/presentation/timeline/widgets/health_timeline_formatters.dart';
import 'package:canil_gcm/features/health/presentation/timeline/widgets/health_timeline_refresh_banner.dart';
import 'package:canil_gcm/features/health/presentation/timeline/widgets/health_timeline_type_visuals.dart';
import 'package:canil_gcm/features/health/presentation/timeline/widgets/health_timeline_user_copy.dart';
import 'package:canil_gcm/features/health/presentation/timeline/widgets/health_timeline_view.dart';

import 'fake_health_timeline_source.dart';
import 'timeline_test_helpers.dart';

void main() {
  setUpAll(() {
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  /// Relógio fixo: 16 jul 2026 14:00 local de teste.
  final fixedNow = DateTime(2026, 7, 16, 14, 0);

  Widget wrap(Widget child, {double width = 390, double height = 1200}) {
    return MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(size: Size(width, height)),
        child: Scaffold(
          backgroundColor: const Color(0xFF050D10),
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

  (HealthTimelineController, FakeHealthTimelineSource) buildController() {
    final source = FakeHealthTimelineSource();
    final controller = HealthTimelineController(source: source);
    addTearDown(controller.dispose);
    return (controller, source);
  }

  Future<void> pumpTimeline(
    WidgetTester tester, {
    required HealthTimelineController controller,
    double width = 390,
    double height = 1400,
    ValueChanged<HealthTimelineEntryView>? onEntryTap,
    VoidCallback? onFilterRequested,
    int? activeFilterCount,
    bool? hasActiveFilters,
    String? contextLabel,
  }) async {
    configureSurface(tester, width: width, height: height);
    await tester.pumpWidget(
      wrap(
        HealthTimelineView(
          controller: controller,
          onEntryTap: onEntryTap,
          onFilterRequested: onFilterRequested,
          activeFilterCount: activeFilterCount,
          hasActiveFilters: hasActiveFilters,
          contextLabel: contextLabel,
          now: () => fixedNow,
        ),
        width: width,
        height: height,
      ),
    );
    await tester.pump();
  }

  group('HealthTimelineFormatters', () {
    test('dayGroupLabel HOJE / ONTEM / histórico', () {
      expect(
        HealthTimelineFormatters.dayGroupLabel(
          DateTime(2026, 7, 16),
          now: fixedNow,
        ),
        'HOJE',
      );
      expect(
        HealthTimelineFormatters.dayGroupLabel(
          DateTime(2026, 7, 15),
          now: fixedNow,
        ),
        'ONTEM',
      );
      expect(
        HealthTimelineFormatters.dayGroupLabel(
          DateTime(2026, 7, 10),
          now: fixedNow,
        ),
        '10 JUL 2026',
      );
    });

    test('timeOfDay e metadata labels', () {
      expect(
        HealthTimelineFormatters.timeOfDay(DateTime(2026, 7, 16, 9, 5)),
        '09:05',
      );
      expect(
        HealthTimelineFormatters.amendmentsLabel(
          hasAmendments: true,
          amendmentCount: 1,
        ),
        'Adendo registrado',
      );
      expect(
        HealthTimelineFormatters.amendmentsLabel(
          hasAmendments: true,
          amendmentCount: 2,
        ),
        '2 adendos',
      );
      expect(
        HealthTimelineFormatters.attachmentsLabel(
          hasAttachments: true,
          attachmentCount: 2,
        ),
        '2 anexos',
      );
      expect(
        HealthTimelineFormatters.recordedByLabel('GCM Ragonha'),
        'Registrado por GCM Ragonha',
      );
    });
  });

  group('HealthTimelineTypeVisuals', () {
    test('tipos conhecidos e desconhecido neutro', () {
      final consultation = HealthTimelineTypeVisuals.resolve(
        HealthTimelineTypeView.known(HealthTimelineType.consultation),
      );
      expect(consultation.label, 'CONSULTA VETERINÁRIA');

      final unknown = HealthTimelineTypeVisuals.resolve(
        HealthTimelineTypeView.parse('future_procedure_v9'),
      );
      expect(unknown.label, HealthTimelineUserCopy.unknownTypeLabel);
      expect(unknown.label.toLowerCase(), isNot(contains('future')));
      expect(unknown.label.toLowerCase(), isNot(contains('unknown')));
    });
  });

  group('estados da view', () {
    testWidgets('initial', (tester) async {
      final (controller, _) = buildController();
      await pumpTimeline(tester, controller: controller);

      expect(find.text(HealthTimelineUserCopy.initialTitle), findsOneWidget);
      expect(find.byKey(const ValueKey('timeline-initial')), findsOneWidget);
    });

    testWidgets('loading', (tester) async {
      final (controller, source) = buildController();
      source.holdResponses = true;

      await pumpTimeline(tester, controller: controller);
      final load = controller.setQuery(HealthTimelineQuery(dogId: 'dog-a'));
      await tester.pump();

      expect(find.byKey(const ValueKey('timeline-loading')), findsOneWidget);
      expect(find.text(HealthTimelineUserCopy.title), findsOneWidget);

      source.completeNext(pageOf([]));
      await load;
      await tester.pump();
    });

    testWidgets('empty sem filtros', (tester) async {
      final (controller, source) = buildController();
      source.enqueuePage(pageOf([]));
      await pumpTimeline(tester, controller: controller);
      await controller.setQuery(HealthTimelineQuery(dogId: 'dog-a'));
      await tester.pump();

      expect(find.byKey(const ValueKey('timeline-empty')), findsOneWidget);
      expect(find.text(HealthTimelineUserCopy.emptyMessage), findsOneWidget);
      expect(find.textContaining('nunca teve'), findsNothing);
    });

    testWidgets('empty com filtros', (tester) async {
      final (controller, source) = buildController();
      source.enqueuePage(pageOf([]));
      await pumpTimeline(
        tester,
        controller: controller,
        hasActiveFilters: true,
        activeFilterCount: 2,
        onFilterRequested: () {},
      );
      await controller.setQuery(
        HealthTimelineQuery(
          dogId: 'dog-a',
          types: {HealthTimelineType.vaccination},
        ),
      );
      await tester.pump();

      expect(
        find.text(HealthTimelineUserCopy.emptyWithFiltersMessage),
        findsOneWidget,
      );
    });

    testWidgets('error global com retry', (tester) async {
      final (controller, source) = buildController();
      source.enqueueError(
        const HealthTimelineSourceException('boom-index-firebase'),
      );
      await pumpTimeline(tester, controller: controller);
      await controller.setQuery(HealthTimelineQuery(dogId: 'dog-a'));
      await tester.pump();

      expect(find.byKey(const ValueKey('timeline-error')), findsOneWidget);
      expect(find.text(HealthTimelineUserCopy.errorMessage), findsOneWidget);
      expect(find.textContaining('firebase'), findsNothing);
      expect(find.text(HealthTimelineUserCopy.retry), findsOneWidget);

      source.enqueuePage(pageOf([entry(id: 'e1', title: 'Consulta ok')]));
      await tester.tap(find.text(HealthTimelineUserCopy.retry));
      await tester.pumpAndSettle();

      expect(find.text('Consulta ok'), findsOneWidget);
    });

    testWidgets('offline global', (tester) async {
      final (controller, source) = buildController();
      source.enqueueOffline();
      await pumpTimeline(tester, controller: controller);
      await controller.setQuery(HealthTimelineQuery(dogId: 'dog-a'));
      await tester.pump();

      expect(find.byKey(const ValueKey('timeline-offline')), findsOneWidget);
      expect(find.text(HealthTimelineUserCopy.offlineMessage), findsOneWidget);
      expect(find.text(HealthTimelineUserCopy.retry), findsOneWidget);
    });

    testWidgets('data com header e contexto', (tester) async {
      final (controller, source) = buildController();
      source.enqueuePage(
        pageOf([
          entry(
            id: 'c1',
            type: HealthTimelineType.consultation,
            title: 'Avaliação por claudicação',
            subtitle: 'Restrição operacional por 5 dias',
            occurredAt: DateTime(2026, 7, 16, 14, 32),
          ),
        ]),
      );
      await pumpTimeline(tester, controller: controller, contextLabel: 'Bono');
      await controller.setQuery(HealthTimelineQuery(dogId: 'dog-a'));
      await tester.pump();

      expect(find.byKey(const ValueKey('timeline-data')), findsOneWidget);
      expect(find.text(HealthTimelineUserCopy.title), findsOneWidget);
      expect(find.textContaining('Bono'), findsOneWidget);
      expect(find.text('CONSULTA VETERINÁRIA'), findsOneWidget);
      expect(find.text('Avaliação por claudicação'), findsOneWidget);
      expect(find.text('HOJE'), findsOneWidget);
    });
  });

  group('agrupamento visual', () {
    testWidgets('HOJE, ONTEM e data histórica', (tester) async {
      final (controller, source) = buildController();
      source.enqueuePage(
        pageOf([
          entry(
            id: 't1',
            title: 'Hoje item',
            occurredAt: DateTime(2026, 7, 16, 10),
          ),
          entry(
            id: 'y1',
            title: 'Ontem item',
            type: HealthTimelineType.meal,
            occurredAt: DateTime(2026, 7, 15, 18),
          ),
          entry(
            id: 'h1',
            title: 'Histórico item',
            type: HealthTimelineType.vaccination,
            occurredAt: DateTime(2026, 7, 10, 9),
          ),
        ]),
      );
      await pumpTimeline(tester, controller: controller);
      await controller.setQuery(HealthTimelineQuery(dogId: 'dog-a'));
      await tester.pump();

      expect(find.text('HOJE'), findsOneWidget);
      expect(find.text('ONTEM'), findsOneWidget);
      expect(find.text('10 JUL 2026'), findsOneWidget);
      expect(find.text('Hoje item'), findsOneWidget);
      expect(find.text('Ontem item'), findsOneWidget);
      expect(find.text('Histórico item'), findsOneWidget);
    });
  });

  group('tipos e status', () {
    testWidgets('consultation vaccination weight meal', (tester) async {
      final (controller, source) = buildController();
      source.enqueuePage(
        pageOf([
          entry(
            id: '1',
            type: HealthTimelineType.consultation,
            title: 'Consulta',
            occurredAt: DateTime(2026, 7, 16, 12),
          ),
          entry(
            id: '2',
            type: HealthTimelineType.vaccination,
            title: 'Vacina',
            occurredAt: DateTime(2026, 7, 16, 11),
          ),
          entry(
            id: '3',
            type: HealthTimelineType.weight,
            title: '29,8 kg',
            occurredAt: DateTime(2026, 7, 16, 10),
          ),
          entry(
            id: '4',
            type: HealthTimelineType.meal,
            title: 'Almoço',
            occurredAt: DateTime(2026, 7, 16, 9),
          ),
        ]),
      );
      await pumpTimeline(tester, controller: controller);
      await controller.setQuery(HealthTimelineQuery(dogId: 'dog-a'));
      await tester.pump();

      expect(find.text('CONSULTA VETERINÁRIA'), findsOneWidget);
      expect(find.text('VACINAÇÃO'), findsOneWidget);
      expect(find.text('PESAGEM'), findsOneWidget);
      expect(find.text('ALIMENTAÇÃO'), findsOneWidget);
    });

    testWidgets('tipo desconhecido mostra label neutra', (tester) async {
      final (controller, source) = buildController();
      source.enqueuePage(
        pageOf([
          entry(
            id: 'u1',
            typeRaw: 'future_procedure_v9',
            title: 'Procedimento novo',
            occurredAt: DateTime(2026, 7, 16, 8),
          ),
        ]),
      );
      await pumpTimeline(tester, controller: controller);
      await controller.setQuery(HealthTimelineQuery(dogId: 'dog-a'));
      await tester.pump();

      expect(
        find.text(HealthTimelineUserCopy.unknownTypeLabel),
        findsOneWidget,
      );
      expect(find.textContaining('future_procedure'), findsNothing);
      expect(find.textContaining('unknown'), findsNothing);
      expect(find.text('Procedimento novo'), findsOneWidget);
    });

    testWidgets('cancelled permanece visível com label', (tester) async {
      final (controller, source) = buildController();
      source.enqueuePage(
        pageOf([
          entry(
            id: 'x1',
            title: 'Consulta cancelada',
            status: HealthTimelineEntryStatus.cancelled,
            occurredAt: DateTime(2026, 7, 16, 8),
          ),
        ]),
      );
      await pumpTimeline(tester, controller: controller);
      await controller.setQuery(HealthTimelineQuery(dogId: 'dog-a'));
      await tester.pump();

      expect(find.text('Consulta cancelada'), findsOneWidget);
      expect(find.text(HealthTimelineUserCopy.cancelledLabel), findsOneWidget);
      // Não deve parecer restrição operacional.
      expect(find.textContaining('Impacto'), findsNothing);
    });
  });

  group('metadata', () {
    testWidgets('professional recordedBy attachments amendments impact', (
      tester,
    ) async {
      final (controller, source) = buildController();
      source.enqueuePage(
        pageOf([
          entry(
            id: 'm1',
            title: 'Entrada completa',
            occurredAt: DateTime(2026, 7, 16, 14, 0),
            professional: const ProfessionalIdentitySummary(
              name: 'Carlos Mendes',
              specialty: 'Clínica',
            ),
            recordedBy: RecordedBy(
              uid: 'u1',
              name: 'GCM Ragonha',
              internalRole: 'condutor',
            ),
            hasAttachments: true,
            attachmentCount: 2,
            amendments: HealthTimelineAmendmentMetadata(
              hasAmendments: true,
              amendmentCount: 2,
            ),
            operationalImpact: OperationalImpact(
              level: OperationalImpactLevel.medium,
              description: 'Repouso relativo',
            ),
          ),
        ]),
      );
      await pumpTimeline(tester, controller: controller);
      await controller.setQuery(HealthTimelineQuery(dogId: 'dog-a'));
      await tester.pump();

      expect(find.textContaining('Carlos Mendes'), findsOneWidget);
      expect(find.textContaining('Clínica'), findsOneWidget);
      expect(find.text('Registrado por GCM Ragonha'), findsOneWidget);
      expect(find.text('2 anexos'), findsOneWidget);
      expect(find.text('2 adendos'), findsOneWidget);
      expect(find.textContaining('Impacto médio'), findsOneWidget);
      expect(find.textContaining('Repouso relativo'), findsOneWidget);
    });

    testWidgets('não inventa Dr. ou CRMV', (tester) async {
      final (controller, source) = buildController();
      source.enqueuePage(
        pageOf([
          entry(
            id: 'p1',
            title: 'Sem título honorífico',
            professional: const ProfessionalIdentitySummary(name: 'Ana Souza'),
            occurredAt: DateTime(2026, 7, 16, 12),
          ),
        ]),
      );
      await pumpTimeline(tester, controller: controller);
      await controller.setQuery(HealthTimelineQuery(dogId: 'dog-a'));
      await tester.pump();

      expect(find.textContaining('Ana Souza'), findsOneWidget);
      expect(find.textContaining('Dr.'), findsNothing);
      expect(find.textContaining('CRMV'), findsNothing);
    });
  });

  group('refresh', () {
    testWidgets('pull-to-refresh aciona controller', (tester) async {
      final (controller, source) = buildController();
      source.enqueuePage(
        pageOf([
          entry(
            id: 'r1',
            title: 'Item A',
            occurredAt: DateTime(2026, 7, 16, 10),
          ),
        ]),
      );
      await pumpTimeline(tester, controller: controller);
      await controller.setQuery(HealthTimelineQuery(dogId: 'dog-a'));
      await tester.pump();
      expect(find.text('Item A'), findsOneWidget);

      source.enqueuePage(
        pageOf([
          entry(
            id: 'r2',
            title: 'Item B',
            occurredAt: DateTime(2026, 7, 16, 11),
          ),
        ]),
      );

      await tester.fling(
        find.byType(Scrollable).first,
        const Offset(0, 400),
        1000,
      );
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      await tester.pumpAndSettle();

      expect(find.text('Item B'), findsOneWidget);
      expect(source.requests.length, greaterThanOrEqualTo(2));
    });

    testWidgets('refresh error preserva lista e mostra banner', (tester) async {
      final (controller, source) = buildController();
      source.enqueuePage(
        pageOf([
          entry(
            id: 'keep',
            title: 'Permanente',
            occurredAt: DateTime(2026, 7, 16, 10),
          ),
        ]),
      );
      await pumpTimeline(tester, controller: controller);
      await controller.setQuery(HealthTimelineQuery(dogId: 'dog-a'));
      await tester.pump();

      source.enqueueError(const HealthTimelineSourceException('refresh fail'));
      await controller.refresh();
      await tester.pump();

      expect(find.text('Permanente'), findsOneWidget);
      expect(find.byType(HealthTimelineRefreshBanner), findsOneWidget);
      expect(find.text(HealthTimelineUserCopy.refreshError), findsOneWidget);
      expect(find.byKey(const ValueKey('timeline-data')), findsOneWidget);
    });

    testWidgets('refresh offline preserva lista e banner offline', (
      tester,
    ) async {
      final (controller, source) = buildController();
      source.enqueuePage(
        pageOf([
          entry(
            id: 'keep2',
            title: 'Cache local',
            occurredAt: DateTime(2026, 7, 16, 10),
          ),
        ]),
      );
      await pumpTimeline(tester, controller: controller);
      await controller.setQuery(HealthTimelineQuery(dogId: 'dog-a'));
      await tester.pump();

      source.enqueueOffline('no net');
      await controller.refresh();
      await tester.pump();

      expect(find.text('Cache local'), findsOneWidget);
      expect(find.text(HealthTimelineUserCopy.refreshOffline), findsOneWidget);
    });

    testWidgets('refresh em andamento mantém lista', (tester) async {
      final (controller, source) = buildController();
      source.enqueuePage(
        pageOf([
          entry(
            id: 'vis',
            title: 'Visível durante refresh',
            occurredAt: DateTime(2026, 7, 16, 10),
          ),
        ]),
      );
      await pumpTimeline(tester, controller: controller);
      await controller.setQuery(HealthTimelineQuery(dogId: 'dog-a'));
      await tester.pump();

      source.holdResponses = true;
      final refresh = controller.refresh();
      await tester.pump();

      expect(find.text('Visível durante refresh'), findsOneWidget);
      expect(find.byType(LinearProgressIndicator), findsWidgets);

      source.completeNext(
        pageOf([
          entry(
            id: 'vis',
            title: 'Visível durante refresh',
            occurredAt: DateTime(2026, 7, 16, 10),
          ),
        ]),
      );
      await refresh;
      await tester.pump();
    });
  });

  group('load more', () {
    testWidgets('botão carregar mais e progress', (tester) async {
      final (controller, source) = buildController();
      source.enqueuePage(
        pageOf([
          entry(
            id: 'p1',
            title: 'Página 1',
            occurredAt: DateTime(2026, 7, 16, 12),
          ),
        ], nextCursorToken: 'c1'),
      );
      await pumpTimeline(tester, controller: controller);
      await controller.setQuery(HealthTimelineQuery(dogId: 'dog-a'));
      await tester.pump();

      expect(find.textContaining('CARREGAR MAIS'), findsOneWidget);

      source.holdResponses = true;
      await tester.tap(find.textContaining('CARREGAR MAIS'));
      await tester.pump();

      expect(find.text(HealthTimelineUserCopy.loadingMore), findsOneWidget);
      expect(find.text('Página 1'), findsOneWidget);

      source.completeNext(
        pageOf([
          entry(
            id: 'p2',
            title: 'Página 2',
            occurredAt: DateTime(2026, 7, 15, 10),
          ),
        ]),
      );
      await tester.pumpAndSettle();
      expect(find.text('Página 2'), findsOneWidget);
    });

    testWidgets('load more error + retry', (tester) async {
      final (controller, source) = buildController();
      source.enqueuePage(
        pageOf([
          entry(id: 'a', title: 'Base', occurredAt: DateTime(2026, 7, 16, 12)),
        ], nextCursorToken: 'c1'),
      );
      await pumpTimeline(tester, controller: controller);
      await controller.setQuery(HealthTimelineQuery(dogId: 'dog-a'));
      await tester.pump();

      source.enqueueError(const HealthTimelineSourceException('page2 fail'));
      await tester.tap(find.textContaining('CARREGAR MAIS'));
      await tester.pumpAndSettle();

      expect(find.text('Base'), findsOneWidget);
      expect(find.text(HealthTimelineUserCopy.loadMoreError), findsOneWidget);

      source.enqueuePage(
        pageOf([
          entry(
            id: 'b',
            title: 'Mais itens',
            occurredAt: DateTime(2026, 7, 14, 9),
          ),
        ]),
      );
      await tester.tap(find.text(HealthTimelineUserCopy.retry));
      await tester.pumpAndSettle();

      expect(find.text('Mais itens'), findsOneWidget);
    });

    testWidgets('hasMore false não mostra carregar mais', (tester) async {
      final (controller, source) = buildController();
      source.enqueuePage(
        pageOf([
          entry(
            id: 'only',
            title: 'Único',
            occurredAt: DateTime(2026, 7, 16, 12),
          ),
        ], hasMore: false),
      );
      await pumpTimeline(tester, controller: controller);
      await controller.setQuery(HealthTimelineQuery(dogId: 'dog-a'));
      await tester.pump();

      expect(find.textContaining('CARREGAR MAIS'), findsNothing);
    });
  });

  group('interação', () {
    testWidgets('onEntryTap entrega entry', (tester) async {
      final (controller, source) = buildController();
      HealthTimelineEntryView? tapped;
      source.enqueuePage(
        pageOf([
          entry(
            id: 'tap-1',
            title: 'Clicável',
            occurredAt: DateTime(2026, 7, 16, 12),
          ),
        ]),
      );
      await pumpTimeline(
        tester,
        controller: controller,
        onEntryTap: (e) => tapped = e,
      );
      await controller.setQuery(HealthTimelineQuery(dogId: 'dog-a'));
      await tester.pump();

      await tester.tap(find.text('Clicável'));
      await tester.pump();
      expect(tapped?.id, 'tap-1');
    });

    testWidgets('sem onEntryTap não usa InkWell no card', (tester) async {
      final (controller, source) = buildController();
      source.enqueuePage(
        pageOf([
          entry(
            id: 'n1',
            title: 'Não interativo',
            occurredAt: DateTime(2026, 7, 16, 12),
          ),
        ]),
      );
      await pumpTimeline(tester, controller: controller);
      await controller.setQuery(HealthTimelineQuery(dogId: 'dog-a'));
      await tester.pump();

      final card = find.byType(HealthTimelineEntryCard);
      expect(card, findsOneWidget);
      // Card sem callback não encapsula InkWell próprio.
      expect(
        find.descendant(of: card, matching: find.byType(InkWell)),
        findsNothing,
      );
      expect(find.byIcon(Icons.chevron_right_rounded), findsNothing);
    });

    testWidgets('onFilterRequested', (tester) async {
      final (controller, source) = buildController();
      var filters = 0;
      source.enqueuePage(pageOf([]));
      await pumpTimeline(
        tester,
        controller: controller,
        onFilterRequested: () => filters++,
      );
      await controller.setQuery(HealthTimelineQuery(dogId: 'dog-a'));
      await tester.pump();

      await tester.tap(find.text(HealthTimelineUserCopy.filterAction));
      await tester.pump();
      expect(filters, 1);
    });
  });

  group('responsividade', () {
    for (final width in [360.0, 390.0, 430.0]) {
      testWidgets('largura $width sem overflow com textos longos', (
        tester,
      ) async {
        final (controller, source) = buildController();
        source.enqueuePage(
          pageOf([
            entry(
              id: 'long',
              type: HealthTimelineType.consultation,
              title:
                  'Avaliação clínica detalhada por claudicação intermitente no membro pélvico esquerdo após treinamento de faro',
              subtitle:
                  'Restrição operacional temporária por cinco dias com reavaliação programada e observação de marcha em superfície irregular',
              professional: const ProfessionalIdentitySummary(
                name:
                    'Profissional com nome bastante extenso para validar quebra de linha',
                specialty:
                    'Especialidade clínica com descrição longa e detalhada',
              ),
              recordedBy: RecordedBy(
                uid: 'u-long',
                name: 'GCM com nome operacional extenso para layout',
                internalRole: 'condutor',
              ),
              hasAttachments: true,
              attachmentCount: 3,
              amendments: HealthTimelineAmendmentMetadata(
                hasAmendments: true,
                amendmentCount: 2,
              ),
              operationalImpact: OperationalImpact(
                level: OperationalImpactLevel.high,
                description:
                    'Restrição de emprego operacional em campo aberto e apoio a ocorrências de longa duração',
              ),
              occurredAt: DateTime(2026, 7, 16, 14, 32),
            ),
            entry(
              id: 'cancel-long',
              title:
                  'Registro cancelado com título longo para validação visual',
              status: HealthTimelineEntryStatus.cancelled,
              typeRaw: 'future_procedure_v9',
              occurredAt: DateTime(2026, 7, 15, 9, 1),
            ),
          ]),
        );
        await pumpTimeline(
          tester,
          controller: controller,
          width: width,
          height: 1600,
          onEntryTap: (_) {},
          onFilterRequested: () {},
          activeFilterCount: 1,
          hasActiveFilters: true,
          contextLabel: 'Bono com nome longo de contexto',
        );
        await controller.setQuery(HealthTimelineQuery(dogId: 'dog-a'));
        await tester.pump();

        expect(tester.takeException(), isNull);
        expect(
          find.text(HealthTimelineUserCopy.cancelledLabel),
          findsOneWidget,
        );
        expect(
          find.text(HealthTimelineUserCopy.unknownTypeLabel),
          findsOneWidget,
        );
      });
    }
  });
}
