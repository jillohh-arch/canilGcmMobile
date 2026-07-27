import 'package:canil_gcm/features/health/data/config/health_timeline_flag_provider.dart';
import 'package:canil_gcm/features/health/data/config/health_timeline_mode.dart';

/// Implementação local segura que atua como fallback estrutural absoluto.
///
/// Retorna sempre `legacyOnly` com `missingDefault`, sem consultar fontes externas.
final class LocalHealthTimelineFlagProvider
    implements HealthTimelineFlagProvider {
  const LocalHealthTimelineFlagProvider();

  @override
  Future<HealthTimelineModeResolution> resolveMode() async {
    return const HealthTimelineModeResolution(
      mode: HealthTimelineMode.legacyOnly,
      kind: HealthTimelineModeResolutionKind.missingDefault,
    );
  }
}
