import 'package:cloud_functions/cloud_functions.dart';

import 'package:canil_gcm/features/health/data/schedule/health_schedule_callable_names.dart';

/// Seam mínimo para invocar callables HTTPS sem acoplar testes ao Firebase.
///
/// Produção usa [FirebaseFunctionsHealthScheduleCallableInvoker].
typedef HealthScheduleCallableInvoker =
    Future<Map<String, dynamic>> Function(
      String functionName,
      Map<String, dynamic> data,
    );

/// Invoker real via `cloud_functions` na região canônica.
///
/// Resolve [FirebaseFunctions] de forma **lazy** no primeiro call — permite
/// composition root em testes de widget sem Firebase.initializeApp.
final class FirebaseFunctionsHealthScheduleCallableInvoker {
  FirebaseFunctionsHealthScheduleCallableInvoker({FirebaseFunctions? functions})
    : _functionsOverride = functions;

  final FirebaseFunctions? _functionsOverride;
  FirebaseFunctions? _cached;

  FirebaseFunctions get _functions {
    return _cached ??=
        _functionsOverride ??
        FirebaseFunctions.instanceFor(
          region: HealthScheduleCallableNames.region,
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
    // Integrity será materializada no parse do gateway.
    throw FirebaseFunctionsException(
      code: 'internal',
      message: 'Resposta do callable sem mapa estruturado.',
      details: const {'code': 'integrity'},
    );
  }
}
