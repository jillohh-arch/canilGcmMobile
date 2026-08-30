import 'package:canil_gcm/features/health/domain/health_v1_enums_ext.dart';
import 'package:canil_gcm/features/health/domain/health_v1_models.dart';
import 'package:canil_gcm/features/health/domain/health_v1_value_objects.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Enums canônicos', () {
    test('RestrictionLevel expõe wireNames aprovados', () {
      expect(RestrictionLevel.absolute.wireName, 'absolute');
      expect(RestrictionLevel.partial.wireName, 'partial');
      expect(RestrictionLevel.attention.wireName, 'attention');
    });

    test('TreatmentStatus expõe wireNames aprovados', () {
      expect(TreatmentStatus.active.wireName, 'active');
      expect(TreatmentStatus.paused.wireName, 'paused');
      expect(TreatmentStatus.completed.wireName, 'completed');
      expect(TreatmentStatus.cancelled.wireName, 'cancelled');
    });

    test('ReadinessStatus expõe wireNames do ADR-005', () {
      expect(ReadinessStatus.operational.wireName, 'operational');
      expect(
        ReadinessStatus.operationalAttention.wireName,
        'operational_attention',
      );
      expect(
        ReadinessStatus.fitWithRestrictions.wireName,
        'fit_with_restrictions',
      );
      expect(ReadinessStatus.temporarilyUnfit.wireName, 'temporarily_unfit');
      expect(ReadinessStatus.notEvaluated.wireName, 'not_evaluated');
    });

    test('ScheduleLifecycleStatus e ScheduleType têm wire names', () {
      expect(ScheduleLifecycleStatus.open.wireName, 'open');
      expect(ScheduleType.vaccination.wireName, 'vaccination');
      expect(ScheduleType.deworming.wireName, 'deworming');
    });

    test('VaccinationStatus e PayloadType aprovados', () {
      expect(VaccinationStatus.finalised.wireName, 'final');
      expect(VaccinationStatus.cancelled.wireName, 'cancelled');
      expect(PayloadType.consultationV1.wireName, 'consultation_v1');
      expect(PayloadType.restrictionIssuedV1.wireName, 'restriction_issued_v1');
    });
  });

  group('Value objects compartilhados', () {
    test('ProfessionalIdentity valida campos obrigatórios', () {
      expect(
        () => ProfessionalIdentity(
          name: '',
          registrationType: ProfessionalRegistrationType.crmv,
          registrationNumber: 'CRMV-1',
          clinic: 'Clínica',
        ),
        throwsA(isA<HealthDomainException>()),
      );
      expect(
        () => ProfessionalIdentity(
          name: 'Dra. Vet',
          registrationType: ProfessionalRegistrationType.crmv,
          registrationNumber: '',
          clinic: 'Clínica',
        ),
        throwsA(isA<HealthDomainException>()),
      );
    });

    test('ProfessionalIdentity normaliza e suporta equality', () {
      final a = ProfessionalIdentity(
        name: '  Dra. Vet  ',
        registrationType: ProfessionalRegistrationType.crmv,
        registrationNumber: 'CRMV-1',
        clinic: '  Clínica  ',
        specialty: '  clínica geral  ',
      );
      final b = ProfessionalIdentity(
        name: 'Dra. Vet',
        registrationType: ProfessionalRegistrationType.crmv,
        registrationNumber: 'CRMV-1',
        clinic: 'Clínica',
        specialty: 'clínica geral',
      );
      expect(a, b);
      expect(a.specialty, 'clínica geral');
    });

    test(
      'OperationalImpact com level=none e restrictions não vazias é rejeitado',
      () {
        expect(
          () => OperationalImpact(
            level: OperationalImpactLevel.none,
            description: 'desc',
            restrictionsIssued: const ['busca'],
          ),
          throwsA(isA<HealthDomainException>()),
        );
      },
    );

    test('DoseBlock rejeita valor inválido', () {
      expect(
        () => DoseBlock(
          value: 0,
          unit: DoseUnit.mg,
          perKg: false,
          route: DoseRoute.oral,
        ),
        throwsA(isA<HealthDomainException>()),
      );
    });

    test('ScheduleBlock exige interval quando type=interval', () {
      expect(
        () => ScheduleBlock(
          type: ScheduleTypeBlock.interval,
          timezone: 'America/Sao_Paulo',
          toleranceMinutes: 30,
        ),
        throwsA(isA<HealthDomainException>()),
      );
    });

    test('ScheduleBlock exige times_of_day quando type=fixedTimes', () {
      expect(
        () => ScheduleBlock(
          type: ScheduleTypeBlock.fixedTimes,
          timezone: 'America/Sao_Paulo',
          toleranceMinutes: 30,
        ),
        throwsA(isA<HealthDomainException>()),
      );
    });
  });
}
