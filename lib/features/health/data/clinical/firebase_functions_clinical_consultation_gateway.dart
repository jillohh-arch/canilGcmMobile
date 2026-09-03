import 'package:cloud_firestore/cloud_firestore.dart';

import 'package:canil_gcm/features/health/data/clinical/clinical_consultation_callable_invoker.dart';
import 'package:canil_gcm/features/health/data/clinical/clinical_consultation_callable_names.dart';
import 'package:canil_gcm/features/health/data/clinical/clinical_consultation_error_mapper.dart';
import 'package:canil_gcm/features/health/data/clinical/clinical_consultation_event_parser.dart';
import 'package:canil_gcm/features/health/data/clinical/clinical_consultation_payload_codec.dart';
import 'package:canil_gcm/features/health/domain/clinical_consultation_command.dart';
import 'package:canil_gcm/features/health/domain/clinical_consultation_errors.dart';
import 'package:canil_gcm/features/health/domain/clinical_consultation_gateway.dart';

/// Gateway canônico da Consulta Veterinária.
///
/// Escrita: SOMENTE callables (`Open` / `Append` / `Finalize`). As Rules negam
/// escrita direta de cliente em `clinical_cases` e `clinical_events`
/// (`allow create, update, delete: if false`), então o backend é a única
/// autoridade de mutação.
///
/// Leitura: Firestore direto, autorizado por
/// `hasClinicalReadAuthority() && canAccessDogRecord(dogId)`.
///
/// **Sem fallback legado.** Uma falha nunca é desviada para `HealthLogModel`.
final class FirebaseFunctionsClinicalConsultationGateway
    implements ClinicalConsultationGateway {
  FirebaseFunctionsClinicalConsultationGateway({
    FirebaseFirestore? firestore,
    ClinicalConsultationCallableInvoker? invoker,
  }) : _firestoreOverride = firestore,
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

  /// Status de caso que ainda aceitam novos eventos.
  ///
  /// `discharged` e `cancelled` são terminais no domínio congelado; oferecê-los
  /// no seletor produziria uma falha garantida no Append.
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
        if (revision is! int) continue; // revisão ausente é corrupção

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
      throw ClinicalConsultationErrorMapper.map(error);
    }
  }

  @override
  Future<ConsultationSaveResult> saveConsultation(
    ConsultationCommand command,
  ) async {
    // ── FASE 1: criar o evento clínico (nasce `draft`) ────────────────────
    final ClinicalCreatedEvent created;
    final bool openedNewCase = command.opensNewCase;
    try {
      if (openedNewCase) {
        final response = await _invoke(
          ClinicalConsultationCallableNames.openClinicalCase,
          ClinicalConsultationPayloadCodec.openCaseRequest(command),
        );
        created = ClinicalConsultationPayloadCodec.readOpenResponse(response);
      } else {
        final response = await _invoke(
          ClinicalConsultationCallableNames.appendClinicalEvent,
          ClinicalConsultationPayloadCodec.appendEventRequest(command),
        );
        created = ClinicalConsultationPayloadCodec.readAppendResponse(response);
      }
    } catch (error) {
      // Nada foi confirmado como criado: falha simples, sem pendência.
      return ConsultationSaveFailure(
        ClinicalConsultationErrorMapper.map(error),
      );
    }

    // ── FASE 2: finalizar o MESMO evento ─────────────────────────────────
    return _finalize(
      dogId: command.dogId,
      caseId: created.caseId,
      eventId: created.eventId,
      finalizeOperationId: command.finalizeOperationId,
      expectedRevision: ClinicalConsultationPayloadCodec.freshEventRevision,
      openedNewCase: openedNewCase,
      operationId: command.operationId,
    );
  }

  @override
  Future<ConsultationSaveResult> retryFinalization(
    ConsultationPendingFinalization pending,
  ) {
    // Reusa a identidade original: nenhuma nova consulta é criada.
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
  Future<List<ClinicalConsultationRecordView>> loadCaseConsultations({
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

      final records = <ClinicalConsultationRecordView>[];
      for (final doc in snapshot.docs) {
        final record = ClinicalConsultationEventParser.tryParse(
          caseId: caseId,
          eventId: doc.id,
          data: doc.data(),
        );
        if (record != null) records.add(record);
      }
      records.sort((a, b) => b.occurredAt.compareTo(a.occurredAt));
      return records;
    } catch (error) {
      throw ClinicalConsultationErrorMapper.map(error);
    }
  }

  Future<ConsultationSaveResult> _finalize({
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
        ClinicalConsultationPayloadCodec.finalizeEventRequest(
          dogId: dogId,
          caseId: caseId,
          eventId: eventId,
          operationId: finalizeOperationId,
          expectedRevision: expectedRevision,
        ),
      );
      final finalized =
          ClinicalConsultationPayloadCodec.readFinalizeResponse(response);

      if (!finalized.isFinal) {
        // O servidor respondeu, mas não confirmou `final`. Não declarar sucesso.
        return ConsultationPendingFinalization(
          dogId: dogId,
          caseId: caseId,
          eventId: eventId,
          finalizeOperationId: finalizeOperationId,
          expectedRevision: expectedRevision,
          openedNewCase: openedNewCase,
          failure: const ClinicalConsultationUnexpected(
            message: 'Finalização não confirmada pelo servidor.',
          ),
        );
      }

      if (openedNewCase) {
        return ConsultationOpenedCase(
          dogId: dogId,
          caseId: caseId,
          eventId: eventId,
          wasNoOp: finalized.wasNoOp,
          operationId: operationId ?? finalizeOperationId,
        );
      }
      return ConsultationAppendedToCase(
        dogId: dogId,
        caseId: caseId,
        eventId: eventId,
        wasNoOp: finalized.wasNoOp,
        operationId: operationId ?? finalizeOperationId,
      );
    } catch (error) {
      // O fato clínico existe em `draft`; somente a finalização falhou.
      return ConsultationPendingFinalization(
        dogId: dogId,
        caseId: caseId,
        eventId: eventId,
        finalizeOperationId: finalizeOperationId,
        expectedRevision: expectedRevision,
        openedNewCase: openedNewCase,
        failure: ClinicalConsultationErrorMapper.map(error),
      );
    }
  }
}
