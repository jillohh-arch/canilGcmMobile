// Copyright 2024 GCM Health. All rights reserved.
//
// Tests for Health Timeline Shadow Runner Executor (4C-C-C-H2A).
//
// Exactly 16 test declarations. Zero functional timing / wall-clock delays.

import 'dart:async';

import 'package:canil_gcm/features/health/data/shadow/health_timeline_shadow_models.dart';
import 'package:canil_gcm/features/health/data/shadow/health_timeline_shadow_runner.dart';
import 'package:canil_gcm/features/health/data/shadow/health_timeline_shadow_runner_executor.dart';
import 'package:flutter_test/flutter_test.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Test Fakes — Zero wall clock delays.
// ─────────────────────────────────────────────────────────────────────────────

class _FakeElapsedTimer implements HealthTimelineShadowElapsedTimer {
  _FakeElapsedTimer({
    this.configuredLatencyMs = 42,
    this.stopError,
    this.elapsedError,
    this.events,
  });

  final int configuredLatencyMs;
  final Object? stopError;
  final Object? elapsedError;
  final List<String>? events;

  int startCalls = 0;
  int stopCalls = 0;
  int elapsedReads = 0;

  @override
  void start() {
    startCalls++;
    events?.add('timer.started');
  }

  @override
  void stop() {
    stopCalls++;
    events?.add('timer.stopped');
    final err = stopError;
    if (err != null) throw err;
  }

  @override
  int get elapsedMilliseconds {
    elapsedReads++;
    final err = elapsedError;
    if (err != null) throw err;
    return configuredLatencyMs;
  }
}

class _FakeRunnerTimeoutExecutor
    implements HealthTimelineShadowRunnerTimeoutExecutor {
  _FakeRunnerTimeoutExecutor({
    this.forceTimeout = false,
    this.forceThrow = false,
    this.events,
  });

  final bool forceTimeout;
  final bool forceThrow;
  final List<String>? events;

  int calls = 0;
  Duration? receivedTimeout;
  Future<HealthTimelineShadowRunResult> Function()? receivedOperation;

  @override
  Future<HealthTimelineShadowRunResult> execute({
    required Future<HealthTimelineShadowRunResult> Function() operation,
    required Duration timeout,
  }) async {
    calls++;
    receivedTimeout = timeout;
    receivedOperation = operation;
    events?.add('timeoutExecutor.entered');

    if (forceTimeout) {
      throw TimeoutException('Fake timeout');
    }
    if (forceThrow) {
      throw StateError('Fake timeout executor throw');
    }

    return await operation();
  }
}

// Helper builders
HealthTimelineShadowRunSuccess _sampleSuccess() {
  return const HealthTimelineShadowRunSuccess(
    primaryCount: 5,
    shadowCount: 5,
    matchedCount: 5,
    missingCount: 0,
    extraCount: 0,
    uncorrelatedPrimaryCount: 0,
    uncorrelatedShadowCount: 0,
    ambiguousPrimaryCount: 0,
    ambiguousShadowCount: 0,
    orderingMismatch: false,
  );
}

HealthTimelineShadowRunFailure _sampleFailure() {
  return const HealthTimelineShadowRunFailure(
    kind: HealthTimelineShadowFailureKind.shadowFailure,
  );
}

const _kTestTimeout = Duration(seconds: 37);

