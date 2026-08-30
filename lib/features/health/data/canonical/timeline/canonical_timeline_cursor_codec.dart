import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:crypto/crypto.dart';
import 'package:canil_gcm/features/health/presentation/timeline/health_timeline_cursor.dart';
import 'package:canil_gcm/features/health/presentation/timeline/health_timeline_query.dart';
import 'package:canil_gcm/features/health/presentation/timeline/health_timeline_source.dart';

/// Estado descompactado do cursor da projeção canônica health_timeline.
final class CanonicalTimelineCursorPosition {
  const CanonicalTimelineCursorPosition({
    required this.version,
    required this.dogId,
    required this.filterFingerprint,
    required this.seconds,
    required this.nanoseconds,
    required this.documentId,
    this.sortDirection = 'DESC',
  });

  static const int currentVersion = 1;

  final int version;
  final String dogId;
  final String filterFingerprint;
  final int seconds;
  final int nanoseconds;
  final String documentId;
  final String sortDirection;

  Timestamp get timestamp => Timestamp(seconds, nanoseconds);

  Map<String, Object?> toJson() => {
    'v': version,
    'dogId': dogId,
    'fp': filterFingerprint,
    's': seconds,
    'ns': nanoseconds,
    'docId': documentId,
    'dir': sortDirection,
  };
}

/// Codec do cursor opaco da projeção canônica health_timeline.
///
/// Codifica/decodifica [HealthTimelineCursor] sem perda de precisão do Firestore Timestamp.
/// Utiliza SHA-256 da biblioteca `crypto` para a identidade determinística da query.
abstract final class CanonicalTimelineCursorCodec {
  CanonicalTimelineCursorCodec._();

  /// Calcula o fingerprint SHA-256 determinístico das propriedades da query.
  static String computeQueryFingerprint(HealthTimelineQuery query) {
    final sortedTypes = query.types.map((t) => t.wireName).toList()..sort();

    final map = <String, Object?>{
      'dogId': query.dogId,
      'pageSize': query.pageSize,
      'types': sortedTypes,
      'startIso': query.period.start?.toUtc().toIso8601String(),
      'endIso': query.period.end?.toUtc().toIso8601String(),
      'caseId': query.caseId,
      'profName': query.professional?.name,
      'profReg': query.professional?.registrationNumber,
    };

    final canonicalJson = jsonEncode(map);
    return sha256.convert(utf8.encode(canonicalJson)).toString();
  }

  /// Codifica uma posição em [HealthTimelineCursor] opaco em Base64.
  static HealthTimelineCursor encode({
    required String dogId,
    required HealthTimelineQuery query,
    required Timestamp timestamp,
    required String documentId,
  }) {
    if (documentId.trim().isEmpty) {
      throw const HealthTimelineSourceException('cursor_invalid_document_id');
    }
    final position = CanonicalTimelineCursorPosition(
      version: CanonicalTimelineCursorPosition.currentVersion,
      dogId: dogId,
      filterFingerprint: computeQueryFingerprint(query),
      seconds: timestamp.seconds,
      nanoseconds: timestamp.nanoseconds,
      documentId: documentId.trim(),
      sortDirection: 'DESC',
    );

    final jsonStr = jsonEncode(position.toJson());
    final token = base64Url.encode(utf8.encode(jsonStr));
    return HealthTimelineCursor(token);
  }

  /// Decodifica e valida o [cursor] opaco.
  ///
  /// Lança [HealthTimelineSourceException] caso qualquer regra de segurança falhe.
  static CanonicalTimelineCursorPosition decode(
    HealthTimelineCursor cursor, {
    required String dogId,
    required HealthTimelineQuery query,
  }) {
    final token = cursor.token.trim();
    if (token.isEmpty) {
      throw const HealthTimelineSourceException('cursor_corrupted');
    }

    List<int> bytes;
    try {
      bytes = base64Url.decode(token);
    } catch (_) {
      throw const HealthTimelineSourceException('cursor_corrupted');
    }

    Map<String, dynamic> map;
    try {
      final jsonStr = utf8.decode(bytes);
      final decoded = jsonDecode(jsonStr);
      if (decoded is! Map) {
        throw const HealthTimelineSourceException('cursor_invalid_schema');
      }
      map = Map<String, dynamic>.from(decoded);
    } catch (e) {
      if (e is HealthTimelineSourceException) rethrow;
      throw const HealthTimelineSourceException('cursor_corrupted');
    }

    final version = map['v'];
    if (version != CanonicalTimelineCursorPosition.currentVersion) {
      throw const HealthTimelineSourceException('cursor_version_unsupported');
    }

    final rawDogId = map['dogId'];
    if (rawDogId is! String || rawDogId.trim().isEmpty) {
      throw const HealthTimelineSourceException('cursor_invalid_schema');
    }
    if (rawDogId.trim() != dogId) {
      throw const HealthTimelineSourceException('cursor_dog_mismatch');
    }

    final rawFp = map['fp'];
    if (rawFp is! String || rawFp.trim().isEmpty) {
      throw const HealthTimelineSourceException('cursor_invalid_schema');
    }
    final expectedFp = computeQueryFingerprint(query);
    if (rawFp != expectedFp) {
      throw const HealthTimelineSourceException('cursor_query_mismatch');
    }

    final rawDir = map['dir'];
    if (rawDir is! String || rawDir != 'DESC') {
      throw const HealthTimelineSourceException('cursor_direction_mismatch');
    }

    final seconds = map['s'];
    final nanoseconds = map['ns'];
    if (seconds is! int || nanoseconds is! int) {
      throw const HealthTimelineSourceException('cursor_invalid_timestamp');
    }
    if (nanoseconds < 0 || nanoseconds > 999999999) {
      throw const HealthTimelineSourceException('cursor_invalid_timestamp');
    }

    final rawDocId = map['docId'];
    if (rawDocId is! String || rawDocId.trim().isEmpty) {
      throw const HealthTimelineSourceException('cursor_invalid_document_id');
    }

    try {
      // Validate that Timestamp can be instantiated with these seconds & nanoseconds
      Timestamp(seconds, nanoseconds);
    } catch (_) {
      throw const HealthTimelineSourceException('cursor_invalid_timestamp');
    }

    return CanonicalTimelineCursorPosition(
      version: version as int,
      dogId: rawDogId.trim(),
      filterFingerprint: rawFp.trim(),
      seconds: seconds,
      nanoseconds: nanoseconds,
      documentId: rawDocId.trim(),
      sortDirection: rawDir,
    );
  }
}
