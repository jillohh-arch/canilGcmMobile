import 'package:flutter_test/flutter_test.dart';
import 'package:canil_gcm/core/domain/occurrence_signature.dart';
import 'package:canil_gcm/core/domain/occurrence_team_member.dart';
import 'package:canil_gcm/features/occurrences/domain/occurrence_status.dart';

void main() {
  group('OccurrenceSignature Model', () {
    test('Should create OccurrenceSignature with default values', () {
      final signature = OccurrenceSignature(
        handlerId: 'handler123',
        status: SignatureStatus.pending,
        signatureMethod: SignatureMethod.biometric,
        signatureHash: 'hash123',
      );

      expect(signature.handlerId, 'handler123');
      expect(signature.status, SignatureStatus.pending);
      expect(signature.signatureMethod, SignatureMethod.biometric);
      expect(signature.signatureHash, 'hash123');
      expect(signature.signedAt, null);
      expect(signature.reason, null);
    });

    test('Should create OccurrenceSignature with all values', () {
      final signedAt = DateTime.now();
      final signature = OccurrenceSignature(
        handlerId: 'handler123',
        status: SignatureStatus.signed,
        signedAt: signedAt,
        signatureMethod: SignatureMethod.password,
        signatureHash: 'hash123',
        reason: 'Test reason',
      );

      expect(signature.handlerId, 'handler123');
      expect(signature.status, SignatureStatus.signed);
      expect(signature.signedAt, signedAt);
      expect(signature.signatureMethod, SignatureMethod.password);
      expect(signature.signatureHash, 'hash123');
      expect(signature.reason, 'Test reason');
    });

    test('Should convert to and from JSON', () {
      final original = OccurrenceSignature(
        handlerId: 'handler123',
        status: SignatureStatus.signed,
        signedAt: DateTime.now(),
        signatureMethod: SignatureMethod.biometric,
        signatureHash: 'hash123',
      );

      final json = original.toJson();
      final restored = OccurrenceSignature.fromJson(json);

      expect(restored.handlerId, original.handlerId);
      expect(restored.status, original.status);
      expect(restored.signedAt, original.signedAt);
      expect(restored.signatureMethod, original.signatureMethod);
      expect(restored.signatureHash, original.signatureHash);
    });

    test('Should copy with modifications', () {
      final original = OccurrenceSignature(
        handlerId: 'handler123',
        status: SignatureStatus.pending,
        signatureMethod: SignatureMethod.biometric,
        signatureHash: 'hash123',
      );

      final copied = original.copyWith(
        status: SignatureStatus.signed,
        reason: 'Test reason',
      );

      expect(copied.handlerId, original.handlerId);
      expect(copied.status, SignatureStatus.signed);
      expect(copied.signatureMethod, original.signatureMethod);
      expect(copied.signatureHash, original.signatureHash);
      expect(copied.reason, 'Test reason');
    });
  });

  group('OccurrenceTeamMember Model', () {
    test('Should create OccurrenceTeamMember', () {
      final addedAt = DateTime.now();
      final member = OccurrenceTeamMember(
        handlerId: 'handler123',
        role: TeamRole.integrante,
        addedAt: addedAt,
        addedBy: 'handler456',
      );

      expect(member.handlerId, 'handler123');
      expect(member.role, TeamRole.integrante);
      expect(member.addedAt, addedAt);
      expect(member.addedBy, 'handler456');
    });

    test('Should convert to and from JSON', () {
      final original = OccurrenceTeamMember(
        handlerId: 'handler123',
        role: TeamRole.titular,
        addedAt: DateTime.now(),
        addedBy: 'handler456',
      );

      final json = original.toJson();
      final restored = OccurrenceTeamMember.fromJson(json);

      expect(restored.handlerId, original.handlerId);
      expect(restored.role, original.role);
      expect(restored.addedAt, original.addedAt);
      expect(restored.addedBy, original.addedBy);
    });
  });

  group('OccurrenceStatus Model', () {
    test('Should have correct status values', () {
      expect(OccurrenceStatus.inProgress.toMap(), 'in_progress');
      expect(OccurrenceStatus.finalizing.toMap(), 'finalizing');
      expect(OccurrenceStatus.awaitingSignatures.toMap(), 'awaiting_signatures');
      expect(OccurrenceStatus.finalized.toMap(), 'finalized');
      expect(OccurrenceStatus.finalizedWithPending.toMap(), 'finalized_with_pending');
      expect(OccurrenceStatus.canceled.toMap(), 'canceled');
    });

    test('Should parse from string', () {
      expect(OccurrenceStatus.fromMap('in_progress'), OccurrenceStatus.inProgress);
      expect(OccurrenceStatus.fromMap('finalizing'), OccurrenceStatus.finalizing);
      expect(OccurrenceStatus.fromMap('awaiting_signatures'), OccurrenceStatus.awaitingSignatures);
      expect(OccurrenceStatus.fromMap('finalized'), OccurrenceStatus.finalized);
      expect(OccurrenceStatus.fromMap('finalized_with_pending'), OccurrenceStatus.finalizedWithPending);
      expect(OccurrenceStatus.fromMap('canceled'), OccurrenceStatus.canceled);
    });

    test('Should have correct open/closed status', () {
      expect(OccurrenceStatus.inProgress.isOpen, true);
      expect(OccurrenceStatus.finalizing.isOpen, true);
      expect(OccurrenceStatus.awaitingSignatures.isOpen, false);
      expect(OccurrenceStatus.finalized.isOpen, false);
      expect(OccurrenceStatus.finalizedWithPending.isOpen, false);
      expect(OccurrenceStatus.canceled.isOpen, false);

      expect(OccurrenceStatus.inProgress.isClosed, false);
      expect(OccurrenceStatus.finalizing.isClosed, false);
      expect(OccurrenceStatus.awaitingSignatures.isClosed, false);
      expect(OccurrenceStatus.finalized.isClosed, true);
      expect(OccurrenceStatus.finalizedWithPending.isClosed, true);
      expect(OccurrenceStatus.canceled.isClosed, true);
    });
  });
}