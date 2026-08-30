import 'package:cloud_functions/cloud_functions.dart';

import '../../domain/health_restriction_flow_errors.dart';
import '../../domain/health_restriction_lifecycle_gateway.dart';
import 'health_restriction_flow_callable_invoker.dart';
import 'health_restriction_flow_callables.dart';
import 'health_restriction_flow_error_mapper.dart';
import 'health_restriction_flow_payload_codec.dart';

/// Gateway dos comandos terminais de OperationalRestriction (B2).
///
/// Transporte compartilhado com ISSUE — mesmo invoker, mesmo error mapper — mas
/// dois métodos de domínio explícitos. Não existe `changeStatus`: END e CANCEL
/// exigem autoridades diferentes no backend (`health.release_restriction` e
/// `health.cancel_restriction`) e significam coisas clinicamente opostas.
///
/// Não depende do agregado `OperationalRestriction`: age sobre `dogId` +
/// `restrictionId`, que é o que o backend exige.
final class FirebaseFunctionsHealthRestrictionLifecycleGateway
    implements HealthRestrictionLifecycleGateway {
  FirebaseFunctionsHealthRestrictionLifecycleGateway({
    FirebaseFunctions? functions,
    HealthRestrictionFlowCallableInvoker? invoker,
  }) : _functions = functions,
       _invokerOverride = invoker;

  final FirebaseFunctions? _functions;
  final HealthRestrictionFlowCallableInvoker? _invokerOverride;
  HealthRestrictionFlowCallableInvoker? _cachedInvoker;

  HealthRestrictionFlowCallableInvoker get _invoke {
    return _cachedInvoker ??=
        _invokerOverride ??
        FirebaseFunctionsHealthRestrictionFlowCallableInvoker(
          functions: _functions,
        ).call;
  }

  @override
  Future<HealthRestrictionTerminalOutcome> end(
    EndOperationalRestrictionCommand command,
  ) {
    return _run(
      functionName: HealthRestrictionFlowCallables.restrictionEnd,
      payload: HealthRestrictionFlowPayloadCodec.encodeEnd(command),
      expected: HealthRestrictionTerminalStatus.ended,
      step: HealthRestrictionFlowStep.restrictionEnd,
    );
  }

  @override
  Future<HealthRestrictionTerminalOutcome> cancel(
    CancelOperationalRestrictionCommand command,
  ) {
    return _run(
      functionName: HealthRestrictionFlowCallables.restrictionCancel,
      payload: HealthRestrictionFlowPayloadCodec.encodeCancel(command),
      expected: HealthRestrictionTerminalStatus.cancelled,
      step: HealthRestrictionFlowStep.restrictionCancel,
    );
  }

  Future<HealthRestrictionTerminalOutcome> _run({
    required String functionName,
    required Map<String, dynamic> payload,
    required HealthRestrictionTerminalStatus expected,
    required HealthRestrictionFlowStep step,
  }) async {
    try {
      final raw = await _invoke(functionName, payload);
      return HealthRestrictionTerminalSuccess(
        HealthRestrictionFlowPayloadCodec.parseTerminal(
          raw,
          expected: expected,
          step: step,
        ),
      );
    } catch (e) {
      // `conflict` chega aqui quando a restrição já está terminal por outra
      // operação. Preservado como erro tipado: só um receipt compatível pode
      // afirmar replay, e o backend já distingue os dois casos.
      return HealthRestrictionTerminalError(
        HealthRestrictionFlowErrorMapper.map(e, step),
      );
    }
  }
}
