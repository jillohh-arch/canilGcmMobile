import 'package:canil_gcm/core/utils/firestore_date.dart';

class TrainingHubData {
  final List<TrainingSpecialtyModel> specialties;
  final List<TrainingGeneralTypeModel> generalTrainings;
  final List<TrainingHubSession> recentSessions;
  final int trainingsThisWeek;
  final String lastTrainingLabel;
  final String suggestedFocus;

  const TrainingHubData({
    required this.specialties,
    required this.generalTrainings,
    required this.recentSessions,
    required this.trainingsThisWeek,
    required this.lastTrainingLabel,
    required this.suggestedFocus,
  });
}

class TrainingSpecialtyModel {
  final String id;
  final String dogId;
  final String name;
  final String status;
  final DateTime? lastTrainingDate;
  final int progressPercentage;
  final List<TrainingSubAreaModel> subAreas;

  const TrainingSpecialtyModel({
    required this.id,
    required this.dogId,
    required this.name,
    required this.status,
    this.lastTrainingDate,
    required this.progressPercentage,
    this.subAreas = const [],
  });

  factory TrainingSpecialtyModel.fromJson(
    Map<String, dynamic> json,
    String docId,
  ) {
    final rawName =
        _readString(json, const ['name', 'title', 'label', 'type']) ??
        'Especialidade';
    final subAreas = _readSubAreas(json);

    return TrainingSpecialtyModel(
      id: docId,
      dogId: _readString(json, const ['dogId', 'dog_id', 'caoId']) ?? '',
      name: normalizeTrainingLabel(rawName),
      status: _readString(json, const ['status', 'state']) ?? 'not_started',
      lastTrainingDate: _readOptionalDate(json, const [
        'lastTrainingDate',
        'last_training_date',
        'lastTrainingAt',
        'last_training_at',
      ]),
      progressPercentage: _readProgress(json, subAreas: subAreas),
      subAreas: subAreas,
    );
  }

  factory TrainingSpecialtyModel.fromDogSpecialty(
    Map<String, dynamic> json,
    String docId,
    String dogId,
  ) {
    final rawName = _readString(json, const ['name', 'title', 'type']) ?? docId;
    final subAreas = _readSubAreas(json);

    return TrainingSpecialtyModel(
      id: docId,
      dogId: dogId,
      name: normalizeTrainingLabel(rawName),
      status: _readString(json, const ['status', 'state']) ?? 'not_started',
      lastTrainingDate: _readOptionalDate(json, const [
        'lastTrainingDate',
        'last_training_date',
        'lastTrainingAt',
        'last_training_at',
      ]),
      progressPercentage: _readProgress(json, subAreas: subAreas),
      subAreas: subAreas,
    );
  }

  TrainingSpecialtyModel copyWith({
    String? id,
    String? dogId,
    String? name,
    String? status,
    DateTime? lastTrainingDate,
    int? progressPercentage,
    List<TrainingSubAreaModel>? subAreas,
  }) {
    return TrainingSpecialtyModel(
      id: id ?? this.id,
      dogId: dogId ?? this.dogId,
      name: name ?? this.name,
      status: status ?? this.status,
      lastTrainingDate: lastTrainingDate ?? this.lastTrainingDate,
      progressPercentage: progressPercentage ?? this.progressPercentage,
      subAreas: subAreas ?? this.subAreas,
    );
  }

  bool get isOperational => normalizedStatus == 'operational';

  bool get isInFormation =>
      normalizedStatus == 'in_formation' || normalizedStatus == 'formation';

  bool get isNotStarted => normalizedStatus == 'not_started';

  bool get isInactive =>
      normalizedStatus == 'inactive' || normalizedStatus == 'inativa';

  bool get isActive => !isInactive && !isNotStarted;

  String get normalizedStatus => normalizeTrainingKey(status);

