import 'package:canil_gcm/features/health/domain/health_v1_enums_ext.dart';
import 'package:canil_gcm/features/health/domain/health_v1_models.dart';
import 'package:canil_gcm/features/health/domain/health_v1_transitions_v2.dart';
import 'package:canil_gcm/features/health/domain/health_v1_value_objects.dart';
import 'package:canil_gcm/features/health/domain/operational_restriction.dart';
import 'package:flutter_test/flutter_test.dart';

/// Transitions do OperationalRestriction.
///
/// Estas helpers NÃO são writer authority: o backend decide e persiste END e
/// CANCEL. Elas representam/validam o resultado em memória, e o que se prova
/// aqui é que nenhuma metadata terminal validada é silenciosamente descartada.
void main() {
  final actor = RecordedBy(uid: 'u1', name: 'Condutor', internalRole: 'condutor');
  final terminalActor = RecordedBy(
    uid: 'u2',
    name: 'Supervisor',
    internalRole: 'admin',
  );
  final professional = ProfessionalIdentity(
    name: 'Dra. Vet',
    registrationType: ProfessionalRegistrationType.crmv,
    registrationNumber: 'CRMV-123',
    clinic: 'Clínica Norte',
  );
  final endProfessional = ProfessionalIdentity(
    name: 'Dr. Externo',
    registrationType: ProfessionalRegistrationType.cfmv,
    registrationNumber: 'CFMV-999',
    clinic: 'Clínica Sul',
    specialty: 'ortopedia',
  );
  const sourceDoc = HealthDocumentRef(healthDocumentId: 'doc-issue');
  const endDoc = HealthDocumentRef(healthDocumentId: 'doc-end');
  final issuedAt = DateTime.utc(2026, 7, 14);
  final terminalAt = issuedAt.add(const Duration(days: 3));

  OperationalRestriction active() => OperationalRestriction(
    id: 'r1',
    dogId: 'dog-1',
    level: RestrictionLevel.partial,
    category: RestrictionCategory.injury,
    description: 'lesão em membro anterior',
    issuedAt: issuedAt,
    recordedBy: actor,
    professional: professional,
    sourceDocument: sourceDoc,
    status: RestrictionStatus.active,
    schemaVersion: 1,
    activitiesRestricted: const ['busca', 'salto'],
    expectedEnd: issuedAt.add(const Duration(days: 10)),
  );

  OperationalRestriction toEnded(OperationalRestriction from) =>
      OperationalRestrictionTransitions.transition(
        from,
        RestrictionStatus.ended,
        actualEnd: terminalAt,
        endedBy: terminalActor,
        endReason: 'alta veterinária',
        endProfessional: endProfessional,
        endSourceDocument: endDoc,
      );

  OperationalRestriction toCancelled(OperationalRestriction from) =>
      OperationalRestrictionTransitions.transition(
        from,
        RestrictionStatus.cancelled,
        cancelledAt: terminalAt,
        cancelledBy: terminalActor,
        cancelReason: 'registro duplicado',
      );

  group('gate active-only', () {
    test('matriz permite apenas active → ended/cancelled', () {
      const expected = <RestrictionStatus, Set<RestrictionStatus>>{
        RestrictionStatus.active: {
          RestrictionStatus.ended,
          RestrictionStatus.cancelled,
        },
        RestrictionStatus.ended: {},
        RestrictionStatus.cancelled: {},
      };
      for (final from in RestrictionStatus.values) {
        for (final to in RestrictionStatus.values) {
          expect(
            OperationalRestrictionTransitions.canTransition(from, to),
            expected[from]!.contains(to),
            reason: '${from.wireName} → ${to.wireName}',
          );
        }
      }
    });

    test('ended nunca reabre', () {
      final ended = toEnded(active());
      for (final to in RestrictionStatus.values) {
        expect(
          () => OperationalRestrictionTransitions.transition(ended, to),
          throwsA(isA<HealthDomainException>()),
          reason: 'ended → ${to.wireName}',
        );
      }
    });

    test('cancelled nunca reabre', () {
      final cancelled = toCancelled(active());
      for (final to in RestrictionStatus.values) {
        expect(
          () => OperationalRestrictionTransitions.transition(cancelled, to),
          throwsA(isA<HealthDomainException>()),
          reason: 'cancelled → ${to.wireName}',
        );
      }
    });
  });

  group('END preserva metadata completa', () {
    test('endProfessional e endSourceDocument sobrevivem à transição', () {
      final ended = toEnded(active());
      expect(ended.status, RestrictionStatus.ended);
      expect(ended.actualEnd, terminalAt);
      expect(ended.endedBy, terminalActor);
      expect(ended.endReason, 'alta veterinária');
      // Regressão: estes dois eram validados e depois descartados.
      expect(ended.endProfessional, endProfessional);
      expect(ended.endSourceDocument, endDoc);
    });

    test('campos materiais da emissão permanecem intactos', () {
      final from = active();
      final ended = toEnded(from);
      expect(ended.id, from.id);
      expect(ended.dogId, from.dogId);
      expect(ended.level, from.level);
      expect(ended.category, from.category);
      expect(ended.description, from.description);
      expect(ended.issuedAt, from.issuedAt);
      expect(ended.recordedBy, from.recordedBy);
      expect(ended.professional, from.professional);
      expect(ended.sourceDocument, from.sourceDocument);
      expect(ended.activitiesRestricted, from.activitiesRestricted);
      expect(ended.schemaVersion, from.schemaVersion);
    });

    test('END não produz metadata de cancelamento', () {
      final ended = toEnded(active());
      expect(ended.cancelledAt, isNull);
      expect(ended.cancelledBy, isNull);
      expect(ended.cancelReason, isNull);
    });

    test('END exige o conjunto terminal completo', () {
      final from = active();
      // Sem endProfessional.
      expect(
        () => OperationalRestrictionTransitions.transition(
          from,
          RestrictionStatus.ended,
          actualEnd: terminalAt,
          endedBy: terminalActor,
          endReason: 'alta',
          endSourceDocument: endDoc,
        ),
        throwsA(
          isA<HealthDomainException>().having(
            (e) => e.code,
            'code',
            'missing_ending_metadata',
          ),
        ),
      );
      // Sem endSourceDocument.
      expect(
        () => OperationalRestrictionTransitions.transition(
          from,
          RestrictionStatus.ended,
          actualEnd: terminalAt,
          endedBy: terminalActor,
          endReason: 'alta',
          endProfessional: endProfessional,
        ),
        throwsA(
          isA<HealthDomainException>().having(
            (e) => e.code,
            'code',
            'missing_ending_metadata',
          ),
        ),
      );
    });
  });

  group('CANCEL preserva metadata completa', () {
    test('cancelledAt/By/Reason sobrevivem à transição', () {
      final cancelled = toCancelled(active());
      expect(cancelled.status, RestrictionStatus.cancelled);
      // Regressão: estes três eram validados e depois descartados.
      expect(cancelled.cancelledAt, terminalAt);
      expect(cancelled.cancelledBy, terminalActor);
      expect(cancelled.cancelReason, 'registro duplicado');
    });

    test('CANCEL não afirma liberação clínica', () {
      final cancelled = toCancelled(active());
      expect(cancelled.actualEnd, isNull);
      expect(cancelled.endedBy, isNull);
      expect(cancelled.endReason, isNull);
      expect(cancelled.endProfessional, isNull);
      expect(cancelled.endSourceDocument, isNull);
    });

    test('CANCEL exige o conjunto terminal completo', () {
      expect(
        () => OperationalRestrictionTransitions.transition(
          active(),
          RestrictionStatus.cancelled,
          cancelledAt: terminalAt,
          cancelledBy: terminalActor,
        ),
        throwsA(
          isA<HealthDomainException>().having(
            (e) => e.code,
            'code',
            'missing_cancellation_metadata',
          ),
        ),
      );
    });
  });

  group('expectedEnd não dispara lifecycle', () {
    test('expectedEnd vencido não altera status', () {
      final from = active();
      expect(from.status, RestrictionStatus.active);
      expect(
        from.isOverdueAt(from.expectedEnd!.add(const Duration(days: 1))),
        isTrue,
      );
      // Vencido continua active: só o backend encerra.
      expect(from.status, RestrictionStatus.active);
    });

    test('expectedEnd é preservado nos dois estados terminais', () {
      final from = active();
      expect(toEnded(from).expectedEnd, from.expectedEnd);
      expect(toCancelled(from).expectedEnd, from.expectedEnd);
    });
  });
}
