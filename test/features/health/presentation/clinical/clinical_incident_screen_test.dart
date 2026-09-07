import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:canil_gcm/features/health/domain/clinical_consultation_gateway.dart'
    show ClinicalCaseOption;
import 'package:canil_gcm/features/health/domain/clinical_incident_command.dart';
import 'package:canil_gcm/features/health/domain/clinical_incident_gateway.dart';
import 'package:canil_gcm/features/health/presentation/clinical/clinical_incident_screen.dart';

class FakeIncidentGateway implements ClinicalIncidentGateway {
  FakeIncidentGateway({this.usableCases = const []});

  final List<ClinicalCaseOption> usableCases;
  ClinicalIncidentCommand? savedCommand;

  @override
  Future<List<ClinicalCaseOption>> loadUsableCases(String dogId) async {
    return usableCases;
  }

  @override
  Future<IncidentSaveResult> saveIncident(ClinicalIncidentCommand command) async {
    savedCommand = command;
    return IncidentOpenedCase(
      dogId: command.dogId,
      caseId: 'case-123',
      eventId: 'event-123',
      wasNoOp: false,
      operationId: command.operationId,
    );
  }

  @override
  Future<IncidentSaveResult> retryFinalization(IncidentPendingFinalization pending) async {
    return IncidentOpenedCase(
      dogId: pending.dogId,
      caseId: pending.caseId,
      eventId: pending.eventId,
      wasNoOp: false,
      operationId: pending.finalizeOperationId,
    );
  }

  @override
  Future<List<ClinicalIncidentRecordView>> loadCaseIncidents({
    required String dogId,
    required String caseId,
  }) async {
    return [];
  }
}

void main() {
  testWidgets('ClinicalIncidentScreen renders all sections and submits successfully',
      (tester) async {
    final gateway = FakeIncidentGateway(
      usableCases: [
        const ClinicalCaseOption(
          caseId: 'case-existing-1',
          title: 'Acompanhamento Físico',
          statusWireName: 'open',
          revision: 1,
        ),
      ],
    );

    await tester.pumpWidget(
      MaterialApp(
        home: ClinicalIncidentScreen(
          dogId: 'dog-test-1',
          gateway: gateway,
        ),
      ),
    );

    await tester.pumpAndSettle();

    // Verify Title
    expect(find.text('Registrar Intercorrência'), findsNWidgets(2)); // AppBar + Button

    // Verify Categories
    expect(find.text('Trauma / Lesão'), findsOneWidget);
    expect(find.text('Intermação / Hipertermia'), findsOneWidget);

    // Select category
    await tester.tap(find.text('Trauma / Lesão'));
    await tester.pumpAndSettle();

    // Select severity
    await tester.tap(find.text('Moderada'));
    await tester.pumpAndSettle();

    // Enter description
    final descField = find.byType(TextField).first;
    await tester.enterText(descField, 'Corte superficial na orelha');
    await tester.pumpAndSettle();

    // Submit
    final submitButton = find.widgetWithText(ElevatedButton, 'Registrar Intercorrência');
    await tester.ensureVisible(submitButton);
    await tester.tap(submitButton);
    await tester.pumpAndSettle();

    expect(gateway.savedCommand, isNotNull);
    expect(gateway.savedCommand!.dogId, 'dog-test-1');
    expect(gateway.savedCommand!.category, IncidentCategory.trauma);
    expect(gateway.savedCommand!.severity, IncidentSeverity.moderate);
    expect(gateway.savedCommand!.description, 'Corte superficial na orelha');
  });
}
