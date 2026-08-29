import 'package:firebase_remote_config/firebase_remote_config.dart';

import 'package:canil_gcm/features/health/data/config/firebase_health_timeline_remote_config_client.dart';
import 'package:canil_gcm/features/health/data/config/health_timeline_flag_provider.dart';
import 'package:canil_gcm/features/health/data/config/health_timeline_mode.dart';
import 'package:canil_gcm/features/health/data/config/health_timeline_remote_config_client.dart';
import 'package:canil_gcm/features/health/data/config/remote_config_health_timeline_flag_provider.dart';

/// Factory produtiva que encapsula a composição completa do provider de feature
/// flag da timeline Health com lock local que bloqueia canonicalPrimary.
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
    return withCanonicalPrimaryLock(delegate: delegate);
  }

  /// Envolve [delegate] com o lock produtivo que bloqueia canonicalPrimary.
  ///
  /// O delegate continua sendo executado normalmente, preservando leitura
  /// cache-first e refresh em background. legacyOnly e shadowCompare são
  /// permitidos; canonicalPrimary é convertido para
  /// legacyOnly/invalidDefault. Valores inválidos e exceptions permanecem
  /// fail-closed pelo provider remoto e por este guard.
  static HealthTimelineFlagProvider withCanonicalPrimaryLock({
    required HealthTimelineFlagProvider delegate,
  }) {
    return _CanonicalPrimaryLockedHealthTimelineFlagProvider(
      delegate: delegate,
    );
  }
}

/// Guard local que impede canonicalPrimary no composition root.
///
/// O delegate pode ler cache, instalar defaults e iniciar refresh background
/// normalmente. legacyOnly e shadowCompare atravessam inalterados;
/// canonicalPrimary é convertido para legacyOnly/invalidDefault. Valores
/// inválidos e exceptions continuam fechando em legacyOnly.
final class _CanonicalPrimaryLockedHealthTimelineFlagProvider
    implements HealthTimelineFlagProvider {
  const _CanonicalPrimaryLockedHealthTimelineFlagProvider({
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

    switch (resolution.mode) {
      case HealthTimelineMode.legacyOnly:
      case HealthTimelineMode.shadowCompare:
        return resolution;

      case HealthTimelineMode.canonicalPrimary:
        return const HealthTimelineModeResolution(
          mode: HealthTimelineMode.legacyOnly,
          kind: HealthTimelineModeResolutionKind.invalidDefault,
        );
    }
  }
}
