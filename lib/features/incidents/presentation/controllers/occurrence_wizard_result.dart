class OccurrenceWizardResult {
  final String report;
  final List<String> results;
  final Map<String, dynamic> details;

  const OccurrenceWizardResult({
    required this.report,
    required this.results,
    required this.details,
  });

  factory OccurrenceWizardResult.fromMap(Map<String, dynamic> data) {
    return OccurrenceWizardResult(
      report: (data['report'] ?? '').toString(),
      results: List<String>.from(data['results'] ?? const []),
      details: data['details'] is Map
          ? Map<String, dynamic>.from(data['details'] as Map)
          : <String, dynamic>{},
    );
  }

  bool get successful {
    return !(results.contains('Nada Localizado') ||
        results.contains('Sem constatação'));
  }

  bool containsResult(String result) {
    return results.contains(result);
  }

  String detail(String key) {
    return (details[key] ?? '').toString().trim();
  }
}
