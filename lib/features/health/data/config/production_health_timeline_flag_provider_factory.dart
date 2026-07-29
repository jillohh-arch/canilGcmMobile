import 'package:firebase_remote_config/firebase_remote_config.dart';

import 'package:canil_gcm/features/health/data/config/firebase_health_timeline_remote_config_client.dart';
import 'package:canil_gcm/features/health/data/config/health_timeline_flag_provider.dart';
import 'package:canil_gcm/features/health/data/config/health_timeline_mode.dart';
import 'package:canil_gcm/features/health/data/config/health_timeline_remote_config_client.dart';
import 'package:canil_gcm/features/health/data/config/remote_config_health_timeline_flag_provider.dart';

/// Factory produtiva que encapsula a composição completa do provider de feature flag
/// da timeline Health com lock local explícito em legacyOnly.
///
/// O shell não precisa conhecer FirebaseRemoteConfig, o client SDK, nem o
/// provider cache-first. Esta factory resolve todos esses detalhes internamente.
abstract final class ProductionHealthTimelineFlagProviderFactory {
  /// Timeout padrão para fetch do Remote Config (encaminhado ao SDK).
  static const Duration defaultFetchTimeout = Duration(minutes: 1);

  /// Intervalo mínimo entre fetches automáticos do SDK.
  static const Duration defaultMinimumFetchInterval = Duration(hours: 1);

  /// Cria o provider produtivo a partir do FirebaseRemoteConfig real.
  ///
  /// Use no composition root (MainRoot). O shell não precisa importar
  /// Firebase nem conhecer detalhes da configuração remota.
  static HealthTimelineFlagProvider forRemoteConfig({
    FirebaseRemoteConfig? remoteConfig,
    Duration fetchTimeout = defaultFetchTimeout,
    Duration minimumFetchInterval = defaultMinimumFetchInterval,
  }) {
    final rc = remoteConfig ?? FirebaseRemoteConfig.instance;
    final client = FirebaseHealthTimelineRemoteConfigClient(remoteConfig: rc);
    return forClient(
      client: client,
      fetchTimeout: fetchTimeout,
      minimumFetchInterval: minimumFetchInterval,
    );
  }

  /// Cria o provider produtivo a partir de um client já instanciado.
  ///
  /// Permite testes sem Firebase real — basta fornecer um fake do client.
  static HealthTimelineFlagProvider forClient({
    required HealthTimelineRemoteConfigClient client,
    Duration fetchTimeout = defaultFetchTimeout,
    Duration minimumFetchInterval = defaultMinimumFetchInterval,
  }) {
    final delegate = RemoteConfigHealthTimelineFlagProvider(
      client: client,
      fetchTimeout: fetchTimeout,
      minimumFetchInterval: minimumFetchInterval,
    );
    return withLegacyOnlyLock(delegate: delegate);
  }

  /// Envolve [delegate] com o lock produtivo que permite somente legacyOnly.
  ///
  /// O delegate continua sendo executado normalmente, preservando leitura
  /// cache-first e refresh em background. Modos não autorizados são
  /// convertidos para legacyOnly/invalidDefault.
  static HealthTimelineFlagProvider withLegacyOnlyLock({
    required HealthTimelineFlagProvider delegate,
  }) {
    return _LegacyOnlyLockedHealthTimelineFlagProvider(delegate: delegate);
  }
}

/// Guard local que restringe o modo entregue ao composition root a legacyOnly.
///
/// O delegate pode ler cache, instalar defaults e iniciar refresh background
/// normalmente. O guard apenas converte qualquer modo diferente de legacyOnly
/// para legacyOnly/invalidDefault antes de entregar ao consumidor.
final class _LegacyOnlyLockedHealthTimelineFlagProvider
    implements HealthTimelineFlagProvider {
  const _LegacyOnlyLockedHealthTimelineFlagProvider({
    required HealthTimelineFlagProvider delegate,
  }) : _delegate = delegate;

  final HealthTimelineFlagProvider _delegate;

  @override
  Future<HealthTimelineModeResolution> resolveMode() async {
    final HealthTimelineModeResolution resolution;
    try {
      resolution = await _delegate.resolveMode();
    } catch (_) {
      // Delegate lançou exception inesperada → fallback seguro.
      return const HealthTimelineModeResolution(
        mode: HealthTimelineMode.legacyOnly,
        kind: HealthTimelineModeResolutionKind.missingDefault,
      );
    }

    // Permitir somente legacyOnly — preservar kind original.
    if (resolution.mode == HealthTimelineMode.legacyOnly) {
      return resolution;
    }

    // shadowCompare ou canonicalPrimary → bloquear.
    return const HealthTimelineModeResolution(
      mode: HealthTimelineMode.legacyOnly,
      kind: HealthTimelineModeResolutionKind.invalidDefault,
    );
  }
}
