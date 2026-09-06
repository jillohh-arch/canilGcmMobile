// FF-OCC-08.I1 — REGRESSION GUARD for drug weight unit in occurrence PDF generation.
//
// Defect:
//   OccurrencePdfGenerator formatted modern `weight_grams` without unit suffix 'g',
//   leading to document ambiguity between mass in grams vs portion counts.
//
// Rule:
//   - Modern `weight_grams` -> appends ' g' (e.g. 'Maconha - 255 g')
//   - Legacy `quantidade`    -> preserves unadorned value (e.g. 'Maconha - 255')
//   - Missing / empty amount -> renders type name only (e.g. 'Maconha')

import 'package:flutter_test/flutter_test.dart';

import 'package:canil_gcm/core/services/pdf_generator/occurrence_pdf_generator.dart';
import 'package:canil_gcm/features/dogs/domain/dog.dart';
import 'package:canil_gcm/features/occurrences/domain/occurrence.dart';
import 'package:canil_gcm/features/occurrences/domain/occurrence_result.dart';
import 'package:canil_gcm/features/occurrences/domain/occurrence_status.dart';

import 'pdf_diagnostic_harness.dart';

final _t0 = DateTime(2026, 8, 25, 10, 0);

Dog _dog() => Dog(
      id: 'dog-01',
      name: 'Thor',
      breed: 'Pastor Belga Malinois',
      dateOfBirth: DateTime(2021, 3, 10),
      registrationNumber: 'K9-0001',
    );

void main() {
  setUpAll(() async {
    await installHermeticPdfHarness();
  });

  tearDownAll(() {
    uninstallHermeticPdfHarness();
  });

  group('FF-OCC-08 — Drug weight unit formatting', () {
    test('Case A: modern single drug weight_grams gets "g" unit', () {
      final input = [
        {'type': 'Maconha', 'weight_grams': '255'},
      ];
      final formatted = OccurrencePdfGenerator.formatDrugDescriptionForTest(input);
      expect(formatted, equals('Maconha - 255 g'));
    });

    test('Case B: three modern drug entries each carry "g" unit', () {
      final input = [
        {'type': 'Maconha', 'weight_grams': '255'},
        {'type': 'Cocaína', 'weight_grams': '171'},
        {'type': 'Crack', 'weight_grams': '24'},
      ];
      final formatted = OccurrencePdfGenerator.formatDrugDescriptionForTest(input);
      expect(
        formatted,
        equals('Maconha - 255 g; Cocaína - 171 g; Crack - 24 g'),
      );
    });

    test('Case C: legacy quantidade preserves unadorned value without invented unit', () {
      final input = [
        {'type': 'Maconha', 'quantidade': '255'},
      ];
      final formatted = OccurrencePdfGenerator.formatDrugDescriptionForTest(input);
      expect(formatted, equals('Maconha - 255'));
    });

    test('Case D: missing amount renders type only', () {
      final input = [
        {'type': 'Maconha'},
      ];
      final formatted = OccurrencePdfGenerator.formatDrugDescriptionForTest(input);
      expect(formatted, equals('Maconha'));
    });

    test('Case E: empty weight_grams string renders type only', () {
      final input = [
        {'type': 'Maconha', 'weight_grams': ''},
      ];
      final formatted = OccurrencePdfGenerator.formatDrugDescriptionForTest(input);
      expect(formatted, equals('Maconha'));
    });

    test('Case E2: empty weight_grams does NOT fall back to legacy quantidade', () {
      // PRECEDENCE PRESERVATION (FF-OCC-08.I1-R).
      // `??` selects on null, not on emptiness: an EXISTING but empty
      // `weight_grams` remains the selected field, so the legacy `quantidade`
      // is never consulted. Baseline behaviour renders the type alone, and this
      // gate must not "improve" that into 'Maconha - 255'.
      final input = [
        {'type': 'Maconha', 'weight_grams': '', 'quantidade': '255'},
      ];
      final formatted = OccurrencePdfGenerator.formatDrugDescriptionForTest(input);
      expect(
        formatted,
        equals('Maconha'),
        reason:
            'Empty weight_grams must not fall through to quantidade. A result of '
            '"Maconha - 255" means the modern/legacy precedence drifted.',
      );
    });

    test('Case I: type whitespace is preserved exactly, not trimmed', () {
      // PRESERVATION (FF-OCC-08.I1-R): the baseline formatter never trimmed the
      // type. Introducing a trim here would be an unrelated semantic change.
      final input = [
        {'type': ' Maconha ', 'weight_grams': '255'},
      ];
      final formatted = OccurrencePdfGenerator.formatDrugDescriptionForTest(input);
      expect(
        formatted,
        equals(' Maconha  - 255 g'),
        reason:
            'Type must pass through verbatim. Any trimming is scope drift beyond '
            'the documented gram-unit fix.',
      );
    });

    test('Case J: empty type is NOT normalized to the placeholder', () {
      // PRESERVATION (FF-OCC-08.I1-R): `??` only substitutes 'substancia' when
      // BOTH keys are absent. An explicitly empty string is a present value and
      // baseline rendered it as-is.
      final input = [
        {'type': '', 'weight_grams': '255'},
      ];
      final formatted = OccurrencePdfGenerator.formatDrugDescriptionForTest(input);
      expect(
        formatted,
        equals(' - 255 g'),
        reason:
            'An empty type must not become "substancia" — that fallback applies '
            'only to a MISSING key (Case F).',
      );
    });

    test('Case F: fallback type "substancia" used when type is missing', () {
      final input = [
        {'weight_grams': '50'},
      ];
      final formatted = OccurrencePdfGenerator.formatDrugDescriptionForTest(input);
      expect(formatted, equals('substancia - 50 g'));
    });

    test('Case G: empty or non-list raw input returns default placeholder', () {
      expect(
        OccurrencePdfGenerator.formatDrugDescriptionForTest([]),
        equals('Substancia analoga a entorpecente apreendida e registrada na ocorrencia.'),
      );
      expect(
        OccurrencePdfGenerator.formatDrugDescriptionForTest(null),
        equals('Substancia analoga a entorpecente apreendida e registrada na ocorrencia.'),
      );
    });

    test('Case H: real generator produces valid PDF bytes with drug seized results', () async {
      final occurrence = Occurrence(
        id: 'occ-drug-test-01',
        shiftId: 'shift-01',
        primaryHandlerId: 'handler-01',
        primaryHandlerRa: '12345',
        dogId: 'dog-01',
        typeCode: 'TC-01',
        typeName: 'Apreensão de Entorpecentes',
        locationAddress: 'Rua das Palmeiras, 100',
        startedAt: _t0,
        finalizedAt: _t0.add(const Duration(hours: 2)),
        createdAt: _t0,
        updatedAt: _t0.add(const Duration(hours: 2)),
        status: OccurrenceStatus.finalized,
        finalReport: 'Relato de teste com apreensao de entorpecentes.',
        results: const [OccurrenceResult.drugSeized],
        details: const {
          'drug_seized': [
            {'type': 'Maconha', 'weight_grams': '255'},
            {'type': 'Cocaína', 'weight_grams': '171'},
            {'type': 'Crack', 'weight_grams': '24'},
          ],
        },
      );

      final generator = OccurrencePdfGenerator();
      final bytes = await generator.generate(
        occurrence: occurrence,
        events: const [],
        dog: _dog(),
        handlerName: 'GCM Silva',
        handlerRa: '12345',
      );

      expect(bytes, isNotNull);
      expect(bytes.length, greaterThan(0));
    });
  });
}
