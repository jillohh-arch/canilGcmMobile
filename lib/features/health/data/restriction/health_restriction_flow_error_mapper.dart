import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';

import '../../domain/health_restriction_flow_errors.dart';

/// Mapeia erro de transporte para falha de domínio, preservando a ETAPA.
///
/// Preferência de código semântico: `details.code` (que os callables Health
/// sempre preenchem via `appError`) antes do `code` de transporte — o mesmo
/// contrato usado pela Agenda Preventiva.
abstract final class HealthRestrictionFlowErrorMapper {
  HealthRestrictionFlowErrorMapper._();

  static HealthRestrictionFlowFailure map(
    Object error,
    HealthRestrictionFlowStep step,
  ) {
    if (error is HealthRestrictionFlowFailure) return error;
    if (error is FirebaseFunctionsException) return _fromFirebase(error, step);
    debugPrint(
      '[HealthRestrictionFlow] erro não-Firebase em $step: ${error.runtimeType}',
    );
    return HealthRestrictionFlowUnexpected(step);
  }

  static HealthRestrictionFlowFailure _fromFirebase(
    FirebaseFunctionsException e,
    HealthRestrictionFlowStep step,
  ) {
    final semantic = _semanticCode(e);
    final raw = (e.message ?? '').trim();

    switch (semantic) {
      case 'unauthenticated':
        return HealthRestrictionFlowUnauthenticated(step);
      case 'permission-denied':
        return HealthRestrictionFlowPermissionDenied(
          step,
          _permissionMessage(step),
        );
      case 'not-found':
        return HealthRestrictionFlowNotFound(step);
      case 'conflict':
        return HealthRestrictionFlowConflict(step);
      case 'idempotency-conflict':
        return HealthRestrictionFlowIdempotencyConflict(step);
      case 'validation':
      case 'invalid-argument':
        // Mensagem do backend é útil aqui: aponta o campo recusado.
        return HealthRestrictionFlowValidation(
          step,
          raw.isEmpty ? 'Dados inválidos. Revise os campos.' : raw,
        );
      case 'integrity':
        return HealthRestrictionFlowIntegrity(step);
      case 'unavailable':
      case 'deadline-exceeded':
      case 'network-request-failed':
        return HealthRestrictionFlowOffline(step);
      case 'internal':
      case 'unexpected':
      default:
        debugPrint(
          '[HealthRestrictionFlow] callable falhou em $step '
          'code=${e.code} semantic=$semantic',
        );
        return HealthRestrictionFlowUnexpected(step);
    }
  }

  /// Autoridade negada por etapa.
  ///
  /// O backend exige três capabilities distintas — `health.issue_restriction`,
  /// `health.release_restriction` e `health.cancel_restriction` — então dizer
  /// "registrar" numa negação de encerramento seria informação errada. Nenhuma
  /// delas é nomeada ao operador: capability é vocabulário interno.
  ///
  /// A mensagem de ISSUE é preservada literalmente (contrato do B3).
  static String _permissionMessage(HealthRestrictionFlowStep step) {
    return switch (step) {
      HealthRestrictionFlowStep.restrictionEnd =>
        'Você não possui autorização para encerrar uma restrição operacional.',
      HealthRestrictionFlowStep.restrictionCancel =>
        'Você não possui autorização para cancelar o registro desta '
            'restrição operacional.',
      HealthRestrictionFlowStep.documentPrepare ||
      HealthRestrictionFlowStep.documentUpload ||
      HealthRestrictionFlowStep.documentFinalize ||
      HealthRestrictionFlowStep.restrictionIssue =>
        'Você não possui autorização para registrar uma restrição operacional.',
    };
  }

  static String _semanticCode(FirebaseFunctionsException e) {
    final fromDetails = _codeFromDetails(e.details);
    if (fromDetails != null) return fromDetails;
    final code = e.code.trim().toLowerCase();
    if (code == 'invalid-argument') return 'validation';
    return code;
  }

  static String? _codeFromDetails(Object? details) {
    if (details is Map) {
      final raw = details['code'] ?? details['appCode'] ?? details['errorCode'];
      if (raw is String && raw.trim().isNotEmpty) {
        return raw.trim().toLowerCase();
      }
    }
    return null;
  }
}
