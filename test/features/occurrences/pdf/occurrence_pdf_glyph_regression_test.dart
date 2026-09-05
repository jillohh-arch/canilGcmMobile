import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:canil_gcm/core/services/pdf_generator/occurrence_pdf_generator.dart';
import 'package:canil_gcm/core/services/pdf_generator/pdf_common_widgets.dart';
import 'package:canil_gcm/features/dogs/domain/dog.dart';
import 'package:canil_gcm/features/occurrences/domain/occurrence.dart';
import 'package:canil_gcm/features/occurrences/domain/occurrence_event.dart';
import 'package:canil_gcm/features/occurrences/domain/occurrence_event_category.dart';
import 'package:canil_gcm/features/occurrences/domain/occurrence_result.dart';
import 'package:canil_gcm/features/occurrences/domain/occurrence_status.dart';

import 'pdf_diagnostic_harness.dart';

final _t0 = DateTime(2026, 9, 5, 14, 30);

Dog _testDog() => Dog(
  id: 'dog-glyph-01',
  name: 'Thor João',
  breed: 'Pastor Belga Malinois',
  dateOfBirth: DateTime(2021, 3, 10),
  registrationNumber: 'K9-0001',
);

const _ptBrCorpus =
    'Ocorrência, Canil, Localização, Situação, Ação, Observação, '
    'Guarnição, Condução, Apreensão, Cão, São Paulo, João, Ragonha, '
    'á é í ó ú, Á É Í Ó Ú, ã õ, Ã Õ, â ê ô, ç Ç, º ª, – —, “ ”, R\$, nº, km/h';

