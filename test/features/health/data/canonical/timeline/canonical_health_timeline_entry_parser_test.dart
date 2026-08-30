import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:canil_gcm/features/health/data/canonical/timeline/canonical_health_timeline_entry_parser.dart';
import 'package:canil_gcm/features/health/domain/health_v1_enums_ext.dart';
import 'package:canil_gcm/features/health/presentation/timeline/health_timeline_entry_view.dart';
import 'package:canil_gcm/features/health/presentation/timeline/health_timeline_source.dart';

void main() {
  const dogId = 'dog_001';
  final now = DateTime.utc(2026, 7, 26, 10, 0, 0);
  final nowTimestamp = Timestamp.fromDate(now);

  Map<String, dynamic> validMealDoc() {
    return {
      'timeline_type': 'meal',
      'source_collection': 'dogs/$dogId/meal_logs',
      'source_id': 'ml_001',
      'occurred_at': nowTimestamp,
      'recorded_at': nowTimestamp,
      'projected_at': nowTimestamp,
      'title': 'Refeição Matinal',
      'subtitle': 'Ração Canina 250g',
      'dog_id': dogId,
      'recorded_by': {
        'uid': 'user_001',
        'name': 'GCM Silva',
        'internal_role': 'operador',
      },
      'status': 'final',
      'schema_version': 1,
    };
  }

  group('CanonicalHealthTimelineEntryParser', () {
    test('parse meal válido com sucesso', () {
      final data = validMealDoc();
      final view = CanonicalHealthTimelineEntryParser.parseDocument(
        documentId: 'tl1_001',
        data: data,
        queryDogId: dogId,
      );

      expect(view.id, equals('tl1_001'));
      expect(view.dogId, equals(dogId));
      expect(view.type.known, equals(HealthTimelineType.meal));
      expect(view.title, equals('Refeição Matinal'));
      expect(view.subtitle, equals('Ração Canina 250g'));
      expect(view.status, equals(HealthTimelineEntryStatus.finalised));
      expect(view.recordedBy?.uid, equals('user_001'));
      expect(view.recordedBy?.internalRole, equals('operador'));
    });

    test('parse supplement válido com status cancelled', () {
      final data = validMealDoc()
        ..['timeline_type'] = 'supplement'
        ..['title'] = 'Suplemento Omega 3'
        ..['status'] = 'cancelled';

      final view = CanonicalHealthTimelineEntryParser.parseDocument(
        documentId: 'tl1_002',
        data: data,
        queryDogId: dogId,
      );

      expect(view.type.known, equals(HealthTimelineType.supplement));
      expect(view.title, equals('Suplemento Omega 3'));
      expect(view.status, equals(HealthTimelineEntryStatus.cancelled));
      expect(view.isCancelled, isTrue);
    });

    test('subtitle ausente resulta em null sem falhar o documento', () {
      final data = validMealDoc()..remove('subtitle');
      final view = CanonicalHealthTimelineEntryParser.parseDocument(
        documentId: 'tl1_003',
        data: data,
        queryDogId: dogId,
      );

      expect(view.subtitle, null);
    });

    test('timeline_type desconhecido gera tipo unknown visual sem falhar', () {
      final data = validMealDoc()..['timeline_type'] = 'future_type_v2';
      final view = CanonicalHealthTimelineEntryParser.parseDocument(
        documentId: 'tl1_004',
        data: data,
        queryDogId: dogId,
      );

      expect(view.type.isUnknown, isTrue);
      expect(view.type.raw, equals('future_type_v2'));
      expect(view.type.known, isNull);
    });

    test('rejeita cada campo obrigatório quando ausente ou nulo', () {
      final fields = [
        'timeline_type',
        'source_collection',
        'source_id',
        'occurred_at',
        'recorded_at',
        'projected_at',
        'title',
        'dog_id',
        'recorded_by',
        'status',
        'schema_version',
      ];

      for (final field in fields) {
        final data = validMealDoc()..remove(field);
        expect(
          () => CanonicalHealthTimelineEntryParser.parseDocument(
            documentId: 'tl1_err',
            data: data,
            queryDogId: dogId,
          ),
          throwsA(isA<HealthTimelineSourceException>()),
          reason: 'Campo $field ausente deve falhar o documento',
        );
      }
    });

    test('rejeita campo obrigatório com tipo incorreto', () {
      final invalidTypesMap = {
        'timeline_type': 123,
        'source_collection': 456,
        'source_id': true,
        'occurred_at': 'not_a_timestamp',
        'recorded_at': 'not_a_timestamp',
        'projected_at': 'not_a_timestamp',
        'title': 999,
        'dog_id': 888,
        'recorded_by': 'string_instead_of_map',
        'status': 12345,
        'schema_version': '1_string',
      };

      invalidTypesMap.forEach((field, invalidVal) {
        final data = validMealDoc()..[field] = invalidVal;
        expect(
          () => CanonicalHealthTimelineEntryParser.parseDocument(
            documentId: 'tl1_err_type',
            data: data,
            queryDogId: dogId,
          ),
          throwsA(isA<HealthTimelineSourceException>()),
          reason: 'Campo $field com tipo incorreto deve falhar',
        );
      });
    });

    test('rejeita recorded_by incompleto', () {
      final incompleteRecordedBys = [
        {'uid': 'u1', 'name': 'Silva'}, // sem internal_role
        {'uid': 'u1', 'internal_role': 'operador'}, // sem name
        {'name': 'Silva', 'internal_role': 'operador'}, // sem uid
      ];

      for (final inc in incompleteRecordedBys) {
        final data = validMealDoc()..['recorded_by'] = inc;
        expect(
          () => CanonicalHealthTimelineEntryParser.parseDocument(
            documentId: 'tl1_inc',
            data: data,
            queryDogId: dogId,
          ),
          throwsA(isA<HealthTimelineSourceException>()),
        );
      }
    });

    test('rejeita status desconhecido sem converter para final', () {
      final data = validMealDoc()..['status'] = 'invalid_unknown_status';
      expect(
        () => CanonicalHealthTimelineEntryParser.parseDocument(
          documentId: 'tl1_status_err',
          data: data,
          queryDogId: dogId,
        ),
        throwsA(
          isA<HealthTimelineSourceException>().having(
            (e) => e.message,
            'message',
            equals('invalid_status'),
          ),
        ),
      );
    });

    test('rejeita schema_version ausente ou diferente de 1', () {
      final data1 = validMealDoc()..remove('schema_version');
      expect(
        () => CanonicalHealthTimelineEntryParser.parseDocument(
          documentId: 'tl1_schema_1',
          data: data1,
          queryDogId: dogId,
        ),
        throwsA(isA<HealthTimelineSourceException>()),
      );

      final data2 = validMealDoc()..['schema_version'] = 2;
      expect(
        () => CanonicalHealthTimelineEntryParser.parseDocument(
          documentId: 'tl1_schema_2',
          data: data2,
          queryDogId: dogId,
        ),
        throwsA(isA<HealthTimelineSourceException>()),
      );
    });

    test(
      'rejeita dog_id divergente do queryDogId (cross-dog contamination)',
      () {
        final data = validMealDoc()..['dog_id'] = 'dog_OTHER_999';
        expect(
          () => CanonicalHealthTimelineEntryParser.parseDocument(
            documentId: 'tl1_cross',
            data: data,
            queryDogId: dogId,
          ),
          throwsA(
            isA<HealthTimelineSourceException>().having(
              (e) => e.message,
              'message',
              equals('cross_dog_contamination'),
            ),
          ),
        );
      },
    );

    test(
      'rejeita campos de texto obrigatórios compostos somente por espaços',
      () {
        final whitespaceFields = [
          'title',
          'source_id',
          'source_collection',
          'dog_id',
        ];

        for (final field in whitespaceFields) {
          final data = validMealDoc()..[field] = '   ';
          expect(
            () => CanonicalHealthTimelineEntryParser.parseDocument(
              documentId: 'tl1_ws_$field',
              data: data,
              queryDogId: dogId,
            ),
            throwsA(isA<HealthTimelineSourceException>()),
            reason: 'Campo $field com apenas espaços deve falhar',
          );
        }
      },
    );

    test('rejeita recorded_by.internal_role composto somente por espaços', () {
      final data = validMealDoc()
        ..['recorded_by'] = {
          'uid': 'u1',
          'name': 'GCM Silva',
          'internal_role': '   ',
        };

      expect(
        () => CanonicalHealthTimelineEntryParser.parseDocument(
          documentId: 'tl1_role_ws',
          data: data,
          queryDogId: dogId,
        ),
        throwsA(isA<HealthTimelineSourceException>()),
      );
    });

    test('rejeita attachment_count negativo ou não inteiro', () {
      final invalidCounts = [-1, 2.5, '3'];
      for (final count in invalidCounts) {
        final data = validMealDoc()..['attachment_count'] = count;
        expect(
          () => CanonicalHealthTimelineEntryParser.parseDocument(
            documentId: 'tl1_att_err',
            data: data,
            queryDogId: dogId,
          ),
          throwsA(
            isA<HealthTimelineSourceException>().having(
              (e) => e.message,
              'message',
              equals('invalid_attachment_count'),
            ),
          ),
        );
      }
    });
  });
}
