// FF-OCC-01.T1-A — REGRESSION GUARD for the flex-width defect fixed in I1-A.
//
// Defect (proven in D1-E1, fixed in I1-A):
//   OccurrencePdfGenerator.generate
//   -> pw.MultiPage
//   -> _buildDisplacementSection            (outer pw.Row)
//   -> _sectionLabel(...)                   (inner pw.Row, was a NON-FLEX child)
//   -> pw.Expanded                          (inside _sectionLabel)
//   -> package pdf Flex.layout (flex.dart:243)
//   -> Exception: "Flex children have non-zero flex but incoming width
//                  constraints are unbounded."
//
// Root cause: pdf's Flex measures a NON-FLEX child of a horizontal Row with
// BoxConstraints(maxHeight: ...) only (flex.dart:268-273) — maxWidth stays
// infinity. Anything containing an Expanded therefore cannot be a plain
// (non-flex) child of a Row.
//
// This file proves TWO things at once, which a single green test cannot:
//
//   NEGATIVE CONTROL  — the OLD widget shape still makes the real pdf engine
//                       throw. So the guard is wired to something real and is
//                       not passing by accident.
//   PRODUCT REGRESSION— the CURRENT generator, exercised with displacement data
//                       (locations non-empty, so _buildDisplacementSection is
//                       really built), no longer produces that exception.
//
// Scope notes:
//   * A second, independent defect is still open and deliberately NOT fixed:
//     _timelineEvent uses a non-uniform pw.Border together with borderRadius,
//     tripping `assert(borderRadius == null)` at pdf box_border.dart:266 during
//     the PAINT phase. Reaching it is the EXPECTED outcome here: it proves the
//     run got past layout/pagination. Tracked for FF-OCC-01.I1-B.
//   * The field report said "height"; the reproduced/fixed defect is "width".
//     That relationship is still UNKNOWN and is not asserted either way.
//   * No visual golden: this section aborted whenever it had GPS data, so no
//     trustworthy pre-fix visual baseline exists.
//   * Hermetic: no live Firebase, no Firestore/Storage/Auth I/O, no network.

import 'package:flutter_test/flutter_test.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import 'package:canil_gcm/core/services/occurrence_location_service.dart';
import 'package:canil_gcm/core/services/pdf_generator/occurrence_pdf_generator.dart';
import 'package:canil_gcm/features/dogs/domain/dog.dart';
import 'package:canil_gcm/features/occurrences/domain/occurrence.dart';
import 'package:canil_gcm/features/occurrences/domain/occurrence_event.dart';
import 'package:canil_gcm/features/occurrences/domain/occurrence_event_category.dart';
import 'package:canil_gcm/features/occurrences/domain/occurrence_result.dart';
import 'package:canil_gcm/features/occurrences/domain/occurrence_status.dart';

import 'pdf_diagnostic_harness.dart';

/// The exact message this gate guards against. Distinct from the height variant.
const _flexWidthMessage =
    'Flex children have non-zero flex but incoming width constraints are unbounded';

/// The known, still-open second defect. Reaching it means layout succeeded.
const _knownBorderDefect = 'A borderRadius can only be given for a uniform Border';

final _t0 = DateTime(2026, 5, 20, 14, 30);

Dog _dog() => Dog(
  id: 'dog-t1a',
  name: 'Sintetico',
  breed: 'Pastor Belga Malinois',
  dateOfBirth: DateTime(2021, 3, 10),
  registrationNumber: 'K9-0001',
);

OccurrenceEvent _geoEvent({
  required int i,
  required double lat,
  required double lng,
  OccurrenceEventCategory category = OccurrenceEventCategory.other,
  String? description,
  List<String> photoUrls = const [],
}) {
  final ts = _t0.add(Duration(minutes: 7 * i));
  return OccurrenceEvent(
    id: 'evt-$i',
    occurrenceId: 'occ-t1a',
    category: category,
    timestamp: ts,
    title: 'Evento sintetico $i',
    description: description,
    photoUrls: photoUrls,
    gpsLat: lat,
    gpsLng: lng,
    placeLabel: 'Ponto sintetico $i',
    createdAt: ts,
    updatedAt: ts,
  );
}

