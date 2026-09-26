// F40-PDF-REGRESSION-01 — REGRESSION GUARD for real-world PDF pagination
//
// Defect (proven by physical device evidence in F40-HOMOLOGATION-CLOSEOUT-01):
//   OccurrencePdfGenerator.generate
//   -> pw.MultiPage
//   -> When generating an occurrence with realistic media (8+ photos)
//      or a realistic narrative report (voice transcription),
//      the layout engine threw:
//      Instance of 'TooManyPagesException'
//
// Root Cause:
//   1. In `_buildMediaPage`:
//      All event photos (and finalization photos) were placed in a monolithic
//      `pw.Wrap` inside `pw.Column`. When photo count exceeded 6 cards, the
//      Wrap's total height exceeded an A4 page height (~700 pt). Because
//      `pw.Column` cannot break inside a child, it could never fit the Wrap
//      into the page, creating an infinite pagination loop.
//   2. In `_buildReportPage`:
//      The entire report and results were placed side-by-side in a `pw.Row`.
//      In `package:pdf`, `pw.Row` has `canSpan => false`. When the narrative
//      report contained realistic text (e.g. voice transcription of 2,000+ chars),
//      the Row's height exceeded page height and could not span, looping 20 times
//      and throwing `TooManyPagesException`.
//
// Fix:
//   1. In `_buildMediaPage`, media cards are chunked into 2-per-row `pw.Row`s
//      directly inside the column flow (each ~198 pt tall), paginating naturally.
//   2. In `_buildReportPage`, results are presented in a compact 2-column grid,
//      and the narrative report is split into paginable paragraph blocks
//      (each <= 800 chars, ~60-90 pt tall), allowing seamless page breaks.

import 'package:flutter_test/flutter_test.dart';
import 'package:canil_gcm/core/services/pdf_generator/occurrence_pdf_generator.dart';
import 'package:canil_gcm/features/dogs/domain/dog.dart';
import 'package:canil_gcm/features/occurrences/domain/occurrence.dart';
import 'package:canil_gcm/features/occurrences/domain/occurrence_event.dart';
import 'package:canil_gcm/features/occurrences/domain/occurrence_event_category.dart';
import 'package:canil_gcm/features/occurrences/domain/occurrence_result.dart';
import 'package:canil_gcm/features/occurrences/domain/occurrence_status.dart';

import 'pdf_diagnostic_harness.dart';

final _t0 = DateTime(2026, 5, 20, 14, 30);

Dog _dog() => Dog(
  id: 'dog-pagination',
  name: 'Bolt',
  breed: 'Pastor Belga Malinois',
  dateOfBirth: DateTime(2021, 3, 10),
  registrationNumber: 'K9-0001',
);

OccurrenceEvent _event({
  required int i,
  OccurrenceEventCategory category = OccurrenceEventCategory.other,
  String? description,
  double? lat,
  double? lng,
  List<String> photoUrls = const [],
}) {
  final ts = _t0.add(Duration(minutes: 7 * i));
  return OccurrenceEvent(
    id: 'evt-$i',
    occurrenceId: 'occ-pagination',
    category: category,
    timestamp: ts,
    title: 'Ação operacional $i',
    description:
        description ?? 'Registro detalhado da ação número $i em campo.',
    photoUrls: photoUrls,
    gpsLat: lat,
    gpsLng: lng,
    placeLabel: lat == null ? null : 'Ponto operacional $i',
    createdAt: ts,
    updatedAt: ts,
  );
}

Occurrence _occurrence({
  String? finalReport,
  List<String> finalizationPhotos = const [],
  List<OccurrenceResult> results = const [],
  Map<String, dynamic>? details,
}) {
  return Occurrence(
    id: 'occ-pagination',
    shiftId: 'shift-pagination',
    primaryHandlerId: 'handler-pagination',
    primaryHandlerRa: '99999',
    dogId: 'dog-pagination',
    typeCode: 'APOIO',
    typeName: 'Apoio Policial com Emprego de K9',
    locationAddress: 'Rua das Flores, 500 - Limeira/SP',
    gpsLat: -22.5645,
    gpsLng: -47.4017,
    gpsAccuracy: 5.0,
    startedAt: _t0,
    finalizedAt: _t0.add(const Duration(hours: 2)),
    createdAt: _t0,
    updatedAt: _t0.add(const Duration(hours: 2)),
    status: OccurrenceStatus.finalized,
    finalReport: finalReport,
    finalizationPhotos: finalizationPhotos,
    results: results,
    details: details,
    integrityHash: 'f' * 64,
    hashVersion: 4,
  );
}