void main() {
  group('Result contract', () {
    test('execution result hierarchy supports exhaustive matching', () async {
      final HealthTimelineShadowRunnerExecutionResult completed =
          HealthTimelineShadowRunnerCompleted(
            result: _sampleSuccess(),
            elapsedMilliseconds: 10,
          );
      final HealthTimelineShadowRunnerExecutionResult timedOut =
          const HealthTimelineShadowRunnerTimedOut(elapsedMilliseconds: 20);
      final HealthTimelineShadowRunnerExecutionResult threw =
          const HealthTimelineShadowRunnerThrew(elapsedMilliseconds: 30);

      String match(HealthTimelineShadowRunnerExecutionResult r) {
        return switch (r) {
          HealthTimelineShadowRunnerCompleted() => 'completed',
          HealthTimelineShadowRunnerTimedOut() => 'timedOut',
          HealthTimelineShadowRunnerThrew() => 'threw',
        };
      }

      expect(match(completed), 'completed');
      expect(match(timedOut), 'timedOut');
      expect(match(threw), 'threw');
    });
  });

  group('Completed', () {
    test(
      'completed preserves identical success result and elapsed milliseconds',
      () async {
        final expectedResult = _sampleSuccess();
        final timer = _FakeElapsedTimer(configuredLatencyMs: 150);
        final timeoutExecutor = _FakeRunnerTimeoutExecutor();

        final executor =
            DefaultHealthTimelineShadowRunnerExecutor.withDependencies(
              timerFactory: () => timer,
              timeoutExecutor: timeoutExecutor,
            );

        final res = await executor.execute(
          operation: () => Future.value(expectedResult),
          timeout: _kTestTimeout,
        );

        expect(res, isA<HealthTimelineShadowRunnerCompleted>());
        final completed = res as HealthTimelineShadowRunnerCompleted;
        expect(identical(completed.result, expectedResult), isTrue);
        expect(completed.elapsedMilliseconds, 150);
      },
    );

    test(
      'completed preserves identical typed failure result and elapsed milliseconds',
      () async {
        final expectedResult = _sampleFailure();
        final timer = _FakeElapsedTimer(configuredLatencyMs: 80);
        final timeoutExecutor = _FakeRunnerTimeoutExecutor();

        final executor =
            DefaultHealthTimelineShadowRunnerExecutor.withDependencies(
              timerFactory: () => timer,
              timeoutExecutor: timeoutExecutor,
            );

        final res = await executor.execute(
          operation: () => Future.value(expectedResult),
          timeout: _kTestTimeout,
        );

        expect(res, isA<HealthTimelineShadowRunnerCompleted>());
        final completed = res as HealthTimelineShadowRunnerCompleted;
        expect(identical(completed.result, expectedResult), isTrue);
        expect(completed.elapsedMilliseconds, 80);
      },
    );
  });

  group('Exceptions e timeout', () {
    test(
      'synchronous operation throw returns Threw with elapsed milliseconds',
      () async {
        final timer = _FakeElapsedTimer(configuredLatencyMs: 45);
        final timeoutExecutor = _FakeRunnerTimeoutExecutor();

        final executor =
            DefaultHealthTimelineShadowRunnerExecutor.withDependencies(
              timerFactory: () => timer,
              timeoutExecutor: timeoutExecutor,
            );

        final res = await executor.execute(
          operation: () {
            throw StateError('sync_boom');
          },
          timeout: _kTestTimeout,
        );

        expect(res, isA<HealthTimelineShadowRunnerThrew>());
        final threw = res as HealthTimelineShadowRunnerThrew;
        expect(threw.elapsedMilliseconds, 45);
      },
    );

    test(
      'asynchronous operation error returns Threw with elapsed milliseconds',
      () async {
        final timer = _FakeElapsedTimer(configuredLatencyMs: 95);
        final timeoutExecutor = _FakeRunnerTimeoutExecutor();

        final executor =
            DefaultHealthTimelineShadowRunnerExecutor.withDependencies(
              timerFactory: () => timer,
              timeoutExecutor: timeoutExecutor,
            );

        final res = await executor.execute(
          operation: () => Future.error(Exception('async_boom')),
          timeout: _kTestTimeout,
        );

        expect(res, isA<HealthTimelineShadowRunnerThrew>());
        final threw = res as HealthTimelineShadowRunnerThrew;
        expect(threw.elapsedMilliseconds, 95);
      },
    );

    test(
      'TimeoutException returns TimedOut with elapsed milliseconds',
      () async {
        final timer = _FakeElapsedTimer(configuredLatencyMs: 5000);
        final timeoutExecutor = _FakeRunnerTimeoutExecutor(forceTimeout: true);

        final executor =
            DefaultHealthTimelineShadowRunnerExecutor.withDependencies(
              timerFactory: () => timer,
              timeoutExecutor: timeoutExecutor,
            );

        final res = await executor.execute(
          operation: () => Future.value(_sampleSuccess()),
          timeout: _kTestTimeout,
        );

        expect(res, isA<HealthTimelineShadowRunnerTimedOut>());
        final timedOut = res as HealthTimelineShadowRunnerTimedOut;
        expect(timedOut.elapsedMilliseconds, 5000);
      },
    );
  });

  group('Invocation contract', () {
    test('operation is invoked exactly once', () async {
      var opCalls = 0;
      final timer = _FakeElapsedTimer();
      final timeoutExecutor = _FakeRunnerTimeoutExecutor();

      final executor =
          DefaultHealthTimelineShadowRunnerExecutor.withDependencies(
            timerFactory: () => timer,
            timeoutExecutor: timeoutExecutor,
          );

      await executor.execute(
        operation: () {
          opCalls++;
          return Future.value(_sampleSuccess());
        },
        timeout: _kTestTimeout,
      );

      expect(opCalls, 1);
    });

    test('timeout executor is invoked exactly once', () async {
      final timer = _FakeElapsedTimer();
      final timeoutExecutor = _FakeRunnerTimeoutExecutor();

      final executor =
          DefaultHealthTimelineShadowRunnerExecutor.withDependencies(
            timerFactory: () => timer,
            timeoutExecutor: timeoutExecutor,
          );

      await executor.execute(
        operation: () => Future.value(_sampleSuccess()),
        timeout: _kTestTimeout,
      );

      expect(timeoutExecutor.calls, 1);
    });

    test(
      'configured timeout is forwarded unchanged to timeout executor',
      () async {
        final timer = _FakeElapsedTimer();
        final timeoutExecutor = _FakeRunnerTimeoutExecutor();

        final executor =
            DefaultHealthTimelineShadowRunnerExecutor.withDependencies(
              timerFactory: () => timer,
              timeoutExecutor: timeoutExecutor,
            );

        await executor.execute(
          operation: () => Future.value(_sampleSuccess()),
          timeout: _kTestTimeout,
        );

        expect(timeoutExecutor.receivedTimeout, equals(_kTestTimeout));
      },
    );
  });

  group('Timer lifecycle', () {
    test('timer starts before timeout executor invokes operation', () async {
      final events = <String>[];
      final timer = _FakeElapsedTimer(events: events);
      final timeoutExecutor = _FakeRunnerTimeoutExecutor(events: events);

      final executor =
          DefaultHealthTimelineShadowRunnerExecutor.withDependencies(
            timerFactory: () => timer,
            timeoutExecutor: timeoutExecutor,
          );

      await executor.execute(
        operation: () {
          events.add('operation.called');
          return Future.value(_sampleSuccess());
        },
        timeout: _kTestTimeout,
      );

      expect(events, [
        'timer.started',
        'timeoutExecutor.entered',
        'operation.called',
        'timer.stopped',
      ]);
      final startIdx = events.indexOf('timer.started');
      final opIdx = events.indexOf('operation.called');
      expect(startIdx, lessThan(opIdx));
    });

    test('timer stops exactly once after completed execution', () async {
      final timer = _FakeElapsedTimer();
      final timeoutExecutor = _FakeRunnerTimeoutExecutor();

      final executor =
          DefaultHealthTimelineShadowRunnerExecutor.withDependencies(
            timerFactory: () => timer,
            timeoutExecutor: timeoutExecutor,
          );

      await executor.execute(
        operation: () => Future.value(_sampleSuccess()),
        timeout: _kTestTimeout,
      );

      expect(timer.startCalls, 1);
      expect(timer.stopCalls, 1);
    });

    test('timer stops exactly once after thrown execution', () async {
      final timer = _FakeElapsedTimer();
      final timeoutExecutor = _FakeRunnerTimeoutExecutor(forceThrow: true);

      final executor =
          DefaultHealthTimelineShadowRunnerExecutor.withDependencies(
            timerFactory: () => timer,
            timeoutExecutor: timeoutExecutor,
          );

      await executor.execute(
        operation: () => Future.value(_sampleSuccess()),
        timeout: _kTestTimeout,
      );

      expect(timer.startCalls, 1);
      expect(timer.stopCalls, 1);
    });

    test('timer stops exactly once after timed out execution', () async {
      final timer = _FakeElapsedTimer();
      final timeoutExecutor = _FakeRunnerTimeoutExecutor(forceTimeout: true);

      final executor =
          DefaultHealthTimelineShadowRunnerExecutor.withDependencies(
            timerFactory: () => timer,
            timeoutExecutor: timeoutExecutor,
          );

      await executor.execute(
        operation: () => Future.value(_sampleSuccess()),
        timeout: _kTestTimeout,
      );

      expect(timer.startCalls, 1);
      expect(timer.stopCalls, 1);
    });
  });

  group('Default timeout adapter', () {
    test(
      'default timeout executor preserves an immediately completed result and invokes operation once',
      () async {
        const timeoutExecutor =
            DefaultHealthTimelineShadowRunnerTimeoutExecutor();
        final expected = _sampleFailure();
        var opCalls = 0;

        final res = await timeoutExecutor.execute(
          operation: () {
            opCalls++;
            return Future.value(expected);
          },
          timeout: _kTestTimeout,
        );

        expect(opCalls, 1);
        expect(identical(res, expected), isTrue);
      },
    );
  });

  group('Completed path exception isolation', () {
    test(
      'completed-path timer stop failure escapes and is not retried',
      () async {
        final timer = _FakeElapsedTimer(
          stopError: TimeoutException('timer_stop_failure'),
        );
        final timeoutExecutor = _FakeRunnerTimeoutExecutor();

        final executor =
            DefaultHealthTimelineShadowRunnerExecutor.withDependencies(
              timerFactory: () => timer,
              timeoutExecutor: timeoutExecutor,
            );

        await expectLater(
          executor.execute(
            operation: () => Future.value(_sampleSuccess()),
            timeout: _kTestTimeout,
          ),
          throwsA(isA<TimeoutException>()),
        );

        expect(timer.stopCalls, 1);
        expect(timeoutExecutor.calls, 1);
      },
    );

    test(
      'completed-path elapsed getter failure escapes without stopping twice',
      () async {
        final timer = _FakeElapsedTimer(
          elapsedError: StateError('elapsed_failure'),
        );
        final timeoutExecutor = _FakeRunnerTimeoutExecutor();

        final executor =
            DefaultHealthTimelineShadowRunnerExecutor.withDependencies(
              timerFactory: () => timer,
              timeoutExecutor: timeoutExecutor,
            );

        await expectLater(
          executor.execute(
            operation: () => Future.value(_sampleSuccess()),
            timeout: _kTestTimeout,
          ),
          throwsA(isA<StateError>()),
        );

        expect(timer.stopCalls, 1);
        expect(timer.elapsedReads, 1);
        expect(timeoutExecutor.calls, 1);
      },
    );
  });
}
