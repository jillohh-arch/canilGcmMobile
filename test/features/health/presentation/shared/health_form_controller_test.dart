import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'package:canil_gcm/features/health/presentation/shared/forms/health_form_controller.dart';
import 'package:canil_gcm/features/health/presentation/shared/forms/health_form_status.dart';

void main() {
  group('HealthFormController', () {
    late HealthFormController controller;

    setUp(() {
      controller = HealthFormController();
    });

    tearDown(() {
      controller.dispose();
    });

    test('estado inicial é pristine', () {
      expect(controller.status, HealthFormStatus.initial);
      expect(controller.isDirty, isFalse);
      expect(controller.isSubmitting, isFalse);
      expect(controller.hasError, isFalse);
      expect(controller.errorMessage, isNull);
      expect(controller.canSubmit, isTrue);
    });

    test('markDirty altera para dirty e notifica', () {
      var notifications = 0;
      controller.addListener(() => notifications++);

      controller.markDirty();

      expect(controller.isDirty, isTrue);
      expect(controller.status, HealthFormStatus.dirty);
      expect(notifications, 1);

      controller.markDirty();
      expect(notifications, 1);
    });

    test('markPristine limpa dirty e erro', () {
      controller.markDirty();
      controller.clearError();
      controller.markDirty();

      controller.markPristine();

      expect(controller.isDirty, isFalse);
      expect(controller.status, HealthFormStatus.initial);
      expect(controller.errorMessage, isNull);
    });

    test('submit inválido não executa action e grava erro', () async {
      var actionCalls = 0;

      final ok = await controller.submit(
        validate: () => 'Campo obrigatório',
        action: () async {
          actionCalls++;
        },
      );

      expect(ok, isFalse);
      expect(actionCalls, 0);
      expect(controller.status, HealthFormStatus.error);
      expect(controller.errorMessage, 'Campo obrigatório');
      expect(controller.isSubmitting, isFalse);
    });

    test('submit válido passa por submitting e success', () async {
      final statuses = <HealthFormStatus>[];
      controller.addListener(() => statuses.add(controller.status));

      controller.markDirty();
      final ok = await controller.submit(
        validate: () => null,
        action: () async {
          expect(controller.isSubmitting, isTrue);
          expect(controller.canSubmit, isFalse);
        },
      );

      expect(ok, isTrue);
      expect(controller.status, HealthFormStatus.success);
      expect(controller.isDirty, isFalse);
      expect(controller.isSuccess, isTrue);
      expect(statuses, contains(HealthFormStatus.submitting));
      expect(statuses.last, HealthFormStatus.success);
    });

    test('submit com falha preserva dirty e expõe erro', () async {
      controller.markDirty();

      final ok = await controller.submit(
        action: () async {
          throw const HealthFormException('Falha ao salvar');
        },
      );

      expect(ok, isFalse);
      expect(controller.status, HealthFormStatus.error);
      expect(controller.errorMessage, 'Falha ao salvar');
      expect(controller.isDirty, isTrue);
    });

    test('submit após erro permite nova tentativa', () async {
      controller.markDirty();
      await controller.submit(
        action: () async {
          throw const HealthFormException('primeira falha');
        },
      );
      expect(controller.hasError, isTrue);

      final ok = await controller.submit(action: () async {});
      expect(ok, isTrue);
      expect(controller.isSuccess, isTrue);
      expect(controller.isDirty, isFalse);
    });

    test('submit após success permite novo submit', () async {
      await controller.submit(action: () async {});
      expect(controller.isSuccess, isTrue);

      controller.markDirty();
      final ok = await controller.submit(action: () async {});
      expect(ok, isTrue);
      expect(controller.isSuccess, isTrue);
    });

    test('bloqueia submit duplicado enquanto submitting', () async {
      var actionCalls = 0;
      final started = Completer<void>();
      final release = Completer<void>();

      final first = controller.submit(
        action: () async {
          actionCalls++;
          started.complete();
          await release.future;
        },
      );

      await started.future;
      final secondResult = await controller.submit(
        action: () async {
          actionCalls++;
        },
      );
      release.complete();
      final firstResult = await first;

      expect(firstResult, isTrue);
      expect(secondResult, isFalse);
      expect(actionCalls, 1);
      expect(controller.isSubmitting, isFalse);
    });

    test('erro na action não deixa status preso em submitting', () async {
      final ok = await controller.submit(
        action: () async {
          throw StateError('falha inesperada');
        },
      );

      expect(ok, isFalse);
      expect(controller.isSubmitting, isFalse);
      expect(controller.status, HealthFormStatus.error);
      expect(controller.canSubmit, isTrue);
    });

    test(
      'dispose durante submit: Future completa sem notify nem exceção',
      () async {
        var notifications = 0;
        controller.addListener(() => notifications++);

        final started = Completer<void>();
        final release = Completer<void>();

        final submitFuture = controller.submit(
          action: () async {
            started.complete();
            await release.future;
          },
        );

        await started.future;
        expect(controller.isSubmitting, isTrue);
        final notificationsAfterStart = notifications;

        controller.dispose();
        expect(controller.isDisposedForTest, isTrue);

        release.complete();
        final result = await submitFuture;

        expect(result, isFalse);
        expect(notifications, notificationsAfterStart);
        // Nenhuma exceção ao completar após dispose.
      },
    );

    test('dispose durante submit com falha também é seguro', () async {
      var notifications = 0;
      controller.addListener(() => notifications++);

      final started = Completer<void>();
      final release = Completer<void>();

      final submitFuture = controller.submit(
        action: () async {
          started.complete();
          await release.future;
          throw const HealthFormException('falhou após dispose');
        },
      );

      await started.future;
      final notificationsAfterStart = notifications;
      controller.dispose();

      release.complete();
      final result = await submitFuture;

      expect(result, isFalse);
      expect(notifications, notificationsAfterStart);
    });

    test('não notifica após dispose', () async {
      var notifications = 0;
      controller.addListener(() => notifications++);

      controller.markDirty();
      expect(notifications, 1);

      controller.dispose();
      expect(controller.isDisposedForTest, isTrue);

      controller.markDirty();
      controller.markPristine();
      controller.clearError();
      final result = await controller.submit(action: () async {});

      expect(result, isFalse);
      expect(notifications, 1);
    });

    test('submit após dispose retorna false sem executar action', () async {
      var actionCalls = 0;
      controller.dispose();

      final ok = await controller.submit(
        action: () async {
          actionCalls++;
        },
      );

      expect(ok, isFalse);
      expect(actionCalls, 0);
    });

    test('dispose múltiplo é idempotente', () {
      controller.dispose();
      expect(() => controller.dispose(), returnsNormally);
      expect(controller.isDisposedForTest, isTrue);
    });

    test('clearError restaura dirty quando havia erro', () async {
      controller.markDirty();
      await controller.submit(
        action: () async {
          throw Exception('boom');
        },
      );
      expect(controller.hasError, isTrue);

      controller.clearError();

      expect(controller.hasError, isFalse);
      expect(controller.errorMessage, isNull);
      expect(controller.status, HealthFormStatus.dirty);
      expect(controller.isDirty, isTrue);
    });

    test('markDirty é no-op durante submitting', () async {
      final started = Completer<void>();
      final release = Completer<void>();

      final future = controller.submit(
        action: () async {
          started.complete();
          await release.future;
        },
      );
      await started.future;

      controller.markDirty();
      expect(controller.status, HealthFormStatus.submitting);

      release.complete();
      await future;
    });
  });
}
