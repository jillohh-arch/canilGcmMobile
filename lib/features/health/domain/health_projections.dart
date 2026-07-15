import 'health_v1_enums_ext.dart';
import 'health_v1_models.dart';

import 'operational_restriction.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Projeções read-only (ADR-004 §13; Domain Model §2.14 e §3.2; ADR-005 §12).
// Não são fonte canônica. Não recalculam, não invocam policy, não acedem Firestore.
//
// Separação de contratos de timestamp (não equivalentes):
// - readiness_updated_at → Domain Model §2.14; ADR-004
// - last_evaluated_at    → ADR-005 §12
// - updated_at           → ADR-004 health_summary (não modelado aqui)
// - readiness_label / readiness_reason → ADR-005 §12
// - evaluated_by         → ADR-005 §12: "system" | "function_v1"
// ─────────────────────────────────────────────────────────────────────────────

/// Item read-only da timeline clínica (ADR-004 §13; Domain Model §3.1).
final class HealthTimelineItem {
  const HealthTimelineItem({
    required this.id,
    required this.timelineType,
    required this.occurredAt,
    required this.recordedAt,
    required this.title,
    this.subtitle,
    this.caseId,
    this.caseTitle,
    required this.sourceCollection,
    required this.sourceId,
    this.recordedBy,
    this.professionalName,
    this.operationalImpactLevel,
    this.hasAttachments = false,
    this.status,
    this.hasAmendments = false,
    this.amendmentCount = 0,
    this.lastAmendedAt,
    this.legacySource,
    this.legacyId,
  }) : assert(amendmentCount >= 0, 'amendment_count não pode ser negativo');

  final String id;
  final HealthTimelineType timelineType;
  final DateTime occurredAt;
  final DateTime recordedAt;
  final String title;
  final String? subtitle;
  final String? caseId;
  final String? caseTitle;
  final String sourceCollection;
  final String sourceId;
  final RecordedBy? recordedBy;
  final String? professionalName;
  final OperationalImpactLevel? operationalImpactLevel;
  final bool hasAttachments;
  final String? status;
  final bool hasAmendments;
  final int amendmentCount;
  final DateTime? lastAmendedAt;
  final String? legacySource;
  final String? legacyId;
}

/// Fatos documentados de completude (ADR-005 §12 `data_completeness`).
final class ReadinessDataCompleteness {
  const ReadinessDataCompleteness({
    this.hasRecentWeight = false,
    this.hasActiveNutrition = false,
    this.hasVaccinationCurrent = false,
    this.hasRecentExam = false,
  });

  final bool hasRecentWeight;
  final bool hasActiveNutrition;
  final bool hasVaccinationCurrent;
  final bool hasRecentExam;

  @override
  bool operator ==(Object other) =>
      other is ReadinessDataCompleteness &&
      other.hasRecentWeight == hasRecentWeight &&
      other.hasActiveNutrition == hasActiveNutrition &&
      other.hasVaccinationCurrent == hasVaccinationCurrent &&
      other.hasRecentExam == hasRecentExam;

  @override
  int get hashCode => Object.hash(
    hasRecentWeight,
    hasActiveNutrition,
    hasVaccinationCurrent,
    hasRecentExam,
  );
}

/// Contagem agregada de restrições ativas por nível (ADR-005 §12).
/// Não permite valores negativos (validação em runtime).
final class ReadinessRestrictionCount {
  ReadinessRestrictionCount({
    this.absolute = 0,
    this.partial = 0,
    this.attention = 0,
  }) {
    if (absolute < 0 || partial < 0 || attention < 0) {
      throw const HealthDomainException(
        'invalid_restriction_count',
        'restriction_count não aceita valores negativos',
      );
    }
  }

  final int absolute;
  final int partial;
  final int attention;

  int get total => absolute + partial + attention;

  @override
  bool operator ==(Object other) =>
      other is ReadinessRestrictionCount &&
      other.absolute == absolute &&
      other.partial == partial &&
      other.attention == attention;

  @override
  int get hashCode => Object.hash(absolute, partial, attention);
}

/// Resumo de restrição ativa na projeção (ADR-005 §12).
/// Preserva `activities_restricted`; não expõe ProfessionalIdentity completa.
final class ActiveRestrictionSummary {
  ActiveRestrictionSummary({
    required this.id,
    required this.level,
    required this.category,
    this.description,
    required this.since,
    this.expectedEnd,
    List<String> activitiesRestricted = const [],
  }) : activitiesRestricted = List.unmodifiable(
         List<String>.of(activitiesRestricted),
       );

  final String id;
  final RestrictionLevel level;
  final RestrictionCategory category;
  final String? description;
  final DateTime since;
  final DateTime? expectedEnd;

  /// Cópia imutável própria — alias da lista do caller não afeta o resumo.
  final List<String> activitiesRestricted;

  @override
  bool operator ==(Object other) {
    if (other is! ActiveRestrictionSummary) return false;
    if (other.id != id) return false;
    if (other.level != level) return false;
    if (other.category != category) return false;
    if (other.description != description) return false;
    if (other.since != since) return false;
    if (other.expectedEnd != expectedEnd) return false;
    if (other.activitiesRestricted.length != activitiesRestricted.length) {
      return false;
    }
    for (var i = 0; i < activitiesRestricted.length; i++) {
      if (other.activitiesRestricted[i] != activitiesRestricted[i]) {
        return false;
      }
    }
    return true;
  }

  @override
  int get hashCode => Object.hash(
    id,
    level,
    category,
    description,
    since,
    expectedEnd,
    Object.hashAll(activitiesRestricted),
  );
}

/// Valores documentados de `evaluated_by` (ADR-005 §12).
const Set<String> kDocumentedEvaluatedBy = {'system', 'function_v1'};

