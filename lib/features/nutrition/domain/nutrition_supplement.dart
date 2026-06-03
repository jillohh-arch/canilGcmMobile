import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:canil_gcm/core/mixins/soft_deletable.dart';

class NutritionSupplement with SoftDeletable {
  final String? id;
  final String name;
  final String dose;
  final DateTime startedAt;
  final DateTime? endedAt;
  final String status;
  final String? notes;
  final String? createdBy;
  final List<Map<String, dynamic>> auditTrail;

  @override
  final DateTime? deletedAt;
  @override
  final String? deletedBy;
  @override
  final String? deleteReason;

  const NutritionSupplement({
    this.id,
    required this.name,
    required this.dose,
    required this.startedAt,
    this.endedAt,
    this.status = 'em_uso',
    this.notes,
    this.createdBy,
    this.auditTrail = const [],
    this.deletedAt,
    this.deletedBy,
    this.deleteReason,
  });

  bool get isActive =>
      !isDeleted && endedAt == null && status.toLowerCase() != 'suspenso';

  factory NutritionSupplement.fromJson(
    Map<String, dynamic> json, {
    String? docId,
  }) {
    return NutritionSupplement(
      id: docId ?? json['id'] as String?,
      name: json['name'] as String? ?? '',
      dose: json['dose'] as String? ?? '',
      startedAt: _toDateTime(json['started_at']) ?? DateTime.now(),
      endedAt: _toDateTime(json['ended_at']),
      status: json['status'] as String? ?? 'em_uso',
      notes: json['notes'] as String?,
      createdBy: json['created_by'] as String?,
      auditTrail:
          (json['audit_trail'] as List<dynamic>?)
              ?.whereType<Map>()
              .map(
                (e) => e.map((key, value) => MapEntry(key.toString(), value)),
              )
              .toList() ??
          const [],
      deletedAt: SoftDeletable.parseDeletedAt(json['deleted_at']),
      deletedBy: json['deleted_by'] as String?,
      deleteReason:
          json['deleted_reason'] as String? ?? json['delete_reason'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'dose': dose,
      'started_at': Timestamp.fromDate(startedAt),
      if (endedAt != null) 'ended_at': Timestamp.fromDate(endedAt!),
      'status': status,
      if (notes != null) 'notes': notes,
      if (createdBy != null) 'created_by': createdBy,
      'audit_trail': auditTrail,
      ...softDeleteFields(),
    };
  }

  static DateTime? _toDateTime(dynamic value) {
    if (value == null) return null;
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    return null;
  }
}
