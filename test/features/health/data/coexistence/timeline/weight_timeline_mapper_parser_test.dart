import 'package:canil_gcm/features/health/data/coexistence/timeline/health_timeline_mappers.dart';
import 'package:canil_gcm/features/health/data/coexistence/timeline/timeline_mapping_result.dart';
import 'package:canil_gcm/features/health/domain/health_v1_enums_ext.dart';
import 'package:canil_gcm/features/health/presentation/timeline/health_timeline_entry_view.dart';
import 'package:canil_gcm/features/health/presentation/timeline/health_timeline_query.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final measured = DateTime.utc(2026, 8, 6, 10, 32);
  final query = HealthTimelineQuery(dogId: 'dog-apolo');

  Map<String, dynamic> v1(num weight) => {
    'dog_id': 'dog-apolo',
    'weight_kg': weight,
    'schema_version': 1,
    'measured_at': measured,
    'recorded_by': const {
      'uid': 'u',
      'name': 'Ana',
      'internal_role': 'condutor',
    },
  };

  Map<String, dynamic> v2Quick({String status = 'valid'}) => {
    'dog_id': 'dog-apolo',
    'weight_kg': 33.3,
    'measured_at': measured,
    'recorded_at': measured,
    'recorded_by': const {
      'uid': 'u',
      'name': 'Bia',
      'internal_role': 'future_role',
    },
    'schema_version': 2,
    'record_type': 'quick',
    'origin_record_type': 'quick',
    'status': status,
    'revision': 1,
  };

  TimelineMappingResult map(Map<String, dynamic> data) =>
      HealthTimelineMappers.mapWeightRecord(
        dogId: 'dog-apolo',
        docId: 'w1',
        data: data,
        filters: query,
      );

  test('v1 valid → evento de peso', () {
    final result = map(v1(32.0));
    expect(result, isA<TimelineMapped>());
    final entry = (result as TimelineMapped).entry;
    expect(entry.type.known, HealthTimelineType.weight);
    expect(entry.title, 'Pesagem');
  });

  test('v2 valid → evento de peso', () {
    final result = map(v2Quick());
    expect(result, isA<TimelineMapped>());
  });

  test('invalidated → ignorado (excluído da timeline ordinária)', () {
    final result = map(v2Quick(status: 'invalidated'));
    expect(result, isA<TimelineIgnored>());
    expect((result as TimelineIgnored).reasonCode, 'invalidated');
  });

  test('malformed → TimelineInvalid (não vira evento)', () {
    final result = map({
      'dog_id': 'dog-apolo',
      'weight_kg': 'x',
      'schema_version': 1,
      'measured_at': measured,
    });
    expect(result, isA<TimelineInvalid>());
  });

  test('unsupported (schema futuro) → TimelineInvalid', () {
    final result = map({
      'dog_id': 'dog-apolo',
      'weight_kg': 33.3,
      'schema_version': 9,
      'measured_at': measured,
    });
    expect(result, isA<TimelineInvalid>());
  });

  test('created_at permanece apenas como fallback derivado de recordedAt', () {
    final createdAt = DateTime.utc(2026, 8, 6, 9);
    final result = map({...v1(32.0), 'created_at': createdAt});
    final entry = (result as TimelineMapped).entry;
    // occurredAt vem de measured_at; recordedAt usa created_at como fallback.
    expect(entry.occurredAt, measured);
    expect(entry.recordedAt, createdAt);
  });

  test('soft-deleted → ignorado', () {
    final result = map({...v1(32.0), 'deleted_at': measured});
    expect(result, isA<TimelineIgnored>());
    expect((result as TimelineIgnored).reasonCode, 'soft_deleted');
  });
}
