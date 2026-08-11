import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:canil_gcm/features/dogs/data/weight_history_service.dart';
import 'package:canil_gcm/features/health/domain/weight_collection_policy.dart';

final class _FirestoreMock extends Mock implements FirebaseFirestore {}

// Test double for the sealed Firestore interface; no production subtype exists.
// ignore: subtype_of_sealed_class
final class _CollectionMock extends Mock
    implements CollectionReference<Map<String, dynamic>> {}

// Test double for the sealed Firestore interface; no production subtype exists.
// ignore: subtype_of_sealed_class
final class _DocumentMock extends Mock
    implements DocumentReference<Map<String, dynamic>> {}

void main() {
  const dogId = 'dog-1';

  Map<String, dynamic> validV1(double kg, DateTime measuredAt) => {
    'dog_id': dogId,
    'weight_kg': kg,
    'schema_version': 1,
    'measured_at': Timestamp.fromDate(measuredAt),
    'recorded_by': const {
      'uid': 'user-1',
      'name': 'Ana',
      'internal_role': 'condutor',
    },
  };

  Map<String, dynamic> validV2(
    double kg,
    DateTime measuredAt,
    DateTime recordedAt,
  ) => {
    'dog_id': dogId,
    'weight_kg': kg,
    'schema_version': 2,
    'record_type': 'quick',
    'origin_record_type': 'quick',
    'status': 'valid',
    'revision': 1,
    'measured_at': Timestamp.fromDate(measuredAt),
    'recorded_at': Timestamp.fromDate(recordedAt),
    'recorded_by': const {
      'uid': 'user-1',
      'name': 'Ana',
      'internal_role': 'condutor',
    },
  };

  WeightDocumentData document(String id, Map<String, dynamic> data) =>
      (documentId: id, data: data);

  test('12 valid + 1 malformed is inconclusive with 12 readable rows', () {
    final documents = <WeightDocumentData>[
      for (var index = 0; index < 12; index++)
        document(
          'valid-$index',
          validV1(20 + index / 10, DateTime.utc(2026, 7, index + 1)),
        ),
      document('malformed', {
        'dog_id': dogId,
        'weight_kg': 'not-a-number',
        'schema_version': 1,
        'measured_at': Timestamp.fromDate(DateTime.utc(2026, 8, 1)),
      }),
    ];

    final snapshot = WeightHistoryService.analyzeExportDocuments(
      dogId: dogId,
      documents: documents,
    );

    expect(snapshot.state, WeightExportSnapshotState.inconclusive);
    expect(snapshot.current, isNull);
    expect(snapshot.oldest, isNull);
    expect(snapshot.readableRecords, hasLength(12));
    expect(snapshot.blockers, contains(WeightCurrentBlocker.malformed));
  });

  test('unsupported preserves readable rows but blocks authority', () {
    final snapshot = WeightHistoryService.analyzeExportDocuments(
      dogId: dogId,
      documents: [
        document('valid', validV1(24, DateTime.utc(2026, 8, 1))),
        document('future', {
          'dog_id': dogId,
          'weight_kg': 25,
          'schema_version': 99,
          'measured_at': Timestamp.fromDate(DateTime.utc(2026, 8, 2)),
        }),
      ],
    );

    expect(snapshot.state, WeightExportSnapshotState.inconclusive);
    expect(snapshot.current, isNull);
    expect(snapshot.readableRecords.single.id, 'valid');
    expect(snapshot.blockers, contains(WeightCurrentBlocker.unsupported));
  });

  test('duplicate entityId is inconclusive without deduping readable rows', () {
    final snapshot = WeightHistoryService.analyzeExportDocuments(
      dogId: dogId,
      documents: [
        document('duplicate', validV1(24, DateTime.utc(2026, 8, 1))),
        document('duplicate', validV1(25, DateTime.utc(2026, 8, 2))),
      ],
    );

    expect(snapshot.state, WeightExportSnapshotState.inconclusive);
    expect(snapshot.current, isNull);
    expect(snapshot.oldest, isNull);
    expect(snapshot.readableRecords, hasLength(2));
    expect(snapshot.blockers, contains(WeightCurrentBlocker.duplicateEntityId));
  });

  test('valid collection selects canonical current and oldest before seam', () {
    final newestMeasured = DateTime.utc(2026, 8, 10);
    final oldestMeasured = DateTime.utc(2026, 1, 1);
    final snapshot = WeightHistoryService.analyzeExportDocuments(
      dogId: dogId,
      documents: [
        document(
          'newer-recorded-at',
          validV2(25, newestMeasured, DateTime.utc(2026, 8, 10, 12)),
        ),
        document(
          'newer-decoy',
          validV2(39, newestMeasured, DateTime.utc(2026, 8, 10, 10)),
        ),
        document(
          'oldest-decoy',
          validV2(18, oldestMeasured, DateTime.utc(2026, 1, 1, 12)),
        ),
        document(
          'canonical-oldest',
          validV2(22, oldestMeasured, DateTime.utc(2026, 1, 1, 10)),
        ),
      ],
    );

    expect(snapshot.state, WeightExportSnapshotState.current);
    expect(snapshot.current?.id, 'newer-recorded-at');
    expect(snapshot.current?.weightKg, 25);
    expect(snapshot.oldest?.id, 'canonical-oldest');
    expect(snapshot.oldest?.weightKg, 22);
    expect(snapshot.readableRecords, hasLength(4));
  });

  test('empty and invalidated-only collections are none', () {
    final empty = WeightHistoryService.analyzeExportDocuments(
      dogId: dogId,
      documents: const [],
    );
    final invalidated = WeightHistoryService.analyzeExportDocuments(
      dogId: dogId,
      documents: [
        document('invalidated', {
          ...validV2(24, DateTime.utc(2026, 8, 1), DateTime.utc(2026, 8, 1, 1)),
          'status': 'invalidated',
        }),
      ],
    );

    for (final snapshot in [empty, invalidated]) {
      expect(snapshot.state, WeightExportSnapshotState.none);
      expect(snapshot.current, isNull);
      expect(snapshot.oldest, isNull);
      expect(snapshot.readableRecords, isEmpty);
    }
  });

  test('73 valid documents remain full and preserve both endpoints', () {
    final snapshot = WeightHistoryService.analyzeExportDocuments(
      dogId: dogId,
      documents: [
        for (var index = 0; index < 73; index++)
          document(
            'record-${index.toString().padLeft(2, '0')}',
            validV1(20 + index / 10, DateTime.utc(2026, 1, index + 1)),
          ),
      ],
    );

    expect(snapshot.state, WeightExportSnapshotState.current);
    expect(snapshot.readableRecords, hasLength(73));
    expect(snapshot.current?.id, 'record-72');
    expect(snapshot.oldest?.id, 'record-00');
  });

  test('each service call reads a fresh full snapshot', () async {
    final firestore = FakeFirebaseFirestore();
    final collection = firestore
        .collection('dogs')
        .doc(dogId)
        .collection('weight_records');
    await collection.doc('old').set(validV1(24, DateTime.utc(2026, 8, 1)));
    final service = WeightHistoryService(firestore: firestore);

    final first = await service.readExportSnapshot(dogId);
    await collection.doc('new').set(validV1(26, DateTime.utc(2026, 8, 2)));
    final second = await service.readExportSnapshot(dogId);

    expect(first.current?.id, 'old');
    expect(first.readableRecords, hasLength(1));
    expect(second.current?.id, 'new');
    expect(second.readableRecords, hasLength(2));
  });

  test('unavailable snapshot never exposes stale clinical data', () {
    const snapshot = WeightExportSnapshot.unavailable();

    expect(snapshot.state, WeightExportSnapshotState.unavailable);
    expect(snapshot.current, isNull);
    expect(snapshot.oldest, isNull);
    expect(snapshot.readableRecords, isEmpty);
  });

  test(
    'query failure becomes unavailable after one attempted full read',
    () async {
      final firestore = _FirestoreMock();
      final dogs = _CollectionMock();
      final dog = _DocumentMock();
      final weights = _CollectionMock();
      when(() => firestore.collection('dogs')).thenReturn(dogs);
      when(() => dogs.doc(dogId)).thenReturn(dog);
      when(() => dog.collection('weight_records')).thenReturn(weights);
      when(() => weights.get()).thenThrow(StateError('offline'));

      final snapshot = await WeightHistoryService(
        firestore: firestore,
      ).readExportSnapshot(dogId);

      expect(snapshot.state, WeightExportSnapshotState.unavailable);
      expect(snapshot.current, isNull);
      expect(snapshot.readableRecords, isEmpty);
      verify(() => weights.get()).called(1);
    },
  );
}
