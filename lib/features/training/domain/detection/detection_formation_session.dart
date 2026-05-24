import 'package:cloud_firestore/cloud_firestore.dart';

import 'package:canil_gcm/features/training/domain/detection/detection_phase_config.dart';

class DetectionFormationStatus {
  static const inProgress = 'in_progress';
  static const completedByCriterion = 'completed_by_criterion';
  static const endedWithoutCriterion = 'ended_without_criterion';
}

class DetectionOdorMaterials {
  static const noseMp = 'nose_mp';
  static const real = 'real';
  static const scentlogix = 'scentlogix';

  static const values = [noseMp, real, scentlogix];

  static String label(String value) {
    switch (value) {
      case real:
        return 'Odor real';
      case scentlogix:
        return 'ScentLogix';
      case noseMp:
      default:
        return 'Nose MP';
    }
  }
}

class DetectionFormationSession {
  final String? id;
  final String dogId;
  final String dogName;
  final String lineId;
  final String lineName;
  final String lineType;
  final String phase;
  final String phaseName;
  final int boxCount;
  final String odorPositionMode;
  final bool usedBall;
  final String odorMaterial;
  final String status;
  final String? direction;
  final DateTime startedAt;
  final DateTime? endedAt;
  final int durationSeconds;
  final List<DetectionRepetition> repetitions;
  final int totalReps;
  final int longestStreak;
  final int currentStreak;
  final int clockwiseStreak;
  final int counterClockwiseStreak;
  final bool criterionMet;
  final bool phaseAdvanced;
  final String? advancedTo;
  final String notes;
  final String handlerId;
  final String handlerName;
  final List<Map<String, dynamic>> media;
  final List<Map<String, dynamic>> auditTrail;
  final DateTime? deletedAt;
  final String? deletedBy;
  final String? deletedReason;

  DetectionFormationSession({
    this.id,
    required this.dogId,
    required this.dogName,
    required this.lineId,
    required this.lineName,
    required this.lineType,
    required this.phase,
    required this.phaseName,
    required this.boxCount,
    required this.odorPositionMode,
    required this.usedBall,
    required this.odorMaterial,
    required this.status,
    this.direction,
    required this.startedAt,
    this.endedAt,
    required this.durationSeconds,
    required this.repetitions,
    required this.totalReps,
    required this.longestStreak,
    required this.currentStreak,
    this.clockwiseStreak = 0,
    this.counterClockwiseStreak = 0,
    required this.criterionMet,
    required this.phaseAdvanced,
    this.advancedTo,
    this.notes = '',
    required this.handlerId,
    required this.handlerName,
    this.media = const [],
    this.auditTrail = const [],
    this.deletedAt,
    this.deletedBy,
    this.deletedReason,
  });

  factory DetectionFormationSession.fromJson(
    Map<String, dynamic> json, {
    String? docId,
  }) {
    final repetitionsRaw = json['repetitions'];
    final repetitions = repetitionsRaw is List
        ? repetitionsRaw
              .whereType<Map>()
              .map(
                (item) => DetectionRepetition.fromJson(
                  Map<String, dynamic>.from(item),
                ),
              )
              .toList()
        : <DetectionRepetition>[];

    return DetectionFormationSession(
      id: docId ?? json['id'] as String?,
      dogId: _readString(json, const ['dogId', 'dog_id']) ?? '',
      dogName: _readString(json, const ['dogName', 'dog_name']) ?? '',
      lineId: _readString(json, const ['line_id', 'lineId']) ?? '',
      lineName: _readString(json, const ['line_name', 'lineName']) ?? '',
      lineType: _readString(json, const ['line_type', 'lineType']) ?? '',
      phase: _readString(json, const ['phase']) ?? '1b',
      phaseName: _readString(json, const ['phase_name', 'phaseName']) ?? '',
      boxCount: _readInt(json['box_count'] ?? json['boxCount']) ?? 0,
      odorPositionMode:
          _readString(json, const ['odor_position_mode', 'odorPositionMode']) ??
          'fixed_last',
      usedBall:
          json['used_ball'] as bool? ?? json['usedBall'] as bool? ?? false,
      odorMaterial:
          _readString(json, const ['odor_material', 'odorMaterial']) ??
          DetectionOdorMaterials.noseMp,
      status:
          _readString(json, const ['status']) ??
          DetectionFormationStatus.endedWithoutCriterion,
      direction: _readString(json, const ['direction']),
      startedAt:
          _readDate(json['started_at'] ?? json['startedAt']) ?? DateTime.now(),
      endedAt: _readDate(json['ended_at'] ?? json['endedAt']),
      durationSeconds:
          _readInt(json['duration_seconds'] ?? json['durationSeconds']) ?? 0,
      repetitions: repetitions,
      totalReps:
          _readInt(json['total_reps'] ?? json['totalReps']) ??
          repetitions.length,
      longestStreak:
          _readInt(json['longest_streak'] ?? json['longestStreak']) ?? 0,
      currentStreak:
          _readInt(json['current_streak'] ?? json['currentStreak']) ?? 0,
      clockwiseStreak:
          _readInt(json['clockwise_streak'] ?? json['clockwiseStreak']) ?? 0,
      counterClockwiseStreak:
          _readInt(
            json['counter_clockwise_streak'] ?? json['counterClockwiseStreak'],
          ) ??
          0,
      criterionMet:
          json['criterion_met'] as bool? ??
          json['criterionMet'] as bool? ??
          false,
      phaseAdvanced:
          json['phase_advanced'] as bool? ??
          json['phaseAdvanced'] as bool? ??
          false,
      advancedTo: _readString(json, const ['advanced_to', 'advancedTo']),
      notes: _readString(json, const ['notes', 'handlerNotes']) ?? '',
      handlerId: _readString(json, const ['handlerId', 'handler_id']) ?? '',
      handlerName:
          _readString(json, const ['handlerName', 'handler_name']) ?? '',
      media: _readListMap(json['media']),
      auditTrail: _readListMap(json['audit_trail'] ?? json['auditTrail']),
      deletedAt: _readDate(json['deleted_at'] ?? json['deletedAt']),
      deletedBy: _readString(json, const ['deleted_by', 'deletedBy']),
      deletedReason: _readString(json, const [
        'deleted_reason',
        'delete_reason',
      ]),
    );
  }

