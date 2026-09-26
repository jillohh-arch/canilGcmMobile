import 'dart:async';

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:canil_gcm/core/domain/occurrence_team_member.dart';
import 'package:canil_gcm/features/occurrences/data/occurrence_event_repository.dart';
import 'package:canil_gcm/features/occurrences/data/occurrence_repository.dart';
import 'package:canil_gcm/features/occurrences/data/signature_repository.dart';
import 'package:canil_gcm/features/occurrences/domain/occurrence.dart';
import 'package:canil_gcm/features/occurrences/domain/occurrence_status.dart';
import 'package:canil_gcm/features/occurrences/presentation/view_models/occurrence_view_model.dart';

void main() {
  late FakeFirebaseFirestore fakeFirestore;
  late OccurrenceRepository occurrenceRepo;
  late OccurrenceEventRepository eventRepo;
  late SignatureRepository signatureRepo;
  late OccurrenceViewModel occurrenceVM;

  final now = DateTime(2026, 9, 12, 10, 30);
  const handlerRa = '990002';
  const occ1Id = 'occ_lifecycle_001';
  const occ2Id = 'occ_lifecycle_002';

  Occurrence buildOccurrence({
    required String id,
    required OccurrenceStatus status,
    String address = 'Rua Inicial, 100',
  }) {
    return Occurrence(
      id: id,
      shiftId: 'shift-001',
      primaryHandlerId: '990001',
      primaryHandlerRa: '990001',
      dogId: 'dog-01',
      typeCode: 'TC01',
      typeName: 'Apoio Policial',
      startedAt: now,
      createdAt: now,
      updatedAt: now,
      status: status,
      locationAddress: address,
      team: [
        OccurrenceTeamMember(
          handlerId: '990001',
          role: TeamRole.titular,
          addedAt: now,
          addedBy: '990001',
        ),
        OccurrenceTeamMember(
          handlerId: handlerRa,
          role: TeamRole.integrante,
          addedAt: now,
          addedBy: '990001',
        ),
      ],
      pendingHandlerIds: const [handlerRa],
    );
  }

  setUp(() {
    fakeFirestore = FakeFirebaseFirestore();
    occurrenceRepo = OccurrenceRepository(fakeFirestore);
    eventRepo = OccurrenceEventRepository(fakeFirestore);
    signatureRepo = SignatureRepository(firestore: fakeFirestore);
    occurrenceVM = OccurrenceViewModel(
      repository: occurrenceRepo,
      eventRepository: eventRepo,
      signatureRepository: signatureRepo,
      sendTeamNotifications: false,
    );
  });

  group('D2 — Full Lifecycle & Discovery Deadlock Prevention Tests', () {
    test(
      'Complete 9-step lifecycle: global watchOpenForHandler survives ActiveOccurrenceScreen lifecycle without hijack or deadlock',
      () async {
        // Step 1: MainRootScreen / global layer starts watchOpenForHandler for 990002
        occurrenceVM.watchOpenForHandler(handlerRa);
        expect(occurrenceVM.isWatchingOpen, isTrue);
        expect(occurrenceVM.openOccurrence, isNull);

        await pumpEventQueue();
        await Future<void>.delayed(const Duration(milliseconds: 20));

        // Step 2: An occurrence becomes discoverable
        final occ1 = buildOccurrence(id: occ1Id, status: OccurrenceStatus.inProgress);
        await occurrenceRepo.create(occ1);

        await pumpEventQueue();
        await Future<void>.delayed(const Duration(milliseconds: 50));

        expect(occurrenceVM.openOccurrence, isNotNull);
        expect(occurrenceVM.openOccurrence?.id, equals(occ1Id));
        expect(occurrenceVM.openOccurrence?.locationAddress, equals('Rua Inicial, 100'));

        // Step 3: ActiveOccurrenceScreen opens and establishes ONLY a local watchById subscription
        // CRITICAL CHECK: ActiveOccurrenceScreen must NOT call vm.watchOccurrence(id),
        // which previously cancelled _openSub and hijacked the global discovery stream.
        final screenLocalUpdates = <Occurrence?>[];
        StreamSubscription<Occurrence?>? screenSub = occurrenceVM
            .watchById(occ1Id)
            .listen(screenLocalUpdates.add);

        await pumpEventQueue();
        await Future<void>.delayed(const Duration(milliseconds: 20));

        expect(screenLocalUpdates.isNotEmpty, isTrue);
        expect(screenLocalUpdates.last?.locationAddress, equals('Rua Inicial, 100'));

        // Step 4: Local watchById receives parent-document updates in real time
        await occurrenceRepo.update(occ1Id, {
          'location_address': 'Avenida Central, 500',
          'initial_observation': 'Atualizado pela outra viatura',
        });

        await pumpEventQueue();
        await Future<void>.delayed(const Duration(milliseconds: 50));

        expect(screenLocalUpdates.last?.locationAddress, equals('Avenida Central, 500'));
        expect(screenLocalUpdates.last?.initialObservation, equals('Atualizado pela outra viatura'));

        // Step 5: Global watchOpenForHandler remains active throughout screen usage
        expect(occurrenceVM.isWatchingOpen, isTrue);
        expect(occurrenceVM.openOccurrence?.id, equals(occ1Id));

        // Step 6: ActiveOccurrenceScreen disposes and cancels only its local subscription
        await screenSub.cancel();
        screenSub = null;

        // Step 7: Global discovery watcher still functions without any leak or interruption
        expect(occurrenceVM.isWatchingOpen, isTrue);

        // Step 8: Occurrence 1 is finalized/sealed.
        // Old sealed occurrence MUST NOT remain pinned as active in openOccurrence!
        await occurrenceRepo.update(occ1Id, {
          'status': 'finalized',
        });

        await pumpEventQueue();
        await Future<void>.delayed(const Duration(milliseconds: 50));

        // Because watchOpenForHandler queries status == 'open', sealing occ1
        // automatically drops it from the query and resets openOccurrence to null.
        expect(
          occurrenceVM.openOccurrence,
          isNull,
          reason: 'Sealed occurrence must not remain pinned in openOccurrence',
        );

        // Step 9: A NEW occurrence created afterward is discovered normally (NO DEADLOCK)
        final occ2 = buildOccurrence(
          id: occ2Id,
          status: OccurrenceStatus.inProgress,
          address: 'Praça Nova, 1',
        );
        await occurrenceRepo.create(occ2);

        await pumpEventQueue();
        await Future<void>.delayed(const Duration(milliseconds: 50));

        expect(
          occurrenceVM.openOccurrence,
          isNotNull,
          reason: 'Global watcher must seamlessly discover the new occurrence without restart',
        );
        expect(occurrenceVM.openOccurrence?.id, equals(occ2Id));
        expect(occurrenceVM.openOccurrence?.locationAddress, equals('Praça Nova, 1'));
      },
    );

    test('OccurrenceViewModel watchById does NOT mutate or cancel _openSub', () async {
      occurrenceVM.watchOpenForHandler(handlerRa);
      expect(occurrenceVM.isWatchingOpen, isTrue);

      // Calling watchById multiple times does not change isWatchingOpen or hijack _openSub
      final sub1 = occurrenceVM.watchById('some_id_1').listen((_) {});
      final sub2 = occurrenceVM.watchById('some_id_2').listen((_) {});

      expect(occurrenceVM.isWatchingOpen, isTrue);

      await sub1.cancel();
      await sub2.cancel();

      expect(occurrenceVM.isWatchingOpen, isTrue);
    });
  });
}