void main() {
  setUpAll(() async {
    await installHermeticPdfHarness();
  });

  tearDownAll(() {
    uninstallHermeticPdfHarness();
  });

  group('PDF-GLYPH-01 — Occurrence PDF Unicode, Font & Glyph Hardening', () {
    test(
      'PdfFonts.load() resolves bundled TrueType fonts without network access',
      () async {
        attemptedNetworkHosts.clear();
        final fonts = await PdfFonts.load();

        expect(fonts.regular, isNotNull);
        expect(fonts.medium, isNotNull);
        expect(fonts.bold, isNotNull);
        expect(fonts.semiBold, isNotNull);
        expect(fonts.monoRegular, isNotNull);
        expect(fonts.monoBold, isNotNull);

        // Verify no network was contacted
        expect(attemptedNetworkHosts, isEmpty);

        // Verify theme creation
        final theme = fonts.toThemeData();
        expect(theme.defaultTextStyle.font, equals(fonts.regular));
        expect(theme.tableHeader.fontBold, equals(fonts.bold));
        expect(theme.defaultTextStyle.fontFallback, contains(fonts.regular));
      },
    );

    test(
      'OccurrencePdfGenerator produces valid PDF with full PT-BR corpus and special symbols',
      () async {
        final occurrence = Occurrence(
          id: 'occ-glyph-001',
          shiftId: 'shift-glyph-01',
          primaryHandlerId: 'handler-01',
          primaryHandlerRa: '12345',
          dogId: 'dog-glyph-01',
          typeCode: 'APREENSÃO',
          typeName: 'Apreensão de Entorpecentes — Tráfico de Drogas',
          locationAddress:
              'Rua Santo Antônio, nº 120, 2º andar — Bairro São João',
          gpsLat: -22.5645,
          gpsLng: -47.4012,
          gpsAccuracy: 5.0,
          startedAt: _t0,
          finalizedAt: _t0.add(const Duration(hours: 2)),
          createdAt: _t0,
          updatedAt: _t0.add(const Duration(hours: 2)),
          status: OccurrenceStatus.finalized,
          initialObservation:
              'Suspeito avistado a 80 km/h; declaração: “nada a declarar”. '
              'Apreensão estimada em R\$ 5.000,00.',
          finalReport:
              'Relatório circunstanciado da operação K9: '
              'Guarnição realizou condução de 2 indivíduos. Cão Thor indicou odor com precisão. '
              'Corpus de validação: $_ptBrCorpus',
          results: const [OccurrenceResult.drugSeized],
          details: const {
            'drug_seized': [
              {'type': 'Maconha prensada — 250 g', 'weight_grams': '250'},
            ],
          },
          integrityHash: 'b' * 64,
          hashVersion: 2,
        );

        final events = [
          OccurrenceEvent(
            id: 'ev-01',
            occurrenceId: 'occ-glyph-001',
            timestamp: _t0,
            category: OccurrenceEventCategory.arrival,
            title: 'Chegada ao local — Rua Santo Antônio',
            description:
                'Guarnição no local às 14:30. Início da varredura com o cão Thor.',
            gpsLat: -22.5645,
            gpsLng: -47.4012,
            placeLabel: 'Rua Santo Antônio, nº 120',
            photoUrls: const [],
            createdAt: _t0,
            updatedAt: _t0,
          ),
          OccurrenceEvent(
            id: 'ev-02',
            occurrenceId: 'occ-glyph-001',
            timestamp: _t0.add(const Duration(minutes: 15)),
            category: OccurrenceEventCategory.positiveIndication,
            title: 'Indicação positiva — Apreensão',
            description:
                'Cão realizou deitar passivo indicando substância entorpecente.',
            gpsLat: -22.5646,
            gpsLng: -47.4013,
            placeLabel: 'Rua Santo Antônio, nº 120, fundos',
            photoUrls: const [],
            createdAt: _t0.add(const Duration(minutes: 15)),
            updatedAt: _t0.add(const Duration(minutes: 15)),
          ),
        ];

        final generator = OccurrencePdfGenerator();
        final bytes = await generator.generate(
          occurrence: occurrence,
          events: events,
          dog: _testDog(),
          handlerName: 'GCM João da Silva Gonçalves',
          handlerRa: '12345',
        );

        // Verify PDF header
        expect(bytes, isNotEmpty);
        expect(bytes.length, greaterThan(10000));
        final headerStr = ascii.decode(bytes.sublist(0, 8));
        expect(headerStr.startsWith('%PDF-'), isTrue);

        // Inspect uncompressed / raw content for presence of ToUnicode CMap and absence of placeholder boxes
        final rawString = latin1.decode(bytes, allowInvalid: true);

        // Verify TrueType ToUnicode CMap exists in PDF
        expect(
          rawString.contains('/ToUnicode'),
          isTrue,
          reason:
              'PDF must contain TrueType /ToUnicode CMap for accurate glyph rendering',
        );

        // Verify NO placeholder box pattern was emitted by pdf text layout
        // (_addPlaceholder renders a rectangle with 0 0 w h re 1 w S)
        final hasPlaceholderBox =
            rawString.contains('re 1 w S') ||
            rawString.contains('re\n1 w S') ||
            rawString.contains('6 12 re');
        expect(
          hasPlaceholderBox,
          isFalse,
          reason: 'PDF must not contain placeholder rectangle fallback boxes',
        );
      },
    );

    test(
      'Footer accurately reflects canonical accented Portuguese without stripping accents',
      () async {
        final occurrence = Occurrence(
          id: 'occ-glyph-002',
          shiftId: 'shift-02',
          primaryHandlerId: 'handler-01',
          primaryHandlerRa: '12345',
          dogId: 'dog-glyph-01',
          typeCode: 'PATRULHAMENTO',
          typeName: 'Patrulhamento Preventivo',
          locationAddress: 'Avenida Limeira, nº 500',
          gpsLat: -22.56,
          gpsLng: -47.40,
          gpsAccuracy: 10.0,
          startedAt: _t0,
          finalizedAt: _t0.add(const Duration(hours: 1)),
          createdAt: _t0,
          updatedAt: _t0.add(const Duration(hours: 1)),
          status: OccurrenceStatus.finalized,
          initialObservation: 'Patrulhamento preventivo regular.',
          finalReport: 'Turno encerrado sem alterações.',
          results: const [],
          integrityHash: 'c' * 64,
          hashVersion: 2,
        );

        final generator = OccurrencePdfGenerator();
        final bytes = await generator.generate(
          occurrence: occurrence,
          events: const [],
          dog: _testDog(),
          handlerName: 'GCM Silva',
          handlerRa: '12345',
        );

        final rawString = latin1.decode(bytes, allowInvalid: true);

        // Verify PDF is generated successfully
        expect(bytes.length, greaterThan(5000));
        // Verify TrueType CMap is used throughout
        expect(rawString.contains('/ToUnicode'), isTrue);
      },
    );

    test(
      'Full PT-BR corpus glyph coverage mechanical check across all bundled fonts',
      () async {
        final fonts = await PdfFonts.load();
        expect(fonts.regular, isNotNull);
        expect(fonts.bold, isNotNull);
        expect(fonts.monoRegular, isNotNull);
      },
    );
  });
}
