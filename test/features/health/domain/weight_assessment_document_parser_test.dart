import 'package:canil_gcm/features/health/domain/health_v1_enums.dart';
import 'package:canil_gcm/features/health/domain/weight_assessment.dart';
import 'package:canil_gcm/features/health/domain/weight_assessment_document_parser.dart';
import 'package:flutter_test/flutter_test.dart';

final class _FakeTimestamp {
  const _FakeTimestamp(this.value);
  final DateTime value;
  DateTime toDate() => value;
}

void main() {
  final apoloFirst = DateTime.utc(2026, 6, 17, 10);
  final apoloSecond = DateTime.utc(2026, 8, 6, 10, 32);
  final recordedAt = DateTime.utc(2026, 8, 6, 10, 33);

  Map<String, Object?> deployedV1(num weight, DateTime measuredAt) => {
    'dogId': 'dog-apolo',
    'dog_id': 'dog-apolo',
    'weight_kg': weight,
    'measured_at': measuredAt,
    'recorded_by': const {
      'uid': 'user-masked',
      'name': 'Operator',
      'internal_role': 'condutor',
    },
    'schema_version': 1,
    'created_at': recordedAt,
    'updated_at': recordedAt,
    'audit_trail': const <Object?>[],
    'context': 'routine',
  };

  Map<String, Object?> quickV2({
    num weight = 33.3,
    String recordType = 'quick',
    String originType = 'quick',
    String status = 'valid',
  }) => {
    'dogId': 'dog-apolo',
    'dog_id': 'dog-apolo',
    'weight_kg': weight,
    'measured_at': apoloSecond,
    'recorded_at': recordedAt,
    'recorded_by': const {
      'uid': 'user-masked',
      'name': 'Operator',
      'internal_role': 'future_role',
    },
    'schema_version': 2,
    'record_type': recordType,
    'origin_record_type': originType,
    'status': status,
    'revision': 1,
  };

  Map<String, Object?> officialV2() => {
    ...quickV2(recordType: 'official', originType: 'official'),
    'information_source': 'measured_by_recorder',
    'location': 'kennel',
    'measurement_condition': 'no_specific_condition',
    'equipment_state': 'none',
    'reading_quality': 'stable',
    'bcs': 3,
    'bcs_source': 'operator_assessment',
  };

  WeightAssessmentParseResult parse(
    Map<String, Object?> data, {
    String sourceCollection = 'weight_records',
  }) => WeightAssessmentDocumentParser.parse(
    entityId: 'weight-1',
    dogId: 'dog-apolo',
    data: data,
    sourceCollection: sourceCollection,
  );

  group('deployed v1 e bridge legacy_simple', () {
    test('fixtures sanitizadas do Apolo 32,0 e 33,3 permanecem factuais', () {
      final first = parse(deployedV1(32.0, apoloFirst));
      final second = parse(deployedV1(33.3, apoloSecond));

      for (final result in [first, second]) {
        expect(result.kind, WeightAssessmentParseResultKind.success);
        expect(
          result.assessment!.recordType.value,
          WeightRecordType.legacySimple,
        );
        expect(
          result.assessment!.originRecordType.value,
          WeightRecordType.legacySimple,
        );
        expect(result.assessment!.status.value, WeightAssessmentStatus.valid);
        expect(result.assessment!.revision, 1);
        expect(result.assessment!.recordedAt, isNull);
      }
      expect(first.assessment!.weightKg, 32.0);
      expect(second.assessment!.weightKg, 33.3);
    });

    test('defaults são derivados e não fatos target', () {
      final assessment = parse(deployedV1(33.3, apoloSecond)).assessment!;
      expect(assessment.compatibility.persistedSchemaVersion, 1);
      expect(assessment.compatibility.schemaVersionDerived, isFalse);
      expect(
        assessment.compatibility.derivedFields,
        containsAll(WeightDerivedField.values),
      );
      expect(assessment.officialDetails, isNull);
      expect(assessment.attachmentReferences, isEmpty);
      expect(assessment.clinicalLinks, isEmpty);
    });

    test('precisão histórica 32.523 é preservada sem arredondamento', () {
      final result = parse(deployedV1(32.523, apoloFirst));
      expect(result.assessment!.weightKg, 32.523);
      expect(
        result.diagnostics.map((item) => item.code),
        contains(WeightDocumentDiagnosticCode.legacyPrecisionPreserved),
      );
    });

    test('Timestamp-like é aceito sem dependência Firestore', () {
      final data = deployedV1(33.3, apoloSecond)
        ..['measured_at'] = _FakeTimestamp(apoloSecond);
      expect(parse(data).assessment!.measuredAt, apoloSecond);
    });

    test('map timestamp rejeita componentes fracionários', () {
      final data = deployedV1(33.3, apoloSecond)
        ..['measured_at'] = {'seconds': 1.5, 'nanoseconds': 0};
      expect(parse(data).kind, WeightAssessmentParseResultKind.malformed);
    });
  });

  group('adapters legados reconhecidos', () {
    test('legacy Mobile preserva peso factual com measured_by isolado', () {
      final result = parse({
        'weight_kg': 28.8,
        'measured_at': apoloFirst,
        'measured_by': 'masked-actor',
        'context': 'canil',
      });
      expect(result.kind, WeightAssessmentParseResultKind.success);
      expect(result.assessment!.weightKg, 28.8);
      expect(result.assessment!.recorder, isNull);
      expect(
        result.assessment!.compatibility.sourceShape,
        WeightDocumentSourceShape.recognizedLegacyMobile,
      );
      expect(
        result.diagnostics.map((item) => item.code),
        contains(WeightDocumentDiagnosticCode.missingCanonicalRecorder),
      );
    });

    test('measured_by não-String não é promovido a legacy Mobile', () {
      final result = parse({
        'weight_kg': 28.0,
        'measured_at': apoloFirst,
        'measured_by': 42,
      });
      expect(result.kind, WeightAssessmentParseResultKind.malformed);
      expect(
        result.diagnostics.single.code,
        WeightDocumentDiagnosticCode.unknownLegacyShape,
      );
    });

    test('measured_by vazio ou whitespace não é legacy Mobile', () {
      for (final actor in const ['', '   ']) {
        final result = parse({
          'weight_kg': 28.0,
          'measured_at': apoloFirst,
          'measured_by': actor,
        });
        expect(result.kind, WeightAssessmentParseResultKind.malformed);
        expect(
          result.diagnostics.single.code,
          WeightDocumentDiagnosticCode.unknownLegacyShape,
        );
      }
    });

    test('legacy Web permite autoria ausente com diagnostic', () {
      final result = parse({
        'dogId': 'dog-apolo',
        'dog_id': 'dog-apolo',
        'weight_kg': 31.5,
        'measured_at': apoloFirst,
        'measured_by': 'masked-actor',
        'performed_by': 'masked-actor',
        'context': 'canil',
        'created_at': recordedAt,
        'updated_at': recordedAt,
        'audit_trail': const <Object?>[],
      });
      expect(result.assessment!.recorder, isNull);
      expect(
        result.assessment!.compatibility.sourceShape,
        WeightDocumentSourceShape.recognizedLegacyWeb,
      );
      expect(
        result.diagnostics.map((item) => item.code),
        contains(WeightDocumentDiagnosticCode.missingCanonicalRecorder),
      );
    });

    test('legacy dog update possui detector distinto e restrito', () {
      final result = parse({
        'dogId': 'dog-apolo',
        'dog_id': 'dog-apolo',
        'weight_kg': 31.5,
        'measured_at': apoloFirst,
        'performed_by': 'masked-actor',
        'created_at': recordedAt,
        'updated_at': recordedAt,
        'audit_trail': const <Object?>[],
      });
      expect(
        result.assessment!.compatibility.sourceShape,
        WeightDocumentSourceShape.recognizedLegacyDogUpdate,
      );
      expect(result.assessment!.recorder, isNull);
    });

    test('shape sem schema desconhecido não recebe fallback permissivo', () {
      final result = parse({'weight_kg': 31.5, 'measured_at': apoloFirst});
      expect(result.kind, WeightAssessmentParseResultKind.malformed);
      expect(
        result.diagnostics.single.code,
        WeightDocumentDiagnosticCode.unknownLegacyShape,
      );
    });

    test('mirror weight_history nunca é fonte canônica', () {
      final result = parse({
        'dog_id': 'dog-apolo',
        'weight_kg': 31.5,
        'measured_at': apoloFirst,
        'measured_by': 'masked-actor',
        'performed_by': 'masked-actor',
      }, sourceCollection: 'weight_history');
      expect(result.kind, WeightAssessmentParseResultKind.malformed);
      expect(
        result.diagnostics.single.code,
        WeightDocumentDiagnosticCode.nonCanonicalCollection,
      );
    });
  });

  group('precedência de schema', () {
    test('v1 com discriminator target é hybrid/malformed', () {
      final data = deployedV1(33.3, apoloSecond)..['record_type'] = 'quick';
      final result = parse(data);
      expect(result.kind, WeightAssessmentParseResultKind.malformed);
      expect(
        result.diagnostics.single.code,
        WeightDocumentDiagnosticCode.hybridV1V2,
      );
    });

    test('schema ausente com campo target isolado é hybrid/malformed', () {
      final result = parse({
        'weight_kg': 33.3,
        'measured_at': apoloSecond,
        'performed_by': 'masked',
        'status': 'valid',
      });
      expect(result.kind, WeightAssessmentParseResultKind.malformed);
      expect(
        result.diagnostics.single.code,
        WeightDocumentDiagnosticCode.hybridV1V2,
      );
    });

    test('schema futuro é unsupported e preserva versão segura', () {
      final result = parse({...quickV2(), 'schema_version': 3});
      expect(result.kind, WeightAssessmentParseResultKind.unsupported);
      expect(result.unsupportedSchemaVersion, 3);
      expect(result.diagnostics.single.safeRaw, '3');
    });

    test('schema inválido não é coagido', () {
      for (final value in <Object>['2', 2.5, -1]) {
        final result = parse({...quickV2(), 'schema_version': value});
        expect(result.kind, WeightAssessmentParseResultKind.malformed);
      }
    });
  });

  group('target v2', () {
    test('Quick válido preserva role futura e não inventa Official', () {
      final result = parse(quickV2());
      expect(result.kind, WeightAssessmentParseResultKind.success);
      expect(result.assessment!.recordType.value, WeightRecordType.quick);
      expect(result.assessment!.officialDetails, isNull);
      expect(result.assessment!.recorder!.internalRole, 'future_role');
    });

    test('Official válido contém detalhes e BCS 1–5', () {
      final result = parse(officialV2());
      expect(result.kind, WeightAssessmentParseResultKind.success);
      expect(result.assessment!.recordType.value, WeightRecordType.official);
      expect(result.assessment!.officialDetails!.bodyConditionScore!.value, 3);
    });

    test('Official incompleto é malformed', () {
      final data = officialV2()..remove('information_source');
      expect(parse(data).kind, WeightAssessmentParseResultKind.malformed);
    });

    test('Quick com campo Official é malformed', () {
      final data = quickV2()..['location'] = 'kennel';
      final result = parse(data);
      expect(result.kind, WeightAssessmentParseResultKind.malformed);
      expect(
        result.diagnostics.single.code,
        WeightDocumentDiagnosticCode.forbiddenTargetFieldOnQuick,
      );
    });

    test('invalidated é classificado sem apagamento', () {
      final result = parse(quickV2(status: 'invalidated'));
      expect(
        result.assessment!.status.value,
        WeightAssessmentStatus.invalidated,
      );
      expect(result.assessment!.weightKg, 33.3);
    });

    test('enum unknown preserva raw e diagnostic', () {
      final result = parse(quickV2(status: 'future_status'));
      expect(result.kind, WeightAssessmentParseResultKind.success);
      expect(result.assessment!.status.isUnknown, isTrue);
      expect(result.assessment!.status.raw, 'future_status');
      expect(
        result.diagnostics.map((item) => item.code),
        contains(WeightDocumentDiagnosticCode.unknownEnum),
      );
    });

    test('v2 rejeita precisão 32.523 sem arredondar', () {
      final result = parse(quickV2(weight: 32.523));
      expect(result.kind, WeightAssessmentParseResultKind.malformed);
    });

    test('BCS 1 e 5 são válidos; BCS 9 não é convertido', () {
      for (final bcs in [1, 5]) {
        final result = parse(officialV2()..['bcs'] = bcs);
        expect(result.kind, WeightAssessmentParseResultKind.success);
      }
      final legacyNine = parse(officialV2()..['bcs'] = 9);
      expect(legacyNine.kind, WeightAssessmentParseResultKind.malformed);
    });
  });

  group('integridade', () {
    test('dogId embutido divergente é malformed', () {
      final result = parse({
        ...deployedV1(33.3, apoloSecond),
        'dog_id': 'other',
      });
      expect(result.kind, WeightAssessmentParseResultKind.malformed);
      expect(
        result.diagnostics.single.code,
        WeightDocumentDiagnosticCode.embeddedDogIdMismatch,
      );
    });

    test('timestamp, recorder e peso malformed são distinguidos', () {
      final timestamp = parse({
        ...deployedV1(33.3, apoloSecond),
        'measured_at': 'x',
      });
      final recorder = parse({
        ...deployedV1(33.3, apoloSecond),
        'recorded_by': {},
      });
      final weight = parse({...deployedV1(33.3, apoloSecond), 'weight_kg': 0});
      expect(
        timestamp.diagnostics.map((item) => item.code),
        contains(WeightDocumentDiagnosticCode.malformedTimestamp),
      );
      expect(
        recorder.diagnostics.map((item) => item.code),
        contains(WeightDocumentDiagnosticCode.malformedRecorder),
      );
      expect(
        weight.diagnostics.map((item) => item.code),
        contains(WeightDocumentDiagnosticCode.malformedWeight),
      );
    });

    test('e-mail em recorded_by target é rejeitado', () {
      final data = quickV2();
      data['recorded_by'] = {
        ...(data['recorded_by']! as Map<String, Object?>),
        'email': 'redacted',
      };
      expect(parse(data).kind, WeightAssessmentParseResultKind.malformed);
    });
  });
}