Occurrence _occurrence({
  String? finalReport,
  List<OccurrenceResult> results = const [],
  OccurrenceStatus status = OccurrenceStatus.finalized,
  Map<String, dynamic>? details,
}) {
  return Occurrence(
    id: 'occ-t1a',
    shiftId: 'shift-t1a',
    primaryHandlerId: 'handler-t1a',
    primaryHandlerRa: '99999',
    dogId: 'dog-t1a',
    typeCode: 'BUSCA',
    typeName: 'Busca com K9',
    locationAddress: 'Rua Sintetica, 100 - Limeira/SP',
    gpsLat: -22.5645,
    gpsLng: -47.4017,
    gpsAccuracy: 8.0,
    startedAt: _t0,
    finalizedAt: _t0.add(const Duration(hours: 2)),
    createdAt: _t0,
    updatedAt: _t0.add(const Duration(hours: 2)),
    status: status,
    finalReport: finalReport,
    results: results,
    details: details,
    integrityHash: 'a' * 64,
    hashVersion: 2,
  );
}

/// Events equivalent to D1-E1 "CASE B — displacement".
List<OccurrenceEvent> _displacementEvents() => [
  _geoEvent(i: 0, category: OccurrenceEventCategory.opening, lat: -22.5645, lng: -47.4017),
  _geoEvent(i: 1, category: OccurrenceEventCategory.arrival, lat: -22.5700, lng: -47.4100),
  _geoEvent(i: 2, category: OccurrenceEventCategory.closure, lat: -22.5800, lng: -47.4200),
];

/// Events equivalent to D1-E1 "CASE G — realistic".
List<OccurrenceEvent> _realisticEvents() => [
  for (var i = 0; i < 30; i++)
    _geoEvent(
      i: i,
      category:
          OccurrenceEventCategory.values[i % OccurrenceEventCategory.values.length],
      description: 'Descricao sintetica do evento $i. ' * 4,
      lat: -22.5645 - i * 0.001,
      lng: -47.4017 - i * 0.001,
      photoUrls: i % 5 == 0 ? const ['https://example.invalid/p.jpg'] : const [],
    ),
];

/// Replica of the label widget: a Row whose last child is an Expanded rule.
/// Mirrors _sectionLabel (occurrence_pdf_generator.dart:615-631) WITHOUT
/// importing it, so the negative control cannot be silently neutralised by a
/// future refactor of the real helper.
pw.Widget _sectionLabelLike() {
  return pw.Row(
    children: [
      pw.Text('MAPA DE DESLOCAMENTO'),
      pw.SizedBox(width: 8),
      pw.Expanded(child: pw.Container(height: 0.8, color: PdfColors.grey)),
    ],
  );
}

/// Lays out a MultiPage. In pdf 3.12.0 MultiPage lays out during addPage, so the
/// throw surfaces synchronously here rather than at save().
void _layoutMultiPage(List<pw.Widget> children) {
  final doc = pw.Document();
  doc.addPage(
    pw.MultiPage(pageFormat: PdfPageFormat.a4, build: (_) => children),
  );
}

Future<void> _saveMultiPage(List<pw.Widget> children) async {
  final doc = pw.Document();
  doc.addPage(
    pw.MultiPage(pageFormat: PdfPageFormat.a4, build: (_) => children),
  );
  await doc.save();
}

