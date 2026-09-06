import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:canil_gcm/core/domain/occurrence_signature.dart';
import 'package:canil_gcm/core/domain/occurrence_team_member.dart';
import 'package:canil_gcm/core/services/notification_service.dart';
import 'package:canil_gcm/core/services/occurrence_finalization_service.dart';
import 'package:canil_gcm/features/occurrences/data/occurrence_repository.dart';
import 'package:canil_gcm/features/occurrences/data/signature_repository.dart';
import 'package:canil_gcm/features/occurrences/domain/occurrence.dart';
import 'package:canil_gcm/features/occurrences/domain/occurrence_status.dart';
import 'package:canil_gcm/features/occurrences/presentation/view_models/occurrence_finalization_view_model.dart';
import 'package:canil_gcm/features/occurrences/presentation/widgets/deadline_expired_dialog.dart';

class _MockOccurrenceRepository extends Mock implements OccurrenceRepository {}

class _MockSignatureRepository extends Mock implements SignatureRepository {}

class _MockFinalizationService extends Mock
    implements OccurrenceFinalizationService {}

class _MockNotificationService extends Mock implements NotificationService {}

class _FakeOccurrence extends Fake implements Occurrence {}

class _TestFinalizationViewModel extends OccurrenceFinalizationViewModel {
  _TestFinalizationViewModel({
    required super.occurrenceRepository,
    required super.signatureRepository,
    super.notificationService,
    super.finalizationService,
  });

  Occurrence? testOccurrence;
  List<OccurrenceSignature> testSignatures = [];
  List<OccurrenceTeamMember> testTeam = [];

  @override
  Occurrence? get occurrence => testOccurrence;

  @override
  List<OccurrenceSignature> get signatures => testSignatures;

  @override
  List<OccurrenceTeamMember> get team => testTeam;

  void Function(String)? pendingFinalizeSuccess;
  void Function(String)? pendingFinalizeError;
  void Function(String)? pendingRevertSuccess;
  void Function(String)? pendingRevertError;
  void Function(String)? pendingExtendSuccess;
  void Function(String)? pendingExtendError;

  @override
  Future<void> finalizeWithPending({
    required void Function(String) onSuccess,
    required void Function(String) onError,
  }) async {
    pendingFinalizeSuccess = onSuccess;
    pendingFinalizeError = onError;
  }

  @override
  Future<void> revertToDraft({
    required void Function(String) onSuccess,
    required void Function(String) onError,
  }) async {
    pendingRevertSuccess = onSuccess;
    pendingRevertError = onError;
  }

  @override
  Future<void> extendDeadline({
    required Duration extension,
    required void Function(String) onSuccess,
    required void Function(String) onError,
  }) async {
    pendingExtendSuccess = onSuccess;
    pendingExtendError = onError;
  }
}

