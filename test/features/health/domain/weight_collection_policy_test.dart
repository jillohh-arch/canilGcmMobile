import 'package:flutter_test/flutter_test.dart';

import 'package:canil_gcm/features/health/domain/health_v1_models.dart';
import 'package:canil_gcm/features/health/domain/weight_assessment.dart';
import 'package:canil_gcm/features/health/domain/weight_collection_policy.dart';

/// WEIGHT-01E-C1 — regra canônica única de peso atual no Mobile.
///
/// Paridade semântica com a policy Web auditada: bloqueadores globais e
/// desempate `measuredAt` → `recordedAt` → `entityId` (UTF-16 code unit).
void main() {
  const dogId = 'dog-apolo';
  final apoloFirst = DateTime.utc(2026, 6, 17, 14);
  final apoloSecond = DateTime.utc(2026, 8, 6, 10);

  WeightAssessment valid(
    String entityId,
    double weightKg,
    DateTime measuredAt, {
    DateTime? recordedAt,
  }) => WeightAssessment.compatibility(
    entityId: entityId,
    dogId: dogId,
    weight: WeightKg(weightKg),
    measuredAt: measuredAt,
    schemaVersion: 1,
    recorder: null,
    recordedAt: recordedAt,
    compatibility: WeightCompatibilityMetadata(
      sourceShape: WeightDocumentSourceShape.deployedV1,
      persistedSchemaVersion: 1,
    ),
  );

  WeightCandidate validCandidate(
    String entityId,
    double weightKg,
    DateTime measuredAt, {
    DateTime? recordedAt,
  }) => WeightCandidate(
    entityId: entityId,
    kind: WeightCandidateKind.valid,
    assessment: valid(entityId, weightKg, measuredAt, recordedAt: recordedAt),
  );

  WeightCandidate invalidatedCandidate(
    String entityId,
    double weightKg,
    DateTime measuredAt,
  ) => WeightCandidate(
    entityId: entityId,
    kind: WeightCandidateKind.invalidated,
    assessment: valid(entityId, weightKg, measuredAt),
  );

  WeightCandidate blocking(String entityId, WeightCandidateKind kind) =>
      WeightCandidate(entityId: entityId, kind: kind);

  group('current — ordenação canônica', () {
    test('33.3 medido depois de 32.0 é o atual', () {
      final analysis = analyzeWeightCollection([
        validCandidate('a', 32.0, apoloFirst),
        validCandidate('b', 33.3, apoloSecond),
      ]);

      expect(analysis.kind, WeightCurrentKind.current);
      expect(analysis.current!.weightKg, 33.3);
    });

    test('entrada invertida produz o mesmo atual', () {
      final analysis = analyzeWeightCollection([
        validCandidate('b', 33.3, apoloSecond),
        validCandidate('a', 32.0, apoloFirst),
      ]);

      expect(analysis.current!.weightKg, 33.3);
    });

    test('mesmo measuredAt: maior recordedAt factual vence', () {
      final analysis = analyzeWeightCollection([
        validCandidate(
          'a',
          32.0,
          apoloSecond,
          recordedAt: DateTime.utc(2026, 8, 6, 11),
        ),
        validCandidate(
          'b',
          33.3,
          apoloSecond,
          recordedAt: DateTime.utc(2026, 8, 6, 12),
        ),
      ]);

      expect(analysis.current!.weightKg, 33.3);
    });

    test('mesmo measuredAt: recordedAt factual vence null', () {
      final analysis = analyzeWeightCollection([
        validCandidate('zzz', 32.0, apoloSecond),
        validCandidate(
          'aaa',
          33.3,
          apoloSecond,
          recordedAt: DateTime.utc(2026, 8, 6, 12),
        ),
      ]);

      // Vence pelo `recordedAt` factual, apesar do `entityId` menor.
      expect(analysis.current!.weightKg, 33.3);
    });

    test('empate total: entityId DESC decide', () {
      final recordedAt = DateTime.utc(2026, 8, 6, 12);
      final analysis = analyzeWeightCollection([
        validCandidate('A', 32.0, apoloSecond, recordedAt: recordedAt),
        validCandidate('B', 33.3, apoloSecond, recordedAt: recordedAt),
      ]);

      expect(analysis.current!.entityId, 'B');
    });

    test('validRecords fica em ordem decrescente de recência', () {
      final analysis = analyzeWeightCollection([
        validCandidate('a', 30.0, DateTime.utc(2026, 1, 1)),
        validCandidate('c', 33.3, apoloSecond),
        validCandidate('b', 32.0, apoloFirst),
      ]);

      expect(analysis.validRecords.map((r) => r.weightKg).toList(), [
        33.3,
        32.0,
        30.0,
      ]);
    });
  });

  group('comparator entityId — UTF-16 code unit', () {
    test('prefixo: mais longo vence em DESC', () {
      expect(compareWeightEntityIdCodeUnits('AA', 'A'), greaterThan(0));
    });

    test('case sensitivity: minúscula > maiúscula', () {
      // 'a' (0x61) > 'A' (0x41): não é comparação de locale.
      expect(compareWeightEntityIdCodeUnits('a', 'A'), greaterThan(0));
    });

    test('numérico é lexicográfico, não natural: A2 > A10', () {
      expect(compareWeightEntityIdCodeUnits('A2', 'A10'), greaterThan(0));
    });

    test('U+E000 > par surrogate de U+10000 em code unit UTF-16', () {
      // U+E000 = 0xE000. U+10000 = par surrogate 0xD800 0xDC00.
      // Em code unit UTF-16, 0xE000 > 0xD800 — o oposto da ordem de code
      // point Unicode. Este é o contrato exigido.
      const privateUse = '';
      const astral = '\u{10000}';
      expect(
        compareWeightEntityIdCodeUnits(privateUse, astral),
        greaterThan(0),
      );
      expect(privateUse.codeUnitAt(0), 0xE000);
      expect(astral.codeUnitAt(0), 0xD800);
    });

    test('idênticos empatam', () {
      expect(compareWeightEntityIdCodeUnits('same', 'same'), 0);
    });

    test('desempate adversarial escolhe U+E000 como atual', () {
      final recordedAt = DateTime.utc(2026, 8, 6, 12);
      final analysis = analyzeWeightCollection([
        validCandidate('\u{10000}', 32.0, apoloSecond, recordedAt: recordedAt),
        validCandidate('', 33.3, apoloSecond, recordedAt: recordedAt),
      ]);

      expect(analysis.current!.weightKg, 33.3);
    });
  });

  group('bloqueadores globais', () {
    test('valid + malformed → inconclusive', () {
      final analysis = analyzeWeightCollection([
        validCandidate('a', 33.3, apoloSecond),
        blocking('b', WeightCandidateKind.malformed),
      ]);

      expect(analysis.kind, WeightCurrentKind.inconclusive);
      expect(analysis.current, isNull);
      expect(analysis.blockers, contains(WeightCurrentBlocker.malformed));
    });

    test('malformed + valid → inconclusive (posição não importa)', () {
      final analysis = analyzeWeightCollection([
        blocking('b', WeightCandidateKind.malformed),
        validCandidate('a', 33.3, apoloSecond),
      ]);

      expect(analysis.kind, WeightCurrentKind.inconclusive);
      expect(analysis.current, isNull);
    });

    test('valid + unsupported → inconclusive', () {
      final analysis = analyzeWeightCollection([
        validCandidate('a', 33.3, apoloSecond),
        blocking('b', WeightCandidateKind.unsupported),
      ]);

      expect(analysis.kind, WeightCurrentKind.inconclusive);
      expect(analysis.blockers, contains(WeightCurrentBlocker.unsupported));
    });

    test('unsupported + valid → inconclusive (posição não importa)', () {
      final analysis = analyzeWeightCollection([
        blocking('b', WeightCandidateKind.unsupported),
        validCandidate('a', 33.3, apoloSecond),
      ]);

      expect(analysis.kind, WeightCurrentKind.inconclusive);
      expect(analysis.current, isNull);
    });

    test('entityId duplicado → inconclusive, sem deduplicar', () {
      final analysis = analyzeWeightCollection([
        validCandidate('dup', 32.0, apoloFirst),
        validCandidate('dup', 33.3, apoloSecond),
      ]);

      expect(analysis.kind, WeightCurrentKind.inconclusive);
      expect(
        analysis.blockers,
        contains(WeightCurrentBlocker.duplicateEntityId),
      );
      expect(analysis.validRecords, hasLength(2));
    });

    test('inconclusive nunca promove validRecords.first', () {
      final analysis = analyzeWeightCollection([
        validCandidate('a', 33.3, apoloSecond),
        blocking('b', WeightCandidateKind.malformed),
      ]);

      expect(analysis.validRecords, isNotEmpty);
      expect(analysis.current, isNull);
    });

    test('bloqueadores têm ordem estável independente da entrada', () {
      final forward = analyzeWeightCollection([
        blocking('a', WeightCandidateKind.malformed),
        blocking('b', WeightCandidateKind.unsupported),
      ]);
      final reversed = analyzeWeightCollection([
        blocking('b', WeightCandidateKind.unsupported),
        blocking('a', WeightCandidateKind.malformed),
      ]);

      expect(forward.blockers, reversed.blockers);
      expect(forward.blockers, [
        WeightCurrentBlocker.malformed,
        WeightCurrentBlocker.unsupported,
      ]);
    });
  });

  group('invalidated', () {
    test('invalidated mais recente é ignorado; valid anterior é o atual', () {
      final analysis = analyzeWeightCollection([
        validCandidate('a', 33.3, apoloSecond),
        invalidatedCandidate('b', 40.0, DateTime.utc(2026, 8, 10)),
      ]);

      expect(analysis.kind, WeightCurrentKind.current);
      expect(analysis.current!.weightKg, 33.3);
      expect(analysis.invalidatedRecords, hasLength(1));
    });

    test('somente invalidated → none', () {
      final analysis = analyzeWeightCollection([
        invalidatedCandidate('a', 40.0, apoloSecond),
      ]);

      expect(analysis.kind, WeightCurrentKind.none);
      expect(analysis.current, isNull);
    });

    test('invalidated não é bloqueador', () {
      final analysis = analyzeWeightCollection([
        invalidatedCandidate('a', 40.0, apoloSecond),
        validCandidate('b', 33.3, apoloFirst),
      ]);

      expect(analysis.blockers, isEmpty);
      expect(analysis.kind, WeightCurrentKind.current);
    });
  });

  group('vazio', () {
    test('coleção vazia → none', () {
      final analysis = analyzeWeightCollection([]);

      expect(analysis.kind, WeightCurrentKind.none);
      expect(analysis.current, isNull);
      expect(analysis.validRecords, isEmpty);
      expect(analysis.blockers, isEmpty);
    });
  });

  group('independência de ordem de entrada', () {
    test('três permutações produzem o mesmo resultado', () {
      final a = validCandidate('a', 30.0, DateTime.utc(2026, 1, 1));
      final b = validCandidate('b', 32.0, apoloFirst);
      final c = validCandidate('c', 33.3, apoloSecond);
      final invalid = invalidatedCandidate('d', 99.0, DateTime.utc(2026, 9, 1));

      final permutations = [
        [a, b, c, invalid],
        [invalid, c, b, a],
        [c, invalid, a, b],
      ];

      for (final permutation in permutations) {
        final analysis = analyzeWeightCollection(permutation);
        expect(analysis.kind, WeightCurrentKind.current);
        expect(analysis.current!.entityId, 'c');
        expect(analysis.validRecords.map((r) => r.entityId).toList(), [
          'c',
          'b',
          'a',
        ]);
        expect(analysis.blockers, isEmpty);
      }
    });

    test('não muta a lista de entrada', () {
      final input = [
        validCandidate('a', 30.0, DateTime.utc(2026, 1, 1)),
        validCandidate('c', 33.3, apoloSecond),
        validCandidate('b', 32.0, apoloFirst),
      ];
      final originalOrder = input.map((c) => c.entityId).toList();

      analyzeWeightCollection(input);

      expect(input.map((c) => c.entityId).toList(), originalOrder);
    });
  });
}
