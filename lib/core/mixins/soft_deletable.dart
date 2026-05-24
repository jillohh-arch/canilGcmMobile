import 'package:cloud_firestore/cloud_firestore.dart';

mixin SoftDeletable {
  DateTime? get deletedAt;
  String? get deletedBy;
  String? get deleteReason;

  bool get isDeleted => deletedAt != null;

  Map<String, dynamic> softDeleteFields() => {
    'deleted_at': deletedAt != null ? Timestamp.fromDate(deletedAt!) : null,
    'deleted_by': deletedBy,
    'delete_reason': deleteReason,
    'deleted_reason': deleteReason,
  };

  static Query<Map<String, dynamic>> activeOnly(
    Query<Map<String, dynamic>> query,
  ) => query.where('deleted_at', isNull: true);

  static DateTime? parseDeletedAt(dynamic value) {
    if (value == null) return null;
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    if (value is String) return DateTime.tryParse(value);
    return null;
  }
}
