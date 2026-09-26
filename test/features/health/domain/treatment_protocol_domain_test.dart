import 'package:flutter_test/flutter_test.dart';
import 'package:canil_gcm/features/health/domain/treatment_protocol.dart';
import 'package:canil_gcm/features/health/domain/dose_administration.dart';
import 'package:canil_gcm/features/health/domain/health_v1_enums_ext.dart';
import 'package:canil_gcm/features/health/domain/health_v1_models.dart';
import 'package:canil_gcm/features/health/domain/health_v1_value_objects.dart';
import 'package:canil_gcm/features/health/domain/health_schedule_item.dart';
import 'package:canil_gcm/features/health/domain/health_schedule_revision.dart';
import 'package:canil_gcm/features/health/presentation/schedule/health_schedule_action_availability.dart';
import 'package:canil_gcm/features/health/presentation/schedule/health_schedule_item_view.dart';
import 'package:canil_gcm/features/health/domain/health_v1_transitions_v2.dart';

void main() {
  final actor = RecordedBy(
    uid: 'u_vet_1',
    name: 'Dr. Veterinario',
    internalRole: 'veterinario',
  );

  final professional = ProfessionalIdentity(
    name: 'Dr. Veterinario',
    registrationType: ProfessionalRegistrationType.crmv,
    registrationNumber: 'CRMV-SP 12345',
    clinic: 'Canil Central',
  );

  final sourceDoc = const HealthDocumentRef(healthDocumentId: 'doc_prescription_01');
  final now = DateTime.utc(2026, 9, 5, 12, 0, 0);

  group('TreatmentProtocol serialization roundtrip', () {
    test('toMap and fromMap preserve all fields accurately', () {
      final original = TreatmentProtocol(
        id: 'proto_123',
        dogId: 'dog_456',
        caseId: 'case_789',
        medicationName: 'Amoxicilina 500mg',
        dose: DoseBlock(
          value: 250,
          unit: DoseUnit.mg,
          perKg: true,
          route: DoseRoute.oral,
        ),
        schedule: ScheduleBlock(
          type: ScheduleTypeBlock.interval,
          intervalMinutes: 480,
          timesOfDay: const ['08:00', '16:00', '00:00'],
          timezone: 'America/Sao_Paulo',
          toleranceMinutes: 45,
        ),
        startDate: now,
        durationDays: 10,
        recordedBy: actor,
        professional: professional,
        sourceDocument: sourceDoc,
        status: TreatmentStatus.active,
        schemaVersion: 1,
        instructions: 'Tomar junto com alimento',
        pausedAt: null,
        pauseReason: null,
        completedAt: null,
        cancelledAt: null,
        cancelReason: null,
      );

      final map = original.toMap();
      expect(map['dog_id'], 'dog_456');
      expect(map['case_id'], 'case_789');
      expect(map['medication_name'], 'Amoxicilina 500mg');
      expect(map['status'], 'active');
      expect(map['duration_days'], 10);
      expect(map['instructions'], 'Tomar junto com alimento');

      final reconstructed = TreatmentProtocol.fromMap(map, documentId: original.id);
      expect(reconstructed.id, original.id);
      expect(reconstructed.dogId, original.dogId);
      expect(reconstructed.caseId, original.caseId);
      expect(reconstructed.medicationName, original.medicationName);
      expect(reconstructed.status, original.status);
      expect(reconstructed.dose.value, 250);
      expect(reconstructed.dose.unit, DoseUnit.mg);
      expect(reconstructed.dose.perKg, isTrue);
      expect(reconstructed.dose.route, DoseRoute.oral);
      expect(reconstructed.schedule.intervalMinutes, 480);
      expect(reconstructed.schedule.timesOfDay, ['08:00', '16:00', '00:00']);
      expect(reconstructed.durationDays, 10);
      expect(reconstructed.instructions, 'Tomar junto com alimento');
      expect(reconstructed.recordedBy.uid, 'u_vet_1');
      expect(reconstructed.professional.registrationNumber, 'CRMV-SP 12345');
    });

    test('reconstruction with paused status and reason', () {
      final pausedTime = now.add(const Duration(days: 2));
      final original = TreatmentProtocol(
        id: 'proto_paused',
        dogId: 'dog_456',
        caseId: 'case_789',
        medicationName: 'Anti-inflamatório',
        dose: DoseBlock(
          value: 10,
          unit: DoseUnit.mg,
          perKg: false,
          route: DoseRoute.oral,
        ),
        schedule: ScheduleBlock(
          type: ScheduleTypeBlock.interval,
          intervalMinutes: 1440,
          timezone: 'America/Sao_Paulo',
          toleranceMinutes: 30,
        ),
        startDate: now,
        durationDays: 5,
        recordedBy: actor,
        professional: professional,
        sourceDocument: sourceDoc,
        status: TreatmentStatus.paused,
        schemaVersion: 1,
        pausedAt: pausedTime,
        pauseReason: 'Aguardando resultado de exame renal',
      );

      final map = original.toMap();
      final reconstructed = TreatmentProtocol.fromMap(map, documentId: original.id);
      expect(reconstructed.status, TreatmentStatus.paused);
      expect(reconstructed.pausedAt, pausedTime);
      expect(reconstructed.pauseReason, 'Aguardando resultado de exame renal');
    });
  });

  group('DoseAdministration serialization roundtrip', () {
    test('administered dose roundtrip', () {
      final identity = DoseIdentity(protocolId: 'proto_123', plannedDoseId: 'dose_0');
      final scheduled = now;
      final administered = now.add(const Duration(minutes: 10));

      final original = DoseAdministration(
        identity: identity,
        protocolId: 'proto_123',
        dogId: 'dog_456',
        scheduledFor: scheduled,
        status: DoseStatus.administered,
        recordedBy: actor,
        recordedAt: administered,
        schemaVersion: 1,
        administeredAt: administered,
        observations: 'Administrado sem resistência',
      );

      final map = original.toMap();
      expect(map['protocol_id'], 'proto_123');
      expect(map['dog_id'], 'dog_456');
      expect(map['status'], 'administered');
      expect(map['observations'], 'Administrado sem resistência');

      final reconstructed = DoseAdministration.fromMap(map, documentId: original.doseId);
      expect(reconstructed.doseId, original.doseId);
      expect(reconstructed.identity.protocolId, 'proto_123');
      expect(reconstructed.identity.plannedDoseId, 'dose_0');
      expect(reconstructed.status, DoseStatus.administered);
      expect(reconstructed.administeredAt, administered);
      expect(reconstructed.observations, 'Administrado sem resistência');
    });

    test('skipped dose roundtrip', () {
      final identity = DoseIdentity(protocolId: 'proto_123', plannedDoseId: 'dose_1');
      final scheduled = now;

      final original = DoseAdministration(
        identity: identity,
        protocolId: 'proto_123',
        dogId: 'dog_456',
        scheduledFor: scheduled,
        status: DoseStatus.skipped,
        recordedBy: actor,
        recordedAt: scheduled,
        schemaVersion: 1,
        skipReason: 'Vômito após alimentação',
      );

      final map = original.toMap();
      expect(map['status'], 'skipped');
      expect(map['skip_reason'], 'Vômito após alimentação');

      final reconstructed = DoseAdministration.fromMap(map, documentId: original.doseId);
      expect(reconstructed.status, DoseStatus.skipped);
      expect(reconstructed.skipReason, 'Vômito após alimentação');
    });
  });

  group('DoseIdentity deterministic hashing stability', () {
    test('same inputs yield exactly the same hash', () {
      final h1 = DoseIdentity(protocolId: 'p_alpha', plannedDoseId: 'dose_99').deriveDoseId();
      final h2 = DoseIdentity(protocolId: 'p_alpha', plannedDoseId: 'dose_99').deriveDoseId();
      expect(h1, h2);
      expect(h1.length, 64);
    });

    test('different inputs produce different hashes', () {
      final h1 = DoseIdentity(protocolId: 'p_1', plannedDoseId: 'dose_1').deriveDoseId();
      final h2 = DoseIdentity(protocolId: 'p_1', plannedDoseId: 'dose_2').deriveDoseId();
      final h3 = DoseIdentity(protocolId: 'p_2', plannedDoseId: 'dose_1').deriveDoseId();

      expect(h1, isNot(h2));
      expect(h1, isNot(h3));
      expect(h2, isNot(h3));
    });

    test('prefix ambiguity resistance', () {
      // Prevents "ab" + "c" matching "a" + "bc"
      final h1 = DoseIdentity(protocolId: 'ab', plannedDoseId: 'c').deriveDoseId();
      final h2 = DoseIdentity(protocolId: 'a', plannedDoseId: 'bc').deriveDoseId();
      expect(h1, isNot(h2));
    });
  });

  group('TreatmentProtocol State Transitions', () {
    TreatmentProtocol createActive() => TreatmentProtocol(
      id: 'proto_state',
      dogId: 'dog_1',
      caseId: 'case_1',
      medicationName: 'Med',
      dose: DoseBlock(value: 10, unit: DoseUnit.mg, perKg: false, route: DoseRoute.oral),
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
      status: TreatmentStatus.active,
      schemaVersion: 1,
    );

    test('active -> paused -> active -> completed', () {
      final active1 = createActive();
      expect(TreatmentProtocolTransitions.canTransition(active1.status, TreatmentStatus.paused), isTrue);

      final paused = TreatmentProtocolTransitions.transition(
        active1,
        TreatmentStatus.paused,
        pausedAt: now,
        pauseReason: 'Cão em jejum para procedimento',
      );
      expect(paused.status, TreatmentStatus.paused);
      expect(paused.pauseReason, 'Cão em jejum para procedimento');

      expect(TreatmentProtocolTransitions.canTransition(paused.status, TreatmentStatus.active), isTrue);
      final active2 = TreatmentProtocolTransitions.transition(
        paused,
        TreatmentStatus.active,
      );
      expect(active2.status, TreatmentStatus.active);
      expect(active2.pausedAt, isNull);
      expect(active2.pauseReason, isNull);

      expect(TreatmentProtocolTransitions.canTransition(active2.status, TreatmentStatus.completed), isTrue);
      final completed = TreatmentProtocolTransitions.transition(
        active2,
        TreatmentStatus.completed,
        completedAt: now.add(const Duration(days: 7)),
      );
      expect(completed.status, TreatmentStatus.completed);
    });

    test('completed and cancelled are terminal states', () {
      expect(TreatmentProtocolTransitions.canTransition(TreatmentStatus.completed, TreatmentStatus.active), isFalse);
      expect(TreatmentProtocolTransitions.canTransition(TreatmentStatus.completed, TreatmentStatus.paused), isFalse);
      expect(TreatmentProtocolTransitions.canTransition(TreatmentStatus.completed, TreatmentStatus.cancelled), isFalse);

      expect(TreatmentProtocolTransitions.canTransition(TreatmentStatus.cancelled, TreatmentStatus.active), isFalse);
      expect(TreatmentProtocolTransitions.canTransition(TreatmentStatus.cancelled, TreatmentStatus.paused), isFalse);
      expect(TreatmentProtocolTransitions.canTransition(TreatmentStatus.cancelled, TreatmentStatus.completed), isFalse);
    });
  });

  group('Paused Treatment Schedule Item Domain & Presentation Rules', () {
    final temporalConfig = MapHealthScheduleTemporalConfig.uniform(
      HealthScheduleTypeTemporalConfig(
        toleranceAfterScheduled: const Duration(hours: 4),
        upcomingWindow: const Duration(hours: 12),
      ),
    );
    final policy = HealthScheduleTemporalPolicy(config: temporalConfig);

    test('isPaused schedule item suppresses overdue/pending/today to scheduled status', () {
      final scheduledPast = now.subtract(const Duration(hours: 5));
      final duePast = now.subtract(const Duration(hours: 1));

      final pausedItem = HealthScheduleItem(
        id: 'sch_dose_paused',
        dogId: 'dog_456',
        scheduleType: ScheduleType.dose,
        title: 'Dose: Amoxicilina',
        scheduledFor: scheduledPast,
        dueUntil: duePast,
        timezone: 'America/Sao_Paulo',
        lifecycleStatus: ScheduleLifecycleStatus.open,
        sourceType: ScheduleSourceType.treatmentProtocol,
        createdAt: now.subtract(const Duration(days: 1)),
        recordedBy: actor,
        schemaVersion: 1,
        isPaused: true,
      );

      // Sem pausa, o item seria overdue
      final activeItem = HealthScheduleItem(
        id: 'sch_dose_active',
        dogId: 'dog_456',
        scheduleType: ScheduleType.dose,
        title: 'Dose: Amoxicilina',
        scheduledFor: scheduledPast,
        dueUntil: duePast,
        timezone: 'America/Sao_Paulo',
        lifecycleStatus: ScheduleLifecycleStatus.open,
        sourceType: ScheduleSourceType.treatmentProtocol,
        createdAt: now.subtract(const Duration(days: 1)),
        recordedBy: actor,
        schemaVersion: 1,
        isPaused: false,
      );

      expect(policy.evaluate(activeItem, now: now), HealthScheduleTemporalStatus.overdue);
      expect(policy.evaluate(pausedItem, now: now), HealthScheduleTemporalStatus.scheduled);
    });

    test('isPaused schedule item yields NO actionable buttons in presentation', () {
      final viewPaused = HealthScheduleItemView(
        id: 'sch_dose_paused',
        dogId: 'dog_456',
        scheduleType: ScheduleType.dose,
        title: 'Dose: Amoxicilina',
        scheduledFor: now,
        timezone: 'America/Sao_Paulo',
        lifecycleStatus: ScheduleLifecycleStatus.open,
        sourceType: ScheduleSourceType.treatmentProtocol,
        temporalStatus: HealthScheduleTemporalStatus.scheduled,
        createdAt: now,
        recordedBy: actor,
        schemaVersion: 1,
        revision: const HealthScheduleRevision('1'),
        isPaused: true,
      );

      final viewActive = HealthScheduleItemView(
        id: 'sch_dose_active',
        dogId: 'dog_456',
        scheduleType: ScheduleType.dose,
        title: 'Dose: Amoxicilina',
        scheduledFor: now,
        timezone: 'America/Sao_Paulo',
        lifecycleStatus: ScheduleLifecycleStatus.open,
        sourceType: ScheduleSourceType.treatmentProtocol,
        temporalStatus: HealthScheduleTemporalStatus.pending,
        createdAt: now,
        recordedBy: actor,
        schemaVersion: 1,
        revision: const HealthScheduleRevision('1'),
        isPaused: false,
      );

      final pausedActions = HealthScheduleActionAvailability.forView(viewPaused);
      expect(pausedActions, isEmpty);
      expect(HealthScheduleActionAvailability.canComplete(viewPaused), isFalse);
      expect(HealthScheduleActionAvailability.canEdit(viewPaused), isFalse);
      expect(HealthScheduleActionAvailability.canCancel(viewPaused), isFalse);

      final activeActions = HealthScheduleActionAvailability.forView(viewActive);
      expect(activeActions, contains(HealthScheduleItemAction.complete));
      expect(HealthScheduleActionAvailability.canComplete(viewActive), isTrue);
    });
  });
}
