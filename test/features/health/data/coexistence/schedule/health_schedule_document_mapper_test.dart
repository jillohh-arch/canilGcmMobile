import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:canil_gcm/features/health/data/coexistence/schedule/health_schedule_date_parse.dart';
import 'package:canil_gcm/features/health/data/coexistence/schedule/health_schedule_document_mapper.dart';
import 'package:canil_gcm/features/health/data/coexistence/schedule/health_schedule_integrity_exception.dart';
import 'package:canil_gcm/features/health/domain/health_v1_enums_ext.dart';
import 'package:canil_gcm/features/health/domain/health_v1_models.dart';
import 'package:canil_gcm/features/health/presentation/schedule/health_schedule_item_view.dart';
import 'package:canil_gcm/features/health/presentation/schedule/health_schedule_presentation_policy.dart';

void main() {
  Map<String, dynamic> fullDoc({
    String scheduleType = 'vaccination',
    String lifecycle = 'open',
    String sourceType = 'manual',
    Object? scheduledFor,
    Object? dueUntil,
    Object? recordedBy,
    String timezone = 'America/Sao_Paulo',
  }) {
    return {
      'schedule_type': scheduleType,
      'title': 'Vacina V10',
      'scheduled_for':
          scheduledFor ?? Timestamp.fromDate(DateTime.utc(2026, 7, 20, 12)),
      'due_until': dueUntil,
      'timezone': timezone,
      'lifecycle_status': lifecycle,
      'source_type': sourceType,
      'source_id': 'src-1',
      'case_id': 'case-1',
      'created_at': Timestamp.fromDate(DateTime.utc(2026, 7, 1)),
      'recorded_by':
          recordedBy ??
          {'uid': 'u1', 'name': 'Condutor', 'internal_role': 'condutor'},
      'notes': 'obs',
      'schema_version': 1,
      'migration_batch_id': 'batch-x',
    };
  }

  group('HealthScheduleDocumentMapper', () {
    test('documento completo mapeia campos canônicos', () {
      final data = fullDoc(
        dueUntil: Timestamp.fromDate(DateTime.utc(2026, 7, 21, 12)),
      );
      data['revision'] = 1;
      final item = HealthScheduleDocumentMapper.fromFirestore(
        dogId: 'dog-a',
        documentId: 's1',
        data: data,
      );
      expect(item.id, 's1');
      expect(item.dogId, 'dog-a');
      expect(item.scheduleType, ScheduleType.vaccination);
      expect(item.lifecycleStatus, ScheduleLifecycleStatus.open);
      expect(item.sourceType, ScheduleSourceType.manual);
      expect(item.title, 'Vacina V10');
      expect(item.timezone, 'America/Sao_Paulo');
      expect(item.dueUntil, isNotNull);
      expect(item.sourceId, 'src-1');
      expect(item.caseId, 'case-1');
      expect(item.notes, 'obs');
      expect(item.recordedBy.uid, 'u1');
      expect(item.schemaVersion, 1);
      expect(item.revision.token, '1');
    });

    test('treatment_protocol dose com due_until mapeia e valida no HealthScheduleItemView', () {
      final scheduled = DateTime.utc(2026, 9, 5, 12);
      final due = scheduled.add(const Duration(minutes: 30));
      final data = <String, dynamic>{
        'dog_id': 'stg-dog-nutrition-unlinked-001',
        'schedule_type': 'dose',
        'title': 'Dose 1: Medicação Sintética (10mg)',
        'scheduled_for': Timestamp.fromDate(scheduled),
        'due_until': Timestamp.fromDate(due),
        'timezone': 'America/Sao_Paulo',
        'lifecycle_status': 'open',
        'source_type': 'treatment_protocol',
        'source_id': 'tp_test_123',
        'case_id': 'cc_test_123',
        'created_at': Timestamp.fromDate(DateTime.utc(2026, 9, 5, 11)),
        'recorded_by': 'system',
        'revision': 1,
        'schema_version': 1,
        'planned_dose_id': 'dose_1',
        'is_paused': false,
      };

      final item = HealthScheduleDocumentMapper.fromFirestore(
        dogId: 'stg-dog-nutrition-unlinked-001',
        documentId: 'sch_dose_001',
        data: data,
      );

      expect(item.id, 'sch_dose_001');
      expect(item.scheduleType, ScheduleType.dose);
      expect(item.sourceType, ScheduleSourceType.treatmentProtocol);
      expect(item.dueUntil, due);
      expect(item.isPaused, isFalse);

      // Validação de apresentação na Agenda: sem due_until causaria StateError('incomplete_schedule_temporal_config')
      final view = HealthScheduleItemView.fromDomain(
        item,
        policy: healthSchedulePresentationPolicy(),
        now: scheduled.subtract(const Duration(minutes: 10)),
      );
      expect(view.temporalStatus, HealthScheduleTemporalStatus.today);

      // Quando ultrapassa o due_until, torna-se overdue sem estourar StateError
      final viewOverdue = HealthScheduleItemView.fromDomain(
        item,
        policy: healthSchedulePresentationPolicy(),
        now: due.add(const Duration(minutes: 5)),
      );
      expect(viewOverdue.temporalStatus, HealthScheduleTemporalStatus.overdue);

      // Se pausado, temporalStatus permanece scheduled mesmo após o vencimento
      final itemPausado = HealthScheduleDocumentMapper.fromFirestore(
        dogId: 'stg-dog-nutrition-unlinked-001',
        documentId: 'sch_dose_paused',
        data: Map<String, dynamic>.from(data)..['is_paused'] = true,
      );
      expect(itemPausado.isPaused, isTrue);
      final viewPausado = HealthScheduleItemView.fromDomain(
        itemPausado,
        policy: healthSchedulePresentationPolicy(),
        now: due.add(const Duration(minutes: 5)),
      );
      expect(viewPausado.temporalStatus, HealthScheduleTemporalStatus.scheduled);

      // Verificação fail-fast de regressão: dose sem due_until DEVE lançar exceção na camada de apresentação
      final dataSemDueUntil = Map<String, dynamic>.from(data)..remove('due_until');
      final itemSemDueUntil = HealthScheduleDocumentMapper.fromFirestore(
        dogId: 'stg-dog-nutrition-unlinked-001',
        documentId: 'sch_dose_sem_due',
        data: dataSemDueUntil,
      );
      expect(
        () => HealthScheduleItemView.fromDomain(
          itemSemDueUntil,
          policy: healthSchedulePresentationPolicy(),
          now: scheduled,
        ),
        throwsA(
          isA<HealthDomainException>().having(
            (e) => e.code,
            'code',
            'incomplete_schedule_temporal_config',
          ),
        ),
      );
    });

    test('revision = 1 e revision > 1', () {
      final d1 = fullDoc()..['revision'] = 1;
      final d2 = fullDoc()..['revision'] = 7;
      expect(
        HealthScheduleDocumentMapper.fromFirestore(
          dogId: 'dog-a',
          documentId: 'r1',
          data: d1,
        ).revision.token,
        '1',
      );
      expect(
        HealthScheduleDocumentMapper.fromFirestore(
          dogId: 'dog-a',
          documentId: 'r2',
          data: d2,
        ).revision.token,
        '7',
      );
    });

    test('revision ausente → legado 0', () {
      final data = fullDoc();
      data.remove('revision');
      final item = HealthScheduleDocumentMapper.fromFirestore(
        dogId: 'dog-a',
        documentId: 'legacy',
        data: data,
      );
      expect(item.revision.token, '0');
    });

    test('revision inválida → integrity', () {
      expect(
        () => HealthScheduleDocumentMapper.fromFirestore(
          dogId: 'dog-a',
          documentId: 'bad-rev',
          data: fullDoc()..['revision'] = true,
        ),
        throwsA(
          isA<HealthScheduleIntegrityException>().having(
            (e) => e.field,
            'field',
            'revision',
          ),
        ),
      );
      expect(
        () => HealthScheduleDocumentMapper.fromFirestore(
          dogId: 'dog-a',
          documentId: 'neg-rev',
          data: fullDoc()..['revision'] = -1,
        ),
        throwsA(isA<HealthScheduleIntegrityException>()),
      );
    });

    test('campos opcionais ausentes: documento open válido', () {
      final data = fullDoc();
      data.remove('due_until');
      data.remove('source_id');
      data.remove('case_id');
      data.remove('notes');
      data.remove('migration_batch_id');
      final item = HealthScheduleDocumentMapper.fromFirestore(
        dogId: 'dog-a',
        documentId: 's2',
        data: data,
      );
      expect(item.dueUntil, isNull);
      expect(item.sourceId, isNull);
      expect(item.caseId, isNull);
    });

    test('timestamp obrigatório inválido → integrity', () {
      expect(
        () => HealthScheduleDocumentMapper.fromFirestore(
          dogId: 'dog-a',
          documentId: 's3',
          data: fullDoc(scheduledFor: 'not-a-date'),
        ),
        throwsA(
          isA<HealthScheduleIntegrityException>().having(
            (e) => e.field,
            'field',
            'scheduled_for',
          ),
        ),
      );
    });

    test('enum desconhecido → integrity (sem fallback general)', () {
      expect(
        () => HealthScheduleDocumentMapper.fromFirestore(
          dogId: 'dog-a',
          documentId: 's4',
          data: fullDoc(scheduleType: 'future_type_v99'),
        ),
        throwsA(
          isA<HealthScheduleIntegrityException>().having(
            (e) => e.field,
            'field',
            'schedule_type',
          ),
        ),
      );
    });

    test('timezone inválido → integrity via domínio', () {
      expect(
        () => HealthScheduleDocumentMapper.fromFirestore(
          dogId: 'dog-a',
          documentId: 's5',
          data: fullDoc(timezone: 'Mars/Olympus'),
        ),
        throwsA(isA<HealthScheduleIntegrityException>()),
      );
    });

    test('lifecycle completed com metadados mapeia', () {
      final data = fullDoc(lifecycle: 'completed');
      data['completed_at'] = Timestamp.fromDate(DateTime.utc(2026, 7, 21));
      data['completed_by'] = {
        'uid': 'u2',
        'name': 'Vet',
        'internal_role': 'admin',
      };
      final item = HealthScheduleDocumentMapper.fromFirestore(
        dogId: 'dog-a',
        documentId: 's6',
        data: data,
      );
      expect(item.lifecycleStatus, ScheduleLifecycleStatus.completed);
      expect(item.completedAt, isNotNull);
      expect(item.completedBy?.uid, 'u2');
    });

    test('lifecycle cancelled com metadados mapeia', () {
      final data = fullDoc(lifecycle: 'cancelled');
      data['cancelled_at'] = Timestamp.fromDate(DateTime.utc(2026, 7, 21));
      data['cancelled_by'] = {
        'uid': 'u3',
        'name': 'Admin',
        'internal_role': 'admin',
      };
      data['cancel_reason'] = 'duplicado';
      final item = HealthScheduleDocumentMapper.fromFirestore(
        dogId: 'dog-a',
        documentId: 's7',
        data: data,
      );
      expect(item.lifecycleStatus, ScheduleLifecycleStatus.cancelled);
      expect(item.cancelReason, 'duplicado');
    });

    test('recorded_by system string mapeia ator de sistema', () {
      final item = HealthScheduleDocumentMapper.fromFirestore(
        dogId: 'dog-a',
        documentId: 's8',
        data: fullDoc(recordedBy: 'system'),
      );
      expect(item.recordedBy.uid, 'system');
      expect(item.recordedBy.internalRole, 'system');
    });

    group('fromCollectionGroup', () {
      test('dog_id canônico aceito', () {
        final data = fullDoc()..['dog_id'] = 'dog-cg-1';
        final item = HealthScheduleDocumentMapper.fromCollectionGroup(
          documentId: 'cg-doc-1',
          data: data,
        );
        expect(item.id, 'cg-doc-1');
        expect(item.dogId, 'dog-cg-1');
      });

      test('dog_id ausente → integrity', () {
        final data = fullDoc();
        data.remove('dog_id');
        expect(
          () => HealthScheduleDocumentMapper.fromCollectionGroup(
            documentId: 'cg-doc-2',
            data: data,
          ),
          throwsA(
            isA<HealthScheduleIntegrityException>().having(
              (e) => e.field,
              'field',
              'dog_id',
            ),
          ),
        );
      });

      test('dog_id tipo inválido → integrity', () {
        final data = fullDoc()..['dog_id'] = 12345;
        expect(
          () => HealthScheduleDocumentMapper.fromCollectionGroup(
            documentId: 'cg-doc-3',
            data: data,
          ),
          throwsA(
            isA<HealthScheduleIntegrityException>().having(
              (e) => e.field,
              'field',
              'dog_id',
            ),
          ),
        );
      });

      test('dog_id string vazia → integrity', () {
        final data = fullDoc()..['dog_id'] = '   ';
        expect(
          () => HealthScheduleDocumentMapper.fromCollectionGroup(
            documentId: 'cg-doc-4',
            data: data,
          ),
          throwsA(
            isA<HealthScheduleIntegrityException>().having(
              (e) => e.field,
              'field',
              'dog_id',
            ),
          ),
        );
      });

      test('aliases dogId / caoId / k9_id NÃO substituem dog_id ausente', () {
        for (final alias in ['dogId', 'caoId', 'k9_id', 'dogID']) {
          final data = fullDoc()..[alias] = 'dog-alias-1';
          data.remove('dog_id');
          expect(
            () => HealthScheduleDocumentMapper.fromCollectionGroup(
              documentId: 'cg-doc-alias',
              data: data,
            ),
            throwsA(
              isA<HealthScheduleIntegrityException>().having(
                (e) => e.field,
                'field',
                'dog_id',
              ),
            ),
            reason: '$alias não deve substituir dog_id',
          );
        }
      });
    });
  });

  group('HealthScheduleDateParse', () {
    test('Timestamp válido', () {
      final t = Timestamp.fromDate(DateTime.utc(2026, 1, 2, 3, 4));
      expect(
        HealthScheduleDateParse.tryParse(t),
        DateTime.utc(2026, 1, 2, 3, 4),
      );
    });

    test('obrigatório ausente → null', () {
      expect(HealthScheduleDateParse.parseRequired(null), isNull);
    });

    test('tipo inválido → null', () {
      expect(HealthScheduleDateParse.tryParse(42), isNull);
    });

    test('opcional ausente → null', () {
      expect(HealthScheduleDateParse.tryParse(null), isNull);
    });
  });
}
