import 'package:cloud_firestore/cloud_firestore.dart';

/// Tentativa individual dentro de uma sessão de detecção.
/// Subcoleção: /dogs/{dogId}/training_attempts/{attemptId}
class TrainingAttempt {
  final String? id;
  final String sessionId;
  final int attemptNumber;
  final List<String> linesWorked; // IDs das linhas trabalhadas (multi-linha)
  final String? boxPosition; // 'left' | 'center' | 'right'
  final String result; // 'hit' | 'miss'
  final String? missType; // classificação do erro
  final DateTime timestamp;
  final String? notes;

  TrainingAttempt({
    this.id,
    required this.sessionId,
    required this.attemptNumber,
    this.linesWorked = const [],
    this.boxPosition,
    required this.result,
    this.missType,
    required this.timestamp,
    this.notes,
  });

  bool get isHit => result == 'hit';
  bool get isMiss => result == 'miss';

  factory TrainingAttempt.fromJson(Map<String, dynamic> json, {String? docId}) {
    return TrainingAttempt(
      id: docId ?? json['id'] as String?,
      sessionId: json['session_id'] as String? ?? '',
      attemptNumber: json['attempt_number'] as int? ?? 0,
      linesWorked:
          (json['lines_worked'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          [],
      boxPosition: json['box_position'] as String?,
      result: json['result'] as String? ?? 'miss',
      missType: json['miss_type'] as String?,
      timestamp: _toDateTime(json['timestamp']) ?? DateTime.now(),
      notes: json['notes'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'session_id': sessionId,
      'attempt_number': attemptNumber,
      'lines_worked': linesWorked,
      if (boxPosition != null) 'box_position': boxPosition,
      'result': result,
      if (missType != null) 'miss_type': missType,
      'timestamp': Timestamp.fromDate(timestamp),
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
