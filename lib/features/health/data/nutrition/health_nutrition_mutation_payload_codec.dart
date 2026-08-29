import 'package:canil_gcm/features/health/domain/health_nutrition_mutation_commands.dart';
import 'package:canil_gcm/features/health/domain/health_nutrition_mutation_errors.dart';
import 'package:canil_gcm/features/health/domain/health_nutrition_mutation_gateway.dart';
import 'package:canil_gcm/features/health/domain/health_v1_enums.dart';

/// Serialização/deserialização wire ↔ domínio (camada data).
///
/// Wire canônico: **snake_case** (Gate 2).
/// Datas: ISO-8601 UTC.
/// Não envia campos server-owned. Não regenera operationId.
abstract final class HealthNutritionMutationPayloadCodec {
  HealthNutritionMutationPayloadCodec._();

  static const mealServerOwnedKeys = <String>{
    'period', // forbidden on planned only; adhoc sends period as client field
    'scheduled_for',
    'scheduledFor',
    'meal_occurrence_id',
    'mealOccurrenceId',
    'local_service_date',
    'localServiceDate',
    'prescription_amount_at_time',
    'prescriptionAmountAtTime',
    'recorded_by',
    'recordedBy',
    'recorded_at',
    'recordedAt',
    'schema_version',
    'schemaVersion',
    'revision',
    'create_fingerprint',
    'createFingerprint',
    'entity_semantic_fingerprint',
    'entitySemanticFingerprint',
    'receipt_id',
    'receiptId',
    'actor',
    'source',
  };

  static Map<String, dynamic> encodePlannedMeal(
    CreatePlannedMealLogCommand command,
  ) {
    final data = <String, dynamic>{
      'mode': 'planned',
      'dog_id': command.dogId,
      'plan_id': command.planId,
      'planned_meal_id': command.plannedMealId,
      'offered_grams': command.offeredGrams,
      'acceptance': command.acceptance.value!.wireName,
      'fed_at': command.fedAt.toUtc().toIso8601String(),
      'operation_id': command.operationId,
    };
    if (command.consumedGrams != null) {
      data['consumed_grams'] = command.consumedGrams;
    }
    if (command.observations != null && command.observations!.isNotEmpty) {
      data['observations'] = command.observations;
    }
    if (command.attachmentRefs.isNotEmpty) {
      data['attachment_refs'] = List<String>.from(command.attachmentRefs);
    }
    return data;
  }

  static Map<String, dynamic> encodeAdhocMeal(
    CreateAdhocMealLogCommand command,
  ) {
    final data = <String, dynamic>{
      'mode': 'adhoc',
      'dog_id': command.dogId,
      'period': command.period.value!.wireName,
      'offered_grams': command.offeredGrams,
      'acceptance': command.acceptance.value!.wireName,
      'fed_at': command.fedAt.toUtc().toIso8601String(),
      'operation_id': command.operationId,
    };
    if (command.consumedGrams != null) {
      data['consumed_grams'] = command.consumedGrams;
    }
    if (command.observations != null && command.observations!.isNotEmpty) {
      data['observations'] = command.observations;
    }
    if (command.attachmentRefs.isNotEmpty) {
      data['attachment_refs'] = List<String>.from(command.attachmentRefs);
    }
    return data;
  }

  static Map<String, dynamic> encodeSupplement(
    CreateSupplementLogCommand command,
  ) {
    final data = <String, dynamic>{
      'dog_id': command.dogId,
      'supplement_name': command.supplementName,
      'dose': command.dose,
      'unit': command.unit.value!.wireName,
      'administered_at': command.administeredAt.toUtc().toIso8601String(),
      'operation_id': command.operationId,
    };
    if (command.nutritionPlanId != null &&
        command.nutritionPlanId!.isNotEmpty) {
      data['nutrition_plan_id'] = command.nutritionPlanId;
    }
    if (command.supplementRegimenId != null &&
        command.supplementRegimenId!.isNotEmpty) {
      data['supplement_regimen_id'] = command.supplementRegimenId;
    }
    if (command.notes != null && command.notes!.isNotEmpty) {
      data['notes'] = command.notes;
    }
    if (command.batchNumber != null && command.batchNumber!.isNotEmpty) {
      data['batch_number'] = command.batchNumber;
    }
    if (command.protocolId != null && command.protocolId!.isNotEmpty) {
      data['protocol_id'] = command.protocolId;
    }
    return data;
  }

  /// Parse receipt MealLog.
  ///
  /// snake_case é o contrato canônico. Se camelCase mirror existir:
  /// - valores equivalentes → aceitar (canônico = snake)
  /// - valores contraditórios → integrity (não mascarar)
  static CreateMealLogSuccess parseMealReceipt(
    Object? raw, {
    required String operationId,
  }) {
    final map = _asMap(raw);
    final dogId = _requireStringMirror(map, 'dog_id', 'dogId');
    final mealId = _requireStringMirror(map, 'meal_id', 'mealId');
    final revision = _requireRevision(map['revision']);
    final wasNoOp = _requireBoolMirror(map, 'was_no_op', 'wasNoOp');
    final occurrence = _optionalStringMirror(
      map,
      'meal_occurrence_id',
      'mealOccurrenceId',
    );

    return CreateMealLogSuccess(
      dogId: dogId,
      mealId: mealId,
      revision: revision,
      wasNoOp: wasNoOp,
      operationId: operationId,
      mealOccurrenceId: occurrence,
    );
  }

