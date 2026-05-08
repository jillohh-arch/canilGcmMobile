part 'occurrence_nature_seed.dart';

class OccurrenceNature {
  final String code;
  final String name;
  final String group;
  final bool active;

  const OccurrenceNature({
    required this.code,
    required this.name,
    required this.group,
    this.active = true,
  });

  factory OccurrenceNature.fromJson(Map<String, dynamic> json) {
    return OccurrenceNature(
      code: json['code']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      group: json['group']?.toString() ?? '',
      active: json['active'] as bool? ?? true,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'code': code,
      'name': name,
      'group': group,
      'active': active,
      'searchText': searchableText,
    };
  }

  String get label => code.isEmpty ? name : '$code - $name';

  String get searchableText => normalizeForSearch('$code $name $group');

  bool matches(String query) {
    final normalized = normalizeForSearch(query);
    if (normalized.isEmpty) return true;
    return normalized
        .split(' ')
        .where((token) => token.isNotEmpty)
        .every(searchableText.contains);
  }

  static String normalizeForSearch(String value) {
    var normalized = value.toLowerCase().trim();
    const replacements = {
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
      'ñ': 'n',
    };

    replacements.forEach((from, to) {
      normalized = normalized.replaceAll(from, to);
    });

    return normalized
        .replaceAll(RegExp(r'[^a-z0-9]+'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }
}
