import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../../data/coexistence/summary/health_readiness_convergence_gateway.dart';
import '../../domain/health_document_gateway.dart';
import '../../domain/health_restriction_flow_errors.dart';
import '../../domain/health_restriction_lifecycle_gateway.dart';
import '../../domain/health_v1_value_objects.dart';
import 'health_restriction_convergence_coordinator.dart';
// `HealthEvidenceIntent` é reusada do fluxo de emissão: a intenção documental
// (arquivo + natureza + título) é idêntica nas duas verticais, e duplicá-la
// criaria dois fingerprints para manter em sincronia. O controller de ISSUE não
// é tocado.
import 'health_restriction_issue_controller.dart' show HealthEvidenceIntent;

/// Progresso do encerramento.
///
/// Quatro etapas com progresso preservado em memória durante a sessão antes do
/// comando terminal: cada uma concluída é fato no backend e não se refaz em
/// retry dentro da mesma sessão. Process death perde os operationIds.
enum HealthRestrictionEndStage {
  idle,
  documentPreparing,
  documentPrepared,
  documentUploading,
  documentUploaded,
  documentFinalizing,
  documentFinalized,
  ending,
  success,
  failure,
}

/// Intenção de encerramento (liberação clínica documentada).
final class HealthRestrictionEndIntent {
  const HealthRestrictionEndIntent({
    required this.dogId,
    required this.restrictionId,
    required this.endReason,
    required this.endProfessional,
  });

  final String dogId;
  final String restrictionId;
  final String endReason;

  /// Profissional EXTERNO que decidiu a liberação.
  final ProfessionalIdentity endProfessional;

  /// Chave determinística da intenção terminal.
  ///
  /// Inclui a evidência já finalizada: se o documento mudar, o payload de END
  /// muda, então a chave de operação precisa mudar também — reusá-la produziria
  /// `idempotency-conflict` no backend, corretamente.
  String fingerprintWith(HealthDocumentRef reference) => [
    dogId,
    restrictionId,
    endReason.trim(),
    endProfessional.name,
    endProfessional.registrationType.wireName,
    endProfessional.registrationNumber,
    endProfessional.clinic,
    endProfessional.specialty?.trim() ?? '',
    reference.healthDocumentId,
  ].join(' ');
}

/// Encerra uma restrição com evidência clínica documentada.
///
/// Orquestra PREPARE → upload → FINALIZE → END preservando progresso por etapa,
/// exatamente como o fluxo de emissão. Reusa integralmente a foundation
/// documental do B3: nenhum pipeline novo de documento é criado aqui.
///
/// Não navega, não faz fetch de detalhe, não refresca o resumo e não lê
/// Firestore diretamente.
final class HealthRestrictionEndController extends ChangeNotifier {
  HealthRestrictionEndController({
    required HealthDocumentGateway documentGateway,
    required HealthEvidenceUploader uploader,
    required HealthRestrictionLifecycleGateway lifecycleGateway,
    required HealthReadinessConvergenceGateway convergenceGateway,
    String Function()? operationIdFactory,
  }) : _documentGateway = documentGateway,
       _uploader = uploader,
       _lifecycleGateway = lifecycleGateway,
       _newOperationId = operationIdFactory ?? (() => const Uuid().v4()) {
    _convergence = HealthRestrictionConvergenceCoordinator(
      gateway: convergenceGateway,
      onChanged: notifyListeners,
    );
  }

  final HealthDocumentGateway _documentGateway;
  final HealthEvidenceUploader _uploader;
  final HealthRestrictionLifecycleGateway _lifecycleGateway;
  final String Function() _newOperationId;
  late final HealthRestrictionConvergenceCoordinator _convergence;

  /// Fase causal do encerramento já commitado (B4-R.C3).
  HealthRestrictionConvergenceCoordinator get convergence => _convergence;

  HealthRestrictionEndStage _stage = HealthRestrictionEndStage.idle;
  HealthRestrictionFlowFailure? _failure;
  bool _submitting = false;

  // Progresso documental (mesma disciplina do ISSUE).
  String? _documentOperationId;
  String? _documentIntentFingerprint;
  PreparedHealthDocumentUpload? _prepared;
  bool _uploadCompleted = false;
  HealthDocumentRef? _documentRef;

  // Progresso do comando terminal.
  String? _endOperationId;
  String? _endIntentFingerprint;
  HealthRestrictionTerminalResult? _result;

  HealthRestrictionEndStage get stage => _stage;
  HealthRestrictionFlowFailure? get failure => _failure;
  bool get isSubmitting => _submitting;
  HealthRestrictionTerminalResult? get result => _result;

  /// Documento canônico já criado — sobrevive a falha do END.
  HealthDocumentRef? get documentReference => _documentRef;

  @visibleForTesting
  String? get documentOperationIdForTest => _documentOperationId;

  @visibleForTesting
  String? get endOperationIdForTest => _endOperationId;

  @visibleForTesting
  String? get uploadPathForTest => _prepared?.uploadPath;

