import 'package:flutter_test/flutter_test.dart';

import 'package:canil_gcm/core/services/pdf_generator/weight_history_pdf.dart';
import 'package:canil_gcm/features/dogs/domain/dog.dart';
import 'package:canil_gcm/features/health/domain/health_log_model.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final dog = Dog(
    id: 'dog-thor',
    name: 'Thor',
    breed: 'Pastor Belga Malinois',
    dateOfBirth: DateTime(2021, 5, 20),
    microchip: '981098102938499',
    registrationNumber: 'K9-MAL-07',
    idealWeightMin: 28.0,
    idealWeightMax: 32.0,
    weight: 30.2,
    conductorRa: '5678',
    specialties: ['Patrulhamento', 'Intervenção'],
  );

  group('WeightHistoryPdf — Emissão de PDF F70 por Estado de Autoridade', () {
    test('Estado CURRENT: emite PDF com peso atual e gráfico de evolução', () async {
      final logs = [
        HealthLogModel(
          id: 'w1',
          dogId: dog.id,
          date: DateTime(2026, 9, 10),
          type: 'other',
          subtype: 'Pesagem',
          weight: 30.5,
          healthObservations: 'Pesagem mensal regular',
          vetName: 'Dr. Santos',
        ),
        HealthLogModel(
          id: 'w2',
          dogId: dog.id,
          date: DateTime(2026, 8, 10),
          type: 'other',
          subtype: 'Pesagem',
          weight: 30.0,
          healthObservations: 'Início de ciclo',
          vetName: 'Dr. Santos',
        ),
      ];

      final bytes = await WeightHistoryPdf.generate(
        dog,
        logs,
        authority: const WeightPdfAuthority(
          state: WeightPdfAuthorityState.current,
          currentKg: 30.5,
          oldestKg: 30.0,
        ),
      );

      expect(bytes, isNotEmpty);
      expect(bytes.take(4), orderedEquals('%PDF'.codeUnits));
    });

    test('Estado NONE: emite PDF para cão sem pesagens registradas', () async {
      final bytes = await WeightHistoryPdf.generate(
        dog,
        [],
        authority: const WeightPdfAuthority.none(),
      );

      expect(bytes, isNotEmpty);
      expect(bytes.take(4), orderedEquals('%PDF'.codeUnits));
    });

    test('Estado INCONCLUSIVE: emite PDF listando pesagens sem eleger atual', () async {
      final logs = List.generate(
        6,
        (i) => HealthLogModel(
          id: 'inc-$i',
          dogId: dog.id,
          date: DateTime(2026, 6, 1).add(Duration(days: i * 15)),
          type: 'other',
          subtype: 'Pesagem',
          weight: 29.0 + (i * 0.2),
          healthObservations: 'Registro da série $i',
        ),
      );

      final bytes = await WeightHistoryPdf.generate(
        dog,
        logs,
        authority: const WeightPdfAuthority.inconclusive(),
      );

      expect(bytes, isNotEmpty);
      expect(bytes.take(4), orderedEquals('%PDF'.codeUnits));
    });

    test('Estado UNAVAILABLE: emite PDF preservando ausência de leitura', () async {
      final logs = [
        HealthLogModel(
          id: 'unav-1',
          dogId: dog.id,
          date: DateTime(2026, 5, 1),
          type: 'other',
          subtype: 'Pesagem',
          weight: 29.5,
          healthObservations: 'Pesagem anterior',
        ),
      ];

      final bytes = await WeightHistoryPdf.generate(
        dog,
        logs,
        authority: const WeightPdfAuthority.unavailable(),
      );

      expect(bytes, isNotEmpty);
      expect(bytes.take(4), orderedEquals('%PDF'.codeUnits));
    });

    test('Multipágina: emite PDF com volume elevado de pesagens (50+ registros)', () async {
      final longLogs = List.generate(
        60,
        (i) => HealthLogModel(
          id: 'log-$i',
          dogId: dog.id,
          date: DateTime(2026, 10, 1).subtract(Duration(days: i * 7)),
          type: 'other',
          subtype: 'Pesagem Semanal',
          weight: 29.0 + ((i % 5) * 0.3),
          healthObservations: 'Acompanhamento de rotina semana $i',
          vetName: 'GCM Condutor',
        ),
      );

      final bytes = await WeightHistoryPdf.generate(
        dog,
        longLogs,
        authority: const WeightPdfAuthority(
          state: WeightPdfAuthorityState.current,
          currentKg: 29.0,
          oldestKg: 30.2,
        ),
      );

      expect(bytes, isNotEmpty);
      expect(bytes.length, greaterThan(4000));
      expect(bytes.take(4), orderedEquals('%PDF'.codeUnits));
    });
  });
}
