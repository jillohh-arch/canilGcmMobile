import 'package:flutter_test/flutter_test.dart';

import 'package:canil_gcm/features/health/domain/health_v1_enums_ext.dart';
import 'package:canil_gcm/features/health/presentation/schedule/health_schedule_global_controller.dart';
import 'package:canil_gcm/features/health/presentation/schedule/health_schedule_global_query.dart';
import 'package:canil_gcm/features/health/presentation/schedule/health_schedule_global_state.dart';
import 'package:canil_gcm/features/health/presentation/schedule/health_schedule_source.dart';

import 'fake_health_schedule_global_source.dart';
import 'schedule_test_helpers.dart';

/// HW-4C — estado da Agenda Global.
///
/// Invariantes protegidos:
///   1. catálogo vazio NÃO emite query;
///   2. permission-denied e erro técnico não colapsam em vazio;
///   3. resposta stale nunca sobrescreve catálogo novo;
///   4. truncated é preservado;
///   5. estados temporais derivam da policy única.
void main() {
  late FakeHealthScheduleGlobalSource source;
  late HealthScheduleGlobalController controller;
  late DateTime clockNow;

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
    // O teste de dispose descarta o controller por conta própria; um segundo
    // dispose viola o contrato do ChangeNotifier.
    if (!controller.isDisposedForTest) controller.dispose();
  });

  group('catálogo', () {
    test('estado inicial é Initial', () {
      expect(controller.state, isA<HealthScheduleGlobalInitial>());
      expect(source.callCount, 0);
    });

    test('catálogo vazio → NoCatalog sem emitir query', () async {
      await controller.setCatalog(const []);

      expect(controller.state, isA<HealthScheduleGlobalNoCatalog>());
      expect(
        source.callCount,
        0,
        reason: 'catálogo vazio não pode emitir query collection-group',
      );
    });

    test('catálogo com itens → Data com catalogSize', () async {
      source.enqueueItems([
        scheduleItem(id: 's1', dogId: 'dog-a'),
        scheduleItem(id: 's2', dogId: 'dog-b'),
      ]);

      await controller.setCatalog(const ['dog-a', 'dog-b']);

      final state = controller.state;
      expect(state, isA<HealthScheduleGlobalData>());
      final snapshot = (state as HealthScheduleGlobalData).snapshot;
      expect(snapshot.items, hasLength(2));
      expect(snapshot.catalogSize, 2);
      expect(source.callCount, 1);
      expect(source.requests.single.authorizedDogIds, ['dog-a', 'dog-b']);
    });

    test('catálogo válido sem itens → Empty (não NoCatalog)', () async {
      source.enqueueItems(const []);

      await controller.setCatalog(const ['dog-a']);

      final state = controller.state;
      expect(state, isA<HealthScheduleGlobalEmpty>());
      expect((state as HealthScheduleGlobalEmpty).catalogSize, 1);
    });

    test('lifecycle consultado é o persistido', () async {
      source.enqueueItems(const []);
      await controller.setCatalog(const [
        'dog-a',
      ], lifecycleStatus: ScheduleLifecycleStatus.completed);

      expect(
        source.requests.single.lifecycleStatus,
        ScheduleLifecycleStatus.completed,
      );
    });
  });

  group('loading', () {
    test('emite Loading antes da resposta', () async {
      source.holdResponses = true;
      final future = controller.setCatalog(const ['dog-a']);

      expect(controller.state, isA<HealthScheduleGlobalLoading>());

      source.completeNextItems([scheduleItem()]);
      await future;
      expect(controller.state, isA<HealthScheduleGlobalData>());
    });
  });

  group('erros não colapsam em vazio', () {
    test('permission-denied → PermissionDenied', () async {
      source.enqueueError(
        const HealthScheduleSourceException(
          'Sem permissão',
          isPermissionDenied: true,
        ),
      );

      await controller.setCatalog(const ['dog-a']);

      expect(controller.state, isA<HealthScheduleGlobalPermissionDenied>());
    });

    test('failed-precondition (índice) → Error, não Empty', () async {
      source.enqueueError(
        const HealthScheduleSourceException(
          'Consulta indisponível: índice ausente.',
        ),
      );

      await controller.setCatalog(const ['dog-a']);

      final state = controller.state;
      expect(state, isA<HealthScheduleGlobalError>());
      expect(state, isNot(isA<HealthScheduleGlobalEmpty>()));
      expect((state as HealthScheduleGlobalError).isOffline, isFalse);
    });

    test('offline → Error com isOffline', () async {
      source.enqueueError(
        const HealthScheduleSourceException('Sem conexão', isOffline: true),
      );

      await controller.setCatalog(const ['dog-a']);

      final state = controller.state;
      expect(state, isA<HealthScheduleGlobalError>());
      expect((state as HealthScheduleGlobalError).isOffline, isTrue);
    });
  });

  group('truncated', () {
    test('truncated preservado no snapshot', () async {
      source.enqueueItems([scheduleItem()], truncated: true);

      await controller.setCatalog(const ['dog-a']);

      final snapshot = (controller.state as HealthScheduleGlobalData).snapshot;
      expect(snapshot.truncated, isTrue);
    });

    test('não truncado → false', () async {
      source.enqueueItems([scheduleItem()]);
      await controller.setCatalog(const ['dog-a']);
      expect(
        (controller.state as HealthScheduleGlobalData).snapshot.truncated,
        isFalse,
      );
    });
  });

  group('refresh', () {
    test('refresh sem catálogo lança StateError', () {
      expect(() => controller.refresh(), throwsStateError);
    });

    test('refresh preserva dados durante a operação', () async {
      source.enqueueItems([scheduleItem(id: 's1')]);
      await controller.setCatalog(const ['dog-a']);

      source.holdResponses = true;
      final future = controller.refresh();

      final during = controller.state;
      expect(during, isA<HealthScheduleGlobalData>());
      final snapshot = (during as HealthScheduleGlobalData).snapshot;
      expect(snapshot.isRefreshing, isTrue);
      expect(snapshot.items, hasLength(1), reason: 'stale data preservada');

      source.completeNextItems([
        scheduleItem(id: 's1'),
        scheduleItem(id: 's2'),
      ]);
      await future;
      expect(
        (controller.state as HealthScheduleGlobalData).snapshot.items,
        hasLength(2),
      );
    });

    test('falha no refresh preserva lista e reporta erro', () async {
      source.enqueueItems([scheduleItem(id: 's1')]);
      await controller.setCatalog(const ['dog-a']);

      source.enqueueError(
        const HealthScheduleSourceException('Falhou', isOffline: true),
      );
      await controller.refresh();

      final state = controller.state;
      expect(state, isA<HealthScheduleGlobalData>());
      final snapshot = (state as HealthScheduleGlobalData).snapshot;
      expect(snapshot.items, hasLength(1), reason: 'não apaga dados exibidos');
      expect(snapshot.hasRefreshFailure, isTrue);
      expect(snapshot.lastRefreshWasOffline, isTrue);
      expect(snapshot.isRefreshing, isFalse);
    });

    test('refresh não duplica itens', () async {
      source.enqueueItems([scheduleItem(id: 's1')]);
      await controller.setCatalog(const ['dog-a']);

      source.enqueueItems([scheduleItem(id: 's1')]);
      await controller.refresh();

      final snapshot = (controller.state as HealthScheduleGlobalData).snapshot;
      expect(snapshot.items, hasLength(1));
    });
  });

  group('stale response', () {
    test('resposta do catálogo A não sobrescreve catálogo B', () async {
      source.holdResponses = true;

      // Catálogo A inicia.
      final futureA = controller.setCatalog(const ['dog-a']);
      expect(source.callCount, 1);

      // Catálogo B substitui antes da resposta de A.
      final futureB = controller.setCatalog(const ['dog-b']);
      expect(source.callCount, 2);

      // B (o mais recente) responde PRIMEIRO — index 1 na fila.
      source.completeNextItems([
        scheduleItem(id: 'b1', dogId: 'dog-b'),
      ], index: 1);
      // A (stale) responde DEPOIS: é o caso que ameaça sobrescrever B.
      source.completeNextItems([scheduleItem(id: 'a1', dogId: 'dog-a')]);

      await futureA;
      await futureB;

      final snapshot = (controller.state as HealthScheduleGlobalData).snapshot;
      expect(
        snapshot.items.map((e) => e.id),
        ['b1'],
        reason: 'resposta stale de A não pode sobrescrever B',
      );
    });

    test('geração avança a cada setCatalog', () async {
      source.enqueueItems(const []);
      await controller.setCatalog(const ['dog-a']);
      final g1 = controller.generationForTest;

      source.enqueueItems(const []);
      await controller.setCatalog(const ['dog-b']);

      expect(controller.generationForTest, greaterThan(g1));
    });

    test('troca para catálogo vazio invalida resposta em voo', () async {
      source.holdResponses = true;
      final future = controller.setCatalog(const ['dog-a']);

      // Escopo muda para catálogo vazio.
      await controller.setCatalog(const []);
      expect(controller.state, isA<HealthScheduleGlobalNoCatalog>());

      // Resposta antiga chega depois.
      source.completeNextItems([scheduleItem()]);
      await future;

      expect(
        controller.state,
        isA<HealthScheduleGlobalNoCatalog>(),
        reason: 'resposta stale não pode ressuscitar dados',
      );
    });
  });

  group('temporal derivado na leitura', () {
    test('policy única classifica itens (overdue por relógio)', () async {
      // scheduled_for no passado + tolerância de 24h estourada → overdue.
      source.enqueueItems([
        scheduleItem(
          id: 'atrasado',
          scheduledFor: scheduleTestNow.subtract(const Duration(days: 3)),
        ),
      ]);

      await controller.setCatalog(const ['dog-a']);

      final snapshot = (controller.state as HealthScheduleGlobalData).snapshot;
      expect(snapshot.groups.overdue, hasLength(1));
      expect(snapshot.groups.today, isEmpty);
    });

    test('recompute reclassifica sem nova query', () async {
      source.enqueueItems([
        scheduleItem(
          id: 's1',
          scheduledFor: scheduleTestNow.add(const Duration(hours: 2)),
        ),
      ]);
      await controller.setCatalog(const ['dog-a']);

      final callsBefore = source.callCount;
      expect(
        (controller.state as HealthScheduleGlobalData).snapshot.groups.today,
        hasLength(1),
      );

      // Avança o relógio além da tolerância.
      clockNow = scheduleTestNow.add(const Duration(days: 3));
      controller.recomputeTemporalStates();

      final snapshot = (controller.state as HealthScheduleGlobalData).snapshot;
      expect(snapshot.groups.overdue, hasLength(1));
      expect(
        source.callCount,
        callsBefore,
        reason: 'derivação temporal não faz I/O',
      );
    });

    test('itens ordenados globalmente por scheduled_for', () async {
      source.enqueueItems([
        scheduleItem(
          id: 'late',
          dogId: 'dog-b',
          scheduledFor: scheduleTestNow.add(const Duration(days: 2)),
        ),
        scheduleItem(
          id: 'early',
          dogId: 'dog-a',
          scheduledFor: scheduleTestNow.add(const Duration(hours: 1)),
        ),
      ]);

      await controller.setCatalog(const ['dog-a', 'dog-b']);

      final snapshot = (controller.state as HealthScheduleGlobalData).snapshot;
      expect(snapshot.items.map((e) => e.id), ['early', 'late']);
    });
  });

  group('dispose', () {
    test('não notifica após dispose', () async {
      source.holdResponses = true;
      final future = controller.setCatalog(const ['dog-a']);
      controller.dispose();

      source.completeNextItems([scheduleItem()]);
      await future;

      expect(controller.isDisposedForTest, isTrue);
    });
  });

  group('chunk contract', () {
    test('usa o chunk default medido do HW-4A.2D.1', () async {
      source.enqueueItems(const []);
      await controller.setCatalog(const ['dog-a']);

      expect(
        source.requests.single.chunkSize,
        HealthScheduleGlobalQuery.defaultChunkSize,
      );
      expect(HealthScheduleGlobalQuery.defaultChunkSize, 5);
    });
  });
}
