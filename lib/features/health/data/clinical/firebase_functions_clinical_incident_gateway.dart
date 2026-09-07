import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:canil_gcm/features/health/data/clinical/clinical_consultation_callable_invoker.dart';
import 'package:canil_gcm/features/health/data/clinical/clinical_consultation_callable_names.dart';
import 'package:canil_gcm/features/health/domain/clinical_consultation_gateway.dart'
    show ClinicalCaseOption;
import 'package:canil_gcm/features/health/data/clinical/clinical_consultation_payload_codec.dart'
    show ClinicalCreatedEvent;
import 'package:canil_gcm/features/health/data/clinical/clinical_incident_error_mapper.dart';
import 'package:canil_gcm/features/health/data/clinical/clinical_incident_event_parser.dart';
import 'package:canil_gcm/features/health/data/clinical/clinical_incident_payload_codec.dart';
import 'package:canil_gcm/features/health/domain/clinical_incident_command.dart';
import 'package:canil_gcm/features/health/domain/clinical_incident_errors.dart';
import 'package:canil_gcm/features/health/domain/clinical_incident_gateway.dart';

final class FirebaseFunctionsClinicalIncidentGateway
    implements ClinicalIncidentGateway {
  FirebaseFunctionsClinicalIncidentGateway({
    FirebaseFirestore? firestore,
    ClinicalConsultationCallableInvoker? invoker,
  })  : _firestoreOverride = firestore,
        _invokerOverride = invoker;

  final FirebaseFirestore? _firestoreOverride;
  final ClinicalConsultationCallableInvoker? _invokerOverride;
  ClinicalConsultationCallableInvoker? _cachedInvoker;

  FirebaseFirestore get _db => _firestoreOverride ?? FirebaseFirestore.instance;

  ClinicalConsultationCallableInvoker get _invoke {
    return _cachedInvoker ??=
        _invokerOverride ??
        FirebaseFunctionsClinicalConsultationCallableInvoker().call;
  }

  static const _usableStatuses = <String>{
    'open',
    'under_investigation',
    'under_treatment',
    'monitoring',
  };

  @override
  Future<List<ClinicalCaseOption>> loadUsableCases(String dogId) async {
    try {
      final snapshot = await _db
          .collection('dogs')
          .doc(dogId)
          .collection('clinical_cases')
          .get();

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
        final left = a.openedAt;
        final right = b.openedAt;
        if (left == null && right == null) return a.caseId.compareTo(b.caseId);
        if (left == null) return 1;
        if (right == null) return -1;
        return right.compareTo(left);
      });
      return options;
    } catch (error) {
      throw ClinicalIncidentErrorMapper.map(error);
    }
  }

  @override
  Future<IncidentSaveResult> saveIncident(
    ClinicalIncidentCommand command,
  ) async {
    final ClinicalCreatedEvent created;
    final bool openedNewCase = command.opensNewCase;
    try {
      if (openedNewCase) {
        final response = await _invoke(
          ClinicalConsultationCallableNames.openClinicalCase,
          ClinicalIncidentPayloadCodec.openCaseRequest(command),
        );
        created = ClinicalIncidentPayloadCodec.readOpenResponse(response);
      } else {
        final response = await _invoke(
          ClinicalConsultationCallableNames.appendClinicalEvent,
          ClinicalIncidentPayloadCodec.appendEventRequest(command),
        );
        created = ClinicalIncidentPayloadCodec.readAppendResponse(response);
      }
    } catch (error) {
      return IncidentSaveFailure(
        ClinicalIncidentErrorMapper.map(error),
      );
    }

    return _finalize(
      dogId: command.dogId,
      caseId: created.caseId,
      eventId: created.eventId,
      finalizeOperationId: command.finalizeOperationId,
      expectedRevision: ClinicalIncidentPayloadCodec.freshEventRevision,
      openedNewCase: openedNewCase,
      operationId: command.operationId,
    );
  }

  @override
  Future<IncidentSaveResult> retryFinalization(
    IncidentPendingFinalization pending,
  ) {
    return _finalize(
      dogId: pending.dogId,
      caseId: pending.caseId,
      eventId: pending.eventId,
      finalizeOperationId: pending.finalizeOperationId,
      expectedRevision: pending.expectedRevision,
      openedNewCase: pending.openedNewCase,
      operationId: null,
    );
  }

  @override
  Future<List<ClinicalIncidentRecordView>> loadCaseIncidents({
    required String dogId,
    required String caseId,
  }) async {
    try {
      final snapshot = await _db
          .collection('dogs')
          .doc(dogId)
          .collection('clinical_cases')
          .doc(caseId)
          .collection('clinical_events')
          .get();

      final records = <ClinicalIncidentRecordView>[];
      for (final doc in snapshot.docs) {
        final record = ClinicalIncidentEventParser.tryParse(
          caseId: caseId,
          eventId: doc.id,
          data: doc.data(),
        );
        if (record != null) records.add(record);
      }
      records.sort((a, b) => b.occurredAt.compareTo(a.occurredAt));
      return records;
    } catch (error) {
      throw ClinicalIncidentErrorMapper.map(error);
    }
  }

  Future<IncidentSaveResult> _finalize({
    required String dogId,
    required String caseId,
    required String eventId,
    required String finalizeOperationId,
    required int expectedRevision,
    required bool openedNewCase,
    required String? operationId,
  }) async {
    try {
      final response = await _invoke(
        ClinicalConsultationCallableNames.finalizeClinicalEvent,
        ClinicalIncidentPayloadCodec.finalizeEventRequest(
          dogId: dogId,
          caseId: caseId,
          eventId: eventId,
          operationId: finalizeOperationId,
          expectedRevision: expectedRevision,
        ),
      );
      final finalized =
          ClinicalIncidentPayloadCodec.readFinalizeResponse(response);

      if (!finalized.isFinal) {
        return IncidentPendingFinalization(
          dogId: dogId,
          caseId: caseId,
          eventId: eventId,
          finalizeOperationId: finalizeOperationId,
          expectedRevision: expectedRevision,
          openedNewCase: openedNewCase,
          failure: const ClinicalIncidentUnexpected(
            message: 'Finalização não confirmada pelo servidor.',
          ),
        );
      }

      if (openedNewCase) {
        return IncidentOpenedCase(
          dogId: dogId,
          caseId: caseId,
          eventId: eventId,
          wasNoOp: finalized.wasNoOp,
          operationId: operationId ?? finalizeOperationId,
        );
      }
      return IncidentAppendedToCase(
        dogId: dogId,
        caseId: caseId,
        eventId: eventId,
        wasNoOp: finalized.wasNoOp,
        operationId: operationId ?? finalizeOperationId,
      );
    } catch (error) {
      return IncidentPendingFinalization(
        dogId: dogId,
        caseId: caseId,
        eventId: eventId,
        finalizeOperationId: finalizeOperationId,
        expectedRevision: expectedRevision,
        openedNewCase: openedNewCase,
        failure: ClinicalIncidentErrorMapper.map(error),
      );
    }
  }
}
