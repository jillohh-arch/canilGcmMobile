// FF-OCC-01.T1-B — REGRESSION GUARD for the partial-Border + borderRadius defect
// fixed in I1-B, plus consolidated full-generator validation of I1-A + I1-B.
//
// Defect (proven in I1-B):
//   OccurrencePdfGenerator.generate
//   -> pw.MultiPage
//   -> _buildTimelinePage                    (entries non-empty branch)
//   -> _timelineEvent                        (occurrence_pdf_generator.dart:1859)
//   -> pw.Container(decoration: pw.BoxDecoration(border: <NON-UNIFORM>,
//                                               borderRadius: <non-null>))
//   -> package pdf decoration.dart:411-419   (PaintPhase.foreground)
//   -> package pdf box_border.dart:265
//   -> AssertionError: "A borderRadius can only be given for a uniform Border."
//
// Package mechanism, read from pdf-3.12.0 source and recorded as FACT:
//   * Border.isUniform            (box_border.dart:227)
//         top == bottom && bottom == left && left == right
//   * Border.paint                (box_border.dart:230)
//         if isUniform  -> a rectangular box MAY carry a borderRadius, painted by
//                          _paintUniformBorderWithRadius (lines 249-258).
//         if NOT uniform-> execution falls through to line 265:
//                          assert(borderRadius == null, ...)
//   * BoxDecoration.paint         (decoration.dart:411-419)
//         forwards `resolvedBorderRadius` to border.paint during
//         PaintPhase.foreground. So this defect fires in the PAINT phase, AFTER
//         layout and pagination have already succeeded. That is precisely why
//         every pre-I1-B fixture reported reachedLayout == true and still
//         produced no bytes.
//
// Classification (audited in I1-B, not re-litigated here):
//   BUG — SAME DEFECT CLASS AS HISTORICAL FIX (713eee8), not a proven regression.
//   713eee8 removed the same invalid pairing from two OTHER containers; the
//   _timelineEvent container was authored later (426ff097) already carrying it.
//
// What this file proves, which a single green run cannot:
//   NEGATIVE CONTROL  — the OLD decoration shape STILL trips box_border.dart:265
//                       in the real pdf engine, so the guard is wired to a real
//                       precondition and is not green by accident.
//   CORRECTED CONTROL — the same partial border WITHOUT borderRadius paints and
//                       saves, so the I1-B fix shape is genuinely valid.
//   PRODUCT REGRESSION— the CURRENT generator, driven by a timeline-bearing
//                       fixture, actually reaches _timelineEvent's paint and
//                       completes pdf.save() with real bytes.
//   NON-VACUITY       — the fixture provably cannot skip the _timelineEvent
//                       subtree, and byte growth confirms timeline content was
//                       really emitted.
//
// Scope notes:
//   * NO productive source is modified by this file. occurrence_pdf_generator.dart
//     is READ-ONLY for this gate.
//   * I1-A (flex-width) already has its own dedicated guard in
//     occurrence_pdf_flex_width_regression_test.dart. This file does not duplicate
//     that file's negative controls; it only keeps the combined matrix honest by
//     refusing to tolerate a flex-width signature anywhere.
//   * CASE E stays a DIAGNOSTIC FIXTURE ARTIFACT: its TooManyPagesException comes
//     from the deliberately oversized synthetic report string in the fixture, not
//     from the product. maxPages and productive pagination are untouched.
//   * The field report said "height"; the reproduced/fixed flex defect was
//     "width". That relationship remains UNKNOWN and is not asserted either way.
//   * Hermetic: no live Firebase, no Firestore/Storage/Auth I/O, no network.

import 'package:flutter_test/flutter_test.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import 'package:canil_gcm/core/services/pdf_generator/occurrence_pdf_generator.dart';
import 'package:canil_gcm/features/dogs/domain/dog.dart';
import 'package:canil_gcm/features/occurrences/domain/occurrence.dart';
import 'package:canil_gcm/features/occurrences/domain/occurrence_event.dart';
import 'package:canil_gcm/features/occurrences/domain/occurrence_event_category.dart';
import 'package:canil_gcm/features/occurrences/domain/occurrence_result.dart';
import 'package:canil_gcm/features/occurrences/domain/occurrence_status.dart';

