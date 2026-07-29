// Copyright 2024 GCM Health. All rights reserved.

import 'package:flutter_test/flutter_test.dart';
import 'package:canil_gcm/features/health/data/shadow/health_timeline_shadow_models.dart';
import 'package:canil_gcm/features/health/data/shadow/telemetry/health_timeline_shadow_telemetry_contract.dart';
import 'package:canil_gcm/features/health/data/shadow/telemetry/health_timeline_shadow_telemetry_mapper.dart';

void main() {
  group('Count bucket — T1 a T10', () {
    test('T1  negativo lança ArgumentError', () {
      expect(() => bucketHealthTimelineShadowCount(-1), throwsArgumentError);
    });

    test('T2  0 -> zero', () {
      expect(
        bucketHealthTimelineShadowCount(0),
        HealthTimelineShadowCountBucket.zero,
      );
    });

    test('T3  1 -> one', () {
      expect(
        bucketHealthTimelineShadowCount(1),
        HealthTimelineShadowCountBucket.one,
      );
    });

    test('T4  2 -> twoToFive', () {
      expect(
        bucketHealthTimelineShadowCount(2),
        HealthTimelineShadowCountBucket.twoToFive,
      );
    });

    test('T5  5 -> twoToFive', () {
      expect(
        bucketHealthTimelineShadowCount(5),
        HealthTimelineShadowCountBucket.twoToFive,
      );
    });

    test('T6  6 -> sixToTen', () {
      expect(
        bucketHealthTimelineShadowCount(6),
        HealthTimelineShadowCountBucket.sixToTen,
      );
    });

    test('T7  10 -> sixToTen', () {
      expect(
        bucketHealthTimelineShadowCount(10),
        HealthTimelineShadowCountBucket.sixToTen,
      );
    });

    test('T8  11 -> elevenToTwentyFive', () {
      expect(
        bucketHealthTimelineShadowCount(11),
        HealthTimelineShadowCountBucket.elevenToTwentyFive,
      );
    });

    test('T9  25 -> elevenToTwentyFive', () {
      expect(
        bucketHealthTimelineShadowCount(25),
        HealthTimelineShadowCountBucket.elevenToTwentyFive,
      );
    });

    test('T10 26 e valor grande -> twentySixPlus', () {
      expect(
        bucketHealthTimelineShadowCount(26),
        HealthTimelineShadowCountBucket.twentySixPlus,
      );
      expect(
        bucketHealthTimelineShadowCount(1000),
        HealthTimelineShadowCountBucket.twentySixPlus,
      );
    });
  });

  group('Latency bucket — T11 a T19', () {
    test('T11 null -> unknown', () {
      expect(
        bucketHealthTimelineShadowLatency(null),
        HealthTimelineShadowLatencyBucket.unknown,
      );
    });

    test('T12 negativo lança ArgumentError', () {
      expect(() => bucketHealthTimelineShadowLatency(-1), throwsArgumentError);
    });

    test('T13 0 e 99 -> lessThan100', () {
      expect(
        bucketHealthTimelineShadowLatency(0),
        HealthTimelineShadowLatencyBucket.lessThan100,
      );
      expect(
        bucketHealthTimelineShadowLatency(99),
        HealthTimelineShadowLatencyBucket.lessThan100,
      );
    });

    test('T14 100 e 249 -> from100To249', () {
      expect(
        bucketHealthTimelineShadowLatency(100),
        HealthTimelineShadowLatencyBucket.from100To249,
      );
      expect(
        bucketHealthTimelineShadowLatency(249),
        HealthTimelineShadowLatencyBucket.from100To249,
      );
    });

    test('T15 250 e 499 -> from250To499', () {
      expect(
        bucketHealthTimelineShadowLatency(250),
        HealthTimelineShadowLatencyBucket.from250To499,
      );
      expect(
        bucketHealthTimelineShadowLatency(499),
        HealthTimelineShadowLatencyBucket.from250To499,
      );
    });

    test('T16 500 e 999 -> from500To999', () {
      expect(
        bucketHealthTimelineShadowLatency(500),
        HealthTimelineShadowLatencyBucket.from500To999,
      );
      expect(
        bucketHealthTimelineShadowLatency(999),
        HealthTimelineShadowLatencyBucket.from500To999,
      );
    });

    test('T17 1000 e 1999 -> from1000To1999', () {
      expect(
        bucketHealthTimelineShadowLatency(1000),
        HealthTimelineShadowLatencyBucket.from1000To1999,
      );
      expect(
        bucketHealthTimelineShadowLatency(1999),
        HealthTimelineShadowLatencyBucket.from1000To1999,
      );
    });

    test('T18 2000 e 4999 -> from2000To4999', () {
      expect(
        bucketHealthTimelineShadowLatency(2000),
        HealthTimelineShadowLatencyBucket.from2000To4999,
      );
      expect(
        bucketHealthTimelineShadowLatency(4999),
        HealthTimelineShadowLatencyBucket.from2000To4999,
      );
    });

    test('T19 5000 e valor grande -> atLeast5000', () {
      expect(
        bucketHealthTimelineShadowLatency(5000),
        HealthTimelineShadowLatencyBucket.atLeast5000,
      );
      expect(
        bucketHealthTimelineShadowLatency(15000),
        HealthTimelineShadowLatencyBucket.atLeast5000,
      );
    });
  });

  group('Mapper e schema — T20 a T24', () {
    test(
      'T20 comparison bucketiza todos os campos e preserva orderingMismatch',
      () {
        const outcome = HealthTimelineShadowComparison(
          primaryCount: 15,
          shadowCount: 15,
          matchedCount: 15,
          missingCount: 0,
          extraCount: 1,
          uncorrelatedPrimaryCount: 2,
          uncorrelatedShadowCount: 6,
          ambiguousPrimaryCount: 10,
          ambiguousShadowCount: 28,
          orderingMismatch: true,
          shadowLatencyMs: 350,
        );

        final record = HealthTimelineShadowTelemetryMapper.fromOutcome(outcome);

        expect(record, isA<HealthTimelineShadowTelemetryComparison>());
        final comp = record as HealthTimelineShadowTelemetryComparison;

        expect(
          comp.primaryCountBucket,
          HealthTimelineShadowCountBucket.elevenToTwentyFive,
        );
        expect(
          comp.shadowCountBucket,
          HealthTimelineShadowCountBucket.elevenToTwentyFive,
        );
        expect(
          comp.matchedCountBucket,
          HealthTimelineShadowCountBucket.elevenToTwentyFive,
        );
        expect(comp.missingCountBucket, HealthTimelineShadowCountBucket.zero);
        expect(comp.extraCountBucket, HealthTimelineShadowCountBucket.one);
        expect(
          comp.uncorrelatedPrimaryCountBucket,
          HealthTimelineShadowCountBucket.twoToFive,
        );
        expect(
          comp.uncorrelatedShadowCountBucket,
          HealthTimelineShadowCountBucket.sixToTen,
        );
        expect(
          comp.ambiguousPrimaryCountBucket,
          HealthTimelineShadowCountBucket.sixToTen,
        );
        expect(
          comp.ambiguousShadowCountBucket,
          HealthTimelineShadowCountBucket.twentySixPlus,
        );
        expect(comp.orderingMismatch, isTrue);
        expect(
          comp.latencyBucket,
          HealthTimelineShadowLatencyBucket.from250To499,
        );

        final json = comp.toJson();
        expect(json['schema_version'], 1);
        expect(json['outcome_type'], 'comparison');
        expect(json['primary_count_bucket'], '11_25');
        expect(json['shadow_count_bucket'], '11_25');
        expect(json['matched_count_bucket'], '11_25');
        expect(json['missing_count_bucket'], '0');
        expect(json['extra_count_bucket'], '1');
        expect(json['uncorrelated_primary_count_bucket'], '2_5');
        expect(json['uncorrelated_shadow_count_bucket'], '6_10');
        expect(json['ambiguous_primary_count_bucket'], '6_10');
        expect(json['ambiguous_shadow_count_bucket'], '26_plus');
        expect(json['ordering_mismatch'], true);
        expect(json['latency_bucket'], '250_499');
      },
    );

    test('T21 todos os skip kinds têm wire values explícitos corretos', () {
      final notFirst = HealthTimelineShadowTelemetryMapper.fromOutcome(
        const HealthTimelineShadowSkipped(
          skipKind: HealthTimelineShadowSkipKind.notFirstPage,
        ),
      );
      expect(notFirst.toJson()['skip_kind'], 'not_first_page');

      final types = HealthTimelineShadowTelemetryMapper.fromOutcome(
        const HealthTimelineShadowSkipped(
          skipKind: HealthTimelineShadowSkipKind.unsupportedTypes,
        ),
      );
      expect(types.toJson()['skip_kind'], 'unsupported_types');

      final caseId = HealthTimelineShadowTelemetryMapper.fromOutcome(
        const HealthTimelineShadowSkipped(
          skipKind: HealthTimelineShadowSkipKind.unsupportedCaseId,
        ),
      );
      expect(caseId.toJson()['skip_kind'], 'unsupported_case_id');

      final prof = HealthTimelineShadowTelemetryMapper.fromOutcome(
        const HealthTimelineShadowSkipped(
          skipKind: HealthTimelineShadowSkipKind.unsupportedProfessional,
        ),
      );
      expect(prof.toJson()['skip_kind'], 'unsupported_professional');
    });

    test('T22 todos os failure kinds têm wire values explícitos corretos', () {
      final primary = HealthTimelineShadowTelemetryMapper.fromOutcome(
        const HealthTimelineShadowFailure(
          failureKind: HealthTimelineShadowFailureKind.primaryFailure,
          shadowLatencyMs: 50,
        ),
      );
      expect(primary.toJson()['failure_kind'], 'primary_failure');
      expect(primary.toJson()['latency_bucket'], 'lt_100');

      final shadow = HealthTimelineShadowTelemetryMapper.fromOutcome(
        const HealthTimelineShadowFailure(
          failureKind: HealthTimelineShadowFailureKind.shadowFailure,
          shadowLatencyMs: 1500,
        ),
      );
      expect(shadow.toJson()['failure_kind'], 'shadow_failure');
      expect(shadow.toJson()['latency_bucket'], '1000_1999');

      final timeout = HealthTimelineShadowTelemetryMapper.fromOutcome(
        const HealthTimelineShadowFailure(
          failureKind: HealthTimelineShadowFailureKind.shadowTimeout,
          shadowLatencyMs: 5000,
        ),
      );
      expect(timeout.toJson()['failure_kind'], 'shadow_timeout');
      expect(timeout.toJson()['latency_bucket'], 'gte_5000');

      final comparator = HealthTimelineShadowTelemetryMapper.fromOutcome(
        const HealthTimelineShadowFailure(
          failureKind: HealthTimelineShadowFailureKind.comparatorFailure,
          shadowLatencyMs: 300,
        ),
      );
      expect(comparator.toJson()['failure_kind'], 'comparator_failure');
      expect(comparator.toJson()['latency_bucket'], '250_499');
    });

    test('T23 failure com latência null serializa latency_bucket unknown', () {
      final record = HealthTimelineShadowTelemetryMapper.fromOutcome(
        const HealthTimelineShadowFailure(
          failureKind: HealthTimelineShadowFailureKind.primaryFailure,
          shadowLatencyMs: null,
        ),
      );
      final json = record.toJson();
      expect(json['failure_kind'], 'primary_failure');
      expect(json['latency_bucket'], 'unknown');
    });

    test('T24 toJson expõe somente a whitelist e nenhum campo proibido', () {
      const compOutcome = HealthTimelineShadowComparison(
        primaryCount: 1,
        shadowCount: 1,
        matchedCount: 1,
        missingCount: 0,
        extraCount: 0,
        uncorrelatedPrimaryCount: 0,
        uncorrelatedShadowCount: 0,
        ambiguousPrimaryCount: 0,
        ambiguousShadowCount: 0,
        orderingMismatch: false,
        shadowLatencyMs: 120,
      );

      const skipOutcome = HealthTimelineShadowSkipped(
        skipKind: HealthTimelineShadowSkipKind.notFirstPage,
      );

      const failOutcome = HealthTimelineShadowFailure(
        failureKind: HealthTimelineShadowFailureKind.shadowFailure,
        shadowLatencyMs: 550,
      );

      final compJson = HealthTimelineShadowTelemetryMapper.fromOutcome(
        compOutcome,
      ).toJson();
      final skipJson = HealthTimelineShadowTelemetryMapper.fromOutcome(
        skipOutcome,
      ).toJson();
      final failJson = HealthTimelineShadowTelemetryMapper.fromOutcome(
        failOutcome,
      ).toJson();

      final allJsons = [compJson, skipJson, failJson];

      const forbiddenKeys = [
        'dog_id',
        'dogId',
        'uid',
        'userId',
        'user_id',
        'email',
        'document_id',
        'documentId',
        'source_id',
        'sourceId',
        'legacy_id',
        'legacyId',
        'case_id',
        'caseId',
        'payload',
        'exception',
        'message',
        'stack_trace',
        'stackTrace',
        'shadow_latency_ms',
        'shadowLatencyMs',
        'primary_count',
        'primaryCount',
        'shadow_count',
        'shadowCount',
        'recorded_at',
        'recordedAt',
        'app_version',
        'appVersion',
        'build_number',
        'buildNumber',
        'platform',
        'environment',
      ];

      for (final json in allJsons) {
        for (final forbiddenKey in forbiddenKeys) {
          expect(
            json.containsKey(forbiddenKey),
            isFalse,
            reason: 'Key $forbiddenKey must not be in toJson output',
          );
        }
      }

      // Whitelist check
      const whitelistComparisonKeys = {
        'schema_version',
        'outcome_type',
        'primary_count_bucket',
        'shadow_count_bucket',
        'matched_count_bucket',
        'missing_count_bucket',
        'extra_count_bucket',
        'uncorrelated_primary_count_bucket',
        'uncorrelated_shadow_count_bucket',
        'ambiguous_primary_count_bucket',
        'ambiguous_shadow_count_bucket',
        'ordering_mismatch',
        'latency_bucket',
      };

      const whitelistSkippedKeys = {
        'schema_version',
        'outcome_type',
        'skip_kind',
      };

      const whitelistFailureKeys = {
        'schema_version',
        'outcome_type',
        'failure_kind',
        'latency_bucket',
      };

      expect(compJson.keys.toSet(), equals(whitelistComparisonKeys));
      expect(skipJson.keys.toSet(), equals(whitelistSkippedKeys));
      expect(failJson.keys.toSet(), equals(whitelistFailureKeys));
    });
  });
}
