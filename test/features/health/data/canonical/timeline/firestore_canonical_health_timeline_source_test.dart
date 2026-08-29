// ignore_for_file: subtype_of_sealed_class, annotate_overrides

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:canil_gcm/features/health/data/canonical/timeline/firestore_canonical_health_timeline_source.dart';
import 'package:canil_gcm/features/health/domain/health_v1_enums_ext.dart';
import 'package:canil_gcm/features/health/presentation/timeline/health_timeline_query.dart';
import 'package:canil_gcm/features/health/presentation/timeline/health_timeline_source.dart';

/// In-memory fake of [FirebaseFirestore] tailored for testing composite value
/// pagination with [FieldPath.documentId] without relying on fake_cloud_firestore
/// internal cast limitations.
class TestCanonicalFirestore extends Fake implements FirebaseFirestore {
  final Map<String, Map<String, dynamic>> docs = {};
  FirebaseException? simulatedException;

  @override
  CollectionReference<Map<String, dynamic>> collection(String path) {
    return TestCanonicalCollectionReference(this);
  }
}

class TestCanonicalCollectionReference extends Fake
    implements CollectionReference<Map<String, dynamic>> {
  TestCanonicalCollectionReference(this.firestore);

  final TestCanonicalFirestore firestore;

  @override
  DocumentReference<Map<String, dynamic>> doc([String? path]) {
    return TestCanonicalDocumentReference(firestore, path ?? 'generated_id');
  }

  @override
  Query<Map<String, dynamic>> orderBy(Object field, {bool descending = false}) {
    return TestCanonicalQuery(firestore).orderBy(field, descending: descending);
  }

  @override
  Query<Map<String, dynamic>> where(
    Object field, {
    Object? isEqualTo,
    Object? isNotEqualTo,
    Object? isLessThan,
    Object? isLessThanOrEqualTo,
    Object? isGreaterThan,
    Object? isGreaterThanOrEqualTo,
    Object? arrayContains,
    Iterable<Object?>? arrayContainsAny,
    Iterable<Object?>? whereIn,
    Iterable<Object?>? whereNotIn,
    bool? isNull,
  }) {
    return TestCanonicalQuery(firestore).where(
      field,
      isGreaterThanOrEqualTo: isGreaterThanOrEqualTo,
      isLessThanOrEqualTo: isLessThanOrEqualTo,
    );
  }
}

class TestCanonicalDocumentReference extends Fake
    implements DocumentReference<Map<String, dynamic>> {
  TestCanonicalDocumentReference(this.firestore, this.docId);

  final TestCanonicalFirestore firestore;
  final String docId;

  @override
  CollectionReference<Map<String, dynamic>> collection(String collectionPath) {
    return TestCanonicalCollectionReference(firestore);
  }
}

class TestCanonicalQuery extends Fake implements Query<Map<String, dynamic>> {
  TestCanonicalQuery(
    this.firestore, {
    this.filterStartAt,
    this.filterEndAt,
    this.startAfterValues,
    this.limitCount,
  });

  final TestCanonicalFirestore firestore;
  final Timestamp? filterStartAt;
  final Timestamp? filterEndAt;
  final List<dynamic>? startAfterValues;
  final int? limitCount;

  @override
  Query<Map<String, dynamic>> orderBy(Object field, {bool descending = false}) {
    return this;
  }

  @override
  Query<Map<String, dynamic>> where(
    Object field, {
    Object? isEqualTo,
    Object? isNotEqualTo,
    Object? isLessThan,
    Object? isLessThanOrEqualTo,
    Object? isGreaterThan,
    Object? isGreaterThanOrEqualTo,
    Object? arrayContains,
    Iterable<Object?>? arrayContainsAny,
    Iterable<Object?>? whereIn,
    Iterable<Object?>? whereNotIn,
    bool? isNull,
  }) {
    Timestamp? newStart = filterStartAt;
    Timestamp? newEnd = filterEndAt;
    if (field == 'occurred_at') {
      if (isGreaterThanOrEqualTo is Timestamp) {
        newStart = isGreaterThanOrEqualTo;
      }
      if (isLessThanOrEqualTo is Timestamp) {
        newEnd = isLessThanOrEqualTo;
      }
    }
    return TestCanonicalQuery(
      firestore,
      filterStartAt: newStart,
      filterEndAt: newEnd,
      startAfterValues: startAfterValues,
      limitCount: limitCount,
    );
  }

