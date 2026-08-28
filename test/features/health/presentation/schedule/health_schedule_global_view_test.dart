import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:canil_gcm/features/health/presentation/schedule/health_schedule_global_controller.dart';
import 'package:canil_gcm/features/health/presentation/schedule/health_schedule_global_grouping.dart';
import 'package:canil_gcm/features/health/presentation/schedule/health_schedule_global_view.dart';
import 'package:canil_gcm/features/health/presentation/schedule/health_schedule_source.dart';
import 'package:canil_gcm/features/health/presentation/schedule/widgets/health_schedule_item_card.dart';
import 'package:canil_gcm/features/health/presentation/schedule/widgets/health_schedule_user_copy.dart';

import 'fake_health_schedule_global_source.dart';
import 'schedule_test_helpers.dart';

/// HW-4C — UI da Agenda Global.
///
/// Estrutura sob teste: seção temporal (nível 1) → subheader por K9 (nível 2)
/// → [HealthScheduleItemCard] existente, preservado sem alteração.
void main() {
  late FakeHealthScheduleGlobalSource source;
  late HealthScheduleGlobalController controller;
  late DateTime clockNow;

  setUpAll(() {
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  setUp(() {
    source = FakeHealthScheduleGlobalSource();
    clockNow = scheduleTestNow;
    controller = HealthScheduleGlobalController(
      source: source,
      temporalPolicy: testSchedulePolicy(),
      clock: () => clockNow,
    );
  });

  tearDown(() {
    if (!controller.isDisposedForTest) controller.dispose();
  });

  HealthScheduleDogLabel labels(String dogId) => switch (dogId) {
    'dog-a' => const HealthScheduleDogLabel(name: 'Apolo'),
    'dog-b' => const HealthScheduleDogLabel(name: 'Bono'),
    _ => const HealthScheduleDogLabel(name: 'K9'),
  };

  Widget wrap(Widget child, {double width = 390}) {
    return MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(size: Size(width, 844)),
        child: Scaffold(
          body: SizedBox(width: width, height: 844, child: child),
        ),
      ),
    );
  }

  HealthScheduleGlobalView view() => HealthScheduleGlobalView(
    controller: controller,
    resolveDog: labels,
    now: () => clockNow,
    onRetry: controller.refresh,
  );

  group('lista multi-K9', () {
    testWidgets('renderiza itens de dois K9s com contexto de cada um', (
      tester,
    ) async {
      source.enqueueItems([
        scheduleItem(id: 'a1', dogId: 'dog-a'),
        scheduleItem(id: 'b1', dogId: 'dog-b'),
      ]);
      await controller.setCatalog(const ['dog-a', 'dog-b']);
      await tester.pumpWidget(wrap(view()));
      await tester.pump();

      // Contexto do K9 visível por subheader.
      expect(find.text('Apolo'), findsOneWidget);
      expect(find.text('Bono'), findsOneWidget);
      // Subheaders com chave qualificada pela seção (o mesmo cão pode
      // aparecer em várias seções, então dogId sozinho colidiria).
      expect(
        find.byKey(const ValueKey('schedule-global-dog-hoje-dog-a')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('schedule-global-dog-hoje-dog-b')),
        findsOneWidget,
      );
      // Cards existentes, um por item.
      expect(find.byType(HealthScheduleItemCard), findsNWidgets(2));
    });

    testWidgets('card compartilhado é reutilizado sem alteração', (
      tester,
    ) async {
      source.enqueueItems([scheduleItem(id: 'a1', dogId: 'dog-a')]);
      await controller.setCatalog(const ['dog-a']);
      await tester.pumpWidget(wrap(view()));
      await tester.pump();

      final card = tester.widget<HealthScheduleItemCard>(
        find.byType(HealthScheduleItemCard),
      );
      // O card não recebe ação nesta rodada (gate de leitura/integração).
      expect(card.onAction, isNull);
      expect(card.item.dogId, 'dog-a');
    });

    testWidgets('chave do card inclui dogId (unicidade multi-K9)', (
      tester,
    ) async {
      // Dois cães podem ter scheduleId igual: a chave precisa distinguir.
      source.enqueueItems([
        scheduleItem(id: 'mesmo', dogId: 'dog-a'),
        scheduleItem(id: 'mesmo', dogId: 'dog-b'),
      ]);
      await controller.setCatalog(const ['dog-a', 'dog-b']);
      await tester.pumpWidget(wrap(view()));
      await tester.pump();

      expect(
        find.byKey(const ValueKey('schedule-card-dog-a-mesmo')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('schedule-card-dog-b-mesmo')),
        findsOneWidget,
      );
    });

    testWidgets('MESMO K9 em várias seções temporais não duplica chave', (
      tester,
    ) async {
      // Caso mais comum em campo: um cão com item atrasado E item futuro.
      // O subheader dele aparece em DUAS seções — as chaves precisam ser
      // únicas na mesma ListView, senão a árvore quebra em runtime.
      source.enqueueItems([
        scheduleItem(
          id: 'atraso',
          dogId: 'dog-a',
          scheduledFor: scheduleTestNow.subtract(const Duration(days: 4)),
        ),
        scheduleItem(
          id: 'futuro',
          dogId: 'dog-a',
          scheduledFor: scheduleTestNow.add(const Duration(days: 3)),
        ),
      ]);
      await controller.setCatalog(const ['dog-a']);
      await tester.pumpWidget(wrap(view()));
      await tester.pump();

      expect(
        tester.takeException(),
        isNull,
        reason: 'chave duplicada de subheader quebra a árvore de widgets',
      );
      // Duas seções, cada uma com o subheader do mesmo cão.
      expect(
        find.text(HealthScheduleUserCopy.sectionAttention),
        findsOneWidget,
      );
      expect(find.text(HealthScheduleUserCopy.sectionUpcoming), findsOneWidget);
      expect(find.text('Apolo'), findsNWidgets(2));
      expect(find.byType(HealthScheduleItemCard), findsNWidgets(2));
    });

    testWidgets('K9 fora do catálogo aparece com rótulo neutro', (
      tester,
    ) async {
      source.enqueueItems([scheduleItem(id: 'x1', dogId: 'dog-fora')]);
      await controller.setCatalog(const ['dog-fora']);
      await tester.pumpWidget(wrap(view()));
      await tester.pump();

      expect(find.text('K9'), findsOneWidget);
      expect(find.byType(HealthScheduleItemCard), findsOneWidget);
    });
  });

  group('agrupamento temporal', () {
    testWidgets('overdue aparece na seção REQUER ATENÇÃO', (tester) async {
      source.enqueueItems([
        scheduleItem(
          id: 'atrasado',
          dogId: 'dog-a',
          scheduledFor: scheduleTestNow.subtract(const Duration(days: 3)),
        ),
      ]);
      await controller.setCatalog(const ['dog-a']);
      await tester.pumpWidget(wrap(view()));
      await tester.pump();

      expect(
        find.text(HealthScheduleUserCopy.sectionAttention),
        findsOneWidget,
      );
    });

    testWidgets('today aparece na seção HOJE', (tester) async {
      source.enqueueItems([
        scheduleItem(
          id: 'hoje',
          dogId: 'dog-a',
          scheduledFor: scheduleTestNow.add(const Duration(hours: 2)),
        ),
      ]);
      await controller.setCatalog(const ['dog-a']);
      await tester.pumpWidget(wrap(view()));
      await tester.pump();

      expect(find.text(HealthScheduleUserCopy.sectionToday), findsOneWidget);
    });

    testWidgets('upcoming aparece na seção PRÓXIMOS', (tester) async {
      source.enqueueItems([
        scheduleItem(
          id: 'proximo',
          dogId: 'dog-a',
          scheduledFor: scheduleTestNow.add(const Duration(days: 3)),
        ),
      ]);
      await controller.setCatalog(const ['dog-a']);
      await tester.pumpWidget(wrap(view()));
      await tester.pump();

      expect(find.text(HealthScheduleUserCopy.sectionUpcoming), findsOneWidget);
    });

    testWidgets('seção temporal é o primeiro nível; K9 o segundo', (
      tester,
    ) async {
      source.enqueueItems([
        scheduleItem(
          id: 'a-atraso',
          dogId: 'dog-a',
          scheduledFor: scheduleTestNow.subtract(const Duration(days: 3)),
        ),
        scheduleItem(
          id: 'b-atraso',
          dogId: 'dog-b',
          scheduledFor: scheduleTestNow.subtract(const Duration(days: 2)),
        ),
      ]);
      await controller.setCatalog(const ['dog-a', 'dog-b']);
      await tester.pumpWidget(wrap(view()));
      await tester.pump();

      // Uma seção temporal contendo dois subheaders de K9.
      expect(
        find.text(HealthScheduleUserCopy.sectionAttention),
        findsOneWidget,
      );
      expect(find.text('Apolo'), findsOneWidget);
      expect(find.text('Bono'), findsOneWidget);
    });
  });

  group('estados', () {
    testWidgets('catálogo vazio → mensagem própria, não "agenda vazia"', (
      tester,
    ) async {
      await controller.setCatalog(const []);
      await tester.pumpWidget(wrap(view()));
      await tester.pump();

      expect(
        find.byKey(const ValueKey('schedule-global-no-catalog')),
        findsOneWidget,
      );
      expect(
        find.text(HealthScheduleGlobalCopy.noCatalogTitle),
        findsOneWidget,
      );
      expect(source.callCount, 0);
    });

    testWidgets('empty legítimo → agenda em dia', (tester) async {
      source.enqueueItems(const []);
      await controller.setCatalog(const ['dog-a']);
      await tester.pumpWidget(wrap(view()));
      await tester.pump();

      expect(
        find.byKey(const ValueKey('schedule-global-empty')),
        findsOneWidget,
      );
      expect(find.text(HealthScheduleGlobalCopy.emptyTitle), findsOneWidget);
    });

    testWidgets('permission denied tem estado próprio', (tester) async {
      source.enqueueError(
        const HealthScheduleSourceException(
          'Sem permissão para a agenda do efetivo.',
          isPermissionDenied: true,
        ),
      );
      await controller.setCatalog(const ['dog-a']);
      await tester.pumpWidget(wrap(view()));
      await tester.pump();

      expect(
        find.byKey(const ValueKey('schedule-global-permission-denied')),
        findsOneWidget,
      );
      // Nunca apresentado como agenda vazia.
      expect(find.byKey(const ValueKey('schedule-global-empty')), findsNothing);
      expect(find.text(HealthScheduleGlobalCopy.emptyTitle), findsNothing);
    });

    testWidgets('erro técnico não vira empty', (tester) async {
      source.enqueueError(
        const HealthScheduleSourceException('índice ausente'),
      );
      await controller.setCatalog(const ['dog-a']);
      await tester.pumpWidget(wrap(view()));
      await tester.pump();

      expect(
        find.byKey(const ValueKey('schedule-global-error')),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('schedule-global-empty')), findsNothing);
    });

    testWidgets('offline tem estado distinto de erro técnico', (tester) async {
      source.enqueueError(
        const HealthScheduleSourceException('Sem conexão', isOffline: true),
      );
      await controller.setCatalog(const ['dog-a']);
      await tester.pumpWidget(wrap(view()));
      await tester.pump();

      expect(
        find.byKey(const ValueKey('schedule-global-offline')),
        findsOneWidget,
      );
    });

    testWidgets('loading mostra skeleton', (tester) async {
      source.holdResponses = true;
      final future = controller.setCatalog(const ['dog-a']);
      await tester.pumpWidget(wrap(view()));
      await tester.pump();

      expect(find.byType(HealthScheduleItemCard), findsNothing);

      source.completeNextItems([scheduleItem()]);
      await future;
      await tester.pump();
      expect(find.byType(HealthScheduleItemCard), findsOneWidget);
    });
  });

  group('truncated', () {
    testWidgets('alternar para truncated em REBUILD não quebra a árvore', (
      tester,
    ) async {
      // Defeito visto na revisão visual do Gate 2: ao inserir o banner de
      // truncated no topo da ListView, todos os índices dos children
      // deslocam. Children sem chave estável fazem o Flutter reconciliar por
      // índice e o sliver estoura
      // `child == null || indexOf(child) > index`.
      //
      // Build inicial nunca pega isso: exige REBUILD com a lista alterada.
      // O MESMO cão em duas seções gera duas chaves de subheader iguais na
      // MESMA ListView. Na reconciliação por chave após o deslocamento de
      // índices, a busca acha a chave duplicada no índice errado.
      final items = [
        scheduleItem(
          id: 'a-atraso',
          dogId: 'dog-a',
          scheduledFor: scheduleTestNow.subtract(const Duration(days: 3)),
        ),
        scheduleItem(
          id: 'a-hoje',
          dogId: 'dog-a',
          scheduledFor: scheduleTestNow.add(const Duration(hours: 2)),
        ),
        scheduleItem(
          id: 'b-proximo',
          dogId: 'dog-b',
          scheduledFor: scheduleTestNow.add(const Duration(days: 3)),
        ),
      ];

      source.enqueueItems(items);
      await controller.setCatalog(const ['dog-a', 'dog-b']);
      await tester.pumpWidget(wrap(view()));
      await tester.pump();
      expect(tester.takeException(), isNull);

      // Mesma view, agora com truncated → insere banner no topo.
      source.enqueueItems(items, truncated: true);
      await controller.refresh();
      await tester.pump();

      expect(
        tester.takeException(),
        isNull,
        reason: 'inserir o banner de truncated não pode quebrar o sliver',
      );
      expect(
        find.byKey(const ValueKey('schedule-global-truncated')),
        findsOneWidget,
      );
    });

    testWidgets('truncated exibe aviso explícito', (tester) async {
      source.enqueueItems([
        scheduleItem(id: 'a1', dogId: 'dog-a'),
      ], truncated: true);
      await controller.setCatalog(const ['dog-a']);
      await tester.pumpWidget(wrap(view()));
      await tester.pump();

      expect(
        find.byKey(const ValueKey('schedule-global-truncated')),
        findsOneWidget,
      );
      expect(find.textContaining('Mostrando os primeiros'), findsOneWidget);
    });

    testWidgets('sem truncated não exibe aviso', (tester) async {
      source.enqueueItems([scheduleItem(id: 'a1', dogId: 'dog-a')]);
      await controller.setCatalog(const ['dog-a']);
      await tester.pumpWidget(wrap(view()));
      await tester.pump();

      expect(
        find.byKey(const ValueKey('schedule-global-truncated')),
        findsNothing,
      );
    });

    testWidgets('não oferece botão de carga ilimitada', (tester) async {
      source.enqueueItems([
        scheduleItem(id: 'a1', dogId: 'dog-a'),
      ], truncated: true);
      await controller.setCatalog(const ['dog-a']);
      await tester.pumpWidget(wrap(view()));
      await tester.pump();

      expect(find.textContaining('carregar tudo'), findsNothing);
      expect(find.textContaining('Carregar tudo'), findsNothing);
      expect(find.textContaining('Ver todos'), findsNothing);
    });
  });

  group('refresh', () {
    testWidgets('pull-to-refresh disponível na lista', (tester) async {
      source.enqueueItems([scheduleItem(id: 'a1', dogId: 'dog-a')]);
      await controller.setCatalog(const ['dog-a']);
      await tester.pumpWidget(wrap(view()));
      await tester.pump();

      expect(find.byType(RefreshIndicator), findsOneWidget);
    });

    testWidgets('falha de refresh preserva lista e mostra banner', (
      tester,
    ) async {
      source.enqueueItems([scheduleItem(id: 'a1', dogId: 'dog-a')]);
      await controller.setCatalog(const ['dog-a']);
      await tester.pumpWidget(wrap(view()));
      await tester.pump();

      source.enqueueError(
        const HealthScheduleSourceException('Falha ao atualizar'),
      );
      await controller.refresh();
      await tester.pump();

      // Dados preservados + aviso.
      expect(find.byType(HealthScheduleItemCard), findsOneWidget);
      expect(
        find.byKey(const ValueKey('schedule-global-refresh-failure')),
        findsOneWidget,
      );
    });
  });

  group('responsividade', () {
    for (final width in [360.0, 390.0, 430.0]) {
      testWidgets('largura $width sem overflow', (tester) async {
        source.enqueueItems([
          scheduleItem(
            id: 'a1',
            dogId: 'dog-a',
            title: 'Vacina antirrábica com título bastante longo para testar',
          ),
          scheduleItem(id: 'b1', dogId: 'dog-b'),
        ]);
        await controller.setCatalog(const ['dog-a', 'dog-b']);
        await tester.pumpWidget(wrap(view(), width: width));
        await tester.pump();

        expect(tester.takeException(), isNull);
      });
    }
  });
}
