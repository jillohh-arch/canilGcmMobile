import 'package:cloud_firestore/cloud_firestore.dart';

/// Registro de peso do cão.
/// Subcoleção: /dogs/{dogId}/weight_history/{recordId}
class WeightRecord {
  final String? id;
  final double weightKg;
  final DateTime measuredAt;
  final String measuredBy;
  final String context; // 'canil' | 'clinica_vet' | 'casa'
  final String? photoUrl;
  final String? notes;

  WeightRecord({
    this.id,
    required this.weightKg,
    required this.measuredAt,
    required this.measuredBy,
    this.context = 'canil',
    this.photoUrl,
    this.notes,
  });

  factory WeightRecord.fromJson(Map<String, dynamic> json, {String? docId}) {
    return WeightRecord(
      id: docId ?? json['id'] as String?,
      weightKg: (json['weight_kg'] as num?)?.toDouble() ?? 0.0,
      measuredAt: _toDateTime(json['measured_at']) ?? DateTime.now(),
      measuredBy: json['measured_by'] as String? ?? '',
      context: json['context'] as String? ?? 'canil',
      photoUrl: json['photo_url'] as String?,
      notes: json['notes'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'weight_kg': weightKg,
      'measured_at': Timestamp.fromDate(measuredAt),
      'measured_by': measuredBy,
      'context': context,
      if (photoUrl != null) 'photo_url': photoUrl,
      if (notes != null) 'notes': notes,
    };
  }

  static DateTime? _toDateTime(dynamic value) {
    if (value == null) return null;
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    return null;
  }
}
