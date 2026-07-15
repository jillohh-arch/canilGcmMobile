import 'package:canil_gcm/features/health/domain/health_v1_enums_ext.dart';
import 'package:canil_gcm/features/health/domain/health_v1_models.dart';
import 'package:canil_gcm/features/health/domain/health_v1_transitions_v2.dart';
import 'package:canil_gcm/features/health/domain/health_v1_value_objects.dart';
import 'package:canil_gcm/features/health/domain/vaccination_record.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final actor = RecordedBy(
    uid: 'u1',
    name: 'Condutor',
    internalRole: 'condutor',
  );
  final applied = DateTime.utc(2026, 7, 14, 10);

  VaccinationRecord build({
    VaccinationStatus status = VaccinationStatus.finalised,
    DateTime? validityUntil,
    DateTime? nextDueAt,
    String? notes,
    String? dose,
    DateTime? cancelledAt,
    RecordedBy? cancelledBy,
    String? cancelReason,
  }) => VaccinationRecord(
    id: 'vr-1',
    dogId: 'dog-1',
    vaccineName: 'V10',
    appliedAt: applied,
    recordedBy: actor,
    recordStatus: status,
    schemaVersion: 1,
    validityUntil: validityUntil,
    nextDueAt: nextDueAt,
    notes: notes,
    dose: dose,
    cancelledAt: cancelledAt,
    cancelledBy: cancelledBy,
    cancelReason: cancelReason,
  );

  group('VaccinationRecord', () {
    test('construção válida com status final', () {
      final r = build(dose: '1 ml');
      expect(r.recordStatus, VaccinationStatus.finalised);
      expect(r.vaccineName, 'V10');
      expect(r.dose, '1 ml');
    });

    test('vaccine_name vazio é rejeitado', () {
      expect(
        () => VaccinationRecord(
          id: 'vr-1',
          dogId: 'dog-1',
          vaccineName: '   ',
          appliedAt: applied,
          recordedBy: actor,
          recordStatus: VaccinationStatus.finalised,
          schemaVersion: 1,
        ),
        throwsA(isA<HealthDomainException>()),
      );
    });

    test('schemaVersion <= 0 é rejeitado', () {
      expect(
        () => VaccinationRecord(
          id: 'vr-1',
          dogId: 'dog-1',
          vaccineName: 'V10',
          appliedAt: applied,
          recordedBy: actor,
          recordStatus: VaccinationStatus.finalised,
          schemaVersion: 0,
        ),
        throwsA(isA<HealthDomainException>()),
      );
    });

    test('validityUntil anterior a appliedAt é rejeitado', () {
      expect(
        () => build(validityUntil: applied.subtract(const Duration(days: 1))),
        throwsA(isA<HealthDomainException>()),
      );
    });

    test('nextDueAt anterior a appliedAt é rejeitado', () {
      expect(
        () => build(nextDueAt: applied.subtract(const Duration(days: 1))),
        throwsA(isA<HealthDomainException>()),
      );
    });

    test('cancelled exige metadados completos', () {
      expect(
        () => build(status: VaccinationStatus.cancelled),
        throwsA(isA<HealthDomainException>()),
      );
      expect(
        () => build(
          status: VaccinationStatus.cancelled,
          cancelledAt: applied,
          cancelledBy: actor,
          cancelReason: '',
        ),
        throwsA(isA<HealthDomainException>()),
      );
      final r = build(
        status: VaccinationStatus.cancelled,
        cancelledAt: applied,
        cancelledBy: actor,
        cancelReason: 'registro duplicado',
      );
      expect(r.recordStatus, VaccinationStatus.cancelled);
      expect(r.cancelReason, 'registro duplicado');
    });

    test('final não aceita metadados de cancelamento', () {
      expect(
        () =>
            build(cancelledAt: applied, cancelledBy: actor, cancelReason: 'x'),
        throwsA(isA<HealthDomainException>()),
      );
    });

    test('professional e sourceDocument opcionais em aplicação interna', () {
      final r = build();
      expect(r.professional, isNull);
      expect(r.sourceDocument, isNull);
    });

    test('professional preenchido quando aplicação externa', () {
      final r = VaccinationRecord(
        id: 'vr-1',
        dogId: 'dog-1',
        vaccineName: 'Antirrábica',
        appliedAt: applied,
        recordedBy: actor,
        recordStatus: VaccinationStatus.finalised,
        schemaVersion: 1,
        professional: ProfessionalIdentity(
          name: 'Dra. Vet',
          registrationType: ProfessionalRegistrationType.crmv,
          registrationNumber: 'CRMV-999',
          clinic: 'Clínica X',
        ),
        sourceDocument: const HealthDocumentRef(healthDocumentId: 'doc-1'),
      );
      expect(r.professional?.registrationNumber, 'CRMV-999');
      expect(r.sourceDocument?.healthDocumentId, 'doc-1');
    });
  });

  group('VaccinationRecordTransitions', () {
    /// Matriz esperada declarada independentemente da implementação.
    const expected = <VaccinationStatus, Set<VaccinationStatus>>{
      VaccinationStatus.finalised: {VaccinationStatus.cancelled},
      VaccinationStatus.cancelled: {},
    };

    test('matriz completa de transições', () {
      for (final origin in VaccinationStatus.values) {
        for (final destination in VaccinationStatus.values) {
          final allowed = expected[origin]!.contains(destination);
          expect(
            VaccinationRecordTransitions.canTransition(origin, destination),
            allowed,
            reason: '${origin.wireName} → ${destination.wireName}',
          );
        }
      }
    });

    test('final → cancelled com metadados', () {
      final original = build();
      final cancelled = VaccinationRecordTransitions.transition(
        original,
        VaccinationStatus.cancelled,
        cancelledAt: applied.add(const Duration(hours: 1)),
        cancelledBy: actor,
        cancelReason: 'duplicado',
      );
      expect(cancelled.recordStatus, VaccinationStatus.cancelled);
      expect(cancelled.cancelReason, 'duplicado');
      expect(cancelled.vaccineName, original.vaccineName);
    });

    test('final → cancelled sem reason é rejeitado', () {
      expect(
        () => VaccinationRecordTransitions.transition(
          build(),
          VaccinationStatus.cancelled,
          cancelledAt: applied,
          cancelledBy: actor,
          cancelReason: '  ',
        ),
        throwsA(isA<HealthDomainException>()),
      );
    });

    test('cancelled → final é proibido', () {
      final cancelled = build(
        status: VaccinationStatus.cancelled,
        cancelledAt: applied,
        cancelledBy: actor,
        cancelReason: 'erro',
      );
      expect(
        () => VaccinationRecordTransitions.transition(
          cancelled,
          VaccinationStatus.finalised,
        ),
        throwsA(isA<HealthDomainException>()),
      );
    });
  });
}
