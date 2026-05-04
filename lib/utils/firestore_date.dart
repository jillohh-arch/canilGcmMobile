import 'package:cloud_firestore/cloud_firestore.dart';

DateTime parseFirestoreDate(dynamic value, {DateTime? fallback}) {
  if (value is Timestamp) return value.toDate();
  if (value is DateTime) return value;
  if (value is String && value.isNotEmpty) {
    final parsed = DateTime.tryParse(value);
    if (parsed != null) return parsed;
  }
  return fallback ?? DateTime.now();
}