  Map<String, dynamic> toJson() {
    final metadata = {
      'line_id': lineId,
      'line': lineName,
      'line_type': lineType,
      'phase': phase,
      'phase_name': phaseName,
      'box_count': boxCount,
      'odor_position_mode': odorPositionMode,
      'used_ball': usedBall,
      'odor_material': odorMaterial,
      'direction': direction,
      'total_reps': totalReps,
      'longest_streak': longestStreak,
      'current_streak': currentStreak,
      'clockwise_streak': clockwiseStreak,
      'counter_clockwise_streak': counterClockwiseStreak,
      'criterion_met': criterionMet,
      'phase_advanced': phaseAdvanced,
      'status': status,
      if (advancedTo != null) 'advanced_to': advancedTo,
      'repetitions': repetitions.map((rep) => rep.toJson()).toList(),
    };

    return {
      if (id != null) 'id': id,
      'type': 'detection_formation',
      'trainingType': 'Detecção',
      'specialty': 'Detecção',
      'subtype': 'Formação Ragonha',
      'status': status,
      'syncStatus': 'synced',
      'dogId': dogId,
      'dog_id': dogId,
      'dogName': dogName,
      'dog_name': dogName,
      'handlerId': handlerId,
      'handler_id': handlerId,
      'handlerName': handlerName,
      'handler_name': handlerName,
      'line_id': lineId,
      'line_name': lineName,
      'line_type': lineType,
      'lines': [lineType],
      'phase': phase,
      'phase_name': phaseName,
      'box_count': boxCount,
      'odor_position_mode': odorPositionMode,
      'used_ball': usedBall,
      'odor_material': odorMaterial,
      if (direction != null) 'direction': direction,
      'started_at': Timestamp.fromDate(startedAt),
      if (endedAt != null) 'ended_at': Timestamp.fromDate(endedAt!),
      'date': Timestamp.fromDate(startedAt),
      'createdAt': Timestamp.fromDate(startedAt),
      'created_at': Timestamp.fromDate(startedAt),
      'duration_seconds': durationSeconds,
      'searchDuration': durationSeconds,
      'repetitions': repetitions.map((rep) => rep.toJson()).toList(),
      'total_reps': totalReps,
      'longest_streak': longestStreak,
      'current_streak': currentStreak,
      'clockwise_streak': clockwiseStreak,
      'counter_clockwise_streak': counterClockwiseStreak,
      'criterion_met': criterionMet,
      'phase_advanced': phaseAdvanced,
      if (advancedTo != null) 'advanced_to': advancedTo,
      'notes': notes,
      'handlerNotes': notes,
      'location': '',
      'weather': '',
      'media': media,
      'mediaAttachments': media,
      'metadata': metadata,
      'created_by': handlerId,
      'created_by_name': handlerName,
      'audit_trail': auditTrail,
      if (deletedAt != null) 'deleted_at': Timestamp.fromDate(deletedAt!),
      if (deletedBy != null) 'deleted_by': deletedBy,
      if (deletedReason != null) 'deleted_reason': deletedReason,
    };
  }

