import 'package:canil_gcm/features/health/domain/health_v1_enums_ext.dart';
import 'package:canil_gcm/features/health/domain/health_v1_models.dart';
import 'package:canil_gcm/features/health/domain/treatment_protocol.dart';
import 'package:canil_gcm/features/health/domain/health_v1_value_objects.dart';
import 'package:canil_gcm/features/health/domain/health_v1_transitions_v2.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final actor = RecordedBy(
    uid: 'u1',
    name: 'Condutor',
    internalRole: 'condutor',
  );
  final professional = ProfessionalIdentity(
    name: 'Dra. Vet',
    registrationType: ProfessionalRegistrationType.crmv,
    registrationNumber: 'CRMV-123',
    clinic: 'Clínica Norte',
  );
  final sourceDoc = const HealthDocumentRef(healthDocumentId: 'doc-1');
  final now = DateTime.utc(2026, 7, 14, 10);

  TreatmentProtocol build({
    TreatmentStatus status = TreatmentStatus.active,
    DateTime? pausedAt,
    String? pauseReason,
    DateTime? completedAt,
    DateTime? cancelledAt,
    String? cancelReason,
    int durationDays = 7,
  }) => TreatmentProtocol(
    id: 'tp-1',
    dogId: 'dog-1',
    caseId: 'case-1',
    medicationName: 'Amoxicilina',
    dose: DoseBlock(
      value: 500,
      unit: DoseUnit.mg,
      perKg: false,
      route: DoseRoute.oral,
    ),
    schedule: ScheduleBlock(
      type: ScheduleTypeBlock.interval,
      intervalMinutes: 720,
      timezone: 'America/Sao_Paulo',
      toleranceMinutes: 30,
    ),
    startDate: now,
    recordedBy: actor,
    professional: professional,
    sourceDocument: sourceDoc,
    status: status,
    schemaVersion: 1,
    durationDays: durationDays,
    pausedAt: pausedAt,
    pauseReason: pauseReason,
    completedAt: completedAt,
    cancelledAt: cancelledAt,
    cancelReason: cancelReason,
  );

  group('TreatmentProtocol', () {
    test('construção válida retorna protocolo', () {
      final tp = build();
      expect(tp.status, TreatmentStatus.active);
      expect(tp.medicationName, 'Amoxicilina');
      expect(tp.dose.value, 500);
    });

    test('paused exige paused_at e pause_reason', () {
      expect(
        () => build(
          status: TreatmentStatus.paused,
          pausedAt: now,
          pauseReason: null,
        ),
        throwsA(isA<HealthDomainException>()),
      );
      expect(
        () => build(
          status: TreatmentStatus.paused,
          pausedAt: null,
          pauseReason: 'animal ausente',
        ),
        throwsA(isA<HealthDomainException>()),
      );
    });

    test('completed exige completed_at', () {
      expect(
        () => build(status: TreatmentStatus.completed, completedAt: null),
        throwsA(isA<HealthDomainException>()),
      );
    });

    test('cancelled exige cancelled_at e cancel_reason', () {
      expect(
        () => build(
          status: TreatmentStatus.cancelled,
          cancelledAt: now,
          cancelReason: null,
        ),
        throwsA(isA<HealthDomainException>()),
      );
      expect(
        () => build(
          status: TreatmentStatus.cancelled,
          cancelledAt: null,
          cancelReason: 'erro',
        ),
        throwsA(isA<HealthDomainException>()),
      );
    });

    test('não cancelado não pode ter metadados de cancelamento', () {
      expect(
        () => build(
          status: TreatmentStatus.active,
          cancelledAt: now,
          cancelReason: 'erro',
        ),
        throwsA(isA<HealthDomainException>()),
      );
    });

    test('durationDays <= 0 é rejeitado', () {
      expect(() => build(durationDays: 0), throwsA(isA<HealthDomainException>()));
    });

    test('estado active não pode ter metadados paused/completed', () {
      expect(
        () => build(
          status: TreatmentStatus.active,
          pausedAt: now,
          pauseReason: 'parado',
        ),
        throwsA(isA<HealthDomainException>()),
      );
    });

    test('matriz completa de transições (independente)', () {
      const expected = <TreatmentStatus, Set<TreatmentStatus>>{
        TreatmentStatus.active: {
          TreatmentStatus.paused,
          TreatmentStatus.completed,
          TreatmentStatus.cancelled,
        },
        TreatmentStatus.paused: {
          TreatmentStatus.active,
          TreatmentStatus.cancelled,
        },
        TreatmentStatus.completed: {},
        TreatmentStatus.cancelled: {},
      };
      for (final origin in TreatmentStatus.values) {
        for (final destination in TreatmentStatus.values) {
          final allowed = expected[origin]!.contains(destination);
          final reason = '${origin.wireName} → ${destination.wireName}';
          expect(
            TreatmentProtocolTransitions.canTransition(origin, destination),
            allowed,
            reason: reason,
          );
        }
      }
    });

    test('transição active→paused exige pause_reason', () {
      final tp = build();
      expect(
        () => TreatmentProtocolTransitions.transition(
          tp,
          TreatmentStatus.paused,
          pausedAt: now,
          pauseReason: '',
        ),
        throwsA(isA<HealthDomainException>()),
      );
    });

    test('transição active→completed exige completed_at', () {
      final tp = build();
      expect(
        () => TreatmentProtocolTransitions.transition(
          tp,
          TreatmentStatus.completed,
        ),
        throwsA(isA<HealthDomainException>()),
      );
    });

    test('transição active→cancelled exige cancel_reason', () {
      final tp = build();
      expect(
        () => TreatmentProtocolTransitions.transition(
          tp,
          TreatmentStatus.cancelled,
          cancelledAt: now,
          cancelReason: '',
        ),
        throwsA(isA<HealthDomainException>()),
      );
    });

    test('transição paused→active limpa metadados de pausa', () {
      final paused = build(
        status: TreatmentStatus.paused,
        pausedAt: now,
        pauseReason: 'animal ausente',
      );
      final resumed = TreatmentProtocolTransitions.transition(
        paused,
        TreatmentStatus.active,
      );
      expect(resumed.status, TreatmentStatus.active);
      expect(resumed.pausedAt, isNull);
      expect(resumed.pauseReason, isNull);
    });
  });
}