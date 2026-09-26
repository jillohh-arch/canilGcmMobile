import 'dart:convert';

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:canil_gcm/core/domain/occurrence_participation.dart';
import 'package:canil_gcm/core/domain/occurrence_signature.dart';
import 'package:canil_gcm/core/domain/occurrence_team_member.dart';
import 'package:canil_gcm/core/services/integrity_verification_service.dart';
import 'package:canil_gcm/core/services/occurrence_finalization_service.dart';
import 'package:canil_gcm/features/occurrences/domain/occurrence.dart';
import 'package:canil_gcm/features/occurrences/domain/occurrence_event.dart';
import 'package:canil_gcm/features/occurrences/domain/occurrence_event_category.dart';
import 'package:canil_gcm/features/occurrences/domain/occurrence_result.dart';

/// FF-OCC-09: `verifyById` passou a obter o estado documental do verificador
/// oficial. Os testes que o exercitam injetam a resposta autoritativa para
/// permanecerem herméticos — nenhuma requisição real é feita.
MockClient _authoritativeClient({
  required String occurrenceId,
  required String storedHash,
  required int hashVersion,
  String status = 'intact',
  bool documentIntact = true,
}) {
  return MockClient((_) async {
    return http.Response(
      jsonEncode({
        'occurrence_id': occurrenceId,
        'status': status,
        'sealed': true,
        'intact': documentIntact,
        'document_intact': documentIntact,
        'stored_hash': storedHash,
        'hash_version': hashVersion,
      }),
      200,
      headers: const {'content-type': 'application/json'},
    );
  });
}

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

    test('verificacao profunda detecta midia divergente sem quebrar o selo '
        'documental', () async {
      final db = FakeFirebaseFirestore();
      final event = _event(photoHash: 'foto-a');
      final base = _occurrence();
      final hash = OccurrenceFinalizationService.calculateIntegrityHashV2For(
        base,
        events: [event],
      );
      final sealed = base.copyWith(integrityHash: hash, hashVersion: 2);
      await db.collection('occurrences').doc(sealed.id).set(sealed.toMap());
      await db
          .collection('occurrences')
          .doc(sealed.id)
          .collection('events')
          .doc(event.id)
          .set(event.toMap());

      final service = IntegrityVerificationService(
        firestore: db,
        httpClient: _authoritativeClient(
          occurrenceId: sealed.id,
          storedHash: hash,
          hashVersion: 2,
        ),
        mediaHashReader: (_, {int maxBytes = 20 * 1024 * 1024}) async =>
            'foto-trocada',
      );

      final verdict = await service.verifyById(
        sealed.id,
        verifyMediaBytes: true,
      );

      // FF-OCC-09: o documento continua integro segundo a autoridade; a
      // divergencia de midia e reportada pelo canal proprio.
      expect(verdict.status, IntegrityStatus.intact);
      expect(verdict.checkedMediaCount, 1);
      expect(verdict.mediaIssues.single, contains('SHA-256'));
    });

    test('verificacao profunda mantem selo quando bytes conferem', () async {
      final db = FakeFirebaseFirestore();
      final event = _event(photoHash: 'foto-a');
      final base = _occurrence();
      final hash = OccurrenceFinalizationService.calculateIntegrityHashV2For(
        base,
        events: [event],
      );
      final sealed = base.copyWith(integrityHash: hash, hashVersion: 2);
      await db.collection('occurrences').doc(sealed.id).set(sealed.toMap());
      await db
          .collection('occurrences')
          .doc(sealed.id)
          .collection('events')
          .doc(event.id)
          .set(event.toMap());

      final service = IntegrityVerificationService(
        firestore: db,
        httpClient: _authoritativeClient(
          occurrenceId: sealed.id,
          storedHash: hash,
          hashVersion: 2,
        ),
        mediaHashReader: (_, {int maxBytes = 20 * 1024 * 1024}) async =>
            'foto-a',
      );

      final verdict = await service.verifyById(
        sealed.id,
        verifyMediaBytes: true,
      );

      expect(verdict.status, IntegrityStatus.intact);
      expect(verdict.checkedMediaCount, 1);
      expect(verdict.mediaIssues, isEmpty);
    });

    test('participacao v4 preserva status aceito no payload do hash', () {
      final participation = OccurrenceParticipation.fromJson({
        'handler_id': '123',
        'status': 'accepted',
        'at': '2026-05-29T10:00:00.000Z',
        'updated_by': '123',
      });

      expect(participation.status, OccurrenceParticipationStatus.accepted);
      expect(participation.toHashPayload()['status'], 'accepted');
    });

    test('hash canonico ignora duplicatas em arrays como a Function', () {
      final base = _occurrence().copyWith(
        results: const [
          OccurrenceResult.drugSeized,
          OccurrenceResult.drugSeized,
        ],
        finalizationPhotos: const [
          ' https://example.test/final.jpg ',
          'https://example.test/final.jpg',
        ],
        finalizationPhotoHashes: const [' final-hash ', 'final-hash'],
        acceptedHandlerIds: const ['123', '123'],
      );
      final canonical = _occurrence().copyWith(
        finalizationPhotos: const ['https://example.test/final.jpg'],
        finalizationPhotoHashes: const ['final-hash'],
        acceptedHandlerIds: const ['123'],
      );
      final duplicatedEvent = _eventWithPhotoUrls(
        photoHash: 'foto-a',
        photoUrls: const [
          ' https://example.test/foto.jpg ',
          'https://example.test/foto.jpg',
        ],
      );
      final canonicalEvent = _eventWithPhotoUrls(
        photoHash: 'foto-a',
        photoUrls: const ['https://example.test/foto.jpg'],
      );

      final duplicatedHash =
          OccurrenceFinalizationService.calculateIntegrityHashV4For(
            base,
            events: [duplicatedEvent],
          );
      final canonicalHash =
          OccurrenceFinalizationService.calculateIntegrityHashV4For(
            canonical,
            events: [canonicalEvent],
          );

      expect(duplicatedHash, canonicalHash);
    });

    test('hash canonico ignora eventos soft-deletados como a Function', () {
      final occurrence = _occurrence();
      final activeEvent = _event(id: 'event-1', photoHash: 'foto-a');
      final deletedEvent = _event(
        id: 'event-2',
        photoHash: 'foto-removida',
      ).copyWith(deletedAt: DateTime.utc(2026, 5, 29, 12));

      final withDeleted =
          OccurrenceFinalizationService.calculateIntegrityHashV4For(
            occurrence,
            events: [activeEvent, deletedEvent],
          );
      final withoutDeleted =
          OccurrenceFinalizationService.calculateIntegrityHashV4For(
            occurrence,
            events: [activeEvent],
          );

      expect(withDeleted, withoutDeleted);
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
        status: OccurrenceParticipationStatus.accepted,
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
  return _eventWithPhotoUrls(
    id: id,
    photoHash: photoHash,
    photoUrls: const ['https://example.test/foto.jpg'],
  );
}

OccurrenceEvent _eventWithPhotoUrls({
  String id = 'event-1',
  required String photoHash,
  required List<String> photoUrls,
}) {
  final now = DateTime.utc(2026, 5, 29, 11);
  return OccurrenceEvent(
    id: id,
    occurrenceId: 'occ-1',
    category: OccurrenceEventCategory.positiveIndication,
    timestamp: now,
    title: 'Indicação',
    description: 'K9 indicou odor alvo',
    photoUrls: photoUrls,
    photoMetadata: [
      {'sha256': photoHash},
    ],
    gpsLat: -22.56,
    gpsLng: -47.4,
    createdAt: now,
    updatedAt: now,
  );
}
