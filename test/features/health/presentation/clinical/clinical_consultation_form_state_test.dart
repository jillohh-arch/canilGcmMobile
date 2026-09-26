import 'package:flutter_test/flutter_test.dart';

import 'package:canil_gcm/features/health/domain/clinical_consultation_command.dart';
import 'package:canil_gcm/features/health/domain/health_v1_enums.dart';
import 'package:canil_gcm/features/health/presentation/clinical/clinical_consultation_form_state.dart';

ConsultationFormState _validState() {
  return ConsultationFormState(
    occurredAt: DateTime.now().subtract(const Duration(hours: 1)),
  )
    ..selectedCaseId = 'cc_existing'
    ..reason = ConsultationReason.preventiva;
}

void main() {
  group('validação', () {
    test('sem destino de caso o formulário é recusado', () {
      final state = ConsultationFormState()
        ..reason = ConsultationReason.retorno;

      expect(state.hasCaseTarget, isFalse);
      expect(state.validate(), contains('caso clínico'));
    });

    test('abrir novo caso é um destino válido', () {
      final state = ConsultationFormState()
        ..openNewCase = true
        ..reason = ConsultationReason.preventiva;

      expect(state.hasCaseTarget, isTrue);
      expect(state.validate(), isNull);
    });

    test('caso existente selecionado é um destino válido', () {
      expect(_validState().validate(), isNull);
    });

    test('motivo é obrigatório', () {
      final state = ConsultationFormState()..selectedCaseId = 'cc_1';
      expect(state.validate(), contains('motivo'));
    });

    test('data/hora no futuro é recusada antes de ir ao servidor', () {
      final state = _validState()
        ..occurredAt = DateTime.now().add(const Duration(hours: 2));
      expect(state.validate(), contains('futuro'));
    });

    test('vitais inválidos são recusados', () {
      expect(
        (_validState()..temperatureCelsius = 'abc').validate(),
        contains('Temperatura'),
      );
      expect(
        (_validState()..heartRateBpm = 'x').validate(),
        contains('cardíaca'),
      );
      expect(
        (_validState()..respiratoryRateIrpm = '--').validate(),
        contains('respiratória'),
      );
      expect((_validState()..weightKg = 'kg').validate(), contains('Peso'));
    });

    test('vitais ausentes são permitidos', () {
      final state = _validState();
      expect(state.validate(), isNull);
      final command = state.toCommand(dogId: 'dog-1');
      expect(command.vitals.temperatureCelsius, isNull);
      expect(command.vitals.weightKg, isNull);
    });
  });

  group('mapeamento para o comando canônico', () {
    test('caso existente vira Append (caseId preservado)', () {
      final command = _validState().toCommand(dogId: 'dog-1');
      expect(command.caseId, equals('cc_existing'));
      expect(command.opensNewCase, isFalse);
    });

    test('abrir novo caso vira Open (caseId nulo)', () {
      final state = ConsultationFormState()
        ..openNewCase = true
        ..reason = ConsultationReason.emergencia;
      final command = state.toCommand(dogId: 'dog-1');
      expect(command.caseId, isNull);
      expect(command.opensNewCase, isTrue);
    });

    test('tipo e payload canônicos são fixos', () {
      final command = _validState().toCommand(dogId: 'dog-1');
      expect(command.eventType.wireName, equals('consultation'));
      expect(command.payloadType.wireName, equals('consultation_v1'));
      expect(command.openingType.wireName, equals('consultation'));
    });

    test('vírgula decimal é aceita nos vitais', () {
      final state = _validState()
        ..temperatureCelsius = '38,5'
        ..weightKg = '29,8';
      final command = state.toCommand(dogId: 'dog-1');
      expect(command.vitals.temperatureCelsius, equals(38.5));
      expect(command.vitals.weightKg, equals(29.8));
    });

    test('condutas são serializadas em ordem canônica', () {
      final state = _validState()
        ..conducts.addAll({
          ConsultationConduct.ajusteNutricional,
          ConsultationConduct.medicacaoPrescrita,
        });
      final content = state.toCommand(dogId: 'dog-1').buildContent();
      expect(
        content['conducts'],
        equals(['medication_prescribed', 'nutritional_adjustment']),
      );
    });

    test('conclusão operacional entra como evidência no content', () {
      final state = _validState()
        ..operationalStatus = ConsultationOperationalStatus.restrito;
      final content = state.toCommand(dogId: 'dog-1').buildContent();
      expect(content['operational_status'], equals('restricted'));
    });

    test('sem veterinário informado nenhum profissional é fabricado', () {
      final command = _validState().toCommand(dogId: 'dog-1');
      expect(
        command.professional,
        isNull,
        reason: 'não inventar ProfessionalIdentity a partir de quem digitou',
      );
    });

    test('com veterinário informado o profissional é mapeado', () {
      final state = _validState()
        ..veterinarianName = 'Dr. Carlos Henrique'
        ..professionalRegistrationType = 'CRMV'
        ..professionalRegistrationNumber = 'SP 14872'
        ..clinicOrLocation = 'Canil GCM Limeira';
      final command = state.toCommand(dogId: 'dog-1');

      expect(command.professional, isNotNull);
      final wire = command.professional!.toWire();
      expect(wire['name'], equals('Dr. Carlos Henrique'));
      expect(wire['registration_type'], equals('CRMV'));
      expect(wire['registration_number'], equals('SP 14872'));
      expect(wire['clinic'], equals('Canil GCM Limeira'));
    });

    test('campos vazios não viram chaves no content', () {
      final content = _validState().toCommand(dogId: 'dog-1').buildContent();
      expect(content.containsKey('findings'), isFalse);
      expect(content.containsKey('diagnosis'), isFalse);
      expect(content.containsKey('conduct_notes'), isFalse);
      // O motivo garante content não vazio (exigência do backend).
      expect(content['reason'], equals('preventiva'));
      expect(content, isNotEmpty);
    });
  });

  group('identidades de operação da tentativa', () {
    test('a mesma tentativa reusa os mesmos operationIds', () {
      final state = _validState();
      final first = state.toCommand(dogId: 'dog-1');
      final second = state.toCommand(dogId: 'dog-1');

      expect(second.operationId, equals(first.operationId));
      expect(
        second.finalizeOperationId,
        equals(first.finalizeOperationId),
        reason: 'um retry não pode gerar nova identidade de consulta',
      );
    });

    test('create e finalize são distintos entre si', () {
      final command = _validState().toCommand(dogId: 'dog-1');
      expect(
        command.operationId,
        isNot(equals(command.finalizeOperationId)),
        reason: 'os recibos coexistem sob operations/{operationId}',
      );
    });

    test('após sucesso a tentativa é encerrada e uma nova gera novos ids', () {
      final state = _validState();
      final first = state.toCommand(dogId: 'dog-1');
      state.completeAttempt();
      final next = state.toCommand(dogId: 'dog-1');

      expect(next.operationId, isNot(equals(first.operationId)));
    });
  });
}
