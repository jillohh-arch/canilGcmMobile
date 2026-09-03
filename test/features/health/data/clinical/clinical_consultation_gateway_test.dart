import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:canil_gcm/features/health/data/clinical/clinical_consultation_callable_names.dart';
import 'package:canil_gcm/features/health/data/clinical/clinical_consultation_operation_ids.dart';
import 'package:canil_gcm/features/health/data/clinical/firebase_functions_clinical_consultation_gateway.dart';
import 'package:canil_gcm/features/health/domain/clinical_consultation_command.dart';
import 'package:canil_gcm/features/health/domain/clinical_consultation_errors.dart';
import 'package:canil_gcm/features/health/domain/clinical_consultation_gateway.dart';

typedef _Call = ({String name, Map<String, dynamic> data});

const _dogId = 'stg-dog-1';
const _caseId = 'cc_existing_case';
const _createOp = 'consult_create_1_abcdefgh';
const _finalizeOp = 'consult_final_1_abcdefgh';

ConsultationCommand _command({String? caseId}) {
  return ConsultationCommand(
    dogId: _dogId,
    operationId: _createOp,
    finalizeOperationId: _finalizeOp,
    occurredAt: DateTime.utc(2026, 7, 13, 14, 10),
    reason: ConsultationReason.preventiva,
    vitals: const ConsultationVitals(
      bodyCondition: ConsultationBodyCondition.bom,
      hydration: ConsultationHydration.normal,
      temperatureCelsius: 38.5,
      heartRateBpm: 88,
      respiratoryRateIrpm: 24,
      weightKg: 29.8,
    ),
    conducts: const {ConsultationConduct.ajusteNutricional},
    caseId: caseId,
    veterinarianName: 'Dr. Carlos Henrique',
    clinicOrLocation: 'Canil GCM Limeira',
    findings: 'Sem alteracoes relevantes ao exame fisico.',
    diagnosis: 'Avaliacao preventiva sem achados significativos.',
    operationalStatus: ConsultationOperationalStatus.totalmenteApto,
    professional: const ConsultationProfessional(
      name: 'Dr. Carlos Henrique',
      registrationType: 'CRMV',
      registrationNumber: 'SP 14872',
      clinic: 'Canil GCM Limeira',
    ),
  );
}

