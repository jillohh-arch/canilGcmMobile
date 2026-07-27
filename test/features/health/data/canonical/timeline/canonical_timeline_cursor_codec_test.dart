import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:canil_gcm/features/health/data/canonical/timeline/canonical_timeline_cursor_codec.dart';
import 'package:canil_gcm/features/health/presentation/timeline/health_timeline_cursor.dart';
import 'package:canil_gcm/features/health/presentation/timeline/health_timeline_query.dart';
import 'package:canil_gcm/features/health/presentation/timeline/health_timeline_source.dart';

void main() {
  const dogId = 'dog_001';
  final query = HealthTimelineQuery(dogId: dogId, pageSize: 20);
  final timestamp = Timestamp(1785045600, 514000000);
  const documentId = 'tl1_abc123';

  group('CanonicalTimelineCursorCodec', () {
    test(
      'round-trip completo preserva segundos, nanossegundos e documentId',
      () {
        final cursor = CanonicalTimelineCursorCodec.encode(
          dogId: dogId,
          query: query,
          timestamp: timestamp,
          documentId: documentId,
        );

        expect(cursor, isA<HealthTimelineCursor>());
        expect(cursor.token.isNotEmpty, isTrue);

        final decoded = CanonicalTimelineCursorCodec.decode(
          cursor,
          dogId: dogId,
          query: query,
        );

        expect(decoded.dogId, equals(dogId));
        expect(decoded.seconds, equals(1785045600));
        expect(decoded.nanoseconds, equals(514000000));
        expect(decoded.timestamp, equals(timestamp));
        expect(decoded.documentId, equals(documentId));
        expect(decoded.sortDirection, equals('DESC'));
      },
    );

    test('token é determinístico para mesmos parâmetros', () {
      final cursor1 = CanonicalTimelineCursorCodec.encode(
        dogId: dogId,
        query: query,
        timestamp: timestamp,
        documentId: documentId,
      );
      final cursor2 = CanonicalTimelineCursorCodec.encode(
        dogId: dogId,
        query: query,
        timestamp: timestamp,
        documentId: documentId,
      );

      expect(cursor1.token, equals(cursor2.token));
    });

    test('rejeita Base64 inválido', () {
      const invalidCursor = HealthTimelineCursor('@@@_invalid_base64_@@@');
      expect(
        () => CanonicalTimelineCursorCodec.decode(
          invalidCursor,
          dogId: dogId,
          query: query,
        ),
        throwsA(
          isA<HealthTimelineSourceException>().having(
            (e) => e.message,
            'message',
            equals('cursor_corrupted'),
          ),
        ),
      );
    });

    test('rejeita JSON inválido', () {
      final invalidJsonToken = base64Url.encode(utf8.encode('not_a_json_map'));
      final cursor = HealthTimelineCursor(invalidJsonToken);
      expect(
        () => CanonicalTimelineCursorCodec.decode(
          cursor,
          dogId: dogId,
          query: query,
        ),
        throwsA(
          isA<HealthTimelineSourceException>().having(
            (e) => e.message,
            'message',
            equals('cursor_corrupted'),
          ),
        ),
      );
    });

    test('rejeita versão desconhecida do cursor', () {
      final jsonMap = {
        'v': 99,
        'dogId': dogId,
        'fp': CanonicalTimelineCursorCodec.computeQueryFingerprint(query),
        's': 1785045600,
        'ns': 514000000,
        'docId': documentId,
        'dir': 'DESC',
      };
      final token = base64Url.encode(utf8.encode(jsonEncode(jsonMap)));
      final cursor = HealthTimelineCursor(token);

      expect(
        () => CanonicalTimelineCursorCodec.decode(
          cursor,
          dogId: dogId,
          query: query,
        ),
        throwsA(
          isA<HealthTimelineSourceException>().having(
            (e) => e.message,
            'message',
            equals('cursor_version_unsupported'),
          ),
        ),
      );
    });

    test('rejeita cursor com dogId divergente (outro cão)', () {
      final cursor = CanonicalTimelineCursorCodec.encode(
        dogId: 'dog_OTHER_999',
        query: HealthTimelineQuery(dogId: 'dog_OTHER_999', pageSize: 20),
        timestamp: timestamp,
        documentId: documentId,
      );

      expect(
        () => CanonicalTimelineCursorCodec.decode(
          cursor,
          dogId: dogId,
          query: query,
        ),
        throwsA(
          isA<HealthTimelineSourceException>().having(
            (e) => e.message,
            'message',
            equals('cursor_dog_mismatch'),
          ),
        ),
      );
    });

    test('rejeita cursor de outra query (fingerprint divergente)', () {
      final differentQuery = HealthTimelineQuery(dogId: dogId, pageSize: 50);
      final cursor = CanonicalTimelineCursorCodec.encode(
        dogId: dogId,
        query: differentQuery,
        timestamp: timestamp,
        documentId: documentId,
      );

      expect(
        () => CanonicalTimelineCursorCodec.decode(
          cursor,
          dogId: dogId,
          query: query,
        ),
        throwsA(
          isA<HealthTimelineSourceException>().having(
            (e) => e.message,
            'message',
            equals('cursor_query_mismatch'),
          ),
        ),
      );
    });

    test('rejeita documentId vazio no encode e decode', () {
      expect(
        () => CanonicalTimelineCursorCodec.encode(
          dogId: dogId,
          query: query,
          timestamp: timestamp,
          documentId: '  ',
        ),
        throwsA(isA<HealthTimelineSourceException>()),
      );
    });

    test('rejeita nanossegundos fora da faixa 0..999999999', () {
      final jsonMap = {
        'v': 1,
        'dogId': dogId,
        'fp': CanonicalTimelineCursorCodec.computeQueryFingerprint(query),
        's': 1785045600,
        'ns': 1000000000, // nanosegundos inválidos (> 999999999)
        'docId': documentId,
        'dir': 'DESC',
      };
      final token = base64Url.encode(utf8.encode(jsonEncode(jsonMap)));
      final cursor = HealthTimelineCursor(token);

      expect(
        () => CanonicalTimelineCursorCodec.decode(
          cursor,
          dogId: dogId,
          query: query,
        ),
        throwsA(
          isA<HealthTimelineSourceException>().having(
            (e) => e.message,
            'message',
            equals('cursor_invalid_timestamp'),
          ),
        ),
      );
    });

    test('rejeita direção divergente ou ausente', () {
      for (final dirVal in ['ASC', null, 123]) {
        final jsonMap = <String, dynamic>{
          'v': 1,
          'dogId': dogId,
          'fp': CanonicalTimelineCursorCodec.computeQueryFingerprint(query),
          's': 1785045600,
          'ns': 514000000,
          'docId': documentId,
        };
        if (dirVal != null) {
          jsonMap['dir'] = dirVal;
        }
        final token = base64Url.encode(utf8.encode(jsonEncode(jsonMap)));
        final cursor = HealthTimelineCursor(token);

        expect(
          () => CanonicalTimelineCursorCodec.decode(
            cursor,
            dogId: dogId,
            query: query,
          ),
          throwsA(
            isA<HealthTimelineSourceException>().having(
              (e) => e.message,
              'message',
              equals('cursor_direction_mismatch'),
            ),
          ),
        );
      }
    });

    test(
      'rejeita dogId ou fp ausente, vazio, somente espaços ou tipo incorreto',
      () {
        final invalidValues = [null, '', '   ', 12345];
        for (final val in invalidValues) {
          // Invalid dogId
          var map1 = {
            'v': 1,
            'fp': CanonicalTimelineCursorCodec.computeQueryFingerprint(query),
            's': 1785045600,
            'ns': 514000000,
            'docId': documentId,
            'dir': 'DESC',
          };
          if (val != null) map1['dogId'] = val;
          expect(
            () => CanonicalTimelineCursorCodec.decode(
              HealthTimelineCursor(
                base64Url.encode(utf8.encode(jsonEncode(map1))),
              ),
              dogId: dogId,
              query: query,
            ),
            throwsA(isA<HealthTimelineSourceException>()),
          );

          // Invalid fp
          var map2 = {
            'v': 1,
            'dogId': dogId,
            's': 1785045600,
            'ns': 514000000,
            'docId': documentId,
            'dir': 'DESC',
          };
          if (val != null) map2['fp'] = val;
          expect(
            () => CanonicalTimelineCursorCodec.decode(
              HealthTimelineCursor(
                base64Url.encode(utf8.encode(jsonEncode(map2))),
              ),
              dogId: dogId,
              query: query,
            ),
            throwsA(isA<HealthTimelineSourceException>()),
          );
        }
      },
    );

    test('rejeita s ou ns ausentes ou com tipo incorreto', () {
      final invalidTsValues = [null, '123', 45.67];
      for (final val in invalidTsValues) {
        var mapS = {
          'v': 1,
          'dogId': dogId,
          'fp': CanonicalTimelineCursorCodec.computeQueryFingerprint(query),
          'ns': 514000000,
          'docId': documentId,
          'dir': 'DESC',
        };
        if (val != null) mapS['s'] = val;
        expect(
          () => CanonicalTimelineCursorCodec.decode(
            HealthTimelineCursor(
              base64Url.encode(utf8.encode(jsonEncode(mapS))),
            ),
            dogId: dogId,
            query: query,
          ),
          throwsA(isA<HealthTimelineSourceException>()),
        );

        var mapNs = {
          'v': 1,
          'dogId': dogId,
          'fp': CanonicalTimelineCursorCodec.computeQueryFingerprint(query),
          's': 1785045600,
          'docId': documentId,
          'dir': 'DESC',
        };
        if (val != null) mapNs['ns'] = val;
        expect(
          () => CanonicalTimelineCursorCodec.decode(
            HealthTimelineCursor(
              base64Url.encode(utf8.encode(jsonEncode(mapNs))),
            ),
            dogId: dogId,
            query: query,
          ),
          throwsA(isA<HealthTimelineSourceException>()),
        );
      }
    });

    test('aceita segundos negativos válidos (datas históricas)', () {
      final cursor = CanonicalTimelineCursorCodec.encode(
        dogId: dogId,
        query: query,
        timestamp: Timestamp(-100, 500),
        documentId: documentId,
      );

      final decoded = CanonicalTimelineCursorCodec.decode(
        cursor,
        dogId: dogId,
        query: query,
      );

      expect(decoded.seconds, equals(-100));
      expect(decoded.nanoseconds, equals(500));
    });

    test('rejeita docId ausente, vazio, somente espaços ou tipo incorreto', () {
      for (final val in [null, '', '   ', 999]) {
        final map = {
          'v': 1,
          'dogId': dogId,
          'fp': CanonicalTimelineCursorCodec.computeQueryFingerprint(query),
          's': 1785045600,
          'ns': 514000000,
          'dir': 'DESC',
        };
        if (val != null) map['docId'] = val;
        final token = base64Url.encode(utf8.encode(jsonEncode(map)));
        expect(
          () => CanonicalTimelineCursorCodec.decode(
            HealthTimelineCursor(token),
            dogId: dogId,
            query: query,
          ),
          throwsA(isA<HealthTimelineSourceException>()),
        );
      }
    });
  });
}
