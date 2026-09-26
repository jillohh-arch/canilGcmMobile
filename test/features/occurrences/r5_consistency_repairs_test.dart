// ignore_for_file: depend_on_referenced_packages
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:provider/provider.dart';

import 'package:canil_gcm/core/domain/notification_item.dart';
import 'package:canil_gcm/core/services/notification_service.dart';
import 'package:canil_gcm/features/history/presentation/screens/history_screen.dart';
import 'package:canil_gcm/features/occurrences/domain/occurrence_event.dart';
import 'package:canil_gcm/features/occurrences/domain/occurrence_event_category.dart';
import 'package:canil_gcm/core/domain/occurrence_signature.dart';
import 'package:canil_gcm/features/occurrences/domain/occurrence_status.dart';
import 'package:canil_gcm/core/domain/occurrence_team_member.dart';
import 'package:canil_gcm/features/occurrences/presentation/widgets/active_occurrence_event_card.dart';
import 'package:canil_gcm/features/shifts/domain/active_shift_session.dart';
import 'package:canil_gcm/features/shifts/domain/vehicle.dart';
import 'package:canil_gcm/features/shifts/domain/vehicle_crew.dart';
import 'package:canil_gcm/features/shifts/presentation/screens/vehicle_crew_post_sheet.dart';
import 'package:canil_gcm/features/shifts/presentation/viewmodels/shift_viewmodel.dart';
import 'package:canil_gcm/features/auth/presentation/viewmodels/auth_viewmodel.dart';
import 'package:canil_gcm/features/users/presentation/viewmodels/user_viewmodel.dart';
import 'package:canil_gcm/features/dogs/presentation/viewmodels/dog_viewmodel.dart';
import 'package:firebase_core_platform_interface/firebase_core_platform_interface.dart';
import '../shifts/crew_k9_test_helpers.dart';

