/// Contrato do gateway de HealthDocument canônico (consumidor do B0).
///
/// O Mobile NÃO conhece Storage sealing, generation nem fingerprint de selo: o
/// B0 encapsulou isso. Daqui o fluxo é apenas
/// PREPARE → upload no staging devolvido → FINALIZE → [HealthDocumentRef].
library;

import 'health_evidence_file.dart';
import 'health_restriction_flow_errors.dart';
import 'health_v1_value_objects.dart';

/// Comando de PREPARE. Não carrega metadata clínica — o B0 só deriva
/// identidade e path de staging nesta etapa.
final class PrepareHealthDocumentCommand {
  const PrepareHealthDocumentCommand({
    required this.dogId,
    required this.operationId,
  });

  final String dogId;
  final String operationId;
}

/// Resposta do PREPARE. `uploadPath` é o ÚNICO destino de upload aceito —
/// o cliente nunca constrói path.
final class PreparedHealthDocumentUpload {
  const PreparedHealthDocumentUpload({
    required this.dogId,
    required this.documentId,
    required this.uploadPath,
    required this.maxBytes,
  });

  final String dogId;
  final String documentId;
  final String uploadPath;
  final int maxBytes;
}

/// Comando de FINALIZE. Mínimo do contrato B0 para esta vertical.
///
/// `ProfessionalIdentity` NÃO é duplicada aqui: ela pertence à restrição, não
/// ao documento.
final class FinalizeHealthDocumentCommand {
  const FinalizeHealthDocumentCommand({
    required this.dogId,
    required this.operationId,
    required this.nature,
    required this.title,
  });

  final String dogId;
  final String operationId;
  final HealthEvidenceNature nature;
  final String title;
}

/// Resultado do FINALIZE: a referência citável do documento canônico.
final class FinalizedHealthDocument {
  const FinalizedHealthDocument({
    required this.dogId,
    required this.documentId,
    required this.reference,
    required this.wasNoOp,
  });

  final String dogId;
  final String documentId;

  /// Superfície oficial para o próximo comando (ISSUE).
  final HealthDocumentRef reference;

  /// `true` em replay idempotente — mesma referência, nenhuma escrita nova.
  final bool wasNoOp;
}

sealed class PrepareHealthDocumentResult {
  const PrepareHealthDocumentResult();
}

final class PrepareHealthDocumentSuccess extends PrepareHealthDocumentResult {
  const PrepareHealthDocumentSuccess(this.prepared);

  final PreparedHealthDocumentUpload prepared;
}

final class PrepareHealthDocumentError extends PrepareHealthDocumentResult {
  const PrepareHealthDocumentError(this.failure);

  final HealthRestrictionFlowFailure failure;
}

sealed class FinalizeHealthDocumentResult {
  const FinalizeHealthDocumentResult();
}

final class FinalizeHealthDocumentSuccess extends FinalizeHealthDocumentResult {
  const FinalizeHealthDocumentSuccess(this.document);

  final FinalizedHealthDocument document;
}

final class FinalizeHealthDocumentError extends FinalizeHealthDocumentResult {
  const FinalizeHealthDocumentError(this.failure);

  final HealthRestrictionFlowFailure failure;
}

abstract interface class HealthDocumentGateway {
  Future<PrepareHealthDocumentResult> prepareUpload(
    PrepareHealthDocumentCommand command,
  );

  Future<FinalizeHealthDocumentResult> finalizeUpload(
    FinalizeHealthDocumentCommand command,
  );
}

/// Upload do arquivo no staging path devolvido pelo PREPARE.
///
/// Separado do gateway de callables porque é Storage, não Functions — e porque
/// precisa ser fail-closed de forma independente.
abstract interface class HealthEvidenceUploader {
  /// Sobe [file] em [uploadPath] com MIME explícito.
  ///
  /// Deve LANÇAR [HealthRestrictionFlowFailure] em qualquer falha, incluindo o
  /// `null` que `StorageService.uploadBytes` devolve em `object-not-found`.
  /// Nunca devolve URL: download URL não é autoridade.
  Future<void> upload({
    required SelectedHealthEvidenceFile file,
    required String uploadPath,
  });
}