/// Projeção read-only do subconjunto de prontidão (ADR-005 §12 + Domain Model §2.14).
///
/// Invariantes enforced no construtor:
/// - schemaVersion > 0
/// - evaluatedBy ∈ {system, function_v1} (ADR-005 §12)
/// - readinessLabel / readinessReason não vazios (campos de exibição ADR-005)
/// - restrictionCount sem negativos e **consistente** com activeRestrictionsSummary
/// - coleções imutáveis com cópia defensiva
final class ReadinessSnapshot {
  ReadinessSnapshot({
    required this.status,
    required String readinessLabel,
    required String readinessReason,
    required this.readinessUpdatedAt,
    required this.lastEvaluatedAt,
    required String evaluatedBy,
    required this.schemaVersion,
    List<ActiveRestrictionSummary> activeRestrictionsSummary = const [],
    ReadinessRestrictionCount? restrictionCount,
    this.dataCompleteness = const ReadinessDataCompleteness(),
  }) : readinessLabel = readinessLabel.trim(),
       readinessReason = readinessReason.trim(),
       evaluatedBy = evaluatedBy.trim(),
       activeRestrictionsSummary = List.unmodifiable(
         List<ActiveRestrictionSummary>.of(activeRestrictionsSummary),
       ),
       restrictionCount =
           restrictionCount ?? _countFrom(activeRestrictionsSummary) {
    if (this.schemaVersion <= 0) {
      throw const HealthDomainException(
        'invalid_schema_version',
        'schema_version deve ser positivo',
      );
    }
    if (this.readinessLabel.isEmpty) {
      throw const HealthDomainException(
        'missing_readiness_label',
        'readiness_label é obrigatório (ADR-005 §12)',
      );
    }
    if (this.readinessReason.isEmpty) {
      throw const HealthDomainException(
        'missing_readiness_reason',
        'readiness_reason é obrigatório (ADR-005 §12)',
      );
    }
    if (!kDocumentedEvaluatedBy.contains(this.evaluatedBy)) {
      throw HealthDomainException(
        'invalid_evaluated_by',
        'evaluated_by deve ser um de ${kDocumentedEvaluatedBy.join(" | ")} '
            '(ADR-005 §12)',
      );
    }
    // Contagens negativas já são barradas no assert do value object; reforço
    // runtime para construção via factory sem const asserts em release.
    if (this.restrictionCount.absolute < 0 ||
        this.restrictionCount.partial < 0 ||
        this.restrictionCount.attention < 0) {
      throw const HealthDomainException(
        'invalid_restriction_count',
        'restriction_count não aceita valores negativos',
      );
    }
    final derived = _countFrom(this.activeRestrictionsSummary);
    if (this.restrictionCount != derived) {
      throw const HealthDomainException(
        'inconsistent_restriction_count',
        'restriction_count deve refletir active_restrictions por nível',
      );
    }
  }

  /// `readiness_status` (ADR-005 §12; Domain Model §2.14).
  final ReadinessStatus status;

  /// `readiness_label` (ADR-005 §12).
  final String readinessLabel;

  /// `readiness_reason` (ADR-005 §12).
  final String readinessReason;

  /// `readiness_updated_at` (Domain Model §2.14; ADR-004).
  final DateTime readinessUpdatedAt;

  /// `last_evaluated_at` (ADR-005 §12). Distinto de [readinessUpdatedAt].
  final DateTime lastEvaluatedAt;

  /// `evaluated_by` — `"system" | "function_v1"` (ADR-005 §12).
  final String evaluatedBy;

  final int schemaVersion;

  /// Cópia imutável própria.
  final List<ActiveRestrictionSummary> activeRestrictionsSummary;
  final ReadinessRestrictionCount restrictionCount;
  final ReadinessDataCompleteness dataCompleteness;

  static ReadinessRestrictionCount _countFrom(
    List<ActiveRestrictionSummary> summaries,
  ) {
    var absolute = 0;
    var partial = 0;
    var attention = 0;
    for (final r in summaries) {
      switch (r.level) {
        case RestrictionLevel.absolute:
          absolute++;
          break;
        case RestrictionLevel.partial:
          partial++;
          break;
        case RestrictionLevel.attention:
          attention++;
          break;
      }
    }
    return ReadinessRestrictionCount(
      absolute: absolute,
      partial: partial,
      attention: attention,
    );
  }

  /// Constrói a partir de restrições ativas, derivando contagem e summaries.
  factory ReadinessSnapshot.fromActiveRestrictions({
    required ReadinessStatus status,
    required String readinessLabel,
    required String readinessReason,
    required DateTime readinessUpdatedAt,
    required DateTime lastEvaluatedAt,
    required String evaluatedBy,
    required int schemaVersion,
    required List<OperationalRestriction> activeRestrictions,
    ReadinessDataCompleteness dataCompleteness =
        const ReadinessDataCompleteness(),
  }) {
    final summaries = activeRestrictions
        .map(
          (r) => ActiveRestrictionSummary(
            id: r.id,
            level: r.level,
            category: r.category,
            description: r.description,
            since: r.issuedAt,
            expectedEnd: r.expectedEnd,
            activitiesRestricted: r.activitiesRestricted,
          ),
        )
        .toList(growable: false);
    return ReadinessSnapshot(
      status: status,
      readinessLabel: readinessLabel,
      readinessReason: readinessReason,
      readinessUpdatedAt: readinessUpdatedAt,
      lastEvaluatedAt: lastEvaluatedAt,
      evaluatedBy: evaluatedBy,
      schemaVersion: schemaVersion,
      activeRestrictionsSummary: summaries,
      // Contagem derivada internamente — única fonte de verdade.
      dataCompleteness: dataCompleteness,
    );
  }
}
