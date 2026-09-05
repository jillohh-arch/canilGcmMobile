import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';

import 'package:canil_gcm/features/health/domain/clinical_consultation_gateway.dart';
import 'package:canil_gcm/features/health/domain/exam_process.dart';
import 'package:canil_gcm/features/health/domain/exam_process_command.dart';
import 'package:canil_gcm/features/health/domain/exam_process_gateway.dart';
import 'exam_process_callable_names.dart';

typedef ExamCallableInvoker = Future<Map<String, dynamic>> Function(
  String functionName,
  Map<String, dynamic> data,
);

final class FirebaseFunctionsExamProcessGateway implements ExamProcessGateway {
  FirebaseFunctionsExamProcessGateway({
    FirebaseFirestore? firestore,
    ExamCallableInvoker? invoker,
  })  : _firestore = firestore,
        _invokerOverride = invoker;

  final FirebaseFirestore? _firestore;
  final ExamCallableInvoker? _invokerOverride;
  ExamCallableInvoker? _cachedInvoker;

  FirebaseFirestore get _db => _firestore ?? FirebaseFirestore.instance;

  ExamCallableInvoker get _invoke {
    return _cachedInvoker ??= _invokerOverride ?? _defaultInvoker;
  }

  Future<Map<String, dynamic>> _defaultInvoker(
    String functionName,
    Map<String, dynamic> data,
  ) async {
    final functions = FirebaseFunctions.instanceFor(
      region: ExamProcessCallableNames.region,
    );
    final callable = functions.httpsCallable(functionName);
    final result = await callable.call(data);
    final payload = result.data;
    if (payload is Map) {
      return Map<String, dynamic>.from(payload);
    }
    throw FirebaseFunctionsException(
      code: 'internal',
      message: 'Resposta do callable em formato inesperado.',
    );
  }

  static const _usableStatuses = {
    'open',
    'under_investigation',
    'under_treatment',
    'monitoring',
  };

  @override
  Future<List<ClinicalCaseOption>> loadUsableCases(String dogId) async {
    QuerySnapshot<Map<String, dynamic>> snapshot;
    try {
      snapshot = await _db
          .collection('dogs')
          .doc(dogId)
          .collection('clinical_cases')
          .get(const GetOptions(source: Source.server))
          .timeout(const Duration(seconds: 4));
    } catch (_) {
      snapshot = await _db
          .collection('dogs')
          .doc(dogId)
          .collection('clinical_cases')
          .get();
    }

    final options = <ClinicalCaseOption>[];
    for (final doc in snapshot.docs) {
      final data = doc.data();
      final status = (data['clinical_status'] as String?)?.trim();
      if (status == null || !_usableStatuses.contains(status)) continue;

      final revision = data['revision'];
      if (revision is! int) continue;

      options.add(
        ClinicalCaseOption(
          caseId: doc.id,
          title: (data['title'] as String?)?.trim().isNotEmpty == true
              ? (data['title'] as String).trim()
              : 'Caso clínico',
          statusWireName: status,
          revision: revision,
          openedAt: (data['opened_at'] as Timestamp?)?.toDate(),
        ),
      );
    }

    options.sort((a, b) {
      final aDate = a.openedAt;
      final bDate = b.openedAt;
      if (aDate == null && bDate == null) return 0;
      if (aDate == null) return 1;
      if (bDate == null) return -1;
      return bDate.compareTo(aDate);
    });

    return options;
  }

