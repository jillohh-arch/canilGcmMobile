import 'package:cloud_functions/cloud_functions.dart';

import '../../domain/health_document_gateway.dart';
import '../../domain/health_restriction_flow_errors.dart';
import 'health_restriction_flow_callable_invoker.dart';
import 'health_restriction_flow_callables.dart';
import 'health_restriction_flow_error_mapper.dart';
import 'health_restriction_flow_payload_codec.dart';

/// Gateway do HealthDocument canônico (B0) via Cloud Functions.
///
/// Não conhece Storage: PREPARE devolve o staging path, o upload é
/// responsabilidade do [HealthEvidenceUploader], e o FINALIZE é a autoridade
/// que verifica os bytes e sela.
final class FirebaseFunctionsHealthDocumentGateway
    implements HealthDocumentGateway {
  FirebaseFunctionsHealthDocumentGateway({
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
  Future<PrepareHealthDocumentResult> prepareUpload(
    PrepareHealthDocumentCommand command,
  ) async {
    try {
      final raw = await _invoke(
        HealthRestrictionFlowCallables.documentPrepareUpload,
        HealthRestrictionFlowPayloadCodec.encodePrepare(command),
      );
      return PrepareHealthDocumentSuccess(
        HealthRestrictionFlowPayloadCodec.parsePrepared(raw),
      );
    } catch (e) {
      return PrepareHealthDocumentError(
        HealthRestrictionFlowErrorMapper.map(
          e,
          HealthRestrictionFlowStep.documentPrepare,
        ),
      );
    }
  }

  @override
  Future<FinalizeHealthDocumentResult> finalizeUpload(
    FinalizeHealthDocumentCommand command,
  ) async {
    try {
      final raw = await _invoke(
        HealthRestrictionFlowCallables.documentFinalizeUpload,
        HealthRestrictionFlowPayloadCodec.encodeFinalize(command),
      );
      return FinalizeHealthDocumentSuccess(
        HealthRestrictionFlowPayloadCodec.parseFinalized(raw),
      );
    } catch (e) {
      return FinalizeHealthDocumentError(
        HealthRestrictionFlowErrorMapper.map(
          e,
          HealthRestrictionFlowStep.documentFinalize,
        ),
      );
    }
  }
}
