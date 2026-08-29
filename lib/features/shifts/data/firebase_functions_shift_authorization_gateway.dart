import 'package:cloud_functions/cloud_functions.dart';

import 'package:canil_gcm/features/shifts/domain/shift_authorization.dart';

/// HEALTH-V1-OP-AUTH — transporte da boundary autoritativa de turno.
///
/// Espelha a convenção já usada pelos gateways Health v1 (Peso/Agenda): mesma
/// região, invoker injetável para teste, e mapeamento explícito de erro.
///
/// O ponto crítico deste arquivo é o mapeamento: o backend distingue bloqueio
/// clínico de falha técnica por CÓDIGO DE APLICAÇÃO, e essa distinção precisa
/// sobreviver até a UI. Colapsar tudo em "falha ao sincronizar" reintroduziria o
/// defeito que esta vertical corrige.
typedef ShiftAuthorizationInvoker =
    Future<Map<String, dynamic>> Function(
      String functionName,
      Map<String, dynamic> data,
    );

abstract final class ShiftAuthorizationCallableContract {
  static const region = 'southamerica-east1';
  static const executeCommand = 'shiftExecuteAuthorizedCommand';
}

final class FirebaseFunctionsShiftAuthorizationGateway
    implements ShiftAuthorizationGateway {
  FirebaseFunctionsShiftAuthorizationGateway({
    FirebaseFunctions? functions,
    ShiftAuthorizationInvoker? invoker,
  }) : _functionsOverride = functions,
       _invokerOverride = invoker;

  final FirebaseFunctions? _functionsOverride;
  final ShiftAuthorizationInvoker? _invokerOverride;
  FirebaseFunctions? _cachedFunctions;

  FirebaseFunctions get _functions => _cachedFunctions ??=
      _functionsOverride ??
      FirebaseFunctions.instanceFor(
        region: ShiftAuthorizationCallableContract.region,
      );

  Future<Map<String, dynamic>> _invoke(
    String functionName,
    Map<String, dynamic> data,
  ) async {
    final override = _invokerOverride;
    if (override != null) return override(functionName, data);
    final result = await _functions.httpsCallable(functionName).call(data);
    if (result.data is! Map) {
      throw const ShiftAuthorizationFailure(
        ShiftAuthorizationFailureKind.internal,
        'Resposta inválida do servidor ao processar a operação de turno.',
      );
    }
    return Map<String, dynamic>.from(result.data as Map);
  }

  @override
  Future<ShiftAuthorizationResult> execute(
    ShiftAuthorizationCommand command,
  ) async {
    try {
      final raw = await _invoke(
        ShiftAuthorizationCallableContract.executeCommand,
        command.toPayload(),
      );
      return _parseResult(command, raw);
    } on ShiftAuthorizationFailure {
      // NUNCA cair para o writer direto antigo: uma negativa do backend é
      // decisão, não sugestão. Repassar preserva a invariante de segurança.
      rethrow;
    } on FirebaseFunctionsException catch (error) {
      throw mapShiftAuthorizationFunctionsError(error);
    } catch (_) {
      throw const ShiftAuthorizationFailure(
        ShiftAuthorizationFailureKind.internal,
        'Não foi possível concluir a operação de turno.',
      );
    }
  }
}

ShiftAuthorizationResult _parseResult(
  ShiftAuthorizationCommand command,
  Map<String, dynamic> raw,
) {
  final dogId = raw['dogId'];
  final decision = raw['decision'];
  if (dogId is! String ||
      dogId.trim().isEmpty ||
      decision is! String ||
      decision.trim().isEmpty) {
    throw const ShiftAuthorizationFailure(
      ShiftAuthorizationFailureKind.internal,
      'Resposta inválida do servidor ao processar a operação de turno.',
    );
  }

  final restrictions = _parseRestrictions(raw['restrictions']);
  final outcome = switch (decision.trim()) {
    'allowed_with_restrictions' =>
      ShiftAuthorizationOutcome.allowedWithRestrictions,
    'allowed' =>
      restrictions.isEmpty
          ? ShiftAuthorizationOutcome.allowed
          : ShiftAuthorizationOutcome.allowedWithNotice,
    // Um outcome de permissão desconhecido não pode ser presumido benigno.
    _ => throw ShiftAuthorizationFailure(
      ShiftAuthorizationFailureKind.internal,
      'Decisão de autorização não reconhecida: $decision.',
    ),
  };

  final shiftId = raw['shiftId'];
  return ShiftAuthorizationResult(
    action: command.action,
    dogId: dogId.trim(),
    outcome: outcome,
    restrictions: restrictions,
    acknowledgementRecorded: raw['acknowledgementRecorded'] == true,
    shiftId: shiftId is String && shiftId.trim().isNotEmpty
        ? shiftId.trim()
        : null,
    wasNoOp: raw['wasNoOp'] == true,
  );
}

