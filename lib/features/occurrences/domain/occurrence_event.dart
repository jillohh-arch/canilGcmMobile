import 'package:cloud_firestore/cloud_firestore.dart';

import 'package:canil_gcm/core/mixins/soft_deletable.dart';
import 'occurrence_event_category.dart';

class OccurrenceEvent with SoftDeletable {
  final String id;
  final String occurrenceId;

  final OccurrenceEventCategory category;
  final DateTime timestamp;
  final String? title;
  final String? description;

  final List<String> photoUrls;
  final List<Map<String, dynamic>> photoMetadata;

  final double? gpsLat;
  final double? gpsLng;

  final DateTime createdAt;
  final DateTime updatedAt;

  final List<Map<String, dynamic>> auditTrail;

  @override
  final DateTime? deletedAt;
  @override
  final String? deletedBy;
  @override
  final String? deleteReason;

  const OccurrenceEvent({
    required this.id,
    required this.occurrenceId,
    required this.category,
    required this.timestamp,
    this.title,
    this.description,
    this.photoUrls = const [],
    this.photoMetadata = const [],
    this.gpsLat,
    this.gpsLng,
    required this.createdAt,
    required this.updatedAt,
    this.auditTrail = const [],
    this.deletedAt,
    this.deletedBy,
    this.deleteReason,
  });

  factory OccurrenceEvent.fromMap(Map<String, dynamic> map, String id,
      {required String occurrenceId}) {
    return OccurrenceEvent(
      id: id,
      occurrenceId: occurrenceId,
      category: OccurrenceEventCategory.fromMap(map['category'] as String?),
      timestamp: _parseDateTime(map['timestamp']) ?? DateTime.now(),
      title: map['title'] as String?,
      description: map['description'] as String?,
      photoUrls: (map['photo_urls'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          const [],
      photoMetadata: (map['photo_metadata'] as List<dynamic>?)
              ?.map((e) => Map<String, dynamic>.from(e as Map))
              .toList() ??
          const [],
      gpsLat: (map['gps_lat'] as num?)?.toDouble(),
      gpsLng: (map['gps_lng'] as num?)?.toDouble(),
      createdAt: _parseDateTime(map['created_at']) ?? DateTime.now(),
      updatedAt: _parseDateTime(map['updated_at']) ?? DateTime.now(),
      auditTrail: (map['audit_trail'] as List<dynamic>?)
              ?.map((e) => Map<String, dynamic>.from(e as Map))
              .toList() ??
          const [],
      deletedAt: SoftDeletable.parseDeletedAt(map['deleted_at']),
      deletedBy: map['deleted_by'] as String?,
      deleteReason: map['delete_reason'] as String?,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'occurrence_id': occurrenceId,
      'category': category.toMap(),
      'timestamp': Timestamp.fromDate(timestamp),
      'title': title,
      'description': description,
      'photo_urls': photoUrls,
      'photo_metadata': photoMetadata,
      'gps_lat': gpsLat,
      'gps_lng': gpsLng,
      'created_at': Timestamp.fromDate(createdAt),
      'updated_at': Timestamp.fromDate(updatedAt),
      'audit_trail': auditTrail,
      ...softDeleteFields(),
    };
  }

  OccurrenceEvent copyWith({
    String? id,
    String? occurrenceId,
    OccurrenceEventCategory? category,
    DateTime? timestamp,
    String? title,
    String? description,
    List<String>? photoUrls,
    List<Map<String, dynamic>>? photoMetadata,
    double? gpsLat,
    double? gpsLng,
    DateTime? createdAt,
    DateTime? updatedAt,
    List<Map<String, dynamic>>? auditTrail,
    DateTime? deletedAt,
    String? deletedBy,
    String? deleteReason,
  }) {
    return OccurrenceEvent(
      id: id ?? this.id,
      occurrenceId: occurrenceId ?? this.occurrenceId,
      category: category ?? this.category,
      timestamp: timestamp ?? this.timestamp,
      title: title ?? this.title,
      description: description ?? this.description,
      photoUrls: photoUrls ?? this.photoUrls,
      photoMetadata: photoMetadata ?? this.photoMetadata,
      gpsLat: gpsLat ?? this.gpsLat,
      gpsLng: gpsLng ?? this.gpsLng,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      auditTrail: auditTrail ?? this.auditTrail,
      deletedAt: deletedAt ?? this.deletedAt,
      deletedBy: deletedBy ?? this.deletedBy,
      deleteReason: deleteReason ?? this.deleteReason,
    );
  }

  static DateTime? _parseDateTime(dynamic value) {
    if (value == null) return null;
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    if (value is String) return DateTime.tryParse(value);
    return null;
  }
}
