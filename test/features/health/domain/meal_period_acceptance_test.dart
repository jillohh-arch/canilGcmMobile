import 'package:canil_gcm/features/health/domain/health_v1_enums.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('MealPeriod wire canônico', () {
    test('parse de todos os wires', () {
      for (final p in MealPeriod.values) {
        final parsed = MealPeriodWire.parseCanonical(p.wireName);
        expect(parsed.isKnown, isTrue);
        expect(parsed.value, p);
      }
    });

    test('trim em wire canônico', () {
      expect(
        MealPeriodWire.parseCanonical('  morning  ').value,
        MealPeriod.morning,
      );
    });

    test('unknown preservado', () {
      final p = MealPeriodWire.parseCanonical('brunch');
      expect(p.isUnknown, isTrue);
      expect(p.raw, 'brunch');
    });

    test('absent para vazio/null', () {
      expect(MealPeriodWire.parseCanonical(null).isAbsent, isTrue);
      expect(MealPeriodWire.parseCanonical('').isAbsent, isTrue);
      expect(MealPeriodWire.parseCanonical('   ').isAbsent, isTrue);
    });
  });

  group('MealPeriod aliases legados D6', () {
    test('manha / almoco / noite', () {
      expect(MealPeriodWire.parseLegacy('manha').value, MealPeriod.morning);
      expect(MealPeriodWire.parseLegacy('almoco').value, MealPeriod.afternoon);
      expect(MealPeriodWire.parseLegacy('noite').value, MealPeriod.night);
    });

    test('casing: match exato (política existente) — Manha é unknown', () {
      expect(MealPeriodWire.parseLegacy('Manha').isUnknown, isTrue);
    });

    test('trim de alias', () {
      expect(
        MealPeriodWire.parseLegacy('  almoco  ').value,
        MealPeriod.afternoon,
      );
    });

    test('wire canônico ainda funciona via parseLegacy', () {
      expect(MealPeriodWire.parseLegacy('evening').value, MealPeriod.evening);
    });
  });

  group('MealAcceptance unknown-safe', () {
    test('wires canônicos', () {
      for (final a in MealAcceptance.values) {
        final p = MealAcceptanceWire.parse(a.wireName);
        expect(p.isKnown, isTrue);
        expect(p.value, a);
      }
    });

    test('unknown e absent', () {
      expect(MealAcceptanceWire.parse('quase').isUnknown, isTrue);
      expect(MealAcceptanceWire.parse(null).isAbsent, isTrue);
      expect(MealAcceptanceWire.parse('').isAbsent, isTrue);
    });

    test('não usa label PT como wire', () {
      expect(MealAcceptanceWire.parse('total').isUnknown, isTrue);
      expect(MealAcceptanceWire.parse('parcial').isUnknown, isTrue);
      expect(MealAcceptanceWire.parse('recusou').isUnknown, isTrue);
    });
  });
}
