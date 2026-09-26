import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:canil_gcm/core/domain/occurrence_signature.dart';
import 'package:canil_gcm/core/domain/occurrence_team_member.dart';
import 'package:canil_gcm/core/services/occurrence_transition_service.dart';
import 'package:canil_gcm/features/occurrences/data/occurrence_repository.dart';
import 'package:canil_gcm/features/occurrences/domain/occurrence.dart';
import 'package:canil_gcm/features/occurrences/domain/occurrence_result.dart';
import 'package:canil_gcm/features/occurrences/domain/occurrence_status.dart';

class _FakeOccurrenceTransitionService implements OccurrenceTransitionService {
  String? lastSealedOccurrenceId;
  String? lastClosedForSignaturesOccurrenceId;
  String? lastSignedOccurrenceId;
  String? lastAcceptedOccurrenceId;
  int acceptParticipationCallCount = 0;

  @override
  Future<SealOccurrenceResult> sealOccurrenceV4({
    required String occurrenceId,
    required String finalReport,
    required List<OccurrenceResult> results,
    required Map<String, dynamic>? details,
    required List<String> finalizationPhotos,
    required List<String> finalizationPhotoHashes,
    bool withPending = false,
  }) async {
    lastSealedOccurrenceId = occurrenceId;
    return const SealOccurrenceResult(
      integrityHash: 'test-hash',
      hashVersion: 4,
      status: 'finalized',
    );
  }

  @override
  Future<void> closeForSignatures({
    required String occurrenceId,
    required String finalReport,
    required List<OccurrenceResult> results,
    required Map<String, dynamic>? details,
    required List<String> finalizationPhotos,
    required List<String> finalizationPhotoHashes,
    Duration signatureDeadline = const Duration(hours: 48),
  }) async {
    lastClosedForSignaturesOccurrenceId = occurrenceId;
  }

  @override
  Future<void> signOccurrence({
    required String occurrenceId,
    required OccurrenceSignature signature,
  }) async {
    lastSignedOccurrenceId = occurrenceId;
  }

  @override
  Future<void> requestCorrection({
    required String occurrenceId,
    required String reason,
  }) async {}

  @override
  Future<void> declineParticipation({
    required String occurrenceId,
    required String reason,
  }) async {}

  @override
  Future<void> acceptParticipation({required String occurrenceId}) async {
    acceptParticipationCallCount++;
    lastAcceptedOccurrenceId = occurrenceId;
  }
}

void main() {
  late FakeFirebaseFirestore fakeFirestore;
  late _FakeOccurrenceTransitionService fakeTransitionService;
  late OccurrenceRepository repository;

  final now = DateTime(2026, 9, 10, 10, 0);

  setUp(() {
    fakeFirestore = FakeFirebaseFirestore();
    fakeTransitionService = _FakeOccurrenceTransitionService();
    repository = OccurrenceRepository(
      fakeFirestore,
      transitionService: fakeTransitionService,
    );
  });

  group('TC1-SIGN — Signature Eligibility Regression Tests', () {
    test(
      'TC1-SIGN-01: Pending Actor B is excluded from signatures and occurrence seals directly',
      () async {
        final occ = Occurrence(
          id: 'occ-tc1-sign-01',
          shiftId: 'shift-tc1',
          primaryHandlerId: 'actor-a',
          primaryHandlerRa: '990001',
          dogId: 'stg-dog-tc1-001',
          typeCode: 'AVERIGUACAO',
          typeName: 'Averiguação',
          locationAddress: 'Rua Operacional, 100',
          startedAt: now,
          createdAt: now,
          updatedAt: now,
          status: OccurrenceStatus.inProgress,
          team: [
            OccurrenceTeamMember(
              handlerId: '990001',
              handlerEmail: '990001@gcm.com.br',
              displayName: 'Actor A',
              role: TeamRole.titular,
              addedAt: now,
              addedBy: '990001',
            ),
            OccurrenceTeamMember(
              handlerId: '990002',
              handlerEmail: '990002@gcm.com.br',
              displayName: 'Actor B',
              role: TeamRole.integrante,
              addedAt: now,
              addedBy: '990001',
            ),
          ],
        );

        await repository.create(occ);

        // Final report filled
        final result = await repository.closeForSignatures(
          occurrenceId: 'occ-tc1-sign-01',
          finalReport: 'Relato final completo sem pendências.',
        );

        // Canonical no-cosigner fallback seals directly because Actor B never accepted
        expect(result, equals(CloseForSignaturesResult.sealedDirectly));
        expect(
          fakeTransitionService.lastSealedOccurrenceId,
          equals('occ-tc1-sign-01'),
        );
        expect(
          fakeTransitionService.lastClosedForSignaturesOccurrenceId,
          isNull,
        );
      },
    );

    test(
      'TC1-SIGN-02: Accepted Actor B becomes eligible cosigner and signature round is entered',
      () async {
        final occ = Occurrence(
          id: 'occ-tc1-sign-02',
          shiftId: 'shift-tc1',
          primaryHandlerId: 'actor-a',
          primaryHandlerRa: '990001',
          dogId: 'stg-dog-tc1-001',
          typeCode: 'AVERIGUACAO',
          typeName: 'Averiguação',
          locationAddress: 'Rua Operacional, 100',
          startedAt: now,
          createdAt: now,
          updatedAt: now,
          status: OccurrenceStatus.inProgress,
          team: [
            OccurrenceTeamMember(
              handlerId: '990001',
              handlerEmail: '990001@gcm.com.br',
              displayName: 'Actor A',
              role: TeamRole.titular,
              addedAt: now,
              addedBy: '990001',
            ),
            OccurrenceTeamMember(
              handlerId: '990002',
              handlerEmail: '990002@gcm.com.br',
              displayName: 'Actor B',
              role: TeamRole.integrante,
              addedAt: now,
              addedBy: '990001',
            ),
          ],
        );

        await repository.create(occ);

        // Simulate Actor B accepting participation:
        await fakeFirestore
            .collection('occurrences')
            .doc('occ-tc1-sign-02')
            .update({
              'accepted_handler_ids': ['990001', '990002'],
              'pending_handler_ids': <String>[],
              'participation_status': 'accepted',
            });

        // Now close for signatures with accepted Actor B
        final result = await repository.closeForSignatures(
          occurrenceId: 'occ-tc1-sign-02',
          finalReport: 'Relato final completo para assinaturas.',
        );

        // Must require signatures because Actor B accepted and is eligible cosigner
        expect(result, equals(CloseForSignaturesResult.awaitingSignatures));
        expect(
          fakeTransitionService.lastClosedForSignaturesOccurrenceId,
          equals('occ-tc1-sign-02'),
        );
      },
    );
  });
}
