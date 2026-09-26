import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:canil_gcm/features/health/domain/clinical_consultation_gateway.dart';
import 'package:canil_gcm/features/health/domain/dose_administration.dart';
import 'package:canil_gcm/features/health/domain/health_v1_enums_ext.dart';
import 'package:canil_gcm/features/health/domain/health_v1_models.dart';
import 'package:canil_gcm/features/health/domain/health_v1_value_objects.dart';
import 'package:canil_gcm/features/health/domain/treatment_protocol.dart';
import 'package:canil_gcm/features/health/domain/treatment_protocol_command.dart';
import 'package:canil_gcm/features/health/domain/treatment_protocol_gateway.dart';
import 'package:canil_gcm/features/health/presentation/clinical/treatment_execution_screen.dart';

class MockTreatmentProtocolGateway implements TreatmentProtocolGateway {
  List<ClinicalCaseOption> casesToReturn = [];
  List<TreatmentProtocol> protocolsToReturn = [];
  List<Map<String, dynamic>> schedulesToReturn = [];

  bool throwOnLoadCases = false;
  List<dynamic> recordedCommands = [];

  @override
  Future<List<ClinicalCaseOption>> loadUsableCases(String dogId) async {
    if (throwOnLoadCases) {
      throw Exception('Falha ao carregar casos clínicos');
    }
    return casesToReturn;
  }

  @override
  Future<List<TreatmentProtocol>> loadProtocols({
    required String dogId,
    String? caseId,
  }) async {
    return protocolsToReturn;
  }

  @override
  Stream<List<TreatmentProtocol>> watchProtocols({
    required String dogId,
    String? caseId,
  }) {
    return Stream.value(protocolsToReturn);
  }

  @override
  Future<List<DoseAdministration>> loadProtocolDoses({
    required String dogId,
    required String protocolId,
  }) async {
    return const [];
  }

  @override
  Stream<List<DoseAdministration>> watchProtocolDoses({
    required String dogId,
    required String protocolId,
  }) {
    return Stream.value(const []);
  }

  @override
  Stream<List<Map<String, dynamic>>> watchProtocolSchedules({
    required String dogId,
    required String protocolId,
  }) {
    return Stream.value(schedulesToReturn);
  }

  @override
  Future<TreatmentProtocolResult> createProtocol(
    CreateTreatmentProtocolCommand command,
  ) async {
    recordedCommands.add(command);
    throw UnimplementedError();
  }

  @override
  Future<TreatmentProtocolResult> pauseProtocol(
    PauseTreatmentProtocolCommand command,
  ) async {
    recordedCommands.add(command);
    throw UnimplementedError();
  }

  @override
  Future<TreatmentProtocolResult> resumeProtocol(
    ResumeTreatmentProtocolCommand command,
  ) async {
    recordedCommands.add(command);
    throw UnimplementedError();
  }

  @override
  Future<TreatmentProtocolResult> completeProtocol(
    CompleteTreatmentProtocolCommand command,
  ) async {
    recordedCommands.add(command);
    throw UnimplementedError();
  }

  @override
  Future<TreatmentProtocolResult> cancelProtocol(
    CancelTreatmentProtocolCommand command,
  ) async {
    recordedCommands.add(command);
    throw UnimplementedError();
  }

  @override
  Future<TreatmentProtocolResult> administerDose(
    AdministerDoseCommand command,
  ) async {
    recordedCommands.add(command);
    final dose = DoseAdministration(
      identity: DoseIdentity(
        protocolId: command.protocolId,
        plannedDoseId: command.plannedDoseId,
      ),
      protocolId: command.protocolId,
      dogId: command.dogId,
      scheduledFor: DateTime.now(),
      status: DoseStatus.administered,
      recordedBy: RecordedBy(uid: 'u1', name: 'Tester', internalRole: 'condutor'),
      recordedAt: DateTime.now(),
      schemaVersion: 1,
      administeredAt: DateTime.now(),
      observations: command.observations,
    );
    return DoseAdministrationSuccess(dose);
  }

  @override
  Future<TreatmentProtocolResult> skipDose(
    SkipDoseCommand command,
  ) async {
    recordedCommands.add(command);
    final dose = DoseAdministration(
      identity: DoseIdentity(
        protocolId: command.protocolId,
        plannedDoseId: command.plannedDoseId,
      ),
      protocolId: command.protocolId,
      dogId: command.dogId,
      scheduledFor: DateTime.now(),
      status: DoseStatus.skipped,
      recordedBy: RecordedBy(uid: 'u1', name: 'Tester', internalRole: 'condutor'),
      recordedAt: DateTime.now(),
      schemaVersion: 1,
      skipReason: command.skipReason,
      observations: command.observations,
    );
    return DoseAdministrationSuccess(dose);
  }
}

