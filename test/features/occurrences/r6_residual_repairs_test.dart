// ignore_for_file: depend_on_referenced_packages
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_core_platform_interface/firebase_core_platform_interface.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_auth/local_auth.dart';
import 'package:mocktail/mocktail.dart';

import 'package:canil_gcm/core/domain/notification_item.dart';
import 'package:canil_gcm/core/domain/occurrence_signature.dart';
import 'package:canil_gcm/core/domain/occurrence_team_member.dart';
import 'package:canil_gcm/core/services/notification_service.dart';
import 'package:canil_gcm/core/services/occurrence_finalization_service.dart';
import 'package:canil_gcm/core/services/occurrence_transition_service.dart';
import 'package:canil_gcm/core/widgets/app_feedback.dart';
import 'package:canil_gcm/features/history/presentation/screens/history_screen.dart';
import 'package:canil_gcm/features/occurrences/data/occurrence_event_repository.dart';
import 'package:canil_gcm/features/occurrences/data/occurrence_repository.dart';
import 'package:canil_gcm/features/occurrences/data/signature_repository.dart';
import 'package:canil_gcm/features/occurrences/domain/occurrence.dart';
import 'package:canil_gcm/features/occurrences/domain/occurrence_status.dart';
import 'package:canil_gcm/features/occurrences/domain/upload_failure_classifier.dart';
import 'package:canil_gcm/features/occurrences/presentation/screens/occurrence_review_screen.dart';
import 'package:canil_gcm/features/occurrences/presentation/view_models/occurrence_finalization_view_model.dart';
import 'package:canil_gcm/features/occurrences/presentation/view_models/occurrence_team_view_model.dart';
import 'package:canil_gcm/features/occurrences/presentation/widgets/signature_confirmation_dialog.dart';
import '../shifts/crew_k9_test_helpers.dart';

class MockOccurrenceRepository extends Mock implements OccurrenceRepository {}
class MockSignatureRepository extends Mock implements SignatureRepository {}
class MockOccurrenceEventRepository extends Mock implements OccurrenceEventRepository {}
class MockOccurrenceTransitionService extends Mock implements OccurrenceTransitionService {}
class MockFinalizationService extends Mock implements OccurrenceFinalizationService {}
class MockNotificationService extends Mock implements NotificationService {}
class MockLocalAuthentication extends Mock implements LocalAuthentication {}
class FakeOccurrenceSignature extends Fake implements OccurrenceSignature {}
class FakeOccurrenceTeamMember extends Fake implements OccurrenceTeamMember {}

