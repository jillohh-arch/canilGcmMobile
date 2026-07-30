// Copyright 2024 GCM Health. All rights reserved.
//
// GATEWAY SHADOW OBSERVER — Observer implementation that forwards to the gateway.
// Fail-silent: absorbs all exceptions from mapper and gateway.

import 'dart:async';

import 'package:canil_gcm/features/health/data/shadow/health_timeline_shadow_models.dart';

import 'health_timeline_shadow_telemetry_contract.dart';
import 'health_timeline_shadow_telemetry_gateway.dart';
import 'health_timeline_shadow_telemetry_mapper.dart';

/// Callback type for mapping outcomes to telemetry records.
typedef HealthTimelineShadowTelemetryMapperCallback =
    HealthTimelineShadowTelemetryRecord Function(
      HealthTimelineShadowOutcome outcome,
    );

/// Observer de telemetria shadow que transmite outcomes para o gateway.
///
/// Cada callback:
/// - mapeia o outcome uma única vez via [HealthTimelineShadowTelemetryMapper]
/// - chama [gateway.record] uma única vez
/// - absorve qualquer exceção (fail-silent)
///
/// O observer é thread-safe para múltiplos callbacks concorrentes.
final class GatewayHealthTimelineShadowObserver
    implements HealthTimelineShadowObserver {
  /// Cria um observer que transmite para o [gateway] fornecido.
  const GatewayHealthTimelineShadowObserver({
    required HealthTimelineShadowTelemetryGateway gateway,
    HealthTimelineShadowTelemetryMapperCallback? mapper,
  }) : _gateway = gateway,
       _mapper = mapper ?? HealthTimelineShadowTelemetryMapper.fromOutcome;

  final HealthTimelineShadowTelemetryGateway _gateway;
  final HealthTimelineShadowTelemetryMapperCallback _mapper;

  @override
  FutureOr<void> onComparison(HealthTimelineShadowComparison value) {
    _transmit(value);
  }

  @override
  FutureOr<void> onSkipped(HealthTimelineShadowSkipped value) {
    _transmit(value);
  }

  @override
  FutureOr<void> onFailure(HealthTimelineShadowFailure value) {
    _transmit(value);
  }

  /// Mapeia e transmite o outcome. Absorve todas as exceções síncronas e
  /// assíncronas do mapper e do gateway.
  Future<void> _transmit(HealthTimelineShadowOutcome outcome) async {
    try {
      final record = _mapper(outcome);
      await _gateway.record(record);
    } catch (_) {
      // Fail-silent: absorve qualquer exceção síncrona ou assíncrona.
      // Não relança, não loga, não notifica.
    }
  }
}
