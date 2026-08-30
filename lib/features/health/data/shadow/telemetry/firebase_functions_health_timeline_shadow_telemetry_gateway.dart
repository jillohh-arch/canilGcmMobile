// Copyright 2024 GCM Health. All rights reserved.
//
// FIREBASE FUNCTIONS GATEWAY — Callable adapter for shadow telemetry.
// Region: southamerica-east1. Callable: healthTimelineRecordShadowTelemetry.

import 'package:cloud_functions/cloud_functions.dart';

import 'health_timeline_shadow_telemetry_callable_client.dart';
import 'health_timeline_shadow_telemetry_contract.dart';
import 'health_timeline_shadow_telemetry_gateway.dart';

/// Implementação Firebase do gateway de telemetria shadow.
///
/// Region: southamerica-east1
/// Callable: healthTimelineRecordShadowTelemetry
///
/// Utiliza FirebaseFunctions SDK que cuida de autenticação e App Check
/// automaticamente, sem necessidade de tokens manuais.
final class FirebaseFunctionsHealthTimelineShadowTelemetryGateway
    implements HealthTimelineShadowTelemetryGateway {
  /// Cria um gateway Firebase Functions.
  ///
  /// Se [functions] for fornecido, utiliza-o diretamente.
  /// Se [client] for fornecido, utiliza-o (útil para testes).
  /// Se nenhum for fornecido, cria uma instância para a região [southamerica-east1].
  FirebaseFunctionsHealthTimelineShadowTelemetryGateway({
    FirebaseFunctions? functions,
    HealthTimelineShadowTelemetryCallableClient? client,
  }) : _functions = functions,
       _client = client;

  final FirebaseFunctions? _functions;
  final HealthTimelineShadowTelemetryCallableClient? _client;

  static const String region = 'southamerica-east1';
  static const String callableName = 'healthTimelineRecordShadowTelemetry';
  static const Duration timeout = Duration(seconds: 10);

  @override
  Future<void> record(HealthTimelineShadowTelemetryRecord record) async {
    final payload = record.toJson();
    final result = await _resolveClient().call(payload);
    _validateResponse(result);
  }

  /// Resolve o client: injetado > FirebaseFunctions SDK.
  HealthTimelineShadowTelemetryCallableClient _resolveClient() {
    if (_client case HealthTimelineShadowTelemetryCallableClient c) {
      return c;
    }
    final functions =
        _functions ?? FirebaseFunctions.instanceFor(region: region);
    return _FirebaseFunctionsCallableClient(
      httpsCallable: functions.httpsCallable(
        callableName,
        options: HttpsCallableOptions(timeout: timeout),
      ),
    );
  }

  /// Valida a resposta do callable semanticamente.
  /// Aceita apenas {accepted: true} como sucesso.
  void _validateResponse(Object? result) {
    if (result == null) {
      throw const _InvalidResponseException('Response is null');
    }

    if (result is! Map) {
      throw _InvalidResponseException(
        'Response is not a Map: ${result.runtimeType}',
      );
    }

    final accepted = result['accepted'];
    if (accepted != true) {
      throw _InvalidResponseException('accepted != true: $accepted');
    }
  }
}

/// Exceção para respostas inválidas do callable.
class _InvalidResponseException implements Exception {
  const _InvalidResponseException(this.message);

  final String message;

  @override
  String toString() => '_InvalidResponseException: $message';
}

/// Adapter interno que converte HttpsCallableResult em Object?.
final class _FirebaseFunctionsCallableClient
    implements HealthTimelineShadowTelemetryCallableClient {
  const _FirebaseFunctionsCallableClient({required HttpsCallable httpsCallable})
    : _httpsCallable = httpsCallable;

  final HttpsCallable _httpsCallable;

  @override
  Future<Object?> call(Map<String, Object> payload) async {
    final result = await _httpsCallable(payload);
    return result.data;
  }
}
