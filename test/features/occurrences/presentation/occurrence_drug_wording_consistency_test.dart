// FF-OCC-08B — REGRESSION TEST: Drug wording and unit consistency across PDF, Confirmation, and History.
//
// Rule:
//   - All surfaces (PDF, Occurrence Confirmation, History Detail) must use the exact same
//     authoritative drug description formatted via `OccurrencePdfGenerator.formatDrugDescription`.
//   - Format is '<type> - <weight> g; <type2> - <weight2> g'.
//   - Multiple drugs are never collapsed into generic 'N substâncias'.
//   - Single drugs follow '<type> - <weight> g', consistent with PDF rather than '<weight>g de <type>'.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:canil_gcm/core/services/pdf_generator/occurrence_pdf_generator.dart';
import 'package:canil_gcm/features/history/presentation/screens/history_detail_screen.dart';
import 'package:canil_gcm/features/history/presentation/screens/history_screen.dart';
import 'package:canil_gcm/features/occurrences/domain/occurrence.dart';
import 'package:canil_gcm/features/occurrences/domain/occurrence_result.dart';
import 'package:canil_gcm/features/occurrences/domain/occurrence_status.dart';
import 'package:canil_gcm/features/occurrences/presentation/screens/occurrence_confirmation_screen.dart';

OccurrenceConfirmationData _createConfirmationData(dynamic drugDetail) {
  return OccurrenceConfirmationData(
    occurrenceId: 'occ-drug-consistency-01',
    typeName: 'Apoio Policial',
    durationLabel: '1h 30m',
    locationAddress: 'Rua das Flores, 500 - Limeira/SP',
    dogName: 'Thor',
    handlerName: 'GCM Ragonha',
    eventCount: 2,
    results: const [OccurrenceResult.drugSeized],
    details: {'drug_seized': drugDetail},
    integrityHash: 'a1b2c3d4e5f67890abcdef1234567890',
  );
}

RecordDetail _createHistoryRecordDetail(dynamic drugDetail) {
  final occ = Occurrence(
    id: '',
    shiftId: 'shift-01',
    primaryHandlerId: 'handler-01',
    primaryHandlerRa: '12345',
    dogId: 'dog-01',
    typeCode: 'APOIO',
    typeName: 'Apoio Policial',
    locationAddress: 'Rua das Flores, 500 - Limeira/SP',
    gpsLat: -22.5645,
    gpsLng: -47.4017,
    status: OccurrenceStatus.finalized,
    results: const [OccurrenceResult.drugSeized],
    details: {'drug_seized': drugDetail},
    startedAt: DateTime(2026, 9, 1, 8, 0),
    finalizedAt: DateTime(2026, 9, 1, 10, 0),
    createdAt: DateTime(2026, 9, 1, 8, 0),
    updatedAt: DateTime(2026, 9, 1, 10, 0),
  );

  final source = HistoryEntry(
    id: occ.id,
    type: HistoryEntryType.occurrence,
    title: occ.typeName,
    subtitle: '',
    time: occ.startedAt,
    author: 'GCM Ragonha',
    tag: 'OCORRÊNCIA',
    icon: Icons.shield,
    color: Colors.blue,
    originalModel: occ,
    details: const {
      '_outcomes': ['drug_seized'],
      '_mediaAttachments': [],
    },
  );

  return RecordDetail(
    id: source.id,
    type: source.type,
    category: 'Ocorrência',
    title: source.title,
    subtitle: source.subtitle,
    location: occ.locationAddress ?? '',
    dateTime: source.time,
    author: source.author,
    dogName: 'Thor',
    handlerName: 'GCM Ragonha',
    status: 'Finalizado',
    syncStatus: 'Sincronizado',
    duration: 'Não informado',
    team: '',
    notes: '',
    icon: source.icon,
    color: source.color,
    internalEvents: const [],
    auditEvents: const [],
    source: source,
  );
}

void main() {
  group('FF-OCC-08B — OccurrencePdfGenerator.formatDrugDescription parity', () {
    test('single drug with weight_grams formats as "<type> - <weight> g"', () {
      final input = [
        {'type': 'Maconha', 'weight_grams': '125'},
      ];
      expect(
        OccurrencePdfGenerator.formatDrugDescription(input),
        equals('Maconha - 125 g'),
      );
    });

    test('multiple drugs format as semicolon-separated list with "g" unit', () {
      final input = [
        {'type': 'Maconha', 'weight_grams': '125'},
        {'type': 'Cocaína', 'weight_grams': '18'},
        {'type': 'Crack', 'weight_grams': '5'},
      ];
      expect(
        OccurrencePdfGenerator.formatDrugDescription(input),
        equals('Maconha - 125 g; Cocaína - 18 g; Crack - 5 g'),
      );
    });

    test('legacy quantidade formats without unit', () {
      final input = [
        {'type': 'Maconha', 'quantidade': '250'},
      ];
      expect(
        OccurrencePdfGenerator.formatDrugDescription(input),
        equals('Maconha - 250'),
      );
    });

    test('empty or missing amounts preserve drug type alone', () {
      final input = [
        {'type': 'LSD'},
        {'type': 'Ecstasy', 'weight_grams': ''},
      ];
      expect(
        OccurrencePdfGenerator.formatDrugDescription(input),
        equals('LSD; Ecstasy'),
      );
    });

    test('handles single map input as well as list input', () {
      final input = {'type': 'Maconha', 'weight_grams': '50'};
      expect(
        OccurrencePdfGenerator.formatDrugDescription(input),
        equals('Maconha - 50 g'),
      );
    });
  });

  group('FF-OCC-08B — OccurrenceConfirmationScreen drug wording parity', () {
    testWidgets(
      'renders exact multi-drug description instead of generic "X substâncias"',
      (tester) async {
        tester.view.physicalSize = const Size(1080, 2400);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        final drugs = [
          {'type': 'Maconha', 'weight_grams': '125'},
          {'type': 'Cocaína', 'weight_grams': '18'},
        ];
        final data = _createConfirmationData(drugs);

        await tester.pumpWidget(
          MaterialApp(home: OccurrenceConfirmationScreen(data: data)),
        );

        // Verify that the drug description is displayed and preserves both drugs with 'g'
        expect(
          find.textContaining('Maconha - 125 g; Cocaína - 18 g'),
          findsOneWidget,
        );
        // Ensure the old wording 'substâncias' is NOT displayed
        expect(find.textContaining('substâncias'), findsNothing);
      },
    );

    testWidgets('renders single drug as "Maconha - 125 g" matching PDF', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final drugs = [
        {'type': 'Maconha', 'weight_grams': '125'},
      ];
      final data = _createConfirmationData(drugs);

      await tester.pumpWidget(
        MaterialApp(home: OccurrenceConfirmationScreen(data: data)),
      );

      expect(find.textContaining('Maconha - 125 g'), findsOneWidget);
      // Ensure the old wording '125g de Maconha' is NOT displayed
      expect(find.text('125g de Maconha'), findsNothing);
    });
  });

  group('FF-OCC-08B — History Detail Screen drug wording parity', () {
    testWidgets('renders exact drug description in HistoryOccurrenceBody', (
      tester,
    ) async {
      final drugs = [
        {'type': 'Maconha', 'weight_grams': '125'},
        {'type': 'Cocaína', 'weight_grams': '18'},
      ];
      final detail = _createHistoryRecordDetail(drugs);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: HistoryOccurrenceBody(detail: detail),
            ),
          ),
        ),
      );

      expect(find.text('Maconha - 125 g; Cocaína - 18 g'), findsOneWidget);
    });
  });
}
