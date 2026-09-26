import 'package:flutter_test/flutter_test.dart';
import 'package:canil_gcm/features/health/domain/clinical_incident_command.dart';
import 'package:canil_gcm/features/health/domain/health_v1_enums.dart';
import 'package:canil_gcm/features/health/domain/health_v1_enums_ext.dart';

void main() {
  group('IncidentCategoryWire', () {
    test('round-trips all categories', () {
      for (final cat in IncidentCategory.values) {
        expect(IncidentCategoryWire.fromWire(cat.wireValue), cat);
        expect(cat.label, isNotEmpty);
      }
    });

    test('unknown wire value maps to other', () {
      expect(IncidentCategoryWire.fromWire('unknown_xyz'), IncidentCategory.other);
    });
  });

  group('IncidentSeverityWire', () {
    test('round-trips all severities', () {
      for (final sev in IncidentSeverity.values) {
        expect(IncidentSeverityWire.fromWire(sev.wireValue), sev);
        expect(sev.label, isNotEmpty);
      }
    });

    test('unknown wire value maps to mild', () {
      expect(IncidentSeverityWire.fromWire('unknown_sev'), IncidentSeverity.mild);
    });
  });

  group('IncidentConductActionWire', () {
    test('round-trips all conduct actions', () {
      for (final act in IncidentConductAction.values) {
        expect(IncidentConductActionWire.tryFromWire(act.wireValue), act);
        expect(act.label, isNotEmpty);
      }
    });

    test('unknown returns null', () {
      expect(IncidentConductActionWire.tryFromWire('unknown_act'), isNull);
    });
  });

  group('ClinicalIncidentCommand', () {
    final now = DateTime.utc(2026, 8, 15, 10, 0);

    test('open new case command builds canonical content map', () {
      final cmd = ClinicalIncidentCommand(
        dogId: 'dog-1',
        operationId: 'op-open-1',
        finalizeOperationId: 'op-fin-1',
        occurredAt: now,
        category: IncidentCategory.trauma,
        severity: IncidentSeverity.moderate,
        description: 'Lesão na pata em treinamento',
        initialConductNotes: 'Curativo realizado',
        conductActions: {IncidentConductAction.firstAidApplied},
        hasOperationalImpact: true,
        caseTitle: 'Lesão Pata Direita',
      );

      expect(cmd.opensNewCase, isTrue);
      expect(cmd.caseId, isNull);
      expect(cmd.eventType, ClinicalEventType.incident);
      expect(cmd.payloadType, PayloadType.incidentV1);
      expect(cmd.openingType, ClinicalCaseOpeningType.incident);

      final content = cmd.buildContent();
      expect(content['category'], 'trauma');
      expect(content['severity'], 'moderate');
      expect(content['description'], 'Lesão na pata em treinamento');
      expect(content['initial_conduct'], 'Curativo realizado');
      expect(content['conduct_actions'], ['first_aid_applied']);
      expect(content['has_operational_impact'], isTrue);
    });

    test('append to existing case command preserves caseId', () {
      final cmd = ClinicalIncidentCommand(
        dogId: 'dog-1',
        caseId: 'case-abc',
        operationId: 'op-app-1',
        finalizeOperationId: 'op-fin-1',
        occurredAt: now,
        category: IncidentCategory.heatstroke,
        severity: IncidentSeverity.severe,
        description: 'Hipertermia no retorno',
      );

      expect(cmd.opensNewCase, isFalse);
      expect(cmd.caseId, 'case-abc');
      final content = cmd.buildContent();
      expect(content['category'], 'heatstroke');
      expect(content['severity'], 'severe');
      expect(content['initial_conduct'], isNull);
      expect(content['conduct_actions'], isNull);
      expect(content['has_operational_impact'], isFalse);
    });
  });
}
