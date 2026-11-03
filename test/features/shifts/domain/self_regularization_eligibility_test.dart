import 'package:flutter_test/flutter_test.dart';
import 'package:canil_gcm/features/shifts/domain/self_regularization_eligibility.dart';

void main() {
  group('evaluateSelfRegularizationEligibility', () {
    test('officialShiftEnd null retorna indeterminate', () {
      final result = evaluateSelfRegularizationEligibility(
        now: DateTime(2026, 11, 3, 18, 0),
        officialShiftEnd: null,
      );

      expect(result, SelfRegularizationEligibilityResult.indeterminate);
    });

    test('antes do fim do turno retorna notEligible', () {
      final shiftEnd = DateTime(2026, 11, 3, 18, 0);
      final now = DateTime(2026, 11, 3, 17, 59);

      final result = evaluateSelfRegularizationEligibility(
        now: now,
        officialShiftEnd: shiftEnd,
      );

      expect(result, SelfRegularizationEligibilityResult.notEligible);
    });

    test('no instante exato do fim do turno retorna notEligible', () {
      final shiftEnd = DateTime(2026, 11, 3, 18, 0);

      final result = evaluateSelfRegularizationEligibility(
        now: shiftEnd,
        officialShiftEnd: shiftEnd,
      );

      expect(result, SelfRegularizationEligibilityResult.notEligible);
    });

    test('fim + 59 minutos retorna notEligible', () {
      final shiftEnd = DateTime(2026, 11, 3, 18, 0);
      final now = shiftEnd.add(const Duration(minutes: 59));

      final result = evaluateSelfRegularizationEligibility(
        now: now,
        officialShiftEnd: shiftEnd,
      );

      expect(result, SelfRegularizationEligibilityResult.notEligible);
    });

    test('fim + 60 minutos retorna temporallyEligible (limite exato)', () {
      final shiftEnd = DateTime(2026, 11, 3, 18, 0);
      final now = shiftEnd.add(const Duration(minutes: 60));

      final result = evaluateSelfRegularizationEligibility(
        now: now,
        officialShiftEnd: shiftEnd,
      );

      expect(result, SelfRegularizationEligibilityResult.temporallyEligible);
    });

    test('fim + 61 minutos retorna temporallyEligible', () {
      final shiftEnd = DateTime(2026, 11, 3, 18, 0);
      final now = shiftEnd.add(const Duration(minutes: 61));

      final result = evaluateSelfRegularizationEligibility(
        now: now,
        officialShiftEnd: shiftEnd,
      );

      expect(result, SelfRegularizationEligibilityResult.temporallyEligible);
    });

    test('muito depois do fim retorna temporallyEligible', () {
      final shiftEnd = DateTime(2026, 11, 3, 6, 0);
      final now = DateTime(2026, 11, 3, 23, 59);

      final result = evaluateSelfRegularizationEligibility(
        now: now,
        officialShiftEnd: shiftEnd,
      );

      expect(result, SelfRegularizationEligibilityResult.temporallyEligible);
    });

    test('funciona com datas em fusos diferentes (UTC vs local)', () {
      final shiftEndUtc = DateTime.utc(2026, 11, 3, 21, 0); // 21:00 UTC
      final nowUtc = DateTime.utc(2026, 11, 3, 22, 0); // 22:00 UTC = +60min

      final result = evaluateSelfRegularizationEligibility(
        now: nowUtc,
        officialShiftEnd: shiftEndUtc,
      );

      expect(result, SelfRegularizationEligibilityResult.temporallyEligible);
    });

    test('ator não titular é elegível temporalmente (avaliação puramente temporal)', () {
      // A elegibilidade temporal NÃO exige titularidade.
      // Esta função avalia APENAS o tempo, independente de quem chama.
      final shiftEnd = DateTime(2026, 11, 3, 18, 0);
      final now = shiftEnd.add(const Duration(hours: 2));

      final result = evaluateSelfRegularizationEligibility(
        now: now,
        officialShiftEnd: shiftEnd,
      );

      expect(result, SelfRegularizationEligibilityResult.temporallyEligible);
    });

    test('tolerância exata: 59min59seg ainda é notEligible', () {
      final shiftEnd = DateTime(2026, 11, 3, 18, 0);
      final now = shiftEnd.add(const Duration(minutes: 59, seconds: 59));

      final result = evaluateSelfRegularizationEligibility(
        now: now,
        officialShiftEnd: shiftEnd,
      );

      expect(result, SelfRegularizationEligibilityResult.notEligible);
    });
  });
}