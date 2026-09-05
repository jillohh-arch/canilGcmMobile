// ignore_for_file: subtype_of_sealed_class

import 'package:flutter_test/flutter_test.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';

import 'package:canil_gcm/features/health/data/clinical/treatment_protocol_callable_names.dart';
import 'package:canil_gcm/features/health/data/clinical/firebase_functions_treatment_protocol_gateway.dart';
import 'package:canil_gcm/features/health/domain/dose_administration.dart';
import 'package:canil_gcm/features/health/domain/treatment_protocol_command.dart';
import 'package:canil_gcm/features/health/domain/treatment_protocol_gateway.dart';
import 'package:canil_gcm/features/health/domain/health_v1_enums_ext.dart';
import 'package:canil_gcm/features/health/domain/health_v1_value_objects.dart';

class FakeDocumentSnapshot implements DocumentSnapshot<Map<String, dynamic>> {
  FakeDocumentSnapshot(this._data, this._id);
  final Map<String, dynamic>? _data;
  final String _id;

  @override
  String get id => _id;

  @override
  bool get exists => _data != null;

  @override
  Map<String, dynamic>? data() => _data;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeFirestore implements FirebaseFirestore {
  final Map<String, Map<String, dynamic>> store = {};

  @override
  CollectionReference<Map<String, dynamic>> collection(String collectionPath) {
    return _FakeNestedCollection(this, collectionPath);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeQueryDocumentSnapshot implements QueryDocumentSnapshot<Map<String, dynamic>> {
  FakeQueryDocumentSnapshot(this._data, this._id);
  final Map<String, dynamic> _data;
  final String _id;

  @override
  String get id => _id;

  @override
  bool get exists => true;

  @override
  Map<String, dynamic> data() => _data;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeQuerySnapshot implements QuerySnapshot<Map<String, dynamic>> {
  FakeQuerySnapshot(this._docs);
  final List<QueryDocumentSnapshot<Map<String, dynamic>>> _docs;

  @override
  List<QueryDocumentSnapshot<Map<String, dynamic>>> get docs => _docs;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeNestedCollection implements CollectionReference<Map<String, dynamic>> {
  _FakeNestedCollection(this._db, this._path);
  final FakeFirestore _db;
  final String _path;

  @override
  DocumentReference<Map<String, dynamic>> doc([String? path]) {
    final fullPath = '$_path/${path ?? "auto"}';
    return _FakeNestedDoc(_db, fullPath, path ?? 'auto');
  }

  @override
  Future<QuerySnapshot<Map<String, dynamic>>> get([GetOptions? options]) async {
    final prefix = '$_path/';
    final docs = <QueryDocumentSnapshot<Map<String, dynamic>>>[];
    for (final entry in _db.store.entries) {
      if (entry.key.startsWith(prefix)) {
        final remainder = entry.key.substring(prefix.length);
        if (!remainder.contains('/')) {
          docs.add(FakeQueryDocumentSnapshot(entry.value, remainder));
        }
      }
    }
    return FakeQuerySnapshot(docs);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeNestedDoc implements DocumentReference<Map<String, dynamic>> {
  _FakeNestedDoc(this._db, this._fullPath, this._id);
  final FakeFirestore _db;
  final String _fullPath;
  final String _id;

  @override
  CollectionReference<Map<String, dynamic>> collection(String collectionPath) {
    return _FakeNestedCollection(_db, '$_fullPath/$collectionPath');
  }

  @override
  Future<DocumentSnapshot<Map<String, dynamic>>> get([GetOptions? options]) async {
    final data = _db.store[_fullPath];
    return FakeDocumentSnapshot(data, _id);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  group('FirebaseFunctionsTreatmentProtocolGateway', () {
    late FakeFirestore fakeDb;
    late List<Map<String, dynamic>> calls;

    setUp(() {
      fakeDb = FakeFirestore();
      calls = [];
    });

    Future<Map<String, dynamic>> mockInvoker(
      String functionName,
      Map<String, dynamic> data,
    ) async {
      calls.add({'fn': functionName, 'data': data});
      if (functionName == TreatmentProtocolCallableNames.createTreatmentProtocol) {
        return {
          'success': true,
          'protocolId': 'proto_test_01',
        };
      }
      if (functionName == TreatmentProtocolCallableNames.administerTreatmentDose ||
          functionName == TreatmentProtocolCallableNames.skipTreatmentDose) {
        final plannedDoseId = data['plannedDoseId'] as String;
        final protocolId = data['protocolId'] as String;
        final doseId = DoseIdentity(
          protocolId: protocolId,
          plannedDoseId: plannedDoseId,
        ).deriveDoseId();
        return {
          'success': true,
          'doseId': doseId,
        };
      }
      return {
        'success': true,
        'protocolId': data['protocolId'] ?? 'proto_test_01',
      };
    }

    test('createProtocol sends canonical payload and retrieves protocol', () async {
      final protoPath = 'dogs/dog-1/treatment_protocols/proto_test_01';
      fakeDb.store[protoPath] = {
        'protocol_id': 'proto_test_01',
        'case_id': 'case-1',
        'dog_id': 'dog-1',
        'medication_name': 'Amoxicilina',
        'dose': {
          'value': 500,
          'unit': 'mg',
          'per_kg': false,
          'route': 'oral',
        },
        'schedule': {
          'type': 'interval',
          'interval_minutes': 720,
          'timezone': 'America/Sao_Paulo',
          'tolerance_minutes': 30,
        },
        'start_date': '2026-09-05T12:00:00Z',
        'duration_days': 7,
        'status': 'active',
        'schema_version': 1,
        'recorded_by': {
          'uid': 'u1',
          'name': 'Dr Vet',
          'internal_role': 'veterinario',
        },
        'professional': {
          'name': 'Dr Vet',
          'registration_type': 'crmv',
          'registration_number': '12345',
          'clinic': 'Clinica Vet',
        },
        'source_document': {
          'health_document_id': 'doc-1',
        },
      };

      final gateway = FirebaseFunctionsTreatmentProtocolGateway(
        firestore: fakeDb,
        invoker: mockInvoker,
      );

      final result = await gateway.createProtocol(
        CreateTreatmentProtocolCommand(
          dogId: 'dog-1',
          caseId: 'case-1',
          medicationName: 'Amoxicilina',
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
          startDate: DateTime.utc(2026, 9, 5, 12),
          durationDays: 7,
          professional: ProfessionalIdentity(
            name: 'Dr Vet',
            registrationType: ProfessionalRegistrationType.crmv,
            registrationNumber: '12345',
            clinic: 'Clinica Vet',
          ),
          sourceDocument: const HealthDocumentRef(healthDocumentId: 'doc-1'),
          operationId: 'op_create_01',
        ),
      );

      expect(result, isA<TreatmentProtocolSuccess>());
      final success = result as TreatmentProtocolSuccess;
      expect(success.protocol.id, 'proto_test_01');
      expect(success.protocol.medicationName, 'Amoxicilina');

      expect(calls.length, 1);
      expect(calls.first['fn'], TreatmentProtocolCallableNames.createTreatmentProtocol);
      expect(calls.first['data']['medicationName'], 'Amoxicilina');
    });

    test('administerDose sends correct parameters and retrieves dose record', () async {
      final expectedDoseId = DoseIdentity(
        protocolId: 'proto_test_01',
        plannedDoseId: 'dose_0',
      ).deriveDoseId();
      final dosePath = 'dogs/dog-1/treatment_protocols/proto_test_01/doses/$expectedDoseId';
      fakeDb.store[dosePath] = {
        'dose_id': expectedDoseId,
        'protocol_id': 'proto_test_01',
        'planned_dose_id': 'dose_0',
        'dog_id': 'dog-1',
        'scheduled_for': '2026-09-05T12:00:00Z',
        'status': 'administered',
        'recorded_by': {
          'uid': 'u1',
          'name': 'GCM Condutor',
          'internal_role': 'condutor',
        },
        'recorded_at': '2026-09-05T12:05:00Z',
        'administered_at': '2026-09-05T12:05:00Z',
        'schema_version': 1,
        'observations': 'Sem reação adversa',
      };

      final gateway = FirebaseFunctionsTreatmentProtocolGateway(
        firestore: fakeDb,
        invoker: mockInvoker,
      );

      final result = await gateway.administerDose(
        AdministerDoseCommand(
          dogId: 'dog-1',
          protocolId: 'proto_test_01',
          plannedDoseId: 'dose_0',
          observations: 'Sem reação adversa',
          operationId: 'op_admin_01',
        ),
      );

      expect(result, isA<DoseAdministrationSuccess>());
      final success = result as DoseAdministrationSuccess;
      expect(success.dose.doseId, expectedDoseId);
      expect(success.dose.status, DoseStatus.administered);
      expect(success.dose.observations, 'Sem reação adversa');

      expect(calls.length, 1);
      expect(calls.first['fn'], TreatmentProtocolCallableNames.administerTreatmentDose);
      expect(calls.first['data']['plannedDoseId'], 'dose_0');
    });

    test('skipDose sends skip reason and retrieves updated dose', () async {
      final expectedDoseId = DoseIdentity(
        protocolId: 'proto_test_01',
        plannedDoseId: 'dose_1',
      ).deriveDoseId();
      final dosePath = 'dogs/dog-1/treatment_protocols/proto_test_01/doses/$expectedDoseId';
      fakeDb.store[dosePath] = {
        'dose_id': expectedDoseId,
        'protocol_id': 'proto_test_01',
        'planned_dose_id': 'dose_1',
        'dog_id': 'dog-1',
        'scheduled_for': '2026-09-05T20:00:00Z',
        'status': 'skipped',
        'recorded_by': {
          'uid': 'u1',
          'name': 'GCM Condutor',
          'internal_role': 'condutor',
        },
        'recorded_at': '2026-09-05T20:00:00Z',
        'schema_version': 1,
        'skip_reason': 'Cão apresentando êmese',
      };

      final gateway = FirebaseFunctionsTreatmentProtocolGateway(
        firestore: fakeDb,
        invoker: mockInvoker,
      );

      final result = await gateway.skipDose(
        SkipDoseCommand(
          dogId: 'dog-1',
          protocolId: 'proto_test_01',
          plannedDoseId: 'dose_1',
          skipReason: 'Cão apresentando êmese',
          operationId: 'op_skip_01',
        ),
      );

      expect(result, isA<DoseAdministrationSuccess>());
      final success = result as DoseAdministrationSuccess;
      expect(success.dose.doseId, expectedDoseId);
      expect(success.dose.status, DoseStatus.skipped);
      expect(success.dose.skipReason, 'Cão apresentando êmese');

      expect(calls.length, 1);
      expect(calls.first['fn'], TreatmentProtocolCallableNames.skipTreatmentDose);
      expect(calls.first['data']['skipReason'], 'Cão apresentando êmese');
    });

    test('maps FirebaseFunctionsException to TreatmentProtocolFailure', () async {
      Future<Map<String, dynamic>> failingInvoker(
        String functionName,
        Map<String, dynamic> data,
      ) async {
        throw FirebaseFunctionsException(
          code: 'permission-denied',
          message: 'Usuário não tem autorização para registrar administração de dose.',
        );
      }

      final gateway = FirebaseFunctionsTreatmentProtocolGateway(
        firestore: fakeDb,
        invoker: failingInvoker,
      );

      final result = await gateway.administerDose(
        AdministerDoseCommand(
          dogId: 'dog-1',
          protocolId: 'proto_test_01',
          plannedDoseId: 'dose_0',
          operationId: 'op_err_01',
        ),
      );

      expect(result, isA<TreatmentProtocolFailure>());
      final failure = result as TreatmentProtocolFailure;
      expect(failure.code, 'permission-denied');
      expect(failure.message, contains('não tem autorização'));
    });
  });
}
