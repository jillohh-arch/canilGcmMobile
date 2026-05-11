class OccurrencePayloadFieldWriter {
  const OccurrencePayloadFieldWriter._();

  static void putIfNotEmpty(
    Map<String, dynamic> target,
    String key,
    String value,
  ) {
    final trimmed = value.trim();
    if (trimmed.isNotEmpty) {
      target[key] = trimmed;
    }
  }

  static String text(dynamic value) {
    if (value == null) return '';
    if (value is String) return value.trim();

    final dynamic dynamicValue = value;
    final Object? textValue;
    try {
      textValue = dynamicValue.text;
    } catch (_) {
      return value.toString().trim();
    }

    return textValue is String ? textValue.trim() : '';
  }
}