  @override
  Future<List<ExamProcess>> loadCaseExams({
    required String dogId,
    required String caseId,
  }) async {
    QuerySnapshot<Map<String, dynamic>> snapshot;
    try {
      snapshot = await _db
          .collection('dogs')
          .doc(dogId)
          .collection('clinical_cases')
          .doc(caseId)
          .collection('exams')
          .get(const GetOptions(source: Source.server))
          .timeout(const Duration(seconds: 4));
    } catch (_) {
      snapshot = await _db
          .collection('dogs')
          .doc(dogId)
          .collection('clinical_cases')
          .doc(caseId)
          .collection('exams')
          .get();
    }

    final exams = <ExamProcess>[];
    for (final doc in snapshot.docs) {
      try {
        final exam = ExamProcess.fromMap(doc.data(), documentId: doc.id);
        exams.add(exam);
      } catch (e, st) {
        assert(() {
          debugPrint('[ExamGateway] Erro ao parsear exame ${doc.id}: $e\n$st');
          return true;
        }());
      }
    }

    exams.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return exams;
  }

  @override
  Stream<List<ExamProcess>> watchCaseExams({
    required String dogId,
    required String caseId,
  }) {
    return _db
        .collection('dogs')
        .doc(dogId)
        .collection('clinical_cases')
        .doc(caseId)
        .collection('exams')
        .snapshots()
        .map((snapshot) {
      final exams = <ExamProcess>[];
      for (final doc in snapshot.docs) {
        try {
          final exam = ExamProcess.fromMap(doc.data(), documentId: doc.id);
          exams.add(exam);
        } catch (e, st) {
          assert(() {
            debugPrint(
              '[ExamGateway] Erro ao parsear exame no stream ${doc.id}: $e\n$st',
            );
            return true;
          }());
        }
      }
      exams.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      return exams;
    });
  }

  @override
  Future<ExamProcessResult> requestExam(RequestExamCommand command) async {
    try {
      final payload = <String, dynamic>{
        'dogId': command.dogId,
        'caseId': command.caseId,
        'title': command.title,
        'examType': command.examType.wireName,
        'urgency': command.urgency.wireName,
        'operationId': command.operationId,
      };
      if (command.labName != null && command.labName!.isNotEmpty) {
        payload['labName'] = command.labName;
      }
      if (command.requestReason != null && command.requestReason!.isNotEmpty) {
        payload['requestReason'] = command.requestReason;
      }
      if (command.professional != null) {
        payload['professional'] = {
          'name': command.professional!.name,
          'registration_type': command.professional!.registrationType.wireName,
          'registration_number': command.professional!.registrationNumber,
          'clinic': command.professional!.clinic,
          if (command.professional!.specialty != null)
            'specialty': command.professional!.specialty,
        };
      }

      final res = await _invoke(ExamProcessCallableNames.requestExam, payload);
      final examId = res['examId'] as String? ?? '';
      final exam = await _fetchExam(command.dogId, command.caseId, examId);
      return ExamProcessSuccess(exam);
    } catch (e) {
      return _mapError(e);
    }
  }

  @override
  Future<ExamProcessResult> recordCollection(
    RecordExamCollectionCommand command,
  ) async {
    try {
      final payload = <String, dynamic>{
        'dogId': command.dogId,
        'caseId': command.caseId,
        'examId': command.examId,
        'operationId': command.operationId,
      };
      if (command.collectionSite != null && command.collectionSite!.isNotEmpty) {
        payload['collectionSite'] = command.collectionSite;
      }
      if (command.collectionNotes != null && command.collectionNotes!.isNotEmpty) {
        payload['collectionNotes'] = command.collectionNotes;
      }

      await _invoke(ExamProcessCallableNames.recordCollection, payload);
      final exam = await _fetchExam(command.dogId, command.caseId, command.examId);
      return ExamProcessSuccess(exam);
    } catch (e) {
      return _mapError(e);
    }
  }

  @override
  Future<ExamProcessResult> recordResult(RecordExamResultCommand command) async {
    try {
      final payload = <String, dynamic>{
        'dogId': command.dogId,
        'caseId': command.caseId,
        'examId': command.examId,
        'resultSummary': command.resultSummary,
        'operationId': command.operationId,
      };
      if (command.resultDocumentId != null && command.resultDocumentId!.isNotEmpty) {
        payload['resultDocumentId'] = command.resultDocumentId;
      }

      await _invoke(ExamProcessCallableNames.recordResult, payload);
      final exam = await _fetchExam(command.dogId, command.caseId, command.examId);
      return ExamProcessSuccess(exam);
    } catch (e) {
      return _mapError(e);
    }
  }

