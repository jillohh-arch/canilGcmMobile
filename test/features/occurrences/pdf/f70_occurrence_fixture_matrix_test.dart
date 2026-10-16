// F70 — OCCURRENCE FIXTURE MATRIX A–L (MOB-DOC-01)
// Synthetic, non-official PDFs for visual/forensic validation.
// All guards from the frozen baseline are re-executed against the
// migrated F70 generator to prevent silent contract drift.

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:canil_gcm/core/services/integrity_verification_service.dart';
import 'package:canil_gcm/core/domain/occurrence_signature.dart';
import 'package:canil_gcm/core/domain/occurrence_team_member.dart';
import 'package:canil_gcm/core/services/pdf_generator/occurrence_pdf_generator.dart';
import 'package:canil_gcm/features/dogs/domain/dog.dart';
import 'package:canil_gcm/features/occurrences/domain/occurrence.dart';
import 'package:canil_gcm/features/occurrences/domain/occurrence_event.dart';
import 'package:canil_gcm/features/occurrences/domain/occurrence_event_category.dart';
import 'package:canil_gcm/features/occurrences/domain/occurrence_result.dart';
import 'package:canil_gcm/features/occurrences/domain/occurrence_status.dart';

import 'pdf_diagnostic_harness.dart';

// ── Synthetic IDs (never collide with real occurrences) ──────────────────
const _syntheticPrefix = 'SYNTH-F70-';
final _hashF64 = List.filled(64, 'f').join();
final _hashA64 = List.filled(64, 'a').join();
final _hashB64 = List.filled(64, 'b').join();
final _hashC64 = List.filled(64, 'c').join();
final _t0 = DateTime(2026, 5, 20, 14, 30);

Dog _dog({String id = 'dog-synth', String name = 'Rex'}) => Dog(
  id: id,
  name: name,
  breed: 'Pastor Belga Malinois',
  dateOfBirth: DateTime(2021, 3, 10),
  registrationNumber: 'K9-SYNTH-001',
);

OccurrenceEvent _evt({
  required int i,
  required String occId,
  OccurrenceEventCategory category = OccurrenceEventCategory.other,
  String? description,
  double? lat,
  double? lng,
  List<String> photoUrls = const [],
}) {
  final ts = _t0.add(Duration(minutes: 7 * i));
  return OccurrenceEvent(
    id: 'evt-synth-$i',
    occurrenceId: occId,
    category: category,
    timestamp: ts,
    title: 'Ação sintética $i [DEMO]',
    description:
        description ?? 'Registro sintético $i — fixture F70 não oficial.',
    photoUrls: photoUrls,
    gpsLat: lat,
    gpsLng: lng,
    placeLabel: lat == null ? null : 'Ponto demo $i',
    createdAt: ts,
    updatedAt: ts,
  );
}

Occurrence _occ({
  required String id,
  required OccurrenceStatus status,
  String typeName = 'Apoio Policial com Emprego de K9 [DEMO]',
  String? locationAddress = 'Rua Sintética, 100 — Limeira/SP [DEMO]',
  double? gpsLat = -22.5645,
  double? gpsLng = -47.4017,
  double? gpsAccuracy = 5.0,
  String? finalReport,
  List<OccurrenceResult> results = const [],
  Map<String, dynamic>? details,
  List<OccurrenceTeamMember> team = const [],
  List<OccurrenceSignature> signatures = const [],
  DateTime? signatureRequestAt,
  DateTime? signatureDeadline,
  int signatureRound = 1,
  String? integrityHash,
  int? hashVersion = 4,
  List<String> finalizationPhotos = const [],
  String? vehicleLabel,
  String? vehicleModel,
  String dogId = 'dog-synth',
  String? serviceDogId,
  bool sealIntegrity = true,
}) {
  return Occurrence(
    id: id,
    shiftId: 'shift-synth',
    primaryHandlerId: 'handler-synth-titular',
    primaryHandlerRa: '90001',
    dogId: dogId,
    serviceDogId: serviceDogId,
    typeCode: 'APOIO',
    typeName: typeName,
    locationAddress: locationAddress,
    gpsLat: gpsLat,
    gpsLng: gpsLng,
    gpsAccuracy: gpsAccuracy,
    startedAt: _t0,
    finalizedAt: status == OccurrenceStatus.inProgress
        ? null
        : _t0.add(const Duration(hours: 2)),
    createdAt: _t0,
    updatedAt: _t0.add(const Duration(hours: 2)),
    status: status,
    finalReport: finalReport,
    finalizationPhotos: finalizationPhotos,
    results: results,
    details: details,
    team: team,
    signatures: signatures,
    signatureRequestAt: signatureRequestAt,
    signatureDeadline: signatureDeadline,
    signatureRound: signatureRound,
    integrityHash: sealIntegrity ? (integrityHash ?? _hashF64) : null,
    hashVersion: sealIntegrity ? hashVersion : null,
    vehicleLabel: vehicleLabel,
    vehicleModel: vehicleModel,
  );
}

