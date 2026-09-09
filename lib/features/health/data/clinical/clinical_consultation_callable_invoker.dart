import 'package:cloud_functions/cloud_functions.dart';

import 'package:canil_gcm/features/health/data/clinical/clinical_consultation_callable_names.dart';

/// Seam mínimo para invocar callables clínicos sem acoplar testes ao Firebase.
typedef ClinicalConsultationCallableInvoker =
    Future<Map<String, dynamic>> Function(
      String functionName,
      Map<String, dynamic> data,
    );

/// Invoker real via `cloud_functions` na região canônica.
///
/// Resolve [FirebaseFunctions] de forma lazy no primeiro call, igual ao
/// invoker de Nutrição.
final class FirebaseFunctionsClinicalConsultationCallableInvoker {
  FirebaseFunctionsClinicalConsultationCallableInvoker({
    FirebaseFunctions? functions,
  }) : _functionsOverride = functions;

  final FirebaseFunctions? _functionsOverride;
  FirebaseFunctions? _cached;

  FirebaseFunctions get _functions {
    return _cached ??=
        _functionsOverride ??
        FirebaseFunctions.instanceFor(
          region: ClinicalConsultationCallableNames.region,
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
    throw FirebaseFunctionsException(
      code: 'internal',
      message: 'Resposta do callable clínico em formato inesperado.',
    );
  }
}