  String get statusLabel {
    final normalized = normalizedStatus;
    if (normalized == 'operational' || normalized == 'operacional') {
      return 'Operacional';
    }
    if (normalized == 'in_formation' ||
        normalized == 'formation' ||
        normalized == 'em_formacao') {
      return 'Em formação';
    }
    if (normalized == 'not_started' || normalized == 'nao_iniciada') {
      return 'Não iniciada';
    }
    if (normalized == 'maintenance' || normalized == 'manutencao') {
      return 'Manutenção';
    }
    if (normalized == 'inactive' || normalized == 'inativa') return 'Inativa';
    return normalizeTrainingLabel(status);
  }

  String get lastTrainingLabel => formatRelativeTrainingDate(lastTrainingDate);
}

class TrainingSubAreaModel {
  final String name;
  final String status;

  const TrainingSubAreaModel({required this.name, required this.status});

  factory TrainingSubAreaModel.fromJson(Map<String, dynamic> json) {
    return TrainingSubAreaModel(
      name: normalizeTrainingLabel(
        _readString(json, const ['name', 'title', 'label', 'type']) ??
            'Subárea',
      ),
      status: _readString(json, const ['status', 'state']) ?? 'not_started',
    );
  }

  bool get isOperational {
    final normalized = normalizeTrainingKey(status);
    return normalized == 'operational' || normalized == 'operacional';
  }

  String get statusLabel {
    final normalized = normalizeTrainingKey(status);
    if (normalized == 'operational' || normalized == 'operacional') {
      return 'Operacional';
    }
    if (normalized == 'not_started' || normalized == 'nao_iniciada') {
      return 'Não iniciada';
    }
    if (normalized == 'in_formation' || normalized == 'em_formacao') {
      return 'Em formação';
    }
    return normalizeTrainingLabel(status);
  }
}

class TrainingGeneralTypeModel {
  final String id;
  final String name;
  final String status;
  final DateTime? lastTrainingDate;
  final int sessionCount;

  const TrainingGeneralTypeModel({
    required this.id,
    required this.name,
    required this.status,
    this.lastTrainingDate,
    required this.sessionCount,
  });

  String get lastTrainingLabel => formatRelativeTrainingDate(lastTrainingDate);
}

class TrainingHubSession {
  final String id;
  final String dogId;
  final String dogName;
  final String handlerId;
  final String trainingType;
  final String specialty;
  final String subtype;
  final String status;
  final String syncStatus;
  final DateTime date;
  final DateTime createdAt;
  final String location;
  final String notes;
  final double? performanceScore;
  final Map<String, dynamic> metadata;

  const TrainingHubSession({
    required this.id,
    required this.dogId,
    required this.dogName,
    required this.handlerId,
    required this.trainingType,
    required this.specialty,
    required this.subtype,
    required this.status,
    required this.syncStatus,
    required this.date,
    required this.createdAt,
    required this.location,
    required this.notes,
    this.performanceScore,
    this.metadata = const {},
  });

  factory TrainingHubSession.fromJson(Map<String, dynamic> json, String docId) {
    final metadata = _readMap(json['metadata']);
    final type =
        _readString(json, const ['trainingType', 'type', 'activityType']) ??
        _readString(metadata, const ['trainingType', 'type', 'activityType']) ??
        'Treino';
    final specialty =
        _readString(json, const ['specialty', 'specialtyName']) ??
        _readString(metadata, const ['specialty', 'especialidade']) ??
        _inferSpecialty(type, metadata);
    final subtype =
        _readString(json, const ['subtype', 'subType', 'line', 'focus']) ??
        _readString(metadata, const ['subtype', 'line', 'Linha', 'focus']) ??
        _readString(json, const ['substanceUsed']) ??
        '';
    final date = parseFirestoreDate(
      json['date'] ??
          json['performedAt'] ??
          json['performed_at'] ??
          json['startedAt'] ??
          json['started_at'] ??
          json['createdAt'] ??
          json['created_at'],
    );
    final createdAt = parseFirestoreDate(
      json['createdAt'] ?? json['created_at'] ?? json['date'],
      fallback: date,
    );

    return TrainingHubSession(
      id: docId,
      dogId: _readString(json, const ['dogId', 'dog_id', 'caoId']) ?? '',
      dogName: _readString(json, const ['dogName', 'dog_name']) ?? '',
      handlerId:
          _readString(json, const ['handlerId', 'handler_id', 'condutorId']) ??
          '',
      trainingType: normalizeTrainingLabel(type),
      specialty: normalizeTrainingLabel(specialty),
      subtype: normalizeTrainingLabel(subtype),
      status:
          _readString(json, const ['status']) ??
          _readString(metadata, const ['status']) ??
          'registrado',
      syncStatus:
          _readString(json, const ['syncStatus', 'sync_status']) ??
          _readString(metadata, const ['syncStatus', 'sync_status']) ??
          'sincronizado',
      date: date,
      createdAt: createdAt,
      location: _readString(json, const ['location', 'local']) ?? '',
      notes:
          _readString(json, const [
            'handlerNotes',
            'handler_notes',
            'notes',
            'observation',
            'observations',
            'description',
          ]) ??
          '',
      performanceScore: _readScore(json, metadata),
      metadata: metadata,
    );
  }

