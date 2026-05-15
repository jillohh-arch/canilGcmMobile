import 'package:cloud_firestore/cloud_firestore.dart';

/// Sessão de condicionamento físico do cão.
/// Subcoleção: /dogs/{dogId}/conditioning_sessions/{sessionId}
class ConditioningSession {
  final String? id;
  final String exerciseType;
  // 'passeio' | 'esteira' | 'paraquedas' | 'natacao' | 'tracao_peso' |
  // 'tracao_elastica' | 'escalada' | 'bolinha_campo' | 'a_frame' |
  // 'salto_altura' | 'salto_distancia' | 'cavaletes' | 'outro'
  final String? exerciseNameCustom;
  final Map<String, dynamic> metrics;
  // Métricas variam por exercício:
  // duration_minutes, distance_meters, repetitions, diagonal_meters,
  // velocity_kmh, load_kg, max_height_cm, max_distance_meters
  final String intensity; // 'leve' | 'moderada' | 'intensa'
  final String? gpsTrackId;
  final String postCondition; // 'normal' | 'ofegante' | 'exausto'
  final String? observations;
  final DateTime performedAt;
  final String performedBy;

  ConditioningSession({
    this.id,
    required this.exerciseType,
    this.exerciseNameCustom,
    this.metrics = const {},
    this.intensity = 'moderada',
    this.gpsTrackId,
    this.postCondition = 'normal',
    this.observations,
    required this.performedAt,
    required this.performedBy,
  });

  factory ConditioningSession.fromJson(Map<String, dynamic> json, {String? docId}) {
    return ConditioningSession(
      id: docId ?? json['id'] as String?,
      exerciseType: json['exercise_type'] as String? ?? 'passeio',
      exerciseNameCustom: json['exercise_name_custom'] as String?,
      metrics: (json['metrics'] as Map<String, dynamic>?) ?? {},
      intensity: json['intensity'] as String? ?? 'moderada',
      gpsTrackId: json['gps_track_id'] as String?,
      postCondition: json['post_condition'] as String? ?? 'normal',
      observations: json['observations'] as String?,
      performedAt: _toDateTime(json['performed_at']) ?? DateTime.now(),
      performedBy: json['performed_by'] as String? ?? '',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'exercise_type': exerciseType,
      if (exerciseNameCustom != null) 'exercise_name_custom': exerciseNameCustom,
      'metrics': metrics,
      'intensity': intensity,
      if (gpsTrackId != null) 'gps_track_id': gpsTrackId,
      'post_condition': postCondition,
      if (observations != null) 'observations': observations,
      'performed_at': Timestamp.fromDate(performedAt),
      'performed_by': performedBy,
    };
  }

  /// Duração em minutos (extraída das métricas).
  int? get durationMinutes => metrics['duration_minutes'] as int?;

  /// Distância em metros (extraída das métricas).
  double? get distanceMeters => (metrics['distance_meters'] as num?)?.toDouble();

  static const List<String> exerciseTypes = [
    'passeio',
    'esteira',
    'paraquedas',
    'natacao',
    'tracao_peso',
    'tracao_elastica',
    'escalada',
    'bolinha_campo',
    'a_frame',
    'salto_altura',
    'salto_distancia',
    'cavaletes',
    'outro',
  ];

  static const List<String> intensities = ['leve', 'moderada', 'intensa'];

  static const List<String> postConditions = ['normal', 'ofegante', 'exausto'];

  static DateTime? _toDateTime(dynamic value) {
    if (value == null) return null;
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    return null;
  }
}