List<ShiftRestrictionInfo> _parseRestrictions(Object? raw) {
  if (raw is! List) return const <ShiftRestrictionInfo>[];
  return raw
      .map(ShiftRestrictionInfo.tryParse)
      .whereType<ShiftRestrictionInfo>()
      .toList(growable: false);
}

/// Traduz o erro do callable para a natureza real da negativa.
///
/// O `details.code` é o código de aplicação do backend e tem precedência sobre
/// o código de transporte: é ele que separa "restrição absoluta ativa" de
/// "não consegui verificar", que chegam ambos como `failed-precondition`/
/// `unavailable` no transporte.
ShiftAuthorizationFailure mapShiftAuthorizationFunctionsError(
  FirebaseFunctionsException error,
) {
  final details = error.details;
  final detailsMap = details is Map
      ? Map<String, dynamic>.from(details)
      : const <String, dynamic>{};
  final appCode = (detailsMap['code'] as String?)?.trim().toLowerCase();
  final restrictions = _parseRestrictions(detailsMap['restrictions']);
  final pending = detailsMap['pendingAcknowledgementIds'];
  final pendingIds = pending is List
      ? pending.whereType<String>().toList(growable: false)
      : const <String>[];
  final reasonCode = (detailsMap['reasonCode'] as String?)?.trim();

  switch (appCode) {
    case 'absolute_restriction_active':
      return ShiftAuthorizationFailure(
        ShiftAuthorizationFailureKind.absoluteRestriction,
        'K9 temporariamente inapto para operação. Existe uma restrição '
        'operacional absoluta ativa. A associação ao turno não foi realizada.',
        restrictions: restrictions,
      );
    case 'partial_acknowledgement_required':
      return ShiftAuthorizationFailure(
        ShiftAuthorizationFailureKind.acknowledgementRequired,
        'K9 apto com restrições. É necessária a ciência do responsável.',
        restrictions: restrictions,
        pendingAcknowledgementIds: pendingIds,
      );
    case 'activity_restricted':
      return ShiftAuthorizationFailure(
        ShiftAuthorizationFailureKind.activityRestricted,
        'A atividade solicitada está restrita para este K9.',
        restrictions: restrictions,
      );
    case 'restrictions_unavailable':
      return ShiftAuthorizationFailure(
        ShiftAuthorizationFailureKind.restrictionsUnavailable,
        'Não foi possível verificar as restrições operacionais do K9. '
        'A operação não foi realizada.',
        reasonCode: reasonCode,
      );
    case 'invalid_state':
      return ShiftAuthorizationFailure(
        ShiftAuthorizationFailureKind.invalidState,
        error.message?.trim().isNotEmpty == true
            ? error.message!.trim()
            : 'Estado do turno incompatível com a operação.',
      );
    case 'idempotency_conflict':
      return const ShiftAuthorizationFailure(
        ShiftAuthorizationFailureKind.idempotencyConflict,
        'Esta operação conflita com uma tentativa anterior. '
        'Atualize a tela e tente novamente.',
      );
    case 'k9_not_found':
      return const ShiftAuthorizationFailure(
        ShiftAuthorizationFailureKind.notFound,
        'O K9 informado não foi encontrado.',
      );
    case 'invalid_argument':
      return const ShiftAuthorizationFailure(
        ShiftAuthorizationFailureKind.invalidArgument,
        'Dados inválidos para a operação de turno.',
      );
  }

  // Sem código de aplicação: cai para o transporte.
  return switch (error.code.trim().toLowerCase()) {
    'unauthenticated' => const ShiftAuthorizationFailure(
      ShiftAuthorizationFailureKind.unauthenticated,
      'Sessão expirada. Entre novamente para iniciar o turno.',
    ),
    'permission-denied' => const ShiftAuthorizationFailure(
      ShiftAuthorizationFailureKind.permissionDenied,
      'Seu perfil não permite esta operação com este K9.',
    ),
    'not-found' => const ShiftAuthorizationFailure(
      ShiftAuthorizationFailureKind.notFound,
      'O K9 informado não foi encontrado.',
    ),
    'invalid-argument' => const ShiftAuthorizationFailure(
      ShiftAuthorizationFailureKind.invalidArgument,
      'Dados inválidos para a operação de turno.',
    ),
    // `unavailable` sem código de aplicação é indisponibilidade de serviço —
    // legitimamente um problema de conectividade/backend.
    'unavailable' || 'deadline-exceeded' => const ShiftAuthorizationFailure(
      ShiftAuthorizationFailureKind.network,
      'Serviço temporariamente indisponível. Confira sua conexão e '
      'tente novamente.',
    ),
    'failed-precondition' => const ShiftAuthorizationFailure(
      ShiftAuthorizationFailureKind.invalidState,
      'A operação não pôde ser concluída no estado atual do turno.',
    ),
    _ => const ShiftAuthorizationFailure(
      ShiftAuthorizationFailureKind.internal,
      'Não foi possível concluir a operação de turno.',
    ),
  };
}
