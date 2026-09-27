import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:canil_gcm/core/domain/occurrence_team_member.dart';
import 'package:canil_gcm/features/occurrences/data/occurrence_event_repository.dart';
import 'package:canil_gcm/features/occurrences/data/occurrence_repository.dart';
import 'package:canil_gcm/features/occurrences/data/signature_repository.dart';
import 'package:canil_gcm/features/occurrences/domain/occurrence.dart';
import 'package:canil_gcm/features/occurrences/domain/occurrence_start_eligibility.dart';
import 'package:canil_gcm/features/occurrences/domain/occurrence_status.dart';
import 'package:canil_gcm/features/occurrences/presentation/view_models/occurrence_view_model.dart';
import 'package:canil_gcm/features/app_shell/presentation/screens/main_root_screen.dart';
import 'package:canil_gcm/features/shifts/presentation/screens/active_shift_dashboard_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeFirebaseFirestore fakeFirestore;
  late OccurrenceRepository repository;
  late OccurrenceViewModel viewModel;

  final now = DateTime(2026, 9, 27, 2, 0);

  Occurrence buildTestOccurrence({
    required String id,
    String dogId = 'dog-001',
    String? primaryHandlerRa = '691755',
    String primaryHandlerId = 'uid-691755',
    List<String> teamHandlerIds = const ['691755'],
    OccurrenceStatus status = OccurrenceStatus.inProgress,
    DateTime? updatedAt,
  }) {
    final effectiveUpdatedAt = updatedAt ?? now;
    return Occurrence(
      id: id,
      shiftId: 'shift-001',
      primaryHandlerId: primaryHandlerId,
      primaryHandlerRa: primaryHandlerRa,
      dogId: dogId,
      typeCode: 'PATRULHAMENTO',
      typeName: 'Patrulhamento',
      locationAddress: 'Av. Campinas, 500',
      gpsLat: -22.5642,
      gpsLng: -47.4019,
      startedAt: now,
      createdAt: now,
      updatedAt: effectiveUpdatedAt,
      status: status,
      team: teamHandlerIds
          .map(
            (ra) => OccurrenceTeamMember(
              handlerId: ra,
              role: ra == primaryHandlerRa ? TeamRole.titular : TeamRole.integrante,
              addedAt: now,
              addedBy: primaryHandlerRa ?? 'admin',
            ),
          )
          .toList(),
    );
  }

  setUp(() {
    fakeFirestore = FakeFirebaseFirestore();
    repository = OccurrenceRepository(fakeFirestore);
    viewModel = OccurrenceViewModel(
      repository: repository,
      eventRepository: OccurrenceEventRepository(fakeFirestore),
      signatureRepository: SignatureRepository(firestore: fakeFirestore),
      sendTeamNotifications: false,
    );
  });

  tearDown(() {
    viewModel.dispose();
  });

  group('CT3.F40.OCC-01 — Active Occurrence Discovery Contract', () {
    test('1. Conductor discovery: primary_handler_ra matches even if team_handler_ids is unpopulated', () async {
      // Legacy or minimal occurrence where team_handler_ids was not populated
      final occ = Occurrence(
        id: 'occ-primary-only',
        shiftId: 'shift-001',
        primaryHandlerId: 'uid-conductor',
        primaryHandlerRa: '691755',
        dogId: '',
        typeCode: 'AVERIGUACAO',
        typeName: 'Averiguação',
        startedAt: now,
        createdAt: now,
        updatedAt: now,
        status: OccurrenceStatus.inProgress,
        team: const [],
      );
      await fakeFirestore.collection('occurrences').doc(occ.id).set(occ.toMap());

      // Query via findOpenForHandler
      final found = await repository.findOpenForHandler('691755');
      expect(found, isNotNull);
      expect(found!.id, equals('occ-primary-only'));

      // Stream via watchOpenForHandler
      final streamed = await repository.watchOpenForHandler('691755').first;
      expect(streamed, isNotNull);
      expect(streamed!.id, equals('occ-primary-only'));

      // Context discovery
      final contextFound = await repository.findOpenForContext(handlerRa: '691755');
      expect(contextFound, isNotNull);
      expect(contextFound!.id, equals('occ-primary-only'));
    });

    test('2. Participant without K9: discovered by team member when dogId is empty', () async {
      final occ = buildTestOccurrence(
        id: 'occ-no-k9-team',
        dogId: '',
        primaryHandlerRa: '691755',
        teamHandlerIds: ['691755', '691640'],
      );
      await repository.create(occ);

      // Participant '691640' has no dog assigned, but is part of the crew
      final found = await repository.findOpenForContext(
        dogId: null,
        handlerRa: '691640',
      );
      expect(found, isNotNull);
      expect(found!.id, equals('occ-no-k9-team'));
      expect(found.teamHandlerIds, contains('691640'));

      final streamed = await repository.watchOpenForContext(
        dogId: null,
        handlerRa: '691640',
      ).first;
      expect(streamed, isNotNull);
      expect(streamed!.id, equals('occ-no-k9-team'));
    });

    test('3. Crew lookup: all crew members discover open occurrence simultaneously', () async {
      final occ = buildTestOccurrence(
        id: 'occ-crew',
        primaryHandlerRa: '691755',
        teamHandlerIds: ['691755', '691640', '691800'],
      );
      await repository.create(occ);

      for (final ra in ['691755', '691640', '691800']) {
        final found = await repository.findOpenForHandler(ra);
        expect(found, isNotNull, reason: 'Member $ra must find open occurrence');
        expect(found!.id, equals('occ-crew'));
      }
    });

    test('4. K9 attribution: discovered by dogId even if handlerRa is omitted or different', () async {
      final occ = buildTestOccurrence(
        id: 'occ-k9-alpha',
        dogId: 'dog-k9-alpha',
        primaryHandlerRa: '691755',
      );
      await repository.create(occ);

      final foundByDog = await repository.findOpen('dog-k9-alpha');
      expect(foundByDog, isNotNull);
      expect(foundByDog!.id, equals('occ-k9-alpha'));

      final streamed = await repository.watchOpen('dog-k9-alpha').first;
      expect(streamed, isNotNull);
      expect(streamed!.id, equals('occ-k9-alpha'));
    });

    test('5. Closed occurrence exclusion: finalized and sealed occurrences are excluded', () async {
      final occClosed = buildTestOccurrence(
        id: 'occ-closed',
        primaryHandlerRa: '691755',
        status: OccurrenceStatus.finalized,
      );
      await repository.create(occClosed);

      final occPendingSig = buildTestOccurrence(
        id: 'occ-sealed-pending',
        primaryHandlerRa: '691755',
        status: OccurrenceStatus.finalizedWithPending,
      );
      await repository.create(occPendingSig);

      final foundHandler = await repository.findOpenForHandler('691755');
      expect(foundHandler, isNull);

      final foundContext = await repository.findOpenForContext(
        dogId: 'dog-001',
        handlerRa: '691755',
      );
      expect(foundContext, isNull);

      final streamed = await repository.watchOpenForContext(
        dogId: 'dog-001',
        handlerRa: '691755',
      ).first;
      expect(streamed, isNull);
    });

    test('6. Soft-deleted occurrence exclusion: deleted occurrences are excluded', () async {
      final occ = buildTestOccurrence(
        id: 'occ-to-delete',
        primaryHandlerRa: '691755',
      );
      await repository.create(occ);
      await repository.softDelete('occ-to-delete', '691755', 'Cancelado para teste');

      final found = await repository.findOpenForContext(
        dogId: 'dog-001',
        handlerRa: '691755',
      );
      expect(found, isNull);
    });

    test('7. Multiple candidates: returns most recently updated active occurrence', () async {
      final olderOcc = buildTestOccurrence(
        id: 'occ-older',
        dogId: 'dog-001',
        primaryHandlerRa: '691755',
        updatedAt: now.subtract(const Duration(hours: 1)),
      );
      final newerOcc = buildTestOccurrence(
        id: 'occ-newer',
        dogId: '',
        primaryHandlerRa: '691755',
        teamHandlerIds: ['691755'],
        updatedAt: now,
      );
      await repository.create(olderOcc);
      await repository.create(newerOcc);

      final found = await repository.findOpenForContext(
        dogId: 'dog-001',
        handlerRa: '691755',
      );
      expect(found, isNotNull);
      expect(found!.id, equals('occ-newer'), reason: 'Must return most recently updated');
    });

    test('8. OccurrenceViewModel watchOpenForContext captures both dog and handler stream', () async {
      viewModel.watchOpenForContext(dogId: 'dog-001', handlerRa: '691755');

      final occ = buildTestOccurrence(
        id: 'occ-vm-test',
        dogId: '',
        primaryHandlerRa: '691755',
      );
      await repository.create(occ);

      // Allow microtask to process stream emission
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(viewModel.hasOpen, isTrue);
      expect(viewModel.openOccurrence?.id, equals('occ-vm-test'));
    });
  });

  group('CT3.F40.OCC-02 — Entrypoint Fail-Safe Recovery Orchestration', () {
    test('Root entrypoint recovers open occurrence even if shift is inactive or stale', () async {
      var recovered = false;
      var navigated = false;
      String? blockedMessage;

      await routeRootOccurrenceEntrypoint(
        hasOpenOccurrence: true,
        eligibility: OccurrenceStartEligibility.noActiveShift,
        onRecoverOpenOccurrence: () async => recovered = true,
        onStartNewOccurrence: () => navigated = true,
        onBlocked: (msg) => blockedMessage = msg,
      );

      expect(recovered, isTrue, reason: 'Active occurrence recovery must precede shift eligibility guard');
      expect(navigated, isFalse);
      expect(blockedMessage, isNull);
    });

    test('Quick action entrypoint recovers open occurrence when active occurrence exists', () {
      var recovered = false;
      var navigated = false;
      String? blockedMessage;

      routeQuickActionOccurrenceEntrypoint(
        hasOpenOccurrence: true,
        eligibility: OccurrenceStartEligibility.noVehicleCrew,
        onRecoverOpenOccurrence: () => recovered = true,
        onStartNewOccurrence: () => navigated = true,
        onBlocked: (msg) => blockedMessage = msg,
      );

      expect(recovered, isTrue, reason: 'Quick actions must recover active occurrence rather than start new one');
      expect(navigated, isFalse);
      expect(blockedMessage, isNull);
    });

    test('Quick action entrypoint blocks creation when crew missing and no open occurrence exists', () {
      var recovered = false;
      var navigated = false;
      String? blockedMessage;

      routeQuickActionOccurrenceEntrypoint(
        hasOpenOccurrence: false,
        eligibility: OccurrenceStartEligibility.noVehicleCrew,
        onRecoverOpenOccurrence: () => recovered = true,
        onStartNewOccurrence: () => navigated = true,
        onBlocked: (msg) => blockedMessage = msg,
      );

      expect(recovered, isFalse);
      expect(navigated, isFalse);
      expect(blockedMessage, contains('Assuma uma viatura'));
    });
  });
}