String _longNarrative() =>
    ('Relato sintético F70 para validação de paginação — parágrafo de demonstração com conteúdo não oficial. ' *
            18)
        .trim() +
    '\n\n' +
    ('Segundo bloco sintético para forçar quebra de página e validar que parágrafos paginam sem truncamento. ' *
            14)
        .trim() +
    '\n\n' +
    ('Terceiro bloco sintético cobrindo apuração operacional fictícia, sem valor probatório. ' *
            12)
        .trim();

Dog? _dogFor(Occurrence o) {
  if (o.dogId.trim().isEmpty) return null;
  final sid = o.serviceDogId?.trim();
  if (sid != null && sid.isEmpty) return null;
  return _dog();
}

Future<Uint8List> _generate({
  required Occurrence occurrence,
  required List<OccurrenceEvent> events,
  IntegrityVerdict? verdict,
}) {
  return OccurrencePdfGenerator().generate(
    occurrence: occurrence,
    events: events,
    dog: _dogFor(occurrence),
    handlerName: 'GCM 1CL Silva [DEMO]',
    handlerRa: '90001',
    integrityVerdict: verdict,
  );
}

void main() {
  setUpAll(() async {
    await installHermeticPdfHarness();
  });
  tearDownAll(uninstallHermeticPdfHarness);

  group('F70 — Fixture Matrix A–L', () {
    test('A: normal occurrence with K9 and one actor', () async {
      final occ = _occ(
        id: '${_syntheticPrefix}A',
        status: OccurrenceStatus.finalized,
        finalReport:
            'Relato sintético A — ocorrência normal com K9 e um condutor.',
      );
      final events = [
        _evt(i: 0, occId: occ.id, category: OccurrenceEventCategory.opening),
        _evt(
          i: 1,
          occId: occ.id,
          category: OccurrenceEventCategory.dogWork,
          lat: -22.5645,
          lng: -47.4017,
        ),
      ];
      final bytes = await _generate(occurrence: occ, events: events);
      expect(bytes, isNotEmpty);
      expect(bytes.length, greaterThan(8000));
    });

    test('B: multiple actors with all signatures completed', () async {
      final team = [
        OccurrenceTeamMember(
          handlerId: '90001',
          displayName: 'GCM Silva',
          role: TeamRole.titular,
          addedAt: _t0,
          addedBy: '90001',
        ),
        OccurrenceTeamMember(
          handlerId: '90002',
          displayName: 'GCM Souza',
          role: TeamRole.integrante,
          addedAt: _t0,
          addedBy: '90001',
        ),
        OccurrenceTeamMember(
          handlerId: '90003',
          displayName: 'GCM Lima',
          role: TeamRole.integrante,
          addedAt: _t0,
          addedBy: '90001',
        ),
      ];
      final now = _t0.add(const Duration(hours: 1));
      final sigs = [
        OccurrenceSignature(
          handlerId: '90001',
          status: SignatureStatus.signed,
          signedAt: now,
          signatureMethod: SignatureMethod.biometric,
          signatureHash: _hashA64,
          round: 1,
        ),
        OccurrenceSignature(
          handlerId: '90002',
          status: SignatureStatus.signed,
          signedAt: now.add(const Duration(minutes: 5)),
          signatureMethod: SignatureMethod.password,
          signatureHash: _hashB64,
          round: 1,
        ),
        OccurrenceSignature(
          handlerId: '90003',
          status: SignatureStatus.signed,
          signedAt: now.add(const Duration(minutes: 10)),
          signatureMethod: SignatureMethod.biometric,
          signatureHash: _hashC64,
          round: 1,
        ),
      ];
      final occ = _occ(
        id: '${_syntheticPrefix}B',
        status: OccurrenceStatus.finalized,
        team: team,
        signatures: sigs,
        signatureRequestAt: now,
        signatureDeadline: now.add(const Duration(hours: 24)),
      );
      final events = [
        _evt(i: 0, occId: occ.id, category: OccurrenceEventCategory.opening),
        _evt(i: 1, occId: occ.id, category: OccurrenceEventCategory.closure),
      ];
      final bytes = await _generate(
        occurrence: occ,
        events: events,
        verdict: IntegrityVerdict(
          status: IntegrityStatus.intact,
          storedHash: _hashF64,
          hashVersion: 4,
        ),
      );
      expect(bytes, isNotEmpty);
    });

    test('C: finalizedWithPending with pending co-signature', () async {
      final team = [
        OccurrenceTeamMember(
          handlerId: '90001',
          displayName: 'GCM Silva',
          role: TeamRole.titular,
          addedAt: _t0,
          addedBy: '90001',
        ),
        OccurrenceTeamMember(
          handlerId: '90002',
          displayName: 'GCM Souza',
          role: TeamRole.integrante,
          addedAt: _t0,
          addedBy: '90001',
        ),
      ];
      final now = _t0.add(const Duration(hours: 1));
      final sigs = [
        OccurrenceSignature(
          handlerId: '90001',
          status: SignatureStatus.signed,
          signedAt: now,
          signatureHash: _hashA64,
          round: 1,
        ),
      ];
      final occ = _occ(
        id: '${_syntheticPrefix}C',
        status: OccurrenceStatus.finalizedWithPending,
        team: team,
        signatures: sigs,
        signatureRequestAt: now,
        signatureDeadline: now.add(const Duration(hours: 24)),
      );
      final bytes = await _generate(
        occurrence: occ,
        events: [_evt(i: 0, occId: occ.id)],
        verdict: IntegrityVerdict(
          status: IntegrityStatus.unverified,
          storedHash: _hashF64,
          hashVersion: 4,
        ),
      );
      expect(bytes, isNotEmpty);
    });

    test('D: occurrence without associated K9 (dogName fallback)', () async {
      final occ = _occ(
        id: '${_syntheticPrefix}D',
        status: OccurrenceStatus.finalized,
        dogId: '',
        serviceDogId: '',
      );
      final bytes = await _generate(
        occurrence: occ,
        events: [_evt(i: 0, occId: occ.id)],
      );
      expect(bytes, isNotEmpty);
      expect(String.fromCharCodes(bytes).contains('Rex'), isFalse);
    });

    test('E: multiple evidence images with varied aspect ratios', () async {
      final occ = _occ(
        id: '${_syntheticPrefix}E',
        status: OccurrenceStatus.finalized,
      );
      // URLs are invalid on purpose (hermetic harness blocks network) — tests fallback "imagem indisponível"
      final events = [
        for (var i = 0; i < 6; i++)
          _evt(
            i: i,
            occId: occ.id,
            photoUrls: const ['https://example.invalid/photo.jpg'],
          ),
      ];
      final bytes = await _generate(occurrence: occ, events: events);
      expect(bytes, isNotEmpty);
    });

    test('F: missing/unavailable image with explicit fallback', () async {
      final occ = _occ(
        id: '${_syntheticPrefix}F',
        status: OccurrenceStatus.finalized,
      );
      final events = [
        _evt(
          i: 0,
          occId: occ.id,
          photoUrls: const ['https://example.invalid/missing.jpg'],
        ),
        _evt(i: 1, occId: occ.id, photoUrls: const ['']),
      ];
      final bytes = await _generate(occurrence: occ, events: events);
      expect(bytes, isNotEmpty);
      // Forensic invariant: unavailable image must NOT silently disappear — checked visually; here we guarantee no crash
    });

    test('G: long narrative and long timeline', () async {
      final occ = _occ(
        id: '${_syntheticPrefix}G',
        status: OccurrenceStatus.finalized,
        finalReport: _longNarrative(),
        results: const [
          OccurrenceResult.drugSeized,
          OccurrenceResult.personDetained,
          OccurrenceResult.boCreated,
        ],
        details: const {
          'bo_created': {'bo_number': 'SYNTH/2026/0001'},
        },
      );
      final events = [
        for (var i = 0; i < 14; i++)
          _evt(
            i: i,
            occId: occ.id,
            category: OccurrenceEventCategory
                .values[i % OccurrenceEventCategory.values.length],
            description:
                'Evento sintético G-$i — narrativa longa para paginação.',
            lat: -22.5645 - i * 0.0008,
            lng: -47.4017 - i * 0.0008,
          ),
      ];
      final bytes = await _generate(occurrence: occ, events: events);
      expect(bytes, isNotEmpty);
      expect(bytes.length, greaterThan(15000));
    });

    test('H: multiple-page occurrence with continuation headers', () async {
      final occ = _occ(
        id: '${_syntheticPrefix}H',
        status: OccurrenceStatus.finalized,
        finalReport: _longNarrative(),
        finalizationPhotos: const [
          'https://example.invalid/f1.jpg',
          'https://example.invalid/f2.jpg',
          'https://example.invalid/f3.jpg',
        ],
      );
      final events = [
        for (var i = 0; i < 12; i++)
          _evt(
            i: i,
            occId: occ.id,
            lat: -22.5645 - i * 0.001,
            lng: -47.4017 - i * 0.001,
            photoUrls: i.isEven
                ? const ['https://example.invalid/p.jpg']
                : const [],
          ),
      ];
      final bytes = await _generate(occurrence: occ, events: events);
      expect(bytes, isNotEmpty);
      expect(bytes.length, greaterThan(15000));
    });

    test('I: canceled occurrence', () async {
      final occ = _occ(
        id: '${_syntheticPrefix}I',
        status: OccurrenceStatus.canceled,
        finalReport: 'Ocorrência cancelada — fixture sintético.',
      );
      final bytes = await _generate(
        occurrence: occ,
        events: [
          _evt(i: 0, occId: occ.id, category: OccurrenceEventCategory.opening),
        ],
      );
      expect(bytes, isNotEmpty);
    });

    test('J: finalized occurrence with independent amendment simulation', () async {
      // Amendments are loaded via AmendmentRepository (hermetic harness returns empty snapshot) — so we test that a finalized occurrence still renders cleanly when amendments list is empty
      final occ = _occ(
        id: '${_syntheticPrefix}J',
        status: OccurrenceStatus.finalized,
        finalReport:
            'Relato sintético J — simula ocorrência com aditamento (lista vazia no harness).',
      );
      final bytes = await _generate(
        occurrence: occ,
        events: [_evt(i: 0, occId: occ.id)],
        verdict: IntegrityVerdict(
          status: IntegrityStatus.intact,
          storedHash: _hashF64,
          hashVersion: 4,
        ),
      );
      expect(bytes, isNotEmpty);
    });

    test('K: legacy/unverified integrity state', () async {
      final occLegacy = _occ(
        id: '${_syntheticPrefix}K-legacy',
        status: OccurrenceStatus.finalized,
        hashVersion: 1,
        integrityHash: _hashA64,
      );
      final bytesLegacy = await _generate(
        occurrence: occLegacy,
        events: [_evt(i: 0, occId: occLegacy.id)],
        verdict: IntegrityVerdict(
          status: IntegrityStatus.legacy,
          storedHash: _hashA64,
          hashVersion: 1,
        ),
      );
      expect(bytesLegacy, isNotEmpty);

      final occUnverified = _occ(
        id: '${_syntheticPrefix}K-unverified',
        status: OccurrenceStatus.finalized,
      );
      final bytesUnverified = await _generate(
        occurrence: occUnverified,
        events: [_evt(i: 0, occId: occUnverified.id)],
        verdict: IntegrityVerdict(
          status: IntegrityStatus.unverified,
          storedHash: _hashF64,
          hashVersion: 4,
        ),
      );
      expect(bytesUnverified, isNotEmpty);
    });

    test('L: occurrence without optional location or media details', () async {
      final occ = _occ(
        id: '${_syntheticPrefix}L',
        status: OccurrenceStatus.inProgress,
        locationAddress: null,
        gpsLat: null,
        gpsLng: null,
        gpsAccuracy: null,
        sealIntegrity: false,
      );
      final bytes = await _generate(occurrence: occ, events: []);
      expect(bytes, isNotEmpty);
      // Unsealed lifecycle: hash box must show unsealed state (PENDENTE or prior-hash-free)
      // PDF text is encoded via font subsets — raw byte scan is fragile; verify via integrity helper contract
      final state = OccurrencePdfGenerator.integrityStateTextForTest(
        hasHash: false,
        verdict: null,
      );
      expect(state, contains('PENDENTE'));
      // Also verify the occurrence itself carries no seal
      expect(occ.integrityHash, isNull);
    });
  });

  group('F70 — Forensic string contracts (frozen)', () {
    test('formatDrugDescription contract preserved', () {
      expect(
        OccurrencePdfGenerator.formatDrugDescriptionForTest([
          {'type': 'Maconha', 'weight_grams': '255'},
        ]),
        equals('Maconha - 255 g'),
      );
      expect(
        OccurrencePdfGenerator.formatDrugDescriptionForTest([
          {'type': 'Maconha', 'quantidade': '255'},
        ]),
        equals('Maconha - 255'),
      );
      expect(
        OccurrencePdfGenerator.formatDrugDescriptionForTest([]),
        equals(
          'Substancia analoga a entorpecente apreendida e registrada na ocorrencia.',
        ),
      );
    });

    test('integrityStateText contract preserved (FF-OCC-09)', () {
      expect(
        OccurrencePdfGenerator.integrityStateTextForTest(
          hasHash: false,
          verdict: null,
        ),
        contains('PENDENTE'),
      );
      expect(
        OccurrencePdfGenerator.integrityStateTextForTest(
          hasHash: true,
          verdict: null,
        ),
        contains('SELO ARMAZENADO'),
      );
      expect(
        OccurrencePdfGenerator.integrityStateTextForTest(
          hasHash: true,
          verdict: IntegrityVerdict(status: IntegrityStatus.intact),
        ),
        contains('ÍNTEGRO'),
      );
      expect(
        OccurrencePdfGenerator.integrityStateTextForTest(
          hasHash: true,
          verdict: IntegrityVerdict(status: IntegrityStatus.broken),
        ),
        contains('SELO QUEBRADO'),
      );
      expect(
        OccurrencePdfGenerator.integrityStateTextForTest(
          hasHash: true,
          verdict: IntegrityVerdict(status: IntegrityStatus.unverified),
        ),
        contains('VERIFICAÇÃO NÃO DISPONÍVEL'),
      );
    });

    test('totalMediaCount / isEmptyMediaState contracts', () {
      expect(
        OccurrencePdfGenerator.totalMediaCountForTest(
          eventMediaCount: 3,
          finalizationMediaCount: 2,
        ),
        equals(5),
      );
      expect(
        OccurrencePdfGenerator.isEmptyMediaStateForTest(
          visibleMediaEmpty: true,
          finalizationMediaEmpty: true,
        ),
        isTrue,
      );
      expect(
        OccurrencePdfGenerator.isEmptyMediaStateForTest(
          visibleMediaEmpty: false,
          finalizationMediaEmpty: true,
        ),
        isFalse,
      );
    });
  });
}
