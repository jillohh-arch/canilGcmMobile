import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:canil_gcm/features/occurrences/domain/occurrence_event.dart';
import 'package:canil_gcm/features/occurrences/domain/occurrence_event_category.dart';

void main() {
  final now = DateTime(2026, 5, 18, 14, 45);

  OccurrenceEvent _buildEvent({DateTime? deletedAt}) {
    return OccurrenceEvent(
      id: 'evt-001',
      occurrenceId: 'occ-001',
      category: OccurrenceEventCategory.approach,
      timestamp: now,
      title: 'Abordagem ao suspeito',
      description: 'Indivíduo abordado na esquina',
      photoUrls: ['https://storage.example.com/photo1.jpg'],
      photoMetadata: [
        {'exif_lat': -22.56, 'exif_lng': -47.40, 'taken_at': '2026-05-18T14:45:00Z'}
      ],
      gpsLat: -22.5642,
      gpsLng: -47.4019,
      createdAt: now,
      updatedAt: now,
      deletedAt: deletedAt,
    );
  }

  group('OccurrenceEvent', () {
    group('fromMap/toMap roundtrip', () {
      test('preserva todos os campos', () {
        final original = _buildEvent();
        final map = original.toMap();
        final restored = OccurrenceEvent.fromMap(
          map,
          'evt-001',
          occurrenceId: 'occ-001',
        );

        expect(restored.id, equals('evt-001'));
        expect(restored.occurrenceId, equals('occ-001'));
        expect(restored.category, equals(OccurrenceEventCategory.approach));
        expect(restored.title, equals('Abordagem ao suspeito'));
        expect(restored.description, equals('Indivíduo abordado na esquina'));
        expect(restored.photoUrls.length, equals(1));
        expect(restored.photoMetadata.length, equals(1));
        expect(restored.gpsLat, equals(-22.5642));
        expect(restored.gpsLng, equals(-47.4019));
      });

      test('toMap usa snake_case', () {
        final map = _buildEvent().toMap();

        expect(map.containsKey('occurrence_id'), isTrue);
        expect(map.containsKey('category'), isTrue);
        expect(map.containsKey('timestamp'), isTrue);
        expect(map.containsKey('photo_urls'), isTrue);
        expect(map.containsKey('photo_metadata'), isTrue);
        expect(map.containsKey('gps_lat'), isTrue);
        expect(map.containsKey('gps_lng'), isTrue);
        expect(map.containsKey('created_at'), isTrue);
        expect(map.containsKey('updated_at'), isTrue);
        expect(map.containsKey('audit_trail'), isTrue);
      });

      test('toMap serializa Timestamps', () {
        final map = _buildEvent().toMap();

        expect(map['timestamp'], isA<Timestamp>());
        expect(map['created_at'], isA<Timestamp>());
        expect(map['updated_at'], isA<Timestamp>());
      });

      test('fromMap parseia Timestamp do Firestore', () {
        final map = {
          'occurrence_id': 'occ-001',
          'category': 'dog_work',
          'timestamp': Timestamp.fromDate(now),
          'created_at': Timestamp.fromDate(now),
          'updated_at': Timestamp.fromDate(now),
          'title': 'Faro',
        };

        final event = OccurrenceEvent.fromMap(
          map,
          'evt-002',
          occurrenceId: 'occ-001',
        );

        expect(event.timestamp, equals(now));
        expect(event.category, equals(OccurrenceEventCategory.dogWork));
        expect(event.title, equals('Faro'));
      });

      test('fromMap com campos ausentes usa defaults', () {
        final map = <String, dynamic>{
          'category': 'other',
          'timestamp': Timestamp.fromDate(now),
          'created_at': Timestamp.fromDate(now),
          'updated_at': Timestamp.fromDate(now),
        };

        final event = OccurrenceEvent.fromMap(
          map,
          'evt-003',
          occurrenceId: 'occ-001',
        );

        expect(event.title, isNull);
        expect(event.description, isNull);
        expect(event.photoUrls, isEmpty);
        expect(event.photoMetadata, isEmpty);
        expect(event.gpsLat, isNull);
        expect(event.auditTrail, isEmpty);
      });
    });

    group('copyWith', () {
      test('altera campo específico mantendo outros', () {
        final original = _buildEvent();
        final updated = original.copyWith(
          title: 'Título atualizado',
          category: OccurrenceEventCategory.seizure,
        );

        expect(updated.title, equals('Título atualizado'));
        expect(updated.category, equals(OccurrenceEventCategory.seizure));
        expect(updated.id, equals(original.id));
        expect(updated.occurrenceId, equals(original.occurrenceId));
        expect(updated.description, equals(original.description));
      });
    });

    group('SoftDeletable', () {
      test('isDeleted retorna false quando deletedAt é null', () {
        final event = _buildEvent();
        expect(event.isDeleted, isFalse);
      });

      test('isDeleted retorna true quando deletedAt está presente', () {
        final event = _buildEvent(deletedAt: now);
        expect(event.isDeleted, isTrue);
      });

      test('softDeleteFields inclui campos no toMap', () {
        final event = _buildEvent(deletedAt: now);
        final map = event.toMap();

        expect(map.containsKey('deleted_at'), isTrue);
        expect(map['deleted_at'], isA<Timestamp>());
      });
    });

    group('OccurrenceEventCategory', () {
      test('toMap/fromMap roundtrip', () {
        for (final cat in OccurrenceEventCategory.values) {
          expect(OccurrenceEventCategory.fromMap(cat.toMap()), equals(cat));
        }
      });

      test('label não é vazio', () {
        for (final cat in OccurrenceEventCategory.values) {
          expect(cat.label.isNotEmpty, isTrue);
        }
      });
    });
  });
}
