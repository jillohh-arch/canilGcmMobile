import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:canil_gcm/features/health/domain/health_v1_enums_ext.dart';
import 'package:canil_gcm/features/health/domain/health_v1_models.dart';
import 'package:canil_gcm/features/health/domain/health_v1_value_objects.dart';
import 'package:canil_gcm/features/health/presentation/timeline/health_timeline_controller.dart';
import 'package:canil_gcm/features/health/presentation/timeline/health_timeline_entry_view.dart';
import 'package:canil_gcm/features/health/presentation/timeline/health_timeline_grouping.dart';
import 'package:canil_gcm/features/health/presentation/timeline/health_timeline_query.dart';
import 'package:canil_gcm/features/health/presentation/timeline/health_timeline_source.dart';
import 'package:canil_gcm/features/health/presentation/timeline/health_timeline_state.dart';
import 'package:canil_gcm/features/health/presentation/timeline/widgets/health_timeline_entry_card.dart';
import 'package:canil_gcm/features/health/presentation/timeline/widgets/health_timeline_formatters.dart';
import 'package:canil_gcm/features/health/presentation/timeline/widgets/health_timeline_type_visuals.dart';
import 'package:canil_gcm/features/health/presentation/timeline/widgets/health_timeline_user_copy.dart';
import 'package:canil_gcm/features/health/presentation/timeline/widgets/health_timeline_view.dart';

import 'fake_health_timeline_source.dart';
import 'timeline_test_helpers.dart';

