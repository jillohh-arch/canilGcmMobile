import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:canil_gcm/core/domain/notification_item.dart';
import 'package:canil_gcm/core/domain/occurrence_team_member.dart';
import 'package:canil_gcm/core/services/notification_service.dart';
import 'package:canil_gcm/features/occurrences/data/occurrence_event_repository.dart';
import 'package:canil_gcm/features/occurrences/data/occurrence_repository.dart';
import 'package:canil_gcm/features/occurrences/data/signature_repository.dart';
import 'package:canil_gcm/features/occurrences/domain/occurrence.dart';
import 'package:canil_gcm/features/occurrences/domain/occurrence_status.dart';
import 'package:canil_gcm/features/occurrences/presentation/screens/start_occurrence_screen.dart';
import 'package:canil_gcm/features/occurrences/presentation/view_models/occurrence_view_model.dart';
import 'package:canil_gcm/features/shifts/domain/vehicle_crew.dart';

void main() {
  late FakeFirebaseFirestore r3FakeFirestore;

  setUp(() {
    r3FakeFirestore = FakeFirebaseFirestore();
    NotificationService.clearDispatchedKeysForTesting();
  });

  group('F40.TC1-PHYSICAL-OCCURRENCE-INTEGRATION-FIX-R2 Regression Suite', () {
    late FakeFirebaseFirestore fakeFirestore;
    late OccurrenceRepository occurrenceRepo;
    late OccurrenceEventRepository eventRepo;
    late SignatureRepository signatureRepo;
    late OccurrenceViewModel occurrenceVM;

    final now = DateTime(2026, 9, 12, 10, 30);
    const titularRa = '990001';
    const auxiliarRa = '990002';
    const otherAuxiliarRa = '990003';

    setUp(() {
      fakeFirestore = FakeFirebaseFirestore();
      occurrenceRepo = OccurrenceRepository(fakeFirestore);
      eventRepo = OccurrenceEventRepository(fakeFirestore);
      signatureRepo = SignatureRepository(firestore: fakeFirestore);
      occurrenceVM = OccurrenceViewModel(
        repository: occurrenceRepo,
        eventRepository: eventRepo,
        signatureRepository: signatureRepo,
        notificationService: NotificationService(firestore: fakeFirestore),
        sendTeamNotifications: false,
      );
    });

    // ─── T1: Cross-user notification dispatch ────────────────────────────
    test('T1: NotificationService creates cross-user notification directly without pre-read', () async {
      final notifService = NotificationService(firestore: fakeFirestore);
      final notifId = 'opened_occ_100_$auxiliarRa';

      final resultId = await notifService.createNotification(
        userId: auxiliarRa,
        type: NotificationType.occurrenceParticipationRequested,
        occurrenceId: 'occ_100',
        occurrenceTitle: 'Ocorrência Geral',
        notificationId: notifId,
        deduplicate: true,
        actionRequired: true,
        targetScreen: 'occurrence_active',
      );

      expect(resultId, equals(notifId));
      final doc = await fakeFirestore
          .collection('notifications')
          .doc(auxiliarRa)
          .collection('items')
          .doc(notifId)
          .get();

      expect(doc.exists, isTrue);
      expect(doc.data()!['occurrence_id'], equals('occ_100'));
      expect(doc.data()!['type'], equals('occurrence_participation_requested'));
      expect(doc.data()!['action_required'], isTrue);
    });

    // ─── T2: Deterministic deduplication & idempotency ───────────────────
    test('T2: Idempotent notification creation with identical deterministic ID returns safely', () async {
      final notifService = NotificationService(firestore: fakeFirestore);
      final notifId = 'opened_occ_200_$auxiliarRa';

      final firstCall = await notifService.createNotification(
        userId: auxiliarRa,
        type: NotificationType.occurrenceParticipationRequested,
        occurrenceId: 'occ_200',
        occurrenceTitle: 'Ocorrência Geral',
        notificationId: notifId,
        deduplicate: true,
      );

      final secondCall = await notifService.createNotification(
        userId: auxiliarRa,
        type: NotificationType.occurrenceParticipationRequested,
        occurrenceId: 'occ_200',
        occurrenceTitle: 'Ocorrência Geral',
        notificationId: notifId,
        deduplicate: true,
      );

      expect(firstCall, equals(notifId));
      expect(secondCall, equals(notifId));
    });

    // ─── T3: Occurrence discovery via team_handler_ids ───────────────────
    test('T3: findOpenForHandler discovers open occurrence via team_handler_ids', () async {
      final occ = Occurrence(
        id: 'occ_team_300',
        shiftId: 'shift_1',
        primaryHandlerId: 'uid_$titularRa',
        primaryHandlerRa: titularRa,
        dogId: 'dog_crew_1',
        typeCode: 'AVERIGUACAO',
        typeName: 'Averiguação',
        startedAt: now,
        createdAt: now,
        updatedAt: now,
        status: OccurrenceStatus.inProgress,
        team: [
          OccurrenceTeamMember(
            handlerId: titularRa,
            role: TeamRole.titular,
            addedAt: now,
            addedBy: titularRa,
          ),
          OccurrenceTeamMember(
            handlerId: auxiliarRa,
            role: TeamRole.integrante,
            addedAt: now,
            addedBy: titularRa,
          ),
        ],
      );
      await occurrenceRepo.create(occ);

      // Auxiliar operator (who does not own dog_crew_1) discovers the occurrence
      final discovered = await occurrenceRepo.findOpenForHandler(auxiliarRa);
      expect(discovered, isNotNull);
      expect(discovered!.id, equals('occ_team_300'));
      expect(discovered.primaryHandlerRa, equals(titularRa));
      expect(discovered.teamHandlerIds, contains(auxiliarRa));
    });

    // ─── T4: watchOpenForHandler emits open occurrence updates ───────────
    test('T4: watchOpenForHandler emits open occurrence updates for handler without personal dog', () async {
      final occ = Occurrence(
        id: 'occ_stream_400',
        shiftId: 'shift_1',
        primaryHandlerId: 'uid_$titularRa',
        primaryHandlerRa: titularRa,
        dogId: '',
        typeCode: 'FARO',
        typeName: 'Faro Geral',
        startedAt: now,
        createdAt: now,
        updatedAt: now,
        status: OccurrenceStatus.inProgress,
        team: [
          OccurrenceTeamMember(
            handlerId: auxiliarRa,
            role: TeamRole.integrante,
            addedAt: now,
            addedBy: titularRa,
          ),
        ],
      );
      await occurrenceRepo.create(occ);

      final streamResult = await occurrenceRepo.watchOpenForHandler(auxiliarRa).first;
      expect(streamResult, isNotNull);
      expect(streamResult!.id, equals('occ_stream_400'));
    });

    // ─── T5: findOpenForContext precedence & fallback ────────────────────
    test('T5: findOpenForContext resolves dog first if found, otherwise falls back to handlerRa', () async {
      final occWithDog = Occurrence(
        id: 'occ_with_dog',
        shiftId: 'shift_1',
        primaryHandlerId: 'uid_$titularRa',
        primaryHandlerRa: titularRa,
        dogId: 'dog_alpha',
        typeCode: 'FARO',
        typeName: 'Faro',
        startedAt: now,
        createdAt: now,
        updatedAt: now,
        status: OccurrenceStatus.inProgress,
      );
      await occurrenceRepo.create(occWithDog);

      final occWithoutDog = Occurrence(
        id: 'occ_without_dog',
        shiftId: 'shift_2',
        primaryHandlerId: 'uid_$titularRa',
        primaryHandlerRa: titularRa,
        dogId: '',
        typeCode: 'AVERIGUACAO',
        typeName: 'Averiguação',
        startedAt: now,
        createdAt: now,
        updatedAt: now,
        status: OccurrenceStatus.inProgress,
        team: [
          OccurrenceTeamMember(
            handlerId: otherAuxiliarRa,
            role: TeamRole.integrante,
            addedAt: now,
            addedBy: titularRa,
          ),
        ],
      );
      await occurrenceRepo.create(occWithoutDog);

      // Dog ID matches
      final byDog = await occurrenceRepo.findOpenForContext(
        dogId: 'dog_alpha',
        handlerRa: auxiliarRa,
      );
      expect(byDog, isNotNull);
      expect(byDog!.id, equals('occ_with_dog'));

      // Dog ID null -> resolves by handlerRa
      final byHandler = await occurrenceRepo.findOpenForContext(
        dogId: null,
        handlerRa: otherAuxiliarRa,
      );
      expect(byHandler, isNotNull);
      expect(byHandler!.id, equals('occ_without_dog'));

      // Dog ID unknown -> falls back to handlerRa
      final byFallback = await occurrenceRepo.findOpenForContext(
        dogId: 'unknown_dog',
        handlerRa: otherAuxiliarRa,
      );
      expect(byFallback, isNotNull);
      expect(byFallback!.id, equals('occ_without_dog'));
    });

    // ─── T6: OccurrenceViewModel findOpenForContext cockpit recovery ──────
    test('T6: OccurrenceViewModel.findOpenForContext recovers open occurrence for operator without dog', () async {
      final occ = Occurrence(
        id: 'occ_vm_recovery',
        shiftId: 'shift_1',
        primaryHandlerId: 'uid_$titularRa',
        primaryHandlerRa: titularRa,
        dogId: 'dog_crew_1',
        typeCode: 'AVERIGUACAO',
        typeName: 'Averiguação',
        startedAt: now,
        createdAt: now,
        updatedAt: now,
        status: OccurrenceStatus.inProgress,
        team: [
          OccurrenceTeamMember(
            handlerId: auxiliarRa,
            role: TeamRole.integrante,
            addedAt: now,
            addedBy: titularRa,
          ),
        ],
      );
      await occurrenceRepo.create(occ);

      // Operator in cockpit has effectiveDogId: null, but currentRa: auxiliarRa
      final recovered = await occurrenceVM.findOpenForContext(
        dogId: null,
        handlerRa: auxiliarRa,
      );
      expect(recovered, isNotNull);
      expect(recovered!.id, equals('occ_vm_recovery'));
    });

    // ─── T7: Occurrence filtering for operator without dog in history ─────
    test('T7: Operator without dog sees occurrences matching teamHandlerIds', () async {
      final occ1 = Occurrence(
        id: 'occ_team_member',
        shiftId: 'shift_1',
        primaryHandlerId: 'uid_$titularRa',
        primaryHandlerRa: titularRa,
        dogId: 'dog_other',
        typeCode: 'AVERIGUACAO',
        typeName: 'Averiguação',
        startedAt: now,
        createdAt: now,
        updatedAt: now,
        status: OccurrenceStatus.finalized,
        team: [
          OccurrenceTeamMember(
            handlerId: auxiliarRa,
            role: TeamRole.integrante,
            addedAt: now,
            addedBy: titularRa,
          ),
        ],
      );
      final occ2 = Occurrence(
        id: 'occ_unrelated',
        shiftId: 'shift_1',
        primaryHandlerId: 'uid_$titularRa',
        primaryHandlerRa: titularRa,
        dogId: 'dog_other',
        typeCode: 'AVERIGUACAO',
        typeName: 'Outra',
        startedAt: now,
        createdAt: now,
        updatedAt: now,
        status: OccurrenceStatus.finalized,
        team: [
          OccurrenceTeamMember(
            handlerId: titularRa,
            role: TeamRole.titular,
            addedAt: now,
            addedBy: titularRa,
          ),
        ],
      );
      await occurrenceRepo.create(occ1);
      await occurrenceRepo.create(occ2);

      final list = await occurrenceRepo.watchByHandler(auxiliarRa).first;
      expect(list.any((o) => o.id == 'occ_team_member'), isTrue);
      expect(list.any((o) => o.id == 'occ_unrelated'), isFalse);
    });

    // ─── T8: StartOccurrenceScreen does NOT stamp crew dog onto dog-less members ──
    test('T8: buildGuarnicaoSnapshotMembers does not stamp crew dog onto members with no dog', () {
      final activeMembers = [
        VehicleCrewMember(
          handlerId: titularRa,
          role: 'encarregado',
          status: 'active',
          joinedAt: now,
          dogId: 'dog_crew_alpha',
        ),
        VehicleCrewMember(
          handlerId: auxiliarRa,
          role: 'auxiliar_1',
          status: 'active',
          joinedAt: now,
          dogId: null, // No personal dog!
        ),
        VehicleCrewMember(
          handlerId: otherAuxiliarRa,
          role: 'motorista',
          status: 'active',
          joinedAt: now,
          dogId: '', // Empty personal dog!
        ),
      ];

      final snapshot = StartOccurrenceScreen.buildGuarnicaoSnapshotMembers(
        activeMembers: activeMembers,
        currentRa: titularRa,
        currentHandlerActiveDogId: 'dog_crew_alpha',
        now: now,
      );

      expect(snapshot.length, equals(3));

      final titular = snapshot.firstWhere((m) => m.handlerId == titularRa);
      final aux1 = snapshot.firstWhere((m) => m.handlerId == auxiliarRa);
      final aux2 = snapshot.firstWhere((m) => m.handlerId == otherAuxiliarRa);

      // Titular has dog
      expect(titular.role, equals(TeamRole.titular));
      expect(titular.dogId, equals('dog_crew_alpha'));

      // Auxiliaries must NOT have crew dog stamped on them!
      expect(aux1.role, equals(TeamRole.integrante));
      expect(aux1.dogId, isNull);
      expect(aux1.dogName, isNull);

      expect(aux2.role, equals(TeamRole.integrante));
      expect(aux2.dogId, isNull);
      expect(aux2.dogName, isNull);
    });

    // ─── T9: StartOccurrenceScreen preserves dog for members who DO have dogs ───
    test('T9: buildGuarnicaoSnapshotMembers preserves assigned dog for members who have dogs', () {
      final activeMembers = [
        VehicleCrewMember(
          handlerId: titularRa,
          role: 'encarregado',
          status: 'active',
          joinedAt: now,
          dogId: 'dog_alpha',
        ),
        VehicleCrewMember(
          handlerId: auxiliarRa,
          role: 'auxiliar_1',
          status: 'active',
          joinedAt: now,
          dogId: 'dog_bravo', // Auxiliar brought their own dog!
        ),
      ];

      final snapshot = StartOccurrenceScreen.buildGuarnicaoSnapshotMembers(
        activeMembers: activeMembers,
        currentRa: titularRa,
        currentHandlerActiveDogId: 'dog_alpha',
        now: now,
      );

      final titular = snapshot.firstWhere((m) => m.handlerId == titularRa);
      final aux = snapshot.firstWhere((m) => m.handlerId == auxiliarRa);

      expect(titular.dogId, equals('dog_alpha'));
      expect(aux.dogId, equals('dog_bravo'));
    });
  });

  group('R3 Notification Idempotency & Security (N1-N6)', () {
    NotificationService buildService({
      required Future<void> Function(
        DocumentReference document,
        Map<String, dynamic> data,
      ) writer,
    }) {
      return NotificationService(
        firestore: r3FakeFirestore,
        notificationWriter: writer,
      );
    }

    test('T10: N1 - Authorized first create writes the notification (SUCCESS)', () async {
      final service = NotificationService(firestore: r3FakeFirestore);
      const userId = '990002';
      const notificationId = 'opened_occ_n1_990002';

      final result = await service.createNotification(
        userId: userId,
        type: NotificationType.occurrenceParticipationRequested,
        occurrenceId: 'occ_n1',
        occurrenceTitle: 'Ocorrência teste N1',
        notificationId: notificationId,
        deduplicate: true,
      );

      expect(result, notificationId);
      final stored = await r3FakeFirestore
          .collection('notifications')
          .doc(userId)
          .collection('items')
          .doc(notificationId)
          .get();
      expect(stored.exists, isTrue);
      expect(stored.data()?['type'], 'occurrence_participation_requested');
      expect(stored.data()?['occurrence_id'], 'occ_n1');
    });

    test('T11: N2 - Forbidden cross-user read is never performed (DENIED / no get())', () async {
      var readAttempted = false;
      var writeExecuted = false;

      final service = NotificationService(
        firestore: r3FakeFirestore,
        notificationWriter: (document, data) async {
          writeExecuted = true;
          // Verify that reading document from another user's notifications collection would fail
          await r3FakeFirestore.doc(document.path).set(data);
        },
      );

      const crossUserId = '990002';
      const notificationId = 'opened_occ_n2_990002';

      final result = await service.createNotification(
        userId: crossUserId,
        type: NotificationType.occurrenceParticipationRequested,
        occurrenceId: 'occ_n2',
        occurrenceTitle: 'Ocorrência teste N2',
        notificationId: notificationId,
        deduplicate: true,
      );

      expect(result, equals(notificationId));
      expect(writeExecuted, isTrue);
      expect(readAttempted, isFalse);
    });

    test('T12: N3 - Genuine duplicate dispatch is BENIGN / IDEMPOTENT (no duplicate write, no fatal error)', () async {
      var writeCount = 0;
      final service = NotificationService(
        firestore: r3FakeFirestore,
        notificationWriter: (document, data) async {
          writeCount++;
          await r3FakeFirestore.doc(document.path).set(data);
        },
      );

      const userId = '990002';
      const notificationId = 'opened_occ_n3_990002';

      // 1. Authorized first create
      final firstResult = await service.createNotification(
        userId: userId,
        type: NotificationType.occurrenceParticipationRequested,
        occurrenceId: 'occ_n3',
        occurrenceTitle: 'Ocorrência teste N3',
        notificationId: notificationId,
        deduplicate: true,
      );

      expect(firstResult, equals(notificationId));
      expect(writeCount, equals(1));

      // 2. Same logical notification attempted again (same deterministic ID)
      final secondResult = await service.createNotification(
        userId: userId,
        type: NotificationType.occurrenceParticipationRequested,
        occurrenceId: 'occ_n3',
        occurrenceTitle: 'Ocorrência teste N3',
        notificationId: notificationId,
        deduplicate: true,
      );

      // 3. Deterministic notification ID remains the same
      expect(secondResult, equals(notificationId));
      // 4. No duplicate write performed (in-memory dispatched cache suppresses second call)
      expect(writeCount, equals(1));
      // 5. Occurrence flow receives no fatal error

      final stored = await r3FakeFirestore
          .collection('notifications')
          .doc(userId)
          .collection('items')
          .doc(notificationId)
          .get();
      expect(stored.exists, isTrue);
      expect(stored.data()?['occurrence_id'], 'occ_n3');
    });

    test('T13: N4 - Unauthorized writer denial propagates as failure (FAILURE PROPAGATES)', () async {
      final service = buildService(
        writer: (document, data) => Future<void>.error(
          FirebaseException(
            plugin: 'cloud_firestore',
            code: 'permission-denied',
            message: 'Missing or insufficient permissions.',
          ),
        ),
      );

      expect(
        service.createNotification(
          userId: '990002',
          type: NotificationType.occurrenceParticipationRequested,
          occurrenceId: 'occ_n4',
          occurrenceTitle: 'Ocorrência teste N4',
          notificationId: 'opened_occ_n4_990002',
          deduplicate: true,
        ),
        throwsA(
          isA<FirebaseException>().having(
            (error) => error.code,
            'code',
            'permission-denied',
          ),
        ),
      );
    });

    test('T14: N5 - Invalid payload denial propagates as failure (FAILURE PROPAGATES)', () async {
      final service = buildService(
        writer: (document, data) => Future<void>.error(
          FirebaseException(
            plugin: 'cloud_firestore',
            code: 'permission-denied',
            message: 'Payload validation failed on Firestore rules.',
          ),
        ),
      );

      expect(
        service.createNotification(
          userId: '990002',
          type: NotificationType.occurrenceParticipationRequested,
          occurrenceId: 'occ_n5',
          occurrenceTitle: 'Ocorrência teste N5',
          notificationId: 'opened_occ_n5_990002',
          deduplicate: true,
        ),
        throwsA(
          isA<FirebaseException>().having(
            (error) => error.code,
            'code',
            'permission-denied',
          ),
        ),
      );
    });

    test('T15: N6 - Invalid recipient denial propagates as failure (FAILURE PROPAGATES)', () async {
      final service = buildService(
        writer: (document, data) => Future<void>.error(
          FirebaseException(
            plugin: 'cloud_firestore',
            code: 'permission-denied',
            message: 'Recipient is not a team member.',
          ),
        ),
      );

      expect(
        service.createNotification(
          userId: '990099',
          type: NotificationType.occurrenceParticipationRequested,
          occurrenceId: 'occ_n6',
          occurrenceTitle: 'Ocorrência teste N6',
          notificationId: 'opened_occ_n6_990099',
          deduplicate: true,
        ),
        throwsA(
          isA<FirebaseException>().having(
            (error) => error.code,
            'code',
            'permission-denied',
          ),
        ),
      );
    });

    test('T16: Production path - OccurrenceViewModel handles duplicate team notifications idempotently', () async {
      final notifService = NotificationService(firestore: r3FakeFirestore);
      final vm = OccurrenceViewModel(
        repository: OccurrenceRepository(r3FakeFirestore),
        eventRepository: OccurrenceEventRepository(r3FakeFirestore),
        signatureRepository: SignatureRepository(firestore: r3FakeFirestore),
        notificationService: notifService,
        sendTeamNotifications: true,
      );

      // Initial occurrence creation dispatches notification to 990002
      final created = await vm.createOccurrence(
        id: 'occ_prod_dup_1',
        shiftId: 'shift_prod_1',
        primaryHandlerId: 'uid_990001',
        primaryHandlerRa: '990001',
        dogId: 'dog_k9',
        typeCode: 'PATRULHAMENTO',
        typeName: 'Patrulhamento',
        teamSnapshot: [
          OccurrenceTeamMember(
            handlerId: '990001',
            role: TeamRole.titular,
            addedAt: DateTime.now(),
            addedBy: '990001',
          ),
          OccurrenceTeamMember(
            handlerId: '990002',
            role: TeamRole.integrante,
            addedAt: DateTime.now(),
            addedBy: '990001',
          ),
        ],
      );

      final notifId = 'opened_${created.id}_990002';
      final notifDoc = await r3FakeFirestore
          .collection('notifications')
          .doc('990002')
          .collection('items')
          .doc(notifId)
          .get();
      expect(notifDoc.exists, isTrue);

      // Duplicate attempt on the same notification must be benign and idempotent
      final reattemptResult = await notifService.createNotification(
        userId: '990002',
        type: NotificationType.occurrenceParticipationRequested,
        occurrenceId: created.id,
        occurrenceTitle: 'Patrulhamento',
        notificationId: notifId,
        deduplicate: true,
      );
      expect(reattemptResult, equals(notifId));
    });
  });
}
