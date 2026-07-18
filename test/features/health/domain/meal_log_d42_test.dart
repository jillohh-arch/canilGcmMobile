import 'package:canil_gcm/features/health/domain/health_v1_enums.dart';
import 'package:canil_gcm/features/health/domain/health_v1_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final actor = RecordedBy(
    uid: 'u1',
    name: 'Condutor',
    internalRole: 'condutor',
  );
  final fedAt = DateTime.utc(2026, 7, 14, 8);

  MealLog meal({
    required num offered,
    num? consumed,
    required String acceptance,
    String? planId,
    String? plannedMealId,
    String? mealOccurrenceId,
  }) {
    return MealLog(
      id: 'm1',
      dogId: 'dog-1',
      period: MealPeriodWire.parseCanonical('morning'),
      offeredGrams: offered,
      acceptance: MealAcceptanceWire.parse(acceptance),
      fedAt: fedAt,
      recordedBy: actor,
      schemaVersion: 1,
      revision: 1,
      consumedGrams: consumed,
      planId: planId,
      plannedMealId: plannedMealId,
      mealOccurrenceId: mealOccurrenceId,
    );
  }

  group('D42 offered_grams', () {
    test('offered > 0 aceito', () {
      expect(meal(offered: 1, acceptance: 'unknown').offeredGrams, 1);
    });

    test('offered <= 0 rejeitado', () {
      for (final bad in [
        0,
        -1,
        double.nan,
        double.infinity,
        double.negativeInfinity,
      ]) {
        expect(
          () => meal(offered: bad, acceptance: 'unknown'),
          throwsA(isA<HealthDomainException>()),
        );
      }
    });
  });

  group('D42 consumed bounds', () {
    test('consumed no intervalo [0, offered]', () {
      expect(
        meal(offered: 100, consumed: 0, acceptance: 'refused').consumedGrams,
        0,
      );
      expect(
        meal(offered: 100, consumed: 100, acceptance: 'full').consumedGrams,
        100,
      );
      expect(
        meal(offered: 100, consumed: 50, acceptance: 'partial').consumedGrams,
        50,
      );
    });

    test('consumed < 0 ou > offered rejeitado', () {
      expect(
        () => meal(offered: 100, consumed: -1, acceptance: 'unknown'),
        throwsA(isA<HealthDomainException>()),
      );
      expect(
        () => meal(offered: 100, consumed: 101, acceptance: 'unknown'),
        throwsA(isA<HealthDomainException>()),
      );
    });
  });

  group('D42 acceptance × consumed matrix', () {
    test('refused exige consumed == 0', () {
      expect(
        () => meal(offered: 100, consumed: null, acceptance: 'refused'),
        throwsA(isA<HealthDomainException>()),
      );
      expect(
        () => meal(offered: 100, consumed: 1, acceptance: 'refused'),
        throwsA(isA<HealthDomainException>()),
      );
      expect(
        meal(offered: 100, consumed: 0, acceptance: 'refused').acceptance.value,
        MealAcceptance.refused,
      );
    });

    test('full: null ou == offered', () {
      expect(
        meal(offered: 100, consumed: null, acceptance: 'full').consumedGrams,
        isNull,
      );
      expect(
        meal(offered: 100, consumed: 100, acceptance: 'full').consumedGrams,
        100,
      );
      expect(
        () => meal(offered: 100, consumed: 50, acceptance: 'full'),
        throwsA(isA<HealthDomainException>()),
      );
      expect(
        () => meal(offered: 100, consumed: 0, acceptance: 'full'),
        throwsA(isA<HealthDomainException>()),
      );
    });

    test('partial: null ou 0 < consumed < offered', () {
      expect(
        meal(offered: 100, consumed: null, acceptance: 'partial').consumedGrams,
        isNull,
      );
      expect(
        meal(offered: 100, consumed: 1, acceptance: 'partial').consumedGrams,
        1,
      );
      expect(
        meal(offered: 100, consumed: 99, acceptance: 'partial').consumedGrams,
        99,
      );
      expect(
        () => meal(offered: 100, consumed: 0, acceptance: 'partial'),
        throwsA(isA<HealthDomainException>()),
      );
      expect(
        () => meal(offered: 100, consumed: 100, acceptance: 'partial'),
        throwsA(isA<HealthDomainException>()),
      );
    });

    test('unknown: null preferido; valor só com bounds', () {
      expect(
        meal(offered: 100, consumed: null, acceptance: 'unknown').consumedGrams,
        isNull,
      );
      expect(
        meal(offered: 100, consumed: 40, acceptance: 'unknown').consumedGrams,
        40,
      );
      // não infere outro acceptance
      expect(
        meal(
          offered: 100,
          consumed: 100,
          acceptance: 'unknown',
        ).acceptance.value,
        MealAcceptance.unknown,
      );
    });

    test('acceptance unknown raw preservado sem forçar known', () {
      final m = MealLog(
        id: 'm1',
        dogId: 'dog-1',
        period: MealPeriodWire.parseCanonical('morning'),
        offeredGrams: 50,
        acceptance: ParsedHealthEnum.unknown('weird'),
        fedAt: fedAt,
        recordedBy: actor,
        schemaVersion: 1,
        revision: 1,
        consumedGrams: 10,
      );
      expect(m.acceptance.isUnknown, isTrue);
      expect(m.acceptance.raw, 'weird');
    });
  });

  group('D12 planned linkage', () {
    test('avulso sem vínculos', () {
      final m = meal(offered: 100, acceptance: 'unknown');
      expect(m.isAdHoc, isTrue);
      expect(m.isPlanned, isFalse);
    });

    test('planejado completo', () {
      final m = meal(
        offered: 100,
        acceptance: 'full',
        planId: 'p1',
        plannedMealId: 'slot-am',
        mealOccurrenceId: 'occ-1',
      );
      expect(m.isPlanned, isTrue);
    });

    test('vínculo parcial rejeitado', () {
      expect(
        () => meal(offered: 100, acceptance: 'unknown', planId: 'p1'),
        throwsA(isA<HealthDomainException>()),
      );
      expect(
        () => meal(
          offered: 100,
          acceptance: 'unknown',
          planId: 'p1',
          plannedMealId: 's1',
        ),
        throwsA(isA<HealthDomainException>()),
      );
    });
  });
}