  DetectionFormationSession copyWith({
    String? id,
    String? status,
    DateTime? endedAt,
    int? durationSeconds,
    List<DetectionRepetition>? repetitions,
    int? totalReps,
    int? longestStreak,
    int? currentStreak,
    int? clockwiseStreak,
    int? counterClockwiseStreak,
    bool? criterionMet,
    bool? phaseAdvanced,
    String? advancedTo,
    String? direction,
    String? notes,
    List<Map<String, dynamic>>? auditTrail,
  }) {
    return DetectionFormationSession(
      id: id ?? this.id,
      dogId: dogId,
      dogName: dogName,
      lineId: lineId,
      lineName: lineName,
      lineType: lineType,
      phase: phase,
      phaseName: phaseName,
      boxCount: boxCount,
      odorPositionMode: odorPositionMode,
      usedBall: usedBall,
      odorMaterial: odorMaterial,
      status: status ?? this.status,
      direction: direction ?? this.direction,
      startedAt: startedAt,
      endedAt: endedAt ?? this.endedAt,
      durationSeconds: durationSeconds ?? this.durationSeconds,
      repetitions: repetitions ?? this.repetitions,
      totalReps: totalReps ?? this.totalReps,
      longestStreak: longestStreak ?? this.longestStreak,
      currentStreak: currentStreak ?? this.currentStreak,
      clockwiseStreak: clockwiseStreak ?? this.clockwiseStreak,
      counterClockwiseStreak:
          counterClockwiseStreak ?? this.counterClockwiseStreak,
      criterionMet: criterionMet ?? this.criterionMet,
      phaseAdvanced: phaseAdvanced ?? this.phaseAdvanced,
      advancedTo: advancedTo ?? this.advancedTo,
      notes: notes ?? this.notes,
      handlerId: handlerId,
      handlerName: handlerName,
      media: media,
      auditTrail: auditTrail ?? this.auditTrail,
      deletedAt: deletedAt,
      deletedBy: deletedBy,
      deletedReason: deletedReason,
    );
  }

  static DetectionFormationSession fromRecorder({
    String? id,
    required String dogId,
    required String dogName,
    required String lineId,
    required String lineName,
    required String lineType,
    required DetectionPhaseConfig phase,
    required DateTime startedAt,
    DateTime? endedAt,
    required DetectionSessionRecorder recorder,
    required String status,
    required bool phaseAdvanced,
    String? advancedTo,
    required String handlerId,
    required String handlerName,
    required String odorMaterial,
    String? notes,
    List<Map<String, dynamic>> auditTrail = const [],
  }) {
    final effectiveEndedAt = status == DetectionFormationStatus.inProgress
        ? null
        : endedAt ?? DateTime.now();
    final now = DateTime.now();
    return DetectionFormationSession(
      id: id,
      dogId: dogId,
      dogName: dogName,
      lineId: lineId,
      lineName: lineName,
      lineType: lineType,
      phase: phase.code,
      phaseName: phase.title,
      boxCount: phase.boxCount,
      odorPositionMode: phase.odorPositionMode,
      usedBall: phase.usedBall,
      odorMaterial: odorMaterial,
      status: status,
      direction: phase.isSquare ? recorder.currentDirection : null,
      startedAt: startedAt,
      endedAt: effectiveEndedAt,
      durationSeconds: (effectiveEndedAt ?? now)
          .difference(startedAt)
          .inSeconds,
      repetitions: recorder.repetitions,
      totalReps: recorder.totalReps,
      longestStreak: recorder.longestStreak,
      currentStreak: recorder.currentStreak,
      clockwiseStreak: recorder.clockwiseStreak,
      counterClockwiseStreak: recorder.counterClockwiseStreak,
      criterionMet: recorder.criterionMet,
      phaseAdvanced: phaseAdvanced,
      advancedTo: advancedTo,
      notes: notes ?? '',
      handlerId: handlerId,
      handlerName: handlerName,
      auditTrail: auditTrail,
    );
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

DateTime? _readDate(dynamic value) {
  if (value == null) return null;
  if (value is Timestamp) return value.toDate();
  if (value is DateTime) return value;
  if (value is String) return DateTime.tryParse(value);
  return null;
}

List<Map<String, dynamic>> _readListMap(dynamic value) {
  if (value is! List) return const [];
  return value
      .whereType<Map>()
      .map((item) => Map<String, dynamic>.from(item))
      .toList();
}
