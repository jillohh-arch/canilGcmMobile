import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:canil_gcm/core/domain/occurrence_signature.dart';
import 'package:canil_gcm/core/domain/occurrence_team_member.dart';
import 'package:canil_gcm/core/services/notification_service.dart';
import 'package:canil_gcm/core/services/occurrence_finalization_service.dart';
import 'package:canil_gcm/features/occurrences/domain/occurrence.dart';
import 'package:canil_gcm/features/occurrences/domain/occurrence_status.dart';
import 'package:canil_gcm/features/occurrences/presentation/view_models/occurrence_finalization_view_model.dart';
import 'package:canil_gcm/features/occurrences/data/occurrence_repository.dart';
import 'package:canil_gcm/features/occurrences/data/signature_repository.dart';

class MockOccurrenceRepository extends Mock implements OccurrenceRepository {}

class MockSignatureRepository extends Mock implements SignatureRepository {}

class MockFinalizationService extends Mock
    implements OccurrenceFinalizationService {}

class MockNotificationService extends Mock implements NotificationService {}

class FakeOccurrenceSignature extends Fake implements OccurrenceSignature {}

class FakeOccurrence extends Fake implements Occurrence {}

/// Tests for the redirect-after-final-co-signature fix.
///
/// Verifies that [OccurrenceFinalizationViewModel.isFinalized] correctly
/// reports finalization state, which the UI uses to trigger navigation
/// to OccurrenceConfirmationScreen.
void main() {
  late MockOccurrenceRepository mockOccurrenceRepo;
  late MockSignatureRepository mockSignatureRepo;
  late MockFinalizationService mockFinalizationService;
  late MockNotificationService mockNotificationService;
  late OccurrenceFinalizationViewModel viewModel;

  setUpAll(() {
    registerFallbackValue(FakeOccurrenceSignature());
    registerFallbackValue(FakeOccurrence());
  });

  setUp(() {
    mockOccurrenceRepo = MockOccurrenceRepository();
    mockSignatureRepo = MockSignatureRepository();
    mockFinalizationService = MockFinalizationService();
    mockNotificationService = MockNotificationService();

    // Default stubs for finalization service
    when(
      () => mockFinalizationService.checkForAutoFinalization(any()),
    ).thenAnswer((_) async => false);
    when(
      () => mockFinalizationService.notifyDeadlineExpired(any()),
    ).thenAnswer((_) async {});

    viewModel = OccurrenceFinalizationViewModel(
      occurrenceRepository: mockOccurrenceRepo,
      signatureRepository: mockSignatureRepo,
      finalizationService: mockFinalizationService,
      notificationService: mockNotificationService,
    );
  });

  tearDown(() {
    viewModel.dispose();
  });

  Occurrence makeOccurrence({
    OccurrenceStatus status = OccurrenceStatus.awaitingSignatures,
    List<OccurrenceTeamMember>? team,
  }) {
    return Occurrence(
      id: 'occ-1',
      shiftId: 'shift-1',
      primaryHandlerId: 'handler-1',
      primaryHandlerRa: '12345',
      dogId: 'dog-1',
      typeCode: 'busca',
      typeName: 'Busca',
      startedAt: DateTime(2026, 7, 10, 8, 0),
      createdAt: DateTime(2026, 7, 10, 8, 0),
      updatedAt: DateTime(2026, 7, 10, 8, 0),
      status: status,
      team:
          team ??
          [
            OccurrenceTeamMember(
              handlerId: '12345',
              role: TeamRole.titular,
              addedAt: DateTime(2026, 7, 10),
              addedBy: '12345',
            ),
            OccurrenceTeamMember(
              handlerId: '67890',
              role: TeamRole.integrante,
              addedAt: DateTime(2026, 7, 10),
              addedBy: '12345',
            ),
          ],
    );
  }

  group('isFinalized', () {
    test('returns false when occurrence is null', () {
      expect(viewModel.isFinalized, isFalse);
    });

    test('returns false when status is awaitingSignatures', () async {
      final occ = makeOccurrence(status: OccurrenceStatus.awaitingSignatures);
      when(
        () => mockOccurrenceRepo.getById('occ-1'),
      ).thenAnswer((_) async => occ);
      when(
        () => mockSignatureRepo.getSignatures('occ-1'),
      ).thenAnswer((_) async => []);

      await viewModel.initialize(occurrenceId: 'occ-1');

      expect(viewModel.isFinalized, isFalse);
    });

    test('returns false when status is inProgress', () async {
      final occ = makeOccurrence(status: OccurrenceStatus.inProgress);
      when(
        () => mockOccurrenceRepo.getById('occ-1'),
      ).thenAnswer((_) async => occ);
      when(
        () => mockSignatureRepo.getSignatures('occ-1'),
      ).thenAnswer((_) async => []);

      await viewModel.initialize(occurrenceId: 'occ-1');

      expect(viewModel.isFinalized, isFalse);
    });

    test('returns true when status is finalized', () async {
      final occ = makeOccurrence(status: OccurrenceStatus.finalized);
      when(
        () => mockOccurrenceRepo.getById('occ-1'),
      ).thenAnswer((_) async => occ);
      when(
        () => mockSignatureRepo.getSignatures('occ-1'),
      ).thenAnswer((_) async => []);

      await viewModel.initialize(occurrenceId: 'occ-1');

      expect(viewModel.isFinalized, isTrue);
    });

    test('returns true when status is finalizedWithPending', () async {
      final occ = makeOccurrence(status: OccurrenceStatus.finalizedWithPending);
      when(
        () => mockOccurrenceRepo.getById('occ-1'),
      ).thenAnswer((_) async => occ);
      when(
        () => mockSignatureRepo.getSignatures('occ-1'),
      ).thenAnswer((_) async => []);

      await viewModel.initialize(occurrenceId: 'occ-1');

      expect(viewModel.isFinalized, isTrue);
    });
  });

  group('listener notification on finalization', () {
    test('notifies listeners when status changes to finalized', () async {
      // Initial: awaiting signatures
      final occAwaiting = makeOccurrence(
        status: OccurrenceStatus.awaitingSignatures,
      );
      when(
        () => mockOccurrenceRepo.getById('occ-1'),
      ).thenAnswer((_) async => occAwaiting);
      when(
        () => mockSignatureRepo.getSignatures('occ-1'),
      ).thenAnswer((_) async => []);

      await viewModel.initialize(occurrenceId: 'occ-1');
      expect(viewModel.isFinalized, isFalse);

      // Simulate: auto-finalization causes reload with finalized status
      final occFinalized = makeOccurrence(status: OccurrenceStatus.finalized);
      when(
        () => mockOccurrenceRepo.getById('occ-1'),
      ).thenAnswer((_) async => occFinalized);

      bool wasNotified = false;
      viewModel.addListener(() {
        wasNotified = true;
      });

      await viewModel.initialize(occurrenceId: 'occ-1');

      expect(wasNotified, isTrue);
      expect(viewModel.isFinalized, isTrue);
    });

    test('does not report finalized on signature error', () async {
      final occ = makeOccurrence(status: OccurrenceStatus.awaitingSignatures);
      when(
        () => mockOccurrenceRepo.getById('occ-1'),
      ).thenAnswer((_) async => occ);
      when(
        () => mockSignatureRepo.getSignatures('occ-1'),
      ).thenAnswer((_) async => []);

      await viewModel.initialize(occurrenceId: 'occ-1');

      // Attempt to add signature that fails
      when(
        () => mockOccurrenceRepo.addSignature(
          occurrenceId: any(named: 'occurrenceId'),
          signature: any(named: 'signature'),
        ),
      ).thenThrow(Exception('Network error'));

      String? errorMsg;
      await viewModel.addSignature(
        signature: OccurrenceSignature(
          handlerId: '67890',
          status: SignatureStatus.signed,
          signedAt: DateTime.now(),
          signatureMethod: SignatureMethod.biometric,
        ),
        onSuccess: (_) {},
        onError: (e) => errorMsg = e,
      );

      expect(errorMsg, isNotNull);
      expect(viewModel.isFinalized, isFalse);
    });
  });

  group('navigation guard (double-navigation prevention)', () {
    test('multiple initializations with finalized status '
        'still report isFinalized consistently', () async {
      final occ = makeOccurrence(status: OccurrenceStatus.finalized);
      when(
        () => mockOccurrenceRepo.getById('occ-1'),
      ).thenAnswer((_) async => occ);
      when(
        () => mockSignatureRepo.getSignatures('occ-1'),
      ).thenAnswer((_) async => []);

      int notifyCount = 0;
      viewModel.addListener(() => notifyCount++);

      await viewModel.initialize(occurrenceId: 'occ-1');
      expect(viewModel.isFinalized, isTrue);

      await viewModel.initialize(occurrenceId: 'occ-1');
      expect(viewModel.isFinalized, isTrue);

      // The UI uses _hasNavigatedToConfirmation to prevent double navigation;
      // the ViewModel just consistently reports the state.
      expect(notifyCount, greaterThan(0));
    });
  });

  group('still-pending scenario', () {
    test('remains not finalized when signatures still pending', () async {
      final occ = makeOccurrence(status: OccurrenceStatus.awaitingSignatures);
      when(
        () => mockOccurrenceRepo.getById('occ-1'),
      ).thenAnswer((_) async => occ);
      when(() => mockSignatureRepo.getSignatures('occ-1')).thenAnswer(
        (_) async => [
          OccurrenceSignature(
            handlerId: '67890',
            status: SignatureStatus.pending,
            signedAt: null,
            signatureMethod: SignatureMethod.biometric,
          ),
        ],
      );

      await viewModel.initialize(occurrenceId: 'occ-1');

      expect(viewModel.isFinalized, isFalse);
      expect(viewModel.areAllSignaturesCollected, isFalse);
    });
  });
}