void main() {
  // -------------------------------------------------------------------------
  // 1. NEGATIVE CONTROL — the old shape must still fail.
  //
  // If these ever go green without the guard below also changing, the pdf engine
  // changed its contract and this whole guard must be re-derived.
  // -------------------------------------------------------------------------
  group('T1-A negative control — old layout shape still throws flex-width', () {
    test('NEG-1: label-like Row as NON-FLEX child of a Row throws flex-width', () {
      expect(
        () => _layoutMultiPage([
          pw.Row(
            children: [
              _sectionLabelLike(), // non-flex child => maxWidth == infinity
              pw.Spacer(),
              pw.Text('3 locais'),
            ],
          ),
        ]),
        throwsA(
          isA<Exception>().having(
            (e) => e.toString(),
            'message',
            contains(_flexWidthMessage),
          ),
        ),
        reason:
            'The pre-I1-A shape must still be rejected by the real pdf engine; '
            'otherwise this regression guard proves nothing.',
      );
    });

    test('NEG-2: same label-like Row wrapped in Expanded is SAFE (the fix shape)',
        () async {
      // This is exactly the shape I1-A applied at occurrence_pdf_generator.dart:1371.
      await _saveMultiPage([
        pw.Row(
          children: [
            pw.Expanded(child: _sectionLabelLike()),
            pw.Text('3 locais'),
          ],
        ),
      ]);
      // Reaching here without throwing is the assertion.
    });
  });

  // -------------------------------------------------------------------------
  // 2. PRODUCT REGRESSION — real generator, real layout, displacement present.
  // -------------------------------------------------------------------------
  group('T1-A product regression — displacement path is free of flex-width', () {
    setUpAll(installHermeticPdfHarness);
    tearDownAll(uninstallHermeticPdfHarness);

    /// Runs the REAL generator and returns a classified outcome.
    Future<PdfAttemptResult> run(
      Occurrence occ,
      List<OccurrenceEvent> events,
    ) async {
      try {
        final bytes = await OccurrencePdfGenerator().generate(
          occurrence: occ,
          events: events,
          dog: _dog(),
          handlerName: 'Condutor Sintetico',
          handlerRa: '99999',
        );
        return PdfAttemptResult(
          outcome: PdfAttemptOutcome.generatedAndSaved,
          detail: 'save() produced bytes',
          byteLength: bytes.lengthInBytes,
        );
      } catch (e, st) {
        return classifyError(e, st);
      }
    }

    /// The permanent guard. Fails loudly on the fixed defect; tolerates only the
    /// one known, tracked second defect.
    void assertNoFlexWidthRegression(String label, PdfAttemptResult r) {
      expect(
        r.reachedLayout,
        isTrue,
        reason:
            '$label never reached the pdf layout engine (${r.detail}). The harness '
            'is broken, so this run says nothing about the product.\n${r.stack}',
      );

      expect(
        r.detail,
        isNot(contains(_flexWidthMessage)),
        reason:
            'FF-OCC-01 REGRESSION: the flex-width defect fixed in I1-A is back in '
            '$label. Something re-introduced a widget containing pw.Expanded as a '
            'NON-FLEX child of a pw.Row (see _buildDisplacementSection / '
            '_sectionLabel).\n${r.stack}',
      );

      // Anything other than "clean" or the single known defect must be surfaced
      // rather than silently tolerated.
      if (r.outcome != PdfAttemptOutcome.generatedAndSaved) {
        expect(
          r.detail,
          contains(_knownBorderDefect),
          reason:
              '$label failed past layout with an UNTRACKED error. Expected either a '
              'clean save or the known borderRadius defect (FF-OCC-01.I1-B).\n'
              '${r.stack}',
        );
      }
    }

    test('fixture actually builds the displacement section (guard precondition)',
        () {
      // _buildDisplacementSection early-returns on locations.isEmpty, so the
      // regression below would be vacuous if clustering yielded nothing.
      final locations =
          OccurrenceLocationService.clusterEventsSync(_displacementEvents());
      expect(
        locations,
        isNotEmpty,
        reason:
            'Without clustered locations the generator skips the very section this '
            'gate protects, making the regression test meaningless.',
      );
    });

    test('CASE B — displacement: no flex-width exception', () async {
      final r = await run(_occurrence(), _displacementEvents());
      // ignore: avoid_print
      print('T1-A CASE B -> $r');
      assertNoFlexWidthRegression('CASE B-displacement', r);
    });

    test('CASE G — realistic: no flex-width exception', () async {
      final r = await run(
        _occurrence(
          finalReport: 'Relato sintetico. ' * 120,
          results: const [
            OccurrenceResult.boCreated,
            OccurrenceResult.personDetained,
          ],
          status: OccurrenceStatus.finalizedWithPending,
          details: const {
            'bo_created': {'bo_number': '2026/000123'},
          },
        ),
        _realisticEvents(),
      );
      // ignore: avoid_print
      print('T1-A CASE G -> $r');
      assertNoFlexWidthRegression('CASE G-realistic', r);
    });

    test('hermeticity: every outbound attempt was blocked, hosts are known', () {
      // Hermeticity here is STRUCTURAL: the harness installs an HttpOverrides whose
      // client throws SocketException for every host, so nothing can reach the
      // network regardless of what the generator asks for. What we assert is that
      // the set of hosts it TRIES is the known, benign set — a new host appearing
      // means the generator grew an undocumented outbound dependency.
      //
      // Measured hosts and why each is tolerated:
      //   fonts.gstatic.com     -> PdfGoogleFonts; printing falls back to Helvetica.
      //   a.basemaps.cartocdn.com -> OsmStaticMapGenerator tiles; the productive code
      //                              catches the failure and returns null (no map).
      //   example.invalid       -> OUR OWN fixture's placeholder photo URL. The
      //                            .invalid TLD is reserved by RFC 2606 and can never
      //                            resolve, so it is inert by construction.
      const knownHosts = {
        'fonts.gstatic.com',
        'a.basemaps.cartocdn.com',
        'example.invalid',
      };

      expect(
        attemptedNetworkHosts.toSet().difference(knownHosts),
        isEmpty,
        reason:
            'The generator attempted an UNKNOWN outbound host. Every attempt is '
            'blocked, so this is not a leak, but it is an undocumented dependency '
            'that must be reviewed: ${attemptedNetworkHosts.toSet()}',
      );
    });
  });
}
