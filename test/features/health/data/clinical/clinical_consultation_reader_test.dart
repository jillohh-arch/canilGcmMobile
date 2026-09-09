import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:canil_gcm/features/health/data/clinical/clinical_consultation_event_parser.dart';

/// Documento canônico de consulta finalizada, na forma que o backend persiste.
Map<String, dynamic> _consultationDoc({
  String status = 'final',
  String eventType = 'consultation',
  String payloadType = 'consultation_v1',
}) {
  return <String, dynamic>{
    'event_type': eventType,
    'status': status,
    'payload_type': payloadType,
    'payload_version': 1,
    'occurred_at': Timestamp.fromDate(DateTime.utc(2026, 7, 13, 14, 10)),
    'recorded_at': Timestamp.fromDate(DateTime.utc(2026, 7, 13, 14, 14)),
    'recorded_by': <String, dynamic>{
      'uid': 'stg-homolog-990001',
      'name': 'Condutor K9 990001',
      'internal_role': 'condutor',
    },
    'professional': <String, dynamic>{
      'name': 'Dr. Carlos Henrique',
      'registration_type': 'CRMV',
      'registration_number': 'SP 14872',
      'clinic': 'Canil GCM Limeira',
    },
    'content': <String, dynamic>{
      'reason': 'preventiva',
      'veterinarian_name': 'Dr. Carlos Henrique',
      'clinic_or_location': 'Canil GCM Limeira',
      'body_condition': 'bom',
      'hydration': 'normal',
      'temperature_celsius': 38.5,
      'heart_rate_bpm': 88,
      'respiratory_rate_irpm': 24,
      'weight_kg': 29.8,
      'findings': 'Sem alteracoes relevantes ao exame fisico.',
      'diagnosis': 'Avaliacao preventiva sem achados significativos.',
      'operational_status': 'fully_fit',
      'conducts': <String>['nutritional_adjustment'],
    },
    'revision': 2,
    'schema_version': 1,
  };
}

void main() {
  group('ClinicalConsultationEventParser', () {
    test('consulta final e mapeada como concluida', () {
      final record = ClinicalConsultationEventParser.tryParse(
        caseId: 'cc_a',
        eventId: 'ce_1',
        data: _consultationDoc(),
      );

      expect(record, isNotNull);
      expect(record!.title, equals('Consulta Veterinária'));
      expect(record.caseId, equals('cc_a'));
      expect(record.eventId, equals('ce_1'));
      expect(record.reasonLabel, equals('Preventiva'));
      expect(record.veterinarianName, equals('Dr. Carlos Henrique'));
      expect(record.clinicOrLocation, equals('Canil GCM Limeira'));
      expect(record.findings, contains('Sem alteracoes'));
      expect(record.diagnosis, contains('Avaliacao preventiva'));
      expect(record.operationalStatusLabel, equals('Totalmente apto'));
      // `Timestamp.toDate()` devolve hora LOCAL: comparar o instante.
      expect(
        record.occurredAt.isAtSameMomentAs(DateTime.utc(2026, 7, 13, 14, 10)),
        isTrue,
      );
    });

    test('profissional externo e distinto de quem registrou', () {
      final record = ClinicalConsultationEventParser.tryParse(
        caseId: 'cc_a',
        eventId: 'ce_1',
        data: _consultationDoc(),
      )!;

      expect(record.professionalName, equals('Dr. Carlos Henrique'));
      expect(record.professionalRegistration, equals('CRMV SP 14872'));
      expect(record.recordedByName, equals('Condutor K9 990001'));
      expect(record.recordedByName, isNot(equals(record.professionalName)));
    });

    test('DRAFT nao e consulta concluida', () {
      expect(
        ClinicalConsultationEventParser.tryParse(
          caseId: 'cc_a',
          eventId: 'ce_draft',
          data: _consultationDoc(status: 'draft'),
        ),
        isNull,
        reason: 'um draft de falha parcial nao pode aparecer como concluido',
      );
    });

    test('evento cancelado nao e consulta concluida', () {
      expect(
        ClinicalConsultationEventParser.tryParse(
          caseId: 'cc_a',
          eventId: 'ce_x',
          data: _consultationDoc(status: 'cancelled'),
        ),
        isNull,
      );
    });

    test('outro event_type final nao e lido como consulta', () {
      expect(
        ClinicalConsultationEventParser.tryParse(
          caseId: 'cc_a',
          eventId: 'ce_vac',
          data: _consultationDoc(eventType: 'vaccination'),
        ),
        isNull,
      );
    });

    test('payload_type divergente e rejeitado', () {
      expect(
        ClinicalConsultationEventParser.tryParse(
          caseId: 'cc_a',
          eventId: 'ce_y',
          data: _consultationDoc(payloadType: 'observation_v1'),
        ),
        isNull,
      );
    });

    test('occurred_at ausente e rejeitado', () {
      final data = _consultationDoc()..remove('occurred_at');
      expect(
        ClinicalConsultationEventParser.tryParse(
          caseId: 'cc_a',
          eventId: 'ce_z',
          data: data,
        ),
        isNull,
      );
    });

    test('professional ausente nao impede leitura', () {
      final data = _consultationDoc()..remove('professional');
      final record = ClinicalConsultationEventParser.tryParse(
        caseId: 'cc_a',
        eventId: 'ce_1',
        data: data,
      );

      expect(record, isNotNull);
      expect(record!.professionalName, isNull);
      expect(record.professionalRegistration, isNull);
      expect(record.recordedByName, equals('Condutor K9 990001'));
    });

    test('o caseId lido e o do caso consultado, nunca inferido do doc', () {
      final a = ClinicalConsultationEventParser.tryParse(
        caseId: 'cc_a',
        eventId: 'ce_1',
        data: _consultationDoc(),
      )!;
      final b = ClinicalConsultationEventParser.tryParse(
        caseId: 'cc_b',
        eventId: 'ce_1',
        data: _consultationDoc(),
      )!;

      expect(a.caseId, equals('cc_a'));
      expect(b.caseId, equals('cc_b'));
    });

    test('conteudo bruto nao e exposto como JSON', () {
      final record = ClinicalConsultationEventParser.tryParse(
        caseId: 'cc_a',
        eventId: 'ce_1',
        data: _consultationDoc(),
      )!;

      // A projeção expõe campos tipados, não o mapa `content`.
      expect(record.findings, isNot(contains('{')));
      expect(record.diagnosis, isNot(contains('{')));
    });
  });
}
