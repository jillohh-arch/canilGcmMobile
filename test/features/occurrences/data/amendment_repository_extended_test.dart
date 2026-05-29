import 'package:flutter_test/flutter_test.dart';

import 'package:canil_gcm/core/domain/occurrence_signature.dart';
import 'package:canil_gcm/core/domain/occurrence_team_member.dart';
import 'package:canil_gcm/features/occurrences/domain/amendment.dart';

void main() {
  group('Amendment extended integrity', () {
    test('calcula SHA-256 deterministico do aditamento', () {
      final createdAt = DateTime.utc(2026, 5, 28, 12);
      final corrections = {
        'final_report': const AmendmentCorrection(
          oldValue: 'texto anterior',
          newValue: 'texto corrigido',
        ),
      };
      final integrityHash = Amendment.computeHash(
        occurrenceId: 'occ123',
        reason: 'Correcao de registro',
        corrections: corrections,
        createdBy: '12345',
        createdAt: createdAt,
        sequenceNumber: 1,
      );

      final amendment = Amendment(
        id: 'amd123',
        occurrenceId: 'occ123',
        reason: 'Correcao de registro',
        corrections: corrections,
        createdBy: '12345',
        createdByName: 'Condutor Teste',
        createdByRa: '12345',
        createdAt: createdAt,
        integrityHash: integrityHash,
        sequenceNumber: 1,
      );

      expect(amendment.integrityHash, hasLength(64));
      expect(
        Amendment.computeHash(
          occurrenceId: amendment.occurrenceId,
          reason: amendment.reason,
          corrections: amendment.corrections,
          createdBy: amendment.createdBy,
          createdAt: amendment.createdAt,
          sequenceNumber: amendment.sequenceNumber,
        ),
        amendment.integrityHash,
      );
    });

    test('serializacao de equipe e assinaturas ignora signature_hash', () {
      final addedAt = DateTime.utc(2026, 5, 28, 10);
      final signedAt = DateTime.utc(2026, 5, 28, 11);
      final team = [
        OccurrenceTeamMember(
          handlerId: '456',
          role: TeamRole.integrante,
          addedAt: addedAt,
          addedBy: '123',
        ),
        OccurrenceTeamMember(
          handlerId: '123',
          role: TeamRole.titular,
          addedAt: addedAt,
          addedBy: '123',
        ),
      ];
      final signatures = [
        OccurrenceSignature(
          handlerId: '456',
          status: SignatureStatus.signed,
          signedAt: signedAt,
          signatureMethod: SignatureMethod.biometric,
          signatureHash: 'hash-variavel',
        ),
      ];

      final serialized1 = _serializeForHash(team, signatures);
      final serialized2 = _serializeForHash(team, [
        signatures.first.copyWith(signatureHash: 'outro-hash'),
      ]);

      expect(serialized1, serialized2);
    });
  });
}

String _serializeForHash(
  List<OccurrenceTeamMember> team,
  List<OccurrenceSignature> signatures,
) {
  final orderedTeam = List<OccurrenceTeamMember>.from(team)
    ..sort((a, b) => a.handlerId.compareTo(b.handlerId));
  final orderedSignatures = List<OccurrenceSignature>.from(signatures)
    ..sort((a, b) => a.handlerId.compareTo(b.handlerId));

  return [
    for (final member in orderedTeam) member.toHashPayload().toString(),
    for (final signature in orderedSignatures)
      signature.toHashPayload().toString(),
  ].join('|');
}
