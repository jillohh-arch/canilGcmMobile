import 'package:canil_gcm/features/health/presentation/timeline/detail/health_timeline_detail_target.dart';

/// Motivos controlados de unavailable (sem PHI / paths).
enum HealthTimelineDetailUnavailableReason {
  missingReference,
  invalidSourceId,
  incompleteReference,
  destinationUnavailable,
  typeSourceMismatch,
}

/// Resultado tipado da resolução de detalhe (3D-C).
sealed class HealthTimelineDetailResolution {
  const HealthTimelineDetailResolution();
}

/// Destino real permitido e com dados mínimos.
///
/// [target.kind] indica se é histórico relacionado (v1) vs detalhe exato.
final class HealthTimelineDetailResolved
    extends HealthTimelineDetailResolution {
  const HealthTimelineDetailResolved(this.target);
  final HealthTimelineDetailTarget target;
}

/// Tipo conhecido, mas referência insuficiente / destino indisponível /
/// inconsistência type×source.
final class HealthTimelineDetailUnavailable
    extends HealthTimelineDetailResolution {
  const HealthTimelineDetailUnavailable(this.reason);
  final HealthTimelineDetailUnavailableReason reason;
}

/// Fora da allowlist v1 — zero navegação, sem exception.
final class HealthTimelineDetailUnsupported
    extends HealthTimelineDetailResolution {
  const HealthTimelineDetailUnsupported();
}
