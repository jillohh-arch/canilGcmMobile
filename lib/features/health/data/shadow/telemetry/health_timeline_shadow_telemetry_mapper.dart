// Copyright 2024 GCM Health. All rights reserved.

import 'package:canil_gcm/features/health/data/shadow/health_timeline_shadow_models.dart';

import 'health_timeline_shadow_telemetry_contract.dart';

/// Mapper utilitário e puro que converte outcomes de observação shadow em registros sanitizados.
abstract final class HealthTimelineShadowTelemetryMapper {
  HealthTimelineShadowTelemetryMapper._();

  /// Converte um [HealthTimelineShadowOutcome] em um [HealthTimelineShadowTelemetryRecord].
  static HealthTimelineShadowTelemetryRecord fromOutcome(
    HealthTimelineShadowOutcome outcome,
  ) {
    return switch (outcome) {
      HealthTimelineShadowComparison c =>
        HealthTimelineShadowTelemetryComparison(
          primaryCountBucket: bucketHealthTimelineShadowCount(c.primaryCount),
          shadowCountBucket: bucketHealthTimelineShadowCount(c.shadowCount),
          matchedCountBucket: bucketHealthTimelineShadowCount(c.matchedCount),
          missingCountBucket: bucketHealthTimelineShadowCount(c.missingCount),
          extraCountBucket: bucketHealthTimelineShadowCount(c.extraCount),
          uncorrelatedPrimaryCountBucket: bucketHealthTimelineShadowCount(
            c.uncorrelatedPrimaryCount,
          ),
          uncorrelatedShadowCountBucket: bucketHealthTimelineShadowCount(
            c.uncorrelatedShadowCount,
          ),
          ambiguousPrimaryCountBucket: bucketHealthTimelineShadowCount(
            c.ambiguousPrimaryCount,
          ),
          ambiguousShadowCountBucket: bucketHealthTimelineShadowCount(
            c.ambiguousShadowCount,
          ),
          orderingMismatch: c.orderingMismatch,
          latencyBucket: bucketHealthTimelineShadowLatency(c.shadowLatencyMs),
        ),
      HealthTimelineShadowSkipped s => HealthTimelineShadowTelemetrySkipped(
        skipKind: s.skipKind,
      ),
      HealthTimelineShadowFailure f => HealthTimelineShadowTelemetryFailure(
        failureKind: f.failureKind,
        latencyBucket: bucketHealthTimelineShadowLatency(f.shadowLatencyMs),
      ),
    };
  }
}
