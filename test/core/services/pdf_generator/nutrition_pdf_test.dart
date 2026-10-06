import 'package:flutter_test/flutter_test.dart';

import 'package:canil_gcm/core/services/pdf_generator/nutrition_pdf.dart';
import 'package:canil_gcm/features/dogs/domain/dog.dart';
import 'package:canil_gcm/features/nutrition/domain/feeding.dart';
import 'package:canil_gcm/features/nutrition/domain/nutrition_prescription.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final dog = Dog(
    id: 'dog-max',
    name: 'Max',
    breed: 'Rottweiler',
    dateOfBirth: DateTime(2022, 3, 15),
    microchip: '981098102938111',
    registrationNumber: 'K9-ROT-03',
    weight: 42.0,
    conductorRa: '7890',
    specialties: ['Guarda', 'Proteção Perimetral'],
  );

  final samplePrescription = NutritionPrescription(
    id: 'rx-1',
    amountGramsPerDay: 800,
    foodType: 'Ração Super Premium Alta Performance K9',
    mealsPerDay: 2,
    vetName: 'Dra. Vanessa Lima',
    vetCrmv: 'SP-45678',
    vigentFrom: DateTime(2026, 1, 1),
    hydrationNotes: 'Fornecer água fresca ad libitum. Suplementação eletrolítica pós-treino.',
    notes: 'Fracionamento em 2 refeições de 400g (manhã e noite).',
  );

  group('NutritionPdf — Emissão de Relatório Nutricional F70', () {
    test('Caso Rico com Prescrição e Alta Conformidade (95%)', () async {
      final feedings = [
        Feeding(
          id: 'f1',
          period: 'manha',
          amountGrams: 400,
          prescriptionAtTime: 400,
          divergencePercent: 0.0,
          fedAt: DateTime(2026, 10, 5, 7, 30),
          fedBy: 'GCM 1CL Silva',
        ),
        Feeding(
          id: 'f2',
          period: 'noite',
          amountGrams: 410,
          prescriptionAtTime: 400,
          divergencePercent: 2.5,
          fedAt: DateTime(2026, 10, 5, 19, 0),
          fedBy: 'GCM 1CL Silva',
        ),
        Feeding(
          id: 'f3',
          period: 'manha',
          amountGrams: 395,
          prescriptionAtTime: 400,
          divergencePercent: -1.2,
          fedAt: DateTime(2026, 10, 6, 7, 30),
          fedBy: 'GCM 1CL Santos',
        ),
      ];

      final bytes = await NutritionPdf.generate(
        dog: dog,
        feedings: feedings,
        prescription: samplePrescription,
        conformityPercent: 95.0,
        conformCount: 38,
        divergentCount: 2,
      );

      expect(bytes, isNotEmpty);
      expect(bytes.take(4), orderedEquals('%PDF'.codeUnits));
    });

    test('Caso com Divergências Nutricionais Relevantes', () async {
      final feedings = [
        Feeding(
          id: 'f1',
          period: 'manha',
          amountGrams: 500,
          prescriptionAtTime: 400,
          divergencePercent: 25.0, // Divergente
          divergenceReason: 'Aumento de porção após patrulhamento intenso',
          fedAt: DateTime(2026, 10, 5, 8, 0),
          fedBy: 'GCM Silva',
        ),
        Feeding(
          id: 'f2',
          period: 'noite',
          amountGrams: 300,
          prescriptionAtTime: 400,
          divergencePercent: -25.0, // Divergente
          divergenceReason: 'Cão ingeriu apenas parte da porção',
          fedAt: DateTime(2026, 10, 5, 19, 30),
          fedBy: 'GCM Silva',
        ),
      ];

      final bytes = await NutritionPdf.generate(
        dog: dog,
        feedings: feedings,
        prescription: samplePrescription,
        conformityPercent: 65.0,
        conformCount: 13,
        divergentCount: 7,
      );

      expect(bytes, isNotEmpty);
      expect(bytes.take(4), orderedEquals('%PDF'.codeUnits));
    });

    test('Caso sem Prescrição Vigente (prescription == null)', () async {
      final bytes = await NutritionPdf.generate(
        dog: dog,
        feedings: [],
        prescription: null,
        conformityPercent: 0.0,
        conformCount: 0,
        divergentCount: 0,
      );

      expect(bytes, isNotEmpty);
      expect(bytes.take(4), orderedEquals('%PDF'.codeUnits));
    });

    test('Multipágina: Histórico Extenso de Refeições (50+ registros)', () async {
      final longFeedings = List.generate(
        55,
        (i) => Feeding(
          id: 'feed-$i',
          period: i.isEven ? 'manha' : 'noite',
          amountGrams: 400 + (i % 3 == 0 ? 30 : 0),
          prescriptionAtTime: 400,
          divergencePercent: (i % 3 == 0) ? 7.5 : 0.0,
          fedAt: DateTime(2026, 10, 6, 7, 0).subtract(Duration(hours: i * 12)),
          fedBy: 'Condutor da Escala',
        ),
      );

      final bytes = await NutritionPdf.generate(
        dog: dog,
        feedings: longFeedings,
        prescription: samplePrescription,
        conformityPercent: 92.0,
        conformCount: 50,
        divergentCount: 5,
      );

      expect(bytes, isNotEmpty);
      expect(bytes.length, greaterThan(3000));
      expect(bytes.take(4), orderedEquals('%PDF'.codeUnits));
    });
  });
}