  String get displayTitle => 'Treino • $trainingType';

  String get displaySubtitle {
    if (subtype.isNotEmpty) return subtype;
    if (specialty.isNotEmpty && specialty != trainingType) return specialty;
    if (location.isNotEmpty) return location;
    return statusLabel;
  }

  String get statusLabel {
    final normalized = normalizeTrainingKey(status);
    if (normalized == 'done' ||
        normalized == 'completed' ||
        normalized == 'concluido') {
      return 'Concluído';
    }
    if (normalized == 'pending' || normalized == 'pendente') return 'Pendente';
    return normalizeTrainingLabel(status);
  }

  String get syncStatusLabel {
    final normalized = normalizeTrainingKey(syncStatus);
    if (normalized == 'synced' || normalized == 'sincronizado') {
      return 'Sincronizado';
    }
    if (normalized == 'pending' || normalized == 'pendente') return 'Pendente';
    return normalizeTrainingLabel(syncStatus);
  }
}

String normalizeTrainingKey(String value) {
  return value
      .trim()
      .toLowerCase()
      .replaceAll('ç', 'c')
      .replaceAll('ã', 'a')
      .replaceAll('á', 'a')
      .replaceAll('à', 'a')
      .replaceAll('â', 'a')
      .replaceAll('é', 'e')
      .replaceAll('ê', 'e')
      .replaceAll('í', 'i')
      .replaceAll('ó', 'o')
      .replaceAll('õ', 'o')
      .replaceAll('ô', 'o')
      .replaceAll('ú', 'u')
      .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
      .replaceAll(RegExp(r'_+'), '_')
      .replaceAll(RegExp(r'^_|_$'), '');
}

String normalizeTrainingLabel(String value) {
  final trimmed = value.trim();
  if (trimmed.isEmpty) return '';
  final normalized = normalizeTrainingKey(trimmed);
  const labels = {
    'deteccao': 'Detecção',
    'guarda_protecao': 'Guarda & Proteção',
    'guarda_e_protecao': 'Guarda & Proteção',
    'busca_captura': 'Busca & Captura',
    'busca_e_captura': 'Busca & Captura',
    'obediencia': 'Obediência',
    'condicionamento': 'Condicionamento Físico',
    'condicionamento_fisico': 'Condicionamento Físico',
    'socializacao': 'Socialização',
    'faro': 'Faro',
    'scent_work': 'Faro',
    'tracking': 'Rastro',
    'rastro': 'Rastro',
  };
  if (labels.containsKey(normalized)) return labels[normalized]!;

  return trimmed
      .replaceAll('_', ' ')
      .split(RegExp(r'\s+'))
      .where((part) => part.isNotEmpty)
      .map((part) {
        if (part.length <= 3 && part == part.toUpperCase()) return part;
        return part[0].toUpperCase() + part.substring(1).toLowerCase();
      })
      .join(' ');
}

