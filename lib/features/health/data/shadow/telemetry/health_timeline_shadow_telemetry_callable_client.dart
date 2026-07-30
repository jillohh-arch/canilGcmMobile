// Copyright 2024 GCM Health. All rights reserved.
//
// HEALTH TIMELINE SHADOW TELEMETRY CALLABLE CLIENT — Testable abstraction.
// No Firebase coupling at this layer.

/// Abstração testável para o callable de telemetria shadow.
/// Esconde HttpsCallableResult, FirebaseFunctionsException e detalhes do SDK.
abstract interface class HealthTimelineShadowTelemetryCallableClient {
  /// Invoca o callable com o [payload] e retorna o resultado raw.
  /// Pode falhar com [Exception] em caso de erro de rede, timeout ou resposta inválida.
  Future<Object?> call(Map<String, Object> payload);
}
