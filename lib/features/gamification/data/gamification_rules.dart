part of 'gamification_service.dart';

LevelProgress _calculateLevelProgress(int xp) {
  var level = 1;
  var currentLevelFloorXp = 0;
  var xpRequired = 500;
  var remainingXp = xp;

  while (remainingXp >= xpRequired) {
    remainingXp -= xpRequired;
    currentLevelFloorXp += xpRequired;
    level++;
    xpRequired = (xpRequired * 1.25).toInt();
  }

  return LevelProgress(
    level: level,
    currentXp: xp,
    currentLevelFloorXp: currentLevelFloorXp,
    nextLevelXp: currentLevelFloorXp + xpRequired,
  );
}

int _xpForHealthLog(String logType) {
  final normalizedLogType = _normalizeText(logType);

  if (normalizedLogType.contains('vacina') ||
      normalizedLogType.contains('exame') ||
      normalizedLogType.contains('emerg')) {
    return 50;
  }

  if (normalizedLogType.contains('higiene') ||
      normalizedLogType.contains('banho')) {
    return 20;
  }

  return 10;
}

int _xpForTrainingSession({
  required String trainingType,
  required int durationSeconds,
  required bool hasDistraction,
}) {
  var xpAmount = 30.0;

  if (_normalizeText(trainingType).contains('faro')) {
    if (durationSeconds > 0) {
      final blocksOf30Min = durationSeconds / 1800;
      xpAmount = 40.0 * (blocksOf30Min < 1 ? 1 : blocksOf30Min);
    } else {
      xpAmount = 40.0;
    }
  }

  if (hasDistraction) {
    xpAmount *= 1.5;
  }

  return xpAmount.toInt();
}

int _xpForIncident({required String result, required String type}) {
  final normalizedResult = _normalizeText(result);
  final normalizedType = _normalizeText(type);

  if (normalizedResult.contains('apreensao positiva') ||
      normalizedResult.contains('droga apreendida')) {
    return 100;
  }

  if (_isPersonSearchSuccess(normalizedResult, normalizedType)) {
    return 150;
  }

  return 25;
}

bool _hasDrugApreensao(Map<String, dynamic> data) {
  final result = _normalizeText(data['result'] as String? ?? '');
  final outcomes = _normalizedOutcomes(data);

  return result.contains('apreensao positiva') ||
      outcomes.contains('droga apreendida');
}

bool _hasMissingPersonSuccess(Map<String, dynamic> data) {
  final result = _normalizeText(data['result'] as String? ?? '');
  final type = _normalizeText(data['type'] as String? ?? '');
  final outcomes = _normalizedOutcomes(data);

  return outcomes.contains('pessoa localizada') ||
      result.contains('pessoa localizada') ||
      _isPersonSearchSuccess(result, type);
}

bool _isPersonSearchSuccess(String normalizedResult, String normalizedType) {
  final resultIndicatesPersonFound =
      normalizedResult.contains('pessoa localizada') ||
      normalizedResult.contains('localizacao de pessoa') ||
      normalizedResult.contains('localizacao pessoa') ||
      normalizedResult.contains('desaparecido localizado');

  final typeIndicatesPersonSearch =
      normalizedType.contains('busca de pessoa') ||
      normalizedType.contains('desaparecimento') ||
      normalizedType.contains('localizacao de pessoa');

  return resultIndicatesPersonFound ||
      (typeIndicatesPersonSearch && normalizedResult.contains('sucesso'));
}

List<String> _normalizedOutcomes(Map<String, dynamic> data) {
  if (data['outcomes'] is! List) return const <String>[];

  return List<String>.from(
    data['outcomes'] as List,
  ).map(_normalizeText).toList();
}

String _formatProgress({
  required int current,
  required int target,
  required String singular,
  required String plural,
}) {
  final label = target == 1 ? singular : plural;
  return '$current de $target $label';
}

String _normalizeText(String value) {
  const accents = {
    'á': 'a',
    'à': 'a',
    'ã': 'a',
    'â': 'a',
    'ä': 'a',
    'é': 'e',
    'è': 'e',
    'ê': 'e',
    'ë': 'e',
    'í': 'i',
    'ì': 'i',
    'î': 'i',
    'ï': 'i',
    'ó': 'o',
    'ò': 'o',
    'õ': 'o',
    'ô': 'o',
    'ö': 'o',
    'ú': 'u',
    'ù': 'u',
    'û': 'u',
    'ü': 'u',
    'ç': 'c',
  };

  return value.toLowerCase().split('').map((char) {
    return accents[char] ?? char;
  }).join();
}

DateTime? _resolveDate(dynamic primary, [dynamic secondary, dynamic tertiary]) {
  for (final value in [primary, secondary, tertiary]) {
    final resolved = _parseDynamicDate(value);
    if (resolved != null) {
      return resolved;
    }
  }
  return null;
}

DateTime? _parseDynamicDate(dynamic value) {
  if (value == null) return null;
  if (value is Timestamp) return value.toDate();
  if (value is DateTime) return value;
  if (value is String) {
    return DateTime.tryParse(value);
  }
  if (value is num) {
    return DateTime.fromMillisecondsSinceEpoch(value.toInt());
  }
  if (value is Map<String, dynamic> && value['seconds'] is num) {
    return DateTime.fromMillisecondsSinceEpoch(
      (value['seconds'] as num).toInt() * 1000,
    );
  }
  return null;
}

bool _isDateInCurrentWeek(DateTime? date, DateTime weekStart) {
  if (date == null) return false;
  final normalized = DateTime(date.year, date.month, date.day);
  final weekEnd = weekStart.add(const Duration(days: 7));
  return !normalized.isBefore(weekStart) && normalized.isBefore(weekEnd);
}
