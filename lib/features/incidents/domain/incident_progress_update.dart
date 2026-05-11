import 'package:cloud_firestore/cloud_firestore.dart';

import 'package:canil_gcm/core/utils/firestore_date.dart';

class IncidentProgressUpdate {
  final String title;
  final String description;
  final DateTime timestamp;
  final String? location;
  final double? latitude;
  final double? longitude;
  final String? authorId;
  final String? authorName;
  final List<Map<String, dynamic>> attachments;

  const IncidentProgressUpdate({
    required this.title,
    required this.description,
    required this.timestamp,
    this.location,
    this.latitude,
    this.longitude,
    this.authorId,
    this.authorName,
    this.attachments = const [],
  });

  factory IncidentProgressUpdate.fromJson(Map<String, dynamic> json) {
    return IncidentProgressUpdate(
      title: json['title'] as String? ?? 'Atualização operacional',
      description: json['description'] as String? ?? '',
      timestamp: parseFirestoreDate(json['timestamp']),
      location: json['location'] as String?,
      latitude: (json['latitude'] as num?)?.toDouble(),
      longitude: (json['longitude'] as num?)?.toDouble(),
      authorId: json['authorId'] as String?,
      authorName: json['authorName'] as String?,
      attachments: json['attachments'] != null
          ? List<Map<String, dynamic>>.from(
              (json['attachments'] as List).map(
                (e) => Map<String, dynamic>.from(e as Map),
              ),
            )
          : const [],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'title': title,
      'description': description,
      'timestamp': Timestamp.fromDate(timestamp),
      if (location != null && location!.isNotEmpty) 'location': location,
      if (latitude != null) 'latitude': latitude,
      if (longitude != null) 'longitude': longitude,
      if (authorId != null && authorId!.isNotEmpty) 'authorId': authorId,
      if (authorName != null && authorName!.isNotEmpty)
        'authorName': authorName,
      if (attachments.isNotEmpty) 'attachments': attachments,
    };
  }
}
