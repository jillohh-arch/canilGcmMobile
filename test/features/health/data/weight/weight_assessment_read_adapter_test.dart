import 'dart:io';

import 'package:canil_gcm/features/health/data/weight/weight_assessment_read_adapter.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final measuredFirst = DateTime.utc(2026, 6, 17, 10);
  final measuredSecond = DateTime.utc(2026, 8, 6, 10, 32);
  final recordedAt = DateTime.utc(2026, 8, 6, 10, 33);

  Map<String, dynamic> deployedV1({num weight = 32.0, DateTime? measuredAt}) =>
      {
        'dog_id': 'dog-apolo',
        'weight_kg': weight,
        'measured_at': measuredAt ?? measuredFirst,
        'schema_version': 1,
        'recorded_by': const {
          'uid': 'user-1',
          'name': 'Ana',
          'internal_role': 'condutor',
        },
        'context': 'routine',
      };

  // Web legado: measured_by + performed_by, sem recorded_by canônico.
  Map<String, dynamic> legacyWeb() => {
    'dog_id': 'dog-apolo',
    'weight_kg': 32.0,
    'measured_at': measuredFirst,
    'measured_by': 'RA-1234',
    'performed_by': 'RA-1234',
  };

  // Atualização legada via dog update: performed_by, sem measured_by/context/notes.
  Map<String, dynamic> legacyDogUpdate() => {
    'dog_id': 'dog-apolo',
    'weight_kg': 33.3,
    'measured_at': measuredSecond,
    'performed_by': 'RA-9999',
  };

  Map<String, dynamic> quickV2({String status = 'valid'}) => {
    'dog_id': 'dog-apolo',
    'weight_kg': 33.3,
    'measured_at': measuredSecond,
    'recorded_at': recordedAt,
    'recorded_by': const {
      'uid': 'user-2',
      'name': 'Bia',
      'internal_role': 'future_role',
    },
    'schema_version': 2,
    'record_type': 'quick',
    'origin_record_type': 'quick',
    'status': status,
    'revision': 1,
  };

  Map<String, dynamic> officialV2() => {
    ...quickV2(),
    'record_type': 'official',
    'origin_record_type': 'official',
    'information_source': 'measured_by_recorder',
    'location': 'kennel',
    'measurement_condition': 'no_specific_condition',
    'equipment_state': 'none',
    'reading_quality': 'stable',
    'bcs': 3,
    'bcs_source': 'operator_assessment',
  };

  WeightReadResult read(
    Map<String, dynamic> data, {
    String documentId = 'weight-1',
    String dogId = 'dog-apolo',
    String sourceCollection = 'weight_records',
  }) => WeightAssessmentReadAdapter.read(
    documentId: documentId,
    dogId: dogId,
    data: data,
    sourceCollection: sourceCollection,
  );

  group('WeightAssessmentReadAdapter — classificação', () {
    test('deployed v1 canônico → valid + façade com autoria factual', () {
      final result = read(deployedV1());
      expect(result.kind, WeightReadKind.valid);
      expect(result.record, isNotNull);
      expect(result.record!.weightKg, 32.0);
      expect(result.record!.recordedBy!.name, 'Ana');
      expect(result.record!.schemaVersion, 1);
    });

    test('legacy Web sem recorder → valid + façade com autoria ausente', () {
      final result = read(legacyWeb());
      expect(result.kind, WeightReadKind.valid);
      expect(result.assessment, isNotNull);
      expect(result.assessment!.recorder, isNull);
      // Pesagem permanece renderizável; autoria não é inventada.
      expect(result.record, isNotNull);
      expect(result.record!.weightKg, 32.0);
      expect(result.record!.recordedBy, isNull);
      expect(result.record!.measuredBy, '');
    });

    test(
      'legacy dog update sem recorder → valid + façade com autoria ausente',
      () {
        final result = read(legacyDogUpdate());
        expect(result.kind, WeightReadKind.valid);
        expect(result.assessment!.recorder, isNull);
        expect(result.record, isNotNull);
        expect(result.record!.weightKg, 33.3);
        expect(result.record!.recordedBy, isNull);
      },
    );

    test('v2 Quick válido → valid + façade', () {
      final result = read(quickV2());
      expect(result.kind, WeightReadKind.valid);
      expect(result.record, isNotNull);
      expect(result.record!.weightKg, 33.3);
    });

    test('v2 Official válido → valid + façade', () {
      final result = read(officialV2());
      expect(result.kind, WeightReadKind.valid);
      expect(result.record, isNotNull);
    });

    // PRE-V2-WEIGHT-RECORDEDAT-FACADE-CORRECTIONS: esta é a ÚNICA rota de
    // runtime que carrega `recordedAt` para a façade, e antes desta correção
    // nenhum teste detectava sua remoção. Deve falhar se a propagação em
    // `_toRecord` for apagada.
    test('recordedAt do aggregate é propagado para a façade', () {
      final result = read(quickV2());

      expect(result.assessment!.recordedAt, recordedAt);
      // O que importa: a façade carrega o MESMO instante do aggregate.
      expect(result.record!.recordedAt, recordedAt);
      expect(result.record!.recordedAt, result.assessment!.recordedAt);
      // Não colapsa com `measuredAt`: o desempate depende de serem distintos.
      expect(result.record!.recordedAt, isNot(result.record!.measuredAt));
    });

    test('v1 sem recorded_at → façade com recordedAt null', () {
      final result = read(deployedV1());

      expect(result.kind, WeightReadKind.valid);
      expect(result.assessment!.recordedAt, isNull);
      // Ausência é factual, não substituída por `measuredAt`/`created_at`.
      expect(result.record!.recordedAt, isNull);
    });

    test('invalidated → invalidated, sem façade, não promovido', () {
      final result = read(quickV2(status: 'invalidated'));
      expect(result.kind, WeightReadKind.invalidated);
      expect(result.record, isNull);
      expect(result.assessment, isNotNull);
    });

    test('malformed → bloqueia leitura, sem façade', () {
      final result = read({
        'dog_id': 'dog-apolo',
        'weight_kg': 'not-a-number',
        'measured_at': measuredFirst,
        'schema_version': 1,
      });
      expect(result.kind, WeightReadKind.malformed);
      expect(result.isBlocking, isTrue);
      expect(result.record, isNull);
    });

    test('unsupported (schema futuro) → bloqueia leitura, sem façade', () {
      final result = read({
        'dog_id': 'dog-apolo',
        'weight_kg': 33.3,
        'measured_at': measuredSecond,
        'schema_version': 3,
      });
      expect(result.kind, WeightReadKind.unsupported);
      expect(result.isBlocking, isTrue);
      expect(result.record, isNull);
    });

    test('coleção não canônica é rejeitada por contexto de origem', () {
      final result = read(deployedV1(), sourceCollection: 'weight_history');
      expect(result.kind, WeightReadKind.malformed);
    });

    test('dogId autoritativo divergente do embutido → malformed', () {
      final result = read(deployedV1(), dogId: 'dog-outro');
      expect(result.kind, WeightReadKind.malformed);
    });
  });

  group('WeightAssessmentReadAdapter — diagnostics seguros', () {
    test('diagnostics expõem apenas códigos, sem PII/RA', () {
      final result = read(legacyWeb());
      expect(result.diagnosticCodes, isNotEmpty);
      // Códigos são enum; não há strings livres com uid/nome/RA/email.
      for (final code in result.diagnosticCodes) {
        expect(code, isA<Enum>());
      }
    });
  });

  group('WeightAssessmentReadAdapter — guardrails de código-fonte', () {
    late final String source;

    setUpAll(() {
      source = File(
        'lib/features/health/data/weight/weight_assessment_read_adapter.dart',
      ).readAsStringSync();
    });

    test('não usa o getter deprecated recordedBy em aggregate do parser', () {
      // `.recordedBy` (getter deprecated do aggregate) nunca é chamado; a
      // façade é construída a partir de `recorder`.
      expect(source.contains('.recordedBy'), isFalse);
      expect(source.contains('assessment.recorder'), isTrue);
    });

    test('não acessa/expõe legacyActorReference', () {
      // O termo pode aparecer em comentário explicativo; o que é proibido é
      // o acesso à propriedade (`.legacyActorReference`).
      expect(source.contains('.legacyActorReference'), isFalse);
    });
  });
}