void main() {
  late _MockOccurrenceRepository mockOccurrenceRepo;
  late _MockSignatureRepository mockSignatureRepo;
  late _MockFinalizationService mockFinalizationService;
  late _MockNotificationService mockNotificationService;
  late _TestFinalizationViewModel viewModel;

  setUpAll(() {
    registerFallbackValue(_FakeOccurrence());
  });

  setUp(() {
    mockOccurrenceRepo = _MockOccurrenceRepository();
    mockSignatureRepo = _MockSignatureRepository();
    mockFinalizationService = _MockFinalizationService();
    mockNotificationService = _MockNotificationService();

    when(
      () => mockFinalizationService.checkForAutoFinalization(any()),
    ).thenAnswer((_) async => false);
    when(
      () => mockFinalizationService.notifyDeadlineExpired(any()),
    ).thenAnswer((_) async {});

    viewModel = _TestFinalizationViewModel(
      occurrenceRepository: mockOccurrenceRepo,
      signatureRepository: mockSignatureRepo,
      finalizationService: mockFinalizationService,
      notificationService: mockNotificationService,
    );

    viewModel.testOccurrence = Occurrence(
      id: 'occ-123456789',
      shiftId: 'shift-1',
      primaryHandlerId: 'handler-1',
      primaryHandlerRa: '12345',
      dogId: 'dog-1',
      typeCode: 'TC',
      typeName: 'Type',
      startedAt: DateTime.now().subtract(const Duration(days: 2)),
      status: OccurrenceStatus.awaitingSignatures,
      createdAt: DateTime.now().subtract(const Duration(days: 2)),
      updatedAt: DateTime.now(),
      signatureDeadline: DateTime.now().subtract(const Duration(hours: 1)),
      team: [
        OccurrenceTeamMember(
          handlerId: 'ra-1',
          role: TeamRole.titular,
          addedAt: DateTime.now(),
          addedBy: '12345',
        ),
        OccurrenceTeamMember(
          handlerId: 'ra-2',
          role: TeamRole.integrante,
          addedAt: DateTime.now(),
          addedBy: '12345',
        ),
      ],
    );
    viewModel.testTeam = viewModel.testOccurrence!.team;
  });

  Widget buildTestApp(Widget child) {
    return MaterialApp(home: Scaffold(body: child));
  }

  group('DeadlineExpiredDialog runtime hygiene & lifecycle safety', () {
    testWidgets(
      'onSuccess shows feedback before popping dialog and leaves tree cleanly',
      (tester) async {
        await tester.pumpWidget(
          buildTestApp(
            Builder(
              builder: (context) {
                return ElevatedButton(
                  onPressed: () {
                    showDialog(
                      context: context,
                      builder: (_) =>
                          DeadlineExpiredDialog(viewModel: viewModel),
                    );
                  },
                  child: const Text('Open Dialog'),
                );
              },
            ),
          ),
        );

        // Open dialog
        await tester.tap(find.text('Open Dialog'));
        await tester.pumpAndSettle();

        expect(find.byType(DeadlineExpiredDialog), findsOneWidget);

        // Tap 'Finalizar com pendência'
        await tester.tap(find.text('Finalizar com pendência'));
        await tester.pump();

        expect(viewModel.pendingFinalizeSuccess, isNotNull);

        // Trigger onSuccess while dialog is mounted
        viewModel.pendingFinalizeSuccess!(
          'Ocorrência finalizada com pendências',
        );
        await tester.pumpAndSettle();

        // Dialog should now be popped cleanly
        expect(find.byType(DeadlineExpiredDialog), findsNothing);
        expect(
          find.text('Ocorrência finalizada com pendências'),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'onSuccess after dialog unmount aborts cleanly without throwing or setState after dispose',
      (tester) async {
        await tester.pumpWidget(
          buildTestApp(
            Builder(
              builder: (context) {
                return ElevatedButton(
                  onPressed: () {
                    showDialog(
                      context: context,
                      builder: (_) =>
                          DeadlineExpiredDialog(viewModel: viewModel),
                    );
                  },
                  child: const Text('Open Dialog'),
                );
              },
            ),
          ),
        );

        // Open dialog
        await tester.tap(find.text('Open Dialog'));
        await tester.pumpAndSettle();

        expect(find.byType(DeadlineExpiredDialog), findsOneWidget);

        // Tap 'Finalizar com pendência'
        await tester.tap(find.text('Finalizar com pendência'));
        await tester.pump();

        expect(viewModel.pendingFinalizeSuccess, isNotNull);

        // Dismiss the dialog externally before async callback finishes
        Navigator.of(tester.element(find.byType(DeadlineExpiredDialog))).pop();
        await tester.pumpAndSettle();

        expect(find.byType(DeadlineExpiredDialog), findsNothing);

        // Now complete the async callback after unmount
        expect(() {
          viewModel.pendingFinalizeSuccess!('Ocorrência finalizada tarde');
        }, returnsNormally);

        await tester.pumpAndSettle();
        // No unhandled exceptions or setState after dispose
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'onError after dialog unmount aborts cleanly without throwing or setState after dispose',
      (tester) async {
        await tester.pumpWidget(
          buildTestApp(
            Builder(
              builder: (context) {
                return ElevatedButton(
                  onPressed: () {
                    showDialog(
                      context: context,
                      builder: (_) =>
                          DeadlineExpiredDialog(viewModel: viewModel),
                    );
                  },
                  child: const Text('Open Dialog'),
                );
              },
            ),
          ),
        );

        // Open dialog
        await tester.tap(find.text('Open Dialog'));
        await tester.pumpAndSettle();

        expect(find.byType(DeadlineExpiredDialog), findsOneWidget);

        // Tap 'Aguardar mais 48h'
        await tester.tap(find.text('Aguardar mais 48h'));
        await tester.pump();

        expect(viewModel.pendingExtendError, isNotNull);

        // Dismiss the dialog externally before async callback finishes
        Navigator.of(tester.element(find.byType(DeadlineExpiredDialog))).pop();
        await tester.pumpAndSettle();

        expect(find.byType(DeadlineExpiredDialog), findsNothing);

        // Now complete the async callback after unmount
        expect(() {
          viewModel.pendingExtendError!('Erro simulado');
        }, returnsNormally);

        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'revertToDraft onSuccess shows feedback before popping dialog and leaves tree cleanly',
      (tester) async {
        await tester.pumpWidget(
          buildTestApp(
            Builder(
              builder: (context) {
                return ElevatedButton(
                  onPressed: () {
                    showDialog(
                      context: context,
                      builder: (_) =>
                          DeadlineExpiredDialog(viewModel: viewModel),
                    );
                  },
                  child: const Text('Open Dialog'),
                );
              },
            ),
          ),
        );

        await tester.tap(find.text('Open Dialog'));
        await tester.pumpAndSettle();

        await tester.tap(find.text('Voltar para draft'));
        await tester.pump();

        expect(viewModel.pendingRevertSuccess, isNotNull);

        viewModel.pendingRevertSuccess!('OK');
        await tester.pumpAndSettle();

        expect(find.byType(DeadlineExpiredDialog), findsNothing);
        expect(
          find.text('Ocorrência revertida para draft: OK'),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'extendDeadline onSuccess shows feedback before popping dialog and leaves tree cleanly',
      (tester) async {
        await tester.pumpWidget(
          buildTestApp(
            Builder(
              builder: (context) {
                return ElevatedButton(
                  onPressed: () {
                    showDialog(
                      context: context,
                      builder: (_) =>
                          DeadlineExpiredDialog(viewModel: viewModel),
                    );
                  },
                  child: const Text('Open Dialog'),
                );
              },
            ),
          ),
        );

        await tester.tap(find.text('Open Dialog'));
        await tester.pumpAndSettle();

        await tester.tap(find.text('Aguardar mais 48h'));
        await tester.pump();

        expect(viewModel.pendingExtendSuccess, isNotNull);

        viewModel.pendingExtendSuccess!('Prazo estendido por 48 horas');
        await tester.pumpAndSettle();

        expect(find.byType(DeadlineExpiredDialog), findsNothing);
        expect(find.text('Prazo estendido por 48 horas'), findsOneWidget);
      },
    );
  });
}
