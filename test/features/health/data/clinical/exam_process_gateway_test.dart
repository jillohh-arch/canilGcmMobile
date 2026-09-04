// ignore_for_file: subtype_of_sealed_class

import 'package:flutter_test/flutter_test.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';

import 'package:canil_gcm/features/health/data/clinical/exam_process_callable_names.dart';
import 'package:canil_gcm/features/health/data/clinical/firebase_functions_exam_process_gateway.dart';
import 'package:canil_gcm/features/health/domain/exam_process_command.dart';
import 'package:canil_gcm/features/health/domain/exam_process_gateway.dart';
import 'package:canil_gcm/features/health/domain/health_v1_enums.dart';
import 'package:canil_gcm/features/health/domain/health_v1_enums_ext.dart';

// Fake DocumentSnapshot para simular a resposta de leitura do Firestore
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

// Fake DocumentReference
class FakeDocumentReference implements DocumentReference<Map<String, dynamic>> {
  FakeDocumentReference(this._data, this._id);
  final Map<String, dynamic>? _data;
  final String _id;

  @override
  Future<DocumentSnapshot<Map<String, dynamic>>> get([GetOptions? options]) async {
    return FakeDocumentSnapshot(_data, _id);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

// Fake CollectionReference
class FakeCollectionReference implements CollectionReference<Map<String, dynamic>> {
  FakeCollectionReference(this._dataStore);
  final Map<String, Map<String, dynamic>> _dataStore;

  @override
  DocumentReference<Map<String, dynamic>> doc([String? path]) {
    final id = path ?? 'doc-1';
    return FakeDocumentReference(_dataStore[id], id);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

// Fake Firestore
class FakeFirestore implements FirebaseFirestore {
  final Map<String, Map<String, dynamic>> store = {};

  @override
  CollectionReference<Map<String, dynamic>> collection(String collectionPath) {
    return _FakeNestedCollection(this, collectionPath);
  }

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
  group('FirebaseFunctionsExamProcessGateway', () {
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
      return {
        'success': true,
        'examId': data['examId'] ?? 'exam-test-1',
        'stage': 'requested',
      };
    }

    test('requestExam envia payload canônico e busca resultado', () async {
      final examPath = 'dogs/dog-1/clinical_cases/case-1/exams/exam-test-1';
      fakeDb.store[examPath] = {
        'exam_id': 'exam-test-1',
        'case_id': 'case-1',
        'dog_id': 'dog-1',
        'title': 'Hemograma',
        'exam_type': 'blood_work',
        'current_stage': 'requested',
        'created_at': '2026-09-04T12:00:00Z',
        'requested_at': '2026-09-04T12:00:00Z',
        'recorded_by': {
          'uid': 'u1',
          'name': 'GCM',
          'internal_role': 'condutor',
        },
        'schema_version': 1,
      };

      final gateway = FirebaseFunctionsExamProcessGateway(
        firestore: fakeDb,
        invoker: mockInvoker,
      );

      final result = await gateway.requestExam(
        const RequestExamCommand(
          dogId: 'dog-1',
          caseId: 'case-1',
          title: 'Hemograma',
          examType: ExamType.bloodWork,
          operationId: 'op-1',
        ),
      );

      expect(result, isA<ExamProcessSuccess>());
      final success = result as ExamProcessSuccess;
      expect(success.exam.id, 'exam-test-1');
      expect(success.exam.stage, ExamStage.requested);

      expect(calls.length, 1);
      expect(calls.first['fn'], ExamProcessCallableNames.requestExam);
      expect(calls.first['data']['title'], 'Hemograma');
    });

    test('mapeia erro do backend para ExamProcessFailure', () async {
      Future<Map<String, dynamic>> failingInvoker(
        String functionName,
        Map<String, dynamic> data,
      ) async {
        throw FirebaseFunctionsException(
          code: 'permission-denied',
          message: 'Sem permissao',
        );
      }

      final gateway = FirebaseFunctionsExamProcessGateway(
        firestore: fakeDb,
        invoker: failingInvoker,
      );

      final result = await gateway.requestExam(
        const RequestExamCommand(
          dogId: 'dog-1',
          caseId: 'case-1',
          title: 'Hemograma',
          examType: ExamType.bloodWork,
          operationId: 'op-err',
        ),
      );

      expect(result, isA<ExamProcessFailure>());
      final failure = result as ExamProcessFailure;
      expect(failure.code, 'permission-denied');
      expect(failure.message, 'Sem permissao');
    });
  });
}
