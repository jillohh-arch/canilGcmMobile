// FF-OCC-09 — REGRESSION GUARD: who is allowed to declare the document broken.
//
// Physical defect:
//   Occurrence 212bdc56-eee5-4bb2-8a9f-4878a10a346b printed "SELO QUEBRADO"
//   because the Mobile verifier compared a LOCALLY recalculated hash against
//   the stored seal. The production verifier, queried live, answered
//   status=intact / document_intact=true and recalculated exactly the stored
//   hash. Dart and the Cloud Function canonicalize independently, so a local
//   mismatch never proved tampering.
//
// Frozen authority:
//   SERVER SEALS -> SERVER VERIFIES -> MOBILE PRESENTS THE SERVER VERDICT.
//   The local recomputation is diagnostic only. Verification being unavailable
//   is UNKNOWN, not tampering. Media divergence is its own channel and must not
//   overwrite the document status.
//
// Hermetic by construction: every case injects a MockClient, so no test here
// reaches the production verifier.

import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:canil_gcm/core/services/integrity_verification_service.dart';
import 'package:canil_gcm/core/services/occurrence_finalization_service.dart';
import 'package:canil_gcm/core/services/pdf_generator/occurrence_pdf_generator.dart';
import 'package:canil_gcm/features/occurrences/domain/occurrence.dart';
import 'package:canil_gcm/features/occurrences/domain/occurrence_event.dart';
import 'package:canil_gcm/features/occurrences/domain/occurrence_event_category.dart';
import 'package:canil_gcm/features/occurrences/domain/occurrence_status.dart';

const _occurrenceId = 'occ-ff-occ-09';

/// A stored seal that local recalculation will never reproduce. This is the
/// shape of the real defect: the seal is legitimate, the local rebuild differs.
const _storedSeal =
    '9e824cd05f75475ff88b2b2cb8adc26958b05a71bdaf70706935bfc13ac13371';

OccurrenceEvent _event({String photoHash = 'foto-a'}) {
  final now = DateTime.utc(2026, 8, 25, 11);
  return OccurrenceEvent(
    id: 'evt-ff-occ-09',
    occurrenceId: _occurrenceId,
    category: OccurrenceEventCategory.positiveIndication,
    timestamp: now,
    title: 'Indicacao',
    photoUrls: const ['https://example.invalid/foto.jpg'],
    photoMetadata: [
      {'sha256': photoHash},
    ],
    createdAt: now,
    updatedAt: now,
  );
}

Occurrence _sealed({required String integrityHash, int hashVersion = 4}) {
  final now = DateTime.utc(2026, 8, 25, 10);
  return Occurrence(
    id: _occurrenceId,
    shiftId: 'shift-ff-occ-09',
    primaryHandlerId: 'handler-1',
    primaryHandlerRa: '99999',
    dogId: 'dog-1',
    typeCode: 'BUSCA',
    typeName: 'Ocorrencia com entorpecente',
    locationAddress: 'Rua Sintetica, 100 - Limeira/SP',
    startedAt: now,
    finalizedAt: now.add(const Duration(hours: 2)),
    createdAt: now,
    updatedAt: now.add(const Duration(hours: 2)),
    status: OccurrenceStatus.finalized,
    integrityHash: integrityHash,
    hashVersion: hashVersion,
  );
}

Future<FakeFirebaseFirestore> _db(
  Occurrence occurrence,
  OccurrenceEvent event,
) async {
  final db = FakeFirebaseFirestore();
  await db.collection('occurrences').doc(occurrence.id).set(occurrence.toMap());
  await db
      .collection('occurrences')
      .doc(occurrence.id)
      .collection('events')
      .doc(event.id)
      .set(event.toMap());
  return db;
}

/// Builds a coherent authoritative response, mirroring the frozen production
/// contract observed live on 2026-08-30.
MockClient _serverSays(Map<String, dynamic> payload, {int httpStatus = 200}) {
  return MockClient((_) async {
    return http.Response(
      jsonEncode(payload),
      httpStatus,
      headers: const {'content-type': 'application/json'},
    );
  });
}

