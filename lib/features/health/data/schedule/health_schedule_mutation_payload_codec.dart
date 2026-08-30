import 'package:canil_gcm/features/health/domain/health_schedule_mutation_commands.dart';
import 'package:canil_gcm/features/health/domain/health_schedule_mutation_errors.dart';
import 'package:canil_gcm/features/health/domain/health_schedule_revision.dart';
import 'package:canil_gcm/features/health/domain/health_v1_enums_ext.dart';

/// Serialização/deserialização wire ↔ domínio (somente camada data).
///
/// Não envia campos server-owned. Não regenera operationId/idempotencyKey.
abstract final class HealthScheduleMutationPayloadCodec {
  HealthScheduleMutationPayloadCodec._();

  /// Campos proibidos no create (servidor é autoridade).
  static const createServerOwnedKeys = <String>{
    'source_type',
    'sourceType',
    'source_id',
    'sourceId',
    'case_id',
    'caseId',
    'lifecycle_status',
    'lifecycleStatus',
    'recorded_by',
    'recordedBy',
    'completed_at',
    'completedAt',
    'completed_by',
    'completedBy',
    'cancelled_at',
    'cancelledAt',
    'cancelled_by',
    'cancelledBy',
    'created_at',
    'createdAt',
    'schema_version',
    'schemaVersion',
    'revision',
    'actor',
    'actor_uid',
    'actorUid',
  };

  static Map<String, dynamic> encodeCreateManual(
    CreateManualScheduleItemCommand command,
  ) {
    final data = <String, dynamic>{
      'dogId': command.dogId,
      'scheduleType': command.scheduleType.wireName,
      'title': command.title,
      'scheduledFor': command.scheduledFor.toUtc().toIso8601String(),
      'timezone': command.timezone,
      'idempotencyKey': command.idempotencyKey,
    };
    if (command.dueUntil != null) {
      data['dueUntil'] = command.dueUntil!.toUtc().toIso8601String();
    }
    if (command.notes != null) {
      data['notes'] = command.notes;
    }
    // caseId / clientGeneratedId: não enviados — backend rejeita injection e
    // gera scheduleId determinístico a partir da idempotency key.
    return data;
  }

  static Map<String, dynamic> encodeUpdateOpen(
    UpdateOpenScheduleItemCommand command,
  ) {
    final expected = requireWireRevision(command.expectedRevision);
    final patch = <String, dynamic>{};
    if (command.title != null) {
      patch['title'] = command.title;
    }
    if (command.scheduledFor != null) {
      patch['scheduledFor'] = command.scheduledFor!.toUtc().toIso8601String();
    }
    if (command.clearDueUntil) {
      patch['clearDueUntil'] = true;
    } else if (command.dueUntil != null) {
      patch['dueUntil'] = command.dueUntil!.toUtc().toIso8601String();
    }
    if (command.timezone != null) {
      patch['timezone'] = command.timezone;
    }
    if (command.clearNotes) {
      patch['clearNotes'] = true;
    } else if (command.notes != null) {
      patch['notes'] = command.notes;
    }

    return <String, dynamic>{
      'dogId': command.dogId,
      'scheduleId': command.scheduleId,
      'expectedRevision': expected,
      'operationId': command.operationId,
      'patch': patch,
    };
  }

  static Map<String, dynamic> encodeComplete(
    CompleteScheduleItemCommand command,
  ) {
    final data = <String, dynamic>{
      'dogId': command.dogId,
      'scheduleId': command.scheduleId,
    };
    if (command.operationId != null) {
      data['operationId'] = command.operationId;
    }
    return data;
  }

  static Map<String, dynamic> encodeCancel(CancelScheduleItemCommand command) {
    return <String, dynamic>{
      'dogId': command.dogId,
      'scheduleId': command.scheduleId,
      'operationId': command.operationId,
      'cancelReason': command.cancelReason,
    };
  }

  /// Converte token opaco → inteiro wire. Falha tipada se inválido.
  static int requireWireRevision(HealthScheduleRevision revision) {
    final n = revision.tryAsNonNegativeInt();
    if (n == null) {
      throw const HealthScheduleMutationValidation(
        'expectedRevision inválida para o contrato backend (exige inteiro ≥ 0).',
      );
    }
    return n;
  }

  /// Parse do receipt canônico dos quatro callables.
  static ({
    String dogId,
    String scheduleId,
    HealthScheduleRevision revision,
    bool wasNoOp,
    ScheduleLifecycleStatus lifecycleStatus,
  })
  parseReceipt(Object? raw) {
    if (raw is! Map) {
      throw const HealthScheduleMutationIntegrity(
        'Resposta do callable não é um mapa estruturado.',
      );
    }
    final map = Map<String, dynamic>.from(raw);

    final dogId = _requireString(map, const ['dogId', 'dog_id']);
    final scheduleId = _requireString(map, const ['scheduleId', 'schedule_id']);
    final revision = _requireRevision(map['revision']);
    final wasNoOp = _requireBool(map['wasNoOp'] ?? map['was_no_op']);
    final lifecycleRaw =
        map['lifecycleStatus'] ?? map['lifecycle_status'] ?? map['lifecycle'];
    final lifecycleParsed = ScheduleLifecycleStatus.parse(lifecycleRaw);
    if (!lifecycleParsed.isKnown || lifecycleParsed.value == null) {
      throw const HealthScheduleMutationIntegrity(
        'lifecycleStatus ausente ou desconhecido na resposta do callable.',
      );
    }

    return (
      dogId: dogId,
      scheduleId: scheduleId,
      revision: revision,
      wasNoOp: wasNoOp,
      lifecycleStatus: lifecycleParsed.value!,
    );
  }

  static String _requireString(Map<String, dynamic> map, List<String> keys) {
    for (final key in keys) {
      final v = map[key];
      if (v is String && v.trim().isNotEmpty) return v.trim();
    }
    throw HealthScheduleMutationIntegrity(
      'Campo obrigatório ausente na resposta: ${keys.first}.',
    );
  }

  static bool _requireBool(Object? raw) {
    if (raw is bool) return raw;
    throw const HealthScheduleMutationIntegrity(
      'wasNoOp ausente ou inválido na resposta do callable.',
    );
  }

  static HealthScheduleRevision _requireRevision(Object? raw) {
    if (raw is int && raw >= 0) {
      return HealthScheduleRevision.numeric(raw);
    }
    if (raw is num && raw == raw.roundToDouble() && raw >= 0) {
      return HealthScheduleRevision.numeric(raw.toInt());
    }
    if (raw is String) {
      final n = int.tryParse(raw.trim());
      if (n != null && n >= 0) {
        return HealthScheduleRevision.numeric(n);
      }
    }
    throw const HealthScheduleMutationIntegrity(
      'revision ausente ou inválida na resposta do callable.',
    );
  }
}