  /// Executa (ou retoma) o encerramento.
  Future<bool> submit({
    required HealthEvidenceIntent evidence,
    required HealthRestrictionEndIntent end,
  }) async {
    if (_submitting) return false;
    _submitting = true;
    _failure = null;
    notifyListeners();

    try {
      final reason = normalizeHealthRestrictionReason(end.endReason);
      if (reason == null) {
        return _fail(
          const HealthRestrictionFlowValidation(
            HealthRestrictionFlowStep.restrictionEnd,
            'Informe o motivo do encerramento.',
          ),
        );
      }

      _reconcileDocumentIntent(evidence);

      if (!await _ensureDocumentPrepared(end.dogId)) return false;
      if (!await _ensureUploaded(evidence)) return false;
      if (!await _ensureDocumentFinalized(end.dogId, evidence)) return false;

      // Reconciliado só agora: a chave terminal depende da evidência final.
      _reconcileEndIntent(end, _documentRef!);

      if (!await _ensureEnded(end, reason)) return false;

      // O encerramento já é fato canônico. Daqui em diante qualquer falha é de
      // CONVERGÊNCIA, nunca de encerramento: `_result` e o stage `success`
      // sobrevivem ao que acontecer na barreira causal.
      _stage = HealthRestrictionEndStage.success;
      await _convergence.onMutationCommitted(end.dogId);
      return true;
    } finally {
      _submitting = false;
      notifyListeners();
    }
  }

  /// Arquivo, natureza ou título mudaram: documento anterior, se já selado,
  /// permanece canônico e simplesmente não será citado. Nenhum cleanup
  /// client-side — isso é permitido pelo contrato.
  void _reconcileDocumentIntent(HealthEvidenceIntent evidence) {
    final fingerprint = evidence.fingerprint;
    if (_documentIntentFingerprint != null &&
        _documentIntentFingerprint != fingerprint) {
      _documentOperationId = null;
      _prepared = null;
      _uploadCompleted = false;
      _documentRef = null;
    }
    _documentIntentFingerprint = fingerprint;
    _documentOperationId ??= _newOperationId();
  }

  void _reconcileEndIntent(
    HealthRestrictionEndIntent end,
    HealthDocumentRef reference,
  ) {
    final fingerprint = end.fingerprintWith(reference);
    if (_endIntentFingerprint != null && _endIntentFingerprint != fingerprint) {
      _endOperationId = null;
      _result = null;
    }
    _endIntentFingerprint = fingerprint;
    _endOperationId ??= _newOperationId();
  }

  Future<bool> _ensureDocumentPrepared(String dogId) async {
    if (_prepared != null) return true;

    _setStage(HealthRestrictionEndStage.documentPreparing);
    final result = await _documentGateway.prepareUpload(
      PrepareHealthDocumentCommand(
        dogId: dogId,
        operationId: _documentOperationId!,
      ),
    );
    switch (result) {
      case PrepareHealthDocumentSuccess(:final prepared):
        _prepared = prepared;
        _setStage(HealthRestrictionEndStage.documentPrepared);
        return true;
      case PrepareHealthDocumentError(:final failure):
        return _fail(failure);
    }
  }

  Future<bool> _ensureUploaded(HealthEvidenceIntent evidence) async {
    if (_uploadCompleted) return true;

    _setStage(HealthRestrictionEndStage.documentUploading);
    try {
      // Único destino aceito: o staging devolvido pelo PREPARE.
      await _uploader.upload(
        file: evidence.file,
        uploadPath: _prepared!.uploadPath,
      );
      _uploadCompleted = true;
      _setStage(HealthRestrictionEndStage.documentUploaded);
      return true;
    } on HealthRestrictionFlowFailure catch (e) {
      return _fail(e);
    } catch (e) {
      debugPrint('[HealthRestrictionEnd] upload inesperado: $e');
      return _fail(
        const HealthRestrictionFlowUnexpected(
          HealthRestrictionFlowStep.documentUpload,
        ),
      );
    }
  }

  Future<bool> _ensureDocumentFinalized(
    String dogId,
    HealthEvidenceIntent evidence,
  ) async {
    if (_documentRef != null) return true;

    _setStage(HealthRestrictionEndStage.documentFinalizing);
    final result = await _documentGateway.finalizeUpload(
      FinalizeHealthDocumentCommand(
        dogId: dogId,
        operationId: _documentOperationId!,
        nature: evidence.nature,
        title: evidence.title,
      ),
    );
    switch (result) {
      case FinalizeHealthDocumentSuccess(:final document):
        _documentRef = document.reference;
        _setStage(HealthRestrictionEndStage.documentFinalized);
        return true;
      case FinalizeHealthDocumentError(:final failure):
        return _fail(failure);
    }
  }

  Future<bool> _ensureEnded(
    HealthRestrictionEndIntent end,
    String reason,
  ) async {
    _setStage(HealthRestrictionEndStage.ending);
    final outcome = await _lifecycleGateway.end(
      EndOperationalRestrictionCommand(
        dogId: end.dogId,
        restrictionId: end.restrictionId,
        operationId: _endOperationId!,
        endReason: reason,
        endProfessional: end.endProfessional,
        endSourceDocument: _documentRef!,
      ),
    );
    switch (outcome) {
      case HealthRestrictionTerminalSuccess(:final result):
        _result = result;
        return true;
      case HealthRestrictionTerminalError(:final failure):
        return _fail(failure);
    }
  }

  void _setStage(HealthRestrictionEndStage next) {
    _stage = next;
    notifyListeners();
  }

  bool _fail(HealthRestrictionFlowFailure failure) {
    _failure = failure;
    _stage = HealthRestrictionEndStage.failure;
    return false;
  }
}