void main() {
  late MockTreatmentProtocolGateway mockGateway;

  setUp(() {
    mockGateway = MockTreatmentProtocolGateway();
  });

  Widget createWidget({String dogId = 'dog-1', String? caseId}) {
    return MaterialApp(
      home: TreatmentExecutionScreen(
        dogId: dogId,
        caseId: caseId,
        gateway: mockGateway,
      ),
    );
  }

  testWidgets('renders active protocol, next dose, and buttons with min 44px height', (
    tester,
  ) async {
    mockGateway.casesToReturn = [
      const ClinicalCaseOption(
        caseId: 'case-1',
        title: 'Caso Dermatite',
        statusWireName: 'open',
        revision: 1,
      ),
    ];

    final now = DateTime.utc(2026, 9, 5, 12);
    final protocol = TreatmentProtocol(
      id: 'proto-1',
      dogId: 'dog-1',
      caseId: 'case-1',
      medicationName: 'Cefalexina 500mg',
      dose: DoseBlock(
        value: 500,
        unit: DoseUnit.mg,
        perKg: false,
        route: DoseRoute.oral,
      ),
      schedule: ScheduleBlock(
        type: ScheduleTypeBlock.interval,
        intervalMinutes: 720,
        timezone: 'America/Sao_Paulo',
        toleranceMinutes: 30,
      ),
      startDate: now,
      durationDays: 14,
      recordedBy: RecordedBy(uid: 'u1', name: 'Vet', internalRole: 'veterinario'),
      professional: ProfessionalIdentity(
        name: 'Dra. Ana',
        registrationType: ProfessionalRegistrationType.crmv,
        registrationNumber: '12345',
        clinic: 'Clínica K9',
      ),
      sourceDocument: const HealthDocumentRef(healthDocumentId: 'doc-1'),
      status: TreatmentStatus.active,
      schemaVersion: 1,
      instructions: 'Administrar após refeição',
    );

    mockGateway.protocolsToReturn = [protocol];
    mockGateway.schedulesToReturn = [
      {
        'schedule_id': 'sch-1',
        'planned_dose_id': 'dose_0',
        'status': 'open',
        'scheduled_for': '2026-09-05T14:00:00Z',
      },
    ];

    await tester.pumpWidget(createWidget(caseId: 'case-1'));
    await tester.pumpAndSettle();

    // Verify Title and Active Medication
    expect(find.text('Tratamentos e Medicamentos'), findsOneWidget);
    expect(find.text('Cefalexina 500mg'), findsOneWidget);
    expect(find.text('Administrar após refeição'), findsOneWidget);
    expect(find.text('Tratamentos Ativos'), findsOneWidget);

    // Verify Action Buttons
    final adminBtnFinder = find.byKey(const ValueKey('administer_btn_proto-1'));
    final skipBtnFinder = find.byKey(const ValueKey('skip_btn_proto-1'));

    expect(adminBtnFinder, findsOneWidget);
    expect(skipBtnFinder, findsOneWidget);

    // Verify min touch target >= 44px
    final adminSize = tester.getSize(adminBtnFinder);
    expect(adminSize.height, greaterThanOrEqualTo(44.0));

    final skipSize = tester.getSize(skipBtnFinder);
    expect(skipSize.height, greaterThanOrEqualTo(44.0));
  });

  testWidgets('renders empty state when no cases are available', (tester) async {
    mockGateway.casesToReturn = [];

    await tester.pumpWidget(createWidget());
    await tester.pumpAndSettle();

    expect(find.text('Nenhum tratamento em andamento'), findsOneWidget);
  });

  testWidgets('renders empty state when case has no active protocols', (tester) async {
    mockGateway.casesToReturn = [
      const ClinicalCaseOption(
        caseId: 'case-1',
        title: 'Caso Monitoramento',
        statusWireName: 'open',
        revision: 1,
      ),
    ];
    mockGateway.protocolsToReturn = [];

    await tester.pumpWidget(createWidget(caseId: 'case-1'));
    await tester.pumpAndSettle();

    expect(find.text('Nenhum tratamento em andamento'), findsOneWidget);
  });

  testWidgets('renders error state when case loading fails', (tester) async {
    mockGateway.throwOnLoadCases = true;

    await tester.pumpWidget(createWidget());
    await tester.pumpAndSettle();

    expect(find.textContaining('Erro ao carregar casos clínicos'), findsOneWidget);
    expect(find.text('Tentar Novamente'), findsOneWidget);
  });

  testWidgets('tapping Administrar Dose opens administration confirmation dialog', (
    tester,
  ) async {
    mockGateway.casesToReturn = [
      const ClinicalCaseOption(
        caseId: 'case-1',
        title: 'Caso Dermatite',
        statusWireName: 'open',
        revision: 1,
      ),
    ];

    final now = DateTime.utc(2026, 9, 5, 12);
    mockGateway.protocolsToReturn = [
      TreatmentProtocol(
        id: 'proto-1',
        dogId: 'dog-1',
        caseId: 'case-1',
        medicationName: 'Amoxicilina',
        dose: DoseBlock(
          value: 250,
          unit: DoseUnit.mg,
          perKg: false,
          route: DoseRoute.oral,
        ),
        schedule: ScheduleBlock(
          type: ScheduleTypeBlock.interval,
          intervalMinutes: 720,
          timezone: 'America/Sao_Paulo',
          toleranceMinutes: 30,
        ),
        startDate: now,
        recordedBy: RecordedBy(uid: 'u1', name: 'Vet', internalRole: 'veterinario'),
        professional: ProfessionalIdentity(
          name: 'Dra. Ana',
          registrationType: ProfessionalRegistrationType.crmv,
          registrationNumber: '12345',
          clinic: 'Clínica K9',
        ),
        sourceDocument: const HealthDocumentRef(healthDocumentId: 'doc-1'),
        status: TreatmentStatus.active,
        schemaVersion: 1,
      ),
    ];
    mockGateway.schedulesToReturn = [
      {
        'schedule_id': 'sch-1',
        'planned_dose_id': 'dose_0',
        'status': 'open',
        'scheduled_for': '2026-09-05T14:00:00Z',
      },
    ];

    await tester.pumpWidget(createWidget(caseId: 'case-1'));
    await tester.pumpAndSettle();

    final adminBtnFinder = find.byKey(const ValueKey('administer_btn_proto-1'));
    await tester.tap(adminBtnFinder);
    await tester.pumpAndSettle();

    expect(find.text('Confirmar Administração de Dose'), findsOneWidget);
    expect(find.text('Confirmar Administração'), findsOneWidget);
  });

  testWidgets('tapping Pular Dose opens dialog requiring reason', (tester) async {
    mockGateway.casesToReturn = [
      const ClinicalCaseOption(
        caseId: 'case-1',
        title: 'Caso Dermatite',
        statusWireName: 'open',
        revision: 1,
      ),
    ];

    final now = DateTime.utc(2026, 9, 5, 12);
    mockGateway.protocolsToReturn = [
      TreatmentProtocol(
        id: 'proto-1',
        dogId: 'dog-1',
        caseId: 'case-1',
        medicationName: 'Amoxicilina',
        dose: DoseBlock(
          value: 250,
          unit: DoseUnit.mg,
          perKg: false,
          route: DoseRoute.oral,
        ),
        schedule: ScheduleBlock(
          type: ScheduleTypeBlock.interval,
          intervalMinutes: 720,
          timezone: 'America/Sao_Paulo',
          toleranceMinutes: 30,
        ),
        startDate: now,
        recordedBy: RecordedBy(uid: 'u1', name: 'Vet', internalRole: 'veterinario'),
        professional: ProfessionalIdentity(
          name: 'Dra. Ana',
          registrationType: ProfessionalRegistrationType.crmv,
          registrationNumber: '12345',
          clinic: 'Clínica K9',
        ),
        sourceDocument: const HealthDocumentRef(healthDocumentId: 'doc-1'),
        status: TreatmentStatus.active,
        schemaVersion: 1,
      ),
    ];
    mockGateway.schedulesToReturn = [
      {
        'schedule_id': 'sch-1',
        'planned_dose_id': 'dose_0',
        'status': 'open',
        'scheduled_for': '2026-09-05T14:00:00Z',
      },
    ];

    await tester.pumpWidget(createWidget(caseId: 'case-1'));
    await tester.pumpAndSettle();

    final skipBtnFinder = find.byKey(const ValueKey('skip_btn_proto-1'));
    await tester.tap(skipBtnFinder);
    await tester.pumpAndSettle();

    expect(find.text('Pular Dose de Tratamento'), findsOneWidget);
    expect(find.text('Motivo obrigatório *'), findsOneWidget);
    expect(find.text('Confirmar Dose Pulada'), findsOneWidget);

    // Tapping without entering reason triggers validation
    await tester.tap(find.text('Confirmar Dose Pulada'));
    await tester.pumpAndSettle();

    expect(find.text('O motivo é obrigatório para registrar dose pulada.'), findsOneWidget);
  });
}
