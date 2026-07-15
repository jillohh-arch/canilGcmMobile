import 'package:canil_gcm/features/health/domain/health_v1_enums.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ParsedHealthEnum', () {
    test('faz round-trip de todos os catálogos canônicos', () {
      for (final status in ClinicalCaseStatus.values) {
        final parsed = ClinicalCaseStatusWire.parse(status.wireName);
        expect(parsed.state, ParsedHealthEnumState.known);
        expect(parsed.value, status);
        expect(parsed.raw, status.wireName);
      }
      for (final type in ClinicalEventType.values) {
        expect(ClinicalEventTypeWire.parse(type.wireName).value, type);
      }
      for (final stage in ExamStage.values) {
        expect(ExamStageWire.parse(stage.wireName).value, stage);
      }
      for (final period in MealPeriod.values) {
        final parsed = MealPeriodWire.parseCanonical(period.wireName);
        expect(parsed.value, period);
        expect(parsed.raw, period.wireName);
      }
    });

    test('ClinicalCaseOpeningType contém exatamente os quatro valores', () {
      expect(ClinicalCaseOpeningType.values.map((value) => value.wireName), [
        'incident',
        'consultation',
        'preventive',
        'administrative',
      ]);
    });

    test('distingue known, unknown e absent', () {
      final known = ClinicalEventTypeWire.parse('reopen');
      final unknown = ClinicalEventTypeWire.parse(' future_event ');
      final absentNull = ClinicalEventTypeWire.parse(null);
      final absentEmpty = ClinicalEventTypeWire.parse('');
      final absentSpaces = ClinicalEventTypeWire.parse('   ');

      expect(known.isKnown, isTrue);
      expect(unknown.isUnknown, isTrue);
      expect(unknown.raw, 'future_event');
      expect(absentNull.isAbsent, isTrue);
      expect(absentNull.raw, isNull);
      expect(absentEmpty, absentNull);
      expect(absentSpaces, absentNull);
      expect({known, unknown, absentNull}, hasLength(3));
    });

    test('parsing é case-sensitive e trim é deliberado', () {
      expect(ClinicalCaseStatusWire.parse(' open ').isKnown, isTrue);
      expect(ClinicalCaseStatusWire.parse('OPEN').isUnknown, isTrue);
    });

    test('factory unknown rejeita raw ausente', () {
      expect(
        () => ParsedHealthEnum<MealPeriod>.unknown(' '),
        throwsArgumentError,
      );
    });

    test('aliases legados comprovados preservam raw', () {
      expect(MealPeriodWire.parseLegacy('manha').value, MealPeriod.morning);
      expect(MealPeriodWire.parseLegacy('almoco').isUnknown, isTrue);
      expect(MealPeriodWire.parseLegacy('almoco').raw, 'almoco');
      expect(MealPeriodWire.parseLegacy('noite').value, MealPeriod.night);
      expect(MealPeriodWire.parseLegacy('noite').raw, 'night');
      expect(MealPeriodWire.parseLegacy('madrugada').isUnknown, isTrue);
    });
  });
}
