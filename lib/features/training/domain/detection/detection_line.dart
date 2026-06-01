import 'package:cloud_firestore/cloud_firestore.dart';

import 'package:canil_gcm/features/training/domain/detection/detection_phase_config.dart';

/// Linha de detecção do cão.
///
/// Subcoleção: `/dogs/{dogId}/detection_lines/{lineId}`.
class DetectionLine {
  final String? id;
  final String type;
  final String? customName;
  final String status;
  final String currentPhase;
  final int consecutiveHits;
  final int bestStreak;
  final String? imprintingMaterial;
  final String? externalCertificationId;
  final DateTime? startedAt;
  final DateTime? operationalSince;
  final List<String> phasesCompleted;
  final List<Map<String, dynamic>> phaseHistory;
  final List<Map<String, dynamic>> auditTrail;
  final DateTime? updatedAt;
  final DateTime? lastSessionAt;
  final DateTime? deletedAt;
  final String? deletedBy;
  final String? deletedReason;

  const DetectionLine({
    this.id,
    required this.type,
    this.customName,
    this.status = 'not_started',
    this.currentPhase = '1b',
    this.consecutiveHits = 0,
    this.bestStreak = 0,
    this.imprintingMaterial,
    this.externalCertificationId,
    this.startedAt,
    this.operationalSince,
    this.phasesCompleted = const [],
    this.phaseHistory = const [],
    this.auditTrail = const [],
    this.updatedAt,
    this.lastSessionAt,
    this.deletedAt,
    this.deletedBy,
    this.deletedReason,
  });

  factory DetectionLine.fromJson(Map<String, dynamic> json, {String? docId}) {
    return DetectionLine(
      id: docId ?? json['id'] as String?,
      type: _normalizeLineType(json['type'] as String? ?? 'drogas'),
      customName: json['custom_name'] as String?,
      status: json['status'] as String? ?? 'not_started',
      currentPhase: DetectionPhaseCatalog.normalizePhaseCode(
        json['current_phase'] as String? ?? json['currentPhase'] as String?,
      ),
      consecutiveHits: _readInt(json['consecutive_hits']) ?? 0,
      bestStreak: _readInt(json['best_streak']) ?? 0,
      imprintingMaterial: json['imprinting_material'] as String?,
      externalCertificationId: json['external_certification_id'] as String?,
      startedAt: _toDateTime(json['started_at']),
      operationalSince: _toDateTime(json['operational_since']),
      phasesCompleted: _readStringList(
        json['phases_completed'],
      ).map(DetectionPhaseCatalog.normalizePhaseCode).toList(),
      phaseHistory: _readMapList(json['phase_history']),
      auditTrail: _readMapList(json['audit_trail']),
      updatedAt: _toDateTime(json['updated_at']),
      lastSessionAt: _toDateTime(json['last_session_at']),
      deletedAt: _toDateTime(json['deleted_at']),
      deletedBy: json['deleted_by'] as String?,
      deletedReason:
          json['deleted_reason'] as String? ?? json['delete_reason'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'type': _normalizeLineType(type),
      if (customName != null) 'custom_name': customName,
      'status': status,
      'current_phase': normalizedCurrentPhase,
      'consecutive_hits': consecutiveHits,
      'best_streak': bestStreak,
      if (imprintingMaterial != null) 'imprinting_material': imprintingMaterial,
      if (externalCertificationId != null)
        'external_certification_id': externalCertificationId,
      if (startedAt != null) 'started_at': Timestamp.fromDate(startedAt!),
      if (operationalSince != null)
        'operational_since': Timestamp.fromDate(operationalSince!),
      'phases_completed': phasesCompleted,
      if (phaseHistory.isNotEmpty) 'phase_history': phaseHistory,
      if (auditTrail.isNotEmpty) 'audit_trail': auditTrail,
      if (updatedAt != null) 'updated_at': Timestamp.fromDate(updatedAt!),
      if (lastSessionAt != null)
        'last_session_at': Timestamp.fromDate(lastSessionAt!),
      if (deletedAt != null) 'deleted_at': Timestamp.fromDate(deletedAt!),
      if (deletedBy != null) 'deleted_by': deletedBy,
      if (deletedReason != null) 'deleted_reason': deletedReason,
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
    List<String>? phasesCompleted,
    List<Map<String, dynamic>>? phaseHistory,
    List<Map<String, dynamic>>? auditTrail,
    DateTime? updatedAt,
    DateTime? lastSessionAt,
    DateTime? deletedAt,
    String? deletedBy,
    String? deletedReason,
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
      phasesCompleted: phasesCompleted ?? this.phasesCompleted,
      phaseHistory: phaseHistory ?? this.phaseHistory,
      auditTrail: auditTrail ?? this.auditTrail,
      updatedAt: updatedAt ?? this.updatedAt,
      lastSessionAt: lastSessionAt ?? this.lastSessionAt,
      deletedAt: deletedAt ?? this.deletedAt,
      deletedBy: deletedBy ?? this.deletedBy,
      deletedReason: deletedReason ?? this.deletedReason,
    );
  }

  String get normalizedCurrentPhase =>
      DetectionPhaseCatalog.normalizePhaseCode(currentPhase);

  DetectionPhaseConfig get phaseConfig =>
      DetectionPhaseCatalog.byCode(currentPhase);

  String get normalizedType => _normalizeLineType(type);

  String get displayName {
    switch (normalizedType) {
      case 'drogas':
        return 'Drogas';
      case 'armas':
        return 'Armas';
      case 'cadaver':
        return 'Cadáver';
      default:
        return customName?.trim().isNotEmpty == true ? customName! : 'Linha';
    }
  }

  bool get isDeleted => deletedAt != null;

  int get requiredConsecutiveHits => phaseConfig.targetConsecutiveHits ?? 0;

  static const List<String> phases = [
    '1b',
    '2b',
    '2v',
    '3b',
    '3v',
    '4b',
    '4v',
    '4c',
  ];

  static const List<String> officialTypes = ['drogas', 'armas', 'cadaver'];

  static String displayNameForType(String type) {
    switch (_normalizeLineType(type)) {
      case 'drogas':
        return 'Drogas';
      case 'armas':
        return 'Armas';
      case 'cadaver':
        return 'Cadáver';
      default:
        return 'Linha';
    }
  }

  static String iconForType(String type) {
    switch (_normalizeLineType(type)) {
      case 'drogas':
        return '💊';
      case 'armas':
        return '🔫';
      case 'cadaver':
        return '🕯';
      default:
        return '🎯';
    }
  }

  static DateTime? _toDateTime(dynamic value) {
    if (value == null) return null;
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    if (value is String) return DateTime.tryParse(value);
    return null;
  }

  static int? _readInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value);
    return null;
  }

  static List<String> _readStringList(dynamic value) {
    if (value is! List) return const [];
    return value.map((item) => item.toString()).toList();
  }

  static List<Map<String, dynamic>> _readMapList(dynamic value) {
    if (value is! List) return const [];
    return value
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList();
  }

  static String _normalizeLineType(String value) {
    final normalized = value.trim().toLowerCase();
    switch (normalized) {
      case 'drugs':
      case 'droga':
      case 'drogas':
        return 'drogas';
      case 'weapons':
      case 'arma':
      case 'armas':
        return 'armas';
      case 'cadaver':
      case 'cadáver':
      case 'cadaveres':
      case 'cadáveres':
        return 'cadaver';
      default:
        return normalized;
    }
  }
}
