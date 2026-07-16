import 'package:canil_gcm/features/health/domain/health_v1_enums_ext.dart';
import 'package:canil_gcm/features/health/presentation/timeline/health_timeline_controller.dart';
import 'package:canil_gcm/features/health/presentation/timeline/health_timeline_cursor.dart';
import 'package:canil_gcm/features/health/presentation/timeline/health_timeline_entry_view.dart';
import 'package:canil_gcm/features/health/presentation/timeline/health_timeline_grouping.dart';
import 'package:canil_gcm/features/health/presentation/timeline/health_timeline_page.dart';
import 'package:canil_gcm/features/health/presentation/timeline/health_timeline_query.dart';
import 'package:canil_gcm/features/health/presentation/timeline/health_timeline_source.dart';
import 'package:canil_gcm/features/health/presentation/timeline/health_timeline_state.dart';
import 'package:canil_gcm/features/health/presentation/timeline/models/health_timeline_detail_reference.dart';
import 'package:canil_gcm/features/health/presentation/timeline/models/health_timeline_traceability.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_health_timeline_source.dart';
import 'timeline_test_helpers.dart';

void main() {
  late FakeHealthTimelineSource source;
  late HealthTimelineController controller;

  setUp(() {
    source = FakeHealthTimelineSource();
    controller = HealthTimelineController(source: source);
  });

  tearDown(() {
    if (!controller.isDisposedForTest) {
      controller.dispose();
    }
    source.reset();
  });

  group('identidade e igualdade de query', () {
    test('Set de tipos em ordem diferente é a mesma identity', () {
      final a = HealthTimelineQuery(
        dogId: 'dog-a',
        types: {HealthTimelineType.weight, HealthTimelineType.vaccination},
      );
      final b = HealthTimelineQuery(
        dogId: 'dog-a',
        types: {HealthTimelineType.vaccination, HealthTimelineType.weight},
      );
      expect(a.filterIdentity, b.filterIdentity);
      expect(a, b);
    });

    test('types vazio significa todos — identity estável', () {
      final a = HealthTimelineQuery(dogId: 'dog-a');
      final b = HealthTimelineQuery(dogId: 'dog-a', types: const {});
      expect(a.filterIdentity, b.filterIdentity);
      expect(a.types, isEmpty);
    });

    test('cursor diferente: query != mas identity ==', () {
      final a = HealthTimelineQuery(
        dogId: 'dog-a',
        cursor: const HealthTimelineCursor('c1'),
      );
      final b = HealthTimelineQuery(
        dogId: 'dog-a',
        cursor: const HealthTimelineCursor('c2'),
      );
      expect(a.filterIdentity, b.filterIdentity);
      expect(a, isNot(equals(b)));
    });

    test('pageSize/caseId/dogId/professional alteram identity', () {
      final base = HealthTimelineQuery(dogId: 'dog-a');
      expect(
        base.filterIdentity,
        isNot(HealthTimelineQuery(dogId: 'dog-a', pageSize: 10).filterIdentity),
      );
      expect(
        base.filterIdentity,
        isNot(HealthTimelineQuery(dogId: 'dog-a', caseId: 'c').filterIdentity),
      );
      expect(
        base.filterIdentity,
        isNot(HealthTimelineQuery(dogId: 'dog-b').filterIdentity),
      );
      expect(
        base.filterIdentity,
        isNot(
          HealthTimelineQuery(
            dogId: 'dog-a',
            professional: HealthTimelineProfessionalFilter(name: 'X'),
          ).filterIdentity,
        ),
      );
    });

    test('copyWith invalid pageSize ainda valida', () {
      final q = HealthTimelineQuery(dogId: 'd');
      expect(() => q.copyWith(pageSize: 0), throwsArgumentError);
      expect(() => q.copyWith(pageSize: 101), throwsArgumentError);
      expect(q.copyWith(pageSize: 1).pageSize, 1);
      expect(q.copyWith(pageSize: 100).pageSize, 100);
    });

    test('dogId e caseId são normalizados (trim)', () {
      final q = HealthTimelineQuery(dogId: '  dog-a  ', caseId: '  c1  ');
      expect(q.dogId, 'dog-a');
      expect(q.caseId, 'c1');
      expect(
        q.filterIdentity,
        HealthTimelineQuery(dogId: 'dog-a', caseId: 'c1').filterIdentity,
      );
    });

    test('professional filter trim e igualdade', () {
      final a = HealthTimelineProfessionalFilter(
        name: '  Dra. Ana  ',
        registrationNumber: ' 123 ',
        registrationType: ProfessionalRegistrationType.crmv,
      );
      final b = HealthTimelineProfessionalFilter(
        name: 'Dra. Ana',
        registrationNumber: '123',
        registrationType: ProfessionalRegistrationType.crmv,
      );
      expect(a, b);
      expect(
        a,
        isNot(
          HealthTimelineProfessionalFilter(
            name: 'Dra. Ana',
            registrationNumber: '999',
          ),
        ),
      );
    });
  });

  group('imutabilidade', () {
    test('HealthTimelinePage isola lista mutável de entrada', () {
      final mutable = [entry(id: 'a')];
      final page = HealthTimelinePage(
        items: mutable,
        nextCursor: null,
        hasMore: false,
      );
      mutable.add(entry(id: 'b'));
      expect(page.items, hasLength(1));
      expect(() => page.items.add(entry(id: 'c')), throwsUnsupportedError);
    });

    test('query.types é unmodifiable', () {
      final q = HealthTimelineQuery(
        dogId: 'd',
        types: {HealthTimelineType.meal},
      );
      expect(
        () => q.types.add(HealthTimelineType.dose),
        throwsUnsupportedError,
      );
    });

    test('snapshot.items é unmodifiable', () {
      final snap = HealthTimelineSnapshot(
        items: [entry(id: '1')],
        hasMore: false,
        query: HealthTimelineQuery(dogId: 'd'),
      );
      expect(() => snap.items.add(entry(id: '2')), throwsUnsupportedError);
    });

    test('controller não expõe lista mutável via state', () async {
      source.enqueuePage(pageOf([entry(id: '1')]));
      await controller.setQuery(HealthTimelineQuery(dogId: 'dog-a'));
      final items = (controller.state as HealthTimelineData).items;
      expect(() => items.add(entry(id: 'x')), throwsUnsupportedError);
    });
  });

  group('dedupe + ordering', () {
    test('página sobreposta deduplica C e reordena se occurredAt muda', () {
      final t1 = DateTime(2026, 7, 10, 12);
      final t2 = DateTime(2026, 7, 11, 12);
      final existing = [
        entry(id: 'A', occurredAt: t1.add(const Duration(hours: 2))),
        entry(id: 'B', occurredAt: t1.add(const Duration(hours: 1))),
        entry(id: 'C', occurredAt: t1, title: 'C-old'),
      ];
      final incoming = [
        entry(id: 'C', occurredAt: t2, title: 'C-new'),
        entry(id: 'D', occurredAt: t1.subtract(const Duration(hours: 1))),
        entry(id: 'E', occurredAt: t1.subtract(const Duration(hours: 2))),
      ];
      final merged = mergeTimelineEntries(
        existing: existing,
        incoming: incoming,
      );
      expect(merged.map((e) => e.id).toList(), ['C', 'A', 'B', 'D', 'E']);
      expect(merged.firstWhere((e) => e.id == 'C').title, 'C-new');
      expect(merged.firstWhere((e) => e.id == 'C').occurredAt, t2);
    });

    test(
      'loadMore com occurredAt alterado reordena lista do controller',
      () async {
        final oldTime = DateTime(2026, 7, 5, 12);
        final newTime = DateTime(2026, 7, 12, 12);
        source.enqueuePage(
          pageOf([
            entry(id: 'keep', occurredAt: DateTime(2026, 7, 10)),
            entry(id: 'move', occurredAt: oldTime, title: 'old'),
          ], nextCursorToken: 'c1'),
        );
        await controller.setQuery(HealthTimelineQuery(dogId: 'dog-a'));
        source.enqueuePage(
          pageOf([
            entry(id: 'move', occurredAt: newTime, title: 'updated'),
            entry(id: 'extra', occurredAt: DateTime(2026, 7, 8)),
          ]),
        );
        await controller.loadMore();
        final ids = (controller.state as HealthTimelineData).items
            .map((e) => e.id)
            .toList();
        expect(ids.first, 'move');
        expect(ids, ['move', 'keep', 'extra']);
      },
    );
  });

  group('refresh failure semantics', () {
    test(
      'erro genérico no refresh preserva lista e lastRefreshError',
      () async {
        source.enqueuePage(pageOf([entry(id: '1')]));
        await controller.setQuery(HealthTimelineQuery(dogId: 'dog-a'));
        source.enqueueError(const HealthTimelineSourceException('boom'));
        await controller.refresh();
        final data = controller.state as HealthTimelineData;
        expect(data.items.single.id, '1');
        expect(data.isRefreshing, isFalse);
        expect(data.hasRefreshFailure, isTrue);
        expect(data.lastRefreshError, 'boom');
        expect(data.lastRefreshWasOffline, isFalse);
      },
    );

    test(
      'offline no refresh preserva lista e marca lastRefreshWasOffline',
      () async {
        source.enqueuePage(pageOf([entry(id: '1')]));
        await controller.setQuery(HealthTimelineQuery(dogId: 'dog-a'));
        source.enqueueOffline('sem rede');
        await controller.refresh();
        final data = controller.state as HealthTimelineData;
        expect(data.items.single.id, '1');
        expect(data.lastRefreshError, 'sem rede');
        expect(data.lastRefreshWasOffline, isTrue);
      },
    );

    test('refresh bem-sucedido limpa lastRefreshError', () async {
      source.enqueuePage(pageOf([entry(id: '1')]));
      await controller.setQuery(HealthTimelineQuery(dogId: 'dog-a'));
      source.enqueueError(const HealthTimelineSourceException('boom'));
      await controller.refresh();
      expect(
        (controller.state as HealthTimelineData).hasRefreshFailure,
        isTrue,
      );

      source.enqueuePage(pageOf([entry(id: '2')]));
      await controller.refresh();
      final data = controller.state as HealthTimelineData;
      expect(data.items.single.id, '2');
      expect(data.hasRefreshFailure, isFalse);
      expect(data.lastRefreshError, isNull);
    });

    test(
      'loadMore após refresh falho restaura cursor e preserva lastRefreshError',
      () async {
        source.enqueuePage(pageOf([entry(id: '1')], nextCursorToken: 'c1'));
        await controller.setQuery(HealthTimelineQuery(dogId: 'dog-a'));
        source.enqueueError(const HealthTimelineSourceException('r-fail'));
        await controller.refresh();
        final afterFail = controller.state as HealthTimelineData;
        expect(afterFail.lastRefreshError, 'r-fail');
        expect(afterFail.hasMore, isTrue);
        expect(controller.nextCursorForTest?.token, 'c1');

        source.enqueuePage(
          pageOf([entry(id: '2', occurredAt: DateTime(2026, 7, 1))]),
        );
        await controller.loadMore();
        final data = controller.state as HealthTimelineData;
        expect(data.items.map((e) => e.id), ['1', '2']);
        expect(data.lastRefreshError, 'r-fail');
      },
    );
  });

  group('loadMore error + refresh', () {
    test('loadMoreError limpo após refresh bem-sucedido', () async {
      source.enqueuePage(pageOf([entry(id: '1')], nextCursorToken: 'c1'));
      await controller.setQuery(HealthTimelineQuery(dogId: 'dog-a'));
      source.enqueueError(const HealthTimelineSourceException('page fail'));
      await controller.loadMore();
      expect(
        (controller.state as HealthTimelineData).loadMoreError,
        'page fail',
      );
      expect(controller.nextCursorForTest?.token, 'c1');

      source.enqueuePage(
        pageOf([entry(id: 'fresh')], nextCursorToken: 'c-new'),
      );
      await controller.refresh();
      final data = controller.state as HealthTimelineData;
      expect(data.loadMoreError, isNull);
      expect(data.items.single.id, 'fresh');
      expect(controller.nextCursorForTest?.token, 'c-new');
    });

    test('erro de loadMore preserva cursor para retry', () async {
      source.enqueuePage(pageOf([entry(id: '1')], nextCursorToken: 'keep-me'));
      await controller.setQuery(HealthTimelineQuery(dogId: 'dog-a'));
      source.enqueueError(const HealthTimelineSourceException('x'));
      await controller.loadMore();
      expect(controller.nextCursorForTest?.token, 'keep-me');
      expect((controller.state as HealthTimelineData).hasMore, isTrue);
    });
  });

  group('races estendidas', () {
    test('loadMore + troca de filtro: itens de A não entram em B', () async {
      source.enqueuePage(
        pageOf([
          entry(id: 'w1', type: HealthTimelineType.weight),
        ], nextCursorToken: 'cA'),
      );
      await controller.setQuery(
        HealthTimelineQuery(dogId: 'dog-a', types: {HealthTimelineType.weight}),
      );

      source.holdResponses = true;
      final more = controller.loadMore();
      final switchFilter = controller.setQuery(
        HealthTimelineQuery(dogId: 'dog-a', types: {HealthTimelineType.meal}),
      );

      source.completeMatching(
        (q) => q.types.contains(HealthTimelineType.meal),
        pageOf([entry(id: 'm1', type: HealthTimelineType.meal)]),
      );
      await switchFilter;

      source.completeMatching(
        (q) => q.cursor != null,
        pageOf([
          entry(
            id: 'LEAK-A',
            type: HealthTimelineType.weight,
            title: 'não deve entrar',
          ),
        ]),
      );
      await more;

      final data = controller.state as HealthTimelineData;
      expect(data.query.types, {HealthTimelineType.meal});
      expect(data.items.map((e) => e.id), ['m1']);
      expect(data.items.any((e) => e.id == 'LEAK-A'), isFalse);
    });

    test('loadMore + troca de cão: itens de A não entram em B', () async {
      source.enqueuePage(
        pageOf([entry(id: 'a1', dogId: 'dog-a')], nextCursorToken: 'cA'),
      );
      await controller.setQuery(HealthTimelineQuery(dogId: 'dog-a'));

      source.holdResponses = true;
      final more = controller.loadMore();
      final switchDog = controller.selectDog('dog-b');

      source.completeMatching(
        (q) => q.dogId == 'dog-b',
        pageOf([entry(id: 'b1', dogId: 'dog-b')]),
      );
      await switchDog;

      source.completeMatching(
        (q) => q.cursor != null,
        pageOf([entry(id: 'LEAK', dogId: 'dog-a')]),
      );
      await more;

      final data = controller.state as HealthTimelineData;
      expect(data.dogId, 'dog-b');
      expect(data.items.single.id, 'b1');
    });

    test(
      'request 2 responde antes de request 1 (setQuery out-of-order)',
      () async {
        source.holdResponses = true;
        final r1 = controller.setQuery(HealthTimelineQuery(dogId: 'dog-a'));
        final r2 = controller.setQuery(HealthTimelineQuery(dogId: 'dog-b'));

        // B (mais novo) primeiro.
        source.completeMatching(
          (q) => q.dogId == 'dog-b',
          pageOf([entry(id: 'b', dogId: 'dog-b')]),
        );
        await r2;
        expect((controller.state as HealthTimelineData).items.single.id, 'b');

        // A (antigo) depois — ignorado.
        source.completeMatching(
          (q) => q.dogId == 'dog-a',
          pageOf([entry(id: 'a', dogId: 'dog-a')]),
        );
        await r1;
        expect((controller.state as HealthTimelineData).items.single.id, 'b');
      },
    );

    test('refresh duplo: resposta antiga não sobrescreve a nova', () async {
      source.enqueuePage(pageOf([entry(id: '1')]));
      await controller.setQuery(HealthTimelineQuery(dogId: 'dog-a'));

      source.holdResponses = true;
      final r1 = controller.refresh();
      final r2 = controller.refresh();
      expect(source.pendingCount, 2);

      // Completa o refresh mais antigo primeiro com payload stale.
      source.completeNext(pageOf([entry(id: 'stale')]));
      await r1;
      // Ainda refreshing (r2 ativo) ou já data se r1 foi ignorado e r2 pending.
      // Completa o mais recente.
      source.completeNext(pageOf([entry(id: 'latest')]));
      await r2;

      final data = controller.state as HealthTimelineData;
      expect(data.items.single.id, 'latest');
      expect(data.isRefreshing, isFalse);
    });

    test('loadMore → refresh: ordem inversa (refresh resolve antes)', () async {
      source.enqueuePage(pageOf([entry(id: '1')], nextCursorToken: 'c1'));
      await controller.setQuery(HealthTimelineQuery(dogId: 'dog-a'));

      source.holdResponses = true;
      final more = controller.loadMore();
      final refresh = controller.refresh();

      // Refresh resolve primeiro.
      source.completeMatching(
        (q) => q.cursor == null,
        pageOf([entry(id: 'fresh')]),
      );
      await refresh;
      expect((controller.state as HealthTimelineData).items.single.id, 'fresh');

      // loadMore tarda.
      source.completeMatching(
        (q) => q.cursor != null,
        pageOf([entry(id: 'LEAK')]),
      );
      await more;
      expect((controller.state as HealthTimelineData).items.map((e) => e.id), [
        'fresh',
      ]);
    });
  });

  group('dispose durante request', () {
    test('dispose no meio do setQuery não notifica nem lança', () async {
      source.holdResponses = true;
      var notifications = 0;
      controller.addListener(() => notifications++);

      final future = controller.setQuery(HealthTimelineQuery(dogId: 'dog-a'));
      expect(controller.state, isA<HealthTimelineLoading>());
      final notificationsAfterLoad = notifications;

      controller.dispose();
      expect(controller.isDisposedForTest, isTrue);

      source.completeNext(pageOf([entry(id: 'late')]));
      await future;

      // Sem notificação adicional após dispose.
      expect(notifications, notificationsAfterLoad);
      // Estado permanece no último valor pré-dispose (loading) — sem mutação.
      expect(controller.state, isA<HealthTimelineLoading>());
    });

    test('dispose no meio do loadMore não corrompe', () async {
      source.enqueuePage(pageOf([entry(id: '1')], nextCursorToken: 'c1'));
      await controller.setQuery(HealthTimelineQuery(dogId: 'dog-a'));

      source.holdResponses = true;
      final more = controller.loadMore();
      expect((controller.state as HealthTimelineData).isLoadingMore, isTrue);
      controller.dispose();
      source.completeNext(pageOf([entry(id: '2')]));
      await more;
      // Sem throw; disposed.
      expect(controller.isDisposedForTest, isTrue);
    });
  });

  group('flags presas (isRefreshing / isLoadingMore)', () {
    test('erro em loadMore limpa isLoadingMore', () async {
      source.enqueuePage(pageOf([entry(id: '1')], nextCursorToken: 'c1'));
      await controller.setQuery(HealthTimelineQuery(dogId: 'dog-a'));
      source.enqueueError(const HealthTimelineSourceException('x'));
      await controller.loadMore();
      final data = controller.state as HealthTimelineData;
      expect(data.isLoadingMore, isFalse);
      expect(data.loadMoreError, 'x');
    });

    test('erro em refresh limpa isRefreshing', () async {
      source.enqueuePage(pageOf([entry(id: '1')]));
      await controller.setQuery(HealthTimelineQuery(dogId: 'dog-a'));
      source.enqueueError(const HealthTimelineSourceException('x'));
      await controller.refresh();
      final data = controller.state as HealthTimelineData;
      expect(data.isRefreshing, isFalse);
    });

    test(
      'troca de query durante isLoadingMore não deixa flag no novo estado',
      () async {
        source.enqueuePage(pageOf([entry(id: '1')], nextCursorToken: 'c1'));
        await controller.setQuery(HealthTimelineQuery(dogId: 'dog-a'));
        source.holdResponses = true;
        final more = controller.loadMore();
        final next = controller.setQuery(HealthTimelineQuery(dogId: 'dog-b'));
        source.completeMatching(
          (q) => q.dogId == 'dog-b',
          pageOf([entry(id: 'b')]),
        );
        await next;
        source.completeMatching(
          (q) => q.cursor != null,
          pageOf([entry(id: 'x')]),
        );
        await more;
        final data = controller.state as HealthTimelineData;
        expect(data.isLoadingMore, isFalse);
        expect(data.isRefreshing, isFalse);
        expect(data.items.single.id, 'b');
      },
    );
  });

  group('empty vs error', () {
    test('exception não vira empty', () async {
      source.enqueueError(const HealthTimelineSourceException('fail'));
      await controller.setQuery(HealthTimelineQuery(dogId: 'dog-a'));
      expect(controller.state, isA<HealthTimelineError>());
      expect(controller.state, isNot(isA<HealthTimelineEmpty>()));
    });

    test('lista vazia com sucesso vira empty não data', () async {
      source.enqueuePage(pageOf(const []));
      await controller.setQuery(HealthTimelineQuery(dogId: 'dog-a'));
      expect(controller.state, isA<HealthTimelineEmpty>());
      expect(controller.state, isNot(isA<HealthTimelineData>()));
    });
  });

  group('DateTime utc / agrupamento local', () {
    test('UTC próximo de meia-noite pode cair em dia local diferente', () {
      // 2026-07-10 23:30 UTC → em UTC-3 vira 2026-07-10 20:30 (mesmo dia)
      // 2026-07-11 01:30 UTC → em UTC-3 vira 2026-07-10 22:30 (dia anterior)
      final e1 = entry(
        id: 'utc1',
        occurredAt: DateTime.utc(2026, 7, 10, 23, 30),
      );
      final e2 = entry(
        id: 'utc2',
        occurredAt: DateTime.utc(2026, 7, 11, 1, 30),
      );

      // Simula device em UTC-3.
      DateTime toUtcMinus3(DateTime d) =>
          d.toUtc().add(const Duration(hours: -3));

      final groups = groupTimelineByDay([e2, e1], toLocal: toUtcMinus3);
      // e1: 20:30 do dia 10; e2: 22:30 do dia 10 — mesmo dia local.
      expect(groups, hasLength(1));
      expect(groups.single.date, DateTime(2026, 7, 10));
      expect(groups.single.entries.map((e) => e.id), ['utc2', 'utc1']);
    });

    test(
      'toLocal default é aplicado de forma consistente (não compara utc cru)',
      () {
        final utc = entry(id: 'u', occurredAt: DateTime.utc(2026, 7, 10, 12));
        final groups = groupTimelineByDay([utc]);
        expect(groups, hasLength(1));
        // day key é local meia-noite (isUtc == false).
        expect(groups.single.date.isUtc, isFalse);
        expect(groups.single.date.hour, 0);
      },
    );
  });

  group('period', () {
    test('somente start / somente end / ambos null', () {
      final onlyStart = HealthTimelinePeriod(start: DateTime(2026, 1, 1));
      final onlyEnd = HealthTimelinePeriod(end: DateTime(2026, 12, 31));
      final unbounded = HealthTimelinePeriod();
      expect(onlyStart.end, isNull);
      expect(onlyEnd.start, isNull);
      expect(unbounded.isUnbounded, isTrue);
    });

    test('start == end inclusivo é válido e igual', () {
      final d = DateTime(2026, 7, 10);
      final a = HealthTimelinePeriod(start: d, end: d);
      final b = HealthTimelinePeriod(start: d, end: d);
      expect(a, b);
    });
  });

  group('forward compatibility / status / amendments / attachments', () {
    test('draft não é HealthTimelineEntryStatus', () {
      expect(HealthTimelineEntryStatus.tryParse('draft'), isNull);
      expect(HealthTimelineEntryStatus.values.map((e) => e.wireName), [
        'final',
        'cancelled',
      ]);
    });

    test('tipo desconhecido agrupa e ordena normalmente', () {
      final t = DateTime(2026, 7, 10, 12);
      final items = sortTimelineEntries([
        entry(id: 'u', typeRaw: 'future_x', occurredAt: t),
        entry(id: 'k', type: HealthTimelineType.weight, occurredAt: t),
      ]);
      expect(items.map((e) => e.id), ['k', 'u']); // id ASC no empate
      final groups = groupTimelineByDay(items, toLocal: (d) => d);
      expect(groups.single.entries, hasLength(2));
    });

    test(
      'hasAmendments false com lastAmendedAt é permitido (sem overengineer)',
      () {
        final m = HealthTimelineAmendmentMetadata(
          lastAmendedAt: DateTime(2026, 7, 1),
        );
        expect(m.hasAmendments, isFalse);
        expect(m.lastAmendedAt, isNotNull);
      },
    );

    test('attachmentCount null com hasAttachments true é permitido', () {
      final e = entry(id: 'a', hasAttachments: true, attachmentCount: null);
      expect(e.hasAttachments, isTrue);
      expect(e.attachmentCount, isNull);
    });

    test('traceability vazio é permitido', () {
      const t = HealthTimelineTraceability();
      expect(t.hasCanonicalSource, isFalse);
      expect(t.hasLegacySource, isFalse);
    });

    test('detail reference rejeita strings vazias em assert/debug', () {
      expect(
        () => HealthTimelineDetailReference(sourceType: '', sourceId: 'x'),
        throwsA(anything),
      );
      expect(
        () => HealthTimelineDetailReference(sourceType: 't', sourceId: ''),
        throwsA(anything),
      );
    });
  });

  group('source abstraction / imports', () {
    test('exception offline não depende de Firebase', () {
      const e = HealthTimelineSourceException('off', isOffline: true);
      expect(e.isOffline, isTrue);
      expect(e.toString(), 'off');
    });
  });

  group('notifyListeners', () {
    test('setQuery bem-sucedido notifica loading e data', () async {
      source.enqueuePage(pageOf([entry(id: '1')]));
      final states = <Type>[];
      controller.addListener(() {
        states.add(controller.state.runtimeType);
      });
      await controller.setQuery(HealthTimelineQuery(dogId: 'dog-a'));
      expect(states, contains(HealthTimelineLoading));
      expect(states, contains(HealthTimelineData));
    });

    test('resposta de race ignorada não notifica estado incorreto', () async {
      source.holdResponses = true;
      await Future<void>.value();
      final fA = controller.setQuery(HealthTimelineQuery(dogId: 'dog-a'));
      final fB = controller.setQuery(HealthTimelineQuery(dogId: 'dog-b'));

      final states = <String>[];
      controller.addListener(() {
        final s = controller.state;
        if (s is HealthTimelineData) {
          states.add('data:${s.dogId}:${s.items.map((e) => e.id).join(',')}');
        } else if (s is HealthTimelineLoading) {
          states.add('loading:${s.dogId}');
        }
      });

      source.completeMatching(
        (q) => q.dogId == 'dog-b',
        pageOf([entry(id: 'b', dogId: 'dog-b')]),
      );
      await fB;
      source.completeMatching(
        (q) => q.dogId == 'dog-a',
        pageOf([entry(id: 'a', dogId: 'dog-a')]),
      );
      await fA;

      expect(states.where((s) => s.startsWith('data:')), ['data:dog-b:b']);
      expect(states.any((s) => s.contains('dog-a:a')), isFalse);
    });
  });
}
