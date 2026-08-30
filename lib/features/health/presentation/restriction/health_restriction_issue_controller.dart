import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../../data/coexistence/summary/health_readiness_convergence_gateway.dart';
import '../../domain/health_document_gateway.dart';
import '../../domain/health_evidence_file.dart';
import '../../domain/health_restriction_flow_errors.dart';
import '../../domain/health_restriction_issue_gateway.dart';
import '../../domain/health_v1_enums_ext.dart';
import '../../domain/health_v1_value_objects.dart';
import 'health_restriction_convergence_coordinator.dart';

/// Progresso do fluxo de emissão.
///
/// Existe para que "Tentar novamente" retome de onde parou, em vez de refazer
/// upload e recriar documento. Cada etapa concluída é um fato durável no
/// backend (staging escrito, documento selado, restrição emitida) — repetir
/// cegamente geraria staging redundante e documentos órfãos desnecessários.
enum HealthRestrictionIssueStage {
  idle,
  documentPreparing,
  documentPrepared,
  documentUploading,
  documentUploaded,
  documentFinalizing,
  documentFinalized,
  restrictionIssuing,
  success,
  failure,
}

/// Intenção da restrição, materializada para fingerprint.
final class HealthRestrictionIntent {
  const HealthRestrictionIntent({
    required this.dogId,
    required this.level,
    required this.category,
    required this.description,
    required this.professional,
    required this.activitiesRestricted,
    this.expectedEnd,
  });

  final String dogId;
  final RestrictionLevel level;
  final RestrictionCategory category;
  final String description;
  final ProfessionalIdentity professional;
  final List<String> activitiesRestricted;
  final DateTime? expectedEnd;

  /// Chave determinística da intenção. Não precisa ser criptográfica: serve
  /// só para detectar que o operador mudou algo material entre tentativas.
  String get fingerprint {
    // `partial` é o único nível em que atividades são materiais; nos outros a
    // lista não vai no payload, então não pode influenciar a chave.
    final activities = level == RestrictionLevel.partial
        ? activitiesRestricted.join('')
        : '';
    return [
      dogId,
      level.wireName,
      category.wireName,
      description.trim(),
      activities,
      expectedEnd?.toUtc().toIso8601String() ?? '',
      professional.name,
      professional.registrationType.wireName,
      professional.registrationNumber,
      professional.clinic,
      professional.specialty?.trim() ?? '',
    ].join('');
  }
}

/// Intenção documental, materializada para fingerprint.
final class HealthEvidenceIntent {
  const HealthEvidenceIntent({
    required this.file,
    required this.nature,
    required this.title,
  });

  final SelectedHealthEvidenceFile file;
  final HealthEvidenceNature nature;
  final String title;

  String get fingerprint =>
      [file.localIdentity, nature.wireName, title.trim()].join('');
}

/// Orquestra PREPARE → upload → FINALIZE → ISSUE preservando progresso.
final class HealthRestrictionIssueController extends ChangeNotifier {
  HealthRestrictionIssueController({
    required HealthDocumentGateway documentGateway,
    required HealthEvidenceUploader uploader,
    required HealthRestrictionIssueGateway restrictionGateway,
    required HealthReadinessConvergenceGateway convergenceGateway,
    String Function()? operationIdFactory,
  }) : _documentGateway = documentGateway,
       _uploader = uploader,
       _restrictionGateway = restrictionGateway,
       _newOperationId = operationIdFactory ?? (() => const Uuid().v4()) {
    _convergence = HealthRestrictionConvergenceCoordinator(
      gateway: convergenceGateway,
      onChanged: notifyListeners,
    );
  }

  final HealthDocumentGateway _documentGateway;
  final HealthEvidenceUploader _uploader;
  final HealthRestrictionIssueGateway _restrictionGateway;
  final String Function() _newOperationId;
  late final HealthRestrictionConvergenceCoordinator _convergence;

  /// Fase causal da restrição já emitida (B4-R.C3).
  HealthRestrictionConvergenceCoordinator get convergence => _convergence;

  HealthRestrictionIssueStage _stage = HealthRestrictionIssueStage.idle;
  HealthRestrictionFlowFailure? _failure;
  bool _submitting = false;

  // Progresso documental.
  String? _documentOperationId;
  String? _documentIntentFingerprint;
  PreparedHealthDocumentUpload? _prepared;
  bool _uploadCompleted = false;
  HealthDocumentRef? _documentRef;

  // Progresso da restrição.
  String? _restrictionOperationId;
  String? _restrictionIntentFingerprint;
  String? _restrictionId;

  HealthRestrictionIssueStage get stage => _stage;
  HealthRestrictionFlowFailure? get failure => _failure;
  bool get isSubmitting => _submitting;
  String? get restrictionId => _restrictionId;

  /// Documento canônico já criado — sobrevive a falha do ISSUE.
  HealthDocumentRef? get documentReference => _documentRef;

  @visibleForTesting
  String? get documentOperationIdForTest => _documentOperationId;

  @visibleForTesting
  String? get restrictionOperationIdForTest => _restrictionOperationId;

  @visibleForTesting
  String? get uploadPathForTest => _prepared?.uploadPath;

