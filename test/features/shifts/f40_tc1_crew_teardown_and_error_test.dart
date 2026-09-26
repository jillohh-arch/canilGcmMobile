import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:canil_gcm/features/shifts/data/shift_service.dart';

void main() {
  late FakeFirebaseFirestore fakeFirestore;
  late ShiftService shiftService;

  final now = DateTime(2026, 9, 12, 12, 0);
  const titularRa = '990001';
  const auxiliaryRa = '990002';
  const crewId = 'crew-stg-tc1-01';
  const vehicleId = 'vtr-01';

  setUp(() async {
    fakeFirestore = FakeFirebaseFirestore();
    shiftService = ShiftService(firestore: fakeFirestore);

    // Setup vehicle_crews/{crewId}
    await fakeFirestore.collection('vehicle_crews').doc(crewId).set({
      'id': crewId,
      'vehicle_id': vehicleId,
      'titular_handler_id': titularRa,
      'active': true,
      'crew_size': 2,
    });

    // Setup titular member doc
    await fakeFirestore
        .collection('vehicle_crews')
        .doc(crewId)
        .collection('members')
        .doc(titularRa)
        .set({
      'handler_id': titularRa,
      'role': 'titular',
      'status': 'active',
      'dog_id': 'dog-01',
      'joined_at': now.subtract(const Duration(hours: 2)),
    });

    // Setup auxiliary member doc
    await fakeFirestore
        .collection('vehicle_crews')
        .doc(crewId)
        .collection('members')
        .doc(auxiliaryRa)
        .set({
      'handler_id': auxiliaryRa,
      'role': 'auxiliar_1',
      'status': 'active',
      'joined_at': now.subtract(const Duration(hours: 2)),
    });

    // Setup active_shifts for titular
    await fakeFirestore.collection('active_shifts').doc(titularRa).set({
      'handlerId': titularRa,
      'shiftId': 'shift-titular-01',
      'status': 'active',
      'vehicle_id': vehicleId,
      'vehicle_crew_id': crewId,
      'service_dog_id': 'dog-01',
      'startedAt': now.subtract(const Duration(hours: 2)),
    });

    // Setup active_shifts for auxiliary
    await fakeFirestore.collection('active_shifts').doc(auxiliaryRa).set({
      'handlerId': auxiliaryRa,
      'shiftId': 'shift-aux-01',
      'status': 'active',
      'vehicle_id': vehicleId,
      'vehicle_crew_id': crewId,
      'startedAt': now.subtract(const Duration(hours: 2)),
    });
  });

  group('D5 — Shift Crew Auto-Teardown & Error Propagation Tests', () {
    test('Auxiliary / no-K9 ends shift while in crew updates own member doc without mutating parent crew doc', () async {
      await shiftService.endShift(auxiliaryRa);

      // 1. Auxiliary's active_shift is ended and vehicle fields cleared
      final auxShiftSnap = await fakeFirestore.collection('active_shifts').doc(auxiliaryRa).get();
      expect(auxShiftSnap.data()?['status'], equals('ended'));
      expect(auxShiftSnap.data()?['vehicle_crew_id'], isNull);
      expect(auxShiftSnap.data()?['vehicle_id'], isNull);

      // 2. Auxiliary's crew member doc is ended and dog_id is absent (deleted via FieldValue.delete)
      final auxMemberSnap = await fakeFirestore
          .collection('vehicle_crews')
          .doc(crewId)
          .collection('members')
          .doc(auxiliaryRa)
          .get();
      expect(auxMemberSnap.data()?['status'], equals('ended'));
      expect(auxMemberSnap.data()?.containsKey('dog_id'), isFalse);

      // 3. Parent crew doc was NOT mutated into closed/ended by auxiliary
      final crewSnap = await fakeFirestore.collection('vehicle_crews').doc(crewId).get();
      expect(crewSnap.data()?['active'], isTrue);
    });

    test('Titular ends shift while in crew: closes crew when alone and records history snapshot', () async {
      // First auxiliary leaves
      await fakeFirestore
          .collection('vehicle_crews')
          .doc(crewId)
          .collection('members')
          .doc(auxiliaryRa)
          .update({'status': 'ended'});

      // Titular ends shift
      await shiftService.endShift(titularRa);

      // 1. Titular active_shift is ended
      final titularShiftSnap = await fakeFirestore.collection('active_shifts').doc(titularRa).get();
      expect(titularShiftSnap.data()?['status'], equals('ended'));

      // 2. Parent crew doc is closed
      final crewSnap = await fakeFirestore.collection('vehicle_crews').doc(crewId).get();
      expect(crewSnap.data()?['active'], isFalse);

      // 3. Vehicle crew history snapshot created
      final historySnaps = await fakeFirestore.collection('vehicle_crew_history').get();
      expect(historySnaps.docs.isNotEmpty, isTrue);
      expect(historySnaps.docs.first.data()['vehicle_id'], equals(vehicleId));
    });

    test('Titular ends shift while auxiliary still active: leaves crew open with service_dog_id removed', () async {
      // Titular ends shift while auxiliary is still active
      await shiftService.endShift(titularRa);

      // Crew doc remains active
      final crewSnap = await fakeFirestore.collection('vehicle_crews').doc(crewId).get();
      expect(crewSnap.data()?['active'], isTrue);
      expect(crewSnap.data()?.containsKey('service_dog_id'), isFalse);
    });

    test('Manual leaveVehicle followed by endShift remains successful and clean', () async {
      // 1. Auxiliary leaves vehicle first via leaveVehicle
      await shiftService.leaveVehicle(auxiliaryRa);

      final auxMemberSnap = await fakeFirestore
          .collection('vehicle_crews')
          .doc(crewId)
          .collection('members')
          .doc(auxiliaryRa)
          .get();
      expect(auxMemberSnap.data()?['status'], equals('ended'));

      // 2. Auxiliary ends shift
      await shiftService.endShift(auxiliaryRa);

      final auxShiftAfterEnd = await fakeFirestore.collection('active_shifts').doc(auxiliaryRa).get();
      expect(auxShiftAfterEnd.data()?['status'], equals('ended'));
    });

    test('Denied transaction in endShift propagates error and does not report success', () async {
      final deniedFirestore = _DeniedTransactionFirestore();
      await deniedFirestore.collection('active_shifts').doc(auxiliaryRa).set({
        'ra': auxiliaryRa,
        'status': 'active',
        'vehicle_crew_id': crewId,
      });

      final failingService = ShiftService(firestore: deniedFirestore);

      expect(
        () => failingService.endShift(auxiliaryRa),
        throwsA(
          isA<FirebaseException>().having((e) => e.code, 'code', 'permission-denied'),
        ),
      );
    });
  });
}

class _DeniedTransactionFirestore extends FakeFirebaseFirestore {
  @override
  Future<T> runTransaction<T>(
    TransactionHandler<T> transactionHandler, {
    Duration timeout = const Duration(seconds: 30),
    int maxAttempts = 5,
  }) {
    throw FirebaseException(
      plugin: 'cloud_firestore',
      code: 'permission-denied',
      message: 'Transaction denied by security rules.',
    );
  }
}
