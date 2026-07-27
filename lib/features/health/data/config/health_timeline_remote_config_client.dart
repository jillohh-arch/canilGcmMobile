/// Origem do valor retornado pelo cliente de configuração remota.
enum HealthTimelineRemoteValueSource { staticValue, defaultValue, remoteValue }

/// Objeto de valor imutável representando um valor de configuração remota e sua origem.
final class HealthTimelineRemoteValue {
  const HealthTimelineRemoteValue({required this.value, required this.source});

  final String value;
  final HealthTimelineRemoteValueSource source;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is HealthTimelineRemoteValue &&
        other.value == value &&
        other.source == source;
  }

  @override
  int get hashCode => Object.hash(value, source);

  @override
  String toString() => 'HealthTimelineRemoteValue(source: $source)';
}

/// Contrato do cliente de configuração remota da timeline Health.
abstract interface class HealthTimelineRemoteConfigClient {
  Future<void> ensureInitialized();

  Future<void> setConfigSettings({
    required Duration fetchTimeout,
    required Duration minimumFetchInterval,
  });

  Future<void> setDefaults(Map<String, Object> defaults);

  Future<bool> fetchAndActivate();

  HealthTimelineRemoteValue readValue(String key);
}
