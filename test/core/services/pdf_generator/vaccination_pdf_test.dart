import 'package:canil_gcm/core/services/pdf_generator/vaccination_pdf.dart';
import 'package:canil_gcm/features/dogs/domain/dog.dart';
import 'package:canil_gcm/features/health/domain/health_log_model.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('gera carteira para registro canônico de vacinação', () async {
    final dog = Dog(
      id: 'dog-1',
      name: 'Kira',
      breed: 'Pastor Alemão',
      dateOfBirth: DateTime.utc(2020),
    );
    final log = HealthLogModel(
      id: 'vacina-1',
      dogId: dog.id,
      dogName: dog.name,
      date: DateTime(2026, 8, 11),
      type: 'vaccination',
      subtype: 'Antirrábica',
      healthObservations: 'Lote: AR-2026',
      nextDueDate: DateTime(2027, 8, 11),
    );

    final bytes = await VaccinationPdf.generate(dog, [log]);

    expect(bytes, isNotEmpty);
    expect(bytes.take(4), orderedEquals('%PDF'.codeUnits));
  });
}
