import 'package:canil_gcm/features/health/domain/health_v1_models.dart';
import 'package:canil_gcm/features/health/domain/meal_occurrence.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('LocalServiceDate', () {
    test('wall clock usa timezone do plano e não timezone do device', () {
      final instant = LocalServiceDate.instantFromLocal(
        year: 2026,
        month: 7,
        day: 19,
        hour: 8,
        minute: 30,
        timezone: 'America/Sao_Paulo',
      );
      expect(instant, DateTime.utc(2026, 7, 19, 11, 30));
    });

    test('fronteira DST rejeita horário local inexistente', () {
      expect(
        () => LocalServiceDate.instantFromLocal(
          year: 2026,
          month: 3,
          day: 8,
          hour: 2,
          minute: 30,
          timezone: 'America/New_York',
        ),
        throwsA(isA<HealthDomainException>()),
      );
    });

    test('fromIso válido sem horário embutido', () {
      final d = LocalServiceDate.fromIso('2026-07-18');
      expect(d.year, 2026);
      expect(d.month, 7);
      expect(d.day, 18);
      expect(d.isoDate, '2026-07-18');
    });

    test('fromIso inválido', () {
      expect(
        () => LocalServiceDate.fromIso('18/07/2026'),
        throwsA(isA<HealthDomainException>()),
      );
      expect(
        () => LocalServiceDate.fromIso('2026-02-30'),
        throwsA(isA<HealthDomainException>()),
      );
    });

    test('fromInstant exige timezone explícito (não device)', () {
      final instant = DateTime.utc(2026, 7, 18, 2, 30);
      expect(
        () => LocalServiceDate.fromInstant(instant, timezone: '  '),
        throwsA(isA<HealthDomainException>()),
      );
      // 02:30Z = 23:30 no dia anterior em America/Sao_Paulo
      final local = LocalServiceDate.fromInstant(
        instant,
        timezone: 'America/Sao_Paulo',
      );
      expect(local.isoDate, '2026-07-17');
      final utc = LocalServiceDate.fromInstant(instant, timezone: 'Etc/UTC');
      expect(utc.isoDate, '2026-07-18');
    });
  });

  group('MealOccurrenceKey (identidade semântica)', () {
    LocalServiceDate d(String iso) => LocalServiceDate.fromIso(iso);

    test('mesmos componentes → igualdade e hashCode', () {
      final a = MealOccurrenceKey(
        dogId: 'dog-1',
        planId: 'plan-1',
        plannedMealId: 'slot-am',
        localServiceDate: d('2026-07-18'),
      );
      final b = MealOccurrenceKey(
        dogId: 'dog-1',
        planId: 'plan-1',
        plannedMealId: 'slot-am',
        localServiceDate: d('2026-07-18'),
      );
      expect(a, b);
      expect(a.hashCode, b.hashCode);
      expect(a.diagnosticLabel, contains('dog-1'));
    });

    test('dog diferente → diferente', () {
      final base = MealOccurrenceKey(
        dogId: 'dog-1',
        planId: 'p',
        plannedMealId: 's',
        localServiceDate: d('2026-07-18'),
      );
      expect(
        base,
        isNot(
          MealOccurrenceKey(
            dogId: 'dog-2',
            planId: 'p',
            plannedMealId: 's',
            localServiceDate: d('2026-07-18'),
          ),
        ),
      );
    });

    test('plan diferente → diferente', () {
      final base = MealOccurrenceKey(
        dogId: 'dog-1',
        planId: 'p1',
        plannedMealId: 's',
        localServiceDate: d('2026-07-18'),
      );
      expect(
        base,
        isNot(
          MealOccurrenceKey(
            dogId: 'dog-1',
            planId: 'p2',
            plannedMealId: 's',
            localServiceDate: d('2026-07-18'),
          ),
        ),
      );
    });

    test('slot diferente → diferente', () {
      final base = MealOccurrenceKey(
        dogId: 'dog-1',
        planId: 'p',
        plannedMealId: 'am',
        localServiceDate: d('2026-07-18'),
      );
      expect(
        base,
        isNot(
          MealOccurrenceKey(
            dogId: 'dog-1',
            planId: 'p',
            plannedMealId: 'pm',
            localServiceDate: d('2026-07-18'),
          ),
        ),
      );
    });

    test('localServiceDate diferente → diferente', () {
      final base = MealOccurrenceKey(
        dogId: 'dog-1',
        planId: 'p',
        plannedMealId: 's',
        localServiceDate: d('2026-07-18'),
      );
      expect(
        base,
        isNot(
          MealOccurrenceKey(
            dogId: 'dog-1',
            planId: 'p',
            plannedMealId: 's',
            localServiceDate: d('2026-07-19'),
          ),
        ),
      );
    });

    test('campos vazios rejeitados', () {
      expect(
        () => MealOccurrenceKey(
          dogId: ' ',
          planId: 'p',
          plannedMealId: 's',
          localServiceDate: d('2026-07-18'),
        ),
        throwsA(isA<HealthDomainException>()),
      );
    });
  });

  group('MealOccurrenceId (opaco físico)', () {
    test('valor vazio rejeitado', () {
      expect(() => MealOccurrenceId(''), throwsA(isA<HealthDomainException>()));
      expect(
        () => MealOccurrenceId('   '),
        throwsA(isA<HealthDomainException>()),
      );
    });

    test('opacidade preservada sem reinterpretar', () {
      final id = MealOccurrenceId('opaque-server-token-xyz');
      expect(id.value, 'opaque-server-token-xyz');
      expect(id, MealOccurrenceId('opaque-server-token-xyz'));
      // Não confundir com MealOccurrenceKey
      expect(id, isNot(isA<MealOccurrenceKey>()));
    });
  });
}
