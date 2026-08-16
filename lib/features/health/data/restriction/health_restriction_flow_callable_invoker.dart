import 'package:cloud_functions/cloud_functions.dart';

import 'health_restriction_flow_callables.dart';

/// Seam de transporte: produção usa Firebase Functions, teste injeta um fake.
typedef HealthRestrictionFlowCallableInvoker =
    Future<Map<String, dynamic>> Function(
      String functionName,
      Map<String, dynamic> data,
    );

/// Invoker real, seguindo o padrão factual da Agenda Preventiva.
final class FirebaseFunctionsHealthRestrictionFlowCallableInvoker {
  FirebaseFunctionsHealthRestrictionFlowCallableInvoker({
    FirebaseFunctions? functions,
  }) : _functionsOverride = functions;

  final FirebaseFunctions? _functionsOverride;
  FirebaseFunctions? _cached;

  FirebaseFunctions get _functions {
    return _cached ??=
        _functionsOverride ??
        FirebaseFunctions.instanceFor(
          region: HealthRestrictionFlowCallables.region,
        );
  }

  Future<Map<String, dynamic>> call(
    String functionName,
    Map<String, dynamic> data,
  ) async {
    final callable = _functions.httpsCallable(functionName);
    final result = await callable.call(data);
    final payload = result.data;
    if (payload is Map) {
      return Map<String, dynamic>.from(payload);
    }
    // Resposta sem mapa estruturado é integridade, não erro de transporte:
    // o parse do gateway materializa a falha com a etapa correta.
    throw FirebaseFunctionsException(
      code: 'internal',
      message: 'Resposta do callable sem mapa estruturado.',
      details: const {'code': 'integrity'},
    );
  }
}