  @override
  Query<Map<String, dynamic>> startAfter(Iterable<Object?> values) {
    return TestCanonicalQuery(
      firestore,
      filterStartAt: filterStartAt,
      filterEndAt: filterEndAt,
      startAfterValues: values.toList(),
      limitCount: limitCount,
    );
  }

  @override
  Query<Map<String, dynamic>> limit(int limit) {
    return TestCanonicalQuery(
      firestore,
      filterStartAt: filterStartAt,
      filterEndAt: filterEndAt,
      startAfterValues: startAfterValues,
      limitCount: limit,
    );
  }

  @override
  Future<QuerySnapshot<Map<String, dynamic>>> get([GetOptions? options]) async {
    if (firestore.simulatedException != null) {
      throw firestore.simulatedException!;
    }

    var entries = firestore.docs.entries.toList();

    // 1. Filter by period (start / end)
    if (filterStartAt != null) {
      entries = entries.where((e) {
        final t = e.value['occurred_at'];
        if (t is! Timestamp) return true;
        return t.compareTo(filterStartAt!) >= 0;
      }).toList();
    }
    if (filterEndAt != null) {
      entries = entries.where((e) {
        final t = e.value['occurred_at'];
        if (t is! Timestamp) return true;
        return t.compareTo(filterEndAt!) <= 0;
      }).toList();
    }

    // 2. Sort by occurred_at DESC, then documentId DESC
    entries.sort((a, b) {
      final tA = a.value['occurred_at'] as Timestamp?;
      final tB = b.value['occurred_at'] as Timestamp?;
      if (tA != null && tB != null) {
        final cmp = tB.compareTo(tA); // DESC
        if (cmp != 0) return cmp;
      }
      return b.key.compareTo(a.key); // documentId DESC
    });

    // 3. Apply composite value startAfter cursor: [Timestamp, documentId]
    if (startAfterValues != null && startAfterValues!.length >= 2) {
      final cursorTs = startAfterValues![0] as Timestamp;
      final cursorDocId = startAfterValues![1] as String;

      // In DESC order (occurred_at DESC, docId DESC):
      // Item X comes BEFORE cursor if:
      // - X.occurred_at > cursorTs, OR
      // - X.occurred_at == cursorTs AND X.docId >= cursorDocId
      entries = entries.where((e) {
        final t = e.value['occurred_at'] as Timestamp?;
        if (t == null) return false;
        final cmpTs = t.compareTo(cursorTs);
        if (cmpTs > 0) return false; // comes before cursor
        if (cmpTs == 0) {
          final cmpId = e.key.compareTo(cursorDocId);
          if (cmpId >= 0) return false; // comes before or equals cursor
        }
        return true; // comes after cursor
      }).toList();
    }

    // 4. Apply limit
    if (limitCount != null && entries.length > limitCount!) {
      entries = entries.sublist(0, limitCount);
    }

    final docSnapshots = entries
        .map((e) => TestCanonicalQueryDocumentSnapshot(e.key, e.value))
        .toList();

    return TestCanonicalQuerySnapshot(docSnapshots);
  }
}

class TestCanonicalQuerySnapshot extends Fake
    implements QuerySnapshot<Map<String, dynamic>> {
  TestCanonicalQuerySnapshot(this._docs);

  final List<QueryDocumentSnapshot<Map<String, dynamic>>> _docs;

  @override
  List<QueryDocumentSnapshot<Map<String, dynamic>>> get docs => _docs;
}

