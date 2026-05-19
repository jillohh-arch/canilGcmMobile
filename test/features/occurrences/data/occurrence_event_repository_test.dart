import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:canil_gcm/features/occurrences/data/occurrence_event_repository.dart';
import 'package:canil_gcm/features/occurrences/domain/occurrence_event.dart';
import 'package:canil_gcm/features/occurrences/domain/occurrence_event_category.dart';

void main() {
  late FakeFirebaseFirestore fakeFirestore;
  late OccurrenceEventRepository repository;

  final now = DateTime(2026, 5, 18, 14, 45);

  OccurrenceEvent _buildEvent({
    String id = 'evt-001',
    String occurrenceId = 'occ-001',
    OccurrenceEventCategory category = OccurrenceEventCategory.approach,
  }) {
    return OccurrenceEvent(
      id: id,
      occurrenceId: occurrenceId,
      category: category,
      timestamp: now,
      title: 'Abordagem',
      description: 'Suspeito abordado',
      gpsLat: -22.5642,
      gpsLng: -47.4019,
      createdAt: now,
      updatedAt: now,
    );
  }

  setUp(() {
    fakeFirestore = FakeFirebaseFirestore();
    repository = OccurrenceEventRepository(fakeFirestore);

    // Cria documento pai para a subcoleção existir
    fakeFirestore.collection('occurrences').doc('occ-001').set({
      'dog_id': 'dog-001',
      'status': 'in_progress',
    });
  });

  group('OccurrenceEventRepository', () {
    group('create', () {
      test('salva evento na subcoleção events', () async {
        final event = _buildEvent();
        final created = await repository.create(event);

        final snap = await fakeFirestore
            .collection('occurrences')
            .doc('occ-001')
            .collection('events')
            .doc('evt-001')
            .get();

        expect(snap.exists, isTrue);
        expect(snap.data()!['category'], equals('approach'));
        expect(snap.data()!['title'], equals('Abordagem'));
        expect(created.auditTrail.length, equals(1));
        expect(created.auditTrail.first['action'], equals('created'));
      });
    });

    group('getById', () {
      test('retorna evento existente', () async {
        await repository.create(_buildEvent());
        final result = await repository.getById('occ-001', 'evt-001');

        expect(result, isNotNull);
        expect(result!.id, equals('evt-001'));
        expect(result.category, equals(OccurrenceEventCategory.approach));
      });

      test('retorna null se não existe', () async {
        final result = await repository.getById('occ-001', 'inexistente');
        expect(result, isNull);
      });

      test('retorna null se soft-deleted', () async {
        await repository.create(_buildEvent());
        await repository.softDelete('occ-001', 'evt-001', 'user-001', 'Erro');

        final result = await repository.getById('occ-001', 'evt-001');
        expect(result, isNull);
      });
    });

    group('update', () {
      test('atualiza campos e registra audit entry', () async {
        await repository.create(_buildEvent());
        await repository.update('occ-001', 'evt-001', {
          'title': 'Abordagem atualizada',
        });

        final snap = await fakeFirestore
            .collection('occurrences')
            .doc('occ-001')
            .collection('events')
            .doc('evt-001')
            .get();
        final data = snap.data()!;

        expect(data['title'], equals('Abordagem atualizada'));
        final trail = data['audit_trail'] as List;
        expect(trail.length, greaterThan(1));
        final lastEntry = trail.last as Map;
        expect(lastEntry['action'], equals('updated'));
        expect(lastEntry['field_name'], equals('title'));
      });
    });

    group('softDelete', () {
      test('marca campos de deleção', () async {
        await repository.create(_buildEvent());
        await repository.softDelete(
            'occ-001', 'evt-001', 'user-001', 'Duplicado');

        final snap = await fakeFirestore
            .collection('occurrences')
            .doc('occ-001')
            .collection('events')
            .doc('evt-001')
            .get();
        final data = snap.data()!;

        expect(data['deleted_by'], equals('user-001'));
        expect(data['delete_reason'], equals('Duplicado'));
        expect(data['deleted_at'], isNotNull);
      });
    });

    group('countByOccurrence', () {
      test('conta apenas eventos não deletados', () async {
        await repository.create(_buildEvent(id: 'evt-001'));
        await repository.create(_buildEvent(id: 'evt-002'));
        await repository.create(_buildEvent(id: 'evt-003'));
        await repository.softDelete(
            'occ-001', 'evt-003', 'user-001', 'Removido');

        final count = await repository.countByOccurrence('occ-001');
        expect(count, equals(2));
      });

      test('retorna 0 para ocorrência sem eventos', () async {
        final count = await repository.countByOccurrence('occ-999');
        expect(count, equals(0));
      });
    });
  });
}
