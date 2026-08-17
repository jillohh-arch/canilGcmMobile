/// Contrato dos comandos terminais de OperationalRestriction (consumidor do B2).
///
/// Dois comandos, deliberadamente separados — não existe `changeStatus`:
///
/// * END    — liberação clínica documentada. Exige razão, profissional externo
///            e evidência canônica citável.
/// * CANCEL — invalidação administrativa do registro. NÃO afirma liberação
///            clínica e, por contrato do backend, rejeita profissional e
///            documento como erro, não como campo opcional.
///
/// Este contrato NÃO depende do agregado `OperationalRestriction`: age sobre
/// `dogId` + `restrictionId`, que é o que o backend exige. O read path (como a
/// UI descobre o `restrictionId`) é escopo do B4-B2.
library;

import 'health_restriction_flow_errors.dart';
import 'health_v1_value_objects.dart';

/// Estado terminal alcançado, conforme reportado pelo backend.
///
/// O cliente nunca infere o destino: o `status` vem no payload de resposta.
enum HealthRestrictionTerminalStatus {
  ended,
  cancelled;

  String get wireName => switch (this) {
    HealthRestrictionTerminalStatus.ended => 'ended',
    HealthRestrictionTerminalStatus.cancelled => 'cancelled',
  };

  /// Parse estrito. `null` para qualquer valor fora do vocabulário canônico —
  /// incluindo `active`, que não é estado terminal.
  static HealthRestrictionTerminalStatus? fromWire(String? wire) =>
      switch (wire) {
        'ended' => HealthRestrictionTerminalStatus.ended,
        'cancelled' => HealthRestrictionTerminalStatus.cancelled,
        _ => null,
      };
}

/// Comando de encerramento (liberação clínica documentada).
final class EndOperationalRestrictionCommand {
  const EndOperationalRestrictionCommand({
    required this.dogId,
    required this.restrictionId,
    required this.operationId,
    required this.endReason,
    required this.endProfessional,
    required this.endSourceDocument,
  });

  final String dogId;
  final String restrictionId;
  final String operationId;
  final String endReason;

  /// Profissional EXTERNO que decidiu a liberação — distinto do operador que
  /// registra, resolvido server-side.
  final ProfessionalIdentity endProfessional;

  /// Evidência canônica da liberação, citada por identidade.
  final HealthDocumentRef endSourceDocument;
}

/// Comando de cancelamento (invalidação administrativa).
///
/// Sem profissional e sem documento por construção: o tipo não os possui, então
/// não há como enviá-los por engano.
final class CancelOperationalRestrictionCommand {
  const CancelOperationalRestrictionCommand({
    required this.dogId,
    required this.restrictionId,
    required this.operationId,
    required this.cancelReason,
  });

  final String dogId;
  final String restrictionId;
  final String operationId;
  final String cancelReason;
}

/// Resultado de uma transição terminal.
///
/// Deliberadamente mínimo: não carrega profissional, path de Storage, URL nem
/// internals de auditoria.
final class HealthRestrictionTerminalResult {
  const HealthRestrictionTerminalResult({
    required this.dogId,
    required this.restrictionId,
    required this.status,
    required this.wasNoOp,
  });

  final String dogId;
  final String restrictionId;
  final HealthRestrictionTerminalStatus status;

  /// `true` em replay idempotente — mesma transição, nenhuma escrita nova.
  final bool wasNoOp;
}

sealed class HealthRestrictionTerminalOutcome {
  const HealthRestrictionTerminalOutcome();
}

final class HealthRestrictionTerminalSuccess
    extends HealthRestrictionTerminalOutcome {
  const HealthRestrictionTerminalSuccess(this.result);

  final HealthRestrictionTerminalResult result;
}

final class HealthRestrictionTerminalError
    extends HealthRestrictionTerminalOutcome {
  const HealthRestrictionTerminalError(this.failure);

  final HealthRestrictionFlowFailure failure;
}

/// Transporte compartilhado, comandos de domínio distintos.
abstract interface class HealthRestrictionLifecycleGateway {
  Future<HealthRestrictionTerminalOutcome> end(
    EndOperationalRestrictionCommand command,
  );

  Future<HealthRestrictionTerminalOutcome> cancel(
    CancelOperationalRestrictionCommand command,
  );
}

/// Razão material de uma transição terminal, normalizada.
///
/// Existe para que controller e gateway compartilhem a mesma noção de "razão
/// vazia é inválida" sem duplicar `trim()` em cada camada.
String? normalizeHealthRestrictionReason(String raw) {
  final trimmed = raw.trim();
  return trimmed.isEmpty ? null : trimmed;
}

/// Rótulo operacional do estado terminal, para uso futuro da UI (B4-C).
///
/// O vocabulário estabelecido no código é `encerrar`/`encerramento` para
/// `ended`; "liberação" aparece apenas em comentário de backend e fixture.
String healthRestrictionTerminalLabel(HealthRestrictionTerminalStatus status) {
  return switch (status) {
    HealthRestrictionTerminalStatus.ended => 'Encerrada',
    HealthRestrictionTerminalStatus.cancelled => 'Registro cancelado',
  };
}
