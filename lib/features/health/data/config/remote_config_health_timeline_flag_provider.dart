import 'dart:async';

import 'package:canil_gcm/features/health/data/config/health_timeline_flag_provider.dart';
import 'package:canil_gcm/features/health/data/config/health_timeline_mode.dart';
import 'package:canil_gcm/features/health/data/config/health_timeline_remote_config_client.dart';

/// Provider de Feature Flag da timeline Health alimentado pelo Remote Config (fail-closed e cache-aware).
final class RemoteConfigHealthTimelineFlagProvider
    implements HealthTimelineFlagProvider {
  RemoteConfigHealthTimelineFlagProvider({
    required HealthTimelineRemoteConfigClient client,
    required Duration fetchTimeout,
    required Duration minimumFetchInterval,
  }) : _client = client,
       _fetchTimeout = fetchTimeout,
       _minimumFetchInterval = minimumFetchInterval {
    if (fetchTimeout <= Duration.zero) {
      throw ArgumentError.value(
        fetchTimeout,
        'fetchTimeout',
        'fetchTimeout deve ser maior que zero.',
      );
    }
    if (minimumFetchInterval < Duration.zero) {
      throw ArgumentError.value(
        minimumFetchInterval,
        'minimumFetchInterval',
        'minimumFetchInterval não pode ser negativo.',
      );
    }
  }

  static const String flagKey = 'health_timeline_mode';
  static const String defaultWireValue = 'legacyOnly';

  final HealthTimelineRemoteConfigClient _client;
  final Duration _fetchTimeout;
  final Duration _minimumFetchInterval;

  static const _safeDefaultResolution = HealthTimelineModeResolution(
    mode: HealthTimelineMode.legacyOnly,
    kind: HealthTimelineModeResolutionKind.missingDefault,
  );

  @override
  Future<HealthTimelineModeResolution> resolveMode() async {
    try {
      await _client.ensureInitialized();
    } catch (_) {
      return _safeDefaultResolution;
    }

    try {
      await _client.setConfigSettings(
        fetchTimeout: _fetchTimeout,
        minimumFetchInterval: _minimumFetchInterval,
      );
    } catch (_) {
      return _safeDefaultResolution;
    }

    try {
      await _client.setDefaults({flagKey: defaultWireValue});
    } catch (_) {
      return _safeDefaultResolution;
    }

    try {
      await _client.fetchAndActivate().timeout(_fetchTimeout);
    } catch (_) {
      // Ignora erro ou timeout do fetchAndActivate para permitir o uso de cache remoto existente.
    }

    final HealthTimelineRemoteValue remoteValue;
    try {
      remoteValue = _client.readValue(flagKey);
    } catch (_) {
      return _safeDefaultResolution;
    }

    switch (remoteValue.source) {
      case HealthTimelineRemoteValueSource.remoteValue:
        return HealthTimelineModeResolution.parse(remoteValue.value);
      case HealthTimelineRemoteValueSource.defaultValue:
      case HealthTimelineRemoteValueSource.staticValue:
        return _safeDefaultResolution;
    }
  }
}
