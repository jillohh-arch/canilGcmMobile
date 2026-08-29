import 'package:cloud_functions/cloud_functions.dart';

import '../../domain/health_restriction_flow_errors.dart';
import '../../domain/health_restriction_issue_gateway.dart';
import 'health_restriction_flow_callable_invoker.dart';
import 'health_restriction_flow_callables.dart';
import 'health_restriction_flow_error_mapper.dart';
import 'health_restriction_flow_payload_codec.dart';

/// Gateway de emissão de OperationalRestriction (B1) via Cloud Functions.
///
/// Só ISSUE. A autoridade exigida pelo backend é `health.issue_restriction`,
/// distinta de `health.create`/`health.edit` — o cliente não replica essa
/// checagem, apenas traduz a negação para linguagem operacional.
final class FirebaseFunctionsHealthRestrictionIssueGateway
    implements HealthRestrictionIssueGateway {
  FirebaseFunctionsHealthRestrictionIssueGateway({
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
  Future<IssueOperationalRestrictionResult> issue(
    IssueOperationalRestrictionCommand command,
  ) async {
    try {
      final raw = await _invoke(
        HealthRestrictionFlowCallables.restrictionIssue,
        HealthRestrictionFlowPayloadCodec.encodeIssue(command),
      );
      return IssueOperationalRestrictionSuccess(
        HealthRestrictionFlowPayloadCodec.parseIssued(raw),
      );
    } catch (e) {
      return IssueOperationalRestrictionError(
        HealthRestrictionFlowErrorMapper.map(
          e,
          HealthRestrictionFlowStep.restrictionIssue,
        ),
      );
    }
  }
}
