import 'package:canil_gcm/features/health/presentation/summary/health_summary_block_models.dart';
import 'package:canil_gcm/features/health/presentation/summary/health_summary_section_status.dart';

/// Seções deliberadamente **não mapeadas** na coexistência legada (2D).
///
/// Não usam score legado, não inferem prontidão e não fingem protocolo
/// terapêutico a partir de eventos genéricos.
abstract final class HealthSummaryUnsafeSections {
  HealthSummaryUnsafeSections._();

  static const readiness =
      HealthSummarySectionData<HealthSummaryReadinessView>.unavailable(
        message:
            'Prontidão Health v1 ainda sem fonte compatível na coexistência legada',
      );

  static const treatments =
      HealthSummarySectionData<HealthSummaryTreatmentsView>.unavailable(
        message:
            'Tratamentos estruturados (protocolos) não disponíveis no legado',
      );

  static const attention =
      HealthSummarySectionData<HealthSummaryAttentionView>.unavailable(
        message:
            'Atenções prioritárias sem fonte segura na coexistência legada',
      );
}
