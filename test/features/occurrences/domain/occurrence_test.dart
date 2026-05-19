import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:canil_gcm/features/occurrences/domain/occurrence.dart';
import 'package:canil_gcm/features/occurrences/domain/occurrence_result.dart';
import 'package:canil_gcm/features/occurrences/domain/occurrence_status.dart';

void main() {
  final now = DateTime(2026, 5, 18, 14, 30);

  Occurrence _buildOccurrence({
    OccurrenceStatus status = OccurrenceStatus.inProgress,
    DateTime? deletedAt,
  }) {
    return Occurrence(
      id: 'occ-001',
      shiftId: 'shift-001',
      primaryHandlerId: 'handler-001',
      dogId: 'dog-001',
      typeCode: 'FARO_VEICULO',
      typeName: 'Faro em Veículo',
      locationAddress: 'Rua Brasil, 100',
      gpsLat: -22.5642,
      gpsLng: -47.4019,
      gpsAccuracy: 4.2,
      startedAt: now,
      createdAt: now,
      updatedAt: now,
      status: status,
      initialObservation: 'Acionamento via rádio',
      results: [OccurrenceResult.drugSeized],
      deletedAt: deletedAt,
    );
  }

  group('Occurrence', () {
    group('fromMap/toMap roundtrip', () {
      test('preserva todos os campos', () {
        final original = _buildOccurrence();
        final map = original.toMap();
        final restored = Occurrence.fromMap(map, 'occ-001');

        expect(restored.id, equals('occ-001'));
        expect(restored.shiftId, equals('shift-001'));
        expect(restored.primaryHandlerId, equals('handler-001'));
        expect(restored.dogId, equals('dog-001'));
        expect(restored.typeCode, equals('FARO_VEICULO'));
        expect(restored.typeName, equals('Faro em Veículo'));
        expect(restored.locationAddress, equals('Rua Brasil, 100'));
        expect(restored.gpsLat, equals(-22.5642));
        expect(restored.gpsLng, equals(-47.4019));
        expect(restored.gpsAccuracy, equals(4.2));
        expect(restored.status, equals(OccurrenceStatus.inProgress));
        expect(restored.initialObservation, equals('Acionamento via rádio'));
        expect(restored.results, equals([OccurrenceResult.drugSeized]));
      });

      test('toMap usa snake_case', () {
        final map = _buildOccurrence().toMap();

        expect(map.containsKey('shift_id'), isTrue);
        expect(map.containsKey('primary_handler_id'), isTrue);
        expect(map.containsKey('dog_id'), isTrue);
        expect(map.containsKey('type_code'), isTrue);
        expect(map.containsKey('type_name'), isTrue);
        expect(map.containsKey('location_address'), isTrue);
        expect(map.containsKey('gps_lat'), isTrue);
        expect(map.containsKey('gps_lng'), isTrue);
        expect(map.containsKey('gps_accuracy'), isTrue);
        expect(map.containsKey('started_at'), isTrue);
        expect(map.containsKey('created_at'), isTrue);
        expect(map.containsKey('updated_at'), isTrue);
        expect(map.containsKey('initial_observation'), isTrue);
        expect(map.containsKey('integrity_hash'), isTrue);
      });

      test('toMap serializa Timestamps', () {
        final map = _buildOccurrence().toMap();

        expect(map['started_at'], isA<Timestamp>());
        expect(map['created_at'], isA<Timestamp>());
        expect(map['updated_at'], isA<Timestamp>());
      });

      test('fromMap parseia Timestamp do Firestore', () {
        final map = {
          'shift_id': 'shift-001',
          'primary_handler_id': 'handler-001',
          'dog_id': 'dog-001',
          'type_code': 'PATRULHA',
          'type_name': 'Patrulha',
          'started_at': Timestamp.fromDate(now),
          'created_at': Timestamp.fromDate(now),
          'updated_at': Timestamp.fromDate(now),
          'status': 'finalized',
        };

        final occ = Occurrence.fromMap(map, 'occ-002');

        expect(occ.startedAt, equals(now));
        expect(occ.status, equals(OccurrenceStatus.finalized));
      });
    });

    group('copyWith', () {
      test('altera campo específico mantendo outros', () {
        final original = _buildOccurrence();
        final updated = original.copyWith(
          status: OccurrenceStatus.finalized,
          finalReport: 'Droga localizada no painel',
        );

        expect(updated.status, equals(OccurrenceStatus.finalized));
        expect(updated.finalReport, equals('Droga localizada no painel'));
        expect(updated.id, equals(original.id));
        expect(updated.dogId, equals(original.dogId));
        expect(updated.typeCode, equals(original.typeCode));
      });
    });

    group('SoftDeletable', () {
      test('isDeleted retorna false quando deletedAt é null', () {
        final occ = _buildOccurrence();
        expect(occ.isDeleted, isFalse);
      });

      test('isDeleted retorna true quando deletedAt está presente', () {
        final occ = _buildOccurrence(deletedAt: now);
        expect(occ.isDeleted, isTrue);
      });

      test('softDeleteFields inclui campos no toMap', () {
        final occ = _buildOccurrence(deletedAt: now);
        final map = occ.toMap();

        expect(map.containsKey('deleted_at'), isTrue);
        expect(map['deleted_at'], isA<Timestamp>());
      });
    });

    group('OccurrenceStatus', () {
      test('isOpen para inProgress e finalizing', () {
        expect(OccurrenceStatus.inProgress.isOpen, isTrue);
        expect(OccurrenceStatus.finalizing.isOpen, isTrue);
        expect(OccurrenceStatus.finalized.isOpen, isFalse);
        expect(OccurrenceStatus.canceled.isOpen, isFalse);
      });

      test('isClosed para finalized e canceled', () {
        expect(OccurrenceStatus.finalized.isClosed, isTrue);
        expect(OccurrenceStatus.canceled.isClosed, isTrue);
        expect(OccurrenceStatus.inProgress.isClosed, isFalse);
      });

      test('toMap/fromMap roundtrip', () {
        for (final status in OccurrenceStatus.values) {
          expect(OccurrenceStatus.fromMap(status.toMap()), equals(status));
        }
      });
    });

    group('OccurrenceResult', () {
      test('toMap/fromMap roundtrip', () {
        for (final result in OccurrenceResult.values) {
          expect(OccurrenceResult.fromMap(result.toMap()), equals(result));
        }
      });

      test('label não é vazio', () {
        for (final result in OccurrenceResult.values) {
          expect(result.label.isNotEmpty, isTrue);
        }
      });
    });
  });
}
