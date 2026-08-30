import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';

import 'package:canil_gcm/features/health/data/nutrition/health_nutrition_callable_invoker.dart';
import 'package:canil_gcm/features/health/data/nutrition/health_nutrition_callable_names.dart';
import 'package:canil_gcm/features/health/data/nutrition/health_nutrition_functions_error_mapper.dart';
import 'package:canil_gcm/features/health/data/nutrition/health_nutrition_mutation_payload_codec.dart';
import 'package:canil_gcm/features/health/domain/health_nutrition_mutation_commands.dart';
import 'package:canil_gcm/features/health/domain/health_nutrition_mutation_errors.dart';
import 'package:canil_gcm/features/health/domain/health_nutrition_mutation_gateway.dart';

/// Gateway permanente: domain command → callable Firebase → receipt tipado.
///
/// - Região: [HealthNutritionCallableNames.region]
/// - Auth: sessão Firebase Auth do SDK
/// - **Zero** [FirebaseFirestore] — somente [FirebaseFunctions]
/// - Backend é autoridade final (sem dual-write legado)
final class FirebaseFunctionsHealthNutritionMutationGateway
    implements HealthNutritionMutationGateway {
  FirebaseFunctionsHealthNutritionMutationGateway({
    FirebaseFunctions? functions,
    HealthNutritionCallableInvoker? invoker,
  }) : _functions = functions,
       _invokerOverride = invoker;

  final FirebaseFunctions? _functions;
  final HealthNutritionCallableInvoker? _invokerOverride;
  HealthNutritionCallableInvoker? _cachedInvoker;

  HealthNutritionCallableInvoker get _invoke {
    return _cachedInvoker ??=
        _invokerOverride ??
        FirebaseFunctionsHealthNutritionCallableInvoker(
          functions: _functions,
        ).call;
  }

  @override
  Future<HealthNutritionMutationResult> createPlannedMealLog(
    CreatePlannedMealLogCommand command,
  ) {
    return _runMeal(
      functionName: HealthNutritionCallableNames.createMealLog,
      payload: HealthNutritionMutationPayloadCodec.encodePlannedMeal(command),
      operationId: command.operationId,
    );
  }

  @override
  Future<HealthNutritionMutationResult> createAdhocMealLog(
    CreateAdhocMealLogCommand command,
  ) {
    return _runMeal(
      functionName: HealthNutritionCallableNames.createMealLog,
      payload: HealthNutritionMutationPayloadCodec.encodeAdhocMeal(command),
      operationId: command.operationId,
    );
  }

  @override
  Future<HealthNutritionMutationResult> createSupplementLog(
    CreateSupplementLogCommand command,
  ) {
    return _runSupplement(
      functionName: HealthNutritionCallableNames.createSupplementLog,
      payload: HealthNutritionMutationPayloadCodec.encodeSupplement(command),
      operationId: command.operationId,
    );
  }

  Future<HealthNutritionMutationResult> _runMeal({
    required String functionName,
    required Map<String, dynamic> payload,
    required String operationId,
  }) async {
    try {
      final raw = await _invoke(functionName, payload);
      return HealthNutritionMutationPayloadCodec.parseMealReceipt(
        raw,
        operationId: operationId,
      );
    } catch (e, st) {
      return _mapError(functionName, e, st);
    }
  }

  Future<HealthNutritionMutationResult> _runSupplement({
    required String functionName,
    required Map<String, dynamic> payload,
    required String operationId,
  }) async {
    try {
      final raw = await _invoke(functionName, payload);
      return HealthNutritionMutationPayloadCodec.parseSupplementReceipt(
        raw,
        operationId: operationId,
      );
    } catch (e, st) {
      return _mapError(functionName, e, st);
    }
  }

  HealthNutritionMutationErrorResult _mapError(
    String functionName,
    Object e,
    StackTrace st,
  ) {
    if (e is FirebaseFunctionsException) {
      debugPrint(
        '[FirebaseFunctionsHealthNutritionMutationGateway] '
        '$functionName FirebaseFunctionsException code=${e.code}',
      );
    } else if (e is! HealthNutritionMutationFailure) {
      debugPrint(
        '[FirebaseFunctionsHealthNutritionMutationGateway] '
        '$functionName falhou: ${e.runtimeType}',
      );
      assert(() {
        debugPrint('$st');
        return true;
      }());
    }
    return HealthNutritionMutationErrorResult(
      HealthNutritionFunctionsErrorMapper.map(e),
    );
  }
}
