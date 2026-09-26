import 'package:flutter_test/flutter_test.dart';
import 'package:canil_gcm/features/health/data/clinical/clinical_incident_error_mapper.dart';
import 'package:canil_gcm/features/health/data/clinical/clinical_incident_event_parser.dart';
import 'package:canil_gcm/features/health/data/clinical/firebase_functions_clinical_incident_gateway.dart';
import 'package:canil_gcm/features/health/domain/clinical_incident_command.dart';
import 'package:canil_gcm/features/health/domain/clinical_incident_errors.dart';
import 'package:canil_gcm/features/health/domain/clinical_incident_gateway.dart';

void main() {
  group('ClinicalIncidentErrorMapper', () {
    test('maps offline errors', () {
      final err = Exception('Client is offline: network unavailable');
      final mapped = ClinicalIncidentErrorMapper.map(err);
      expect(mapped, isA<ClinicalIncidentOffline>());
    });

    test('preserves existing ClinicalIncidentFailure', () {
      const original = ClinicalIncidentValidation(message: 'Dados inválidos');
      expect(ClinicalIncidentErrorMapper.map(original), same(original));
    });
  });

  group('ClinicalIncidentEventParser', () {
    test('parses canonical incident event document', () {
      final docData = <String, dynamic>{
        'event_type': 'incident',
        'occurred_at': '2026-08-15T10:00:00.000Z',
        'status': 'final',
        'content': {
          'category': 'trauma',
          'severity': 'moderate',
          'description': 'Corte na pata',
          'initial_conduct': 'Curativo',
        },
      };

      final parsed = ClinicalIncidentEventParser.tryParse(
        caseId: 'case-1',
        eventId: 'event-1',
        data: docData,
      );

      expect(parsed, isNotNull);
      expect(parsed!.caseId, 'case-1');
      expect(parsed.eventId, 'event-1');
      expect(parsed.category, IncidentCategory.trauma);
      expect(parsed.severity, IncidentSeverity.moderate);
      expect(parsed.description, 'Corte na pata');
      expect(parsed.initialConduct, 'Curativo');
      expect(parsed.isFinal, isTrue);
    });

    test('ignores non-incident events', () {
      final docData = <String, dynamic>{
        'event_type': 'consultation',
        'content': {'notes': 'abc'},
      };

      final parsed = ClinicalIncidentEventParser.tryParse(
        caseId: 'case-1',
        eventId: 'event-1',
        data: docData,
      );

      expect(parsed, isNull);
    });
  });

  group('FirebaseFunctionsClinicalIncidentGateway', () {
    test('saveIncident opens new case and finalizes successfully', () async {
      final calls = <String, dynamic>{};

      Future<Map<String, dynamic>> fakeInvoker(
        String name,
        Map<String, dynamic> payload,
      ) async {
        calls[name] = payload;
        if (name == 'healthOpenClinicalCase') {
          return {
            'dogId': 'dog-1',
            'caseId': 'case-new-1',
            'openingEventId': 'event-open-1',
            'wasNoOp': false,
          };
        }
        if (name == 'healthFinalizeClinicalEvent') {
          return {
            'status': 'final',
            'wasNoOp': false,
          };
        }
        throw UnimplementedError(name);
      }

      final gateway = FirebaseFunctionsClinicalIncidentGateway(
        invoker: fakeInvoker,
      );

      final cmd = ClinicalIncidentCommand(
        dogId: 'dog-1',
        operationId: 'op-create-1',
        finalizeOperationId: 'op-fin-1',
        occurredAt: DateTime.utc(2026, 8, 15, 10, 0),
        category: IncidentCategory.trauma,
        severity: IncidentSeverity.mild,
        description: 'Pequena escoriação',
      );

      final result = await gateway.saveIncident(cmd);

      expect(result, isA<IncidentOpenedCase>());
      final opened = result as IncidentOpenedCase;
      expect(opened.dogId, 'dog-1');
      expect(opened.caseId, 'case-new-1');
      expect(opened.eventId, 'event-open-1');
      expect(calls.containsKey('healthOpenClinicalCase'), isTrue);
      expect(calls.containsKey('healthFinalizeClinicalEvent'), isTrue);
    });

    test('saveIncident appends to existing case successfully', () async {
      final calls = <String, dynamic>{};

      Future<Map<String, dynamic>> fakeInvoker(
        String name,
        Map<String, dynamic> payload,
      ) async {
        calls[name] = payload;
        if (name == 'healthAppendClinicalEvent') {
          return {
            'dogId': 'dog-1',
            'caseId': 'case-exist-1',
            'eventId': 'event-app-2',
            'wasNoOp': false,
          };
        }
        if (name == 'healthFinalizeClinicalEvent') {
          return {
            'status': 'final',
            'wasNoOp': false,
          };
        }
        throw UnimplementedError(name);
      }

      final gateway = FirebaseFunctionsClinicalIncidentGateway(
        invoker: fakeInvoker,
      );

      final cmd = ClinicalIncidentCommand(
        dogId: 'dog-1',
        caseId: 'case-exist-1',
        operationId: 'op-create-2',
        finalizeOperationId: 'op-fin-2',
        occurredAt: DateTime.utc(2026, 8, 15, 10, 0),
        category: IncidentCategory.respiratory,
        severity: IncidentSeverity.moderate,
        description: 'Tosse persistente',
      );

      final result = await gateway.saveIncident(cmd);

      expect(result, isA<IncidentAppendedToCase>());
      final appended = result as IncidentAppendedToCase;
      expect(appended.dogId, 'dog-1');
      expect(appended.caseId, 'case-exist-1');
      expect(appended.eventId, 'event-app-2');
      expect(calls.containsKey('healthAppendClinicalEvent'), isTrue);
    });
  });
}