void main() {
  setUpAll(() {
    FirebasePlatform.instance = FakeFirebasePlatform();
    registerFallbackValue(FakeOccurrenceSignature());
    registerFallbackValue(FakeOccurrenceTeamMember());
    registerFallbackValue(NotificationType.signatureCompleted);
    registerFallbackValue(const AuthenticationOptions());
  });

  group('R6.1 — Storage Upload Resilience & Error Classification', () {
    test('Classifies object-not-found as permanent upload failure with descriptive message', () {
      final notFoundException = FirebaseException(
        plugin: 'firebase_storage',
        code: 'object-not-found',
        message: 'No such object or bucket',
      );

      final classification = UploadFailureClassifier.classify(notFoundException);
      expect(classification, equals(UploadFailureType.permanent));
      expect(UploadFailureClassifier.isRecoverable(notFoundException), isFalse);

      final friendlyMsg = UploadFailureClassifier.getFriendlyMessage(notFoundException);
      expect(friendlyMsg, contains('Repositório de arquivos não encontrado no servidor de nuvem'));
    });

    test('AppFeedbackText translates storage object-not-found correctly', () {
      final storageEx = FirebaseException(
        plugin: 'firebase_storage',
        code: 'object-not-found',
      );
      final feedback = AppFeedbackText.fromError(storageEx, fallback: 'Fallback');
      expect(feedback, contains('armazenamento em nuvem'));
    });
  });

  group('R6.2 — Return for Correction Navigation & Error Classification', () {
    test('AppFeedbackText maps FirebaseFunctionsException not-found to missing remote service, not missing record', () {
      final functionsEx = FirebaseFunctionsException(
        code: 'not-found',
        message: 'NOT FOUND',
      );
      final feedback = AppFeedbackText.fromError(functionsEx, fallback: 'Fallback');
      expect(feedback, contains('Serviço remoto não encontrado ou função não implantada'));
      expect(feedback, isNot(contains('O registro não foi encontrado')));
    });

    Occurrence createReviewOccurrence({
      required OccurrenceStatus status,
      String primaryRa = '990001',
      List<OccurrenceTeamMember>? team,
    }) {
      return Occurrence(
        id: 'occ-r6-2',
        shiftId: 'shift-1',
        primaryHandlerId: primaryRa,
        primaryHandlerRa: primaryRa,
        dogId: 'dog-1',
        typeCode: 'apoio',
        typeName: 'Apoio Policial',
        status: status,
        createdAt: DateTime(2026, 3, 30, 10, 0),
        startedAt: DateTime(2026, 3, 30, 10, 0),
        updatedAt: DateTime(2026, 3, 30, 10, 0),
        signatureRound: 1,
        team: team ?? [
          OccurrenceTeamMember(
            handlerId: primaryRa,
            role: TeamRole.titular,
            displayName: 'Titular',
            addedAt: DateTime(2026, 3, 30, 10, 0),
            addedBy: primaryRa,
          ),
          OccurrenceTeamMember(
            handlerId: '990002',
            role: TeamRole.integrante,
            displayName: 'Integrante Auxiliar',
            addedAt: DateTime(2026, 3, 30, 10, 0),
            addedBy: primaryRa,
          ),
        ],
      );
    }

    testWidgets('accepted + unsigned -> open Devolver -> validation -> valid reason -> transition invocation -> pop with returned_for_correction (no _dependents crash)', (tester) async {
      final mockOccRepo = MockOccurrenceRepository();
      final mockSigRepo = MockSignatureRepository();
      final mockEventRepo = MockOccurrenceEventRepository();
      final mockTransition = MockOccurrenceTransitionService();
      final mockFinalizationService = MockFinalizationService();

      final occ = createReviewOccurrence(status: OccurrenceStatus.awaitingSignatures);
      when(() => mockOccRepo.getById('occ-r6-2')).thenAnswer((_) async => occ);
      when(() => mockEventRepo.listByOccurrence('occ-r6-2')).thenAnswer((_) async => []);
      when(() => mockSigRepo.getSignatures('occ-r6-2')).thenAnswer((_) async => [
        OccurrenceSignature(
          handlerId: '990002',
          status: SignatureStatus.pending,
          signedAt: DateTime(2026, 3, 30, 10, 0),
          signatureMethod: SignatureMethod.biometric,
        ),
      ]);
      when(() => mockTransition.requestCorrection(
        occurrenceId: any(named: 'occurrenceId'),
        reason: any(named: 'reason'),
      )).thenAnswer((_) async {});
      when(() => mockFinalizationService.checkForAutoFinalization(any()))
          .thenAnswer((_) async => false);

      final teamVM = OccurrenceFinalizationViewModel(
        occurrenceRepository: mockOccRepo,
        signatureRepository: mockSigRepo,
        notificationService: MockNotificationService(),
        finalizationService: mockFinalizationService,
      );

      dynamic poppedResult;

      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () async {
                poppedResult = await Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => OccurrenceReviewScreen(
                      occurrenceId: 'occ-r6-2',
                      occurrenceRepository: mockOccRepo,
                      eventRepository: mockEventRepo,
                      signatureRepository: mockSigRepo,
                      transitionService: mockTransition,
                      teamViewModel: teamVM,
                      currentHandlerRa: '990002',
                    ),
                  ),
                );
              },
              child: const Text('Open Review'),
            ),
          ),
        ),
      );

      // Open OccurrenceReviewScreen
      await tester.tap(find.text('Open Review'));
      await tester.pumpAndSettle();

      // Find Devolver button
      final devolverButton = find.widgetWithText(OutlinedButton, 'Devolver');
      expect(devolverButton, findsOneWidget);

      // Tap Devolver to open dialog
      await tester.tap(devolverButton);
      await tester.pumpAndSettle();

      // Empty reason validation check
      expect(find.text('Devolver para correção'), findsOneWidget);
      final confirmDevolverButton = find.widgetWithText(FilledButton, 'Devolver');
      await tester.tap(confirmDevolverButton);
      await tester.pumpAndSettle();

      expect(find.text('Informe o motivo da devolução.'), findsOneWidget);
      verifyNever(() => mockTransition.requestCorrection(
        occurrenceId: any(named: 'occurrenceId'),
        reason: any(named: 'reason'),
      ));

      // Enter valid reason
      await tester.enterText(find.byType(TextField), '  Ajustar descrição dos fatos  ');
      await tester.tap(confirmDevolverButton);
      await tester.pumpAndSettle();

      // Transition invocation verified with trimmed reason
      verify(() => mockTransition.requestCorrection(
        occurrenceId: 'occ-r6-2',
        reason: 'Ajustar descrição dos fatos',
      )).called(1);

      // Deterministic landing: screen popped with returned_for_correction
      expect(poppedResult, equals('returned_for_correction'));
      expect(find.text('Open Review'), findsOneWidget);
    });

    testWidgets('signed -> no Devolver action available', (tester) async {
      final mockOccRepo = MockOccurrenceRepository();
      final mockSigRepo = MockSignatureRepository();
      final mockEventRepo = MockOccurrenceEventRepository();
      final mockTransition = MockOccurrenceTransitionService();
      final mockFinalizationService = MockFinalizationService();

      final occ = createReviewOccurrence(status: OccurrenceStatus.awaitingSignatures);
      when(() => mockOccRepo.getById('occ-r6-2')).thenAnswer((_) async => occ);
      when(() => mockEventRepo.listByOccurrence('occ-r6-2')).thenAnswer((_) async => []);
      when(() => mockSigRepo.getSignatures('occ-r6-2')).thenAnswer((_) async => [
        OccurrenceSignature(
          handlerId: '990002',
          status: SignatureStatus.signed,
          signedAt: DateTime(2026, 3, 30, 10, 0),
          signatureMethod: SignatureMethod.biometric,
        ),
      ]);
      when(() => mockFinalizationService.checkForAutoFinalization(any()))
          .thenAnswer((_) async => false);

      final teamVM = OccurrenceFinalizationViewModel(
        occurrenceRepository: mockOccRepo,
        signatureRepository: mockSigRepo,
        notificationService: MockNotificationService(),
        finalizationService: mockFinalizationService,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: OccurrenceReviewScreen(
            occurrenceId: 'occ-r6-2',
            occurrenceRepository: mockOccRepo,
            eventRepository: mockEventRepo,
            signatureRepository: mockSigRepo,
            transitionService: mockTransition,
            teamViewModel: teamVM,
            currentHandlerRa: '990002',
          ),
        ),
      );
      await tester.pumpAndSettle();

      final devolverButton = find.widgetWithText(OutlinedButton, 'Devolver');
      if (devolverButton.evaluate().isNotEmpty) {
        final button = tester.widget<OutlinedButton>(devolverButton);
        expect(button.onPressed, isNull);
      } else {
        expect(devolverButton, findsNothing);
      }
    });

    testWidgets('sealed -> no Devolver action available', (tester) async {
      final mockOccRepo = MockOccurrenceRepository();
      final mockSigRepo = MockSignatureRepository();
      final mockEventRepo = MockOccurrenceEventRepository();
      final mockTransition = MockOccurrenceTransitionService();
      final mockFinalizationService = MockFinalizationService();

      final occ = createReviewOccurrence(status: OccurrenceStatus.finalized);
      when(() => mockOccRepo.getById('occ-r6-2')).thenAnswer((_) async => occ);
      when(() => mockEventRepo.listByOccurrence('occ-r6-2')).thenAnswer((_) async => []);
      when(() => mockSigRepo.getSignatures('occ-r6-2')).thenAnswer((_) async => []);
      when(() => mockFinalizationService.checkForAutoFinalization(any()))
          .thenAnswer((_) async => false);

      final teamVM = OccurrenceFinalizationViewModel(
        occurrenceRepository: mockOccRepo,
        signatureRepository: mockSigRepo,
        notificationService: MockNotificationService(),
        finalizationService: mockFinalizationService,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: OccurrenceReviewScreen(
            occurrenceId: 'occ-r6-2',
            occurrenceRepository: mockOccRepo,
            eventRepository: mockEventRepo,
            signatureRepository: mockSigRepo,
            transitionService: mockTransition,
            teamViewModel: teamVM,
            currentHandlerRa: '990002',
          ),
        ),
      );
      await tester.pumpAndSettle();

      final devolverButton = find.widgetWithText(OutlinedButton, 'Devolver');
      if (devolverButton.evaluate().isNotEmpty) {
        final button = tester.widget<OutlinedButton>(devolverButton);
        expect(button.onPressed, isNull);
      } else {
        expect(devolverButton, findsNothing);
      }
    });

    testWidgets('titular -> no Devolver action available', (tester) async {
      final mockOccRepo = MockOccurrenceRepository();
      final mockSigRepo = MockSignatureRepository();
      final mockEventRepo = MockOccurrenceEventRepository();
      final mockTransition = MockOccurrenceTransitionService();
      final mockFinalizationService = MockFinalizationService();

      final occ = createReviewOccurrence(status: OccurrenceStatus.awaitingSignatures);
      when(() => mockOccRepo.getById('occ-r6-2')).thenAnswer((_) async => occ);
      when(() => mockEventRepo.listByOccurrence('occ-r6-2')).thenAnswer((_) async => []);
      when(() => mockSigRepo.getSignatures('occ-r6-2')).thenAnswer((_) async => []);
      when(() => mockFinalizationService.checkForAutoFinalization(any()))
          .thenAnswer((_) async => false);

      final teamVM = OccurrenceFinalizationViewModel(
        occurrenceRepository: mockOccRepo,
        signatureRepository: mockSigRepo,
        notificationService: MockNotificationService(),
        finalizationService: mockFinalizationService,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: OccurrenceReviewScreen(
            occurrenceId: 'occ-r6-2',
            occurrenceRepository: mockOccRepo,
            eventRepository: mockEventRepo,
            signatureRepository: mockSigRepo,
            transitionService: mockTransition,
            teamViewModel: teamVM,
            currentHandlerRa: '990001', // Titular
          ),
        ),
      );
      await tester.pumpAndSettle();

      final devolverButton = find.widgetWithText(OutlinedButton, 'Devolver');
      if (devolverButton.evaluate().isNotEmpty) {
        final button = tester.widget<OutlinedButton>(devolverButton);
        expect(button.onPressed, isNull);
      } else {
        expect(devolverButton, findsNothing);
      }
    });
  });

  group('R6.3 — Biometric Signature Async Race & Duplicate Protection', () {
    late MockOccurrenceRepository mockOccurrenceRepo;
    late MockSignatureRepository mockSignatureRepo;
    late MockFinalizationService mockFinalizationService;
    late MockNotificationService mockNotificationService;
    late MockLocalAuthentication mockLocalAuth;
    late OccurrenceTeamViewModel teamVM;
    late OccurrenceFinalizationViewModel finalizationVM;

    final testOccurrence = Occurrence(
      id: 'occ-r6-3',
      shiftId: 'shift-1',
      primaryHandlerId: '990001',
      primaryHandlerRa: '990001',
      dogId: 'dog-1',
      typeCode: 'apoio',
      typeName: 'Apoio Policial',
      status: OccurrenceStatus.awaitingSignatures,
      createdAt: DateTime(2026, 3, 30, 10, 0),
      startedAt: DateTime(2026, 3, 30, 10, 0),
      updatedAt: DateTime(2026, 3, 30, 10, 0),
      signatureRound: 1,
      team: [
        OccurrenceTeamMember(
          handlerId: '990001',
          role: TeamRole.titular,
          displayName: 'Titular',
          addedAt: DateTime(2026, 3, 30, 10, 0),
          addedBy: '990001',
        ),
        OccurrenceTeamMember(
          handlerId: '990002',
          role: TeamRole.integrante,
          displayName: 'Auxiliar',
          addedAt: DateTime(2026, 3, 30, 10, 0),
          addedBy: '990001',
        ),
      ],
    );

    setUp(() async {
      mockOccurrenceRepo = MockOccurrenceRepository();
      mockSignatureRepo = MockSignatureRepository();
      mockFinalizationService = MockFinalizationService();
      mockNotificationService = MockNotificationService();
      mockLocalAuth = MockLocalAuthentication();

      when(() => mockLocalAuth.canCheckBiometrics).thenAnswer((_) async => true);
      when(() => mockLocalAuth.isDeviceSupported()).thenAnswer((_) async => true);
      when(() => mockLocalAuth.authenticate(
        localizedReason: any(named: 'localizedReason'),
        options: any(named: 'options'),
      )).thenAnswer((_) async => true);

      when(() => mockFinalizationService.checkForAutoFinalization(any()))
          .thenAnswer((_) async => false);
      when(() => mockOccurrenceRepo.getById('occ-r6-3'))
          .thenAnswer((_) async => testOccurrence);
      when(() => mockSignatureRepo.getSignatures('occ-r6-3'))
          .thenAnswer((_) async => []);
      when(() => mockOccurrenceRepo.addSignature(
            occurrenceId: any(named: 'occurrenceId'),
            signature: any(named: 'signature'),
          )).thenAnswer((_) async {});
      when(() => mockNotificationService.createNotification(
            userId: any(named: 'userId'),
            type: any(named: 'type'),
            occurrenceId: any(named: 'occurrenceId'),
            occurrenceTitle: any(named: 'occurrenceTitle'),
            additionalData: any(named: 'additionalData'),
          )).thenAnswer((_) async => 'notif-1');

      teamVM = OccurrenceTeamViewModel(
        occurrenceRepository: mockOccurrenceRepo,
        signatureRepository: mockSignatureRepo,
        notificationService: mockNotificationService,
      );
      await teamVM.initialize(occurrenceId: 'occ-r6-3');

      finalizationVM = OccurrenceFinalizationViewModel(
        occurrenceRepository: mockOccurrenceRepo,
        signatureRepository: mockSignatureRepo,
        notificationService: mockNotificationService,
        finalizationService: mockFinalizationService,
      );
      await finalizationVM.initialize(occurrenceId: 'occ-r6-3');
    });

    test('addSignature awaits onSuccess properly in OccurrenceFinalizationViewModel hierarchy', () async {
      final signature = OccurrenceSignature(
        handlerId: '990002',
        status: SignatureStatus.signed,
        signedAt: DateTime.now().toUtc(),
        signatureMethod: SignatureMethod.biometric,
        signatureHash: 'hash-abc-123',
      );

      when(() => mockSignatureRepo.getSignatures('occ-r6-3'))
          .thenAnswer((_) async => [signature]);

      bool callbackExecuted = false;
      String? callbackMessage;

      await finalizationVM.addSignature(
        signature: signature,
        onSuccess: (message) async {
          await Future<void>.delayed(const Duration(milliseconds: 20));
          callbackExecuted = true;
          callbackMessage = message;
        },
        onError: (error) {
          fail('Should not fail: $error');
        },
      );

      expect(callbackExecuted, isTrue);
      expect(callbackMessage, equals('Assinatura adicionada com sucesso'));
      expect(finalizationVM.signatures.any((s) => s.handlerId == '990002'), isTrue);
    });

    testWidgets('Exact physical-equivalent async race ordering (10 steps) succeeds without false duplicate emission', (tester) async {
      int writeCallCount = 0;
      bool dialogSuccessTriggered = false;

      when(() => mockOccurrenceRepo.addSignature(
        occurrenceId: any(named: 'occurrenceId'),
        signature: any(named: 'signature'),
      )).thenAnswer((invocation) async {
        writeCallCount++;
        final signature = invocation.namedArguments[#signature] as OccurrenceSignature;
        // Step 4: Stream/Repo publishes the newly created signature
        when(() => mockSignatureRepo.getSignatures('occ-r6-3'))
            .thenAnswer((_) async => [signature]);
      });

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SignatureConfirmationDialog(
              occurrence: testOccurrence,
              viewModel: teamVM,
              localAuth: mockLocalAuth,
              currentHandlerRa: '990002',
              onSuccess: () {
                dialogSuccessTriggered = true;
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Step 1: Local signing begins - tap biometric button
      final biometricButton = find.text('Assinar com biometria');
      expect(biometricButton, findsOneWidget);

      // Step 2 & 3: Tap triggers biometric authenticate (returns true) and write begins
      await tester.tap(biometricButton);

      // Step 4: Stream publishes newly created signature
      // Step 5: High-level onSuccess has NOT completed yet
      await tester.pump();

      // Step 6: UI MUST NOT emit "já assinada" or "Você já assinou"
      expect(find.textContaining('já assinou'), findsNothing);
      expect(find.textContaining('já assinada'), findsNothing);
      expect(find.textContaining('Esta ocorrência já foi assinada'), findsNothing);

      // Step 7: onSuccess completes
      await tester.pumpAndSettle();

      // Step 8: Exactly one success
      expect(find.text('Assinatura realizada'), findsOneWidget);
      expect(find.text('Assinatura adicionada com sucesso'), findsOneWidget);

      // Step 9: No duplicate error
      expect(find.textContaining('já assinada'), findsNothing);

      // Step 10: Exactly one write was performed
      expect(writeCallCount, equals(1));
      verify(() => mockOccurrenceRepo.addSignature(
        occurrenceId: 'occ-r6-3',
        signature: any(named: 'signature'),
      )).called(1);

      // Tap OK to complete dialog flow
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      expect(dialogSuccessTriggered, isTrue);
    });

    testWidgets('Pre-existing signed state before operation provides deterministic duplicate protection', (tester) async {
      // Setup occurrence with pre-existing signed state for handler 990002
      final preSigned = OccurrenceSignature(
        handlerId: '990002',
        status: SignatureStatus.signed,
        signedAt: DateTime(2026, 3, 30, 9, 30),
        signatureMethod: SignatureMethod.biometric,
        signatureHash: 'pre-existing-hash-111',
      );

      when(() => mockSignatureRepo.getSignatures('occ-r6-3'))
          .thenAnswer((_) async => [preSigned]);

      await teamVM.initialize(occurrenceId: 'occ-r6-3');

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SignatureConfirmationDialog(
              occurrence: testOccurrence,
              viewModel: teamVM,
              localAuth: mockLocalAuth,
              currentHandlerRa: '990002',
              onSuccess: () {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Deterministic duplicate protection: warning is displayed
      expect(find.text('Esta ocorrência já foi assinada por este usuário'), findsOneWidget);

      // Verify that no repository write was performed
      verifyNever(() => mockOccurrenceRepo.addSignature(
        occurrenceId: any(named: 'occurrenceId'),
        signature: any(named: 'signature'),
      ));
    });
  });

  group('R6.4 — History Duration Projection & Physical Case (13:33 -> 13:40)', () {
    test('13:33 -> 13:40 yields ~7 min duration (NEVER 0 min) and same canonical timestamp pair', () {
      final start = DateTime(2026, 3, 30, 13, 33, 0);
      final end = DateTime(2026, 3, 30, 13, 40, 0);

      final occ = Occurrence(
        id: 'occ-physical-case',
        shiftId: 'shift-1',
        primaryHandlerId: '990001',
        dogId: 'dog-1',
        typeCode: 'apoio',
        typeName: 'Apoio K9',
        status: OccurrenceStatus.finalized,
        startedAt: start,
        createdAt: start,
        updatedAt: end,
        finalizedAt: end,
        durationTotal: 0, // In physical test, durationTotal was 0 in Firestore
      );

      final entry = OccurrenceHistoryBuilder.buildEntry(
        occ,
        isYou: true,
        author: 'Você',
      );

      final detail = RecordDetail.fromEntry(entry);

      // Exact assertion: 7 min, never 0 min
      expect(detail.duration, equals('7 min'));
      expect(detail.duration, isNot(equals('0 min')));

      // Prove displayed start/end and displayed duration derive from the SAME canonical timestamp pair
      expect(entry.details['Início'], equals('13:33'));
      expect(entry.details['Fim'], equals('13:40'));

      final startFormatted = entry.details['Início'] as String;
      final endFormatted = entry.details['Fim'] as String;
      final interval = '$startFormatted → $endFormatted';

      expect(interval, equals('13:33 → 13:40'));
      expect(entry.time, equals(start));
    });

    test('Table-driven duration and interval projection matrix', () {
      final testCases = <Map<String, dynamic>>[
        {
          'name': 'Physical R4 test case (13:33 -> 13:40)',
          'start': DateTime(2026, 3, 30, 13, 33, 0),
          'end': DateTime(2026, 3, 30, 13, 40, 0),
          'status': OccurrenceStatus.finalized,
          'durationTotal': 0,
          'expectedDuration': '7 min',
          'expectedInterval': '13:33 → 13:40',
        },
        {
          'name': 'Sub-minute (45 seconds difference)',
          'start': DateTime(2026, 3, 30, 10, 0, 0),
          'end': DateTime(2026, 3, 30, 10, 0, 45),
          'status': OccurrenceStatus.finalized,
          'durationTotal': null,
          'expectedDuration': '< 1 min',
          'expectedInterval': '10:00 → 10:00',
        },
        {
          'name': 'Zero interval (0 seconds)',
          'start': DateTime(2026, 3, 30, 10, 0, 0),
          'end': DateTime(2026, 3, 30, 10, 0, 0),
          'status': OccurrenceStatus.finalized,
          'durationTotal': 0,
          'expectedDuration': '< 1 min',
          'expectedInterval': '10:00 → 10:00',
        },
        {
          'name': 'Cross-hour interval (13:58 -> 14:05)',
          'start': DateTime(2026, 3, 30, 13, 58, 0),
          'end': DateTime(2026, 3, 30, 14, 5, 0),
          'status': OccurrenceStatus.finalized,
          'durationTotal': null,
          'expectedDuration': '7 min',
          'expectedInterval': '13:58 → 14:05',
        },
        {
          'name': 'Cross-midnight interval (23:55 -> 00:08 next day)',
          'start': DateTime(2026, 3, 30, 23, 55, 0),
          'end': DateTime(2026, 3, 31, 0, 8, 0),
          'status': OccurrenceStatus.finalized,
          'durationTotal': null,
          'expectedDuration': '13 min',
          'expectedInterval': '23:55 → 00:08',
        },
        {
          'name': 'Missing finalized timestamp (in progress occurrence)',
          'start': DateTime(2026, 3, 30, 14, 0, 0),
          'end': null,
          'status': OccurrenceStatus.inProgress,
          'durationTotal': null,
          'expectedDuration': 'Em andamento',
          'expectedInterval': '14:00 → Em andamento',
        },
      ];

      for (final tc in testCases) {
        final occ = Occurrence(
          id: 'occ-${tc['name']}',
          shiftId: 'shift-1',
          primaryHandlerId: '990001',
          dogId: 'dog-1',
          typeCode: 'apoio',
          typeName: 'Apoio K9',
          status: tc['status'] as OccurrenceStatus,
          startedAt: tc['start'] as DateTime,
          createdAt: tc['start'] as DateTime,
          updatedAt: (tc['end'] as DateTime?) ?? (tc['start'] as DateTime),
          finalizedAt: tc['end'] as DateTime?,
          durationTotal: tc['durationTotal'] as int?,
        );

        final entry = OccurrenceHistoryBuilder.buildEntry(occ, isYou: true);
        final detail = RecordDetail.fromEntry(entry);

        expect(
          detail.duration,
          equals(tc['expectedDuration']),
          reason: 'Failed for ${tc['name']}',
        );

        final startStr = entry.details['Início']?.toString() ?? '';
        final endStr = entry.details['Fim']?.toString();
        final actualInterval = endStr != null
            ? '$startStr → $endStr'
            : (entry.isInProgress ? '$startStr → Em andamento' : startStr);

        expect(
          actualInterval,
          equals(tc['expectedInterval']),
          reason: 'Interval mismatch for ${tc['name']}',
        );
      }
    });

    test('Occurrence initialized from Firestore Timestamp objects correctly resolves duration & interval', () {
      final start = DateTime(2026, 3, 30, 13, 33, 0);
      final end = DateTime(2026, 3, 30, 13, 40, 0);

      final rawFirestoreMap = {
        'shift_id': 'shift-1',
        'primary_handler_id': '990001',
        'dog_id': 'dog-1',
        'type_code': 'apoio',
        'type_name': 'Apoio Policial',
        'status': 'finalized',
        'started_at': Timestamp.fromDate(start),
        'finalized_at': Timestamp.fromDate(end),
        'duration_total': 0,
      };

      final occ = Occurrence.fromMap(rawFirestoreMap, 'occ-firestore-timestamp');
      expect(occ.startedAt, equals(start));
      expect(occ.finalizedAt, equals(end));

      final entry = OccurrenceHistoryBuilder.buildEntry(occ, isYou: true);
      final detail = RecordDetail.fromEntry(entry);

      expect(detail.duration, equals('7 min'));
      expect(detail.duration, isNot(equals('0 min')));

      final startStr = entry.details['Início']?.toString();
      final endStr = entry.details['Fim']?.toString();
      expect('$startStr → $endStr', equals('13:33 → 13:40'));
    });
  });
}
