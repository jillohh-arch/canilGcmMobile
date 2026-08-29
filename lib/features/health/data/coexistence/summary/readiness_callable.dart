import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';

/// Nomes e região do callable de Prontidão (READINESS-V1 Gate 4).
abstract final class ReadinessCallableNames {
  ReadinessCallableNames._();

  /// Callable server-side que reprojeta `health_summary/current`.
  static const refresh = 'healthReadinessRefresh';

  static const region = 'southamerica-east1';
}

/// Seam mínimo para invocar o callable sem acoplar testes ao Firebase.
typedef ReadinessCallableInvoker =
    Future<Map<String, dynamic>> Function(
      String functionName,
      Map<String, dynamic> data,
    );

/// Invoker real via `cloud_functions` na região canônica.
final class FirebaseFunctionsReadinessCallableInvoker {
  FirebaseFunctionsReadinessCallableInvoker({FirebaseFunctions? functions})
    : _functionsOverride = functions;

  final FirebaseFunctions? _functionsOverride;
  FirebaseFunctions? _cached;

  FirebaseFunctions get _functions {
    return _cached ??=
        _functionsOverride ??
        FirebaseFunctions.instanceFor(region: ReadinessCallableNames.region);
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
      message: 'Resposta do callable sem mapa estruturado.',
      details: const {'code': 'integrity'},
    );
  }
}

/// Gateway do refresh de Prontidão.
///
/// Contrato de request congelado: **apenas** `dogId`.
///
/// O Mobile jamais envia resultado clínico (`readinessStatus`, `reason`,
/// `completeness`, `alerts`, `restrictions`). O backend é o único avaliador e
/// rejeita payload com veredito do cliente (provado no Gate 4).
final class ReadinessRefreshGateway {
  ReadinessRefreshGateway({required ReadinessCallableInvoker invoke})
    : _invoke = invoke;

  final ReadinessCallableInvoker _invoke;

  /// Solicita reprojeção server-side. Retorna `true` se o backend concluiu.
  ///
  /// Nunca lança: falha de canal vira `false`, e o chamador trata como
  /// indisponibilidade técnica (sem cálculo local de fallback).
  Future<bool> refresh(String dogId) async {
    try {
      // Payload mínimo — o formato é asserido por teste de contrato.
      final response = await _invoke(ReadinessCallableNames.refresh, {
        'dogId': dogId,
      });
      final ok = response['ok'];
      return ok == true;
    } on FirebaseFunctionsException catch (e) {
      debugPrint(
        '[ReadinessRefreshGateway] refresh bloqueado [${e.code}]: ${e.message}',
      );
      return false;
    } catch (e) {
      debugPrint('[ReadinessRefreshGateway] refresh falhou: $e');
      return false;
    }
  }
}
