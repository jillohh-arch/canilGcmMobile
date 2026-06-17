import 'package:cloud_functions/cloud_functions.dart';

class NutritionAiInsight {
  final String insightId;
  final String promptVersion;
  final String model;
  final bool usedAi;
  final int periodDays;
  final String summary;
  final String recommendationLevel;
  final String foodAdjustment;
  final List<String> supplementNotes;
  final List<String> hydrationNotes;
  final List<String> operationalFactors;
  final List<String> dataGaps;
  final List<String> veterinaryWarnings;
  final List<String> nextActions;
  final Map<String, dynamic> sourceSummary;

  const NutritionAiInsight({
    required this.insightId,
    required this.promptVersion,
    required this.model,
    required this.usedAi,
    required this.periodDays,
    required this.summary,
    required this.recommendationLevel,
    required this.foodAdjustment,
    required this.supplementNotes,
    required this.hydrationNotes,
    required this.operationalFactors,
    required this.dataGaps,
    required this.veterinaryWarnings,
    required this.nextActions,
    required this.sourceSummary,
  });

  factory NutritionAiInsight.fromMap(Map<dynamic, dynamic> data) {
    return NutritionAiInsight(
      insightId: data['insight_id']?.toString() ?? '',
      promptVersion: data['prompt_version']?.toString() ?? '',
      model: data['model']?.toString() ?? '',
      usedAi: data['used_ai'] == true,
      periodDays: _intValue(data['period_days']) ?? 30,
      summary: data['summary']?.toString() ?? '',
      recommendationLevel:
          data['recommendation_level']?.toString() ?? 'manter_monitorando',
      foodAdjustment: data['food_adjustment']?.toString() ?? '',
      supplementNotes: _stringList(data['supplement_notes']),
      hydrationNotes: _stringList(data['hydration_notes']),
      operationalFactors: _stringList(data['operational_factors']),
      dataGaps: _stringList(data['data_gaps']),
      veterinaryWarnings: _stringList(data['veterinary_warnings']),
      nextActions: _stringList(data['next_actions']),
      sourceSummary:
          (data['source_summary'] as Map<dynamic, dynamic>?)?.map(
            (key, value) => MapEntry(key.toString(), value),
          ) ??
          const {},
    );
  }

  static int? _intValue(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.round();
    if (value is String) return int.tryParse(value);
    return null;
  }

  static List<String> _stringList(dynamic value) {
    if (value is! List) return const [];
    return value
        .map((item) => item.toString().trim())
        .where((item) => item.isNotEmpty)
        .toList();
  }
}

class NutritionAiService {
  NutritionAiService({FirebaseFunctions? functions})
    : _functions =
          functions ??
          FirebaseFunctions.instanceFor(region: 'southamerica-east1');

  final FirebaseFunctions _functions;

  Future<NutritionAiInsight> generateInsight({
    required String dogId,
    required int periodDays,
  }) async {
    final callable = _functions.httpsCallable('generateNutritionAiInsight');
    final response = await callable.call<Map<dynamic, dynamic>>({
      'dog_id': dogId,
      'period_days': periodDays,
    });
    final insight = NutritionAiInsight.fromMap(response.data);
    if (insight.summary.trim().isEmpty &&
        insight.foodAdjustment.trim().isEmpty) {
      throw StateError('A análise retornou vazia. Tente novamente.');
    }
    return insight;
  }
}
