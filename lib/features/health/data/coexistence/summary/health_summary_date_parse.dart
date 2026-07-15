import 'package:cloud_firestore/cloud_firestore.dart';

/// Parser defensivo de datas para a 2D (sem fallback para DateTime.now()).
///
/// Aceita Timestamp, DateTime, ISO string e maps legados seconds/nanoseconds.
/// Valor inválido → null (registro ignorado, não derruba o Summary).
abstract final class HealthSummaryDateParse {
  HealthSummaryDateParse._();

  static DateTime? tryParse(Object? value) {
    if (value == null) return null;
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    if (value is String) {
      final t = value.trim();
      if (t.isEmpty) return null;
      return DateTime.tryParse(t);
    }
    if (value is Map) {
      final seconds = value['seconds'] ?? value['_seconds'];
      final nanos = value['nanoseconds'] ?? value['_nanoseconds'] ?? 0;
      if (seconds is int) {
        return DateTime.fromMillisecondsSinceEpoch(
          seconds * 1000 + ((nanos is int ? nanos : 0) ~/ 1000000),
          isUtc: true,
        ).toLocal();
      }
      if (seconds is num) {
        return DateTime.fromMillisecondsSinceEpoch(
          (seconds * 1000).round() + ((nanos is num ? nanos : 0) ~/ 1000000),
          isUtc: true,
        ).toLocal();
      }
    }
    return null;
  }
}
