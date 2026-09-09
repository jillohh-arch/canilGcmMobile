import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:canil_gcm/features/health/data/clinical/clinical_consultation_event_parser.dart';
import 'package:canil_gcm/features/health/domain/clinical_consultation_gateway.dart';

/// Evento persistido no caminho canônico
/// `dogs/{dogId}/clinical_cases/{caseId}/clinical_events/{eventId}`.
Map<String, dynamic> _event({
  required String status,
  required String diagnosis,
  String eventType = 'consultation',
  String payloadType = 'consultation_v1',
  DateTime? occurredAt,
}) {
  return <String, dynamic>{
    'event_type': eventType,
    'status': status,
    'payload_type': payloadType,
    'payload_version': 1,
    'occurred_at': Timestamp.fromDate(
      occurredAt ?? DateTime.utc(2026, 7, 13, 14, 10),
    ),
    'recorded_by': <String, dynamic>{'name': 'Condutor 990001'},
    'content': <String, dynamic>{
      'reason': 'preventiva',
      'diagnosis': diagnosis,
    },
    'revision': 2,
    'schema_version': 1,
  };
}

/// Espelha o filtro/ordenação que o gateway aplica sobre a subcoleção do caso.
///
/// A leitura remota em si é Firestore; o que precisa de prova determinística é
/// a REGRA: somente `final`, ordenado por `occurred_at` desc, escopo por caso.
List<ClinicalConsultationRecordView> readCaseScoped({
  required String caseId,
  required Map<String, Map<String, dynamic>> events,
}) {
  final records = <ClinicalConsultationRecordView>[];
  for (final entry in events.entries) {
    final record = ClinicalConsultationEventParser.tryParse(
      caseId: caseId,
      eventId: entry.key,
      data: entry.value,
    );
    if (record != null) records.add(record);
  }
  records.sort((a, b) => b.occurredAt.compareTo(a.occurredAt));
  return records;
}

void main() {
  group('histórico por CASO (escopo V1)', () {
    test('somente consultas final aparecem como concluídas', () {
      final records = readCaseScoped(
        caseId: 'cc_a',
        events: {
          'ce_final': _event(status: 'final', diagnosis: 'Concluída'),
          'ce_draft': _event(status: 'draft', diagnosis: 'Pendente'),
          'ce_cancelled': _event(status: 'cancelled', diagnosis: 'Cancelada'),
        },
      );

      expect(records, hasLength(1));
      expect(records.single.eventId, equals('ce_final'));
      expect(records.single.diagnosis, equals('Concluída'));
    });

    test('um draft de falha parcial não é listado como concluído', () {
      final records = readCaseScoped(
        caseId: 'cc_a',
        events: {
          'ce_draft': _event(status: 'draft', diagnosis: 'Aguardando final'),
        },
      );

      expect(
        records,
        isEmpty,
        reason: 'o registro existe, mas não é uma consulta concluída',
      );
    });

    test('ordenação é occurred_at decrescente', () {
      final records = readCaseScoped(
        caseId: 'cc_a',
        events: {
          'ce_old': _event(
            status: 'final',
            diagnosis: 'Antiga',
            occurredAt: DateTime.utc(2026, 7, 10, 9),
          ),
          'ce_new': _event(
            status: 'final',
            diagnosis: 'Recente',
            occurredAt: DateTime.utc(2026, 7, 20, 9),
          ),
        },
      );

      expect(
        records.map((r) => r.eventId).toList(),
        equals(['ce_new', 'ce_old']),
      );
    });

    test('registros do caso A não vazam para o caso B', () {
      final caseA = readCaseScoped(
        caseId: 'cc_a',
        events: {'ce_1': _event(status: 'final', diagnosis: 'Do caso A')},
      );
      final caseB = readCaseScoped(
        caseId: 'cc_b',
        events: {'ce_2': _event(status: 'final', diagnosis: 'Do caso B')},
      );

      expect(caseA.single.caseId, equals('cc_a'));
      expect(caseB.single.caseId, equals('cc_b'));
      expect(caseA.single.eventId, isNot(equals(caseB.single.eventId)));
      // Cada leitura é escopada ao seu próprio caso: nenhuma agregação global.
      expect(caseA.map((r) => r.eventId), isNot(contains('ce_2')));
      expect(caseB.map((r) => r.eventId), isNot(contains('ce_1')));
    });

    test('outros tipos clínicos finais não poluem o histórico de consultas', () {
      final records = readCaseScoped(
        caseId: 'cc_a',
        events: {
          'ce_consult': _event(status: 'final', diagnosis: 'Consulta'),
          'ce_vaccine': _event(
            status: 'final',
            diagnosis: 'Vacina',
            eventType: 'vaccination',
            payloadType: 'vaccination_v1',
          ),
          'ce_note': _event(
            status: 'final',
            diagnosis: 'Nota',
            eventType: 'general_note',
            payloadType: 'general_note_v1',
          ),
        },
      );

      expect(records, hasLength(1));
      expect(records.single.eventId, equals('ce_consult'));
    });

    test('caso sem eventos devolve lista vazia, não erro', () {
      expect(readCaseScoped(caseId: 'cc_a', events: const {}), isEmpty);
    });

    test('uma consulta recém-finalizada torna-se visível', () {
      // Antes do Finalize: o evento existe em draft e não é listado.
      final before = readCaseScoped(
        caseId: 'cc_a',
        events: {'ce_1': _event(status: 'draft', diagnosis: 'Nova consulta')},
      );
      expect(before, isEmpty);

      // Depois do Finalize: o MESMO evento passa a ser listado.
      final after = readCaseScoped(
        caseId: 'cc_a',
        events: {'ce_1': _event(status: 'final', diagnosis: 'Nova consulta')},
      );
      expect(after, hasLength(1));
      expect(after.single.eventId, equals('ce_1'));
      expect(after.single.diagnosis, equals('Nova consulta'));
    });
  });
}
