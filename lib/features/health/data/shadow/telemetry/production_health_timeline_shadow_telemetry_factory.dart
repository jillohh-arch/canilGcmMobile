// Copyright 2024 GCM Health. All rights reserved.
//
// PRODUCTION HEALTH TIMELINE SHADOW TELEMETRY FACTORY.
//
// Lazy factory that composes the production observer chain:
// FirebaseFunctions → callable client → gateway → observer.

import 'package:cloud_functions/cloud_functions.dart';

import 'firebase_functions_health_timeline_shadow_telemetry_gateway.dart';
import 'gateway_health_timeline_shadow_observer.dart';
import 'health_timeline_shadow_telemetry_callable_client.dart';

/// Factory lazy para criar o observer de telemetria shadow produtivo.
///
/// Sem side effects durante a construção.
/// Sem chamada de rede durante create().
abstract final class ProductionHealthTimelineShadowTelemetryFactory {
  ProductionHealthTimelineShadowTelemetryFactory._();

  /// Cria um [GatewayHealthTimelineShadowObserver] pronto para uso.
  ///
  /// Se [functions] for fornecido, utiliza-o para o callable.
  /// Se [client] for fornecido, utiliza-o diretamente (útil para testes).
  ///
  /// A construção é lazy: nenhum callable é invocado até que um outcome
  /// seja observado.
  static GatewayHealthTimelineShadowObserver create({
    FirebaseFunctions? functions,
    HealthTimelineShadowTelemetryCallableClient? client,
  }) {
    final gateway = FirebaseFunctionsHealthTimelineShadowTelemetryGateway(
      functions: functions,
      client: client,
    );

    return GatewayHealthTimelineShadowObserver(gateway: gateway);
  }
}
