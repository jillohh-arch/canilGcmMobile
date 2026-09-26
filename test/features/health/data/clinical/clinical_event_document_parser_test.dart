import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:canil_gcm/features/health/data/clinical/clinical_event_document_parser.dart';
import 'package:canil_gcm/features/health/domain/clinical_event_read_model.dart';
import 'package:canil_gcm/features/health/domain/health_v1_enums.dart';

void main() {
  group('ClinicalEventDocumentParser — ClinicalEvent', () {
    test(
      '1. Evento draft completo: parsing preserva todos os campos e enums conhecidos',
      () {
        final now = DateTime.utc(2026, 9, 6, 12, 30);
        final raw = <String, dynamic>{
          'dog_id': 'dog-01',
          'case_id': 'case-01',
          'event_id': 'evt-01',
          'entity_kind': 'clinical_event',
          'event_type': 'consultation',
          'status': 'draft',
          'occurred_at': Timestamp.fromDate(now),
          'recorded_at': Timestamp.fromDate(now),
          'updated_at': Timestamp.fromDate(now),
          'recorded_by': {
            'uid': 'user-123',
            'name': 'Dr. Silva',
            'internal_role': 'veterinario',
          },
          'payload_type': 'consultation_v1',
          'payload_version': 1,
          'schema_version': 1,
          'revision': 1,
          'content': {'reason': 'rotina', 'diagnosis': 'Saudável'},
          'attachment_refs': ['hdoc_1234567890abcdef'],
          'has_amendments': false,
          'amendment_count': 0,
        };

        final event = ClinicalEventDocumentParser.parseEvent(
          dogId: 'dog-01',
          caseId: 'case-01',
          eventId: 'evt-01',
          data: raw,
        );

        expect(event.id, 'evt-01');
        expect(event.dogId, 'dog-01');
        expect(event.caseId, 'case-01');
        expect(event.type.isKnown, isTrue);
        expect(event.type.value, ClinicalEventType.consultation);
        expect(event.status.isKnown, isTrue);
        expect(event.status.value, ClinicalEventStatus.draft);
        expect(event.isDraft, isTrue);
        expect(event.isFinal, isFalse);
        expect(event.isCancelled, isFalse);
        expect(event.occurredAt, now);
        expect(event.recordedAt, now);
        expect(event.updatedAt, now);
        expect(event.revision, 1);
        expect(event.recordedBy?.uid, 'user-123');
        expect(event.recordedBy?.name, 'Dr. Silva');
        expect(event.recordedBy?.internalRole, 'veterinario');
        expect(event.hasAmendments, isFalse);
        expect(event.amendmentCount, 0);
        expect(event.knownHasAmendments, isFalse);
        expect(event.attachmentRefs, ['hdoc_1234567890abcdef']);
        expect(event.content['diagnosis'], 'Saudável');
        expect(event.hasQualityIssues, isFalse);
      },
    );

    test('2. Evento finalizado: parse de finalized_at e revisão avançada', () {
      final occurred = DateTime.utc(2026, 9, 5, 10, 0);
      final finalized = DateTime.utc(2026, 9, 5, 10, 15);
      final raw = <String, dynamic>{
        'event_type': 'incident',
        'status': 'final',
        'occurred_at': Timestamp.fromDate(occurred),
        'recorded_at': Timestamp.fromDate(occurred),
        'finalized_at': Timestamp.fromDate(finalized),
        'updated_at': Timestamp.fromDate(finalized),
        'recorded_by': {
          'uid': 'op-1',
          'name': 'Condutor',
          'internal_role': 'operador',
        },
        'payload_type': 'incident_v1',
        'payload_version': 1,
        'schema_version': 1,
        'revision': 2,
        'content': {'description': 'Trauma leve'},
      };

      final event = ClinicalEventDocumentParser.parseEvent(
        dogId: 'dog-01',
        caseId: 'case-01',
        eventId: 'evt-final',
        data: raw,
      );

      expect(event.status.value, ClinicalEventStatus.finalised);
      expect(event.isFinal, isTrue);
      expect(event.finalizedAt, finalized);
      expect(event.revision, 2);
    });

    test(
      '3. Evento cancelado: parse completo dos metadados de cancelamento',
      () {
        final occurred = DateTime.utc(2026, 9, 5, 10, 0);
        final cancelled = DateTime.utc(2026, 9, 5, 11, 0);
        final raw = <String, dynamic>{
          'event_type': 'vaccination',
          'status': 'cancelled',
          'occurred_at': Timestamp.fromDate(occurred),
          'recorded_at': Timestamp.fromDate(occurred),
          'recorded_by': {
            'uid': 'op-1',
            'name': 'Operador',
            'internal_role': 'operador',
          },
          'cancel_reason': 'Dose duplicada por engano',
          'cancelled_at': Timestamp.fromDate(cancelled),
          'cancelled_by': {
            'uid': 'vet-02',
            'name': 'Dra. Luiza',
            'internal_role': 'veterinario',
          },
          'payload_type': 'vaccination_v1',
          'payload_version': 1,
          'schema_version': 1,
          'revision': 3,
          'content': {'vaccine': 'Raiva'},
        };

        final event = ClinicalEventDocumentParser.parseEvent(
          dogId: 'dog-01',
          caseId: 'case-01',
          eventId: 'evt-canc',
          data: raw,
        );

        expect(event.status.value, ClinicalEventStatus.cancelled);
        expect(event.isCancelled, isTrue);
        expect(event.cancelReason, 'Dose duplicada por engano');
        expect(event.cancelledAt, cancelled);
        expect(event.cancelledBy?.name, 'Dra. Luiza');
        expect(event.cancelledBy?.internalRole, 'veterinario');
        expect(event.hasQualityIssues, isFalse);
      },
    );

    test(
      '4. Invariante 7.1 UNKNOWN: ausência de has_amendments e amendment_count NÃO vira false ou 0',
      () {
        // Cenário real: Evento criado pelo ExamProcess writer NÃO contém has_amendments nem amendment_count
        final raw = <String, dynamic>{
          'entity_kind': 'clinical_event',
          'event_id': 'evt-exam-01',
          'case_id': 'case-01',
          'dog_id': 'dog-01',
          'exam_id': 'exam-99',
          'event_type': 'exam_request',
          'payload_type': 'exam_request_v1',
          'payload_version': 1,
          'status': 'final',
          'occurred_at': '2026-09-04T12:00:00.000Z',
          'recorded_at': '2026-09-04T12:00:00.000Z',
          'recorded_by': {
            'uid': 'vet-1',
            'name': 'Dra. Ana',
            'internal_role': 'veterinario',
          },
          'content': {'title': 'Hemograma'},
          'revision': 1,
          'schema_version': 1,
        };

        final event = ClinicalEventDocumentParser.parseEvent(
          dogId: 'dog-01',
          caseId: 'case-01',
          eventId: 'evt-exam-01',
          data: raw,
        );

        // PROVA INCONTROVERSA: ausência permanece null, não defaulted para false ou 0
        expect(event.hasAmendments, isNull);
        expect(event.amendmentCount, isNull);
        expect(event.knownHasAmendments, isNull);
        expect(event.examId, 'exam-99');
        expect(event.hasQualityIssues, isFalse);
      },
    );

    test(
      '5. Invariante 7.2 OCCURRED VS RECORDED: occurred_at ausente preserva UNKNOWN e não substitui por recorded_at',
      () {
        final recorded = DateTime.utc(2026, 9, 6, 8, 0);
        final raw = <String, dynamic>{
          'event_type': 'general_note',
          'status': 'final',
          'recorded_at': Timestamp.fromDate(recorded),
          // occurred_at deliberadamente ausente
          'recorded_by': {
            'uid': 'op-1',
            'name': 'Operador',
            'internal_role': 'operador',
          },
          'payload_type': 'general_note_v1',
          'payload_version': 1,
          'schema_version': 1,
          'revision': 1,
          'content': {'note': 'Observação de campo'},
        };

        final event = ClinicalEventDocumentParser.parseEvent(
          dogId: 'dog-01',
          caseId: 'case-01',
          eventId: 'evt-no-occurred',
          data: raw,
        );

        // O campo de domínio occurredAt DEVE ser nulo (não substituído por recordedAt)
        expect(event.occurredAt, isNull);
        expect(event.recordedAt, recorded);
        expect(event.hasQualityIssues, isTrue);
        expect(event.dataQualityIssues, contains('missing_occurred_at'));

        // O fallback técnico para ordenação pode usar recordedAt
        expect(event.occurredAtOrFallback, recorded);
      },
    );

    test(
      '6. Invariante 7.3 ACTOR: recorded_by.internal_role representa usuário interno, separado de professional',
      () {
        final raw = <String, dynamic>{
          'event_type': 'consultation',
          'status': 'final',
          'occurred_at': '2026-09-01T10:00:00.000Z',
          'recorded_at': '2026-09-01T10:00:00.000Z',
          'recorded_by': {
            'uid': 'escriturario-1',
            'name': 'GCM Santos',
            'internal_role': 'operador',
          },
          'professional': {
            'id': 'vet-ext-44',
            'name': 'Dr. Marcos Veterinário',
            'registration_type': 'CRMV-SP',
            'registration_number': '12345',
            'clinic': 'Hospital Veterinário Central',
          },
          'payload_type': 'consultation_v1',
          'payload_version': 1,
          'schema_version': 1,
          'revision': 1,
          'content': {},
        };

        final event = ClinicalEventDocumentParser.parseEvent(
          dogId: 'dog-01',
          caseId: 'case-01',
          eventId: 'evt-actors',
          data: raw,
        );

        expect(event.recordedBy?.name, 'GCM Santos');
        expect(event.recordedBy?.internalRole, 'operador');

        expect(event.professional?.name, 'Dr. Marcos Veterinário');
        expect(event.professional?.clinic, 'Hospital Veterinário Central');
        expect(event.professional?.formattedRegistration, 'CRMV-SP 12345');
        expect(event.professional?.rawMap['id'], 'vet-ext-44');
        expect(event.hasQualityIssues, isFalse);
      },
    );

    test(
      '7. Tolerância e segurança: enums desconhecidos preservam valor bruto sem exceção',
      () {
        final raw = <String, dynamic>{
          'event_type': 'future_event_type_v2',
          'status': 'in_review_v2',
          'occurred_at': '2026-09-01T10:00:00.000Z',
          'recorded_at': '2026-09-01T10:00:00.000Z',
          'recorded_by': {
            'uid': 'u1',
            'name': 'User',
            'internal_role': 'admin',
          },
          'payload_type': 'future_payload',
          'payload_version': 2,
          'schema_version': 2,
          'revision': 1,
          'content': {'some': 'future_data'},
        };

        final event = ClinicalEventDocumentParser.parseEvent(
          dogId: 'dog-01',
          caseId: 'case-01',
          eventId: 'evt-unknown-enum',
          data: raw,
        );

        expect(event.type.isUnknown, isTrue);
        expect(event.type.raw, 'future_event_type_v2');
        expect(event.status.isUnknown, isTrue);
        expect(event.status.raw, 'in_review_v2');
        expect(event.hasQualityIssues, isTrue);
        expect(
          event.dataQualityIssues,
          contains('unknown_event_type:future_event_type_v2'),
        );
        expect(
          event.dataQualityIssues,
          contains('unknown_event_status:in_review_v2'),
        );
      },
    );

    test(
      '8. Robustez: documento completamente vazio ou malformado não quebra o parser',
      () {
        final event = ClinicalEventDocumentParser.parseEvent(
          dogId: 'dog-01',
          caseId: 'case-01',
          eventId: 'evt-corrupt',
          data: <String, dynamic>{},
        );

        expect(event.id, 'evt-corrupt');
        expect(event.hasQualityIssues, isTrue);
        expect(event.dataQualityIssues, contains('missing_event_type'));
        expect(event.dataQualityIssues, contains('missing_event_status'));
        expect(event.dataQualityIssues, contains('missing_occurred_at'));
        expect(event.dataQualityIssues, contains('missing_recorded_at'));
      },
    );

    test(
      '9. Wire factual: attachment_refs ausente permanece null (UNKNOWN); vazio vira []; IDs de HealthDocument preservados',
      () {
        final base = <String, dynamic>{
          'event_type': 'consultation',
          'status': 'final',
          'occurred_at': '2026-09-01T10:00:00.000Z',
          'recorded_at': '2026-09-01T10:00:00.000Z',
          'recorded_by': {
            'uid': 'u1',
            'name': 'User',
            'internal_role': 'admin',
          },
          'payload_type': 'consultation_v1',
          'payload_version': 1,
          'schema_version': 1,
          'revision': 1,
          'content': {},
        };

        // 9a. Ausente no documento persistido => null (UNKNOWN)
        final eventNoAttachments = ClinicalEventDocumentParser.parseEvent(
          dogId: 'dog-01',
          caseId: 'case-01',
          eventId: 'evt-none',
          data: Map.from(base),
        );
        expect(eventNoAttachments.attachmentRefs, isNull);

        // 9b. Explicitamente vazio => []
        final eventEmptyAttachments = ClinicalEventDocumentParser.parseEvent(
          dogId: 'dog-01',
          caseId: 'case-01',
          eventId: 'evt-empty',
          data: Map.from(base)..['attachment_refs'] = <String>[],
        );
        expect(eventEmptyAttachments.attachmentRefs, isEmpty);
        expect(eventEmptyAttachments.attachmentRefs, isNotNull);

        // 9c. HealthDocument IDs
        final eventWithHdocs = ClinicalEventDocumentParser.parseEvent(
          dogId: 'dog-01',
          caseId: 'case-01',
          eventId: 'evt-hdocs',
          data: Map.from(base)..['attachment_refs'] = ['hdoc_123', 'hdoc_456'],
        );
        expect(eventWithHdocs.attachmentRefs, ['hdoc_123', 'hdoc_456']);

        // 9d. Malformado (não lista) => null com issue
        final eventBadAttachments = ClinicalEventDocumentParser.parseEvent(
          dogId: 'dog-01',
          caseId: 'case-01',
          eventId: 'evt-bad-att',
          data: Map.from(base)..['attachment_refs'] = 'not-a-list',
        );
        expect(eventBadAttachments.attachmentRefs, isNull);
        expect(
          eventBadAttachments.dataQualityIssues,
          contains('malformed_attachment_refs'),
        );
      },
    );

    test(
      '10. Wire factual: recorded_by.internal_role aceita emissões do servidor (admin, condutor) sem degradação',
      () {
        Map<String, dynamic> makeRaw(String role) => <String, dynamic>{
          'event_type': 'consultation',
          'status': 'final',
          'occurred_at': '2026-09-01T10:00:00.000Z',
          'recorded_at': '2026-09-01T10:00:00.000Z',
          'recorded_by': {
            'uid': 'u1',
            'name': 'Agente Silva',
            'internal_role': role,
          },
          'payload_type': 'consultation_v1',
          'payload_version': 1,
          'schema_version': 1,
          'revision': 1,
          'content': {},
        };

        // admin
        final evAdmin = ClinicalEventDocumentParser.parseEvent(
          dogId: 'd',
          caseId: 'c',
          eventId: 'e1',
          data: makeRaw('admin'),
        );
        expect(evAdmin.recordedBy?.internalRole, 'admin');
        expect(evAdmin.recordedBy?.isDegraded, isFalse);
        expect(evAdmin.hasQualityIssues, isFalse);

        // condutor
        final evCondutor = ClinicalEventDocumentParser.parseEvent(
          dogId: 'd',
          caseId: 'c',
          eventId: 'e2',
          data: makeRaw('condutor'),
        );
        expect(evCondutor.recordedBy?.internalRole, 'condutor');
        expect(evCondutor.recordedBy?.isDegraded, isFalse);
        expect(evCondutor.hasQualityIssues, isFalse);
      },
    );

    test(
      '11. Wire factual: professional suporta chaves do writer clínico e dados não normalizados em rawMap',
      () {
        final raw = <String, dynamic>{
          'event_type': 'consultation',
          'status': 'final',
          'occurred_at': '2026-09-01T10:00:00.000Z',
          'recorded_at': '2026-09-01T10:00:00.000Z',
          'recorded_by': {
            'uid': 'u1',
            'name': 'User',
            'internal_role': 'admin',
          },
          'professional': {
            'name': 'Dra. Vanessa',
            'registration_type': 'CRMV-RJ',
            'registration_number': '98765',
            'clinic': 'Clínica K9 Rio',
            'legacy_id': 'legacy-999',
            'specialty': 'Ortopedia',
          },
          'payload_type': 'consultation_v1',
          'payload_version': 1,
          'schema_version': 1,
          'revision': 1,
          'content': {},
        };

        final event = ClinicalEventDocumentParser.parseEvent(
          dogId: 'd',
          caseId: 'c',
          eventId: 'e',
          data: raw,
        );

        expect(event.professional?.name, 'Dra. Vanessa');
        expect(event.professional?.registrationType, 'CRMV-RJ');
        expect(event.professional?.registrationNumber, '98765');
        expect(event.professional?.clinic, 'Clínica K9 Rio');
        expect(event.professional?.formattedRegistration, 'CRMV-RJ 98765');
        expect(event.professional?.rawMap['legacy_id'], 'legacy-999');
        expect(event.professional?.rawMap['specialty'], 'Ortopedia');
        expect(event.hasQualityIssues, isFalse);
      },
    );

    test(
      '12. Wire factual: content é mapa estruturado aberto preservando chaves arbitrárias sob payload_type fechado',
      () {
        final raw = <String, dynamic>{
          'event_type': 'exam_result',
          'status': 'final',
          'occurred_at': '2026-09-01T10:00:00.000Z',
          'recorded_at': '2026-09-01T10:00:00.000Z',
          'recorded_by': {
            'uid': 'u1',
            'name': 'User',
            'internal_role': 'admin',
          },
          'payload_type': 'exam_result_v1',
          'payload_version': 1,
          'schema_version': 1,
          'revision': 1,
          'content': {
            'findings': 'Leucocitose moderada',
            'numeric_parameters': {
              'rbc': 6.8,
              'wbc': 18500,
              'platelets': 250000,
            },
            'abnormal_flags': ['wbc_high'],
            'custom_metadata': {'lab': 'LabVet Alpha', 'batch': 42},
          },
        };

        final event = ClinicalEventDocumentParser.parseEvent(
          dogId: 'd',
          caseId: 'c',
          eventId: 'e',
          data: raw,
        );

        expect(event.content['findings'], 'Leucocitose moderada');
        expect((event.content['numeric_parameters'] as Map)['rbc'], 6.8);
        expect(event.content['abnormal_flags'], ['wbc_high']);
        expect(
          (event.content['custom_metadata'] as Map)['lab'],
          'LabVet Alpha',
        );
        expect(event.hasQualityIssues, isFalse);
      },
    );

    test(
      '13. Wire factual: autoridade primária de ID é DocumentSnapshot; event_id redundante validado',
      () {
        final base = <String, dynamic>{
          'event_type': 'consultation',
          'status': 'final',
          'occurred_at': '2026-09-01T10:00:00.000Z',
          'recorded_at': '2026-09-01T10:00:00.000Z',
          'recorded_by': {
            'uid': 'u1',
            'name': 'User',
            'internal_role': 'admin',
          },
          'payload_type': 'consultation_v1',
          'payload_version': 1,
          'schema_version': 1,
          'revision': 1,
          'content': {},
        };

        // 13a. Sem event_id no documento (comum no writer clínico genérico): id é DocumentSnapshot.id, 0 issues
        final evNoDocId = ClinicalEventDocumentParser.parseEvent(
          dogId: 'dog-01',
          caseId: 'case-01',
          eventId: 'snap-id-1',
          data: Map.from(base),
        );
        expect(evNoDocId.id, 'snap-id-1');
        expect(evNoDocId.hasQualityIssues, isFalse);

        // 13b. Com event_id idêntico no documento (ExamProcess): 0 issues
        final evMatchingId = ClinicalEventDocumentParser.parseEvent(
          dogId: 'dog-01',
          caseId: 'case-01',
          eventId: 'snap-id-2',
          data: Map.from(base)..['event_id'] = 'snap-id-2',
        );
        expect(evMatchingId.id, 'snap-id-2');
        expect(evMatchingId.hasQualityIssues, isFalse);

        // 13c. Com event_id divergente no documento: autoridade permanece DocumentSnapshot.id, issue registrada
        final evMismatchId = ClinicalEventDocumentParser.parseEvent(
          dogId: 'dog-01',
          caseId: 'case-01',
          eventId: 'snap-id-3',
          data: Map.from(base)..['event_id'] = 'conflicting-id',
        );
        expect(evMismatchId.id, 'snap-id-3');
        expect(evMismatchId.hasQualityIssues, isTrue);
        expect(
          evMismatchId.dataQualityIssues,
          contains('persisted_event_id_mismatch'),
        );
      },
    );

    test(
      '14. Wire factual: finalized_at é opcional persistido; ExamProcess status final sem finalized_at NÃO gera inconformidade',
      () {
        // Evento originado por ExamProcess (emite status: "final" diretamente, sem finalized_at)
        final rawExamProcess = <String, dynamic>{
          'event_type': 'exam_result',
          'status': 'final',
          'occurred_at': '2026-09-01T10:00:00.000Z',
          'recorded_at': '2026-09-01T10:00:00.000Z',
          'recorded_by': {
            'uid': 'u1',
            'name': 'User',
            'internal_role': 'admin',
          },
          'payload_type': 'exam_result_v1',
          'payload_version': 1,
          'schema_version': 1,
          'revision': 1,
          'content': {'result': 'Negativo'},
          // finalized_at deliberadamente ausente
        };

        final event = ClinicalEventDocumentParser.parseEvent(
          dogId: 'dog-01',
          caseId: 'case-01',
          eventId: 'evt-exam-res',
          data: rawExamProcess,
        );

        expect(event.status.value, ClinicalEventStatus.finalised);
        expect(event.isFinal, isTrue);
        expect(event.finalizedAt, isNull);
        // Não deve ser considerado corrupto por não possuir finalized_at
        expect(event.hasQualityIssues, isFalse);
      },
    );
  });

  group('ClinicalEventDocumentParser — ClinicalAmendment', () {
    test('1. Emenda completa: parse de correção com motivo e autoria', () {
      final recorded = DateTime.utc(2026, 9, 6, 14, 0);
      final raw = <String, dynamic>{
        'type': 'correction',
        'reason': 'Ajuste de dosagem prescrita',
        'payload_type': 'consultation_v1',
        'payload_version': 1,
        'schema_version': 1,
        'content': {'corrected_dose': '2 comprimidos'},
        'recorded_by': {
          'uid': 'vet-01',
          'name': 'Dr. Alberto',
          'internal_role': 'veterinario',
        },
        'recorded_at': Timestamp.fromDate(recorded),
      };

      final amendment = ClinicalEventDocumentParser.parseAmendment(
        dogId: 'dog-01',
        caseId: 'case-01',
        eventId: 'evt-01',
        amendmentId: 'ca_1234567890abcdef12345678',
        data: raw,
        ordinal: 1,
      );

      expect(amendment.id, 'ca_1234567890abcdef12345678');
      expect(amendment.eventId, 'evt-01');
      expect(amendment.caseId, 'case-01');
      expect(amendment.dogId, 'dog-01');
      expect(amendment.type.isKnown, isTrue);
      expect(amendment.type.value, ClinicalAmendmentType.correction);
      expect(amendment.reason, 'Ajuste de dosagem prescrita');
      expect(amendment.recordedAt, recorded);
      expect(amendment.ordinal, 1);
      expect(amendment.recordedBy?.name, 'Dr. Alberto');
      expect(amendment.hasQualityIssues, isFalse);
    });

    test('2. Emenda adendo e complemento: tipos conhecidos', () {
      final rawAddendum = <String, dynamic>{
        'type': 'addendum',
        'reason': 'Acrescenta exame complementar',
        'content': {},
      };
      final a1 = ClinicalEventDocumentParser.parseAmendment(
        dogId: 'd',
        caseId: 'c',
        eventId: 'e',
        amendmentId: 'ca_1',
        data: rawAddendum,
      );
      expect(a1.type.value, ClinicalAmendmentType.addendum);

      final rawComplement = <String, dynamic>{
        'type': 'complement',
        'reason': 'Complemento de anamnese',
        'content': {},
      };
      final a2 = ClinicalEventDocumentParser.parseAmendment(
        dogId: 'd',
        caseId: 'c',
        eventId: 'e',
        amendmentId: 'ca_2',
        data: rawComplement,
      );
      expect(a2.type.value, ClinicalAmendmentType.complement);
    });

    test('3. Emenda com tipo desconhecido e motivo ausente', () {
      final raw = <String, dynamic>{
        'type': 'future_amendment_type',
        // reason ausente
      };

      final amendment = ClinicalEventDocumentParser.parseAmendment(
        dogId: 'd',
        caseId: 'c',
        eventId: 'e',
        amendmentId: 'ca_bad',
        data: raw,
      );

      expect(amendment.type.isUnknown, isTrue);
      expect(amendment.type.raw, 'future_amendment_type');
      expect(amendment.hasQualityIssues, isTrue);
      expect(
        amendment.dataQualityIssues,
        contains('unknown_amendment_type:future_amendment_type'),
      );
      expect(amendment.dataQualityIssues, contains('missing_amendment_reason'));
    });
  });
}
