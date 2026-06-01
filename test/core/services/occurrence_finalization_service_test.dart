import 'package:flutter_test/flutter_test.dart';

import 'package:canil_gcm/core/domain/occurrence_participation.dart';
import 'package:canil_gcm/core/domain/occurrence_signature.dart';
import 'package:canil_gcm/core/domain/occurrence_team_member.dart';
import 'package:canil_gcm/core/services/occurrence_finalization_service.dart';
import 'package:canil_gcm/features/occurrences/domain/occurrence.dart';
import 'package:canil_gcm/features/occurrences/domain/occurrence_event.dart';
import 'package:canil_gcm/features/occurrences/domain/occurrence_event_category.dart';
import 'package:canil_gcm/features/occurrences/domain/occurrence_result.dart';

void main() {
  group('OccurrenceFinalizationService hash v3', () {
    test('inclui eventos, equipe e assinaturas sem signature_hash', () {
      final occurrence = _occurrence(
        signatures: [
          OccurrenceSignature(
            handlerId: '456',
            status: SignatureStatus.signed,
            signedAt: DateTime.utc(2026, 5, 29, 12),
            signatureMethod: SignatureMethod.biometric,
            signatureHash: 'hash-variavel',
          ),
        ],
      );
      final events = [_event(photoHash: 'foto-a')];

      final hash = OccurrenceFinalizationService.calculateIntegrityHashV3For(
        occurrence,
        events: events,
      );
      final sameWithoutSignatureHash =
          OccurrenceFinalizationService.calculateIntegrityHashV3For(
            _occurrence(
              signatures: [
                occurrence.signatures.first.copyWith(
                  signatureHash: 'outro-hash-variavel',
                ),
              ],
            ),
            events: events,
          );
      final changedEvent =
          OccurrenceFinalizationService.calculateIntegrityHashV3For(
            occurrence,
            events: [_event(photoHash: 'foto-b')],
          );

      expect(hash, hasLength(64));
      expect(sameWithoutSignatureHash, hash);
      expect(changedEvent, isNot(hash));
    });

    test('ordena resultados e eventos de forma deterministica', () {
      final signatures = [
        OccurrenceSignature(
          handlerId: '456',
          status: SignatureStatus.signed,
          signedAt: DateTime.utc(2026, 5, 29, 12),
          signatureMethod: SignatureMethod.biometric,
        ),
      ];
      final occurrence = _occurrence(
        signatures: signatures,
        results: const [
          OccurrenceResult.weaponSeized,
          OccurrenceResult.drugSeized,
        ],
      );
      final reorderedOccurrence = _occurrence(
        signatures: signatures,
        results: const [
          OccurrenceResult.drugSeized,
          OccurrenceResult.weaponSeized,
        ],
      );
      final events = [
        _event(id: 'event-2', photoHash: 'foto-b'),
        _event(id: 'event-1', photoHash: 'foto-a'),
      ];

      final hash = OccurrenceFinalizationService.calculateIntegrityHashV3For(
        occurrence,
        events: events,
      );
      final reorderedHash =
          OccurrenceFinalizationService.calculateIntegrityHashV3For(
            reorderedOccurrence,
            events: events.reversed.toList(),
          );

      expect(reorderedHash, hash);
    });

    test('hash v4 inclui participacoes sem alterar v3 legado', () {
      final occurrence =
          _occurrence(
            signatures: [
              OccurrenceSignature(
                handlerId: '456',
                status: SignatureStatus.signed,
                signedAt: DateTime.utc(2026, 5, 29, 12),
                signatureMethod: SignatureMethod.biometric,
              ),
            ],
          ).copyWith(
            crewId: 'crew-1075',
            serviceDogId: 'dog-1',
            signatureRound: 1,
            participationStatus: 'accepted',
            acceptedHandlerIds: const ['123', '456'],
            declinedHandlerIds: const [],
            pendingHandlerIds: const [],
            editAuthorizedHandlerIds: const ['123', '456'],
            participationRevision: 1,
            participations: [
              OccurrenceParticipation(
                handlerId: '123',
                status: OccurrenceParticipationStatus.accepted,
                at: DateTime.utc(2026, 5, 29, 10),
                updatedBy: '123',
              ),
              OccurrenceParticipation(
                handlerId: '456',
                status: OccurrenceParticipationStatus.accepted,
                at: DateTime.utc(2026, 5, 29, 10),
                updatedBy: '123',
              ),
            ],
          );
      final events = [_event(photoHash: 'foto-a')];

      final hashV3 = OccurrenceFinalizationService.calculateIntegrityHashV3For(
        occurrence,
        events: events,
      );
      final hashV4 = OccurrenceFinalizationService.calculateIntegrityHashV4For(
        occurrence,
        events: events,
      );
      final declined = occurrence.copyWith(
        declinedHandlerIds: const ['456'],
        acceptedHandlerIds: const ['123'],
        participations: [
          occurrence.participations.first,
          OccurrenceParticipation(
            handlerId: '456',
            status: OccurrenceParticipationStatus.declined,
            declineReason: 'Nao estava no local',
            at: DateTime.utc(2026, 5, 29, 10),
            updatedBy: '456',
          ),
        ],
      );
      final declinedHash =
          OccurrenceFinalizationService.calculateIntegrityHashV4For(
            declined,
            events: events,
          );

      expect(hashV4, hasLength(64));
      expect(hashV4, isNot(hashV3));
      expect(declinedHash, isNot(hashV4));
    });
  });
}

Occurrence _occurrence({
  required List<OccurrenceSignature> signatures,
  List<OccurrenceResult> results = const [OccurrenceResult.drugSeized],
}) {
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
    results: results,
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
      OccurrenceTeamMember(
        handlerId: '456',
        role: TeamRole.integrante,
        addedAt: now,
        addedBy: '123',
      ),
    ],
    signatures: signatures,
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
