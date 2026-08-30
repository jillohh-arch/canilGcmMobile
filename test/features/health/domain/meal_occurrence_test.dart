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
    test('v1 reproduz vetor fixo do backend byte a byte', () {
      final id = MealOccurrenceId.v1(
        MealOccurrenceKey(
          dogId: 'dog-1',
          planId: 'plan-1',
          plannedMealId: 'slot-am',
          localServiceDate: LocalServiceDate.fromIso('2026-07-18'),
        ),
      );

      expect(
        id.value,
        'mo1_b8227a81de279403afa97d01e64fbbba7028674e139849fa03f857a633b46e40',
      );
      expect(id.value, matches(RegExp(r'^mo1_[0-9a-f]{64}$')));
    });

    test('v1 preserva vetor UTF-8 do backend', () {
      final id = MealOccurrenceId.v1(
        MealOccurrenceKey(
          dogId: 'cão-α',
          planId: 'plano-2',
          plannedMealId: 'slot-noite',
          localServiceDate: LocalServiceDate.fromIso('2026-12-31'),
        ),
      );

      expect(
        id.value,
        'mo1_c46a51b23c505f1ba4d5790866782acf9772f1c9798617a52ffb7450a87f32a5',
      );
    });

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
