import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:canil_gcm/features/health/data/coexistence/schedule/health_schedule_date_parse.dart';
import 'package:canil_gcm/features/health/data/coexistence/schedule/health_schedule_document_mapper.dart';
import 'package:canil_gcm/features/health/data/coexistence/schedule/health_schedule_integrity_exception.dart';
import 'package:canil_gcm/features/health/domain/health_v1_enums_ext.dart';

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
      final item = HealthScheduleDocumentMapper.fromFirestore(
        dogId: 'dog-a',
        documentId: 's1',
        data: fullDoc(
          dueUntil: Timestamp.fromDate(DateTime.utc(2026, 7, 21, 12)),
        ),
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
