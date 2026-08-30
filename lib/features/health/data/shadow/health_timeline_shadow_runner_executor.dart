// Copyright 2024 GCM Health. All rights reserved.
//
// HEALTH TIMELINE SHADOW RUNNER EXECUTOR (4C-C-C-H2A).
//
// Deterministic execution seam for HealthTimelineShadowRunner.
// Measures latency, applies timeout, and sanitizes throws.
//
// Privacy: contains NO dogId, query, items, clinical data, payload, or exceptions.

import 'dart:async';

import 'health_timeline_shadow_runner.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Execution Result Union
// ─────────────────────────────────────────────────────────────────────────────

/// Sealed result union for [HealthTimelineShadowRunnerExecutor].
sealed class HealthTimelineShadowRunnerExecutionResult {
  const HealthTimelineShadowRunnerExecutionResult();
}

/// Runner completed execution — preserves the runner's [result] and measured [elapsedMilliseconds].
final class HealthTimelineShadowRunnerCompleted
    extends HealthTimelineShadowRunnerExecutionResult {
  const HealthTimelineShadowRunnerCompleted({
    required this.result,
    required this.elapsedMilliseconds,
  });

  final HealthTimelineShadowRunResult result;
  final int elapsedMilliseconds;
}

/// Runner execution timed out — carries measured [elapsedMilliseconds].
final class HealthTimelineShadowRunnerTimedOut
    extends HealthTimelineShadowRunnerExecutionResult {
  const HealthTimelineShadowRunnerTimedOut({required this.elapsedMilliseconds});

  final int elapsedMilliseconds;
}

/// Runner execution threw a synchronous or asynchronous exception — carries measured [elapsedMilliseconds].
final class HealthTimelineShadowRunnerThrew
    extends HealthTimelineShadowRunnerExecutionResult {
  const HealthTimelineShadowRunnerThrew({required this.elapsedMilliseconds});

  final int elapsedMilliseconds;
}

// ─────────────────────────────────────────────────────────────────────────────
// Seams (Timer & Timeout Executor)
// ─────────────────────────────────────────────────────────────────────────────

/// Abstract timer seam for measuring elapsed milliseconds during runner execution.
abstract interface class HealthTimelineShadowElapsedTimer {
  void start();
  void stop();
  int get elapsedMilliseconds;
}

/// Factory typedef for creating [HealthTimelineShadowElapsedTimer] instances.
typedef HealthTimelineShadowElapsedTimerFactory =
    HealthTimelineShadowElapsedTimer Function();

final class _StopwatchHealthTimelineShadowElapsedTimer
    implements HealthTimelineShadowElapsedTimer {
  final Stopwatch _stopwatch = Stopwatch();

  @override
  void start() {
    _stopwatch.start();
  }

  @override
  void stop() {
    _stopwatch.stop();
  }

  @override
  int get elapsedMilliseconds => _stopwatch.elapsedMilliseconds;
}

/// Abstract timeout executor seam for applying timeouts to runner operations.
abstract interface class HealthTimelineShadowRunnerTimeoutExecutor {
  Future<HealthTimelineShadowRunResult> execute({
    required Future<HealthTimelineShadowRunResult> Function() operation,
    required Duration timeout,
  });
}

/// Production implementation of [HealthTimelineShadowRunnerTimeoutExecutor].
final class DefaultHealthTimelineShadowRunnerTimeoutExecutor
    implements HealthTimelineShadowRunnerTimeoutExecutor {
  const DefaultHealthTimelineShadowRunnerTimeoutExecutor();

  @override
  Future<HealthTimelineShadowRunResult> execute({
    required Future<HealthTimelineShadowRunResult> Function() operation,
    required Duration timeout,
  }) {
    final operationFuture = Future<HealthTimelineShadowRunResult>.sync(
      operation,
    );

    return operationFuture.timeout(timeout);
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Public Interface & Default Implementation
// ─────────────────────────────────────────────────────────────────────────────

/// Abstract interface for executing a [HealthTimelineShadowRunner] operation safely
/// with latency measurement and timeout control.
abstract interface class HealthTimelineShadowRunnerExecutor {
  Future<HealthTimelineShadowRunnerExecutionResult> execute({
    required Future<HealthTimelineShadowRunResult> Function() operation,
    required Duration timeout,
  });
}

/// Default production implementation of [HealthTimelineShadowRunnerExecutor].
final class DefaultHealthTimelineShadowRunnerExecutor
    implements HealthTimelineShadowRunnerExecutor {
  const DefaultHealthTimelineShadowRunnerExecutor()
    : _timerFactory = _defaultTimerFactory,
      _timeoutExecutor =
          const DefaultHealthTimelineShadowRunnerTimeoutExecutor();

  const DefaultHealthTimelineShadowRunnerExecutor.withDependencies({
    required HealthTimelineShadowElapsedTimerFactory timerFactory,
    required HealthTimelineShadowRunnerTimeoutExecutor timeoutExecutor,
  }) : _timerFactory = timerFactory,
       _timeoutExecutor = timeoutExecutor;

  static HealthTimelineShadowElapsedTimer _defaultTimerFactory() =>
      _StopwatchHealthTimelineShadowElapsedTimer();

  final HealthTimelineShadowElapsedTimerFactory _timerFactory;
  final HealthTimelineShadowRunnerTimeoutExecutor _timeoutExecutor;

  @override
  Future<HealthTimelineShadowRunnerExecutionResult> execute({
    required Future<HealthTimelineShadowRunResult> Function() operation,
    required Duration timeout,
  }) async {
    final timer = _timerFactory();
    timer.start();

    late final HealthTimelineShadowRunResult result;

    try {
      result = await _timeoutExecutor.execute(
        operation: operation,
        timeout: timeout,
      );
    } on TimeoutException {
      timer.stop();

      return HealthTimelineShadowRunnerTimedOut(
        elapsedMilliseconds: timer.elapsedMilliseconds,
      );
    } on Object {
      timer.stop();

      return HealthTimelineShadowRunnerThrew(
        elapsedMilliseconds: timer.elapsedMilliseconds,
      );
    }

    timer.stop();

    return HealthTimelineShadowRunnerCompleted(
      result: result,
      elapsedMilliseconds: timer.elapsedMilliseconds,
    );
  }
}
