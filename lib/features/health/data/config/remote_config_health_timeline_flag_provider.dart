import 'dart:async';

import 'package:canil_gcm/features/health/data/config/health_timeline_flag_provider.dart';
import 'package:canil_gcm/features/health/data/config/health_timeline_mode.dart';
import 'package:canil_gcm/features/health/data/config/health_timeline_remote_config_client.dart';

/// Provider de Feature Flag da timeline Health alimentado pelo Remote Config (cache-first e fail-closed).
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

  /// Refresh em curso. Usado para deduplicar fetches concorrentes.
  Future<void>? _refreshInFlight;

  @override
  Future<HealthTimelineModeResolution> resolveMode() async {
    // 1. ensureInitialized
    try {
      await _client.ensureInitialized();
    } catch (_) {
      return _safeDefaultResolution;
    }

    // 2. setConfigSettings
    try {
      await _client.setConfigSettings(
        fetchTimeout: _fetchTimeout,
        minimumFetchInterval: _minimumFetchInterval,
      );
    } catch (_) {
      return _safeDefaultResolution;
    }

    // 3. setDefaults
    try {
      await _client.setDefaults({flagKey: defaultWireValue});
    } catch (_) {
      return _safeDefaultResolution;
    }

    // 4. readValue — leitura local, SEMPRE antes do fetch
    final HealthTimelineRemoteValue remoteValue;
    try {
      remoteValue = _client.readValue(flagKey);
    } catch (_) {
      return _safeDefaultResolution;
    }

    // 5. Converter valor local em resolução
    final resolution = _resolutionFromRemoteValue(remoteValue);

    // 6. Iniciar refresh em background — não aguarda
    _startRefreshIfNeeded();

    // 7. Retornar imediatamente o valor local
    return resolution;
  }

  /// Converte o valor local lido em HealthTimelineModeResolution fail-closed.
  ///
  /// - `remoteValue`: interpreta o wire value normalmente.
  /// - `defaultValue` ou `staticValue`: retorna safe default.
  HealthTimelineModeResolution _resolutionFromRemoteValue(
    HealthTimelineRemoteValue remoteValue,
  ) {
    switch (remoteValue.source) {
      case HealthTimelineRemoteValueSource.remoteValue:
        return HealthTimelineModeResolution.parse(remoteValue.value);
      case HealthTimelineRemoteValueSource.defaultValue:
      case HealthTimelineRemoteValueSource.staticValue:
        return _safeDefaultResolution;
    }
  }

  /// Inicia refresh em background, deduplicando chamadas concorrentes.
  void _startRefreshIfNeeded() {
    if (_refreshInFlight != null) return;

    final refresh = _refreshSafely();
    _refreshInFlight = refresh;

    unawaited(
      refresh.whenComplete(() {
        // Limpa slot in-flight apenas se for o mesmo future.
        if (identical(_refreshInFlight, refresh)) {
          _refreshInFlight = null;
        }
      }),
    );
  }

  /// Executa fetchAndActivate com tratamento de exceptions.
  ///
  /// Failures are swallowed — o cache local existente é preservado.
  /// O resultado do refresh só afetará a próxima chamada de resolveMode.
  Future<void> _refreshSafely() async {
    try {
      await _client.fetchAndActivate();
    } catch (_) {
      // Ignora qualquer falha — exception de rede, throttling, ou outro erro.
      // O cache local permanece intacto.
    }
  }
}
