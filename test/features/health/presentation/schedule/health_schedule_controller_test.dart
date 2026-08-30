import 'package:canil_gcm/features/health/domain/health_v1_enums_ext.dart';
import 'package:canil_gcm/features/health/presentation/schedule/health_schedule_controller.dart';
import 'package:canil_gcm/features/health/presentation/schedule/health_schedule_query.dart';
import 'package:canil_gcm/features/health/presentation/schedule/health_schedule_source.dart';
import 'package:canil_gcm/features/health/presentation/schedule/health_schedule_state.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_health_schedule_source.dart';
import 'schedule_test_helpers.dart';

void main() {
  late FakeHealthScheduleSource source;
  late HealthScheduleController controller;
  late DateTime clockNow;

  setUp(() {
    source = FakeHealthScheduleSource();
    clockNow = scheduleTestNow;
    controller = HealthScheduleController(
      source: source,
      temporalPolicy: testSchedulePolicy(),
      clock: () => clockNow,
    );
  });

  tearDown(() {
    controller.dispose();
    source.reset();
  });

  group('estado básico', () {
    test('inicia em initial', () {
      expect(controller.state, isA<HealthScheduleInitial>());
      expect(controller.activeDogId, isNull);
    });

    test('loading → data', () async {
      source.enqueuePage(
        schedulePage([
          scheduleItem(
            id: '1',
            scheduledFor: scheduleTestNow.add(const Duration(days: 2)),
          ),
        ]),
      );
      final future = controller.setQuery(HealthScheduleQuery(dogId: 'dog-a'));
      expect(controller.state, isA<HealthScheduleLoading>());
      expect((controller.state as HealthScheduleLoading).dogId, 'dog-a');
      await future;

      expect(controller.state, isA<HealthScheduleData>());
      final data = controller.state as HealthScheduleData;
      expect(data.dogId, 'dog-a');
      expect(data.items, hasLength(1));
      expect(
        data.items.first.temporalStatus,
        HealthScheduleTemporalStatus.upcoming,
      );
      expect(data.groups.upcoming, hasLength(1));
      expect(data.isRefreshing, isFalse);
    });

    test('loading → empty', () async {
      source.enqueuePage(schedulePage(const []));
      await controller.setQuery(HealthScheduleQuery(dogId: 'dog-a'));
      expect(controller.state, isA<HealthScheduleEmpty>());
      expect((controller.state as HealthScheduleEmpty).dogId, 'dog-a');
    });

    test('loading → error', () async {
      source.enqueueError(
        const HealthScheduleSourceException('falha de leitura'),
      );
      await controller.setQuery(HealthScheduleQuery(dogId: 'dog-a'));
      expect(controller.state, isA<HealthScheduleError>());
      final err = controller.state as HealthScheduleError;
      expect(err.dogId, 'dog-a');
      expect(err.message, 'falha de leitura');
      expect(err.lastKnown, isNull);
    });

    test('loading → offline', () async {
      source.enqueueOffline('sem rede');
      await controller.setQuery(HealthScheduleQuery(dogId: 'dog-a'));
      expect(controller.state, isA<HealthScheduleOffline>());
      expect((controller.state as HealthScheduleOffline).dogId, 'dog-a');
    });
  });

  group('agrupamentos', () {
    test(
      'classifica overdue/today/upcoming/scheduled sem recalcular na UI',
      () async {
        source.enqueuePage(
          schedulePage([
            scheduleItem(
              id: 'over',
              scheduledFor: scheduleTestNow.subtract(const Duration(days: 3)),
              dueUntil: scheduleTestNow.subtract(const Duration(hours: 1)),
            ),
            scheduleItem(
              id: 'today',
              scheduledFor: scheduleTestNow.add(const Duration(hours: 5)),
            ),
            scheduleItem(
              id: 'up',
              scheduledFor: scheduleTestNow.add(const Duration(days: 3)),
            ),
            scheduleItem(
              id: 'prog',
              scheduledFor: scheduleTestNow.add(const Duration(days: 30)),
            ),
            scheduleItem(
              id: 'done',
              status: ScheduleLifecycleStatus.completed,
              scheduledFor: scheduleTestNow.subtract(const Duration(days: 1)),
              completedAt: scheduleTestNow.subtract(const Duration(hours: 2)),
            ),
            scheduleItem(
              id: 'canc',
              status: ScheduleLifecycleStatus.cancelled,
              scheduledFor: scheduleTestNow.add(const Duration(days: 1)),
              cancelledAt: scheduleTestNow,
              cancelReason: 'cancelado',
            ),
          ]),
        );
        await controller.setQuery(HealthScheduleQuery(dogId: 'dog-a'));
        final data = controller.state as HealthScheduleData;
        expect(data.groups.overdue.map((e) => e.id), ['over']);
        expect(data.groups.today.map((e) => e.id), ['today']);
        expect(data.groups.upcoming.map((e) => e.id), ['up']);
        expect(data.groups.scheduled.map((e) => e.id), ['prog']);
        expect(data.groups.completed.map((e) => e.id), ['done']);
        expect(data.groups.cancelled.map((e) => e.id), ['canc']);
      },
    );
  });

  group('isolamento por dogId e stale requests', () {
    test('troca rápida de K9 ignora resposta do cão anterior', () async {
      source.holdResponses = true;

      final f1 = controller.selectDog('dog-a');
      expect(controller.state, isA<HealthScheduleLoading>());
      expect((controller.state as HealthScheduleLoading).dogId, 'dog-a');

      final f2 = controller.selectDog('dog-b');
      expect((controller.state as HealthScheduleLoading).dogId, 'dog-b');

      // Resposta tardia de A não deve sobrescrever B.
      source.completeMatching(
        (q) => q.dogId == 'dog-a',
        schedulePage([scheduleItem(id: 'a1', dogId: 'dog-a')]),
      );
      await Future<void>.delayed(Duration.zero);
      expect(controller.state, isA<HealthScheduleLoading>());
      expect((controller.state as HealthScheduleLoading).dogId, 'dog-b');

      source.completeMatching(
        (q) => q.dogId == 'dog-b',
        schedulePage([
          scheduleItem(
            id: 'b1',
            dogId: 'dog-b',
            scheduledFor: scheduleTestNow.add(const Duration(days: 2)),
          ),
        ]),
      );
      await f2;
      await f1;

      expect(controller.state, isA<HealthScheduleData>());
      final data = controller.state as HealthScheduleData;
      expect(data.dogId, 'dog-b');
      expect(data.items.map((e) => e.id), ['b1']);
      expect(data.items.every((e) => e.dogId == 'dog-b'), isTrue);
    });

    test('resposta antiga não sobrescreve solicitação mais recente', () async {
      source.holdResponses = true;

      final first = controller.setQuery(HealthScheduleQuery(dogId: 'dog-a'));
      final second = controller.setQuery(
        HealthScheduleQuery(dogId: 'dog-a', types: {ScheduleType.weighing}),
      );

      // Completa a 1ª (já stale) com item de vacinação.
      source.completeNext(
        schedulePage([
          scheduleItem(id: 'stale', scheduleType: ScheduleType.vaccination),
        ]),
      );
      await Future<void>.delayed(Duration.zero);
      expect(controller.state, isA<HealthScheduleLoading>());

      source.completeNext(
        schedulePage([
          scheduleItem(
            id: 'fresh',
            scheduleType: ScheduleType.weighing,
            scheduledFor: scheduleTestNow.add(const Duration(days: 1)),
          ),
        ]),
      );
      await second;
      await first;

      final data = controller.state as HealthScheduleData;
      expect(data.items.map((e) => e.id), ['fresh']);
      expect(data.query.types, {ScheduleType.weighing});
    });

    test('dois dogIds não misturam itens', () async {
      source.enqueuePage(
        schedulePage([
          scheduleItem(
            id: 'a1',
            dogId: 'dog-a',
            scheduledFor: scheduleTestNow.add(const Duration(days: 1)),
          ),
        ]),
      );
      await controller.selectDog('dog-a');
      expect((controller.state as HealthScheduleData).items.single.id, 'a1');

      source.enqueuePage(
        schedulePage([
          scheduleItem(
            id: 'b1',
            dogId: 'dog-b',
            scheduledFor: scheduleTestNow.add(const Duration(days: 1)),
          ),
        ]),
      );
      await controller.selectDog('dog-b');
      final data = controller.state as HealthScheduleData;
      expect(data.dogId, 'dog-b');
      expect(data.items.single.id, 'b1');
      expect(data.items.single.dogId, 'dog-b');
    });
  });

  group('refresh', () {
    test(
      'refresh com sucesso substitui itens e limpa falha anterior',
      () async {
        source.enqueuePage(
          schedulePage([
            scheduleItem(
              id: 'old',
              scheduledFor: scheduleTestNow.add(const Duration(days: 2)),
            ),
          ]),
        );
        await controller.setQuery(HealthScheduleQuery(dogId: 'dog-a'));
        expect((controller.state as HealthScheduleData).items.single.id, 'old');

        source.enqueuePage(
          schedulePage([
            scheduleItem(
              id: 'new',
              scheduledFor: scheduleTestNow.add(const Duration(days: 1)),
            ),
          ]),
        );
        await controller.refresh();
        final data = controller.state as HealthScheduleData;
        expect(data.items.map((e) => e.id), ['new']);
        expect(data.isRefreshing, isFalse);
        expect(data.lastRefreshError, isNull);
        expect(data.dogId, 'dog-a');
      },
    );

    test(
      'refresh com erro preserva dados válidos e expõe lastRefreshError',
      () async {
        source.enqueuePage(
          schedulePage([
            scheduleItem(
              id: 'keep',
              scheduledFor: scheduleTestNow.add(const Duration(days: 2)),
            ),
          ]),
        );
        await controller.setQuery(HealthScheduleQuery(dogId: 'dog-a'));
        expect(controller.state, isA<HealthScheduleData>());

        source.enqueueError(
          const HealthScheduleSourceException('refresh falhou'),
        );
        await controller.refresh();

        expect(controller.state, isA<HealthScheduleData>());
        final data = controller.state as HealthScheduleData;
        expect(data.dogId, 'dog-a');
        expect(data.items.map((e) => e.id), ['keep']);
        expect(data.isRefreshing, isFalse);
        expect(data.lastRefreshError, 'refresh falhou');
        expect(data.hasRefreshFailure, isTrue);
      },
    );
  });

  group('race conditions adicionais', () {
    test('erro antigo não sobrescreve requisição nova bem-sucedida', () async {
      source.holdResponses = true;

      final first = controller.setQuery(HealthScheduleQuery(dogId: 'dog-a'));
      final second = controller.setQuery(HealthScheduleQuery(dogId: 'dog-b'));

      // Erro da requisição A (stale) chega primeiro.
      source.failMatching(
        (q) => q.dogId == 'dog-a',
        const HealthScheduleSourceException('erro de A'),
      );
      await Future<void>.delayed(Duration.zero);
      expect(controller.state, isA<HealthScheduleLoading>());
      expect((controller.state as HealthScheduleLoading).dogId, 'dog-b');

      source.completeMatching(
        (q) => q.dogId == 'dog-b',
        schedulePage([
          scheduleItem(
            id: 'b-ok',
            dogId: 'dog-b',
            scheduledFor: scheduleTestNow.add(const Duration(days: 2)),
          ),
        ]),
      );
      await second;
      await first;

      expect(controller.state, isA<HealthScheduleData>());
      final data = controller.state as HealthScheduleData;
      expect(data.dogId, 'dog-b');
      expect(data.items.single.id, 'b-ok');
      expect(data.lastRefreshError, isNull);
    });
  });

  group('dispose', () {
    test(
      'resposta tardia após dispose não atualiza estado nem notifica',
      () async {
        source.holdResponses = true;
        final pending = controller.setQuery(
          HealthScheduleQuery(dogId: 'dog-a'),
        );
        expect(controller.state, isA<HealthScheduleLoading>());

        var notifications = 0;
        controller.addListener(() => notifications++);

        controller.dispose();
        expect(controller.isDisposedForTest, isTrue);

        source.completeNext(
          schedulePage([
            scheduleItem(
              id: 'late',
              scheduledFor: scheduleTestNow.add(const Duration(days: 1)),
            ),
          ]),
        );
        await pending;
        await Future<void>.delayed(Duration.zero);

        // Continua no loading da requisição descartada — sem promote para data.
        expect(controller.state, isA<HealthScheduleLoading>());
        expect((controller.state as HealthScheduleLoading).dogId, 'dog-a');
        expect(notifications, 0);
      },
    );
  });

  group('clock injetável', () {
    test('mudança de now altera classificação na próxima carga', () async {
      final scheduled = scheduleTestNow.add(const Duration(days: 3));
      source.enqueuePage(
        schedulePage([scheduleItem(id: '1', scheduledFor: scheduled)]),
      );
      await controller.setQuery(HealthScheduleQuery(dogId: 'dog-a'));
      expect(
        (controller.state as HealthScheduleData).items.single.temporalStatus,
        HealthScheduleTemporalStatus.upcoming,
      );

      clockNow = scheduled.add(const Duration(days: 2));
      source.enqueuePage(
        schedulePage([scheduleItem(id: '1', scheduledFor: scheduled)]),
      );
      await controller.refresh();
      expect(
        (controller.state as HealthScheduleData).items.single.temporalStatus,
        HealthScheduleTemporalStatus.overdue,
      );
    });
  });

  group('query', () {
    test('dogId vazio lança', () {
      expect(() => HealthScheduleQuery(dogId: ''), throwsArgumentError);
      expect(() => controller.selectDog('  '), throwsArgumentError);
    });
  });
}
