import 'package:canil_gcm/features/health/domain/health_v1_enums_ext.dart';

/// Prontidão para o Resumo — **não calcula** status clínico.
///
/// Reutiliza [ReadinessStatus] canônico (exatamente cinco estados).
final class HealthSummaryReadinessView {
  const HealthSummaryReadinessView({
    required this.status,
    this.reason,
    this.restrictionSummaries = const [],
    this.updatedAt,
  });

  /// Status oficial de prontidão (domínio).
  final ReadinessStatus status;

  /// Texto de apresentação (reason/subtitle), sem semântica clínica nova.
  final String? reason;

  /// Resumos curtos de restrições para UI (não são entidades de domínio).
  final List<String> restrictionSummaries;

  final DateTime? updatedAt;

  @override
  bool operator ==(Object other) =>
      other is HealthSummaryReadinessView &&
      other.status == status &&
      other.reason == reason &&
      _listEq(other.restrictionSummaries, restrictionSummaries) &&
      other.updatedAt == updatedAt;

  @override
  int get hashCode => Object.hash(
    status,
    reason,
    Object.hashAll(restrictionSummaries),
    updatedAt,
  );
}

/// Peso atual resumido.
final class HealthSummaryWeightView {
  HealthSummaryWeightView({
    required this.weightKg,
    this.measuredAt,
    this.bodyConditionScore,
  }) {
    if (!weightKg.isFinite || weightKg < 0) {
      throw ArgumentError.value(
        weightKg,
        'weightKg',
        'peso deve ser finito e não negativo',
      );
    }
  }

  final double weightKg;
  final DateTime? measuredAt;

  /// Escore corporal quando existir (apresentação; sem cálculo clínico).
  final String? bodyConditionScore;

  @override
  bool operator ==(Object other) =>
      other is HealthSummaryWeightView &&
      other.weightKg == weightKg &&
      other.measuredAt == measuredAt &&
      other.bodyConditionScore == bodyConditionScore;

  @override
  int get hashCode => Object.hash(weightKg, measuredAt, bodyConditionScore);
}

/// Vacinação resumida (sem vigência calculada nesta fase).
final class HealthSummaryVaccinationView {
  const HealthSummaryVaccinationView({
    this.summaryLabel,
    this.lastRecordLabel,
    this.nextDueAt,
  });

  /// Situação resumida para exibição (ex.: "Em dia").
  final String? summaryLabel;
  final String? lastRecordLabel;
  final DateTime? nextDueAt;

  @override
  bool operator ==(Object other) =>
      other is HealthSummaryVaccinationView &&
      other.summaryLabel == summaryLabel &&
      other.lastRecordLabel == lastRecordLabel &&
      other.nextDueAt == nextDueAt;

  @override
  int get hashCode => Object.hash(summaryLabel, lastRecordLabel, nextDueAt);
}

/// Tratamentos ativos resumidos.
final class HealthSummaryTreatmentsView {
  HealthSummaryTreatmentsView({
    required this.activeProtocolCount,
    this.primarySummary,
  }) {
    if (activeProtocolCount < 0) {
      throw ArgumentError.value(
        activeProtocolCount,
        'activeProtocolCount',
        'não pode ser negativo',
      );
    }
  }

  final int activeProtocolCount;
  final String? primarySummary;

  @override
  bool operator ==(Object other) =>
      other is HealthSummaryTreatmentsView &&
      other.activeProtocolCount == activeProtocolCount &&
      other.primarySummary == primarySummary;

  @override
  int get hashCode => Object.hash(activeProtocolCount, primarySummary);
}

/// Item de atenção prioritária do Resumo (sem navegação nesta fase).
final class HealthSummaryAttentionItem {
  const HealthSummaryAttentionItem({
    required this.id,
    required this.title,
    this.subtitle,
    this.destinationHint,
  });

  final String id;
  final String title;
  final String? subtitle;

  /// Dica opcional de destino futuro (ex.: "agenda"); a 2B não navega.
  final String? destinationHint;

