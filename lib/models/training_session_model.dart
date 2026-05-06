import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:canil_gcm/utils/firestore_date.dart';

class TrainingSessionModel {
  final String? id;
  final String dogId;
  final String dogName;
  final String handlerId;
  final DateTime date;
  final String trainingType; // 'Faro', 'Proteção', 'Obediência'
  final String? substanceUsed;
  final String? hidingTime;
  final double? humidity;
  final String? windDirection;
  final int? searchDuration; // in seconds
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
    return TrainingSessionModel(
      id: docId ?? json['id'],
      dogId: json['dogId'] ?? '',
      dogName: json['dogName'] ?? '',
      handlerId: json['handlerId'] ?? '',
      date: parseFirestoreDate(json['date']),
      trainingType: json['trainingType'] ?? 'Desconhecido',
      substanceUsed: json['substanceUsed'],
      hidingTime: json['hidingTime'],
      humidity: json['humidity'] != null
          ? (json['humidity'] as num).toDouble()
          : null,
      windDirection: json['windDirection'],
      searchDuration: json['searchDuration'],
      location: json['location'] ?? '',
      weather: json['weather'] ?? '',
      handlerNotes: json['handlerNotes'] ?? '',
      mediaAttachments: json['mediaAttachments'] != null
          ? List<Map<String, dynamic>>.from(
              (json['mediaAttachments'] as List).map(
                (e) => Map<String, dynamic>.from(e as Map),
              ),
            )
          : null,
      metadata: json['metadata'] as Map<String, dynamic>?,
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