class TestCanonicalQueryDocumentSnapshot extends Fake
    implements QueryDocumentSnapshot<Map<String, dynamic>> {
  TestCanonicalQueryDocumentSnapshot(this._id, this._data);

  final String _id;
  final Map<String, dynamic> _data;

  @override
  String get id => _id;

  @override
  Map<String, dynamic> data() => _data;
}

void main() {
  late TestCanonicalFirestore testFirestore;
  late FirestoreCanonicalHealthTimelineSource source;

  const dogId = 'dog_001';
  final baseTime = DateTime.utc(2026, 7, 26, 10, 0, 0);

  Map<String, dynamic> createValidDocData({
    required String title,
    required Timestamp occurredAt,
  }) {
    return {
      'timeline_type': 'meal',
      'source_collection': 'dogs/$dogId/meal_logs',
      'source_id': 'source_${occurredAt.seconds}',
      'occurred_at': occurredAt,
      'recorded_at': occurredAt,
      'projected_at': occurredAt,
      'title': title,
      'dog_id': dogId,
      'recorded_by': {
        'uid': 'u1',
        'name': 'GCM Silva',
        'internal_role': 'operador',
      },
      'status': 'final',
      'schema_version': 1,
    };
  }

  setUp(() {
    testFirestore = TestCanonicalFirestore();
    source = FirestoreCanonicalHealthTimelineSource(firestore: testFirestore);
  });

  group('FirestoreCanonicalHealthTimelineSource', () {
    test(
      'rejeita filtros não suportados ANTES de consultar o Firestore',
      () async {
        final queryWithTypes = HealthTimelineQuery(
          dogId: dogId,
          types: {HealthTimelineType.meal},
        );
        expect(
          () => source.loadPage(queryWithTypes),
          throwsA(
            isA<HealthTimelineSourceException>().having(
              (e) => e.message,
              'message',
              equals('unsupported_query_filter'),
            ),
          ),
        );

        final queryWithCase = HealthTimelineQuery(
          dogId: dogId,
          caseId: 'case_123',
        );
        expect(
          () => source.loadPage(queryWithCase),
          throwsA(
            isA<HealthTimelineSourceException>().having(
              (e) => e.message,
              'message',
              equals('unsupported_query_filter'),
            ),
          ),
        );
      },
    );

    test(
      'retorna página vazia quando a subcoleção estiver vazia (empty válido)',
      () async {
        final query = HealthTimelineQuery(dogId: dogId, pageSize: 20);
        final page = await source.loadPage(query);

        expect(page.items, isEmpty);
        expect(page.hasMore, isFalse);
        expect(page.nextCursor, isNull);
      },
    );

    test(
      'carrega primeira página paginada com pageSize + 1 e tem hasMore=true',
      () async {
        for (var i = 1; i <= 3; i++) {
          final t = Timestamp.fromDate(baseTime.add(Duration(hours: i)));
          testFirestore.docs['tl1_00$i'] = createValidDocData(
            title: 'Item $i',
            occurredAt: t,
          );
        }

        final query = HealthTimelineQuery(dogId: dogId, pageSize: 2);
        final page1 = await source.loadPage(query);

        expect(page1.items.length, equals(2));
        expect(page1.hasMore, isTrue);
        expect(page1.nextCursor, isNotNull);
        // Mais recente primeiro (08:00 -> Item 3, depois 07:00 -> Item 2)
        expect(page1.items[0].title, equals('Item 3'));
        expect(page1.items[1].title, equals('Item 2'));
      },
    );

    test('loadMore carrega segunda página sem duplicar documentos', () async {
      for (var i = 1; i <= 3; i++) {
        final t = Timestamp.fromDate(baseTime.add(Duration(hours: i)));
        testFirestore.docs['tl1_00$i'] = createValidDocData(
          title: 'Item $i',
          occurredAt: t,
        );
      }

      final query1 = HealthTimelineQuery(dogId: dogId, pageSize: 2);
      final page1 = await source.loadPage(query1);

      final query2 = HealthTimelineQuery(
        dogId: dogId,
        pageSize: 2,
        cursor: page1.nextCursor,
      );
      final page2 = await source.loadPage(query2);

      expect(page2.items.length, equals(1));
      expect(page2.hasMore, isFalse);
      expect(page2.nextCursor, isNull);
      expect(page2.items[0].title, equals('Item 1'));
    });

    test(
      'TESTE ADVERSARIAL DE EMPATE: paginação determinística por composite cursor',
      () async {
        final sameTimestamp = Timestamp.fromDate(baseTime);

        testFirestore.docs['docA'] = createValidDocData(
          title: 'Doc A',
          occurredAt: sameTimestamp,
        );
        testFirestore.docs['docB'] = createValidDocData(
          title: 'Doc B',
          occurredAt: sameTimestamp,
        );
        testFirestore.docs['docC'] = createValidDocData(
          title: 'Doc C',
          occurredAt: sameTimestamp,
        );

        final query1 = HealthTimelineQuery(dogId: dogId, pageSize: 1);
        final page1 = await source.loadPage(query1);

        expect(page1.items.length, equals(1));
        expect(page1.items[0].id, equals('docC'));
        expect(page1.hasMore, isTrue);
        expect(page1.nextCursor, isNotNull);

        final query2 = HealthTimelineQuery(
          dogId: dogId,
          pageSize: 1,
          cursor: page1.nextCursor,
        );
        final page2 = await source.loadPage(query2);

        expect(page2.items.length, equals(1));
        expect(page2.items[0].id, equals('docB'));
        expect(page2.hasMore, isTrue);
        expect(page2.nextCursor, isNotNull);

        final query3 = HealthTimelineQuery(
          dogId: dogId,
          pageSize: 1,
          cursor: page2.nextCursor,
        );
        final page3 = await source.loadPage(query3);

        expect(page3.items.length, equals(1));
        expect(page3.items[0].id, equals('docA'));
        expect(page3.hasMore, isFalse);
        expect(page3.nextCursor, isNull);
      },
    );

    test(
      'TESTE DE DOCUMENTO DO CURSOR REMOVIDO: avanço continua por valores',
      () async {
        final sameTimestamp = Timestamp.fromDate(baseTime);

        testFirestore.docs['docA'] = createValidDocData(
          title: 'Doc A',
          occurredAt: sameTimestamp,
        );
        testFirestore.docs['docB'] = createValidDocData(
          title: 'Doc B',
          occurredAt: sameTimestamp,
        );
        testFirestore.docs['docC'] = createValidDocData(
          title: 'Doc C',
          occurredAt: sameTimestamp,
        );

        // 1. Carregar primeira página (pageSize=1)
        final query1 = HealthTimelineQuery(dogId: dogId, pageSize: 1);
        final page1 = await source.loadPage(query1);
        expect(page1.items[0].id, equals('docC'));
        final savedCursor = page1.nextCursor;

        // 2. Remover o documento retornado na primeira página (docC)
        testFirestore.docs.remove('docC');

        // 3. Carregar a segunda página com o cursor salvo
        final query2 = HealthTimelineQuery(
          dogId: dogId,
          pageSize: 1,
          cursor: savedCursor,
        );
        final page2 = await source.loadPage(query2);

        // 4. Comprovar avanço correto pelo par (occurred_at + documentId)
        expect(page2.items.length, equals(1));
        expect(page2.items[0].id, equals('docB'));

        // 5. Carregar terceira página
        final query3 = HealthTimelineQuery(
          dogId: dogId,
          pageSize: 1,
          cursor: page2.nextCursor,
        );
        final page3 = await source.loadPage(query3);
        expect(page3.items.length, equals(1));
        expect(page3.items[0].id, equals('docA'));
      },
    );

    test(
      'TESTE DE DOCUMENTO DO CURSOR ALTERADO: avanço ignora modificação posterior do doc',
      () async {
        final sameTimestamp = Timestamp.fromDate(baseTime);

        testFirestore.docs['docA'] = createValidDocData(
          title: 'Doc A',
          occurredAt: sameTimestamp,
        );
        testFirestore.docs['docB'] = createValidDocData(
          title: 'Doc B',
          occurredAt: sameTimestamp,
        );
        testFirestore.docs['docC'] = createValidDocData(
          title: 'Doc C',
          occurredAt: sameTimestamp,
        );

        // 1. Carregar primeira página
        final query1 = HealthTimelineQuery(dogId: dogId, pageSize: 1);
        final page1 = await source.loadPage(query1);
        expect(page1.items[0].id, equals('docC'));
        final savedCursor = page1.nextCursor;

        // 2. Alterar occurred_at do docC para o futuro no banco
        testFirestore.docs['docC']!['occurred_at'] = Timestamp.fromDate(
          baseTime.add(const Duration(days: 10)),
        );

        // 3. Carregar próxima página
        final query2 = HealthTimelineQuery(
          dogId: dogId,
          pageSize: 1,
          cursor: savedCursor,
        );
        final page2 = await source.loadPage(query2);

        // 4. Comprovar que o cursor avança de onde parou baseado no token imutável
        expect(page2.items.length, equals(1));
        expect(page2.items[0].id, equals('docB'));
      },
    );

    test(
      'aplica filtro de período temporal (start e end) no Firestore',
      () async {
        final t1 = Timestamp.fromDate(DateTime.utc(2026, 7, 20));
        final t2 = Timestamp.fromDate(DateTime.utc(2026, 7, 25));
        final t3 = Timestamp.fromDate(DateTime.utc(2026, 7, 30));

        testFirestore.docs['tl_20'] = createValidDocData(
          title: 'Item 20',
          occurredAt: t1,
        );
        testFirestore.docs['tl_25'] = createValidDocData(
          title: 'Item 25',
          occurredAt: t2,
        );
        testFirestore.docs['tl_30'] = createValidDocData(
          title: 'Item 30',
          occurredAt: t3,
        );

        final periodQuery = HealthTimelineQuery(
          dogId: dogId,
          period: HealthTimelinePeriod(
            start: DateTime.utc(2026, 7, 22),
            end: DateTime.utc(2026, 7, 28),
          ),
        );

        final page = await source.loadPage(periodQuery);

        expect(page.items.length, equals(1));
        expect(page.items[0].title, equals('Item 25'));
      },
    );

    test('documento anômalo falha a página inteira (fail-closed)', () async {
      final t = Timestamp.fromDate(baseTime);
      testFirestore.docs['valid_doc'] = createValidDocData(
        title: 'Válido',
        occurredAt: t,
      );

      // Injeta documento corrompido sem title
      final invalidData = createValidDocData(title: 'Invalido', occurredAt: t)
        ..remove('title');
      testFirestore.docs['invalid_doc'] = invalidData;

      final query = HealthTimelineQuery(dogId: dogId, pageSize: 10);

      expect(
        () => source.loadPage(query),
        throwsA(isA<HealthTimelineSourceException>()),
        reason: 'Qualquer documento inválido deve falhar a página inteira',
      );
    });

    test(
      'mapeia exceção do Firebase com código unavailable para isOffline',
      () async {
        testFirestore.simulatedException = FirebaseException(
          plugin: 'firestore',
          code: 'unavailable',
          message: 'Network offline',
        );

        final query = HealthTimelineQuery(dogId: dogId);

        expect(
          () => source.loadPage(query),
          throwsA(
            isA<HealthTimelineSourceException>().having(
              (e) => e.isOffline,
              'isOffline',
              isTrue,
            ),
          ),
        );
      },
    );
  });
}