void main() {
  setUpAll(() {
    FirebasePlatform.instance = FakeFirebasePlatform();
  });

  group('R5.4 — Notification Superseding & Projection', () {
    test('supersedesParticipationRequest returns true for terminal or signature notifications', () {
      expect(NotificationItem.supersedesParticipationRequest(NotificationType.signatureRequested), isTrue);
      expect(NotificationItem.supersedesParticipationRequest(NotificationType.signatureCompleted), isTrue);
      expect(NotificationItem.supersedesParticipationRequest(NotificationType.signatureDeclined), isTrue);
      expect(NotificationItem.supersedesParticipationRequest(NotificationType.occurrenceFinalized), isTrue);
      expect(NotificationItem.supersedesParticipationRequest(NotificationType.amendmentCreated), isTrue);
      expect(NotificationItem.supersedesParticipationRequest(NotificationType.occurrenceParticipationAccepted), isTrue);
      expect(NotificationItem.supersedesParticipationRequest(NotificationType.occurrenceParticipationDeclined), isTrue);

      expect(NotificationItem.supersedesParticipationRequest(NotificationType.occurrenceParticipationRequested), isFalse);
      expect(NotificationItem.supersedesParticipationRequest(NotificationType.shiftStartReminder), isFalse);
      expect(NotificationItem.supersedesParticipationRequest(NotificationType.shiftEndReminder), isFalse);
    });

    test('getOpenActionNotifications filters out participation request when superseded', () async {
      final fakeFirestore = FakeFirebaseFirestore();
      final service = NotificationService(firestore: fakeFirestore);
      NotificationService.clearDispatchedKeysForTesting();
      service.invalidateCache();

      await fakeFirestore
          .collection('notifications')
          .doc('user_1')
          .collection('items')
          .doc('notif_1')
          .set({
        'type': 'occurrence_participation_requested',
        'occurrence_id': 'OCC-100',
        'occurrence_title': 'Ciência solicitada',
        'created_at': Timestamp.fromDate(DateTime(2026, 3, 30, 10, 0)),
        'action_required': true,
        'read_at': null,
        'archived_at': null,
        'resolved_at': null,
      });

      await fakeFirestore
          .collection('notifications')
          .doc('user_1')
          .collection('items')
          .doc('notif_2')
          .set({
        'type': 'signature_requested',
        'occurrence_id': 'OCC-100',
        'occurrence_title': 'Assinatura solicitada',
        'created_at': Timestamp.fromDate(DateTime(2026, 3, 30, 10, 30)),
        'action_required': true,
        'read_at': null,
        'archived_at': null,
        'resolved_at': null,
      });

      final actions = await service.getOpenActionNotifications(userId: 'user_1').first;
      expect(actions.length, 1);
      expect(actions.first.type, NotificationType.signatureRequested);
      expect(actions.first.id, 'notif_2');
    });

    test('getOpenActionNotifications filters out participation request when occurrence finalized', () async {
      final fakeFirestore = FakeFirebaseFirestore();
      final service = NotificationService(firestore: fakeFirestore);
      NotificationService.clearDispatchedKeysForTesting();
      service.invalidateCache();

      await fakeFirestore
          .collection('notifications')
          .doc('user_2')
          .collection('items')
          .doc('notif_part')
          .set({
        'type': 'occurrence_participation_requested',
        'occurrence_id': 'OCC-200',
        'occurrence_title': 'Ciência solicitada',
        'created_at': Timestamp.fromDate(DateTime(2026, 3, 30, 10, 0)),
        'action_required': true,
        'read_at': null,
        'archived_at': null,
        'resolved_at': null,
      });

      await fakeFirestore
          .collection('notifications')
          .doc('user_2')
          .collection('items')
          .doc('notif_final')
          .set({
        'type': 'occurrence_finalized',
        'occurrence_id': 'OCC-200',
        'occurrence_title': 'Ocorrência selada',
        'created_at': Timestamp.fromDate(DateTime(2026, 3, 30, 11, 0)),
        'action_required': false,
        'read_at': null,
        'archived_at': null,
        'resolved_at': null,
      });

      final actions = await service.getOpenActionNotifications(userId: 'user_2').first;
      expect(actions, isEmpty, reason: 'Participation request must be de-promoted once occurrence is finalized');
    });

    test('archiveNotice throws StateError when attempting to archive open action', () async {
      final fakeFirestore = FakeFirebaseFirestore();
      final service = NotificationService(firestore: fakeFirestore);

      final openAction = NotificationItem(
        id: 'action_notif',
        type: NotificationType.signatureRequested,
        occurrenceId: 'OCC-300',
        occurrenceTitle: 'Assinatura',
        createdAt: DateTime.now(),
        actionRequired: true,
        resolvedAt: null,
      );

      expect(openAction.canBeArchived, isFalse);
      expect(openAction.isOpenAction, isTrue);

      expect(
        () => service.archiveNotice(userId: 'user_x', notification: openAction),
        throwsA(isA<StateError>()),
      );
    });

    test('archiveAllNotices filters out open actions and only archives notices', () async {
      final fakeFirestore = FakeFirebaseFirestore();
      final service = NotificationService(firestore: fakeFirestore);

      await fakeFirestore
          .collection('notifications')
          .doc('user_y')
          .collection('items')
          .doc('notice_1')
          .set({
        'type': 'occurrence_finalized',
        'occurrence_id': 'OCC-400',
        'occurrence_title': 'Finalizada',
        'created_at': Timestamp.fromDate(DateTime(2026, 3, 30, 10, 0)),
        'action_required': false,
        'read_at': null,
        'archived_at': null,
        'resolved_at': null,
      });

      await fakeFirestore
          .collection('notifications')
          .doc('user_y')
          .collection('items')
          .doc('action_1')
          .set({
        'type': 'signature_requested',
        'occurrence_id': 'OCC-400',
        'occurrence_title': 'Assinatura',
        'created_at': Timestamp.fromDate(DateTime(2026, 3, 30, 10, 5)),
        'action_required': true,
        'read_at': null,
        'archived_at': null,
        'resolved_at': null,
      });

      final noticeItem = NotificationItem(
        id: 'notice_1',
        type: NotificationType.occurrenceFinalized,
        occurrenceId: 'OCC-400',
        occurrenceTitle: 'Finalizada',
        createdAt: DateTime(2026, 3, 30, 10, 0),
        actionRequired: false,
      );

      final actionItem = NotificationItem(
        id: 'action_1',
        type: NotificationType.signatureRequested,
        occurrenceId: 'OCC-400',
        occurrenceTitle: 'Assinatura',
        createdAt: DateTime(2026, 3, 30, 10, 5),
        actionRequired: true,
      );

      final archivedCount = await service.archiveAllNotices(
        userId: 'user_y',
        notifications: [noticeItem, actionItem],
      );

      expect(archivedCount, 1, reason: 'Only the notice can be archived; open action must be protected');

      final actionDoc = await fakeFirestore
          .collection('notifications')
          .doc('user_y')
          .collection('items')
          .doc('action_1')
          .get();
      expect(actionDoc.data()!['archived_at'], isNull, reason: 'Open action must remain unarchived');

      final noticeDoc = await fakeFirestore
          .collection('notifications')
          .doc('user_y')
          .collection('items')
          .doc('notice_1')
          .get();
      expect(noticeDoc.data()!['archived_at'], isNotNull, reason: 'Notice must be archived');
    });
  });

  group('R5.5 — History Occurrence Clean Projection & Two-Fixture Isolation', () {
    test('RecordDetail.fromEntry for occurrence without dummy fallbacks', () {
      final occEntry = HistoryEntry(
        id: 'occ_entry_1',
        type: HistoryEntryType.occurrence,
        title: 'Ocorrência Operacional',
        subtitle: 'Patrulhamento',
        time: DateTime(2026, 3, 30, 14, 0),
        author: '',
        authorId: '',
        tag: 'OCORRÊNCIA',
        icon: Icons.assignment_outlined,
        color: Colors.blue,
        details: {
          'Tipo': 'Apoio',
          'Status': 'finalized',
          'Início': '14:00',
          'Fim': '14:45',
        },
      );

      final detail = RecordDetail.fromEntry(occEntry);

      expect(detail.dogName, 'Sem cão', reason: 'Must not use Bono as fallback');
      expect(detail.handlerName, 'Não informado', reason: 'Must not use Ragonha as fallback');
      expect(detail.author, 'Não informado', reason: 'Must not use GCM Ragonha as fallback');
      expect(detail.team, 'Não informada', reason: 'Must not use 2 GCMs as fallback');
      expect(detail.duration, '45 min', reason: 'Must calculate real duration from 14:00 to 14:45');
    });

    test('Two-Occurrence fixture isolation proves zero cross-leakage and zero dummy fallbacks', () {
      final entryA = HistoryEntry(
        id: 'occ_A',
        type: HistoryEntryType.occurrence,
        title: 'Ocorrência · Patrulhamento K9',
        subtitle: 'Praça Central, 100',
        time: DateTime(2026, 3, 30, 10, 0),
        author: 'GCM Silva',
        authorId: 'gcm_silva_id',
        tag: 'OCORRÊNCIA',
        icon: Icons.assignment_outlined,
        color: Colors.blue,
        location: 'Praça Central, 100',
        details: {
          'Tipo': 'Patrulhamento K9',
          'Status': 'finalized',
          'Cão': 'Thor',
          'Condutor': 'GCM Silva',
          'Início': '10:00',
          'Fim': '11:00',
          'Duração': '60 min',
          'Equipe': '3 integrantes',
          'Descrição': 'Apoio tático no centro com K9 Thor',
        },
      );

      final entryB = HistoryEntry(
        id: 'occ_B',
        type: HistoryEntryType.occurrence,
        title: 'Ocorrência · Apoio',
        subtitle: 'Avenida Brasil, 500',
        time: DateTime(2026, 3, 30, 14, 0),
        author: 'GCM Souza',
        authorId: 'gcm_souza_id',
        tag: 'OCORRÊNCIA',
        icon: Icons.assignment_outlined,
        color: Colors.green,
        location: 'Avenida Brasil, 500',
        details: {
          'Tipo': 'Apoio',
          'Status': 'finalized',
          'Cão': 'Sem cão',
          'Condutor': 'GCM Souza',
          'Início': '14:00',
          'Fim': '14:30',
          'Duração': '30 min',
          'Equipe': 'Não informada',
          'Descrição': 'Verificação de perímetro sem cão',
        },
      );

      final detailA = RecordDetail.fromEntry(entryA);
      final detailB = RecordDetail.fromEntry(entryB);

      // Verify Fixture A
      expect(detailA.id, 'occ_A');
      expect(detailA.dogName, 'Thor');
      expect(detailA.handlerName, 'GCM Silva');
      expect(detailA.author, 'GCM Silva');
      expect(detailA.duration, '60 min');
      expect(detailA.team, '3 integrantes');
      expect(detailA.location, 'Praça Central, 100');
      expect(detailA.notes, 'Apoio tático no centro com K9 Thor');

      // Verify Fixture B
      expect(detailB.id, 'occ_B');
      expect(detailB.dogName, 'Sem cão');
      expect(detailB.handlerName, 'GCM Souza');
      expect(detailB.author, 'GCM Souza');
      expect(detailB.duration, '30 min');
      expect(detailB.team, 'Não informada');
      expect(detailB.location, 'Avenida Brasil, 500');
      expect(detailB.notes, 'Verificação de perímetro sem cão');

      // Assert zero cross-contamination
      expect(detailB.dogName, isNot(equals(detailA.dogName)));
      expect(detailB.handlerName, isNot(equals(detailA.handlerName)));
      expect(detailB.author, isNot(equals(detailA.author)));
      expect(detailB.duration, isNot(equals(detailA.duration)));
      expect(detailB.team, isNot(equals(detailA.team)));
      expect(detailB.location, isNot(equals(detailA.location)));

      // Assert zero dummy fallbacks in either fixture
      for (final detail in [detailA, detailB]) {
        expect(detail.dogName, isNot(equals('Bono')));
        expect(detail.handlerName, isNot(equals('GCM Ragonha')));
        expect(detail.author, isNot(equals('GCM Ragonha')));
        expect(detail.duration, isNot(equals('42 min')));
        expect(detail.team, isNot(equals('2 GCMs')));
      }
    });
  });

  group('R5.7 — Active Timeline Edit Gating & Card Width', () {
    testWidgets('ActiveOccurrenceEventCard hides editar button when canEdit is false', (tester) async {
      final event = OccurrenceEvent(
        id: 'evt_1',
        occurrenceId: 'occ_1',
        timestamp: DateTime(2026, 3, 30, 10, 15),
        createdAt: DateTime(2026, 3, 30, 10, 15),
        updatedAt: DateTime(2026, 3, 30, 10, 15),
        category: OccurrenceEventCategory.dogWork,
        title: 'Varredura',
        description: 'Varredura realizada com sucesso',
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ActiveOccurrenceEventCard(
              event: event,
              canEdit: false,
              onTap: () {},
            ),
          ),
        ),
      );

      expect(find.text('editar'), findsNothing);
    });

    testWidgets('ActiveOccurrenceEventCard shows editar button when canEdit is true', (tester) async {
      final event = OccurrenceEvent(
        id: 'evt_2',
        occurrenceId: 'occ_1',
        timestamp: DateTime(2026, 3, 30, 10, 15),
        createdAt: DateTime(2026, 3, 30, 10, 15),
        updatedAt: DateTime(2026, 3, 30, 10, 15),
        category: OccurrenceEventCategory.dogWork,
        title: 'Varredura',
        description: 'Varredura realizada com sucesso',
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ActiveOccurrenceEventCard(
              event: event,
              canEdit: true,
              onTap: () {},
            ),
          ),
        ),
      );

      expect(find.text('editar'), findsOneWidget);
    });

    testWidgets('Long handler name in _MetaChip does not overflow 320px viewport', (tester) async {
      tester.view.physicalSize = const Size(320, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final event = OccurrenceEvent(
        id: 'evt_3',
        occurrenceId: 'occ_1',
        timestamp: DateTime(2026, 3, 30, 10, 15),
        createdAt: DateTime(2026, 3, 30, 10, 15),
        updatedAt: DateTime(2026, 3, 30, 10, 15),
        category: OccurrenceEventCategory.dogWork,
        dogHandlerId: '990001',
        title: 'Busca e Apreensão de Entorpecentes',
        description: 'Ação realizada no setor norte',
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ActiveOccurrenceEventCard(
              event: event,
              handlerName: 'GCM 1CL Especializado Fulano de Tal da Silva Junior',
              locationLabel: 'Avenida Principal dos Bandeirantes Km 45',
              canEdit: true,
              onTap: () {},
            ),
          ),
        ),
      );

      expect(tester.takeException(), isNull, reason: 'Must not overflow viewport width');
    });
  });

  group('R5.8 — Vehicle Capacity & Occupancy Badge', () {
    test('VehicleCrewPostBoard exposes 4 roles', () {
      expect(VehicleCrewPostBoard.roles.length, 4);
      expect(VehicleCrewPostBoard.roles, containsAll(['motorista', 'encarregado', 'auxiliar_1', 'auxiliar_2']));
    });

    testWidgets('OccupancyBadge respects vehicle.crewSize capacity strictly', (tester) async {
      // 2-person vehicle with 1 occupant: 1/2 (DISPONÍVEL)
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: OccupancyBadge(occupancy: 1, crewSize: 2),
          ),
        ),
      );
      expect(find.text('1/2'), findsOneWidget);
      expect(find.text('CHEIA'), findsNothing);

      // 2-person vehicle with 2 occupants: CHEIA (not 2/4)
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: OccupancyBadge(occupancy: 2, crewSize: 2),
          ),
        ),
      );
      expect(find.text('CHEIA'), findsOneWidget);
      expect(find.text('2/2'), findsNothing);

      // 4-person vehicle with 2 occupants: 2/4 (DISPONÍVEL)
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: OccupancyBadge(occupancy: 2, crewSize: 4),
          ),
        ),
      );
      expect(find.text('2/4'), findsOneWidget);
      expect(find.text('CHEIA'), findsNothing);

      // 4-person vehicle with 4 occupants: CHEIA
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: OccupancyBadge(occupancy: 4, crewSize: 4),
          ),
        ),
      );
      expect(find.text('CHEIA'), findsOneWidget);
    });

    testWidgets('R5.8 Invariant: 2-person vehicle with 2 occupants displays CHEIA and zero ASSUMIR actions', (tester) async {
      final shiftVM = ShiftViewModel(
        authorizationGateway: MockShiftAuthorizationGateway(),
        shiftService: MockShiftService(),
        authService: MockAuthService(),
      );
      shiftVM.setBoundRaForTesting('990001');
      shiftVM.setSessionForTesting(
        ActiveShiftSession.fromJson({
          'handlerId': '990001',
          'dogId': 'stg-dog-tc1-001',
          'vehicleId': 'STG-TC1-VTR-01',
          'vehicleCrewId': 'STG-TC1-VTR-01',
          'startedAt': DateTime.now().toIso8601String(),
          'status': 'active',
        }),
      );
      final userVM = MockUserViewModel({
        '990001': 'Condutor 1',
        '990002': 'Condutor 2',
      });
      const vehicle = Vehicle(
        id: 'STG-TC1-VTR-01',
        name: 'Viatura 01',
        prefix: 'V-TC1',
        modelName: 'Hilux',
        crewSize: 2,
        unit: 'Canil GCM',
        active: true,
      );
      final Map<String, VehicleCrewMember> activeMembers = {
        'motorista': VehicleCrewMember(
          handlerId: '990001',
          name: 'Condutor 1',
          role: 'motorista',
          status: 'active',
          joinedAt: DateTime(2025),
        ),
        'encarregado': VehicleCrewMember(
          handlerId: '990002',
          name: 'Condutor 2',
          role: 'encarregado',
          status: 'active',
          joinedAt: DateTime(2025),
        ),
      };

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<ShiftViewModel>.value(value: shiftVM),
            ChangeNotifierProvider<AuthViewModel>.value(value: AuthViewModel()),
            ChangeNotifierProvider<UserViewModel>.value(value: userVM),
            ChangeNotifierProvider<DogViewModel>.value(
              value: MockDogViewModel([defaultTestDog1]),
            ),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: Column(
                children: [
                  OccupancyBadge(occupancy: activeMembers.length, crewSize: vehicle.crewSize),
                  Expanded(
                    child: VehicleCrewPostBoard(
                      vehicle: vehicle,
                      activeMembers: activeMembers,
                      hasBinomioActive: false,
                      onPostSelected: (_) {},
                      onLeaveVehicle: () {},
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );

      // Invariant: UI displays CHEIA and ZERO ASSUMIR buttons
      expect(find.text('CHEIA'), findsOneWidget);
      expect(find.text('ASSUMIR'), findsNothing);
    });

    testWidgets('R5.8 Invariant: 4-person vehicle with 2 occupants displays 2/4 and ASSUMIR actions (NEVER CHEIA + ASSUMIR)', (tester) async {
      final shiftVM = ShiftViewModel(
        authorizationGateway: MockShiftAuthorizationGateway(),
        shiftService: MockShiftService(),
        authService: MockAuthService(),
      );
      shiftVM.setBoundRaForTesting('990001');
      shiftVM.setSessionForTesting(
        ActiveShiftSession.fromJson({
          'handlerId': '990001',
          'dogId': 'stg-dog-tc1-001',
          'vehicleId': 'STG-TC1-VTR-01',
          'vehicleCrewId': 'STG-TC1-VTR-01',
          'startedAt': DateTime.now().toIso8601String(),
          'status': 'active',
        }),
      );
      final userVM = MockUserViewModel({
        '990001': 'Condutor 1',
        '990002': 'Condutor 2',
      });
      const vehicle = Vehicle(
        id: 'STG-TC1-VTR-01',
        name: 'Viatura 01',
        prefix: 'V-TC1',
        modelName: 'Hilux',
        crewSize: 4,
        unit: 'Canil GCM',
        active: true,
      );
      final Map<String, VehicleCrewMember> activeMembers = {
        'motorista': VehicleCrewMember(
          handlerId: '990001',
          name: 'Condutor 1',
          role: 'motorista',
          status: 'active',
          joinedAt: DateTime(2025),
        ),
        'encarregado': VehicleCrewMember(
          handlerId: '990002',
          name: 'Condutor 2',
          role: 'encarregado',
          status: 'active',
          joinedAt: DateTime(2025),
        ),
      };

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<ShiftViewModel>.value(value: shiftVM),
            ChangeNotifierProvider<AuthViewModel>.value(value: AuthViewModel()),
            ChangeNotifierProvider<UserViewModel>.value(value: userVM),
            ChangeNotifierProvider<DogViewModel>.value(
              value: MockDogViewModel([defaultTestDog1]),
            ),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: Column(
                children: [
                  OccupancyBadge(occupancy: activeMembers.length, crewSize: vehicle.crewSize),
                  Expanded(
                    child: VehicleCrewPostBoard(
                      vehicle: vehicle,
                      activeMembers: activeMembers,
                      hasBinomioActive: false,
                      onPostSelected: (_) {},
                      onLeaveVehicle: () {},
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );

      // Invariant: UI displays 2/4, ASSUMIR is present, CHEIA is NOT present
      expect(find.text('2/4'), findsOneWidget);
      expect(find.text('CHEIA'), findsNothing);
      expect(find.text('ASSUMIR'), findsWidgets);
    });

    testWidgets('R5.8 Invariant: 4-person vehicle with 4 occupants displays CHEIA and zero ASSUMIR actions', (tester) async {
      final shiftVM = ShiftViewModel(
        authorizationGateway: MockShiftAuthorizationGateway(),
        shiftService: MockShiftService(),
        authService: MockAuthService(),
      );
      shiftVM.setBoundRaForTesting('990001');
      shiftVM.setSessionForTesting(
        ActiveShiftSession.fromJson({
          'handlerId': '990001',
          'dogId': 'stg-dog-tc1-001',
          'vehicleId': 'STG-TC1-VTR-01',
          'vehicleCrewId': 'STG-TC1-VTR-01',
          'startedAt': DateTime.now().toIso8601String(),
          'status': 'active',
        }),
      );
      final userVM = MockUserViewModel({
        '990001': 'Condutor 1',
        '990002': 'Condutor 2',
        '990003': 'Condutor 3',
        '990004': 'Condutor 4',
      });
      const vehicle = Vehicle(
        id: 'STG-TC1-VTR-01',
        name: 'Viatura 01',
        prefix: 'V-TC1',
        modelName: 'Hilux',
        crewSize: 4,
        unit: 'Canil GCM',
        active: true,
      );
      final Map<String, VehicleCrewMember> activeMembers = {
        'motorista': VehicleCrewMember(
          handlerId: '990001',
          name: 'Condutor 1',
          role: 'motorista',
          status: 'active',
          joinedAt: DateTime(2025),
        ),
        'encarregado': VehicleCrewMember(
          handlerId: '990002',
          name: 'Condutor 2',
          role: 'encarregado',
          status: 'active',
          joinedAt: DateTime(2025),
        ),
        'auxiliar_1': VehicleCrewMember(
          handlerId: '990003',
          name: 'Condutor 3',
          role: 'auxiliar_1',
          status: 'active',
          joinedAt: DateTime(2025),
        ),
        'auxiliar_2': VehicleCrewMember(
          handlerId: '990004',
          name: 'Condutor 4',
          role: 'auxiliar_2',
          status: 'active',
          joinedAt: DateTime(2025),
        ),
      };

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<ShiftViewModel>.value(value: shiftVM),
            ChangeNotifierProvider<AuthViewModel>.value(value: AuthViewModel()),
            ChangeNotifierProvider<UserViewModel>.value(value: userVM),
            ChangeNotifierProvider<DogViewModel>.value(
              value: MockDogViewModel([defaultTestDog1]),
            ),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: Column(
                children: [
                  OccupancyBadge(occupancy: activeMembers.length, crewSize: vehicle.crewSize),
                  Expanded(
                    child: VehicleCrewPostBoard(
                      vehicle: vehicle,
                      activeMembers: activeMembers,
                      hasBinomioActive: false,
                      onPostSelected: (_) {},
                      onLeaveVehicle: () {},
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );

      // Invariant: UI displays CHEIA and zero ASSUMIR
      expect(find.text('CHEIA'), findsOneWidget);
      expect(find.text('ASSUMIR'), findsNothing);
    });
  });

  group('R5.2 — Occurrence Return for Correction Lifecycle Matrix', () {
    test('State Matrix Contract: accepted+unsigned (YES), signed+not sealed (NO), sealed (NO)', () {
      bool canRequestCorrection({
        required OccurrenceStatus status,
        required String currentRa,
        required List<OccurrenceTeamMember> team,
        required List<OccurrenceSignature> signatures,
      }) {
        if (status != OccurrenceStatus.awaitingSignatures) return false;
        final member = team.where((item) => item.handlerId == currentRa);
        if (member.isEmpty || member.first.role == TeamRole.titular) return false;
        final hasAlreadySigned = signatures.any(
          (signature) =>
              signature.handlerId == currentRa &&
              signature.status == SignatureStatus.signed,
        );
        if (hasAlreadySigned) return false;
        return true;
      }

      final team = [
        OccurrenceTeamMember(
          handlerId: '990001',
          role: TeamRole.titular,
          addedAt: DateTime(2025),
          addedBy: '990001',
        ),
        OccurrenceTeamMember(
          handlerId: '990002',
          role: TeamRole.integrante,
          addedAt: DateTime(2025),
          addedBy: '990001',
        ),
      ];

      // 1. accepted + unsigned (awaiting_signatures, pending signature)
      final unsignedSignatures = [
        const OccurrenceSignature(
          handlerId: '990002',
          status: SignatureStatus.pending,
        ),
      ];
      expect(
        canRequestCorrection(
          status: OccurrenceStatus.awaitingSignatures,
          currentRa: '990002',
          team: team,
          signatures: unsignedSignatures,
        ),
        isTrue,
        reason: 'accepted + unsigned allows return for correction',
      );

      // 2. signed + not sealed (awaiting_signatures, user already signed)
      final signedSignatures = [
        const OccurrenceSignature(
          handlerId: '990002',
          status: SignatureStatus.signed,
        ),
      ];
      expect(
        canRequestCorrection(
          status: OccurrenceStatus.awaitingSignatures,
          currentRa: '990002',
          team: team,
          signatures: signedSignatures,
        ),
        isFalse,
        reason: 'signed + not sealed forbids return for correction for the signed user',
      );

      // 3. sealed / finalized (occurrence status is finalized/closed)
      expect(
        canRequestCorrection(
          status: OccurrenceStatus.finalized,
          currentRa: '990002',
          team: team,
          signatures: unsignedSignatures,
        ),
        isFalse,
        reason: 'sealed/finalized forbids return for correction',
      );

      // 4. titular (primary handler) cannot devolve to themselves
      expect(
        canRequestCorrection(
          status: OccurrenceStatus.awaitingSignatures,
          currentRa: '990001',
          team: team,
          signatures: unsignedSignatures,
        ),
        isFalse,
        reason: 'titular does not request correction from themselves',
      );
    });
  });
}
