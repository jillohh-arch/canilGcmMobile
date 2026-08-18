import 'package:canil_gcm/features/health/domain/health_v1_enums_ext.dart';
import 'package:canil_gcm/features/health/domain/health_v1_models.dart';
import 'package:canil_gcm/features/health/domain/health_v1_transitions_v2.dart';
import 'package:canil_gcm/features/health/domain/health_v1_value_objects.dart';
import 'package:canil_gcm/features/health/domain/operational_restriction.dart';
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
  final now = DateTime.utc(2026, 7, 14);

  final endProfessional = ProfessionalIdentity(
    name: 'Dr. Externo',
    registrationType: ProfessionalRegistrationType.crmv,
    registrationNumber: 'CRMV-999',
    clinic: 'Clínica Sul',
  );
  final endDoc = const HealthDocumentRef(healthDocumentId: 'doc-end');

  OperationalRestriction build({
    RestrictionLevel level = RestrictionLevel.absolute,
    RestrictionStatus status = RestrictionStatus.active,
    List<String> activities = const ['busca'],
    DateTime? actualEnd,
    RecordedBy? endedBy,
    String? endReason,
    ProfessionalIdentity? endProfessionalOverride,
    HealthDocumentRef? endSourceDocument,
    DateTime? cancelledAt,
    RecordedBy? cancelledBy,
    String? cancelReason,
  }) => OperationalRestriction(
    id: 'r1',
    dogId: 'dog-1',
    level: level,
    category: RestrictionCategory.injury,
    description: 'desc',
    issuedAt: now,
    recordedBy: actor,
    professional: professional,
    sourceDocument: sourceDoc,
    status: status,
    schemaVersion: 1,
    activitiesRestricted: activities,
    actualEnd: actualEnd,
    endedBy: endedBy,
    endReason: endReason,
    endProfessional: endProfessionalOverride,
    endSourceDocument: endSourceDocument,
    cancelledAt: cancelledAt,
    cancelledBy: cancelledBy,
    cancelReason: cancelReason,
  );

  /// Conjunto terminal COMPLETO de END, conforme o patch persistido pelo B2.
  OperationalRestriction buildEnded() => build(
    status: RestrictionStatus.ended,
    actualEnd: now.add(const Duration(days: 1)),
    endedBy: actor,
    endReason: 'alta veterinária',
    endProfessionalOverride: endProfessional,
    endSourceDocument: endDoc,
  );

  /// Conjunto terminal COMPLETO de CANCEL: sem profissional, sem documento.
  OperationalRestriction buildCancelled() => build(
    status: RestrictionStatus.cancelled,
    cancelledAt: now.add(const Duration(days: 1)),
    cancelledBy: actor,
    cancelReason: 'registro duplicado',
  );

  group('OperationalRestriction', () {
    test('partial exige activities_restricted', () {
      expect(
        () => build(level: RestrictionLevel.partial, activities: const []),
        throwsA(isA<HealthDomainException>()),
      );
    });

    test('rejeita metadata de encerramento incompleto', () {
      expect(
        () => build(
          status: RestrictionStatus.ended,
          actualEnd: now.add(const Duration(days: 1)),
        ),
        throwsA(isA<HealthDomainException>()),
      );
    });

    test('construção ended completa é aceita', () {
      final r = buildEnded();
      expect(r.status, RestrictionStatus.ended);
      expect(r.endProfessional, endProfessional);
      expect(r.endSourceDocument, endDoc);
    });

    test('ended sem endProfessional é recusado', () {
      expect(
        () => build(
          status: RestrictionStatus.ended,
          actualEnd: now.add(const Duration(days: 1)),
          endedBy: actor,
          endReason: 'alta veterinária',
          endSourceDocument: endDoc,
        ),
        throwsA(
          isA<HealthDomainException>().having(
            (e) => e.code,
            'code',
            'incomplete_ending_metadata',
          ),
        ),
      );
    });

    test('ended sem endSourceDocument é recusado', () {
      expect(
        () => build(
          status: RestrictionStatus.ended,
          actualEnd: now.add(const Duration(days: 1)),
          endedBy: actor,
          endReason: 'alta veterinária',
          endProfessionalOverride: endProfessional,
        ),
        throwsA(
          isA<HealthDomainException>().having(
            (e) => e.code,
            'code',
            'incomplete_ending_metadata',
          ),
        ),
      );
    });

    test('construção cancelled completa é aceita', () {
      final r = buildCancelled();
      expect(r.status, RestrictionStatus.cancelled);
      expect(r.cancelReason, 'registro duplicado');
      expect(r.cancelledBy, actor);
      // CANCEL não afirma liberação clínica.
      expect(r.endProfessional, isNull);
      expect(r.endSourceDocument, isNull);
    });

    test('cancelled sem metadata de cancelamento é recusado', () {
      expect(
        () => build(status: RestrictionStatus.cancelled),
        throwsA(
          isA<HealthDomainException>().having(
            (e) => e.code,
            'code',
            'missing_cancellation_metadata',
          ),
        ),
      );
    });

    test('cancelled com metadata parcial é recusado', () {
      expect(
        () => build(
          status: RestrictionStatus.cancelled,
          cancelledAt: now.add(const Duration(days: 1)),
          cancelledBy: actor,
        ),
        throwsA(
          isA<HealthDomainException>().having(
            (e) => e.code,
            'code',
            'incomplete_cancellation_metadata',
          ),
        ),
      );
    });

    test('terminal híbrido END + CANCEL é recusado', () {
      expect(
        () => build(
          status: RestrictionStatus.ended,
          actualEnd: now.add(const Duration(days: 1)),
          endedBy: actor,
          endReason: 'alta veterinária',
          endProfessionalOverride: endProfessional,
          endSourceDocument: endDoc,
          cancelledAt: now.add(const Duration(days: 1)),
          cancelledBy: actor,
          cancelReason: 'registro duplicado',
        ),
        throwsA(
          isA<HealthDomainException>().having(
            (e) => e.code,
            'code',
            'hybrid_terminal_metadata',
          ),
        ),
      );
    });

    test('active com metadata de cancelamento é recusado', () {
      expect(
        () => build(
          cancelledAt: now.add(const Duration(days: 1)),
          cancelledBy: actor,
          cancelReason: 'registro duplicado',
        ),
        throwsA(
          isA<HealthDomainException>().having(
            (e) => e.code,
            'code',
            'unexpected_cancellation_metadata',
          ),
        ),
      );
    });

    test('cancelled_at anterior a issued_at é recusado', () {
      expect(
        () => build(
          status: RestrictionStatus.cancelled,
          cancelledAt: now.subtract(const Duration(days: 1)),
          cancelledBy: actor,
          cancelReason: 'registro duplicado',
        ),
        throwsA(
          isA<HealthDomainException>().having(
            (e) => e.code,
            'code',
            'inconsistent_cancelled_at',
          ),
        ),
      );
    });

    test('matriz de transições (independente da implementação)', () {
      const expected = <RestrictionStatus, Set<RestrictionStatus>>{
        RestrictionStatus.active: {
          RestrictionStatus.ended,
          RestrictionStatus.cancelled,
        },
        RestrictionStatus.ended: {},
        RestrictionStatus.cancelled: {},
      };
      for (final origin in RestrictionStatus.values) {
        for (final destination in RestrictionStatus.values) {
          final allowed = expected[origin]!.contains(destination);
          final reason = '${origin.wireName} → ${destination.wireName}';
          expect(
            OperationalRestrictionTransitions.canTransition(
              origin,
              destination,
            ),
            allowed,
            reason: reason,
          );
        }
      }
    });

    test('is_overdue derivado apenas quando active e expected_end vencido', () {
      final r = OperationalRestriction(
        id: 'r2',
        dogId: 'dog-1',
        level: RestrictionLevel.attention,
        category: RestrictionCategory.chronic,
        description: 'd',
        issuedAt: now,
        recordedBy: actor,
        professional: professional,
        sourceDocument: sourceDoc,
        status: RestrictionStatus.active,
        schemaVersion: 1,
        expectedEnd: now.add(const Duration(days: 1)),
      );
      expect(r.isOverdueAt(now), isFalse);
      expect(r.isOverdueAt(now.add(const Duration(days: 2))), isTrue);
    });

    test('activitiesRestricted é imutável por alias', () {
      final activities = <String>['busca'];
      final r = build(level: RestrictionLevel.partial, activities: activities);
      activities.add('faro');
      expect(r.activitiesRestricted, ['busca']);
      expect(
        () => r.activitiesRestricted.add('guarda'),
        throwsA(isA<UnsupportedError>()),
      );
    });
  });
}
