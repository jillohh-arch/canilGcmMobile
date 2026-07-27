import 'package:canil_gcm/features/health/data/config/health_timeline_mode.dart';

/// Interface abstrata do provedor de Feature Flag para a timeline Health.
abstract interface class HealthTimelineFlagProvider {
  /// Resolve o modo atual da timeline de forma assíncrona.
  Future<HealthTimelineModeResolution> resolveMode();
}
