// Copyright 2024 GCM Health. All rights reserved.

import 'package:canil_gcm/features/health/data/shadow/health_timeline_shadow_models.dart';

/// Tipos de outcome sanitizados para observabilidade do shadow.
enum HealthTimelineShadowTelemetryOutcomeType {
  comparison('comparison'),
  skipped('skipped'),
  failure('failure');

  const HealthTimelineShadowTelemetryOutcomeType(this.wireValue);

  final String wireValue;
}

/// Buckets de contagens numéricas para eliminar cardinalidade e reidentificação.
enum HealthTimelineShadowCountBucket {
  zero('0'),
  one('1'),
  twoToFive('2_5'),
  sixToTen('6_10'),
  elevenToTwentyFive('11_25'),
  twentySixPlus('26_plus');

  const HealthTimelineShadowCountBucket(this.wireValue);

  final String wireValue;
}

/// Transforma um inteiro não-negativo de contagem no seu bucket sanitizado.
HealthTimelineShadowCountBucket bucketHealthTimelineShadowCount(int value) {
  if (value < 0) {
    throw ArgumentError('Count cannot be negative: $value');
  }

  if (value == 0) return HealthTimelineShadowCountBucket.zero;
  if (value == 1) return HealthTimelineShadowCountBucket.one;
  if (value <= 5) return HealthTimelineShadowCountBucket.twoToFive;
  if (value <= 10) return HealthTimelineShadowCountBucket.sixToTen;
  if (value <= 25) return HealthTimelineShadowCountBucket.elevenToTwentyFive;
  return HealthTimelineShadowCountBucket.twentySixPlus;
}

/// Buckets discretos de latência para eliminar fingerprinting temporal.
enum HealthTimelineShadowLatencyBucket {
  unknown('unknown'),
  lessThan100('lt_100'),
  from100To249('100_249'),
  from250To499('250_499'),
  from500To999('500_999'),
  from1000To1999('1000_1999'),
  from2000To4999('2000_4999'),
  atLeast5000('gte_5000');

  const HealthTimelineShadowLatencyBucket(this.wireValue);

  final String wireValue;
}

/// Transforma latência em milissegundos no seu bucket sanitizado.
HealthTimelineShadowLatencyBucket bucketHealthTimelineShadowLatency(
  int? milliseconds,
) {
  if (milliseconds == null) {
    return HealthTimelineShadowLatencyBucket.unknown;
  }
  if (milliseconds < 0) {
    throw ArgumentError('Latency cannot be negative: $milliseconds');
  }

  if (milliseconds < 100) {
    return HealthTimelineShadowLatencyBucket.lessThan100;
  }
  if (milliseconds < 250) {
    return HealthTimelineShadowLatencyBucket.from100To249;
  }
  if (milliseconds < 500) {
    return HealthTimelineShadowLatencyBucket.from250To499;
  }
  if (milliseconds < 1000) {
    return HealthTimelineShadowLatencyBucket.from500To999;
  }
  if (milliseconds < 2000) {
    return HealthTimelineShadowLatencyBucket.from1000To1999;
  }
  if (milliseconds < 5000) {
    return HealthTimelineShadowLatencyBucket.from2000To4999;
  }
  return HealthTimelineShadowLatencyBucket.atLeast5000;
}

/// Wire values para [HealthTimelineShadowSkipKind].
extension HealthTimelineShadowSkipKindWireValue
    on HealthTimelineShadowSkipKind {
  String get wireValue {
    return switch (this) {
      HealthTimelineShadowSkipKind.notFirstPage => 'not_first_page',
      HealthTimelineShadowSkipKind.unsupportedTypes => 'unsupported_types',
      HealthTimelineShadowSkipKind.unsupportedCaseId => 'unsupported_case_id',
      HealthTimelineShadowSkipKind.unsupportedProfessional =>
        'unsupported_professional',
    };
  }
}

/// Wire values para [HealthTimelineShadowFailureKind].
extension HealthTimelineShadowFailureKindWireValue
    on HealthTimelineShadowFailureKind {
  String get wireValue {
    return switch (this) {
      HealthTimelineShadowFailureKind.primaryFailure => 'primary_failure',
      HealthTimelineShadowFailureKind.shadowFailure => 'shadow_failure',
      HealthTimelineShadowFailureKind.shadowTimeout => 'shadow_timeout',
      HealthTimelineShadowFailureKind.comparatorFailure => 'comparator_failure',
    };
  }
}

