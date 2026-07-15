import 'package:canil_gcm/features/health/presentation/summary/health_summary_block_models.dart';
import 'package:canil_gcm/features/health/presentation/summary/health_summary_section_status.dart';
import 'package:canil_gcm/features/health/presentation/summary/health_summary_user_copy.dart';

/// Seções deliberadamente **não mapeadas** na coexistência legada (2D).
///
/// Não usam score legado, não inferem prontidão e não fingem protocolo
/// terapêutico a partir de eventos genéricos.
///
/// [message] usa copy operacional (sem jargão de arquitetura).
abstract final class HealthSummaryUnsafeSections {
  HealthSummaryUnsafeSections._();

  static const readiness =
      HealthSummarySectionData<HealthSummaryReadinessView>.unavailable(
        message: HealthSummaryUserCopy.readinessUnavailable,
      );

  static const treatments =
      HealthSummarySectionData<HealthSummaryTreatmentsView>.unavailable(
        message: HealthSummaryUserCopy.treatmentsUnavailable,
      );

  static const attention =
      HealthSummarySectionData<HealthSummaryAttentionView>.unavailable(
        message: HealthSummaryUserCopy.attentionUnavailable,
      );
}
