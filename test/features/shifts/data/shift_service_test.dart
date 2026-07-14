import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:canil_gcm/features/shifts/data/shift_service.dart';
import 'package:canil_gcm/features/shifts/domain/vehicle.dart';

void main() {
  const vehicle = Vehicle(
    id: 'canil-1075',
    name: 'Canil',
    prefix: '1075',
    modelName: 'SUV',
    crewSize: 4,
    unit: 'GCM',
    active: true,
  );

  group('ShiftService.assumeVehicle', () {
    test('permite assumir viatura com turno ativo sem K9', () async {
      final firestore = FakeFirebaseFirestore();
      final service = ShiftService(firestore: firestore);
      const handlerId = '691755';
      const shiftId = 'shift-sem-k9';

      await firestore.collection('active_shifts').doc(handlerId).set({
        'shiftId': shiftId,
        'handlerId': handlerId,
        'dogId': '',
        'service_dog_id': '',
        'status': 'active',
        'startedAt': Timestamp.fromDate(DateTime(2026, 7, 13, 8)),
      });
      await firestore.collection('shift_logs').doc(shiftId).set({
        'id': shiftId,
        'handlerId': handlerId,
        'initialDogId': '',
        'currentDogId': '',
        'service_dog_id': '',
        'status': 'active',
        'startedAt': Timestamp.fromDate(DateTime(2026, 7, 13, 8)),
      });

      await service.assumeVehicle(
        handlerId: handlerId,
        dogId: '',
        vehicle: vehicle,
        role: 'motorista',
      );

      final active = await firestore
          .collection('active_shifts')
          .doc(handlerId)
          .get();
      final log = await firestore.collection('shift_logs').doc(shiftId).get();
      final crew = await firestore
          .collection('vehicle_crews')
          .doc(vehicle.id)
          .get();
      final member = await firestore
          .collection('vehicle_crews')
          .doc(vehicle.id)
          .collection('members')
          .doc(handlerId)
          .get();

      expect(active.data()?['shiftId'], shiftId);
      expect(active.data()?['vehicle_id'], vehicle.id);
      expect(active.data()?['service_dog_id'], '');
      expect(log.data()?['vehicle_id'], vehicle.id);
      expect(crew.data()?['service_dog_id'], '');
      expect(crew.data()?['titular_handler_id'], handlerId);
      expect(member.data()?['dog_id'], '');
      expect(member.data()?['status'], 'active');
    });

    test('segundo GCM sem K9 preserva titular e cão da crew ativa', () async {
      final firestore = FakeFirebaseFirestore();
      final service = ShiftService(firestore: firestore);
      const titularId = '111111';
      const secondHandlerId = '222222';
      const secondShiftId = 'shift-segundo-gcm';

      await firestore.collection('active_shifts').doc(titularId).set({
        'shiftId': 'shift-titular',
        'handlerId': titularId,
        'dogId': 'bono',
        'service_dog_id': 'bono',
        'vehicle_id': vehicle.id,
        'status': 'active',
        'startedAt': Timestamp.fromDate(DateTime(2026, 7, 13, 8)),
      });
      await firestore.collection('active_shifts').doc(secondHandlerId).set({
        'shiftId': secondShiftId,
        'handlerId': secondHandlerId,
        'dogId': '',
        'service_dog_id': '',
        'status': 'active',
        'startedAt': Timestamp.fromDate(DateTime(2026, 7, 13, 8)),
      });
      await firestore.collection('shift_logs').doc(secondShiftId).set({
        'id': secondShiftId,
        'handlerId': secondHandlerId,
        'initialDogId': '',
        'currentDogId': '',
        'service_dog_id': '',
        'status': 'active',
        'startedAt': Timestamp.fromDate(DateTime(2026, 7, 13, 8)),
      });
      await firestore.collection('vehicle_crews').doc(vehicle.id).set({
        'id': vehicle.id,
        'vehicle_id': vehicle.id,
        'crew_size': vehicle.crewSize,
        'service_dog_id': 'bono',
        'titular_handler_id': titularId,
        'active': true,
      });
      await firestore
          .collection('vehicle_crews')
          .doc(vehicle.id)
          .collection('members')
          .doc(titularId)
          .set({
            'handler_id': titularId,
            'role': 'motorista',
            'status': 'active',
            'dog_id': 'bono',
          });

      await service.assumeVehicle(
        handlerId: secondHandlerId,
        dogId: '',
        vehicle: vehicle,
        role: 'auxiliar_1',
      );

      final crew = await firestore
          .collection('vehicle_crews')
          .doc(vehicle.id)
          .get();
      final secondMember = await firestore
          .collection('vehicle_crews')
          .doc(vehicle.id)
          .collection('members')
          .doc(secondHandlerId)
          .get();
      final secondActive = await firestore
          .collection('active_shifts')
          .doc(secondHandlerId)
          .get();

      expect(crew.data()?['titular_handler_id'], titularId);
      expect(crew.data()?['service_dog_id'], 'bono');
      expect(secondMember.data()?['dog_id'], '');
      expect(secondMember.data()?['role'], 'auxiliar_1');
      expect(secondActive.data()?['shiftId'], secondShiftId);
      expect(secondActive.data()?['vehicle_id'], vehicle.id);
    });

    test('preserva fluxo normal ao assumir viatura com K9', () async {
      final firestore = FakeFirebaseFirestore();
      final service = ShiftService(firestore: firestore);
      const handlerId = '333333';

      await firestore.collection('active_shifts').doc(handlerId).set({
        'shiftId': 'shift-com-k9',
        'handlerId': handlerId,
        'dogId': 'bono',
        'service_dog_id': 'bono',
        'status': 'active',
        'startedAt': Timestamp.fromDate(DateTime(2026, 7, 13, 8)),
      });

      await service.assumeVehicle(
        handlerId: handlerId,
        dogId: 'bono',
        vehicle: vehicle,
        role: 'motorista',
      );

      final crew = await firestore
          .collection('vehicle_crews')
          .doc(vehicle.id)
          .get();
      final member = await firestore
          .collection('vehicle_crews')
          .doc(vehicle.id)
          .collection('members')
          .doc(handlerId)
          .get();

      expect(crew.data()?['service_dog_id'], 'bono');
      expect(member.data()?['dog_id'], 'bono');
    });
  });

  group('ShiftService.associateDog', () {
    test('mantém o mesmo shiftId ao associar K9 posteriormente', () async {
      final firestore = FakeFirebaseFirestore();
      final service = ShiftService(firestore: firestore);
      const handlerId = '691755';
      const shiftId = 'shift-original';

      await firestore.collection('active_shifts').doc(handlerId).set({
        'shiftId': shiftId,
        'handlerId': handlerId,
        'dogId': '',
        'service_dog_id': '',
        'status': 'active',
        'startedAt': Timestamp.fromDate(DateTime(2026, 7, 13, 8)),
      });
      await firestore.collection('shift_logs').doc(shiftId).set({
        'id': shiftId,
        'handlerId': handlerId,
        'initialDogId': '',
        'currentDogId': '',
        'service_dog_id': '',
        'status': 'active',
        'startedAt': Timestamp.fromDate(DateTime(2026, 7, 13, 8)),
        'dogSwitches': <Map<String, dynamic>>[],
      });
      await firestore.collection('dogs').doc('bono').set({
        'name': 'Bono',
        'status': 'Ativo',
      });

      await service.associateDog(handlerId: handlerId, dogId: 'bono');

      final active = await firestore
          .collection('active_shifts')
          .doc(handlerId)
          .get();
      final logs = await firestore.collection('shift_logs').get();
      final originalLog = await firestore
          .collection('shift_logs')
          .doc(shiftId)
          .get();

      expect(active.data()?['shiftId'], shiftId);
      expect(active.data()?['service_dog_id'], 'bono');
      expect(logs.docs, hasLength(1));
      expect(logs.docs.single.id, shiftId);
      expect(originalLog.data()?['currentDogId'], 'bono');
      expect(originalLog.data()?['service_dog_id'], 'bono');
    });
  });

  test('endShift encerra turno sem K9', () async {
    final firestore = FakeFirebaseFirestore();
    final service = ShiftService(firestore: firestore);
    const handlerId = '444444';
    const shiftId = 'shift-encerrar-sem-k9';

    await firestore.collection('active_shifts').doc(handlerId).set({
      'shiftId': shiftId,
      'handlerId': handlerId,
      'dogId': '',
      'service_dog_id': '',
      'status': 'active',
      'startedAt': Timestamp.fromDate(DateTime(2026, 7, 13, 8)),
    });
    await firestore.collection('shift_logs').doc(shiftId).set({
      'id': shiftId,
      'handlerId': handlerId,
      'initialDogId': '',
      'currentDogId': '',
      'service_dog_id': '',
      'status': 'active',
      'startedAt': Timestamp.fromDate(DateTime(2026, 7, 13, 8)),
    });

    await service.endShift(handlerId);

    final active = await firestore
        .collection('active_shifts')
        .doc(handlerId)
        .get();
    final log = await firestore.collection('shift_logs').doc(shiftId).get();
    expect(active.data()?['status'], 'ended');
    expect(log.data()?['status'], 'ended');
  });
}
