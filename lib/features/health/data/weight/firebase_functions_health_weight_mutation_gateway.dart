import 'package:cloud_functions/cloud_functions.dart';

import 'package:canil_gcm/features/health/domain/health_weight_mutation_gateway.dart';

typedef HealthWeightCallableInvoker =
    Future<Map<String, dynamic>> Function(
      String functionName,
      Map<String, dynamic> data,
    );

abstract final class HealthWeightCallableContract {
  static const region = 'southamerica-east1';
  static const createRecord = 'healthWeightCreateRecord';
}

final class FirebaseFunctionsHealthWeightMutationGateway
    implements HealthWeightMutationGateway {
  FirebaseFunctionsHealthWeightMutationGateway({
    FirebaseFunctions? functions,
    HealthWeightCallableInvoker? invoker,
  }) : _functionsOverride = functions,
       _invokerOverride = invoker;

  final FirebaseFunctions? _functionsOverride;
  final HealthWeightCallableInvoker? _invokerOverride;
  FirebaseFunctions? _cachedFunctions;

  FirebaseFunctions get _functions => _cachedFunctions ??=
      _functionsOverride ??
      FirebaseFunctions.instanceFor(
        region: HealthWeightCallableContract.region,
      );

  Future<Map<String, dynamic>> _invoke(
    String functionName,
    Map<String, dynamic> data,
  ) async {
    final override = _invokerOverride;
    if (override != null) return override(functionName, data);
    final result = await _functions.httpsCallable(functionName).call(data);
    if (result.data is! Map) {
      throw const HealthWeightMutationFailure(
        HealthWeightMutationErrorCode.malformedResponse,
        'Resposta inválida ao registrar a pesagem.',
      );
    }
    return Map<String, dynamic>.from(result.data as Map);
  }

  @override
  Future<HealthWeightMutationReceipt> createRecord(
    CreateHealthWeightCommand command,
  ) async {
    final notes = command.notes?.trim();
    final payload = <String, dynamic>{
      'weightKg': command.weightKg,
      'measuredAt': command.measuredAt.toUtc().toIso8601String(),
      if (command.context != null) 'context': command.context!.wireValue,
      if (notes != null && notes.isNotEmpty) 'notes': notes,
    };
    final request = <String, dynamic>{
      'dogId': command.dogId,
      'operationId': command.operationId,
      'payload': payload,
    };

    try {
      final raw = await _invoke(
        HealthWeightCallableContract.createRecord,
        request,
      );
      return _parseReceipt(raw);
    } on HealthWeightMutationFailure {
      rethrow;
    } on FirebaseFunctionsException catch (error) {
      throw mapHealthWeightFunctionsError(error);
    } catch (_) {
      throw const HealthWeightMutationFailure(
        HealthWeightMutationErrorCode.internal,
        'Não foi possível registrar a pesagem.',
      );
    }
  }
}

HealthWeightMutationReceipt _parseReceipt(Map<String, dynamic> raw) {
  final dogId = raw['dogId'];
  final entityId = raw['entityId'];
  final weightKg = raw['weightKg'];
  final revision = raw['revision'];
  final wasNoOp = raw['wasNoOp'];
  if (dogId is! String ||
      dogId.trim().isEmpty ||
      entityId is! String ||
      entityId.trim().isEmpty ||
      weightKg is! num ||
      !weightKg.toDouble().isFinite ||
      revision is! int ||
      revision < 1 ||
      wasNoOp is! bool) {
    throw const HealthWeightMutationFailure(
      HealthWeightMutationErrorCode.malformedResponse,
      'Resposta inválida ao registrar a pesagem.',
    );
  }
  return HealthWeightMutationReceipt(
    dogId: dogId.trim(),
    entityId: entityId.trim(),
    weightKg: weightKg.toDouble(),
    revision: revision,
    wasNoOp: wasNoOp,
  );
}

HealthWeightMutationFailure mapHealthWeightFunctionsError(
  FirebaseFunctionsException error,
) {
  final code = error.code.trim().toLowerCase();
  return switch (code) {
    'unauthenticated' => const HealthWeightMutationFailure(
      HealthWeightMutationErrorCode.unauthenticated,
      'Sua sessão expirou. Entre novamente para registrar a pesagem.',
    ),
    'permission-denied' => const HealthWeightMutationFailure(
      HealthWeightMutationErrorCode.permissionDenied,
      'Seu perfil não possui a permissão health.record_routine.',
    ),
    'invalid-argument' => const HealthWeightMutationFailure(
      HealthWeightMutationErrorCode.invalidArgument,
      'Confira o peso e os demais dados informados.',
    ),
    'not-found' => const HealthWeightMutationFailure(
      HealthWeightMutationErrorCode.notFound,
      'O K9 informado não foi encontrado.',
    ),
    'failed-precondition' => const HealthWeightMutationFailure(
      HealthWeightMutationErrorCode.failedPrecondition,
      'A tentativa conflita com uma operação anterior. Revise os dados.',
    ),
    'unavailable' => const HealthWeightMutationFailure(
      HealthWeightMutationErrorCode.unavailable,
      'Serviço temporariamente indisponível. Tente novamente.',
    ),
    'deadline-exceeded' => const HealthWeightMutationFailure(
      HealthWeightMutationErrorCode.deadlineExceeded,
      'A confirmação demorou mais que o esperado. Tente novamente.',
    ),
    _ => const HealthWeightMutationFailure(
      HealthWeightMutationErrorCode.internal,
      'Não foi possível registrar a pesagem.',
    ),
  };
}
