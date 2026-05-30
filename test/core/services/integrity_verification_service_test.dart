import 'package:flutter_test/flutter_test.dart';

import 'package:canil_gcm/core/domain/occurrence_participation.dart';
import 'package:canil_gcm/core/domain/occurrence_signature.dart';
import 'package:canil_gcm/core/domain/occurrence_team_member.dart';
import 'package:canil_gcm/core/services/integrity_verification_service.dart';
import 'package:canil_gcm/core/services/occurrence_finalization_service.dart';
import 'package:canil_gcm/features/occurrences/domain/occurrence.dart';
import 'package:canil_gcm/features/occurrences/domain/occurrence_event.dart';
import 'package:canil_gcm/features/occurrences/domain/occurrence_event_category.dart';
import 'package:canil_gcm/features/occurrences/domain/occurrence_result.dart';

void main() {
  group('IntegrityVerificationService', () {
    test('selo íntegro: hash recalculado bate com o armazenado', () {
      final events = [_event(photoHash: 'foto-a')];
      final base = _occurrence();
      final hash = OccurrenceFinalizationService.calculateIntegrityHashV3For(
        base,
        events: events,
      );
      final sealed = base.copyWith(integrityHash: hash, hashVersion: 3);

      final verdict = IntegrityVerificationService.verify(
        sealed,
        events: events,
      );

      expect(verdict.status, IntegrityStatus.intact);
      expect(verdict.isIntact, isTrue);
      expect(verdict.recomputedHash, hash);
    });

    test('adulteração no evento quebra o selo', () {
      final events = [_event(photoHash: 'foto-a')];
      final base = _occurrence();
      final hash = OccurrenceFinalizationService.calculateIntegrityHashV3For(
        base,
        events: events,
      );
      final sealed = base.copyWith(integrityHash: hash, hashVersion: 3);

      // Troca o hash da foto — simula substituição de evidência.
      final tampered = [_event(photoHash: 'foto-trocada')];
      final verdict = IntegrityVerificationService.verify(
        sealed,
        events: tampered,
      );

      expect(verdict.status, IntegrityStatus.broken);
      expect(verdict.isIntact, isFalse);
    });

    test('adulteração no relato final quebra o selo', () {
      final events = [_event(photoHash: 'foto-a')];
      final base = _occurrence();
      final hash = OccurrenceFinalizationService.calculateIntegrityHashV3For(
        base,
        events: events,
      );
      final sealed = base.copyWith(
        integrityHash: hash,
        hashVersion: 3,
        finalReport: 'Relato adulterado depois do selo',
      );

      final verdict = IntegrityVerificationService.verify(
        sealed,
        events: events,
      );

      expect(verdict.status, IntegrityStatus.broken);
    });

    test('selo é independente de fuso horário (UTC normalizado)', () {
      final events = [_event(photoHash: 'foto-a')];
      final base = _occurrence();
      final hash = OccurrenceFinalizationService.calculateIntegrityHashV3For(
        base,
        events: events,
      );
      // Mesma instância temporal expressa em fuso local não-UTC.
      final localStart = base.startedAt.toLocal();
      final sealed = base.copyWith(
        startedAt: localStart,
        integrityHash: hash,
        hashVersion: 3,
      );

      final verdict = IntegrityVerificationService.verify(
        sealed,
        events: events,
      );

      expect(verdict.status, IntegrityStatus.intact);
    });

    test('ocorrência sem hash retorna não selado', () {
      final verdict = IntegrityVerificationService.verify(_occurrence());
      expect(verdict.status, IntegrityStatus.unsealed);
    });

    test('verifica hash v1, v2, v3 e v4', () {
      final events = [_event(photoHash: 'foto-a')];
      for (final version in [1, 2, 3, 4]) {
        final base = version == 4 ? _occurrenceV4() : _occurrence();
        final hash = OccurrenceFinalizationService.calculateIntegrityHashFor(
          base,
          version: version,
          events: events,
        );
        final sealed = base.copyWith(integrityHash: hash, hashVersion: version);

        final verdict = IntegrityVerificationService.verify(
          sealed,
          events: events,
        );

        expect(verdict.status, IntegrityStatus.intact);
      }
    });
  });
}

Occurrence _occurrenceV4() {
  final now = DateTime.utc(2026, 5, 29, 10);
  return _occurrence().copyWith(
    serviceDogId: 'dog-1',
    crewId: 'crew-1075',
    signatureRound: 2,
    participationStatus: 'accepted',
    acceptedHandlerIds: const ['123'],
    declinedHandlerIds: const [],
    pendingHandlerIds: const [],
    editAuthorizedHandlerIds: const ['123'],
    participationRevision: 1,
    participations: [
      OccurrenceParticipation(
        handlerId: '123',
        status: OccurrenceParticipationStatus.included,
        at: now,
        updatedBy: '123',
      ),
    ],
    correctionRequests: const [
      {
        'id': 'cor-1',
        'round': 1,
        'reason': 'Ajuste solicitado',
        'status': 'open',
      },
    ],
  );
}

Occurrence _occurrence() {
  final now = DateTime.utc(2026, 5, 29, 10);
  return Occurrence(
    id: 'occ-1',
    shiftId: 'shift-1',
    primaryHandlerId: '123',
    primaryHandlerRa: '123',
    dogId: 'dog-1',
    typeCode: 'det',
    typeName: 'Detecção',
    startedAt: now,
    createdAt: now,
    updatedAt: now,
    finalReport: 'Relato final',
    results: const [OccurrenceResult.drugSeized],
    details: const {
      'drug_seized': [
        {'type': 'Maconha', 'weight_grams': '10'},
      ],
    },
    team: [
      OccurrenceTeamMember(
        handlerId: '123',
        role: TeamRole.titular,
        addedAt: now,
        addedBy: '123',
      ),
    ],
    signatures: [
      OccurrenceSignature(
        handlerId: '123',
        status: SignatureStatus.signed,
        signedAt: DateTime.utc(2026, 5, 29, 12),
        signatureMethod: SignatureMethod.biometric,
        signatureHash: 'hash-variavel-ignorado',
      ),
    ],
  );
}

OccurrenceEvent _event({String id = 'event-1', required String photoHash}) {
  final now = DateTime.utc(2026, 5, 29, 11);
  return OccurrenceEvent(
    id: id,
    occurrenceId: 'occ-1',
    category: OccurrenceEventCategory.positiveIndication,
    timestamp: now,
    title: 'Indicação',
    description: 'K9 indicou odor alvo',
    photoUrls: const ['https://example.test/foto.jpg'],
    photoMetadata: [
      {'sha256': photoHash},
    ],
    gpsLat: -22.56,
    gpsLng: -47.4,
    createdAt: now,
    updatedAt: now,
  );
}
