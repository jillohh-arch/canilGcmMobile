import 'package:cloud_firestore/cloud_firestore.dart';

/// Representa um comando na biblioteca de obediência do cão.
/// Subcoleção: /dogs/{dogId}/commands/{commandId}
class DogCommand {
  final String? id;
  final String name;
  final String
  category; // 'operacional' | 'posicional' | 'postural' | 'habilidade'
  final String
  stage; // 'not_trained' | 'introduced' | 'developing' | 'consolidated' | 'operational'
  final String? description;
  final DateTime? learnedAt;
  final DateTime? masteredAt;
  final DateTime lastUpdatedAt;
  final String lastUpdatedBy;
  final DateTime? deletedAt;
  final String? deletedBy;
  final String? deleteReason;

  DogCommand({
    this.id,
    required this.name,
    required this.category,
    this.stage = 'not_trained',
    this.description,
    this.learnedAt,
    this.masteredAt,
    required this.lastUpdatedAt,
    required this.lastUpdatedBy,
    this.deletedAt,
    this.deletedBy,
    this.deleteReason,
  });

  factory DogCommand.fromJson(Map<String, dynamic> json, {String? docId}) {
    return DogCommand(
      id: docId ?? json['id'] as String?,
      name: json['name'] as String? ?? '',
      category: json['category'] as String? ?? 'operacional',
      stage: json['stage'] as String? ?? 'not_trained',
      description: json['description'] as String?,
      learnedAt: _toDateTime(json['learned_at']),
      masteredAt: _toDateTime(json['mastered_at']),
      lastUpdatedAt: _toDateTime(json['last_updated_at']) ?? DateTime.now(),
      lastUpdatedBy: json['last_updated_by'] as String? ?? '',
      deletedAt: _toDateTime(json['deleted_at']),
      deletedBy: json['deleted_by'] as String?,
      deleteReason:
          json['delete_reason'] as String? ?? json['deleted_reason'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'category': category,
      'stage': stage,
      if (description != null) 'description': description,
      if (learnedAt != null) 'learned_at': Timestamp.fromDate(learnedAt!),
      if (masteredAt != null) 'mastered_at': Timestamp.fromDate(masteredAt!),
      'last_updated_at': Timestamp.fromDate(lastUpdatedAt),
      'last_updated_by': lastUpdatedBy,
      if (deletedAt != null) 'deleted_at': Timestamp.fromDate(deletedAt!),
      if (deletedBy != null) 'deleted_by': deletedBy,
      if (deleteReason != null) 'delete_reason': deleteReason,
    };
  }

  DogCommand copyWith({
    String? id,
    String? name,
    String? category,
    String? stage,
    String? description,
    DateTime? learnedAt,
    DateTime? masteredAt,
    DateTime? lastUpdatedAt,
    String? lastUpdatedBy,
    DateTime? deletedAt,
    String? deletedBy,
    String? deleteReason,
  }) {
    return DogCommand(
      id: id ?? this.id,
      name: name ?? this.name,
      category: category ?? this.category,
      stage: stage ?? this.stage,
      description: description ?? this.description,
      learnedAt: learnedAt ?? this.learnedAt,
      masteredAt: masteredAt ?? this.masteredAt,
      lastUpdatedAt: lastUpdatedAt ?? this.lastUpdatedAt,
      lastUpdatedBy: lastUpdatedBy ?? this.lastUpdatedBy,
      deletedAt: deletedAt ?? this.deletedAt,
      deletedBy: deletedBy ?? this.deletedBy,
      deleteReason: deleteReason ?? this.deleteReason,
    );
  }

  bool get isDeleted => deletedAt != null;

  static const List<String> stages = [
    'not_trained',
    'introduced',
    'developing',
    'consolidated',
    'operational',
  ];

  static const List<String> categories = [
    'operacional',
    'posicional',
    'postural',
    'habilidade',
  ];

  static DateTime? _toDateTime(dynamic value) {
    if (value == null) return null;
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    return null;
  }
}
