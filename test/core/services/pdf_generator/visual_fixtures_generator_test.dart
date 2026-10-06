import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';

import 'package:canil_gcm/core/services/pdf_generator/nutrition_pdf.dart';
import 'package:canil_gcm/core/services/pdf_generator/vaccination_pdf.dart';
import 'package:canil_gcm/core/services/pdf_generator/weight_history_pdf.dart';
import 'package:canil_gcm/features/dogs/domain/dog.dart';
import 'package:canil_gcm/features/health/domain/health_log_model.dart';
import 'package:canil_gcm/features/nutrition/domain/feeding.dart';
import 'package:canil_gcm/features/nutrition/domain/nutrition_prescription.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final thor = Dog(
    id: 'k9-thor-01',
    name: 'Thor',
    breed: 'Pastor Belga Malinois',
    dateOfBirth: DateTime(2021, 3, 14),
    microchip: '900215004712345',
    registrationNumber: 'K9-2023-017',
    cor: 'Fulvo com máscara preta',
    weight: 33.5,
    conductorRa: 'Silva (GCM)',
    specialties: ['Patrulhamento', 'Busca e Resgate', 'Detecção', 'Apoio Operacional'],
    idealWeightMin: 32.0,
    idealWeightMax: 35.0,
  );

  final outputDir = Directory('build/visual_fixtures');
  Uint8List? sampleDogPhoto;

  setUpAll(() async {
    if (!await outputDir.exists()) {
      await outputDir.create(recursive: true);
    }
    final photoFile = File('assets/images/k9_ops_loading_dog_static_v1.png');
    if (photoFile.existsSync()) {
      sampleDogPhoto = photoFile.readAsBytesSync();
    }
  });

  group('F70 Visual Fixtures Generation (Conformidade com Mockup)', () {
    test('1. Gera PDF representativo da Carteira de Vacinação (Thor)', () async {
      final logs = [
        HealthLogModel(
          id: 'v1',
          dogId: thor.id,
          date: DateTime(2023, 3, 15),
          type: 'vaccination',
          subtype: 'V8 (Polivalente)',
          healthObservations: 'Dose 1/1. Animal saudável.',
          nextDueDate: DateTime(2024, 3, 15),
          vetName: 'MV. Ana Costa',
          professionalCrmv: 'CRMV-SP 12345',
        ),
        HealthLogModel(
          id: 'v2',
          dogId: thor.id,
          date: DateTime(2024, 3, 20),
          type: 'vaccination',
          subtype: 'V8 (Polivalente)',
          healthObservations: 'Dose 1/1. Reforço anual.',
          nextDueDate: DateTime(2025, 3, 20),
          vetName: 'MV. Ana Costa',
          professionalCrmv: 'CRMV-SP 12345',
        ),
        HealthLogModel(
          id: 'v3',
          dogId: thor.id,
          date: DateTime(2023, 3, 15),
          type: 'vaccination',
          subtype: 'Raiva',
          healthObservations: 'Dose 1/1. Campanha antirrábica.',
          nextDueDate: DateTime(2024, 3, 15),
          vetName: 'MV. Ana Costa',
          professionalCrmv: 'CRMV-SP 12345',
        ),
        HealthLogModel(
          id: 'v4',
          dogId: thor.id,
          date: DateTime(2024, 3, 20),
          type: 'vaccination',
          subtype: 'Raiva',
          healthObservations: 'Dose 1/1. Reforço anual.',
          nextDueDate: DateTime(2025, 3, 20),
          vetName: 'MV. Ana Costa',
          professionalCrmv: 'CRMV-SP 12345',
        ),
        HealthLogModel(
          id: 'v5',
          dogId: thor.id,
          date: DateTime(2024, 4, 10),
          type: 'vaccination',
          subtype: 'Giárdia',
          healthObservations: 'Dose 1/2.',
          nextDueDate: DateTime(2024, 5, 1),
          vetName: 'MV. Pedro Lima',
          professionalCrmv: 'CRMV-SP 67890',
        ),
        HealthLogModel(
          id: 'v6',
          dogId: thor.id,
          date: DateTime(2024, 5, 1),
          type: 'vaccination',
          subtype: 'Giárdia',
          healthObservations: 'Dose 2/2. Esquema completo.',
          nextDueDate: DateTime(2025, 5, 1),
          vetName: 'MV. Pedro Lima',
          professionalCrmv: 'CRMV-SP 67890',
        ),
      ];

      final bytes = await VaccinationPdf.generate(
        thor,
        logs,
        dogPhotoBytes: sampleDogPhoto,
      );
      final file = File('${outputDir.path}/carteira_vacinacao_thor.pdf');
      await file.writeAsBytes(bytes);

      expect(file.existsSync(), isTrue);
      expect(bytes.length, greaterThan(2000));
      expect(bytes.take(4), orderedEquals('%PDF'.codeUnits));
    });

    test('2. Gera PDF representativo do Histórico de Peso (Thor)', () async {
      final weights = [32.0, 32.5, 33.1, 33.0, 33.4, 33.2, 33.5];
      final dates = [
        DateTime(2024, 1, 10),
        DateTime(2024, 2, 10),
        DateTime(2024, 3, 10),
        DateTime(2024, 4, 10),
        DateTime(2024, 5, 10),
        DateTime(2024, 6, 10),
        DateTime(2024, 7, 10),
      ];

      final logs = List.generate(
        weights.length,
        (i) => HealthLogModel(
          id: 'w-$i',
          dogId: thor.id,
          date: dates[i],
          type: 'other',
          subtype: 'Pesagem',
          weight: weights[i],
          healthObservations: 'Acompanhamento mensal de rotina',
          vetName: i % 2 == 0 ? 'MV. Ana Costa' : 'MV. Pedro Lima',
        ),
      );

      final bytes = await WeightHistoryPdf.generate(
        thor,
        logs,
        authority: const WeightPdfAuthority(
          state: WeightPdfAuthorityState.current,
          currentKg: 33.5,
          oldestKg: 32.0,
        ),
        dogPhotoBytes: sampleDogPhoto,
      );
      final file = File('${outputDir.path}/historico_peso_thor.pdf');
      await file.writeAsBytes(bytes);

      expect(file.existsSync(), isTrue);
      expect(bytes.length, greaterThan(2000));
      expect(bytes.take(4), orderedEquals('%PDF'.codeUnits));
    });

    test('3. Gera PDF representativo do Relatório Nutricional (Thor)', () async {
      final prescription = NutritionPrescription(
        id: 'rx-thor-01',
        amountGramsPerDay: 450,
        foodType: 'Ração super premium para cães atletas',
        mealsPerDay: 2,
        vetName: 'MV. Ana Costa',
        vetCrmv: 'SP 12345',
        vigentFrom: DateTime(2024, 1, 1),
        hydrationNotes: 'Água fresca disponível livre acesso',
        notes: 'Suplementação: condroitina + glucosamina. Manutenção do peso ideal.',
      );

      final feedings = List.generate(
        14,
        (i) => Feeding(
          id: 'feed-$i',
          period: i.isEven ? 'manha' : 'noite',
          amountGrams: 225,
          prescriptionAtTime: 225,
          divergencePercent: (i == 3) ? 12.0 : 0.0,
          divergenceReason: (i == 3) ? 'Acréscimo de porção pós-patrulha' : null,
          fedAt: DateTime(2024, 7, 10, i.isEven ? 7 : 18).subtract(Duration(days: i ~/ 2)),
          fedBy: 'GCM Silva',
        ),
      );

      final bytes = await NutritionPdf.generate(
        dog: thor,
        feedings: feedings,
        prescription: prescription,
        conformityPercent: 93.0,
        conformCount: 13,
        divergentCount: 1,
        dogPhotoBytes: sampleDogPhoto,
      );
      final file = File('${outputDir.path}/relatorio_nutricional_thor.pdf');
      await file.writeAsBytes(bytes);

      expect(file.existsSync(), isTrue);
      expect(bytes.length, greaterThan(2000));
      expect(bytes.take(4), orderedEquals('%PDF'.codeUnits));
    });

    test('4. Gera PDF multipágina de estresse (Carteira com 55+ vacinas)', () async {
      final longList = List.generate(
        55,
        (i) => HealthLogModel(
          id: 'v-multi-$i',
          dogId: thor.id,
          date: DateTime(2024, 7, 1).subtract(Duration(days: i * 20)),
          type: 'vaccination',
          subtype: 'Imunobiológico Série $i',
          healthObservations: 'Lote: BATCH-F70-$i',
          nextDueDate: DateTime(2025, 7, 1).subtract(Duration(days: i * 20)),
          vetName: 'MV. Especialista $i',
          professionalCrmv: 'SP-$i',
        ),
      );

      final bytes = await VaccinationPdf.generate(thor, longList);
      final file = File('${outputDir.path}/carteira_vacinacao_multipage.pdf');
      await file.writeAsBytes(bytes);

      expect(file.existsSync(), isTrue);
      expect(bytes.length, greaterThan(4000));
      expect(bytes.take(4), orderedEquals('%PDF'.codeUnits));
    });
  });
}