  @override
  bool operator ==(Object other) =>
      other is HealthSummaryAttentionItem &&
      other.id == id &&
      other.title == title &&
      other.subtitle == subtitle &&
      other.destinationHint == destinationHint;

  @override
  int get hashCode => Object.hash(id, title, subtitle, destinationHint);
}

/// Lista de atenções do Resumo.
final class HealthSummaryAttentionView {
  const HealthSummaryAttentionView({this.items = const []});

  final List<HealthSummaryAttentionItem> items;

  int get count => items.length;

  @override
  bool operator ==(Object other) =>
      other is HealthSummaryAttentionView && _listEq(other.items, items);

  @override
  int get hashCode => Object.hashAll(items);
}

/// Alimentação de hoje (sem integração Nutrition).
final class HealthSummaryNutritionTodayView {
  const HealthSummaryNutritionTodayView({
    this.consumedAmount,
    this.offeredAmount,
    this.plannedAmount,
    this.mealsRecorded,
    this.mealsPlanned,
    this.unitLabel,
  });

  final double? consumedAmount;
  final double? offeredAmount;
  final double? plannedAmount;
  final int? mealsRecorded;
  final int? mealsPlanned;
  final String? unitLabel;

  @override
  bool operator ==(Object other) =>
      other is HealthSummaryNutritionTodayView &&
      other.consumedAmount == consumedAmount &&
      other.offeredAmount == offeredAmount &&
      other.plannedAmount == plannedAmount &&
      other.mealsRecorded == mealsRecorded &&
      other.mealsPlanned == mealsPlanned &&
      other.unitLabel == unitLabel;

  @override
  int get hashCode => Object.hash(
    consumedAmount,
    offeredAmount,
    plannedAmount,
    mealsRecorded,
    mealsPlanned,
    unitLabel,
  );
}

/// Ponto mínimo para evolução de peso (sem widget de gráfico).
final class HealthSummaryWeightPoint {
  const HealthSummaryWeightPoint({required this.at, required this.weightKg});

  final DateTime at;
  final double weightKg;

  @override
  bool operator ==(Object other) =>
      other is HealthSummaryWeightPoint &&
      other.at == at &&
      other.weightKg == weightKg;

  @override
  int get hashCode => Object.hash(at, weightKg);
}

/// Evolução do peso para o Resumo.
final class HealthSummaryWeightTrendView {
  const HealthSummaryWeightTrendView({
    this.points = const [],
    this.targetWeightKg,
    this.bodyConditionScore,
  });

  final List<HealthSummaryWeightPoint> points;
  final double? targetWeightKg;
  final String? bodyConditionScore;

  @override
  bool operator ==(Object other) =>
      other is HealthSummaryWeightTrendView &&
      _listEq(other.points, points) &&
      other.targetWeightKg == targetWeightKg &&
      other.bodyConditionScore == bodyConditionScore;

  @override
  int get hashCode =>
      Object.hash(Object.hashAll(points), targetWeightKg, bodyConditionScore);
}

/// Registro recente resumido (não é timeline completa).
final class HealthSummaryRecentRecordView {
  const HealthSummaryRecentRecordView({
    required this.id,
    required this.type,
    required this.title,
    this.subtitle,
    this.occurredAt,
  });

  final String id;
  final String type;
  final String title;
  final String? subtitle;
  final DateTime? occurredAt;

  @override
  bool operator ==(Object other) =>
      other is HealthSummaryRecentRecordView &&
      other.id == id &&
      other.type == type &&
      other.title == title &&
      other.subtitle == subtitle &&
      other.occurredAt == occurredAt;

  @override
  int get hashCode => Object.hash(id, type, title, subtitle, occurredAt);
}

/// Lista curta de registros recentes.
final class HealthSummaryRecentRecordsView {
  const HealthSummaryRecentRecordsView({this.items = const []});

  final List<HealthSummaryRecentRecordView> items;

  @override
  bool operator ==(Object other) =>
      other is HealthSummaryRecentRecordsView && _listEq(other.items, items);

  @override
  int get hashCode => Object.hashAll(items);
}

bool _listEq<T>(List<T> a, List<T> b) {
  if (identical(a, b)) return true;
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