/// Contrato imutável e selado de registro de telemetria sanitizada do shadow.
sealed class HealthTimelineShadowTelemetryRecord {
  const HealthTimelineShadowTelemetryRecord();

  int get schemaVersion => 1;
  HealthTimelineShadowTelemetryOutcomeType get outcomeType;
  Map<String, Object> toJson();
}

/// Telemetria sanitizada de comparação executada com sucesso.
final class HealthTimelineShadowTelemetryComparison
    extends HealthTimelineShadowTelemetryRecord {
  const HealthTimelineShadowTelemetryComparison({
    required this.primaryCountBucket,
    required this.shadowCountBucket,
    required this.matchedCountBucket,
    required this.missingCountBucket,
    required this.extraCountBucket,
    required this.uncorrelatedPrimaryCountBucket,
    required this.uncorrelatedShadowCountBucket,
    required this.ambiguousPrimaryCountBucket,
    required this.ambiguousShadowCountBucket,
    required this.orderingMismatch,
    required this.latencyBucket,
  });

  final HealthTimelineShadowCountBucket primaryCountBucket;
  final HealthTimelineShadowCountBucket shadowCountBucket;
  final HealthTimelineShadowCountBucket matchedCountBucket;
  final HealthTimelineShadowCountBucket missingCountBucket;
  final HealthTimelineShadowCountBucket extraCountBucket;
  final HealthTimelineShadowCountBucket uncorrelatedPrimaryCountBucket;
  final HealthTimelineShadowCountBucket uncorrelatedShadowCountBucket;
  final HealthTimelineShadowCountBucket ambiguousPrimaryCountBucket;
  final HealthTimelineShadowCountBucket ambiguousShadowCountBucket;
  final bool orderingMismatch;
  final HealthTimelineShadowLatencyBucket latencyBucket;

  @override
  HealthTimelineShadowTelemetryOutcomeType get outcomeType =>
      HealthTimelineShadowTelemetryOutcomeType.comparison;

  @override
  Map<String, Object> toJson() {
    return {
      'schema_version': schemaVersion,
      'outcome_type': outcomeType.wireValue,
      'primary_count_bucket': primaryCountBucket.wireValue,
      'shadow_count_bucket': shadowCountBucket.wireValue,
      'matched_count_bucket': matchedCountBucket.wireValue,
      'missing_count_bucket': missingCountBucket.wireValue,
      'extra_count_bucket': extraCountBucket.wireValue,
      'uncorrelated_primary_count_bucket':
          uncorrelatedPrimaryCountBucket.wireValue,
      'uncorrelated_shadow_count_bucket':
          uncorrelatedShadowCountBucket.wireValue,
      'ambiguous_primary_count_bucket': ambiguousPrimaryCountBucket.wireValue,
      'ambiguous_shadow_count_bucket': ambiguousShadowCountBucket.wireValue,
      'ordering_mismatch': orderingMismatch,
      'latency_bucket': latencyBucket.wireValue,
    };
  }
}

/// Telemetria sanitizada de execução ignorada devido a critérios de elegibilidade.
final class HealthTimelineShadowTelemetrySkipped
    extends HealthTimelineShadowTelemetryRecord {
  const HealthTimelineShadowTelemetrySkipped({required this.skipKind});

  final HealthTimelineShadowSkipKind skipKind;

  @override
  HealthTimelineShadowTelemetryOutcomeType get outcomeType =>
      HealthTimelineShadowTelemetryOutcomeType.skipped;

  @override
  Map<String, Object> toJson() {
    return {
      'schema_version': schemaVersion,
      'outcome_type': outcomeType.wireValue,
      'skip_kind': skipKind.wireValue,
    };
  }
}

/// Telemetria sanitizada de falha na execução ou no comparador shadow.
final class HealthTimelineShadowTelemetryFailure
    extends HealthTimelineShadowTelemetryRecord {
  const HealthTimelineShadowTelemetryFailure({
    required this.failureKind,
    required this.latencyBucket,
  });

  final HealthTimelineShadowFailureKind failureKind;
  final HealthTimelineShadowLatencyBucket latencyBucket;

  @override
  HealthTimelineShadowTelemetryOutcomeType get outcomeType =>
      HealthTimelineShadowTelemetryOutcomeType.failure;

  @override
  Map<String, Object> toJson() {
    return {
      'schema_version': schemaVersion,
      'outcome_type': outcomeType.wireValue,
      'failure_kind': failureKind.wireValue,
      'latency_bucket': latencyBucket.wireValue,
    };
  }
}
