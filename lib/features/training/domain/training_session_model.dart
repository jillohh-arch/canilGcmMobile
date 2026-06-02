import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:canil_gcm/core/utils/firestore_date.dart';

class TrainingSessionModel {
  final String? id;
  final String dogId;
  final String dogName;
  final String handlerId;
  final DateTime date;
  final String trainingType;
  final String? substanceUsed;
  final String? hidingTime;
  final double? humidity;
  final String? windDirection;
  final int? searchDuration;
  final String location;
  final String weather;
  final String handlerNotes;
  final List<Map<String, dynamic>>? mediaAttachments;
  final Map<String, dynamic>? metadata;

  TrainingSessionModel({
    this.id,
    required this.dogId,
    this.dogName = '',
    this.handlerId = '',
    required this.date,
    required this.trainingType,
    this.substanceUsed,
    this.hidingTime,
    this.humidity,
    this.windDirection,
    this.searchDuration,
    required this.location,
    required this.weather,
    required this.handlerNotes,
    this.mediaAttachments,
    this.metadata,
  });

  factory TrainingSessionModel.fromJson(
    Map<String, dynamic> json, [
    String? docId,
  ]) {
    final metadata = _readMap(json['metadata']);
    final dateValue =
        json['date'] ??
        json['performedAt'] ??
        json['performed_at'] ??
        json['startedAt'] ??
        json['started_at'] ??
        json['createdAt'] ??
        json['created_at'];

    return TrainingSessionModel(
      id: docId ?? json['id'] as String?,
      dogId: _readString(json, const ['dogId', 'dog_id', 'caoId']) ?? '',
      dogName: _readString(json, const ['dogName', 'dog_name']) ?? '',
      handlerId:
          _readString(json, const ['handlerId', 'handler_id', 'condutorId']) ??
          '',
      date: parseFirestoreDate(dateValue),
      trainingType:
          _readString(json, const ['trainingType', 'training_type']) ??
          _readString(metadata, const ['trainingType', 'training_type']) ??
          _labelFromType(_readString(json, const ['type']) ?? 'Treino'),
      substanceUsed:
          _readString(json, const ['substanceUsed', 'substance_used']) ??
          _readString(metadata, const ['odor_material', 'substanceUsed']),
      hidingTime: _readString(json, const ['hidingTime', 'hiding_time']),
      humidity: _readDouble(json['humidity'] ?? json['umidade']),
      windDirection: _readString(json, const [
        'windDirection',
        'wind_direction',
      ]),
      searchDuration: _readInt(
        json['searchDuration'] ?? json['duration_seconds'],
      ),
      location: _readString(json, const ['location', 'local']) ?? '',
      weather: _readString(json, const ['weather', 'clima']) ?? '',
      handlerNotes:
          _readString(json, const [
            'handlerNotes',
            'handler_notes',
            'notes',
            'observation',
            'observations',
          ]) ??
          '',
      mediaAttachments: _readListMap(json['mediaAttachments'] ?? json['media']),
      metadata: metadata.isEmpty ? null : metadata,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      if (id != null) 'id': id,
      'dogId': dogId,
      'dogName': dogName,
      'handlerId': handlerId,
      'date': Timestamp.fromDate(date),
      'trainingType': trainingType,
      if (substanceUsed != null) 'substanceUsed': substanceUsed,
      if (hidingTime != null) 'hidingTime': hidingTime,
      if (humidity != null) 'humidity': humidity,
      if (windDirection != null) 'windDirection': windDirection,
      if (searchDuration != null) 'searchDuration': searchDuration,
      'location': location,
      'weather': weather,
      'handlerNotes': handlerNotes,
      if (mediaAttachments != null) 'mediaAttachments': mediaAttachments,
      if (metadata != null && metadata!.isNotEmpty) 'metadata': metadata,
    };
  }
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

int? _readInt(dynamic value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  if (value is String) return int.tryParse(value);
  return null;
}

double? _readDouble(dynamic value) {
  if (value is double) return value;
  if (value is num) return value.toDouble();
  if (value is String) return double.tryParse(value.replaceAll(',', '.'));
  return null;
}

Map<String, dynamic> _readMap(dynamic value) {
  if (value is Map<String, dynamic>) return Map<String, dynamic>.from(value);
  if (value is Map) return Map<String, dynamic>.from(value);
  return const {};
}

List<Map<String, dynamic>>? _readListMap(dynamic value) {
  if (value is! List) return null;
  return value
      .whereType<Map>()
      .map((item) => Map<String, dynamic>.from(item))
      .toList();
}

String _labelFromType(String value) {
  if (value == 'detection_formation') return 'Detecção';
  return value
      .replaceAll('_', ' ')
      .split(RegExp(r'\s+'))
      .where((part) => part.isNotEmpty)
      .map((part) => part[0].toUpperCase() + part.substring(1).toLowerCase())
      .join(' ');
}
