import 'package:canil_gcm/features/health/presentation/summary/health_summary_block_models.dart';
import 'package:canil_gcm/features/health/presentation/summary/health_summary_section_status.dart';
import 'package:canil_gcm/features/health/presentation/summary/health_summary_source_metadata.dart';

/// Read model composto do Resumo Health v1.
///
/// Independente do schema Firestore. Cada bloco usa [HealthSummarySectionData]
/// para suportar loading/available/notRecorded/unavailable em paralelo.
///
/// [dogId] é obrigatório e identifica a qual K9 o payload pertence.
final class HealthSummaryViewData {
  HealthSummaryViewData({
    required String dogId,
    this.readiness = const HealthSummarySectionData.loading(),
    this.weight = const HealthSummarySectionData.loading(),
    this.vaccination = const HealthSummarySectionData.loading(),
    this.treatments = const HealthSummarySectionData.loading(),
    this.attention = const HealthSummarySectionData.loading(),
    this.nutritionToday = const HealthSummarySectionData.loading(),
    this.weightTrend = const HealthSummarySectionData.loading(),
    this.recentRecords = const HealthSummarySectionData.loading(),
    this.metadata = const HealthSummarySourceMetadata(),
  }) : dogId = dogId.trim() {
    if (this.dogId.isEmpty) {
      throw ArgumentError.value(dogId, 'dogId', 'dogId não pode ser vazio');
    }
  }

  final String dogId;

  final HealthSummarySectionData<HealthSummaryReadinessView> readiness;
  final HealthSummarySectionData<HealthSummaryWeightView> weight;
  final HealthSummarySectionData<HealthSummaryVaccinationView> vaccination;
  final HealthSummarySectionData<HealthSummaryTreatmentsView> treatments;
  final HealthSummarySectionData<HealthSummaryAttentionView> attention;
  final HealthSummarySectionData<HealthSummaryNutritionTodayView>
  nutritionToday;
  final HealthSummarySectionData<HealthSummaryWeightTrendView> weightTrend;
  final HealthSummarySectionData<HealthSummaryRecentRecordsView> recentRecords;
  final HealthSummarySourceMetadata metadata;

  HealthSummaryViewData copyWith({
    HealthSummarySectionData<HealthSummaryReadinessView>? readiness,
    HealthSummarySectionData<HealthSummaryWeightView>? weight,
    HealthSummarySectionData<HealthSummaryVaccinationView>? vaccination,
    HealthSummarySectionData<HealthSummaryTreatmentsView>? treatments,
    HealthSummarySectionData<HealthSummaryAttentionView>? attention,
    HealthSummarySectionData<HealthSummaryNutritionTodayView>? nutritionToday,
    HealthSummarySectionData<HealthSummaryWeightTrendView>? weightTrend,
    HealthSummarySectionData<HealthSummaryRecentRecordsView>? recentRecords,
    HealthSummarySourceMetadata? metadata,
  }) {
    return HealthSummaryViewData(
      dogId: dogId,
      readiness: readiness ?? this.readiness,
      weight: weight ?? this.weight,
      vaccination: vaccination ?? this.vaccination,
      treatments: treatments ?? this.treatments,
      attention: attention ?? this.attention,
      nutritionToday: nutritionToday ?? this.nutritionToday,
      weightTrend: weightTrend ?? this.weightTrend,
      recentRecords: recentRecords ?? this.recentRecords,
      metadata: metadata ?? this.metadata,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is HealthSummaryViewData &&
      other.dogId == dogId &&
      other.readiness == readiness &&
      other.weight == weight &&
      other.vaccination == vaccination &&
      other.treatments == treatments &&
      other.attention == attention &&
      other.nutritionToday == nutritionToday &&
      other.weightTrend == weightTrend &&
      other.recentRecords == recentRecords &&
      other.metadata == metadata;

  @override
  int get hashCode => Object.hash(
    dogId,
    readiness,
    weight,
    vaccination,
    treatments,
    attention,
    nutritionToday,
    weightTrend,
    recentRecords,
    metadata,
  );
}