void main() {
  setUpAll(() {
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  final fixedNow = DateTime(2026, 7, 16, 14, 0);

  void configureSurface(WidgetTester tester, {double width = 390}) {
    tester.view.physicalSize = Size(width, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  Future<void> pumpTimeline(
    WidgetTester tester, {
    required HealthTimelineController controller,
    double width = 390,
    ValueChanged<HealthTimelineEntryView>? onEntryTap,
    VoidCallback? onFilterRequested,
    int? activeFilterCount,
    bool? hasActiveFilters,
    DateTime Function()? now,
  }) async {
    configureSurface(tester, width: width);
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(size: Size(width, 1600)),
          child: Scaffold(
            backgroundColor: const Color(0xFF050D10),
            body: SizedBox(
              width: width,
              height: 1600,
              child: HealthTimelineView(
                controller: controller,
                onEntryTap: onEntryTap,
                onFilterRequested: onFilterRequested,
                activeFilterCount: activeFilterCount,
                hasActiveFilters: hasActiveFilters,
                contextLabel: 'Bono',
                now: now ?? () => fixedNow,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  group('sanitização hostil', () {
    final hostiles = <String>[
      'FirebaseException: permission-denied',
      'failed-precondition The query requires an index',
      'https://firestore.googleapis.com/v1/projects/x',
      'firestore.googleapis.com/v1/projects/x/databases',
      'Stack overflow at package:canil_gcm/features/health/x.dart:12',
      'dogs/abc/health_events/xyz collection path',
      'PERMISSION_DENIED on DocumentSnapshot',
      'A' * 200,
    ];

    for (final raw in hostiles) {
      testWidgets(
        'error global não vaza: ${raw.substring(0, raw.length.clamp(0, 40))}',
        (tester) async {
          final source = FakeHealthTimelineSource()
            ..enqueueError(HealthTimelineSourceException(raw));
          final controller = HealthTimelineController(source: source);
          addTearDown(controller.dispose);

          await pumpTimeline(tester, controller: controller);
          await controller.setQuery(HealthTimelineQuery(dogId: 'dog-a'));
          await tester.pump();

          expect(find.text(raw), findsNothing);
          expect(find.textContaining('Firebase'), findsNothing);
          expect(find.textContaining('firestore'), findsNothing);
          expect(find.textContaining('permission-denied'), findsNothing);
          expect(find.textContaining('googleapis'), findsNothing);
          expect(find.textContaining('dogs/'), findsNothing);
          expect(
            find.text(HealthTimelineUserCopy.errorMessage),
            findsOneWidget,
          );
        },
      );
    }

    test('sanitizeMessage unitário cobre padrões técnicos', () {
      for (final raw in hostiles) {
        final out = HealthTimelineUserCopy.sanitizeMessage(
          raw,
          fallback: HealthTimelineUserCopy.errorMessage,
        );
        expect(out, HealthTimelineUserCopy.errorMessage);
      }
      expect(
        HealthTimelineUserCopy.sanitizeMessage(
          'Falha temporária de rede',
          fallback: 'x',
        ),
        'Falha temporária de rede',
      );
    });
  });

  group('operational impact — escala de domínio', () {
    test('labels 1:1 com enum; none não gera texto de ausência', () {
      for (final level in OperationalImpactLevel.values) {
        if (level == OperationalImpactLevel.none) continue;
        final impact = OperationalImpact(
          level: level,
          description: 'Descrição $level',
        );
        final label = HealthTimelineFormatters.operationalImpactLabel(impact);
        expect(label, contains('Descrição'));
        expect(label.toLowerCase(), isNot(contains('sem impacto')));
        expect(label, contains('Impacto'));
      }
    });

    testWidgets('null e none não renderizam impacto', (tester) async {
      final source = FakeHealthTimelineSource()
        ..enqueuePage(
          pageOf([
            entry(
              id: 'no-impact',
              title: 'Sem metadata de impacto',
              occurredAt: DateTime(2026, 7, 16, 10),
            ),
            entry(
              id: 'none-level',
              title: 'Level none',
              operationalImpact: OperationalImpact(
                level: OperationalImpactLevel.none,
                description: 'Sem restrições emitidas',
              ),
              occurredAt: DateTime(2026, 7, 16, 9),
            ),
          ]),
        );
      final controller = HealthTimelineController(source: source);
      addTearDown(controller.dispose);
      await pumpTimeline(tester, controller: controller);
      await controller.setQuery(HealthTimelineQuery(dogId: 'dog-a'));
      await tester.pump();

      expect(find.textContaining('Impacto'), findsNothing);
      expect(find.textContaining('Sem impacto'), findsNothing);
      // description de none não deve virar status inventado
      expect(find.textContaining('Sem restrições emitidas'), findsNothing);
    });

    testWidgets('cada nível real aparece com description', (tester) async {
      final levels = [
        OperationalImpactLevel.low,
        OperationalImpactLevel.medium,
        OperationalImpactLevel.high,
        OperationalImpactLevel.critical,
      ];
      final source = FakeHealthTimelineSource()
        ..enqueuePage(
          pageOf([
            for (var i = 0; i < levels.length; i++)
              entry(
                id: 'imp-$i',
                title: 'Item $i',
                operationalImpact: OperationalImpact(
                  level: levels[i],
                  description: 'Desc nível ${levels[i].wireName}',
                ),
                occurredAt: DateTime(2026, 7, 16, 12 - i),
              ),
          ]),
        );
      final controller = HealthTimelineController(source: source);
      addTearDown(controller.dispose);
      await pumpTimeline(tester, controller: controller);
      await controller.setQuery(HealthTimelineQuery(dogId: 'dog-a'));
      await tester.pump();

      expect(find.textContaining('Impacto baixo'), findsOneWidget);
      expect(find.textContaining('Impacto médio'), findsOneWidget);
      expect(find.textContaining('Impacto alto'), findsOneWidget);
      expect(find.textContaining('Impacto crítico'), findsOneWidget);
      expect(find.textContaining('Desc nível low'), findsOneWidget);
    });
  });

  group('14 tipos oficiais', () {
    test('table-driven: todos resolvem label sem raw técnico', () {
      for (final type in HealthTimelineType.values) {
        final visual = HealthTimelineTypeVisuals.resolve(
          HealthTimelineTypeView.known(type),
        );
        expect(visual.label, isNotEmpty);
        // Label amigável em caixa alta, não o wireName bruto isolado.
        expect(visual.label, isNot(equals(type.wireName)));
        expect(visual.label, isNot(equals(type.name)));
        expect(visual.label.contains('_'), isFalse);
      }
    });

    testWidgets('todos os 14 tipos renderizam sem exception', (tester) async {
      final types = HealthTimelineType.values;
      final source = FakeHealthTimelineSource()
        ..enqueuePage(
          pageOf([
            for (var i = 0; i < types.length; i++)
              entry(
                id: 't-$i',
                type: types[i],
                title: 'Título ${types[i].wireName}',
                occurredAt: DateTime(
                  2026,
                  7,
                  16,
                  20,
                ).subtract(Duration(hours: i)),
              ),
          ]),
        );
      final controller = HealthTimelineController(source: source);
      addTearDown(controller.dispose);
      await pumpTimeline(tester, controller: controller, width: 360);
      await controller.setQuery(HealthTimelineQuery(dogId: 'dog-a'));
      await tester.pump();

      expect(tester.takeException(), isNull);
      for (final type in types) {
        final label = HealthTimelineTypeVisuals.resolve(
          HealthTimelineTypeView.known(type),
        ).label;
        expect(find.text(label), findsWidgets);
      }
    });
  });

  group('unknown type hostil', () {
    final raws = [
      'future_procedure_v9',
      'unknown',
      '<FIREBASE_PATH>',
      'dogs/x/y/z',
      '🚀' * 20,
      'A' * 120,
    ];

    for (final raw in raws) {
      testWidgets('raw oculto: $raw', (tester) async {
        final source = FakeHealthTimelineSource()
          ..enqueuePage(
            pageOf([
              entry(
                id: 'u',
                typeRaw: raw,
                title: 'Item desconhecido',
                occurredAt: DateTime(2026, 7, 16, 8),
              ),
            ]),
          );
        final controller = HealthTimelineController(source: source);
        addTearDown(controller.dispose);
        await pumpTimeline(tester, controller: controller, width: 360);
        await controller.setQuery(HealthTimelineQuery(dogId: 'dog-a'));
        await tester.pump();

        expect(
          find.text(HealthTimelineUserCopy.unknownTypeLabel),
          findsOneWidget,
        );
        expect(
          find.textContaining(raw.length > 40 ? raw.substring(0, 40) : raw),
          findsNothing,
        );
        expect(tester.takeException(), isNull);
      });
    }
  });

  group('cancelled + metadata', () {
    testWidgets('cancelled com impact/anexos/adendos/professional', (
      tester,
    ) async {
      final source = FakeHealthTimelineSource()
        ..enqueuePage(
          pageOf([
            entry(
              id: 'c',
              title: 'Consulta cancelada com metadata',
              status: HealthTimelineEntryStatus.cancelled,
              professional: const ProfessionalIdentitySummary(
                name: 'Carlos Mendes',
                specialty: 'Clínica',
              ),
              hasAttachments: true,
              attachmentCount: 2,
              amendments: HealthTimelineAmendmentMetadata(
                hasAmendments: true,
                amendmentCount: 1,
              ),
              operationalImpact: OperationalImpact(
                level: OperationalImpactLevel.high,
                description: 'Repouso',
              ),
              occurredAt: DateTime(2026, 7, 16, 11),
            ),
          ]),
        );
      final controller = HealthTimelineController(source: source);
      addTearDown(controller.dispose);
      await pumpTimeline(tester, controller: controller);
      await controller.setQuery(HealthTimelineQuery(dogId: 'dog-a'));
      await tester.pump();

      expect(find.text('Consulta cancelada com metadata'), findsOneWidget);
      expect(find.text(HealthTimelineUserCopy.cancelledLabel), findsOneWidget);
      expect(find.textContaining('Carlos Mendes'), findsOneWidget);
      expect(find.text('2 anexos'), findsOneWidget);
      expect(find.text('Adendo registrado'), findsOneWidget);
      expect(find.textContaining('Impacto alto'), findsOneWidget);
    });
  });

  group('100 itens / lazy / performance estrutural', () {
    testWidgets('100 entries multi-dia sem exception', (tester) async {
      final items = <HealthTimelineEntryView>[
        for (var i = 0; i < 100; i++)
          entry(
            id: 'big-$i',
            type:
                HealthTimelineType.values[i % HealthTimelineType.values.length],
            title: i.isEven ? 'Título médio $i' : 'Título longo $i ${'x' * 80}',
            subtitle: i % 3 == 0 ? 'Subtitle ${'y' * 60}' : null,
            professional: i % 4 == 0
                ? ProfessionalIdentitySummary(name: 'Prof $i')
                : null,
            hasAttachments: i % 5 == 0,
            attachmentCount: i % 5 == 0 ? 2 : null,
            occurredAt: DateTime(
              2026,
              7,
              16,
              23,
            ).subtract(Duration(hours: i * 3)),
          ),
      ];
      final source = FakeHealthTimelineSource()
        ..enqueuePage(pageOf(items, nextCursorToken: 'more'));
      final controller = HealthTimelineController(source: source);
      addTearDown(controller.dispose);

      await pumpTimeline(tester, controller: controller, width: 360);
      await controller.setQuery(HealthTimelineQuery(dogId: 'dog-a'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(tester.takeException(), isNull);
      expect(find.byType(ListView), findsWidgets);
      expect(controller.state, isA<HealthTimelineData>());
      expect((controller.state as HealthTimelineData).hasMore, isTrue);
      expect((controller.state as HealthTimelineData).items.length, 100);

      // Scroll até o rodapé (lazy list — load more fora do viewport inicial)
      await tester.scrollUntilVisible(
        find.textContaining('CARREGAR MAIS'),
        400,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.textContaining('CARREGAR MAIS'), findsOneWidget);
    });
  });

  group('refresh + load more visual', () {
    testWidgets('durante refresh não mostra CARREGAR MAIS', (tester) async {
      final source = FakeHealthTimelineSource()
        ..enqueuePage(
          pageOf([
            entry(
              id: 'a',
              title: 'Base',
              occurredAt: DateTime(2026, 7, 16, 12),
            ),
          ], nextCursorToken: 'c1'),
        );
      final controller = HealthTimelineController(source: source);
      addTearDown(controller.dispose);
      await pumpTimeline(tester, controller: controller);
      await controller.setQuery(HealthTimelineQuery(dogId: 'dog-a'));
      await tester.pump();
      expect(find.textContaining('CARREGAR MAIS'), findsOneWidget);

      source.holdResponses = true;
      final refresh = controller.refresh();
      await tester.pump();

      expect(find.text('Base'), findsOneWidget);
      expect(find.byType(LinearProgressIndicator), findsWidgets);
      expect(find.textContaining('CARREGAR MAIS'), findsNothing);

      source.completeNext(
        pageOf([
          entry(id: 'a', title: 'Base', occurredAt: DateTime(2026, 7, 16, 12)),
        ], nextCursorToken: 'c1'),
      );
      await refresh;
      await tester.pump();
      expect(find.textContaining('CARREGAR MAIS'), findsOneWidget);
    });
  });

  group('filtros edge', () {
    testWidgets('count negativo não vira badge', (tester) async {
      final source = FakeHealthTimelineSource()..enqueuePage(pageOf([]));
      final controller = HealthTimelineController(source: source);
      addTearDown(controller.dispose);
      await pumpTimeline(
        tester,
        controller: controller,
        hasActiveFilters: true,
        activeFilterCount: -1,
        onFilterRequested: () {},
      );
      await controller.setQuery(HealthTimelineQuery(dogId: 'dog-a'));
      await tester.pump();

      expect(find.text('-1'), findsNothing);
      expect(
        find.text(HealthTimelineUserCopy.emptyWithFiltersMessage),
        findsOneWidget,
      );
    });

    testWidgets('hasActiveFilters true + count 0: copy filtros, sem badge 0', (
      tester,
    ) async {
      final source = FakeHealthTimelineSource()..enqueuePage(pageOf([]));
      final controller = HealthTimelineController(source: source);
      addTearDown(controller.dispose);
      await pumpTimeline(
        tester,
        controller: controller,
        hasActiveFilters: true,
        activeFilterCount: 0,
        onFilterRequested: () {},
      );
      await controller.setQuery(HealthTimelineQuery(dogId: 'dog-a'));
      await tester.pump();

      expect(
        find.text(HealthTimelineUserCopy.emptyWithFiltersMessage),
        findsOneWidget,
      );
      // Badge numérico "0" não deve aparecer isolado no header de filtros
      expect(find.text('0'), findsNothing);
    });

    testWidgets('onFilterRequested null: sem botão Filtros', (tester) async {
      final source = FakeHealthTimelineSource()
        ..enqueuePage(
          pageOf([
            entry(
              id: 'x',
              title: 'Item',
              occurredAt: DateTime(2026, 7, 16, 10),
            ),
          ]),
        );
      final controller = HealthTimelineController(source: source);
      addTearDown(controller.dispose);
      await pumpTimeline(tester, controller: controller);
      await controller.setQuery(HealthTimelineQuery(dogId: 'dog-a'));
      await tester.pump();

      expect(find.text(HealthTimelineUserCopy.filterAction), findsNothing);
    });
  });

  group('datas / timezone / now', () {
    test('HOJE/ONTEM alinhados a groupTimelineByDay + now injetado', () {
      final now = DateTime(2026, 7, 16, 0, 30);
      final todayEntry = entry(
        id: 't',
        occurredAt: DateTime(2026, 7, 16, 0, 1),
        title: 'hoje',
      );
      final yesterdayEntry = entry(
        id: 'y',
        occurredAt: DateTime(2026, 7, 15, 23, 59),
        title: 'ontem',
      );
      final older = entry(
        id: 'o',
        occurredAt: DateTime(2026, 7, 14, 12),
        title: 'antigo',
      );
      final groups = groupTimelineByDay([todayEntry, yesterdayEntry, older]);
      expect(groups.length, 3);
      expect(
        HealthTimelineFormatters.dayGroupLabel(groups[0].date, now: now),
        'HOJE',
      );
      expect(
        HealthTimelineFormatters.dayGroupLabel(groups[1].date, now: now),
        'ONTEM',
      );
      expect(
        HealthTimelineFormatters.dayGroupLabel(groups[2].date, now: now),
        '14 JUL 2026',
      );
    });

    test('UTC que muda de dia no toLocal mantém label == grupo', () {
      // 2026-07-16 02:00 UTC → local depende do offset; usamos toLocal real
      // e garantimos que dayGroupLabel usa o mesmo day normalizado do grupo.
      final utc = DateTime.utc(2026, 7, 16, 2, 0);
      final e = entry(id: 'utc', occurredAt: utc, title: 'utc');
      final groups = groupTimelineByDay([e]);
      final day = groups.single.date;
      final label = HealthTimelineFormatters.dayGroupLabel(
        day,
        now: day.add(const Duration(hours: 12)),
      );
      // Label é HOJE relativo ao now no mesmo dia do grupo, ou data fixa.
      expect(label == 'HOJE' || label.contains('${day.year}'), isTrue);
      // Grupo date é meia-noite local do occurredAt localizado
      final local = utc.toLocal();
      expect(day.year, local.year);
      expect(day.month, local.month);
      expect(day.day, local.day);
    });

    test('formato histórico estável sem locale de sistema', () {
      expect(
        HealthTimelineFormatters.dayGroupLabel(
          DateTime(2026, 1, 5),
          now: DateTime(2026, 7, 16),
        ),
        '05 JAN 2026',
      );
    });
  });

  group('callbacks e a11y', () {
    testWidgets('um tap = uma invocação; sem InkWell quando null', (
      tester,
    ) async {
      var taps = 0;
      HealthTimelineEntryView? last;
      final source = FakeHealthTimelineSource()
        ..enqueuePage(
          pageOf([
            entry(
              id: 'tap',
              title: 'Clicável único',
              occurredAt: DateTime(2026, 7, 16, 10),
            ),
          ]),
        );
      final controller = HealthTimelineController(source: source);
      addTearDown(controller.dispose);
      await pumpTimeline(
        tester,
        controller: controller,
        onEntryTap: (e) {
          taps++;
          last = e;
        },
      );
      await controller.setQuery(HealthTimelineQuery(dogId: 'dog-a'));
      await tester.pump();

      await tester.tap(find.text('Clicável único'));
      await tester.pump();
      expect(taps, 1);
      expect(last?.id, 'tap');

      // Card com callback tem exatamente um InkWell no card.
      final card = find.byType(HealthTimelineEntryCard);
      expect(
        find.descendant(of: card, matching: find.byType(InkWell)),
        findsOneWidget,
      );
    });

    testWidgets('semantics do card anuncia CANCELADO e impacto', (
      tester,
    ) async {
      final source = FakeHealthTimelineSource()
        ..enqueuePage(
          pageOf([
            entry(
              id: 'sem',
              title: 'A11y item',
              status: HealthTimelineEntryStatus.cancelled,
              operationalImpact: OperationalImpact(
                level: OperationalImpactLevel.medium,
                description: 'Repouso relativo',
              ),
              occurredAt: DateTime(2026, 7, 16, 10),
            ),
          ]),
        );
      final controller = HealthTimelineController(source: source);
      addTearDown(controller.dispose);
      await pumpTimeline(tester, controller: controller);
      await controller.setQuery(HealthTimelineQuery(dogId: 'dog-a'));
      await tester.pump();

      final handle = tester.ensureSemantics();
      try {
        final node = tester.getSemantics(find.byType(HealthTimelineEntryCard));
        final label = node.label;
        expect(label, contains('CANCELADO'));
        expect(label, contains('A11y item'));
        expect(label, contains('Impacto'));
        expect(label, contains('Repouso relativo'));
      } finally {
        handle.dispose();
      }
    });
  });

  group('metadata extrema 360', () {
    testWidgets('textos longos + metadata sem overflow', (tester) async {
      final source = FakeHealthTimelineSource()
        ..enqueuePage(
          pageOf([
            entry(
              id: 'max',
              type: HealthTimelineType.consultation,
              title: 'T' * 220,
              subtitle: 'S' * 520,
              professional: ProfessionalIdentitySummary(
                name: 'P' * 80,
                specialty: 'E' * 80,
              ),
              recordedBy: RecordedBy(
                uid: 'u',
                name: 'R' * 80,
                internalRole: 'condutor',
              ),
              operationalImpact: OperationalImpact(
                level: OperationalImpactLevel.critical,
                description: 'D' * 200,
              ),
              hasAttachments: true,
              attachmentCount: 9,
              amendments: HealthTimelineAmendmentMetadata(
                hasAmendments: true,
                amendmentCount: 4,
              ),
              occurredAt: DateTime(2026, 7, 16, 14, 32),
            ),
          ]),
        );
      final controller = HealthTimelineController(source: source);
      addTearDown(controller.dispose);
      await pumpTimeline(
        tester,
        controller: controller,
        width: 360,
        onEntryTap: (_) {},
      );
      await controller.setQuery(HealthTimelineQuery(dogId: 'dog-a'));
      await tester.pump();

      expect(tester.takeException(), isNull);
      expect(find.textContaining('Impacto crítico'), findsOneWidget);
      expect(find.text('9 anexos'), findsOneWidget);
      expect(find.text('4 adendos'), findsOneWidget);
      expect(find.textContaining('Dr.'), findsNothing);
      expect(find.textContaining('CRMV'), findsNothing);
    });
  });

  group('professional / recordedBy / attachments', () {
    test('recordedByLabel vazio é null', () {
      expect(HealthTimelineFormatters.recordedByLabel(''), isNull);
      expect(HealthTimelineFormatters.recordedByLabel('   '), isNull);
    });

    test('attachments respeita hasAttachments', () {
      expect(
        HealthTimelineFormatters.attachmentsLabel(
          hasAttachments: false,
          attachmentCount: 3,
        ),
        isNull,
      );
      expect(
        HealthTimelineFormatters.attachmentsLabel(
          hasAttachments: true,
          attachmentCount: null,
        ),
        'Anexo',
      );
      expect(
        HealthTimelineFormatters.attachmentsLabel(
          hasAttachments: true,
          attachmentCount: 0,
        ),
        'Anexo',
      );
    });

    test('amendments respeita flags', () {
      expect(
        HealthTimelineFormatters.amendmentsLabel(
          hasAmendments: false,
          amendmentCount: 2,
        ),
        isNull,
      );
      expect(
        HealthTimelineFormatters.amendmentsLabel(
          hasAmendments: true,
          amendmentCount: 0,
        ),
        isNull,
      );
    });
  });

  group('ListView.builder presente', () {
    testWidgets('data usa ListView (lazy builder)', (tester) async {
      final source = FakeHealthTimelineSource()
        ..enqueuePage(
          pageOf([
            entry(id: '1', title: 'A', occurredAt: DateTime(2026, 7, 16, 10)),
          ]),
        );
      final controller = HealthTimelineController(source: source);
      addTearDown(controller.dispose);
      await pumpTimeline(tester, controller: controller);
      await controller.setQuery(HealthTimelineQuery(dogId: 'dog-a'));
      await tester.pump();

      final listView = tester.widget<ListView>(find.byType(ListView).first);
      // ListView.builder usa childrenDelegate do tipo SliverChildBuilderDelegate
      expect(listView.childrenDelegate, isA<SliverChildBuilderDelegate>());
    });
  });
}