  /// Executa (ou retoma) o fluxo.
  ///
  /// Idempotente por etapa: o que já concluiu não é refeito. Se a intenção
  /// mudou desde a tentativa anterior, o progresso afetado é invalidado e uma
  /// nova chave de operação é gerada — reusar a chave com payload diferente
  /// produziria `idempotency-conflict` no backend, corretamente.
  Future<bool> submit({
    required HealthEvidenceIntent evidence,
    required HealthRestrictionIntent restriction,
  }) async {
    if (_submitting) return false;
    _submitting = true;
    _failure = null;
    notifyListeners();

    try {
      _reconcileIntents(evidence: evidence, restriction: restriction);

      final dogId = restriction.dogId;
      if (!await _ensureDocumentPrepared(dogId)) return false;
      if (!await _ensureUploaded(evidence)) return false;
      if (!await _ensureDocumentFinalized(dogId, evidence)) return false;
      if (!await _ensureRestrictionIssued(restriction)) return false;

      // A restrição já é fato canônico. Daqui em diante qualquer falha é de
      // CONVERGÊNCIA, nunca de emissão: `_restrictionId` e o stage `success`
      // sobrevivem ao que acontecer na barreira causal.
      _stage = HealthRestrictionIssueStage.success;
      await _convergence.onMutationCommitted(dogId);
      return true;
    } finally {
      _submitting = false;
      notifyListeners();
    }
  }

  /// Invalida progresso quando a intenção material muda.
  void _reconcileIntents({
    required HealthEvidenceIntent evidence,
    required HealthRestrictionIntent restriction,
  }) {
    final evidenceFp = evidence.fingerprint;
    if (_documentIntentFingerprint != null &&
        _documentIntentFingerprint != evidenceFp) {
      // Arquivo/natureza/título mudaram: o documento anterior, se já foi
      // selado, permanece canônico e simplesmente não será citado. Isso é
      // permitido pelo contrato — nenhum cleanup client-side.
      _documentOperationId = null;
      _prepared = null;
      _uploadCompleted = false;
      _documentRef = null;
    }
    _documentIntentFingerprint = evidenceFp;
    _documentOperationId ??= _newOperationId();

    final restrictionFp = restriction.fingerprint;
    if (_restrictionIntentFingerprint != null &&
        _restrictionIntentFingerprint != restrictionFp) {
      // Só a restrição mudou: o documento já finalizado é preservado.
      _restrictionOperationId = null;
      _restrictionId = null;
    }
    _restrictionIntentFingerprint = restrictionFp;
    _restrictionOperationId ??= _newOperationId();
  }

  Future<bool> _ensureDocumentPrepared(String dogId) async {
    if (_prepared != null) return true;

    _setStage(HealthRestrictionIssueStage.documentPreparing);
    final result = await _documentGateway.prepareUpload(
      PrepareHealthDocumentCommand(
        dogId: dogId,
        operationId: _documentOperationId!,
      ),
    );
    switch (result) {
      case PrepareHealthDocumentSuccess(:final prepared):
        _prepared = prepared;
        _setStage(HealthRestrictionIssueStage.documentPrepared);
        return true;
      case PrepareHealthDocumentError(:final failure):
        return _fail(failure);
    }
  }

  Future<bool> _ensureUploaded(HealthEvidenceIntent evidence) async {
    if (_uploadCompleted) return true;

    _setStage(HealthRestrictionIssueStage.documentUploading);
    try {
      // Único destino aceito: o staging devolvido pelo PREPARE.
      await _uploader.upload(
        file: evidence.file,
        uploadPath: _prepared!.uploadPath,
      );
      _uploadCompleted = true;
      _setStage(HealthRestrictionIssueStage.documentUploaded);
      return true;
    } on HealthRestrictionFlowFailure catch (e) {
      return _fail(e);
    } catch (e) {
      debugPrint('[HealthRestrictionIssue] upload inesperado: $e');
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

    _setStage(HealthRestrictionIssueStage.documentFinalizing);
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
        _setStage(HealthRestrictionIssueStage.documentFinalized);
        return true;
      case FinalizeHealthDocumentError(:final failure):
        return _fail(failure);
    }
  }

  Future<bool> _ensureRestrictionIssued(
    HealthRestrictionIntent restriction,
  ) async {
    _setStage(HealthRestrictionIssueStage.restrictionIssuing);
    final result = await _restrictionGateway.issue(
      IssueOperationalRestrictionCommand(
        dogId: restriction.dogId,
        operationId: _restrictionOperationId!,
        level: restriction.level,
        category: restriction.category,
        description: restriction.description,
        activitiesRestricted: restriction.level == RestrictionLevel.partial
            ? restriction.activitiesRestricted
            : const <String>[],
        expectedEnd: restriction.expectedEnd,
        professional: restriction.professional,
        sourceDocument: _documentRef!,
      ),
    );
    switch (result) {
      case IssueOperationalRestrictionSuccess(:final restriction):
        _restrictionId = restriction.restrictionId;
        return true;
      case IssueOperationalRestrictionError(:final failure):
        return _fail(failure);
    }
  }

  void _setStage(HealthRestrictionIssueStage next) {
    _stage = next;
    notifyListeners();
  }

  bool _fail(HealthRestrictionFlowFailure failure) {
    _failure = failure;
    _stage = HealthRestrictionIssueStage.failure;
    return false;
  }
}
