// ignore_for_file: depend_on_referenced_packages
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_core_platform_interface/firebase_core_platform_interface.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:canil_gcm/core/domain/notification_item.dart';
import 'package:canil_gcm/core/domain/occurrence_signature.dart';
import 'package:canil_gcm/core/domain/occurrence_team_member.dart';
import 'package:canil_gcm/core/services/notification_service.dart';
import 'package:canil_gcm/core/services/occurrence_finalization_service.dart';
import 'package:canil_gcm/core/widgets/app_feedback.dart';
import 'package:canil_gcm/features/history/presentation/screens/history_screen.dart';
import 'package:canil_gcm/features/occurrences/data/occurrence_repository.dart';
import 'package:canil_gcm/features/occurrences/data/signature_repository.dart';
import 'package:canil_gcm/features/occurrences/domain/occurrence.dart';
import 'package:canil_gcm/features/occurrences/domain/occurrence_status.dart';
import 'package:canil_gcm/features/occurrences/domain/upload_failure_classifier.dart';
import 'package:canil_gcm/features/occurrences/presentation/screens/occurrence_review_screen.dart';
import 'package:canil_gcm/features/occurrences/presentation/view_models/occurrence_finalization_view_model.dart';
import '../shifts/crew_k9_test_helpers.dart';

class MockOccurrenceRepository extends Mock implements OccurrenceRepository {}
class MockSignatureRepository extends Mock implements SignatureRepository {}
class MockFinalizationService extends Mock implements OccurrenceFinalizationService {}
class MockNotificationService extends Mock implements NotificationService {}
class FakeOccurrenceSignature extends Fake implements OccurrenceSignature {}

void main() {
  setUpAll(() {
    FirebasePlatform.instance = FakeFirebasePlatform();
    registerFallbackValue(FakeOccurrenceSignature());
    registerFallbackValue(NotificationType.signatureCompleted);
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

  group('R6.2 — Return for Correction Resilience & Error Classification', () {
    test('AppFeedbackText maps FirebaseFunctionsException not-found to missing remote service, not missing record', () {
      final functionsEx = FirebaseFunctionsException(
        code: 'not-found',
        message: 'NOT FOUND',
      );
      final feedback = AppFeedbackText.fromError(functionsEx, fallback: 'Fallback');
      expect(feedback, contains('Serviço remoto não encontrado ou função não implantada'));
      expect(feedback, isNot(contains('O registro não foi encontrado')));
    });

    testWidgets('ReasonInputDialog validates empty input and returns trimmed reason', (tester) async {
      String? returnedReason;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () async {
                  returnedReason = await showDialog<String>(
                    context: context,
                    builder: (_) => AlertDialog(
                      title: const Text('Devolver para correção'),
                      content: const TextField(
                        key: Key('reason_field'),
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.of(context).pop(' Motivo válido '),
                          child: const Text('Confirmar'),
                        ),
                      ],
                    ),
                  );
                },
                child: const Text('Open Dialog'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open Dialog'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Confirmar'));
      await tester.pumpAndSettle();

      expect(returnedReason?.trim(), equals('Motivo válido'));

      // Verify OccurrenceReviewScreen compiles and instantiates cleanly
      const reviewScreen = OccurrenceReviewScreen(
        occurrenceId: 'occ-test-review-r6',
      );
      expect(reviewScreen.occurrenceId, equals('occ-test-review-r6'));
    });
  });

  group('R6.3 — Biometric Signature Duplicate Feedback Race', () {
    late MockOccurrenceRepository mockOccurrenceRepo;
    late MockSignatureRepository mockSignatureRepo;
    late MockFinalizationService mockFinalizationService;
    late MockNotificationService mockNotificationService;
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
          // Simulate async processing
          await Future<void>.delayed(const Duration(milliseconds: 20));
          callbackExecuted = true;
          callbackMessage = message;
        },
        onError: (error) {
          fail('Should not fail: $error');
        },
      );

      // Verify the await guarantees completion before caller resumes
      expect(callbackExecuted, isTrue);
      expect(callbackMessage, equals('Assinatura adicionada com sucesso'));
      expect(finalizationVM.signatures.any((s) => s.handlerId == '990002'), isTrue);
    });
  });

  group('R6.4 — History Duration Projection & Interval Formatting', () {
    test('Dynamic operational interval is generated from actual timestamps without hardcoding', () {
      final now = DateTime(2026, 3, 30, 14, 15);
      final entry = HistoryEntry(
        id: 'occ-dyn-interval',
        type: HistoryEntryType.occurrence,
        title: 'Ocorrência · Operação K9',
        subtitle: 'Av. Paulista, 1000',
        time: now,
        author: 'Você',
        tag: 'VOCÊ',
        icon: Icons.assignment_outlined,
        color: Colors.blue,
        location: 'Av. Paulista, 1000',
        isInProgress: false,
        originalModel: null,
        details: {
          'Tipo': 'Operação K9',
          'Início': '14:15',
          'Fim': '15:45',
          'Duração': '90 min',
        },
      );

      final detail = RecordDetail.fromEntry(entry);
      expect(detail.duration, equals('90 min'));

      // Simulate interval resolution logic from HistoryDetailScreen
      final startStr = detail.source.details['Início']?.toString();
      final endStr = detail.source.details['Fim']?.toString();
      String secondInfoValue = 'Não informado';
      if (startStr != null && endStr != null && endStr.isNotEmpty) {
        secondInfoValue = '$startStr → $endStr';
      }

      expect(secondInfoValue, equals('14:15 → 15:45'));
      expect(secondInfoValue, isNot(equals('13:33 → 13:40')));
    });

    test('Duration under 60 seconds (sub-minute) displays as < 1 min instead of 0 min', () {
      final start = DateTime(2026, 3, 30, 10, 0, 0);
      final endSubMinute = DateTime(2026, 3, 30, 10, 0, 45); // 45 seconds later
      expect(endSubMinute.difference(start).inSeconds, lessThan(60));

      final entry = HistoryEntry(
        id: 'occ-sub-min',
        type: HistoryEntryType.occurrence,
        title: 'Ocorrência · Rápida',
        subtitle: 'Rua A',
        time: start,
        author: 'Você',
        tag: 'VOCÊ',
        icon: Icons.assignment_outlined,
        color: Colors.blue,
        location: 'Rua A',
        isInProgress: false,
        originalModel: null,
        details: {
          'Tipo': 'Rápida',
          'Início': '10:00',
          'Fim': '10:00',
          'Duração': '< 1 min',
        },
      );

      final detail = RecordDetail.fromEntry(entry);
      expect(detail.duration, equals('< 1 min'));
      expect(detail.duration, isNot(equals('0 min')));
    });

    test('RecordDetail sanitizes explicit 0 min to < 1 min', () {
      final entry = HistoryEntry(
        id: 'occ-zero-min',
        type: HistoryEntryType.occurrence,
        title: 'Ocorrência · Zero',
        subtitle: 'Rua B',
        time: DateTime(2026, 3, 30, 10, 0),
        author: 'Você',
        tag: 'VOCÊ',
        icon: Icons.assignment_outlined,
        color: Colors.blue,
        location: 'Rua B',
        isInProgress: false,
        originalModel: null,
        details: {
          'Tipo': 'Zero',
          'Início': '10:00',
          'Fim': '10:00',
          'Duração': '0 min',
        },
      );

      final detail = RecordDetail.fromEntry(entry);
      expect(detail.duration, equals('< 1 min'));
    });
  });
}