  @override
  Future<ExamProcessResult> recordInterpretation(
    RecordExamInterpretationCommand command,
  ) async {
    try {
      final payload = <String, dynamic>{
        'dogId': command.dogId,
        'caseId': command.caseId,
        'examId': command.examId,
        'interpretationText': command.interpretationText,
        'professional': {
          'name': command.professional.name,
          'registration_type': command.professional.registrationType.wireName,
          'registration_number': command.professional.registrationNumber,
          'clinic': command.professional.clinic,
          if (command.professional.specialty != null)
            'specialty': command.professional.specialty,
        },
        'operationId': command.operationId,
      };
      if (command.interpretationDocumentId != null &&
          command.interpretationDocumentId!.isNotEmpty) {
        payload['interpretationDocumentId'] = command.interpretationDocumentId;
      }

      await _invoke(ExamProcessCallableNames.recordInterpretation, payload);
      final exam = await _fetchExam(command.dogId, command.caseId, command.examId);
      return ExamProcessSuccess(exam);
    } catch (e) {
      return _mapError(e);
    }
  }

  @override
  Future<ExamProcessResult> assessImpact(AssessExamImpactCommand command) async {
    try {
      final payload = <String, dynamic>{
        'dogId': command.dogId,
        'caseId': command.caseId,
        'examId': command.examId,
        'operationalImpact': {
          'level': command.operationalImpact.level.wireName,
          'description': command.operationalImpact.description,
          'restrictions_issued': command.operationalImpact.restrictionsIssued,
        },
        'operationId': command.operationId,
      };

      await _invoke(ExamProcessCallableNames.assessImpact, payload);
      final exam = await _fetchExam(command.dogId, command.caseId, command.examId);
      return ExamProcessSuccess(exam);
    } catch (e) {
      return _mapError(e);
    }
  }

  @override
  Future<ExamProcessResult> cancelExam(CancelExamCommand command) async {
    try {
      final payload = <String, dynamic>{
        'dogId': command.dogId,
        'caseId': command.caseId,
        'examId': command.examId,
        'cancelReason': command.cancelReason,
        'operationId': command.operationId,
      };

      await _invoke(ExamProcessCallableNames.cancelExam, payload);
      final exam = await _fetchExam(command.dogId, command.caseId, command.examId);
      return ExamProcessSuccess(exam);
    } catch (e) {
      return _mapError(e);
    }
  }

  Future<ExamProcess> _fetchExam(
    String dogId,
    String caseId,
    String examId,
  ) async {
    DocumentSnapshot<Map<String, dynamic>> doc;
    try {
      doc = await _db
          .collection('dogs')
          .doc(dogId)
          .collection('clinical_cases')
          .doc(caseId)
          .collection('exams')
          .doc(examId)
          .get(const GetOptions(source: Source.server))
          .timeout(const Duration(seconds: 4));
    } catch (_) {
      doc = await _db
          .collection('dogs')
          .doc(dogId)
          .collection('clinical_cases')
          .doc(caseId)
          .collection('exams')
          .doc(examId)
          .get();
    }
    if (!doc.exists || doc.data() == null) {
      throw Exception('Exame $examId não encontrado após mutação.');
    }
    return ExamProcess.fromMap(doc.data()!, documentId: doc.id);
  }

  ExamProcessFailure _mapError(Object e) {
    if (e is FirebaseFunctionsException) {
      return ExamProcessFailure(
        code: e.code,
        message: e.message ?? 'Erro ao processar exame no backend.',
        cause: e,
      );
    }
    return ExamProcessFailure(
      code: 'unknown',
      message: e.toString(),
      cause: e,
    );
  }
}
