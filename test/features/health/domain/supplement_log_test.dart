import 'package:canil_gcm/features/health/domain/health_v1_models.dart';
import 'package:canil_gcm/features/health/domain/supplement_log.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final actor = RecordedBy(
    uid: 'u1',
    name: 'Condutor',
    internalRole: 'condutor',
  );
  final now = DateTime.utc(2026, 7, 14, 10);

  group('SupplementLog', () {
    test('construção válida', () {
      final log = SupplementLog(
        id: 'sl-1',
        dogId: 'dog-1',
        supplementName: 'Ômega 3',
        dose: 1000,
        unit: SupplementDoseUnit.mg,
        administeredAt: now,
        recordedBy: actor,
        schemaVersion: 1,
        revision: 1,
      );
      expect(log.dose, 1000);
      expect(log.unit, SupplementDoseUnit.mg);
      expect(log.nutritionPlanId, isNull);
      expect(log.protocolId, isNull);
      expect(log.revision, 1);
    });

    test('revision < 1 é rejeitada', () {
      expect(
        () => SupplementLog(
          id: 'sl-1',
          dogId: 'dog-1',
          supplementName: 'X',
          dose: 1,
          unit: SupplementDoseUnit.mg,
          administeredAt: now,
          recordedBy: actor,
          schemaVersion: 1,
          revision: 0,
        ),
        throwsA(isA<HealthDomainException>()),
      );
    });

    test('supplementName vazio é rejeitado', () {
      expect(
        () => SupplementLog(
          id: 'sl-1',
          dogId: 'dog-1',
          supplementName: '   ',
          dose: 100,
          unit: SupplementDoseUnit.mg,
          administeredAt: now,
          recordedBy: actor,
          schemaVersion: 1,
          revision: 1,
        ),
        throwsA(isA<HealthDomainException>()),
      );
    });

    test('dose <= 0 é rejeitada', () {
      expect(
        () => SupplementLog(
          id: 'sl-1',
          dogId: 'dog-1',
          supplementName: 'Vitamina C',
          dose: 0,
          unit: SupplementDoseUnit.mg,
          administeredAt: now,
          recordedBy: actor,
          schemaVersion: 1,
          revision: 1,
        ),
        throwsA(isA<HealthDomainException>()),
      );
    });

    test('dose não finita é rejeitada', () {
      expect(
        () => SupplementLog(
          id: 'sl-1',
          dogId: 'dog-1',
          supplementName: 'Vitamina C',
          dose: double.nan,
          unit: SupplementDoseUnit.mg,
          administeredAt: now,
          recordedBy: actor,
          schemaVersion: 1,
          revision: 1,
        ),
        throwsA(isA<HealthDomainException>()),
      );
    });

    test('vínculo opcional ao plano e protocolo é preservado', () {
      final log = SupplementLog(
        id: 'sl-1',
        dogId: 'dog-1',
        supplementName: 'Ômega 3',
        dose: 500,
        unit: SupplementDoseUnit.mg,
        administeredAt: now,
        recordedBy: actor,
        schemaVersion: 1,
        revision: 1,
        nutritionPlanId: 'np-1',
        protocolId: 'tp-1',
        supplementRegimenId: 'reg-1',
      );
      expect(log.nutritionPlanId, 'np-1');
      expect(log.protocolId, 'tp-1');
      expect(log.supplementRegimenId, 'reg-1');
    });

    test('validateAdministeredAt rejeita futuro', () {
      final log = SupplementLog(
        id: 'sl-1',
        dogId: 'dog-1',
        supplementName: 'X',
        dose: 1,
        unit: SupplementDoseUnit.mg,
        administeredAt: now,
        recordedBy: actor,
        schemaVersion: 1,
        revision: 1,
      );
      log.validateAdministeredAt(referenceTime: now);
      expect(
        () => log.validateAdministeredAt(
          referenceTime: now.subtract(const Duration(seconds: 1)),
        ),
        throwsA(isA<HealthDomainException>()),
      );
    });

    test('unit expõe wireNames aprovados', () {
      expect(SupplementDoseUnit.mg.wireName, 'mg');
      expect(SupplementDoseUnit.g.wireName, 'g');
      expect(SupplementDoseUnit.ml.wireName, 'ml');
      expect(SupplementDoseUnit.scoop.wireName, 'scoop');
      expect(SupplementDoseUnit.tablet.wireName, 'tablet');
      expect(SupplementDoseUnit.drop.wireName, 'drop');
      expect(SupplementDoseUnit.other.wireName, 'other');
    });
  });
}
