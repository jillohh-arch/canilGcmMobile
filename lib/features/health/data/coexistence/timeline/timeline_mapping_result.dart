import 'package:canil_gcm/features/health/presentation/timeline/health_timeline_entry_view.dart';

/// Motivos controlados de mapping estruturalmente inválido (sem PHI).
enum TimelineMappingInvalidReason {
  /// Campo de data obrigatório ausente.
  missingRequiredDate,

  /// Campo de data presente mas ilegível / não interpretável.
  invalidRequiredDate,

  /// Outro campo estrutural obrigatório ausente ou corrompido
  /// (ex.: tipo vazio em health_event, weight_kg inválido).
  invalidRequiredStructure,
}

/// Resultado mínimo do mapping legado → timeline (3C).
///
/// ## Semântica
/// - [TimelineMapped]: entrada utilizável;
/// - [TimelineIgnored]: descartável com segurança (soft-delete, filtro, …);
/// - [TimelineInvalid]: ativo relevante sem posicionamento confiável →
///   leitura **inconclusiva** (não é empty, não é sucesso parcial).
sealed class TimelineMappingResult {
  const TimelineMappingResult();
}

/// Documento mapeado com sucesso.
final class TimelineMapped extends TimelineMappingResult {
  const TimelineMapped(this.entry);

  final HealthTimelineEntryView entry;
}

/// Documento ignorável (não bloqueia completude).
final class TimelineIgnored extends TimelineMappingResult {
  const TimelineIgnored([this.reasonCode]);

  /// Código opcional apenas para diagnóstico interno (sem payload clínico).
  final String? reasonCode;
}

/// Documento ativo relevante estruturalmente unmappable.
final class TimelineInvalid extends TimelineMappingResult {
  const TimelineInvalid(this.reason);

  final TimelineMappingInvalidReason reason;
}
