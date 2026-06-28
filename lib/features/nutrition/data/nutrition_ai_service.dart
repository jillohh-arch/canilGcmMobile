import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';

/// Estado de "dado novo" do card de nutrição: quando foi a última análise
/// salva e quantos registros entraram desde então.
class NutritionFreshness {
  /// Timestamp da última análise persistida em `nutrition_ai_insights`.
  /// `null` quando o cão ainda não tem nenhuma análise.
  final DateTime? lastAnalysisAt;

  /// Quantidade de registros novos (treinos + pesagens + refeições + eventos
  /// de saúde) com data posterior à última análise.
  final int newRecords;

  const NutritionFreshness({
    required this.lastAnalysisAt,
    required this.newRecords,
  });

  /// Ainda não existe análise anterior — estado de "primeira vez".
  bool get isFirstTime => lastAnalysisAt == null;

  /// Há dado novo desde a última análise.
  bool get hasNewData => lastAnalysisAt != null && newRecords > 0;

  static const empty = NutritionFreshness(lastAnalysisAt: null, newRecords: 0);
}

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
  NutritionAiService({FirebaseFunctions? functions, FirebaseFirestore? firestore})
    : _functions =
          functions ??
          FirebaseFunctions.instanceFor(region: 'southamerica-east1'),
      _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFunctions _functions;
  final FirebaseFirestore _firestore;

  /// Lê a última análise salva e conta quantos registros novos entraram desde
  /// então. Usa `count()` agregado do Firestore — não traz os documentos
  /// inteiros, só os totais por coleção.
  Future<NutritionFreshness> loadFreshness(String dogId) async {
    final dogRef = _firestore.collection('dogs').doc(dogId);

    final lastInsightSnap = await dogRef
        .collection('nutrition_ai_insights')
        .orderBy('created_at', descending: true)
        .limit(1)
        .get();

    if (lastInsightSnap.docs.isEmpty) {
      return NutritionFreshness.empty;
    }

    final lastAnalysisAt =
        (lastInsightSnap.docs.first.data()['created_at'] as Timestamp?)
            ?.toDate();
    if (lastAnalysisAt == null) {
      // Análise salva sem timestamp resolvido (serverTimestamp pendente):
      // trata como sem dado novo para não falsear o contador.
      return const NutritionFreshness(lastAnalysisAt: null, newRecords: 0);
    }

    final since = Timestamp.fromDate(lastAnalysisAt);
    // ponytail: contagem leve via count() agregado; cada coleção usa seu
    // próprio campo de data. Refinar se precisar de precisão por tipo.
    final counts = await Future.wait([
      _countSince(dogRef.collection('feeding_events'), 'fed_at', since),
      _countSince(dogRef.collection('weight_records'), 'measured_at', since),
      _countSince(dogRef.collection('health_events'), 'date', since),
      _countTrainingSince(dogId, since),
    ]);

    final total = counts.fold<int>(0, (acc, value) => acc + value);
    return NutritionFreshness(
      lastAnalysisAt: lastAnalysisAt,
      newRecords: total,
    );
  }

  Future<int> _countSince(
    Query<Map<String, dynamic>> collection,
    String dateField,
    Timestamp since,
  ) async {
    try {
      final agg = await collection
          .where(dateField, isGreaterThan: since)
          .count()
          .get();
      return agg.count ?? 0;
    } catch (_) {
      // Coleção ausente / índice indisponível: não bloquear o card.
      return 0;
    }
  }

  Future<int> _countTrainingSince(String dogId, Timestamp since) async {
    // Treinos ficam tanto na subcoleção do cão quanto na raiz (dogId/dog_id).
    final dogRef = _firestore.collection('dogs').doc(dogId);
    final results = await Future.wait([
      _countSince(dogRef.collection('training_sessions'), 'date', since),
      _countSince(
        _firestore
            .collection('training_sessions')
            .where('dogId', isEqualTo: dogId),
        'date',
        since,
      ),
    ]);
    return results.fold<int>(0, (acc, value) => acc + value);
  }

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
