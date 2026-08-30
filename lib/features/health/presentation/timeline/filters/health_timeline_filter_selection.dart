import 'package:canil_gcm/features/health/domain/health_v1_enums_ext.dart';
import 'package:canil_gcm/features/health/presentation/timeline/filters/health_timeline_period_preset.dart';
import 'package:canil_gcm/features/health/presentation/timeline/health_timeline_query.dart';

/// Seleção de filtros editável da UI (sem cursor, sem dogId/pageSize).
///
/// ## Query vs UI
/// - [period] entra na identidade da query (3A);
/// - [periodOrigin] é **metadado visual** (preset vs custom) e **não** vai
///   para a query/source — evita que custom com 30 dias vire “preset 30d”
///   apenas na label.
final class HealthTimelineFilterSelection {
  HealthTimelineFilterSelection({
    Set<HealthTimelineType> types = const {},
    HealthTimelinePeriod? period,
    this.periodOrigin = HealthTimelinePeriodPreset.allHistory,
    String? caseId,
    this.professional,
  }) : types = Set.unmodifiable(Set<HealthTimelineType>.of(types)),
       period = period ?? HealthTimelinePeriod(),
       caseId = _trimOrNull(caseId);

  /// Tipos selecionados. Vazio = todos os tipos (sem filtro de tipo).
  final Set<HealthTimelineType> types;

  /// Período estruturado (limites inclusivos, 3A).
  final HealthTimelinePeriod period;

  /// Origem da seleção de período (chip/UI). Não afeta fingerprint da source.
  final HealthTimelinePeriodPreset periodOrigin;

  /// Filtro contextual de caso (não seletor global da página).
  final String? caseId;

  /// Filtro contextual de profissional (não derived de snapshot).
  final HealthTimelineProfessionalFilter? professional;

  static HealthTimelineFilterSelection empty() =>
      HealthTimelineFilterSelection();

  bool get hasTypes => types.isNotEmpty;

  bool get hasPeriod => !period.isUnbounded;

  bool get hasCaseId => caseId != null;

  bool get hasProfessional => professional != null;

  bool get isEmpty => !hasTypes && !hasPeriod && !hasCaseId && !hasProfessional;

  bool get isNotEmpty => !isEmpty;

  /// Contagem semântica do badge: types + period + case + professional.
  int get activeFilterCount {
    var n = 0;
    if (hasTypes) n++;
    if (hasPeriod) n++;
    if (hasCaseId) n++;
    if (hasProfessional) n++;
    return n;
  }

  HealthTimelineFilterSelection copyWith({
    Set<HealthTimelineType>? types,
    HealthTimelinePeriod? period,
    HealthTimelinePeriodPreset? periodOrigin,
    String? caseId,
    bool clearCaseId = false,
    HealthTimelineProfessionalFilter? professional,
    bool clearProfessional = false,
  }) {
    return HealthTimelineFilterSelection(
      types: types ?? this.types,
      period: period ?? this.period,
      periodOrigin: periodOrigin ?? this.periodOrigin,
      caseId: clearCaseId ? null : (caseId ?? this.caseId),
      professional: clearProfessional
          ? null
          : (professional ?? this.professional),
    );
  }

  /// Derivada da query (origem visual: custom se período ativo).
  factory HealthTimelineFilterSelection.fromQuery(HealthTimelineQuery query) {
    final p = query.period;
    return HealthTimelineFilterSelection(
      types: query.types,
      period: p,
      periodOrigin: p.isUnbounded
          ? HealthTimelinePeriodPreset.allHistory
          : HealthTimelinePeriodPreset.custom,
      caseId: query.caseId,
      professional: query.professional,
    );
  }

  HealthTimelineQuery toQuery({
    required String dogId,
    int pageSize = HealthTimelineQuery.defaultPageSize,
  }) {
    return HealthTimelineQuery(
      dogId: dogId,
      types: types,
      period: period,
      caseId: caseId,
      professional: professional,
      pageSize: pageSize,
    );
  }

  /// Igualdade de **query** (sem periodOrigin) — para no-op de setQuery.
  bool queryEquals(HealthTimelineFilterSelection other) {
    if (other.period != period) return false;
    if (other.caseId != caseId) return false;
    if (other.professional != professional) return false;
    if (other.types.length != types.length) return false;
    for (final t in types) {
      if (!other.types.contains(t)) return false;
    }
    return true;
  }

  static String? _trimOrNull(String? value) {
    if (value == null) return null;
    final t = value.trim();
    return t.isEmpty ? null : t;
  }

  @override
  bool operator ==(Object other) {
    if (other is! HealthTimelineFilterSelection) return false;
    if (other.periodOrigin != periodOrigin) return false;
    return queryEquals(other);
  }

  @override
  int get hashCode => Object.hash(
    period,
    periodOrigin,
    caseId,
    professional,
    Object.hashAllUnordered(types),
  );
}
