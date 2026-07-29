// Copyright 2024 GCM Health. All rights reserved.

import 'dart:async';

import 'health_timeline_shadow_telemetry_contract.dart';

/// Gateway abstrato para transmissão ou persistência de registros sanitizados de telemetria.
abstract interface class HealthTimelineShadowTelemetryGateway {
  /// Transmite ou registra um [HealthTimelineShadowTelemetryRecord] de forma assíncrona.
  Future<void> record(HealthTimelineShadowTelemetryRecord record);
}
