import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:canil_gcm/features/health/data/coexistence/schedule/firestore_health_schedule_source.dart';
import 'package:canil_gcm/features/health/data/coexistence/schedule/health_schedule_cursor_codec.dart';
import 'package:canil_gcm/features/health/presentation/schedule/health_schedule_cursor.dart';
import 'package:canil_gcm/features/health/presentation/schedule/health_schedule_query.dart';
import 'package:canil_gcm/features/health/presentation/schedule/health_schedule_source.dart';

void main() {
  late FakeFirebaseFirestore db;
  late FirestoreHealthScheduleSource source;

  setUp(() {
    db = FakeFirebaseFirestore();
    source = FirestoreHealthScheduleSource(firestore: db);
  });

  Future<void> seed({
    required String dogId,
    required String id,
    required DateTime scheduledFor,
    String lifecycle = 'open',
    String scheduleType = 'vaccination',
    String title = 'Item',
  }) async {
    await db
        .collection('dogs')
        .doc(dogId)
        .collection('health_schedule')
        .doc(id)
        .set({
          'schedule_type': scheduleType,
          'title': title,
          'scheduled_for': Timestamp.fromDate(scheduledFor.toUtc()),
          'timezone': 'America/Sao_Paulo',
          'lifecycle_status': lifecycle,
          'source_type': 'manual',
          'created_at': Timestamp.fromDate(DateTime.utc(2026, 1, 1)),
          'recorded_by': {
            'uid': 'u1',
            'name': 'Condutor',
            'internal_role': 'condutor',
          },
          'schema_version': 1,
        });
  }

  test('caminho por dogId e lifecycle open', () async {
    await seed(
      dogId: 'dog-a',
      id: 'a1',
      scheduledFor: DateTime.utc(2026, 7, 20),
      title: 'A1',
    );
    await seed(
      dogId: 'dog-a',
      id: 'a2',
      scheduledFor: DateTime.utc(2026, 7, 21),
      lifecycle: 'completed',
      title: 'A2 done',
    );
    await seed(
      dogId: 'dog-b',
      id: 'b1',
      scheduledFor: DateTime.utc(2026, 7, 20),
      title: 'B1',
    );

    final page = await source.loadPage(HealthScheduleQuery(dogId: 'dog-a'));
    expect(page.items.map((e) => e.id), ['a1']);
    expect(page.items.single.dogId, 'dog-a');
    expect(page.hasMore, isFalse);
  });

  test('ordenação scheduled_for ASC e page size', () async {
    await seed(
      dogId: 'dog-a',
      id: 'z',
      scheduledFor: DateTime.utc(2026, 7, 22),
      title: 'late',
    );
    await seed(
      dogId: 'dog-a',
      id: 'a',
      scheduledFor: DateTime.utc(2026, 7, 20),
      title: 'early',
    );
    await seed(
      dogId: 'dog-a',
      id: 'm',
      scheduledFor: DateTime.utc(2026, 7, 21),
      title: 'mid',
    );

    final page = await source.loadPage(
      HealthScheduleQuery(dogId: 'dog-a', pageSize: 2),
    );
    expect(page.items.map((e) => e.id), ['a', 'm']);
    expect(page.hasMore, isTrue);
    expect(page.nextCursor, isNotNull);
  });

  test('cursor segunda página sem duplicação', () async {
    for (var i = 0; i < 5; i++) {
      await seed(
        dogId: 'dog-a',
        id: 'id-$i',
        scheduledFor: DateTime.utc(2026, 7, 10 + i),
        title: 't$i',
      );
    }
    final first = await source.loadPage(
      HealthScheduleQuery(dogId: 'dog-a', pageSize: 2),
    );
    final second = await source.loadPage(
      HealthScheduleQuery(
        dogId: 'dog-a',
        pageSize: 2,
        cursor: first.nextCursor,
      ),
    );
    final ids = {
      ...first.items.map((e) => e.id),
      ...second.items.map((e) => e.id),
    };
    expect(ids.length, first.items.length + second.items.length);
    expect(
      first.items
          .map((e) => e.id)
          .toSet()
          .intersection(second.items.map((e) => e.id).toSet()),
      isEmpty,
    );
  });

  test('mesmo scheduled_for: ordenação por documentId estável', () async {
    final at = DateTime.utc(2026, 7, 15, 12);
    await seed(dogId: 'dog-a', id: 'b-doc', scheduledFor: at, title: 'B');
    await seed(dogId: 'dog-a', id: 'a-doc', scheduledFor: at, title: 'A');
    final page = await source.loadPage(HealthScheduleQuery(dogId: 'dog-a'));
    expect(page.items.map((e) => e.id), ['a-doc', 'b-doc']);
  });

  test('empty collection → empty page', () async {
    final page = await source.loadPage(HealthScheduleQuery(dogId: 'dog-empty'));
    expect(page.items, isEmpty);
    expect(page.hasMore, isFalse);
    expect(page.nextCursor, isNull);
  });

  test('documento inválido → SourceException (não empty silencioso)', () async {
    await db
        .collection('dogs')
        .doc('dog-a')
        .collection('health_schedule')
        .doc('bad')
        .set({
          'schedule_type': 'unknown_type',
          'title': 'x',
          'scheduled_for': Timestamp.fromDate(DateTime.utc(2026, 7, 1)),
          'timezone': 'America/Sao_Paulo',
          'lifecycle_status': 'open',
          'source_type': 'manual',
          'created_at': Timestamp.fromDate(DateTime.utc(2026, 1, 1)),
          'recorded_by': 'system',
          'schema_version': 1,
        });
    expect(
      () => source.loadPage(HealthScheduleQuery(dogId: 'dog-a')),
      throwsA(isA<HealthScheduleSourceException>()),
    );
  });

  test('cursor codec roundtrip', () {
    final c = HealthScheduleCursorCodec.encode(
      HealthScheduleCursorPosition(
        scheduledFor: DateTime.utc(2026, 7, 14, 10),
        documentId: 'abc',
      ),
    );
    final p = HealthScheduleCursorCodec.decode(c);
    expect(p.documentId, 'abc');
    expect(p.scheduledFor, DateTime.utc(2026, 7, 14, 10));
  });

  test(
    '15 docs mesmo scheduled_for, pageSize 5: cobre todos sem duplicata/vazio',
    () async {
      final at = DateTime.utc(2026, 8, 1, 12);
      // IDs únicos; inserção fora de ordem alfabética.
      final uniqueIds = [
        for (var i = 14; i >= 0; i--) 'id-${i.toString().padLeft(2, '0')}',
      ];
      for (final id in uniqueIds) {
        await seed(dogId: 'dog-a', id: id, scheduledFor: at, title: id);
      }

      Future<List<String>> paginateOnce() async {
        final collected = <String>[];
        HealthScheduleCursor? cursor;
        var pages = 0;
        while (true) {
          pages++;
          expect(pages, lessThanOrEqualTo(10), reason: 'loop infinito');
          final page = await source.loadPage(
            HealthScheduleQuery(dogId: 'dog-a', pageSize: 5, cursor: cursor),
          );
          if (page.items.isEmpty) {
            expect(
              page.hasMore,
              isFalse,
              reason: 'página vazia intermediária com hasMore',
            );
            break;
          }
          collected.addAll(page.items.map((e) => e.id));
          if (!page.hasMore) break;
          expect(page.nextCursor, isNotNull);
          cursor = page.nextCursor;
        }
        return collected;
      }

      final firstRun = await paginateOnce();
      expect(firstRun, hasLength(15));
      expect(firstRun.toSet(), hasLength(15));
      expect(firstRun.toSet(), uniqueIds.toSet());
      // Ordem estável: documentId ASC com mesmo timestamp.
      final expectedOrder = List<String>.of(uniqueIds)..sort();
      expect(firstRun, expectedOrder);

      final secondRun = await paginateOnce();
      expect(secondRun, firstRun);
    },
  );

  test('paginação mista: timestamps iguais e diferentes', () async {
    final t1 = DateTime.utc(2026, 8, 2, 10);
    final t2 = DateTime.utc(2026, 8, 2, 11);
    final t3 = DateTime.utc(2026, 8, 2, 12);
    await seed(dogId: 'dog-a', id: 'b', scheduledFor: t1, title: 'b');
    await seed(dogId: 'dog-a', id: 'a', scheduledFor: t1, title: 'a');
    await seed(dogId: 'dog-a', id: 'c', scheduledFor: t2, title: 'c');
    await seed(dogId: 'dog-a', id: 'e', scheduledFor: t3, title: 'e');
    await seed(dogId: 'dog-a', id: 'd', scheduledFor: t3, title: 'd');

    final p1 = await source.loadPage(
      HealthScheduleQuery(dogId: 'dog-a', pageSize: 2),
    );
    expect(p1.items.map((e) => e.id), ['a', 'b']);
    expect(p1.hasMore, isTrue);

    final p2 = await source.loadPage(
      HealthScheduleQuery(dogId: 'dog-a', pageSize: 2, cursor: p1.nextCursor),
    );
    expect(p2.items.map((e) => e.id), ['c', 'd']);
    expect(p2.hasMore, isTrue);

    final p3 = await source.loadPage(
      HealthScheduleQuery(dogId: 'dog-a', pageSize: 2, cursor: p2.nextCursor),
    );
    expect(p3.items.map((e) => e.id), ['e']);
    expect(p3.hasMore, isFalse);

    final all = [...p1.items, ...p2.items, ...p3.items].map((e) => e.id);
    expect(all.toSet(), {'a', 'b', 'c', 'd', 'e'});
    expect(all.length, 5);
  });
}
