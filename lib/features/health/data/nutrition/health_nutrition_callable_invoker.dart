import 'package:cloud_functions/cloud_functions.dart';

import 'package:canil_gcm/features/health/data/nutrition/health_nutrition_callable_names.dart';

/// Seam mínimo para invocar callables HTTPS sem acoplar testes ao Firebase.
typedef HealthNutritionCallableInvoker =
    Future<Map<String, dynamic>> Function(
      String functionName,
      Map<String, dynamic> data,
    );

/// Invoker real via `cloud_functions` na região canônica.
///
/// Resolve [FirebaseFunctions] de forma **lazy** no primeiro call.
final class FirebaseFunctionsHealthNutritionCallableInvoker {
  FirebaseFunctionsHealthNutritionCallableInvoker({
    FirebaseFunctions? functions,
    Duration requestTimeout = defaultTimeout,
  }) : _functionsOverride = functions,
       _requestTimeout = requestTimeout;

  static const Duration defaultTimeout = Duration(seconds: 15);

  final FirebaseFunctions? _functionsOverride;
  final Duration _requestTimeout;
  FirebaseFunctions? _cached;

  FirebaseFunctions get _functions {
    return _cached ??=
        _functionsOverride ??
        FirebaseFunctions.instanceFor(
          region: HealthNutritionCallableNames.region,
        );
  }

  Future<Map<String, dynamic>> call(
    String functionName,
    Map<String, dynamic> data,
  ) async {
    final callable = _functions.httpsCallable(
      functionName,
      options: HttpsCallableOptions(timeout: _requestTimeout),
    );
    final result = await callable.call(data).timeout(_requestTimeout);
    final payload = result.data;
    if (payload is Map) {
      return Map<String, dynamic>.from(payload);
    }
    throw FirebaseFunctionsException(
      code: 'internal',
      message: 'Resposta do callable sem mapa estruturado.',
      details: const {'code': 'integrity'},
    );
  }
}
