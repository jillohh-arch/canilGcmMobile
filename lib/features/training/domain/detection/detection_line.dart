import 'package:cloud_firestore/cloud_firestore.dart';

/// Linha de detecção do cão (Drogas, Armas, Cadáver, etc).
/// Subcoleção: /dogs/{dogId}/detection_lines/{lineId}
class DetectionLine {
  final String? id;
  final String type; // 'drugs' | 'weapons' | 'cadaver' | 'custom'
  final String? customName;
  final String status; // 'not_started' | 'in_formation' | 'operational'
  final String currentPhase; // 'triagem' | 'fase_1' ... 'fase_5'
  final int consecutiveHits;
  final int bestStreak;
  final String? imprintingMaterial;
  final String? externalCertificationId;
  final DateTime? startedAt;
  final DateTime? operationalSince;

  DetectionLine({
    this.id,
    required this.type,
    this.customName,
    this.status = 'not_started',
    this.currentPhase = 'triagem',
    this.consecutiveHits = 0,
    this.bestStreak = 0,
    this.imprintingMaterial,
    this.externalCertificationId,
    this.startedAt,
    this.operationalSince,
  });

  factory DetectionLine.fromJson(Map<String, dynamic> json, {String? docId}) {
    return DetectionLine(
      id: docId ?? json['id'] as String?,
      type: json['type'] as String? ?? 'drugs',
      customName: json['custom_name'] as String?,
      status: json['status'] as String? ?? 'not_started',
      currentPhase: json['current_phase'] as String? ?? 'triagem',
      consecutiveHits: json['consecutive_hits'] as int? ?? 0,
      bestStreak: json['best_streak'] as int? ?? 0,
      imprintingMaterial: json['imprinting_material'] as String?,
      externalCertificationId: json['external_certification_id'] as String?,
      startedAt: _toDateTime(json['started_at']),
      operationalSince: _toDateTime(json['operational_since']),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'type': type,
      if (customName != null) 'custom_name': customName,
      'status': status,
      'current_phase': currentPhase,
      'consecutive_hits': consecutiveHits,
      'best_streak': bestStreak,
      if (imprintingMaterial != null) 'imprinting_material': imprintingMaterial,
      if (externalCertificationId != null)
        'external_certification_id': externalCertificationId,
      if (startedAt != null) 'started_at': Timestamp.fromDate(startedAt!),
      if (operationalSince != null)
        'operational_since': Timestamp.fromDate(operationalSince!),
    };
  }

  DetectionLine copyWith({
    String? id,
    String? type,
    String? customName,
    String? status,
    String? currentPhase,
    int? consecutiveHits,
    int? bestStreak,
    String? imprintingMaterial,
    String? externalCertificationId,
    DateTime? startedAt,
    DateTime? operationalSince,
  }) {
    return DetectionLine(
      id: id ?? this.id,
      type: type ?? this.type,
      customName: customName ?? this.customName,
      status: status ?? this.status,
      currentPhase: currentPhase ?? this.currentPhase,
      consecutiveHits: consecutiveHits ?? this.consecutiveHits,
      bestStreak: bestStreak ?? this.bestStreak,
      imprintingMaterial: imprintingMaterial ?? this.imprintingMaterial,
      externalCertificationId:
          externalCertificationId ?? this.externalCertificationId,
      startedAt: startedAt ?? this.startedAt,
      operationalSince: operationalSince ?? this.operationalSince,
    );
  }

  /// Critérios de progressão por fase (Protocolo Ragonha).
  int get requiredConsecutiveHits {
    switch (currentPhase) {
      case 'fase_1':
        return 3;
      case 'fase_2':
        return 3;
      case 'fase_3':
        return 10; // Ponto de virada — 99,99983% confiança
      case 'fase_4':
        return 3; // Por subfase (4A/4B/4C)
      case 'fase_5':
        return 5; // Por subfase ambiental
      default:
        return 0;
    }
  }

  static const List<String> phases = [
    'triagem',
    'fase_1',
    'fase_2',
    'fase_3',
    'fase_4',
    'fase_5',
  ];

  static DateTime? _toDateTime(dynamic value) {
    if (value == null) return null;
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    return null;
  }
}