void main() {
  setUpAll(() async {
    await installHermeticPdfHarness();
  });
  tearDownAll(uninstallHermeticPdfHarness);

  group('F40-PDF-REGRESSION-01 — Real-world pagination guards', () {
    test(
      'PAG-1: 8+ event photos paginate cleanly without TooManyPagesException',
      () async {
        final occ = _occurrence();
        final events = [
          for (var i = 0; i < 10; i++)
            _event(i: i, photoUrls: const ['https://example.invalid/p.jpg']),
        ];
        final bytes = await OccurrencePdfGenerator().generate(
          occurrence: occ,
          events: events,
          dog: _dog(),
          handlerName: 'GCM 1CL Silva',
          handlerRa: '99999',
        );
        expect(bytes, isNotEmpty);
        expect(bytes.length, greaterThan(20000));
      },
    );

    test(
      'PAG-2: combined event photos + finalization photos paginate cleanly',
      () async {
        final occ = _occurrence(
          finalizationPhotos: const [
            'https://example.invalid/f1.jpg',
            'https://example.invalid/f2.jpg',
            'https://example.invalid/f3.jpg',
            'https://example.invalid/f4.jpg',
          ],
        );
        final events = [
          for (var i = 0; i < 8; i++)
            _event(i: i, photoUrls: const ['https://example.invalid/p.jpg']),
        ];
        final bytes = await OccurrencePdfGenerator().generate(
          occurrence: occ,
          events: events,
          dog: _dog(),
          handlerName: 'GCM 1CL Silva',
          handlerRa: '99999',
        );
        expect(bytes, isNotEmpty);
        expect(bytes.length, greaterThan(20000));
      },
    );

    test('PAG-3: extensive voice-transcribed final report paginates across pages', () async {
      final occ = _occurrence(
        finalReport:
            'Durante patrulhamento tático preventivo realizado pelo bairro Jardim Nova Itália, '
            'a equipe da viatura K9 visualizou dois indivíduos em atitude suspeita nas proximidades '
            'de uma área de mata conhecida pelo tráfico de entorpecentes.\n\n'
            'Ao perceberem a aproximação da equipe policial, os indivíduos empreenderam fuga '
            'a pé para o interior da vegetação fechada. Foi estabelecido o cerco perimetral e '
            'iniciadas as buscas com o emprego do cão de faro e captura Bolt.\n\n'
            'O animal executou a técnica de varredura sistemática e em menos de 10 minutos '
            'indicou ativamente a presença de um indivíduo homiziado sob uma moita de bambu, '
            'onde foi realizada a abordagem de segurança sem necessidade de uso de força letal.\n\n'
            'Em continuidade à busca no trajeto percorrido durante a fuga, o cão K9 Bolt '
            'realizou indicação passiva em uma sacola plástica camuflada sob folhagens secas, '
            'contendo 120 porções de substância análoga à cocaína e 85 invólucros de maconha, '
            'além de dinheiro em notas trocadas e uma balança digital de precisão.\n\n'
            'Diante dos fatos, foi dada voz de prisão em flagrante delito ao suspeito e '
            'realizada a condução de todos os materiais e partes até o Plantão Policial '
            'para apresentação à autoridade competente, que ratificou a medida e determinou '
            'a lavratura do Boletim de Ocorrência correspondente.',
        results: const [
          OccurrenceResult.drugSeized,
          OccurrenceResult.weaponSeized,
          OccurrenceResult.personDetained,
          OccurrenceResult.boCreated,
        ],
        details: const {
          'drug_seized': [
            {'type': 'Cocaína', 'weight_grams': '150'},
            {'type': 'Maconha', 'weight_grams': '180'},
          ],
          'person_detained': {'count': '1', 'referral': 'Plantão Central'},
          'bo_created': {'bo_number': '2026/05/9876', 'bo_type': 'Flagrante'},
        },
      );
      final events = [for (var i = 0; i < 6; i++) _event(i: i)];
      final bytes = await OccurrencePdfGenerator().generate(
        occurrence: occ,
        events: events,
        dog: _dog(),
        handlerName: 'GCM 1CL Silva',
        handlerRa: '99999',
      );
      expect(bytes, isNotEmpty);
      expect(bytes.length, greaterThan(25000));
    });

    test(
      'PAG-4: representative complete physical occurrence scenario passes cleanly',
      () async {
        final occ = _occurrence(
          finalReport:
              'Relato operacional representativo de homologação de campo. ' *
              30,
          finalizationPhotos: const [
            'https://example.invalid/fin1.jpg',
            'https://example.invalid/fin2.jpg',
          ],
          results: const [
            OccurrenceResult.drugSeized,
            OccurrenceResult.personDetained,
            OccurrenceResult.boCreated,
          ],
          details: const {
            'bo_created': {'bo_number': '2026/004567'},
          },
        );
        final events = [
          for (var i = 0; i < 12; i++)
            _event(
              i: i,
              category: OccurrenceEventCategory
                  .values[i % OccurrenceEventCategory.values.length],
              description: 'Ação registrada durante patrulhamento $i',
              lat: -22.5645 - i * 0.001,
              lng: -47.4017 - i * 0.001,
              photoUrls: i % 2 == 0
                  ? const ['https://example.invalid/foto.jpg']
                  : const [],
            ),
        ];
        final bytes = await OccurrencePdfGenerator().generate(
          occurrence: occ,
          events: events,
          dog: _dog(),
          handlerName: 'GCM 1CL Silva',
          handlerRa: '99999',
        );
        expect(bytes, isNotEmpty);
        expect(bytes.length, greaterThan(30000));
      },
    );
  });
}
