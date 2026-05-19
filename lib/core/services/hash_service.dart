import 'dart:collection';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:crypto/crypto.dart';

class HashService {
  static String computeHash(Map<String, dynamic> data) {
    final serialized = _serialize(data);
    final bytes = utf8.encode(serialized);
    return sha256.convert(bytes).toString();
  }

  static bool verify(Map<String, dynamic> data, String storedHash) {
    return computeHash(data) == storedHash;
  }

  static String _serialize(Map<String, dynamic> data) {
    final normalized = _normalizeValue(data);
    return jsonEncode(normalized);
  }

  static dynamic _normalizeValue(dynamic value) {
    if (value == null) return null;
    if (value is Timestamp) return value.toDate().toUtc().toIso8601String();
    if (value is DateTime) return value.toUtc().toIso8601String();
    if (value is Map<String, dynamic>) return _normalizeMap(value);
    if (value is Map) {
      return _normalizeMap(Map<String, dynamic>.from(value));
    }
    if (value is List) return value.map(_normalizeValue).toList();
    return value;
  }

  static Map<String, dynamic> _normalizeMap(Map<String, dynamic> map) {
    final sorted = SplayTreeMap<String, dynamic>.from(map);
    return sorted.map((key, value) => MapEntry(key, _normalizeValue(value)));
  }
}