  static CreateSupplementLogSuccess parseSupplementReceipt(
    Object? raw, {
    required String operationId,
  }) {
    final map = _asMap(raw);
    final dogId = _requireStringMirror(map, 'dog_id', 'dogId');
    final logId = _requireStringMirror(
      map,
      'supplement_log_id',
      'supplementLogId',
    );
    final revision = _requireRevision(map['revision']);
    final wasNoOp = _requireBoolMirror(map, 'was_no_op', 'wasNoOp');
    return CreateSupplementLogSuccess(
      dogId: dogId,
      supplementLogId: logId,
      revision: revision,
      wasNoOp: wasNoOp,
      operationId: operationId,
    );
  }

  static Map<String, dynamic> _asMap(Object? raw) {
    if (raw is! Map) {
      throw const HealthNutritionMutationIntegrity(
        'Resposta do callable não é um mapa estruturado.',
      );
    }
    return Map<String, dynamic>.from(raw);
  }

  /// String obrigatória com mirror opcional fail-closed.
  static String _requireStringMirror(
    Map<String, dynamic> map,
    String snakeKey,
    String camelKey,
  ) {
    final snake = _asOptionalNonEmptyString(map, snakeKey);
    final camel = _asOptionalNonEmptyString(map, camelKey);
    if (snake != null && camel != null) {
      if (snake != camel) {
        throw HealthNutritionMutationIntegrity(
          'Resposta contraditória: $snakeKey="$snake" vs $camelKey="$camel".',
        );
      }
      return snake;
    }
    if (snake != null) return snake;
    if (camel != null) return camel;
    throw HealthNutritionMutationIntegrity(
      'Campo obrigatório ausente na resposta: $snakeKey.',
    );
  }

  /// Bool com mirror opcional fail-closed.
  static bool _requireBoolMirror(
    Map<String, dynamic> map,
    String snakeKey,
    String camelKey,
  ) {
    final hasSnake = map.containsKey(snakeKey);
    final hasCamel = map.containsKey(camelKey);
    final snake = hasSnake ? map[snakeKey] : null;
    final camel = hasCamel ? map[camelKey] : null;

    if (hasSnake && hasCamel) {
      if (snake is! bool || camel is! bool) {
        throw const HealthNutritionMutationIntegrity(
          'was_no_op ausente ou inválido na resposta do callable.',
        );
      }
      if (snake != camel) {
        throw HealthNutritionMutationIntegrity(
          'Resposta contraditória: $snakeKey=$snake vs $camelKey=$camel.',
        );
      }
      return snake;
    }
    if (hasSnake) {
      if (snake is bool) return snake;
      throw const HealthNutritionMutationIntegrity(
        'was_no_op ausente ou inválido na resposta do callable.',
      );
    }
    if (hasCamel) {
      if (camel is bool) return camel;
      throw const HealthNutritionMutationIntegrity(
        'was_no_op ausente ou inválido na resposta do callable.',
      );
    }
    throw const HealthNutritionMutationIntegrity(
      'was_no_op ausente ou inválido na resposta do callable.',
    );
  }

  /// Nullable string com mirror: null e string diferente → integrity.
  static String? _optionalStringMirror(
    Map<String, dynamic> map,
    String snakeKey,
    String camelKey,
  ) {
    final hasSnake = map.containsKey(snakeKey);
    final hasCamel = map.containsKey(camelKey);
    if (!hasSnake && !hasCamel) return null;

    final snake = hasSnake ? _normalizeOptionalStringValue(map[snakeKey], snakeKey) : null;
    final camel = hasCamel ? _normalizeOptionalStringValue(map[camelKey], camelKey) : null;

    if (hasSnake && hasCamel) {
      if (snake != camel) {
        throw HealthNutritionMutationIntegrity(
          'Resposta contraditória: $snakeKey="$snake" vs $camelKey="$camel".',
        );
      }
      return snake;
    }
    return hasSnake ? snake : camel;
  }

  static String? _asOptionalNonEmptyString(
    Map<String, dynamic> map,
    String key,
  ) {
    if (!map.containsKey(key)) return null;
    final v = map[key];
    if (v is String && v.trim().isNotEmpty) return v.trim();
    return null;
  }

  static String? _normalizeOptionalStringValue(Object? v, String key) {
    if (v == null) return null;
    if (v is String) {
      final t = v.trim();
      return t.isEmpty ? null : t;
    }
    throw HealthNutritionMutationIntegrity(
      'Campo $key inválido na resposta do callable.',
    );
  }

  static int _requireRevision(Object? raw) {
    if (raw is int && raw >= 1) return raw;
    if (raw is num && raw == raw.roundToDouble() && raw >= 1) {
      return raw.toInt();
    }
    if (raw is String) {
      final n = int.tryParse(raw.trim());
      if (n != null && n >= 1) return n;
    }
    throw const HealthNutritionMutationIntegrity(
      'revision ausente ou inválida na resposta do callable.',
    );
  }
}
