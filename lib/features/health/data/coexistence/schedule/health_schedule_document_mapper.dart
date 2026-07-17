import 'package:canil_gcm/features/health/data/coexistence/schedule/health_schedule_date_parse.dart';
import 'package:canil_gcm/features/health/data/coexistence/schedule/health_schedule_integrity_exception.dart';
import 'package:canil_gcm/features/health/domain/health_schedule_item.dart';
import 'package:canil_gcm/features/health/domain/health_v1_enums_ext.dart';
import 'package:canil_gcm/features/health/domain/health_v1_models.dart';

/// Mapeia documento Firestore `health_schedule` → [HealthScheduleItem].
///
/// Valores desconhecidos de enum **não** viram fallback clínico: integrity.
abstract final class HealthScheduleDocumentMapper {
  HealthScheduleDocumentMapper._();

  static const collectionId = 'health_schedule';

  static HealthScheduleItem fromFirestore({
    required String dogId,
    required String documentId,
    required Map<String, dynamic> data,
  }) {
    try {
      final scheduleType = _requireEnum(
        ScheduleType.parse(data['schedule_type']),
        documentId: documentId,
        field: 'schedule_type',
      );
      final lifecycle = _requireEnum(
        ScheduleLifecycleStatus.parse(data['lifecycle_status']),
        documentId: documentId,
        field: 'lifecycle_status',
      );
      final sourceType = _requireEnum(
        ScheduleSourceType.parse(data['source_type']),
        documentId: documentId,
        field: 'source_type',
      );

      final title = (data['title']?.toString() ?? '').trim();
      if (title.isEmpty) {
        throw HealthScheduleIntegrityException(
          documentId: documentId,
          field: 'title',
          reason: 'title é obrigatório',
        );
      }

      final timezone = (data['timezone']?.toString() ?? '').trim();
      if (timezone.isEmpty) {
        throw HealthScheduleIntegrityException(
          documentId: documentId,
          field: 'timezone',
          reason: 'timezone é obrigatório',
        );
      }

      final scheduledFor = HealthScheduleDateParse.parseRequired(
        data['scheduled_for'],
      );
      if (scheduledFor == null) {
        throw HealthScheduleIntegrityException(
          documentId: documentId,
          field: 'scheduled_for',
          reason: 'scheduled_for ausente ou inválido',
        );
      }

      final createdAt = HealthScheduleDateParse.parseRequired(
        data['created_at'],
      );
      if (createdAt == null) {
        throw HealthScheduleIntegrityException(
          documentId: documentId,
          field: 'created_at',
          reason: 'created_at ausente ou inválido',
        );
      }

      final schemaRaw = data['schema_version'];
      final schemaVersion = schemaRaw is int
          ? schemaRaw
          : (schemaRaw is num ? schemaRaw.toInt() : null);
      if (schemaVersion == null || schemaVersion <= 0) {
        throw HealthScheduleIntegrityException(
          documentId: documentId,
          field: 'schema_version',
          reason: 'schema_version inválido',
        );
      }

      final recordedBy = _parseRecordedBy(
        data['recorded_by'],
        documentId: documentId,
        field: 'recorded_by',
        required: true,
      )!;

      final dueUntil = HealthScheduleDateParse.tryParse(data['due_until']);
      final completedAt = HealthScheduleDateParse.tryParse(
        data['completed_at'],
      );
      final cancelledAt = HealthScheduleDateParse.tryParse(
        data['cancelled_at'],
      );
      final completedBy = _parseRecordedBy(
        data['completed_by'],
        documentId: documentId,
        field: 'completed_by',
        required: false,
      );
      final cancelledBy = _parseRecordedBy(
        data['cancelled_by'],
        documentId: documentId,
        field: 'cancelled_by',
        required: false,
      );

      final cancelReason = data['cancel_reason']?.toString();
      final sourceId = _optionalString(data['source_id']);
      final caseId = _optionalString(data['case_id']);
      final notes = data['notes']?.toString();
      final recurrenceRule = _optionalString(data['recurrence_rule']);
      final assignedToUid = _optionalString(data['assigned_to_uid']);
      final assignedToName = _optionalString(
        data['assigned_to_name'] ??
            (data['assigned_to'] is Map
                ? (data['assigned_to'] as Map)['name']
                : null),
      );

      // migration_batch_id é canônico no schema; não entra no domínio 4A.
      return HealthScheduleItem(
        id: documentId,
        dogId: dogId,
        scheduleType: scheduleType,
        title: title,
        scheduledFor: scheduledFor,
        timezone: timezone,
        lifecycleStatus: lifecycle,
        sourceType: sourceType,
        createdAt: createdAt,
        recordedBy: recordedBy,
        schemaVersion: schemaVersion,
        dueUntil: dueUntil,
        completedAt: completedAt,
        completedBy: completedBy,
        cancelledAt: cancelledAt,
        cancelledBy: cancelledBy,
        cancelReason: cancelReason,
        sourceId: sourceId,
        caseId: caseId,
        notes: notes,
        recurrenceRule: recurrenceRule,
        assignedToUid: assignedToUid,
        assignedToName: assignedToName,
      );
    } on HealthScheduleIntegrityException {
      rethrow;
    } on HealthDomainException catch (e) {
      throw HealthScheduleIntegrityException(
        documentId: documentId,
        reason: e.message,
        field: e.code,
      );
    } catch (e) {
      throw HealthScheduleIntegrityException(
        documentId: documentId,
        reason: 'falha ao mapear documento: ${e.runtimeType}',
      );
    }
  }

  static T _requireEnum<T extends Enum>(
    ParsedHealthEnum<T> parsed, {
    required String documentId,
    required String field,
  }) {
    if (parsed.isKnown && parsed.value != null) return parsed.value as T;
    if (parsed.isAbsent) {
      throw HealthScheduleIntegrityException(
        documentId: documentId,
        field: field,
        reason: '$field ausente',
      );
    }
    throw HealthScheduleIntegrityException(
      documentId: documentId,
      field: field,
      reason: 'valor desconhecido "$field"=${parsed.raw}',
    );
  }

  static RecordedBy? _parseRecordedBy(
    Object? raw, {
    required String documentId,
    required String field,
    required bool required,
  }) {
    if (raw == null) {
      if (required) {
        throw HealthScheduleIntegrityException(
          documentId: documentId,
          field: field,
          reason: '$field é obrigatório',
        );
      }
      return null;
    }
    if (raw is String) {
      final s = raw.trim();
      if (s == 'system') {
        return RecordedBy(
          uid: 'system',
          name: 'Sistema',
          internalRole: 'system',
        );
      }
      throw HealthScheduleIntegrityException(
        documentId: documentId,
        field: field,
        reason: '$field string não reconhecida',
      );
    }
    if (raw is Map) {
      final map = Map<String, dynamic>.from(raw);
      final uid = (map['uid'] ?? map['id'] ?? '').toString().trim();
      final name = (map['name'] ?? '').toString().trim();
      final role = (map['internal_role'] ?? map['role'] ?? '')
          .toString()
          .trim();
      if (uid.isEmpty || name.isEmpty || role.isEmpty) {
        throw HealthScheduleIntegrityException(
          documentId: documentId,
          field: field,
          reason: '$field incompleto (uid/name/internal_role)',
        );
      }
      return RecordedBy(uid: uid, name: name, internalRole: role);
    }
    throw HealthScheduleIntegrityException(
      documentId: documentId,
      field: field,
      reason: '$field tipo inválido',
    );
  }

  static String? _optionalString(Object? value) {
    if (value == null) return null;
    final s = value.toString().trim();
    return s.isEmpty ? null : s;
  }
}
