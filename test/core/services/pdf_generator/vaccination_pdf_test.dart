import 'package:canil_gcm/core/services/pdf_generator/vaccination_pdf.dart';
import 'package:canil_gcm/features/dogs/domain/dog.dart';
import 'package:canil_gcm/features/health/domain/health_log_model.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final dog = Dog(
    id: 'dog-1',
    name: 'Kira',
    breed: 'Pastor Alemão',
    dateOfBirth: DateTime.utc(2020),
    microchip: '981098102938475',
    registrationNumber: 'K9-2020-042',
    conductorRa: '1234',
    weight: 28.5,
    specialties: ['Faro', 'Proteção'],
  );

  test('gera carteira para registro canônico de vacinação', () async {
    final log = HealthLogModel(
      id: 'vacina-1',
      dogId: dog.id,
      dogName: dog.name,
      date: DateTime(2026, 8, 11),
      type: 'vaccination',
      subtype: 'Antirrábica',
      healthObservations: 'Lote: AR-2026',
      nextDueDate: DateTime(2027, 8, 11),
      vetName: 'Dr. Roberto Santos',
      professionalCrmv: 'SP-12345',
    );

    final bytes = await VaccinationPdf.generate(dog, [log]);

    expect(bytes, isNotEmpty);
    expect(bytes.take(4), orderedEquals('%PDF'.codeUnits));
  });

  test('gera carteira para cão sem registros (caso mínimo)', () async {
    final bytes = await VaccinationPdf.generate(dog, []);

    expect(bytes, isNotEmpty);
    expect(bytes.take(4), orderedEquals('%PDF'.codeUnits));
  });

  test('gera carteira para caso rico com vacinas vencidas e a vencer', () async {
    final logs = [
      HealthLogModel(
        id: 'v1',
        dogId: dog.id,
        date: DateTime(2025, 1, 10),
        type: 'vaccination',
        subtype: 'V10 Polivalente',
        healthObservations: 'Lote: V10-2025-A',
        nextDueDate: DateTime(2026, 1, 10), // Vencida
        vetName: 'Dra. Camila Alves',
        professionalCrmv: 'SP-99887',
      ),
      HealthLogModel(
        id: 'v2',
        dogId: dog.id,
        date: DateTime(2026, 9, 1),
        type: 'vaccination',
        subtype: 'Gripal Canina',
        healthObservations: 'Lote: KC-8821',
        nextDueDate: DateTime.now().add(const Duration(days: 15)), // Vence em 15 dias
        vetName: 'Dr. Lucas Prado',
        professionalCrmv: 'SP-33441',
      ),
      HealthLogModel(
        id: 'v3',
        dogId: dog.id,
        date: DateTime(2026, 8, 15),
        type: 'vaccination',
        subtype: 'Giárdia',
        healthObservations: 'Lote: GD-1029',
        nextDueDate: DateTime.now().add(const Duration(days: 180)),
        vetName: 'Dr. Lucas Prado',
        professionalCrmv: 'SP-33441',
      ),
    ];

    final bytes = await VaccinationPdf.generate(dog, logs);

    expect(bytes, isNotEmpty);
    expect(bytes.take(4), orderedEquals('%PDF'.codeUnits));
  });

  test('gera carteira multipágina com volume elevado de imunizações (50+ registros)', () async {
    final longList = List.generate(
      55,
      (i) => HealthLogModel(
        id: 'vac-$i',
        dogId: dog.id,
        date: DateTime(2026, 1, 1).subtract(Duration(days: i * 30)),
        type: 'vaccination',
        subtype: 'Dose $i - Imunização Específica',
        healthObservations: 'Lote: BATCH-$i-2026',
        nextDueDate: DateTime(2027, 1, 1).subtract(Duration(days: i * 30)),
        vetName: 'Veterinário Responsável $i',
        professionalCrmv: 'CRMV-$i',
      ),
    );

    final bytes = await VaccinationPdf.generate(dog, longList);

    expect(bytes, isNotEmpty);
    expect(bytes.length, greaterThan(4000));
    expect(bytes.take(4), orderedEquals('%PDF'.codeUnits));
  });
}
