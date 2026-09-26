import 'package:flutter_test/flutter_test.dart';

import 'package:canil_gcm/features/occurrences/domain/occurrence.dart';
import 'package:canil_gcm/features/occurrences/domain/occurrence_status.dart';

void main() {
  final now = DateTime(2026, 9, 12, 11, 0);

  Occurrence buildOccurrence({
    required OccurrenceStatus status,
    List<String> pendingHandlerIds = const ['990002'],
    List<String> acceptedHandlerIds = const ['990001'],
  }) {
    return Occurrence(
      id: 'occ-d3-sealed-test',
      shiftId: 'shift-001',
      primaryHandlerId: '990001',
      primaryHandlerRa: '990001',
      dogId: 'dog-01',
      typeCode: 'TC01',
      typeName: 'Apoio Policial',
      startedAt: now,
      createdAt: now,
      updatedAt: now,
      status: status,
      pendingHandlerIds: pendingHandlerIds,
      acceptedHandlerIds: acceptedHandlerIds,
    );
  }

  group('D3 — Sealed Occurrence Review / Pending Participant State Handling', () {
    test('Sealed occurrence (finalized) marks isClosed=true and isOpen=false', () {
      final occ = buildOccurrence(status: OccurrenceStatus.finalized);
      expect(occ.status.isClosed, isTrue);
      expect(occ.status.isOpen, isFalse);
    });

    test('Sealed occurrence prevents participation response, signing, and correction actions', () {
      final occ = buildOccurrence(status: OccurrenceStatus.finalized);
      const currentRa = '990002'; // Pending participant

      // Replicating OccurrenceReviewScreen gating logic:
      final canRespondParticipation =
          occ.status.isOpen &&
          occ.primaryHandlerRa != currentRa &&
          occ.primaryHandlerId != currentRa &&
          occ.pendingHandlerIds.contains(currentRa);

      final canSign =
          occ.status == OccurrenceStatus.awaitingSignatures &&
          occ.team.any((item) => item.handlerId == currentRa);

      final canRequestCorrection =
          occ.status == OccurrenceStatus.awaitingSignatures &&
          (occ.team.any((m) => m.handlerId == currentRa) ||
              occ.primaryHandlerRa == currentRa ||
              occ.primaryHandlerId == currentRa);

      final canShowActionBar = canRespondParticipation || canSign || canRequestCorrection;

      // Assertions:
      expect(canRespondParticipation, isFalse,
          reason: 'Cannot respond to participation once occurrence is sealed');
      expect(canSign, isFalse,
          reason: 'Cannot sign once occurrence is completed/sealed');
      expect(canRequestCorrection, isFalse,
          reason: 'Cannot request correction once occurrence is completed/sealed');
      expect(canShowActionBar, isFalse,
          reason: 'Action bar must be hidden to avoid displaying impossible/disabled actions');
    });

    test('Occurrence awaitingSignatures allows signing/correction when appropriate but finalized does not', () {
      final occAwaiting = buildOccurrence(status: OccurrenceStatus.awaitingSignatures);
      final occFinalized = buildOccurrence(status: OccurrenceStatus.finalized);

      expect(occAwaiting.status == OccurrenceStatus.awaitingSignatures, isTrue);
      expect(occFinalized.status == OccurrenceStatus.awaitingSignatures, isFalse);
      expect(occFinalized.status.isClosed, isTrue);
    });
  });
}
