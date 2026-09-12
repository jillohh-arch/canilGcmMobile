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
}
