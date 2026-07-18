import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';

import 'package:canil_gcm/features/health/data/schedule/health_schedule_callable_invoker.dart';
import 'package:canil_gcm/features/health/data/schedule/health_schedule_callable_names.dart';
import 'package:canil_gcm/features/health/data/schedule/health_schedule_functions_error_mapper.dart';
import 'package:canil_gcm/features/health/data/schedule/health_schedule_mutation_payload_codec.dart';
import 'package:canil_gcm/features/health/domain/health_schedule_mutation_commands.dart';
import 'package:canil_gcm/features/health/domain/health_schedule_mutation_errors.dart';
import 'package:canil_gcm/features/health/domain/health_schedule_mutation_gateway.dart';

/// Gateway permanente: domain command → callable Firebase → receipt tipado.
///
/// - Região: [HealthScheduleCallableNames.region]
/// - Auth: sessão Firebase Auth do SDK (sem token manual)
/// - Sem regra clínica; backend é autoridade final
final class FirebaseFunctionsHealthScheduleMutationGateway
    implements HealthScheduleMutationGateway {
  FirebaseFunctionsHealthScheduleMutationGateway({
    FirebaseFunctions? functions,
    HealthScheduleCallableInvoker? invoker,
  }) : _functions = functions,
       _invokerOverride = invoker;

  final FirebaseFunctions? _functions;
  final HealthScheduleCallableInvoker? _invokerOverride;
  HealthScheduleCallableInvoker? _cachedInvoker;

  HealthScheduleCallableInvoker get _invoke {
    return _cachedInvoker ??=
        _invokerOverride ??
        FirebaseFunctionsHealthScheduleCallableInvoker(
          functions: _functions,
        ).call;
  }

  @override
  Future<HealthScheduleMutationResult> createManual(
    CreateManualScheduleItemCommand command,
  ) {
    return _run(
      functionName: HealthScheduleCallableNames.createManual,
      payload: HealthScheduleMutationPayloadCodec.encodeCreateManual(command),
      operationId: command.operationId,
    );
  }

  @override
  Future<HealthScheduleMutationResult> updateOpen(
    UpdateOpenScheduleItemCommand command,
  ) async {
    try {
      final payload = HealthScheduleMutationPayloadCodec.encodeUpdateOpen(
        command,
      );
      return await _run(
        functionName: HealthScheduleCallableNames.updateOpen,
        payload: payload,
        operationId: command.operationId,
      );
    } on HealthScheduleMutationFailure catch (e) {
      return HealthScheduleMutationErrorResult(e);
    }
  }

  @override
  Future<HealthScheduleMutationResult> complete(
    CompleteScheduleItemCommand command,
  ) {
    return _run(
      functionName: HealthScheduleCallableNames.complete,
      payload: HealthScheduleMutationPayloadCodec.encodeComplete(command),
      operationId: command.operationId ?? 'complete:${command.scheduleId}',
    );
  }

  @override
  Future<HealthScheduleMutationResult> cancel(
    CancelScheduleItemCommand command,
  ) {
    return _run(
      functionName: HealthScheduleCallableNames.cancel,
      payload: HealthScheduleMutationPayloadCodec.encodeCancel(command),
      operationId: command.operationId,
    );
  }

  Future<HealthScheduleMutationResult> _run({
    required String functionName,
    required Map<String, dynamic> payload,
    required String operationId,
  }) async {
    try {
      final raw = await _invoke(functionName, payload);
      final receipt = HealthScheduleMutationPayloadCodec.parseReceipt(raw);
      return HealthScheduleMutationSuccess(
        dogId: receipt.dogId,
        scheduleId: receipt.scheduleId,
        revision: receipt.revision,
        wasNoOp: receipt.wasNoOp,
        lifecycleStatus: receipt.lifecycleStatus,
        operationId: operationId,
      );
    } catch (e, st) {
      if (e is FirebaseFunctionsException) {
        debugPrint(
          '[FirebaseFunctionsHealthScheduleMutationGateway] '
          '$functionName FirebaseFunctionsException code=${e.code}',
        );
      } else if (e is! HealthScheduleMutationFailure) {
        debugPrint(
          '[FirebaseFunctionsHealthScheduleMutationGateway] '
          '$functionName falhou: ${e.runtimeType}',
        );
        assert(() {
          debugPrint('$st');
          return true;
        }());
      }
      return HealthScheduleMutationErrorResult(
        HealthScheduleFunctionsErrorMapper.map(e),
      );
    }
  }
}
