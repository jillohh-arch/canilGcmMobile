import 'package:firebase_remote_config/firebase_remote_config.dart';
import 'package:canil_gcm/features/health/data/config/health_timeline_remote_config_client.dart';

/// Implementação do cliente de configuração remota baseada no SDK do Firebase Remote Config.
final class FirebaseHealthTimelineRemoteConfigClient
    implements HealthTimelineRemoteConfigClient {
  const FirebaseHealthTimelineRemoteConfigClient({
    required FirebaseRemoteConfig remoteConfig,
  }) : _remoteConfig = remoteConfig;

  final FirebaseRemoteConfig _remoteConfig;

  /// Mapeia o `ValueSource` do SDK Firebase para o enum de domínio `HealthTimelineRemoteValueSource`.
  static HealthTimelineRemoteValueSource mapValueSource(ValueSource source) {
    switch (source) {
      case ValueSource.valueStatic:
        return HealthTimelineRemoteValueSource.staticValue;
      case ValueSource.valueDefault:
        return HealthTimelineRemoteValueSource.defaultValue;
      case ValueSource.valueRemote:
        return HealthTimelineRemoteValueSource.remoteValue;
    }
  }

  @override
  Future<void> ensureInitialized() async {
    await _remoteConfig.ensureInitialized();
  }

  @override
  Future<void> setConfigSettings({
    required Duration fetchTimeout,
    required Duration minimumFetchInterval,
  }) async {
    await _remoteConfig.setConfigSettings(
      RemoteConfigSettings(
        fetchTimeout: fetchTimeout,
        minimumFetchInterval: minimumFetchInterval,
      ),
    );
  }

  @override
  Future<void> setDefaults(Map<String, Object> defaults) async {
    await _remoteConfig.setDefaults(defaults);
  }

  @override
  Future<bool> fetchAndActivate() async {
    return await _remoteConfig.fetchAndActivate();
  }

  @override
  HealthTimelineRemoteValue readValue(String key) {
    final remoteValue = _remoteConfig.getValue(key);
    return HealthTimelineRemoteValue(
      value: remoteValue.asString(),
      source: mapValueSource(remoteValue.source),
    );
  }
}
