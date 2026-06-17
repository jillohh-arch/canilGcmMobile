import 'package:cloud_functions/cloud_functions.dart';

class OccurrenceAiDraft {
  final String draftId;
  final String draftText;
  final List<String> attentionPoints;
  final Map<String, dynamic> sourceSummary;
  final bool usedAi;
  final String model;
  final String promptVersion;

  const OccurrenceAiDraft({
    required this.draftId,
    required this.draftText,
    required this.attentionPoints,
    required this.sourceSummary,
    required this.usedAi,
    required this.model,
    required this.promptVersion,
  });

  factory OccurrenceAiDraft.fromMap(Map<dynamic, dynamic> data) {
    return OccurrenceAiDraft(
      draftId: data['draft_id']?.toString() ?? '',
      draftText: data['draft_text']?.toString() ?? '',
      attentionPoints:
          (data['attention_points'] as List<dynamic>?)
              ?.map((item) => item.toString())
              .where((item) => item.trim().isNotEmpty)
              .toList() ??
          const [],
      sourceSummary:
          (data['source_summary'] as Map<dynamic, dynamic>?)?.map(
            (key, value) => MapEntry(key.toString(), value),
          ) ??
          const {},
      usedAi: data['used_ai'] == true,
      model: data['model']?.toString() ?? '',
      promptVersion: data['prompt_version']?.toString() ?? '',
    );
  }
}

class OccurrenceAiService {
  OccurrenceAiService({FirebaseFunctions? functions})
    : _functions =
          functions ??
          FirebaseFunctions.instanceFor(region: 'southamerica-east1');

  final FirebaseFunctions _functions;

  Future<OccurrenceAiDraft> generateInstitutionalDraft({
    required String occurrenceId,
    required String rawReport,
  }) async {
    final callable = _functions.httpsCallable('generateOccurrenceAiDraft');
    final response = await callable.call<Map<dynamic, dynamic>>({
      'occurrence_id': occurrenceId,
      'raw_report': rawReport,
    });
    final draft = OccurrenceAiDraft.fromMap(response.data);
    if (draft.draftText.trim().isEmpty) {
      throw StateError('A minuta retornou vazia. Tente novamente.');
    }
    return draft;
  }
}