Map<String, dynamic> _intactPayload({List<String>? mediaIssues}) => {
  'occurrence_id': _occurrenceId,
  'status': mediaIssues == null ? 'intact' : 'media_broken',
  'sealed': true,
  'intact': true,
  'document_intact': true,
  'stored_hash': _storedSeal,
  'hash_version': 4,
  'media_issues': ?mediaIssues,
};

void main() {
  group('FF-OCC-09 — the server decides whether the document is broken', () {
    test(
      'R1: server says intact while the local rebuild differs -> NOT broken',
      () async {
        // This is the exact production defect. The stored seal is legitimate,
        // the Dart recomputation cannot reproduce it, and the authoritative
        // verifier confirms the document is intact.
        final event = _event();
        final occurrence = _sealed(integrityHash: _storedSeal);
        final db = await _db(occurrence, event);

        final localOnly = IntegrityVerificationService.verify(
          occurrence,
          events: [event],
        );
        expect(
          localOnly.status,
          IntegrityStatus.broken,
          reason:
              'Precondition: the local-only comparison must disagree, '
              'otherwise this test would not exercise the defect.',
        );

        final verdict = await IntegrityVerificationService(
          firestore: db,
          httpClient: _serverSays(_intactPayload()),
        ).verifyById(_occurrenceId);

        expect(
          verdict.status,
          IntegrityStatus.intact,
          reason:
              'A local mismatch is not authority. The server verdict wins, so '
              'the PDF must never accuse tampering for this occurrence.',
        );
        expect(
          verdict.status,
          isNot(IntegrityStatus.broken),
          reason: 'FF-OCC-09 primary killer: no false broken seal.',
        );
      },
    );

    test('R2: server says broken -> broken is still reachable', () async {
      // The fix must not buy the false negative by disabling real detection.
      final event = _event();
      final occurrence = _sealed(integrityHash: _storedSeal);
      final db = await _db(occurrence, event);

      final verdict = await IntegrityVerificationService(
        firestore: db,
        httpClient: _serverSays({
          'occurrence_id': _occurrenceId,
          'status': 'broken',
          'sealed': true,
          'intact': false,
          'document_intact': false,
          'stored_hash': _storedSeal,
          'hash_version': 4,
        }),
      ).verifyById(_occurrenceId);

      expect(
        verdict.status,
        IntegrityStatus.broken,
        reason: 'Genuine documentary invalidation must remain presentable.',
      );
    });

    group('R3: authoritative verifier unavailable -> unverified', () {
      test('connection failure', () async {
        final event = _event();
        final db = await _db(_sealed(integrityHash: _storedSeal), event);

        final verdict = await IntegrityVerificationService(
          firestore: db,
          httpClient: MockClient(
            (_) async => throw http.ClientException('no route to host'),
          ),
        ).verifyById(_occurrenceId);

        expect(verdict.status, IntegrityStatus.unverified);
        expect(verdict.status, isNot(IntegrityStatus.broken));
      });

      test('non-2xx response', () async {
        final event = _event();
        final db = await _db(_sealed(integrityHash: _storedSeal), event);

        final verdict = await IntegrityVerificationService(
          firestore: db,
          httpClient: _serverSays(const {'status': 'error'}, httpStatus: 500),
        ).verifyById(_occurrenceId);

        expect(verdict.status, IntegrityStatus.unverified);
      });

      test('malformed JSON body', () async {
        final event = _event();
        final db = await _db(_sealed(integrityHash: _storedSeal), event);

        final verdict = await IntegrityVerificationService(
          firestore: db,
          httpClient: MockClient(
            (_) async => http.Response('<html>not json</html>', 200),
          ),
        ).verifyById(_occurrenceId);

        expect(verdict.status, IntegrityStatus.unverified);
      });

      test('payload for a different occurrence is not trusted', () async {
        final event = _event();
        final db = await _db(_sealed(integrityHash: _storedSeal), event);

        final verdict = await IntegrityVerificationService(
          firestore: db,
          httpClient: _serverSays({
            ..._intactPayload(),
            'occurrence_id': 'another-occurrence',
          }),
        ).verifyById(_occurrenceId);

        expect(
          verdict.status,
          IntegrityStatus.unverified,
          reason: 'An answer about a different document proves nothing.',
        );
      });

      test('incoherent payload is not trusted', () async {
        final event = _event();
        final db = await _db(_sealed(integrityHash: _storedSeal), event);

        final verdict = await IntegrityVerificationService(
          firestore: db,
          httpClient: _serverSays({
            ..._intactPayload(),
            'document_intact': false, // contradicts status=intact
          }),
        ).verifyById(_occurrenceId);

        expect(verdict.status, IntegrityStatus.unverified);
      });
    });

    test('R4: unverified is presented without accusing tampering', () {
      const verdict = IntegrityVerdict(status: IntegrityStatus.unverified);
      final label = verdict.label.toLowerCase();

      expect(label, contains('nao disponivel'));
      expect(
        label,
        isNot(contains('quebrado')),
        reason: 'Unavailable verification must not read as a broken seal.',
      );
      expect(
        label,
        isNot(contains('adultera')),
        reason: 'No tampering claim without authority.',
      );
      expect(
        label,
        isNot(contains('qr')),
        reason:
            'FF-OCC-11 proved the printed QR route answers 404, so it must '
            'not be offered as the fallback.',
      );
      expect(verdict.isIntact, isFalse);
    });

    group('R5: media integrity is a separate channel', () {
      test('local deep verification reports media issues without breaking the '
          'document seal', () async {
        final event = _event(photoHash: 'foto-a');
        final localHash =
            OccurrenceFinalizationService.calculateIntegrityHashV2For(
              _sealed(integrityHash: 'placeholder', hashVersion: 2),
              events: [event],
            );
        final occurrence = _sealed(integrityHash: localHash, hashVersion: 2);
        final db = await _db(occurrence, event);

        final verdict = await IntegrityVerificationService(
          firestore: db,
          httpClient: _serverSays({
            ..._intactPayload(),
            'stored_hash': localHash,
            'hash_version': 2,
          }),
          // Storage bytes diverge from the recorded sha256.
          mediaHashReader: (_, {int maxBytes = 20 * 1024 * 1024}) async =>
              'foto-trocada',
        ).verifyById(_occurrenceId, verifyMediaBytes: true);

        expect(
          verdict.status,
          IntegrityStatus.intact,
          reason:
              'The document hash is intact per the authority; only the media '
              'diverges. Reporting a broken seal here would be a lie.',
        );
        expect(
          verdict.mediaIssues,
          isNotEmpty,
          reason: 'The media signal must not be silently lost.',
        );
        expect(verdict.mediaIssues.single, contains('SHA-256'));
        expect(verdict.checkedMediaCount, 1);
      });

      test(
        'server media_broken with an intact document keeps the seal intact',
        () async {
          final event = _event();
          final db = await _db(_sealed(integrityHash: _storedSeal), event);

          final verdict = await IntegrityVerificationService(
            firestore: db,
            httpClient: _serverSays(
              _intactPayload(
                mediaIssues: const ['evento evt-1 foto 1: SHA-256 divergente'],
              ),
            ),
          ).verifyById(_occurrenceId);

          expect(verdict.status, IntegrityStatus.intact);
          expect(verdict.mediaIssues, isNotEmpty);
        },
      );
    });

    // FF-OCC-09.C2 / R1 finding F2. The local recomputation is a diagnostic.
    // If it throws, the authoritative request must still happen — otherwise a
    // diagnostic failure silently becomes a veto over the server's truth.
    test(
      'R6: local diagnostic failure does not block a valid server verdict',
      () async {
        final event = _event();
        final occurrence = _sealed(integrityHash: _storedSeal, hashVersion: 4);
        final db = await _db(occurrence, event);
        // A correction request carrying a GeoPoint. `_loadCorrectionRequests`
        // hands raw Firestore values straight to the hash payload and
        // `_normalizeForHash` passes unknown types through untouched, so
        // canonicalisation ends in `jsonEncode` on a value it cannot encode and
        // the diagnostic throws. v4 is required: correction_requests only enter
        // the payload at that version.
        await db
            .collection('occurrences')
            .doc(_occurrenceId)
            .collection('correction_requests')
            .doc('cor-1')
            .set({
              'round': 1,
              'status': 'open',
              'local': const GeoPoint(-22.5645, -47.4017),
            });

        var serverWasQueried = false;
        final verdict = await IntegrityVerificationService(
          firestore: db,
          httpClient: MockClient((_) async {
            serverWasQueried = true;
            return http.Response(
              jsonEncode(_intactPayload()),
              200,
              headers: const {'content-type': 'application/json'},
            );
          }),
        ).verifyById(_occurrenceId);

        expect(
          verdict.recomputedHash,
          isNull,
          reason:
              'Proof that the catch actually ran: a successful diagnostic always '
              'fills recomputedHash. If this is non-null the test stopped '
              'exercising the failure path and is no longer a killer.',
        );
        expect(
          serverWasQueried,
          isTrue,
          reason:
              'The authoritative verifier must be consulted even when the local '
              'diagnostic cannot be computed. If this fails, someone moved the '
              'server call back behind a successful local recomputation.',
        );
        expect(
          verdict.status,
          IntegrityStatus.intact,
          reason: 'The server said intact; a broken diagnostic cannot veto it.',
        );
      },
    );

    // FF-OCC-09.C2 / R1 finding F5. R4 pins the service label; this pins the
    // text the operator actually reads in the PDF.
    group('R7: PDF integrity text for unverified stays non-accusatory', () {
      String textFor(IntegrityStatus status) {
        return OccurrencePdfGenerator.integrityStateTextForTest(
          hasHash: true,
          verdict: IntegrityVerdict(status: status),
        ).toUpperCase();
      }

      test('says verification unavailable', () {
        expect(
          textFor(IntegrityStatus.unverified),
          contains('VERIFICACAO NAO DISPONIVEL'),
        );
      });

      test('never accuses tampering nor points at the broken QR', () {
        final text = textFor(IntegrityStatus.unverified);
        expect(text, isNot(contains('SELO QUEBRADO')));
        expect(text, isNot(contains('ADULTERA')));
        expect(
          text,
          isNot(contains('NAO CONFERE')),
          reason: 'No hash-mismatch claim without authority.',
        );
        expect(
          text,
          isNot(contains('QR')),
          reason: 'FF-OCC-11: that route answers 404, so it is not a fallback.',
        );
      });

      test('a genuine server broken verdict still reads as broken', () {
        expect(textFor(IntegrityStatus.broken), contains('SELO QUEBRADO'));
      });

      // FF-OCC-09.H1.C1 — physical finding. The online PDF said "INTEGRO / Hash
      // recalculado localmente e conferido com o selo armazenado" for occurrence
      // 212bdc56, whose stored seal is 9e824cd0…3371 while the local
      // recomputation is ac366abc…228cb. The status was right; the sentence
      // explaining it was false. Only the official verifier confirms document
      // integrity, so the wording must attribute it there.
      test('intact credits the official verifier, not the local recompute', () {
        final text = textFor(IntegrityStatus.intact);

        expect(text, contains('INTEGRO'));
        expect(
          text,
          contains('VERIFICADOR OFICIAL'),
          reason: 'Documentary integrity comes from the server authority.',
        );
        expect(
          text,
          isNot(contains('RECALCULADO LOCALMENTE')),
          reason:
              'The local hash may differ while the document is valid — claiming '
              'a local match would be factually false.',
        );
        expect(
          text,
          isNot(contains('CONFERIDO COM O SELO')),
          reason: 'Local recomputation is diagnostic, never the authority.',
        );
        expect(
          text,
          isNot(contains('LOCALMENTE E CONFERIDO')),
          reason: 'Guards the exact stale sentence found in physical H1.',
        );
      });
    });
  });
}
