import 'package:cloud_firestore/cloud_firestore.dart';

/// Especialidade do cão (Guarda & Proteção, Busca & Captura, Detecção).
/// Subcoleção: /dogs/{dogId}/specialties/{specialtyId}
class DogSpecialty {
  final String? id;
  final String type; // 'guarda_protecao' | 'busca_captura' | 'deteccao'
  final String status; // 'not_started' | 'in_formation' | 'operational'
  final DateTime? startedAt;
  final DateTime? operationalSince;
  final String? currentPhase;
  final String? notes;

  DogSpecialty({
    this.id,
    required this.type,
    this.status = 'not_started',
    this.startedAt,
    this.operationalSince,
    this.currentPhase,
    this.notes,
  });

  bool get isOperational => status == 'operational';
  bool get isInFormation => status == 'in_formation';

  factory DogSpecialty.fromJson(Map<String, dynamic> json, {String? docId}) {
    return DogSpecialty(
      id: docId ?? json['id'] as String?,
      type: json['type'] as String? ?? '',
      status: json['status'] as String? ?? 'not_started',
      startedAt: _toDateTime(json['started_at']),
      operationalSince: _toDateTime(json['operational_since']),
      currentPhase: json['current_phase'] as String?,
      notes: json['notes'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'type': type,
      'status': status,
      if (startedAt != null) 'started_at': Timestamp.fromDate(startedAt!),
      if (operationalSince != null)
        'operational_since': Timestamp.fromDate(operationalSince!),
      if (currentPhase != null) 'current_phase': currentPhase,
      if (notes != null) 'notes': notes,
    };
  }

  DogSpecialty copyWith({
    String? id,
    String? type,
    String? status,
    DateTime? startedAt,
    DateTime? operationalSince,
    String? currentPhase,
    String? notes,
  }) {
    return DogSpecialty(
      id: id ?? this.id,
      type: type ?? this.type,
      status: status ?? this.status,
      startedAt: startedAt ?? this.startedAt,
      operationalSince: operationalSince ?? this.operationalSince,
      currentPhase: currentPhase ?? this.currentPhase,
      notes: notes ?? this.notes,
    );
  }

  static const List<String> types = [
    'guarda_protecao',
    'busca_captura',
    'deteccao',
  ];

  static DateTime? _toDateTime(dynamic value) {
    if (value == null) return null;
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    return null;
  }
}