import 'package:cloud_firestore/cloud_firestore.dart';

/// Parser defensivo de datas para `health_schedule` (4C).
///
/// Aceita [Timestamp], [DateTime], ISO string e maps seconds/nanoseconds.
/// Valor inválido → null (sem [DateTime.now]).
abstract final class HealthScheduleDateParse {
  HealthScheduleDateParse._();

  static DateTime? tryParse(Object? value) {
    if (value == null) return null;
    if (value is Timestamp) return value.toDate().toUtc();
    if (value is DateTime) return value.toUtc();
    if (value is String) {
      final t = value.trim();
      if (t.isEmpty) return null;
      return DateTime.tryParse(t)?.toUtc();
    }
    if (value is Map) {
      final seconds = value['seconds'] ?? value['_seconds'];
      final nanos = value['nanoseconds'] ?? value['_nanoseconds'] ?? 0;
      if (seconds is int) {
        return DateTime.fromMillisecondsSinceEpoch(
          seconds * 1000 + ((nanos is int ? nanos : 0) ~/ 1000000),
          isUtc: true,
        );
      }
      if (seconds is num) {
        return DateTime.fromMillisecondsSinceEpoch(
          (seconds * 1000).round() + ((nanos is num ? nanos : 0) ~/ 1000000),
          isUtc: true,
        );
      }
    }
    return null;
  }

  /// Obrigatório: null se ausente/inválido (caller lança integrity).
  static DateTime? parseRequired(Object? value) => tryParse(value);
}
