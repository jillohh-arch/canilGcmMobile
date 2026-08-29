import 'dart:convert';

import 'package:canil_gcm/features/health/presentation/schedule/health_schedule_cursor.dart';

/// Posição opaca de paginação da Agenda (sem tipos Firebase).
///
/// Token = base64url(JSON) com:
/// - `atMs`: scheduled_for em UTC epoch ms
/// - `id`: documentId
final class HealthScheduleCursorPosition {
  const HealthScheduleCursorPosition({
    required this.scheduledFor,
    required this.documentId,
  });

  final DateTime scheduledFor;
  final String documentId;
}

/// Codec do [HealthScheduleCursor] para paginação determinística.
abstract final class HealthScheduleCursorCodec {
  HealthScheduleCursorCodec._();

  static HealthScheduleCursor encode(HealthScheduleCursorPosition position) {
    final payload = <String, Object?>{
      'v': 1,
      'atMs': position.scheduledFor.toUtc().millisecondsSinceEpoch,
      'id': position.documentId,
    };
    final raw = base64UrlEncode(utf8.encode(jsonEncode(payload)));
    return HealthScheduleCursor(raw);
  }

  static HealthScheduleCursorPosition decode(HealthScheduleCursor cursor) {
    try {
      final json =
          jsonDecode(utf8.decode(base64Url.decode(cursor.token))) as Object?;
      if (json is! Map) {
        throw const FormatException('cursor payload inválido');
      }
      final map = Map<String, dynamic>.from(json);
      final atMs = map['atMs'];
      final id = map['id'];
      if (atMs is! int || id is! String || id.trim().isEmpty) {
        throw const FormatException('cursor incompleto');
      }
      return HealthScheduleCursorPosition(
        scheduledFor: DateTime.fromMillisecondsSinceEpoch(atMs, isUtc: true),
        documentId: id.trim(),
      );
    } on FormatException {
      rethrow;
    } catch (e) {
      throw FormatException('cursor ilegível: $e');
    }
  }
}