String formatRelativeTrainingDate(DateTime? date) {
  if (date == null) return 'Sem registro';
  final now = DateTime.now();
  final diff = now.difference(date);
  if (diff.inMinutes < 1) return 'Agora';
  if (diff.inMinutes < 60) return 'há ${diff.inMinutes} min';
  if (diff.inHours < 24) return 'há ${diff.inHours}h';
  if (diff.inDays == 1) return 'há 1 dia';
  return 'há ${diff.inDays} dias';
}

String? _readString(Map<String, dynamic> json, List<String> keys) {
  for (final key in keys) {
    final value = json[key];
    if (value == null) continue;
    final text = value.toString().trim();
    if (text.isNotEmpty) return text;
  }
  return null;
}

Map<String, dynamic> _readMap(dynamic value) {
  if (value is Map<String, dynamic>) return Map<String, dynamic>.from(value);
  if (value is Map) return Map<String, dynamic>.from(value);
  return const {};
}

DateTime? _readOptionalDate(Map<String, dynamic> json, List<String> keys) {
  for (final key in keys) {
    final value = json[key];
    if (value == null) continue;
    return parseFirestoreDate(value);
  }
  return null;
}

List<TrainingSubAreaModel> _readSubAreas(Map<String, dynamic> json) {
  final raw =
      json['subAreas'] ??
      json['sub_areas'] ??
      json['subareas'] ??
      json['lines'];
  if (raw is List) {
    return raw.map((item) {
      if (item is Map<String, dynamic>) {
        return TrainingSubAreaModel.fromJson(item);
      }
      if (item is Map) {
        return TrainingSubAreaModel.fromJson(Map<String, dynamic>.from(item));
      }
      return TrainingSubAreaModel(
        name: normalizeTrainingLabel(item.toString()),
        status: 'not_started',
      );
    }).toList();
  }
  if (raw is Map) {
    return raw.entries.map((entry) {
      final value = entry.value;
      if (value is Map) {
        final data = Map<String, dynamic>.from(value);
        data['name'] ??= entry.key.toString();
        return TrainingSubAreaModel.fromJson(data);
      }
      return TrainingSubAreaModel(
        name: normalizeTrainingLabel(entry.key.toString()),
        status: value.toString(),
      );
    }).toList();
  }
  return const [];
}

int _readProgress(
  Map<String, dynamic> json, {
  required List<TrainingSubAreaModel> subAreas,
}) {
  final raw =
      json['progressPercentage'] ??
      json['progress_percentage'] ??
      json['progress'];
  if (raw is num) {
    final value = raw <= 1 ? raw * 100 : raw;
    return value.round().clamp(0, 100);
  }
  if (subAreas.isNotEmpty) {
    final operational = subAreas.where((area) => area.isOperational).length;
    return ((operational / subAreas.length) * 100).round().clamp(0, 100);
  }

  final status = normalizeTrainingKey(
    _readString(json, const ['status', 'state']) ?? '',
  );
  if (status == 'operational' || status == 'operacional') return 100;
  if (status == 'in_formation' || status == 'em_formacao') return 40;
  return 0;
}

double? _readScore(Map<String, dynamic> json, Map<String, dynamic> metadata) {
  final raw =
      json['performanceScore'] ??
      json['performance_score'] ??
      metadata['performanceScore'] ??
      metadata['performance_score'] ??
      metadata['score'];
  if (raw is num) return raw.toDouble();
  if (raw is String) return double.tryParse(raw.replaceAll(',', '.'));
  return null;
}

String _inferSpecialty(String trainingType, Map<String, dynamic> metadata) {
  final line = _readString(metadata, const ['line', 'Linha']);
  final normalized = normalizeTrainingKey(trainingType);
  if (normalized.contains('detec') || normalized.contains('faro')) {
    return 'Detecção';
  }
  if (normalized.contains('guarda') || normalized.contains('protec')) {
    return 'Guarda & Proteção';
  }
  if (normalized.contains('busca') || normalized.contains('captura')) {
    return 'Busca & Captura';
  }
  return line ?? trainingType;
}
