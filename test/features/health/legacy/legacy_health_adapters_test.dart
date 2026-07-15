import 'package:canil_gcm/features/health/domain/health_v1_enums.dart';
import 'package:canil_gcm/features/health/domain/health_v1_models.dart';
import 'package:canil_gcm/features/health/legacy/legacy_health_adapters.dart';
import 'package:flutter_test/flutter_test.dart';

final class _FakeTimestamp {
  const _FakeTimestamp(this.value);
  final DateTime value;
  DateTime toDate() => value;
}

final class _ThrowingTimestamp {
  DateTime toDate() => throw StateError('broken');
}

final class _WrongTimestamp {
  String toDate() => 'not a date';
}

void main() {
  group('LegacyDateParser', () {
    final expected = DateTime.utc(2026, 7, 14, 12, 30);

    test('aceita DateTime, timestamp-like, mapas, pre-epoch e ISO', () {
      expect(LegacyDateParser.parse(expected).value, expected);
      expect(LegacyDateParser.parse(_FakeTimestamp(expected)).value, expected);
      expect(
        LegacyDateParser.parse({
          'seconds': expected.microsecondsSinceEpoch ~/ 1000000,
          'nanoseconds': 123456000,
        }).value?.microsecond,
        456,
      );
      expect(
        LegacyDateParser.parse({
          '_seconds': expected.microsecondsSinceEpoch ~/ 1000000,
          '_nanoseconds': 0,
        }).hasValue,
        isTrue,
      );
      expect(
        LegacyDateParser.parse({'seconds': -1, 'nanoseconds': 0}).value,
        DateTime.fromMillisecondsSinceEpoch(-1000, isUtc: true),
      );
      expect(
        LegacyDateParser.parse('2026-07-14T12:30:00Z').value?.isUtc,
        isTrue,
      );
      expect(
        LegacyDateParser.parse('2026-07-14T09:30:00-03:00').value?.toUtc(),
        expected,
      );
      expect(
        LegacyDateParser.parse('2026-07-14T12:30:00').value?.isUtc,
        isFalse,
      );
    });

    test('distingue ausência, ISO inválida e tipos incompatíveis', () {
      expect(LegacyDateParser.parse(null).state, LegacyParseState.absent);
      expect(LegacyDateParser.parse(' ').state, LegacyParseState.absent);
      expect(
        LegacyDateParser.parse('sem-data').issues.single.code,
        'invalid_iso',
      );
      expect(
        LegacyDateParser.parse(Object()).issues.single.code,
        'timestamp_like_missing_method',
      );
      expect(
        LegacyDateParser.parse(_ThrowingTimestamp()).issues.single.code,
        'timestamp_like_exception',
      );
      expect(
        LegacyDateParser.parse(_WrongTimestamp()).issues.single.code,
        'timestamp_like_invalid_return',
      );
    });

    test(
      'rejeita componentes fracionários, nanos fora da faixa e extremos',
      () {
        for (final value in [
          {'seconds': 1.5, 'nanoseconds': 0},
          {'seconds': 1, 'nanoseconds': 0.5},
          {'seconds': 1, 'nanoseconds': -1},
          {'seconds': 1, 'nanoseconds': 1000000000},
          {'nanoseconds': 0},
          {'seconds': double.infinity, 'nanoseconds': 0},
          {'seconds': 1e30, 'nanoseconds': 0},
        ]) {
          expect(LegacyDateParser.parse(value).hasValue, isFalse);
        }
      },
    );

    test('nanoseconds ausentes equivalem a zero', () {
      expect(
        LegacyDateParser.parse({'seconds': 0}).value,
        DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
      );
    });
  });

  group('LegacyParseResult', () {
    test('copia issues e expõe lista imutável', () {
      final source = <LegacyParseIssue>[
        const LegacyParseIssue(
          code: 'x',
          field: 'field',
          severity: LegacyIssueSeverity.error,
          message: 'Erro técnico',
        ),
      ];
      final result = LegacyParseResult<Object>.failure(source);
      source.clear();
      expect(result.issues, hasLength(1));
      expect(() => result.issues.clear(), throwsUnsupportedError);
    });

    test('impõe invariantes de failure, partial e absent', () {
      const warning = LegacyParseIssue(
        code: 'warning',
        severity: LegacyIssueSeverity.warning,
        message: 'Aviso técnico',
      );
      const error = LegacyParseIssue(
        code: 'error',
        severity: LegacyIssueSeverity.error,
        message: 'Erro técnico',
      );
      expect(
        () => LegacyParseResult<Object>.failure(const []),
        throwsArgumentError,
      );
      expect(
        () => LegacyParseResult<Object>.failure(const [warning]),
        throwsArgumentError,
      );
      expect(
        LegacyParseResult<Object>.failure(const [error]).state,
        LegacyParseState.failure,
      );
      expect(
        () => LegacyParseResult<Object>.partial(Object(), const []),
        throwsArgumentError,
      );
      expect(
        LegacyParseResult<Object>.absent().state,
        isNot(LegacyParseState.failure),
      );
    });
  });

  group('RawHealthEventsAdapter', () {
    const adapter = RawHealthEventsAdapter();

    test('mapeia documento real e congela payload profundamente', () {
      final nested = <String, Object?>{
        'items': <Object?>[
          {'nested': true},
        ],
      };
      final payload = <String, Object?>{
        'type': 'custom_future_type',
        'date': '2026-07-14T12:30:00Z',
        'healthObservations': 'Observação legada',
        'unknown_field': nested,
      };
      final result = adapter.parse(
        sourceId: 'event-1',
        dogId: 'dog-1',
        data: payload,
      );
      (nested['items']! as List).clear();
      payload['type'] = 'changed';

      expect(result.state, LegacyParseState.success);
      expect(result.value?.typeRaw, 'custom_future_type');
      expect(result.value?.originalPayload['type'], 'custom_future_type');
      expect(
        ((result.value?.originalPayload['unknown_field'] as Map)['items']
            as List),
        hasLength(1),
      );
      expect(
        () =>
            ((result.value!.originalPayload['unknown_field'] as Map)['items']
                    as List)
                .clear(),
        throwsUnsupportedError,
      );
    });

    test('tipo ausente gera partial sem default clínico', () {
      final result = adapter.parse(
        sourceId: 'event-2',
        dogId: 'dog-1',
        data: {'created_at': DateTime.utc(2026, 7, 14)},
      );
      expect(result.state, LegacyParseState.partial);
      expect(result.value?.typeRaw, '');
      expect(result.issues.single.severity, LegacyIssueSeverity.warning);
    });

    test('aliases removidos não são aceitos', () {
      final onlyOccurredAt = adapter.parse(
        sourceId: 'event-2',
        dogId: 'dog-1',
        data: {'occurred_at': DateTime.utc(2026, 7, 14)},
      );
      expect(onlyOccurredAt.state, LegacyParseState.failure);
      final subtypeOnly = adapter.parse(
        sourceId: 'event-3',
        dogId: 'dog-1',
        data: {'date': DateTime.utc(2026, 7, 14), 'subtype': 'vacina-x'},
      );
      expect(subtypeOnly.value?.typeRaw, '');
    });
  });

  group('LegacyWeightAdapter', () {
    const adapter = LegacyWeightAdapter();

    test('preserva measured_by real em view parcial sem inventar autoria', () {
      final result = adapter.parse(
        sourceId: 'weight-1',
        dogId: 'dog-1',
        data: {
          'weight_kg': 24.5,
          'measured_at': DateTime.utc(2026, 7, 14),
          'measured_by': 'user-legacy',
        },
      );
      final view = result.value! as LegacyHealthRecordView;
      expect(result.state, LegacyParseState.partial);
      expect(view.originalPayload['measured_by'], 'user-legacy');
      expect(result.issues.single.field, 'measured_by');
      expect(result.issues.single.code, 'incomplete_legacy_author');
    });

    test('recorded_by completo permite entidade canônica versionada', () {
      final result = adapter.parse(
        sourceId: 'weight-enriched',
        dogId: 'dog-1',
        data: {
          'weight_kg': 24.5,
          'measured_at': DateTime.utc(2026, 7, 14),
          'recorded_by': const {
            'uid': 'user-1',
            'name': 'Condutor',
            'internal_role': 'condutor',
          },
        },
      );
      final assessment = result.value! as WeightAssessment;
      expect(result.state, LegacyParseState.success);
      expect(assessment.schemaVersion, 1);
      expect(assessment.recordedBy.uid, 'user-1');
    });

    test('rejeita alias date, autoria ausente, peso e data inválidos', () {
      final result = adapter.parse(
        sourceId: 'weight-1',
        dogId: 'dog-1',
        data: const {'weight_kg': 0, 'date': '2026-07-14T10:00:00Z'},
      );
      expect(result.state, LegacyParseState.failure);
      expect(result.issues.map((issue) => issue.field), {
        'weight_kg',
        'measured_at',
      });
    });
  });

  group('LegacyNutritionAdapter', () {
    const adapter = LegacyNutritionAdapter();

    test('preserva fed_by real em view parcial sem inventar autoria', () {
      final result = adapter.parse(
        sourceId: 'meal-1',
        dogId: 'dog-1',
        data: const {
          'period': 'manha',
          'amount_grams': 300,
          'fed_at': '2026-07-14T08:00:00Z',
          'fed_by': 'user-legacy',
        },
      );
      final view = result.value! as LegacyHealthRecordView;
      expect(result.state, LegacyParseState.partial);
      expect(view.originalPayload['fed_by'], 'user-legacy');
      expect(result.issues.single.field, 'fed_by');
      expect(result.issues.single.code, 'incomplete_legacy_author');
    });

    test('recorded_by completo permite entidade canônica versionada', () {
      final result = adapter.parse(
        sourceId: 'meal-enriched',
        dogId: 'dog-1',
        data: const {
          'period': 'manha',
          'amount_grams': 300,
          'fed_at': '2026-07-14T08:00:00Z',
          'recorded_by': {
            'uid': 'user-1',
            'name': 'Condutor',
            'internal_role': 'condutor',
          },
        },
      );
      final meal = result.value! as MealLog;
      expect(result.state, LegacyParseState.success);
      expect(meal.schemaVersion, 1);
      expect(meal.recordedBy.uid, 'user-1');
    });

    test('mapeia apenas aliases comprovados para período canônico', () {
      for (final entry in const {
        'manha': MealPeriod.morning,
        'noite': MealPeriod.night,
      }.entries) {
        expect(MealPeriodWire.parseLegacy(entry.key).value, entry.value);
      }
    });

    test('preserva período desconhecido como resultado parcial', () {
      final result = adapter.parse(
        sourceId: 'meal-1',
        dogId: 'dog-1',
        data: const {
          'period': 'almoco',
          'amount_grams': 100,
          'fed_at': '2026-07-14T04:00:00Z',
          'fed_by': 'user-legacy',
        },
      );
      final view = result.value! as LegacyHealthRecordView;
      expect(result.state, LegacyParseState.partial);
      expect(view.originalPayload['period'], 'almoco');
      expect(MealPeriodWire.parseLegacy('almoco').isUnknown, isTrue);
      expect(result.issues.map((issue) => issue.code), {
        'incomplete_legacy_author',
        'unknown_period',
      });
    });

    test('rejeita date e campos obrigatórios ausentes ou inválidos', () {
      final result = adapter.parse(
        sourceId: 'meal-1',
        dogId: 'dog-1',
        data: const {'amount_grams': 'muito', 'date': '2026-07-14T08:00:00Z'},
      );
      expect(result.state, LegacyParseState.failure);
      expect(result.issues.map((issue) => issue.field), {
        'period',
        'amount_grams',
        'fed_at',
      });
    });
  });
}
