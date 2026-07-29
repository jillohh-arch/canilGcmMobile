// Copyright 2024 GCM Health. All rights reserved.
//
// HEALTH TIMELINE SHADOW COMPOSITION FACTORY — Synchronous, lazy, pure composition.
//
// Pure synthetic composition. NO Remote Config resolution. NO Firebase.

import 'package:canil_gcm/features/health/data/config/health_timeline_mode.dart';
import 'package:canil_gcm/features/health/data/shadow/health_timeline_shadow_models.dart';
import 'package:canil_gcm/features/health/data/shadow/health_timeline_shadow_runner.dart';
import 'package:canil_gcm/features/health/data/shadow/health_timeline_shadow_runner_executor.dart';
import 'package:canil_gcm/features/health/data/shadow/shadow_comparing_health_timeline_source.dart';
import 'package:canil_gcm/features/health/presentation/timeline/health_timeline_source.dart';

/// Factory síncrona e lazy que compõe a [HealthTimelineSource] apropriada
/// para uma resolução de modo [HealthTimelineModeResolution] previamente capturada.
final class HealthTimelineShadowCompositionFactory {
  const HealthTimelineShadowCompositionFactory({
    required HealthTimelineSource Function() coexistenceSourceFactory,
    required HealthTimelineShadowRunner Function() runnerFactory,
    HealthTimelineShadowObserver? observer,
    HealthTimelineShadowRunnerExecutor runnerExecutor =
        const DefaultHealthTimelineShadowRunnerExecutor(),
    Duration shadowTimeout = const Duration(seconds: 5),
  }) : _coexistenceSourceFactory = coexistenceSourceFactory,
       _runnerFactory = runnerFactory,
       _observer = observer,
       _runnerExecutor = runnerExecutor,
       _shadowTimeout = shadowTimeout;

  final HealthTimelineSource Function() _coexistenceSourceFactory;
  final HealthTimelineShadowRunner Function() _runnerFactory;
  final HealthTimelineShadowObserver? _observer;
  final HealthTimelineShadowRunnerExecutor _runnerExecutor;
  final Duration _shadowTimeout;

  /// Retorna a source composta de acordo com a resolução do modo.
  HealthTimelineSource createForResolution(
    HealthTimelineModeResolution resolution,
  ) {
    final primarySource = _coexistenceSourceFactory();

    return switch (resolution.mode) {
      HealthTimelineMode.legacyOnly => primarySource,

      HealthTimelineMode.shadowCompare =>
        ShadowComparingHealthTimelineSource.withRunner(
          primarySource: primarySource,
          runner: _runnerFactory(),
          observer: _observer,
          shadowTimeout: _shadowTimeout,
          runnerExecutor: _runnerExecutor,
        ),

      HealthTimelineMode.canonicalPrimary => primarySource,
    };
  }
}
