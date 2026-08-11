import 'package:canil_gcm/features/health/data/coexistence/summary/health_summary_medication_reader.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('evento canônico ativo alimenta card de medicação factual', () async {
    final facts = HealthSummaryMedicationReader.mapHealthEventDocsForTest([
      {
        'type': 'medication',
        'subtype': 'Prednisolona',
        'date': DateTime.utc(2026, 8, 11, 14, 32),
        'healthObservations':
            '[Dosagem: 1 comprimido | Frequência: 1x ao dia | Duração: 4 dias]',
      },
    ]);
    final reader = HealthSummaryMedicationReader(
      loadFacts: (_) async => facts,
      clock: () => DateTime.utc(2026, 8, 11, 18),
    );

    final section = await reader.read('dog-1');

    expect(section.isAvailable, isTrue);
    expect(section.value!.activeProtocolCount, 1);
    expect(section.value!.primarySummary, 'Prednisolona');
  });

  group('janela temporal factual do protocolo', () {
    final startedAt = DateTime.utc(2026, 8, 11, 14, 32);
    // Duração de 4 dias a partir de startedAt: expira em 2026-08-15 14:32.
    final expiration = startedAt.add(const Duration(days: 4));

    HealthSummaryMedicationFact fact() => HealthSummaryMedicationFact(
      medicationName: 'Prednisolona',
      startedAt: startedAt,
      durationDays: 4,
      isContinuous: false,
    );

    Future<int> activeCountAt(DateTime now) async {
      final reader = HealthSummaryMedicationReader(
        loadFacts: (_) async => [fact()],
        clock: () => now,
      );
      final section = await reader.read('dog-1');
      expect(section.isAvailable, isTrue);
      return section.value!.activeProtocolCount;
    }

    test('T1 ACTIVE: início <= now < expiração conta como ativa', () async {
      expect(await activeCountAt(startedAt), 1);
      expect(await activeCountAt(startedAt.add(const Duration(days: 2))), 1);
      expect(
        await activeCountAt(expiration.subtract(const Duration(seconds: 1))),
        1,
      );
    });

    test('T2 FUTURE: início no futuro não conta como ativa', () async {
      expect(
        await activeCountAt(startedAt.subtract(const Duration(seconds: 1))),
        0,
      );
      expect(
        await activeCountAt(startedAt.subtract(const Duration(days: 3))),
        0,
      );
    });

    test('T3 EXPIRED: now após a expiração não conta como ativa', () async {
      expect(
        await activeCountAt(expiration.add(const Duration(seconds: 1))),
        0,
      );
      expect(await activeCountAt(expiration.add(const Duration(days: 30))), 0);
    });

    test('T4 EXACT EXPIRATION: instante exato encerra o protocolo', () async {
      // Janela semiaberta [startedAt, startedAt + durationDays): no instante
      // exato da expiração o protocolo já não está ativo. Comportamento
      // implementado por isActiveAt, congelado aqui como contrato factual.
      expect(await activeCountAt(expiration), 0);
    });

    test(
      'protocolo contínuo permanece ativo além de qualquer duração',
      () async {
        final reader = HealthSummaryMedicationReader(
          loadFacts: (_) async => [
            HealthSummaryMedicationFact(
              medicationName: 'Prednisolona',
              startedAt: startedAt,
              durationDays: null,
              isContinuous: true,
            ),
          ],
          clock: () => expiration.add(const Duration(days: 365)),
        );
        final section = await reader.read('dog-1');
        expect(section.value!.activeProtocolCount, 1);
      },
    );
  });
}