void main() {
  late List<_Call> calls;
  late Map<String, Object?>? Function(String name) responder;
  late Object? Function(String name) thrower;

  setUp(() {
    calls = <_Call>[];
    responder = (_) => null;
    thrower = (_) => null;
  });

  FirebaseFunctionsClinicalConsultationGateway gateway() {
    return FirebaseFunctionsClinicalConsultationGateway(
      invoker: (name, data) async {
        calls.add((name: name, data: Map<String, dynamic>.from(data)));
        final error = thrower(name);
        if (error != null) throw error;
        return Map<String, dynamic>.from(responder(name) ?? const {});
      },
    );
  }

  List<String> names() => calls.map((c) => c.name).toList();

  Map<String, dynamic> callTo(String name) =>
      calls.firstWhere((c) => c.name == name).data;

  group('existing case — Append then Finalize', () {
    setUp(() {
      responder = (name) => switch (name) {
        ClinicalConsultationCallableNames.appendClinicalEvent => {
          'dogId': _dogId,
          'caseId': _caseId,
          'eventId': 'ce_new_event',
          'wasNoOp': false,
        },
        ClinicalConsultationCallableNames.finalizeClinicalEvent => {
          'dogId': _dogId,
          'caseId': _caseId,
          'eventId': 'ce_new_event',
          'status': 'final',
          'revision': 2,
          'wasNoOp': false,
        },
        _ => null,
      };
    });

    test('chama Append uma vez, Finalize uma vez, Open zero vezes', () async {
      final result = await gateway().saveConsultation(
        _command(caseId: _caseId),
      );

      expect(
        names(),
        equals([
          ClinicalConsultationCallableNames.appendClinicalEvent,
          ClinicalConsultationCallableNames.finalizeClinicalEvent,
        ]),
      );
      expect(
        names().where(
          (n) => n == ClinicalConsultationCallableNames.openClinicalCase,
        ),
        isEmpty,
      );
      expect(result, isA<ConsultationAppendedToCase>());
    });

    test('Finalize alveja o MESMO evento criado, com expectedRevision 1',
        () async {
      await gateway().saveConsultation(_command(caseId: _caseId));

      final finalize = callTo(
        ClinicalConsultationCallableNames.finalizeClinicalEvent,
      );
      expect(finalize['eventId'], equals('ce_new_event'));
      expect(finalize['caseId'], equals(_caseId));
      expect(finalize['expectedRevision'], equals(1));
      expect(finalize['operationId'], equals(_finalizeOp));
    });

    test('Append envia consultation / consultation_v1 e NAO envia status',
        () async {
      await gateway().saveConsultation(_command(caseId: _caseId));

      final append = callTo(
        ClinicalConsultationCallableNames.appendClinicalEvent,
      );
      expect(append['eventType'], equals('consultation'));
      expect(append['payloadType'], equals('consultation_v1'));
      expect(append['operationId'], equals(_createOp));
      // `status` e server-managed: enviar seria rejeitado pelo backend.
      expect(append.containsKey('status'), isFalse);
      // attachments deferidos nesta entrega.
      expect(append.containsKey('attachmentRefs'), isFalse);
    });

    test('professional mapeado separado de recorded_by', () async {
      await gateway().saveConsultation(_command(caseId: _caseId));

      final append = callTo(
        ClinicalConsultationCallableNames.appendClinicalEvent,
      );
      final professional = append['professional'] as Map<String, dynamic>;
      expect(professional['name'], equals('Dr. Carlos Henrique'));
      expect(professional['registration_type'], equals('CRMV'));
      expect(professional['registration_number'], equals('SP 14872'));
      // O cliente nunca envia recorded_by: o servidor o deriva do caller.
      expect(append.containsKey('recorded_by'), isFalse);
      expect(append.containsKey('recordedBy'), isFalse);
    });

    test('content carrega avaliacao clinica e conclusao operacional', () async {
      await gateway().saveConsultation(_command(caseId: _caseId));

      final append = callTo(
        ClinicalConsultationCallableNames.appendClinicalEvent,
      );
      final content = append['content'] as Map<String, dynamic>;
      expect(content['reason'], equals('preventiva'));
      expect(content['body_condition'], equals('bom'));
      expect(content['hydration'], equals('normal'));
      expect(content['temperature_celsius'], equals(38.5));
      expect(content['heart_rate_bpm'], equals(88));
      expect(content['respiratory_rate_irpm'], equals(24));
      expect(content['weight_kg'], equals(29.8));
      expect(content['operational_status'], equals('fully_fit'));
      expect(content['conducts'], equals(['nutritional_adjustment']));
    });
  });

  group('novo caso — Open apenas, depois Finalize', () {
    setUp(() {
      responder = (name) => switch (name) {
        ClinicalConsultationCallableNames.openClinicalCase => {
          'dogId': _dogId,
          'caseId': 'cc_opened',
          'openingEventId': 'ce_opening',
          'wasNoOp': false,
        },
        ClinicalConsultationCallableNames.finalizeClinicalEvent => {
          'dogId': _dogId,
          'caseId': 'cc_opened',
          'eventId': 'ce_opening',
          'status': 'final',
          'revision': 2,
          'wasNoOp': false,
        },
        _ => null,
      };
    });

    test('Open uma vez, Append ZERO vezes, Finalize no opening event',
        () async {
      final result = await gateway().saveConsultation(_command());

      expect(
        names(),
        equals([
          ClinicalConsultationCallableNames.openClinicalCase,
          ClinicalConsultationCallableNames.finalizeClinicalEvent,
        ]),
      );
      expect(
        names().where(
          (n) => n == ClinicalConsultationCallableNames.appendClinicalEvent,
        ),
        isEmpty,
        reason: 'Append apos Open duplicaria a consulta',
      );
      final finalize = callTo(
        ClinicalConsultationCallableNames.finalizeClinicalEvent,
      );
      expect(finalize['eventId'], equals('ce_opening'));
      expect(result, isA<ConsultationOpenedCase>());
    });

    test('Open envia openingType consultation e um title nao vazio', () async {
      await gateway().saveConsultation(_command());

      final open = callTo(ClinicalConsultationCallableNames.openClinicalCase);
      expect(open['openingType'], equals('consultation'));
      expect(open['eventType'], equals('consultation'));
      expect((open['title'] as String).trim(), isNotEmpty);
    });
  });

  group('falha parcial — create OK, Finalize falha', () {
    setUp(() {
      responder = (name) => switch (name) {
        ClinicalConsultationCallableNames.appendClinicalEvent => {
          'dogId': _dogId,
          'caseId': _caseId,
          'eventId': 'ce_draft',
          'wasNoOp': false,
        },
        _ => null,
      };
      thrower = (name) =>
          name == ClinicalConsultationCallableNames.finalizeClinicalEvent
          ? FirebaseFunctionsException(
              code: 'unavailable',
              message: 'rede indisponivel',
            )
          : null;
    });

    test('NAO devolve sucesso e preserva a identidade do evento', () async {
      final result = await gateway().saveConsultation(
        _command(caseId: _caseId),
      );

      expect(result, isA<ConsultationPendingFinalization>());
      expect(result, isNot(isA<ConsultationAppendedToCase>()));
      expect(result, isNot(isA<ConsultationOpenedCase>()));

      final pending = result as ConsultationPendingFinalization;
      expect(pending.eventId, equals('ce_draft'));
      expect(pending.caseId, equals(_caseId));
      expect(pending.finalizeOperationId, equals(_finalizeOp));
      expect(pending.expectedRevision, equals(1));
      expect(pending.failure, isA<ClinicalConsultationUnavailable>());
    });

    test('retry finaliza o MESMO evento, sem segundo create', () async {
      final first = await gateway().saveConsultation(_command(caseId: _caseId));
      final pending = first as ConsultationPendingFinalization;

      // Agora a finalizacao passa a funcionar.
      calls.clear();
      thrower = (_) => null;
      responder = (name) =>
          name == ClinicalConsultationCallableNames.finalizeClinicalEvent
          ? {
              'dogId': _dogId,
              'caseId': _caseId,
              'eventId': 'ce_draft',
              'status': 'final',
              'revision': 2,
              'wasNoOp': false,
            }
          : null;

      final retried = await gateway().retryFinalization(pending);

      expect(retried, isA<ConsultationAppendedToCase>());
      expect(
        names(),
        equals([ClinicalConsultationCallableNames.finalizeClinicalEvent]),
        reason: 'retry nao pode recriar a consulta',
      );
      final finalize = callTo(
        ClinicalConsultationCallableNames.finalizeClinicalEvent,
      );
      expect(finalize['eventId'], equals('ce_draft'));
      expect(finalize['operationId'], equals(_finalizeOp));
    });

    test('status diferente de final nao e sucesso', () async {
      thrower = (_) => null;
      responder = (name) => switch (name) {
        ClinicalConsultationCallableNames.appendClinicalEvent => {
          'caseId': _caseId,
          'eventId': 'ce_draft',
          'wasNoOp': false,
        },
        ClinicalConsultationCallableNames.finalizeClinicalEvent => {
          'caseId': _caseId,
          'eventId': 'ce_draft',
          'status': 'draft',
          'revision': 1,
          'wasNoOp': false,
        },
        _ => null,
      };

      final result = await gateway().saveConsultation(
        _command(caseId: _caseId),
      );
      expect(result, isA<ConsultationPendingFinalization>());
    });
  });

  group('falha na criacao', () {
    test('capability ausente nao gera pendencia de finalizacao', () async {
      thrower = (name) =>
          name == ClinicalConsultationCallableNames.appendClinicalEvent
          ? FirebaseFunctionsException(
              code: 'permission-denied',
              message: 'Perfil sem permissao explicita.',
              details: const {
                'code': 'permission-denied',
                'reason': 'capability-not-granted',
                'action': 'record_clinical',
              },
            )
          : null;

      final result = await gateway().saveConsultation(
        _command(caseId: _caseId),
      );

      expect(result, isA<ConsultationSaveFailure>());
      final failure = (result as ConsultationSaveFailure).failure;
      expect(failure, isA<ClinicalConsultationNotAuthorized>());
      expect(
        (failure as ClinicalConsultationNotAuthorized).action,
        equals('record_clinical'),
      );
      expect(
        names(),
        equals([ClinicalConsultationCallableNames.appendClinicalEvent]),
        reason: 'Finalize nao deve ser tentado se o create falhou',
      );
    });

    test('escopo de K9 negado e distinguido de capability', () async {
      thrower = (_) => FirebaseFunctionsException(
        code: 'permission-denied',
        message: 'Seu perfil permite registrar dados apenas para o K9 vinculado.',
        details: const {
          'code': 'permission-denied',
          'reason': 'dog-scope-denied',
        },
      );

      final result = await gateway().saveConsultation(
        _command(caseId: _caseId),
      );
      expect(
        (result as ConsultationSaveFailure).failure,
        isA<ClinicalConsultationDogAccessDenied>(),
      );
    });
  });

  group('operation ids', () {
    test('create e finalize sao distintos e path-safe', () {
      final ids = ConsultationOperationIdFactory.forAttempt();
      expect(ids.createOperationId, isNot(equals(ids.finalizeOperationId)));
      final safe = RegExp(r'^[A-Za-z0-9][A-Za-z0-9._-]{0,127}$');
      expect(safe.hasMatch(ids.createOperationId), isTrue);
      expect(safe.hasMatch(ids.finalizeOperationId), isTrue);
      expect(ids.createOperationId.length, lessThanOrEqualTo(128));
      expect(ids.finalizeOperationId.length, lessThanOrEqualTo(128));
    });
  });
}