import 'pdf_diagnostic_harness.dart';

/// The exact assertion message this gate guards against (pdf box_border.dart:265).
const _borderRadiusMessage =
    'A borderRadius can only be given for a uniform Border';

/// The OTHER, already-fixed defect. Must never reappear in any case either.
const _flexWidthMessage =
    'Flex children have non-zero flex but incoming width constraints are unbounded';

/// The one tolerated fixture-side outcome, and only for CASE E.
const _fixtureArtifact = 'TooManyPagesException';

final _t0 = DateTime(2026, 5, 20, 14, 30);

Dog _dog() => Dog(
  id: 'dog-t1b',
  name: 'Sintetico',
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
    occurrenceId: 'occ-t1b',
    category: category,
    timestamp: ts,
    title: 'Evento sintetico $i',
    description: description,
    photoUrls: photoUrls,
    gpsLat: lat,
    gpsLng: lng,
    placeLabel: lat == null ? null : 'Ponto sintetico $i',
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
    id: 'occ-t1b',
    shiftId: 'shift-t1b',
    primaryHandlerId: 'handler-t1b',
    primaryHandlerRa: '99999',
    dogId: 'dog-t1b',
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

/// The two events of the minimal baseline (CASE A shape).
List<OccurrenceEvent> _minimalEvents() => [
  _event(i: 0, category: OccurrenceEventCategory.opening),
  _event(i: 1, category: OccurrenceEventCategory.closure),
];

/// 50 timeline events, no GPS — the CASE C shape and the principal product guard
/// for the I1-B defect.
List<OccurrenceEvent> _timelineEvents() => [
  for (var i = 0; i < 50; i++)
    _event(
      i: i,
      category:
          OccurrenceEventCategory.values[i % OccurrenceEventCategory.values.length],
      description: 'Descricao sintetica do evento $i. ' * 3,
    ),
];

/// Replica of the DEFECTIVE _timelineEvent decoration (pre-I1-B), mirroring
/// occurrence_pdf_generator.dart:1914-1922 as it stood before the fix. Rebuilt
/// locally rather than imported so that a future refactor of the real helper
/// cannot silently neutralise this control.
pw.Widget _timelineCardLike({required bool withBorderRadius}) {
  return pw.Container(
    margin: const pw.EdgeInsets.only(bottom: 12),
    padding: const pw.EdgeInsets.all(11),
    decoration: pw.BoxDecoration(
      // NON-UNIFORM by construction: `left` differs from the other three sides
      // in both colour and width, so Border.isUniform is false.
      border: pw.Border(
        left: pw.BorderSide(color: PdfColors.cyan, width: 2.5),
        top: pw.BorderSide(color: PdfColors.grey300),
        right: pw.BorderSide(color: PdfColors.grey300),
        bottom: pw.BorderSide(color: PdfColors.grey300),
      ),
      borderRadius: withBorderRadius
          ? const pw.BorderRadius.all(pw.Radius.circular(8))
          : null,
    ),
    child: pw.Text('Evento sintetico'),
  );
}

/// pw.Page defers layout AND paint to save(), so a paint-phase assert surfaces
/// when the returned future completes — not at addPage time.
Future<void> _savePage(pw.Widget child) async {
  final doc = pw.Document();
  doc.addPage(pw.Page(pageFormat: PdfPageFormat.a4, build: (_) => child));
  await doc.save();
}

void main() {
  // -------------------------------------------------------------------------
  // 1. NEGATIVE CONTROL — the old decoration shape must STILL fail.
  //
  // If this ever goes green without the product guard below also changing, the
  // pdf package relaxed its contract and this whole guard must be re-derived.
  // -------------------------------------------------------------------------
  group('T1-B negative control — non-uniform Border + borderRadius still throws', () {
    test('NEG-B1: partial Border WITH borderRadius trips box_border.dart assert',
        () async {
      await expectLater(
        _savePage(_timelineCardLike(withBorderRadius: true)),
        throwsA(
          isA<AssertionError>().having(
            (e) => e.toString(),
            'message',
            contains(_borderRadiusMessage),
          ),
        ),
        reason:
            'The pre-I1-B decoration shape must still be rejected by the real pdf '
            'engine; otherwise this regression guard proves nothing.',
      );
    });

    test('NEG-B2: the assert fires in the PAINT phase, not during layout', () async {
      // Documents the mechanism as behaviour rather than as a comment: addPage
      // (which is where MultiPage layout would explode) completes cleanly, and the
      // failure only appears once save() drives the paint phase. This is why the
      // pre-I1-B matrix reported reachedLayout == true for every case.
      final doc = pw.Document();
      doc.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a4,
          build: (_) => _timelineCardLike(withBorderRadius: true),
        ),
      );
      // addPage did NOT throw — reaching this line is the first assertion.
      await expectLater(
        doc.save(),
        throwsA(
          isA<AssertionError>().having(
            (e) => e.toString(),
            'message',
            contains(_borderRadiusMessage),
          ),
        ),
        reason:
            'The defect must surface from save() (paint), confirming layout and '
            'pagination were never the failing stage.',
      );
    });
  });

  // -------------------------------------------------------------------------
  // 2. CORRECTED CONTROL — the I1-B fix shape must be valid.
  // -------------------------------------------------------------------------
  group('T1-B corrected control — partial Border without borderRadius is valid', () {
    test('POS-B1: same partial Border, no borderRadius, paints and saves', () async {
      // This is exactly the shape I1-B left at occurrence_pdf_generator.dart:1914.
      // The partial border (coloured left tab + thin line on the other sides) is
      // preserved; only the incompatible radius is gone.
      await _savePage(_timelineCardLike(withBorderRadius: false));
      // Completing without throwing is the assertion.
    });

    test('POS-B2: a UNIFORM Border may still carry a borderRadius', () async {
      // Proves the fix was the minimum necessary: the package forbids the radius
      // only for non-uniform borders (box_border.dart:236-262), so nothing here
      // required abandoning rounded corners project-wide.
      await _savePage(
        pw.Container(
          padding: const pw.EdgeInsets.all(11),
          decoration: pw.BoxDecoration(
            border: pw.Border.all(color: PdfColors.grey300),
            borderRadius: const pw.BorderRadius.all(pw.Radius.circular(8)),
          ),
          child: pw.Text('uniforme'),
        ),
      );
    });
  });

  // -------------------------------------------------------------------------
  // 3. PRODUCT REGRESSION + CONSOLIDATED FULL MATRIX (real generator).
  // -------------------------------------------------------------------------
  group('T1-B product validation — real generator, real paint, real bytes', () {
    final matrix = <String, PdfAttemptResult>{};

    setUpAll(installHermeticPdfHarness);
    tearDownAll(() {
      uninstallHermeticPdfHarness();
      // ignore: avoid_print
      print('\n===== FF-OCC-01.T1-B CONSOLIDATED MATRIX (real generator) =====');
      matrix.forEach((k, v) {
        // ignore: avoid_print
        print('CASE $k -> $v');
      });
    });

    Future<PdfAttemptResult> run(
      String label,
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
        final r = PdfAttemptResult(
          outcome: PdfAttemptOutcome.generatedAndSaved,
          detail: 'save() produced bytes',
          byteLength: bytes.lengthInBytes,
        );
        matrix[label] = r;
        return r;
      } catch (e, st) {
        final r = classifyError(e, st);
        matrix[label] = r;
        return r;
      }
    }

    /// The permanent consolidated guard.
    ///
    /// Fails loudly on EITHER fixed defect, and refuses to silently tolerate any
    /// untracked failure. `allowFixtureArtifact` is granted to CASE E only.
    void assertGenerated(
      String label,
      PdfAttemptResult r, {
      bool allowFixtureArtifact = false,
    }) {
      expect(
        r.reachedLayout,
        isTrue,
        reason:
            '$label never reached the pdf layout engine (${r.detail}). The harness '
            'is broken, so this run says nothing about the product.\n${r.stack}',
      );

      expect(
        r.detail,
        isNot(contains(_borderRadiusMessage)),
        reason:
            'FF-OCC-01 REGRESSION (I1-B): the partial-Border + borderRadius defect '
            'is back in $label. Something re-introduced a non-uniform pw.Border '
            'paired with a borderRadius (see _timelineEvent, '
            'occurrence_pdf_generator.dart:1914). pdf box_border.dart:265 forbids '
            'that pairing.\n${r.stack}',
      );

      expect(
        r.detail,
        isNot(contains(_flexWidthMessage)),
        reason:
            'FF-OCC-01 REGRESSION (I1-A): the flex-width defect is back in $label. '
            'Something re-introduced a widget containing pw.Expanded as a NON-FLEX '
            'child of a pw.Row.\n${r.stack}',
      );

      if (allowFixtureArtifact) {
        // CASE E only: the oversized synthetic report legitimately overflows
        // MultiPage. Anything OTHER than that artifact is still a real finding.
        if (r.outcome != PdfAttemptOutcome.generatedAndSaved) {
          expect(
            r.detail,
            contains(_fixtureArtifact),
            reason:
                '$label failed with something other than the known oversized-fixture '
                'artifact. That is a product finding, not a fixture problem.\n'
                '${r.stack}',
          );
        }
        return;
      }

      expect(
        r.outcome,
        PdfAttemptOutcome.generatedAndSaved,
        reason:
            '$label did not produce a complete PDF (${r.detail}). Classify as NEW '
            'REGRESSION or NEWLY EXPOSED DEFECT and return to Control Tower — do '
            'not patch from inside this gate.\n${r.stack}',
      );
      expect(
        r.byteLength,
        greaterThan(0),
        reason: '$label reported success but produced zero bytes.',
      );
    }

    // -----------------------------------------------------------------------
    // 3a. NON-VACUITY PRECONDITIONS for the _timelineEvent subtree.
    // -----------------------------------------------------------------------
    test('PRE-1: timeline fixture cannot skip the _timelineEvent subtree', () {
      // FACT from source: _buildTimelinePage (occurrence_pdf_generator.dart:1828)
      // branches `if (entries.isEmpty) _emptyBox(...) else ...map(_timelineEvent)`.
      // So a non-empty event list is necessary AND sufficient to build every
      // _timelineEvent card. Without this check the CASE C guard below could pass
      // while never touching the defective decoration at all.
      final events = _timelineEvents();
      expect(
        events,
        isNotEmpty,
        reason:
            'With an empty event list the generator renders _emptyBox instead of '
            '_timelineEvent, making the I1-B product guard vacuous.',
      );
      expect(
        events.length,
        greaterThan(1),
        reason:
            'More than one event is required so both the `first` and `last` '
            'branches of _timelineEvent are exercised (the `last` branch draws the '
            'connector rail).',
      );
    });

    test('CASE C — timeline heavy: reaches paint and produces a complete PDF',
        () async {
      // PRINCIPAL PRODUCT GUARD for the I1-B defect. 50 events => 50
      // _timelineEvent cards => 50 non-uniform-border Containers painted. Before
      // I1-B this aborted at box_border.dart:265 with zero bytes.
      final r = await run('C-timeline', _occurrence(), _timelineEvents());
      // ignore: avoid_print
      print('T1-B CASE C -> $r');
      assertGenerated('CASE C-timeline', r);
    });

    test('PRE-2: timeline content really reached the document (byte growth)',
        () async {
      // Second non-vacuity proof, independent of the source reading in PRE-1:
      // the 50-event document must be materially larger than the 2-event one. If
      // the timeline subtree were being skipped, the two would be ~equal.
      final minimal = await run('A-minimal', _occurrence(), _minimalEvents());
      assertGenerated('CASE A-minimal', minimal);

      final heavy = matrix['C-timeline'];
      expect(
        heavy,
        isNotNull,
        reason: 'CASE C must run before this comparison.',
      );
      expect(
        heavy!.byteLength,
        greaterThan(minimal.byteLength),
        reason:
            'A 50-event timeline produced no more bytes than a 2-event one '
            '(${heavy.byteLength} vs ${minimal.byteLength}). The _timelineEvent '
            'subtree is probably not being emitted, which would make this guard '
            'vacuous.',
      );
    });

    // -----------------------------------------------------------------------
    // 3b. FULL MATRIX — A/B/C/D/F/G must save; E is the fixture artifact.
    // CASE A and CASE C are already asserted above and are not re-run.
    // -----------------------------------------------------------------------
    test('CASE B — displacement: complete PDF (also protects I1-A)', () async {
      final r = await run('B-displacement', _occurrence(), [
        _event(i: 0, category: OccurrenceEventCategory.opening, lat: -22.5645, lng: -47.4017),
        _event(i: 1, category: OccurrenceEventCategory.arrival, lat: -22.5700, lng: -47.4100),
        _event(i: 2, category: OccurrenceEventCategory.closure, lat: -22.5800, lng: -47.4200),
      ]);
      assertGenerated('CASE B-displacement', r);
    });

    test('CASE D — media: complete PDF', () async {
      final r = await run('D-media', _occurrence(), [
        for (var i = 0; i < 6; i++)
          _event(i: i, photoUrls: const ['https://example.invalid/p.jpg']),
      ]);
      assertGenerated('CASE D-media', r);
    });

    test('CASE E — oversized synthetic report: FIXTURE ARTIFACT only', () async {
      // Deliberately unchanged from the D1-E1 fixture: same oversized report
      // string, same productive maxPages. The only tolerated non-success in the
      // whole matrix, and even here anything other than TooManyPagesException is
      // treated as a real finding.
      final r = await run(
        'E-report',
        _occurrence(
          finalReport: 'Relato institucional sintetico. ' * 200,
          results: const [
            OccurrenceResult.drugSeized,
            OccurrenceResult.weaponSeized,
            OccurrenceResult.personDetained,
            OccurrenceResult.boCreated,
          ],
          details: const {
            'drug_seized': [
              {'type': 'Maconha', 'weight_grams': '120'},
            ],
            'weapon_seized': {'type': 'Faca', 'quantity': '1'},
            'person_detained': {'count': '2', 'referral': '1o DP'},
            'bo_created': {'bo_number': '2026/000123', 'bo_type': 'Flagrante'},
          },
        ),
        [_event(i: 0, category: OccurrenceEventCategory.opening)],
      );
      assertGenerated('CASE E-report', r, allowFixtureArtifact: true);
    });

    test('CASE F — validation/pending signatures: complete PDF', () async {
      final r = await run(
        'F-validation',
        _occurrence(status: OccurrenceStatus.finalizedWithPending),
        [_event(i: 0, category: OccurrenceEventCategory.opening)],
      );
      assertGenerated('CASE F-validation', r);
    });

    test('CASE G — realistic field combination: complete PDF (also protects I1-A)',
        () async {
      final r = await run(
        'G-realistic',
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
        [
          for (var i = 0; i < 30; i++)
            _event(
              i: i,
              category:
                  OccurrenceEventCategory.values[i % OccurrenceEventCategory.values.length],
              description: 'Descricao sintetica do evento $i. ' * 4,
              lat: -22.5645 - i * 0.001,
              lng: -47.4017 - i * 0.001,
              photoUrls: i % 5 == 0 ? const ['https://example.invalid/p.jpg'] : const [],
            ),
        ],
      );
      assertGenerated('CASE G-realistic', r);
    });

    test('hermeticity: every outbound attempt was blocked, hosts are known', () {
      // Hermeticity is STRUCTURAL: the harness installs an HttpOverrides whose
      // client throws SocketException for every host, so nothing can reach the
      // network regardless of what the generator asks for. What we assert is that
      // the set of hosts it TRIES stays the known, benign set — a new host means
      // the generator grew an undocumented outbound dependency and must be
      // reported as a finding.
      //
      //   fonts.gstatic.com       -> PdfGoogleFonts; printing falls back to Helvetica.
      //   a.basemaps.cartocdn.com -> OsmStaticMapGenerator tiles; productive code
      //                              catches the failure and renders no map.
      //   example.invalid         -> our own fixture placeholder. RFC 2606 reserves
      //                              .invalid, so it can never resolve.
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
