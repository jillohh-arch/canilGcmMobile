class Vehicle {
  final String id;
  final String name;
  final String prefix;
  final String modelName;
  final int crewSize;
  final String unit;
  final bool active;

  const Vehicle({
    required this.id,
    required this.name,
    required this.prefix,
    required this.modelName,
    required this.crewSize,
    required this.unit,
    required this.active,
  });

  String get label {
    final pieces = [
      if (name.trim().isNotEmpty) name.trim(),
      if (prefix.trim().isNotEmpty) prefix.trim(),
    ];
    return pieces.isEmpty ? id : pieces.join(' ');
  }

  factory Vehicle.fromJson(Map<String, dynamic> json, String id) {
    final legacyLabel = _parseString(json['label']);
    final parsedName = _parseString(json['name']);
    final parsedPrefix = _parseString(json['prefix']);

    return Vehicle(
      id: id,
      name: parsedName ?? _nameFromLabel(legacyLabel) ?? 'Viatura',
      prefix: parsedPrefix ?? _prefixFromLabel(legacyLabel) ?? id,
      modelName: _parseString(json['model']) ?? '',
      crewSize:
          _parseInt(json['crew_size']) ?? _parseInt(json['crewSize']) ?? 1,
      unit: _parseString(json['unit']) ?? 'Limeira/SP',
      active: _parseBool(json['active']) ?? true,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'prefix': prefix,
      'model': modelName,
      'crew_size': crewSize,
      'unit': unit,
      'active': active,
    };
  }

  static String? _parseString(dynamic value) {
    if (value == null) return null;
    final text = value.toString().trim();
    return text.isEmpty ? null : text;
  }

  static int? _parseInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.round();
    if (value is String) return int.tryParse(value);
    return null;
  }

  static bool? _parseBool(dynamic value) {
    if (value is bool) return value;
    if (value is String) {
      final normalized = value.trim().toLowerCase();
      if (normalized == 'true' || normalized == '1' || normalized == 'sim') {
        return true;
      }
      if (normalized == 'false' || normalized == '0' || normalized == 'nao') {
        return false;
      }
    }
    return null;
  }

  static String? _nameFromLabel(String? label) {
    if (label == null) return null;
    final parts = label.trim().split(RegExp(r'\s+'));
    if (parts.length <= 1) return label;
    return parts.take(parts.length - 1).join(' ');
  }

  static String? _prefixFromLabel(String? label) {
    if (label == null) return null;
    final parts = label.trim().split(RegExp(r'\s+'));
    if (parts.length <= 1) return null;
    return parts.last;
  }
}
