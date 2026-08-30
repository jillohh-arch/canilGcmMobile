import 'package:canil_gcm/features/health/domain/health_v1_enums_ext.dart';
import 'package:canil_gcm/features/health/presentation/timeline/health_timeline_controller.dart';
import 'package:canil_gcm/features/health/presentation/timeline/health_timeline_cursor.dart';
import 'package:canil_gcm/features/health/presentation/timeline/health_timeline_entry_view.dart';
import 'package:canil_gcm/features/health/presentation/timeline/health_timeline_query.dart';
import 'package:canil_gcm/features/health/presentation/timeline/health_timeline_source.dart';
import 'package:canil_gcm/features/health/presentation/timeline/health_timeline_state.dart';
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
    controller.dispose();
    source.reset();
  });

  group('primeira página', () {
    test('inicia em initial', () {
      expect(controller.state, isA<HealthTimelineInitial>());
      expect(controller.activeQuery, isNull);
    });

    test('loading → data', () async {
      source.enqueuePage(
        pageOf([entry(id: '1', title: 'Consulta')], nextCursorToken: 'c1'),
      );
      final future = controller.setQuery(HealthTimelineQuery(dogId: 'dog-a'));
      expect(controller.state, isA<HealthTimelineLoading>());
      await future;

      expect(controller.state, isA<HealthTimelineData>());
      final data = controller.state as HealthTimelineData;
      expect(data.dogId, 'dog-a');
      expect(data.items, hasLength(1));
      expect(data.items.first.id, '1');
      expect(data.hasMore, isTrue);
      expect(data.isRefreshing, isFalse);
      expect(data.isLoadingMore, isFalse);
      expect(controller.nextCursorForTest?.token, 'c1');
    });

    test('loading → empty', () async {
      source.enqueuePage(pageOf(const []));
      await controller.setQuery(HealthTimelineQuery(dogId: 'dog-a'));
      expect(controller.state, isA<HealthTimelineEmpty>());
      expect((controller.state as HealthTimelineEmpty).dogId, 'dog-a');
    });

    test('loading → error', () async {
      source.enqueueError(
        const HealthTimelineSourceException('falha de leitura'),
      );
      await controller.setQuery(HealthTimelineQuery(dogId: 'dog-a'));
      expect(controller.state, isA<HealthTimelineError>());
      final err = controller.state as HealthTimelineError;
      expect(err.message, 'falha de leitura');
      expect(err.lastKnown, isNull);
    });

    test('loading → offline', () async {
      source.enqueueOffline('sem rede');
      await controller.setQuery(HealthTimelineQuery(dogId: 'dog-a'));
      expect(controller.state, isA<HealthTimelineOffline>());
      final off = controller.state as HealthTimelineOffline;
      expect(off.query.dogId, 'dog-a');
      expect(off.lastKnown, isNull);
    });
  });

  group('load more', () {
    Future<void> loadFirstWithMore() async {
      source.enqueuePage(
        pageOf([
          entry(id: '1', occurredAt: DateTime(2026, 7, 10, 12)),
        ], nextCursorToken: 'c1'),
      );
      await controller.setQuery(HealthTimelineQuery(dogId: 'dog-a'));
    }

    test('sucesso anexa e atualiza cursor', () async {
      await loadFirstWithMore();
      source.enqueuePage(
        pageOf([
          entry(id: '2', occurredAt: DateTime(2026, 7, 9, 12)),
        ], nextCursorToken: 'c2'),
      );
      await controller.loadMore();
      final data = controller.state as HealthTimelineData;
      expect(data.items.map((e) => e.id), ['1', '2']);
      expect(data.hasMore, isTrue);
      expect(controller.nextCursorForTest?.token, 'c2');
      expect(source.requests.last.cursor?.token, 'c1');
    });

    test('hasMore false encerra paginação', () async {
      await loadFirstWithMore();
      source.enqueuePage(
        pageOf([entry(id: '2', occurredAt: DateTime(2026, 7, 9))]),
      );
      await controller.loadMore();
      final data = controller.state as HealthTimelineData;
      expect(data.hasMore, isFalse);
      expect(controller.nextCursorForTest, isNull);
      // Segundo loadMore é no-op.
      final reqCount = source.requests.length;
      await controller.loadMore();
      expect(source.requests.length, reqCount);
    });

    test('dois loadMore simultâneos: apenas um request', () async {
      await loadFirstWithMore();
      source.holdResponses = true;
      final f1 = controller.loadMore();
      final f2 = controller.loadMore();
      expect(source.pendingCount, 1);
      source.completeNext(
        pageOf([entry(id: '2', occurredAt: DateTime(2026, 7, 9))]),
      );
      await Future.wait([f1, f2]);
      final data = controller.state as HealthTimelineData;
      expect(data.items.map((e) => e.id), ['1', '2']);
    });

    test('erro de loadMore preserva lista e permite retry', () async {
      await loadFirstWithMore();
      source.enqueueError(const HealthTimelineSourceException('page fail'));
      await controller.loadMore();
      final data = controller.state as HealthTimelineData;
      expect(data.items.map((e) => e.id), ['1']);
      expect(data.hasMore, isTrue);
      expect(data.loadMoreError, 'page fail');
      expect(data.isLoadingMore, isFalse);

      source.enqueuePage(
        pageOf([entry(id: '2', occurredAt: DateTime(2026, 7, 9))]),
      );
      await controller.loadMore();
      final retry = controller.state as HealthTimelineData;
      expect(retry.items.map((e) => e.id), ['1', '2']);
      expect(retry.loadMoreError, isNull);
    });

    test('dedupe por id no merge de páginas', () async {
      await loadFirstWithMore();
      source.enqueuePage(
        pageOf([
          entry(
            id: '1',
            occurredAt: DateTime(2026, 7, 10, 12),
            title: 'Atualizado',
          ),
          entry(id: '2', occurredAt: DateTime(2026, 7, 9)),
        ]),
      );
      await controller.loadMore();
      final data = controller.state as HealthTimelineData;
      expect(data.items.map((e) => e.id), ['1', '2']);
      expect(data.items.firstWhere((e) => e.id == '1').title, 'Atualizado');
    });

    test('cursor correto na segunda página', () async {
      source.enqueuePage(pageOf([entry(id: '1')], nextCursorToken: 'cursor-A'));
      await controller.setQuery(HealthTimelineQuery(dogId: 'dog-a'));
      source.enqueuePage(pageOf([entry(id: '2')]));
      await controller.loadMore();
      expect(source.requests[1].cursor, const HealthTimelineCursor('cursor-A'));
      expect(source.requests[1].dogId, 'dog-a');
    });
  });

  group('refresh', () {
    test('cursor volta ao início e substitui primeira página', () async {
      source.enqueuePage(
        pageOf([entry(id: '1', title: 'Old')], nextCursorToken: 'c1'),
      );
      await controller.setQuery(HealthTimelineQuery(dogId: 'dog-a'));
      source.enqueuePage(
        pageOf([
          entry(id: '2', occurredAt: DateTime(2026, 7, 9)),
        ], nextCursorToken: 'c1'),
      );
      await controller.loadMore();
      expect((controller.state as HealthTimelineData).items, hasLength(2));

      source.enqueuePage(
        pageOf([entry(id: '10', title: 'Fresh')], nextCursorToken: 'c-new'),
      );
      await controller.refresh();
      final data = controller.state as HealthTimelineData;
      expect(data.items.map((e) => e.id), ['10']);
      expect(data.items.single.title, 'Fresh');
      expect(controller.nextCursorForTest?.token, 'c-new');
      // Request de refresh sem cursor.
      expect(source.requests.last.cursor, isNull);
    });

    test(
      'refresh com dados existentes marca isRefreshing e não apaga lista',
      () async {
        source.holdResponses = true;
        final load = controller.setQuery(HealthTimelineQuery(dogId: 'dog-a'));
        source.completeNext(pageOf([entry(id: '1')], nextCursorToken: 'c1'));
        await load;
        expect(controller.state, isA<HealthTimelineData>());

        final refreshFuture = controller.refresh();
        expect(controller.state, isA<HealthTimelineData>());
        final refreshing = controller.state as HealthTimelineData;
        expect(refreshing.isRefreshing, isTrue);
        expect(refreshing.items.map((e) => e.id), ['1']);

        source.completeNext(
          pageOf([entry(id: '2', title: 'Novo')], nextCursorToken: 'c2'),
        );
        await refreshFuture;
        final data = controller.state as HealthTimelineData;
        expect(data.isRefreshing, isFalse);
        expect(data.items.single.id, '2');
      },
    );

    test('erro no refresh preserva dados da mesma identidade', () async {
      source.enqueuePage(pageOf([entry(id: '1')], nextCursorToken: 'c1'));
      await controller.setQuery(HealthTimelineQuery(dogId: 'dog-a'));
      source.enqueueError(const HealthTimelineSourceException('boom'));
      await controller.refresh();
      expect(controller.state, isA<HealthTimelineData>());
      final data = controller.state as HealthTimelineData;
      expect(data.items.single.id, '1');
      expect(data.isRefreshing, isFalse);
    });

    test('offline no refresh com dados preserva lista', () async {
      source.enqueuePage(pageOf([entry(id: '1')]));
      await controller.setQuery(HealthTimelineQuery(dogId: 'dog-a'));
      source.enqueueOffline();
      await controller.refresh();
      expect(controller.state, isA<HealthTimelineData>());
      expect((controller.state as HealthTimelineData).items.single.id, '1');
    });

    test('sem duplicação após refresh', () async {
      source.enqueuePage(
        pageOf([
          entry(id: '1'),
          entry(id: '2', occurredAt: DateTime(2026, 7, 9)),
        ]),
      );
      await controller.setQuery(HealthTimelineQuery(dogId: 'dog-a'));
      source.enqueuePage(
        pageOf([
          entry(id: '1'),
          entry(id: '2', occurredAt: DateTime(2026, 7, 9)),
        ]),
      );
      await controller.refresh();
      final data = controller.state as HealthTimelineData;
      expect(data.items.map((e) => e.id), ['1', '2']);
    });
  });

  group('race protection', () {
    test('Dog A → Dog B: resposta tardia de A ignorada', () async {
      source.holdResponses = true;
      final a = controller.setQuery(HealthTimelineQuery(dogId: 'dog-a'));
      final b = controller.setQuery(HealthTimelineQuery(dogId: 'dog-b'));
      expect(source.pendingCount, 2);

      // Completa A depois de B já estar ativo.
      source.completeMatching(
        (q) => q.dogId == 'dog-a',
        pageOf([entry(id: 'a1', dogId: 'dog-a')]),
      );
      await a;
      // Ainda loading de B.
      expect(controller.state, isA<HealthTimelineLoading>());
      expect((controller.state as HealthTimelineLoading).dogId, 'dog-b');

      source.completeMatching(
        (q) => q.dogId == 'dog-b',
        pageOf([entry(id: 'b1', dogId: 'dog-b')]),
      );
      await b;
      final data = controller.state as HealthTimelineData;
      expect(data.dogId, 'dog-b');
      expect(data.items.single.id, 'b1');
    });

    test('Filtro A → Filtro B: resposta antiga ignorada', () async {
      source.holdResponses = true;
      final f1 = controller.setQuery(
        HealthTimelineQuery(dogId: 'dog-a', types: {HealthTimelineType.weight}),
      );
      final f2 = controller.setQuery(
        HealthTimelineQuery(dogId: 'dog-a', types: {HealthTimelineType.meal}),
      );

      source.completeMatching(
        (q) => q.types.contains(HealthTimelineType.weight),
        pageOf([
          entry(id: 'w1', type: HealthTimelineType.weight, title: 'Peso'),
        ]),
      );
      await f1;
      expect(controller.activeQuery?.types, {HealthTimelineType.meal});

      source.completeMatching(
        (q) => q.types.contains(HealthTimelineType.meal),
        pageOf([
          entry(id: 'm1', type: HealthTimelineType.meal, title: 'Refeição'),
        ]),
      );
      await f2;
      final data = controller.state as HealthTimelineData;
      expect(data.items.single.id, 'm1');
      expect(data.query.types, {HealthTimelineType.meal});
    });

    test('loadMore → refresh: resposta tardia de loadMore ignorada', () async {
      source.enqueuePage(pageOf([entry(id: '1')], nextCursorToken: 'c1'));
      await controller.setQuery(HealthTimelineQuery(dogId: 'dog-a'));

      source.holdResponses = true;
      final more = controller.loadMore();
      expect(source.pendingCount, 1);

      final refresh = controller.refresh();
      // loadMore held + refresh held
      expect(source.pendingCount, 2);

      // Completa loadMore antigo com item "contaminante".
      source.completeMatching(
        (q) => q.cursor != null,
        pageOf([entry(id: 'LEAK', title: 'não deve aparecer')]),
      );
      await more;

      source.completeMatching(
        (q) => q.cursor == null,
        pageOf([entry(id: 'fresh', title: 'Refresh ok')]),
      );
      await refresh;

      final data = controller.state as HealthTimelineData;
      expect(data.items.map((e) => e.id), ['fresh']);
      expect(data.items.any((e) => e.id == 'LEAK'), isFalse);
    });

    test('refresh → nova query: resposta antiga de refresh ignorada', () async {
      source.enqueuePage(pageOf([entry(id: '1')]));
      await controller.setQuery(HealthTimelineQuery(dogId: 'dog-a'));

      source.holdResponses = true;
      final refresh = controller.refresh();
      final newQuery = controller.setQuery(HealthTimelineQuery(dogId: 'dog-b'));

      source.completeMatching(
        (q) => q.dogId == 'dog-a',
        pageOf([entry(id: 'stale-a', dogId: 'dog-a')]),
      );
      await refresh;

      source.completeMatching(
        (q) => q.dogId == 'dog-b',
        pageOf([entry(id: 'b-ok', dogId: 'dog-b')]),
      );
      await newQuery;

      final data = controller.state as HealthTimelineData;
      expect(data.dogId, 'dog-b');
      expect(data.items.single.id, 'b-ok');
    });
  });

  group('isolamento dog/query', () {
    test('dados de dog A não reaparecem em dog B após falha', () async {
      source.enqueuePage(
        pageOf([entry(id: 'a1', dogId: 'dog-a', title: 'Só A')]),
      );
      await controller.setQuery(HealthTimelineQuery(dogId: 'dog-a'));
      expect((controller.state as HealthTimelineData).items.single.id, 'a1');

      source.enqueueError(const HealthTimelineSourceException('fail B'));
      await controller.setQuery(HealthTimelineQuery(dogId: 'dog-b'));
      expect(controller.state, isA<HealthTimelineError>());
      final err = controller.state as HealthTimelineError;
      expect(err.dogId, 'dog-b');
      expect(err.lastKnown, isNull);
    });

    test('falha de filtro B não reapresenta resultados do filtro A', () async {
      source.enqueuePage(
        pageOf([
          entry(id: 'w1', type: HealthTimelineType.weight, title: 'Peso'),
        ]),
      );
      await controller.setQuery(
        HealthTimelineQuery(dogId: 'dog-a', types: {HealthTimelineType.weight}),
      );

      source.enqueueError(const HealthTimelineSourceException('fail meal'));
      await controller.setQuery(
        HealthTimelineQuery(dogId: 'dog-a', types: {HealthTimelineType.meal}),
      );
      final err = controller.state as HealthTimelineError;
      expect(err.query.types, {HealthTimelineType.meal});
      expect(err.lastKnown, isNull);
    });

    test('selectDog troca identidade', () async {
      source.enqueuePage(pageOf([entry(id: 'a', dogId: 'dog-a')]));
      await controller.setQuery(
        HealthTimelineQuery(dogId: 'dog-a', types: {HealthTimelineType.exam}),
      );
      source.enqueuePage(pageOf([entry(id: 'b', dogId: 'dog-b')]));
      await controller.selectDog('dog-b');
      final data = controller.state as HealthTimelineData;
      expect(data.dogId, 'dog-b');
      expect(data.query.types, {HealthTimelineType.exam});
      expect(data.items.single.id, 'b');
    });

    test('applyFilters isola por caseId e profissional', () async {
      source.enqueuePage(pageOf([entry(id: '1')]));
      await controller.setQuery(HealthTimelineQuery(dogId: 'dog-a'));

      source.enqueuePage(pageOf([entry(id: 'case-item', caseId: 'c9')]));
      await controller.applyFilters(caseId: 'c9');
      expect((controller.state as HealthTimelineData).query.caseId, 'c9');

      source.enqueueError(const HealthTimelineSourceException('fail pro'));
      await controller.applyFilters(
        professional: HealthTimelineProfessionalFilter(name: 'Dr. X'),
        clearCaseId: true,
      );
      final err = controller.state as HealthTimelineError;
      expect(err.query.professional?.name, 'Dr. X');
      expect(err.query.caseId, isNull);
      expect(err.lastKnown, isNull);
    });

    test('período diferente isola identidade', () async {
      source.enqueuePage(pageOf([entry(id: '1')]));
      await controller.setQuery(
        HealthTimelineQuery(
          dogId: 'dog-a',
          period: HealthTimelinePeriod(start: DateTime(2026, 1, 1)),
        ),
      );
      source.enqueueError(const HealthTimelineSourceException('fail'));
      await controller.setQuery(
        HealthTimelineQuery(
          dogId: 'dog-a',
          period: HealthTimelinePeriod(start: DateTime(2026, 6, 1)),
        ),
      );
      expect(controller.state, isA<HealthTimelineError>());
      expect((controller.state as HealthTimelineError).lastKnown, isNull);
    });
  });

  group('ordenação no controller', () {
    test('primeira página ordena occurredAt DESC', () async {
      source.enqueuePage(
        pageOf([
          entry(id: 'old', occurredAt: DateTime(2026, 7, 1)),
          entry(id: 'new', occurredAt: DateTime(2026, 7, 10)),
          entry(id: 'mid', occurredAt: DateTime(2026, 7, 5)),
        ]),
      );
      await controller.setQuery(HealthTimelineQuery(dogId: 'dog-a'));
      final ids = (controller.state as HealthTimelineData).items.map(
        (e) => e.id,
      );
      expect(ids, ['new', 'mid', 'old']);
    });
  });

  group('tipo desconhecido na timeline', () {
    test('entrada unknown não derruba o load', () async {
      source.enqueuePage(
        pageOf([
          entry(id: 'k', type: HealthTimelineType.consultation),
          entry(id: 'u', typeRaw: 'brand_new_type', title: 'Futuro'),
        ]),
      );
      await controller.setQuery(HealthTimelineQuery(dogId: 'dog-a'));
      final data = controller.state as HealthTimelineData;
      expect(data.items, hasLength(2));
      expect(data.items.any((e) => e.type.isUnknown), isTrue);
      expect(
        data.items.firstWhere((e) => e.id == 'u').type.raw,
        'brand_new_type',
      );
    });
  });

  group('cancelled', () {
    test('entrada cancelled permanece na lista', () async {
      source.enqueuePage(
        pageOf([
          entry(
            id: 'c',
            status: HealthTimelineEntryStatus.cancelled,
            title: 'Cancelado',
          ),
        ]),
      );
      await controller.setQuery(HealthTimelineQuery(dogId: 'dog-a'));
      final data = controller.state as HealthTimelineData;
      expect(data.items.single.isCancelled, isTrue);
    });
  });
}
