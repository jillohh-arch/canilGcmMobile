import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';

import 'package:canil_gcm/features/health/domain/health_schedule_mutation_errors.dart';

/// Mapeia erros Firebase Functions → falhas tipadas de domínio.
///
/// Prioriza `details.code` estruturado (HttpsError.details no backend).
/// Não expõe [FirebaseFunctionsException] nem stack traces.
abstract final class HealthScheduleFunctionsErrorMapper {
  HealthScheduleFunctionsErrorMapper._();

  static HealthScheduleMutationFailure map(Object error) {
    if (error is HealthScheduleMutationFailure) {
      return error;
    }
    if (error is FirebaseFunctionsException) {
      return _fromFirebase(error);
    }
    debugPrint(
      '[HealthScheduleMutationGateway] erro não-Firebase: ${error.runtimeType}',
    );
    return const HealthScheduleMutationUnexpected();
  }

  static HealthScheduleMutationFailure _fromFirebase(
    FirebaseFunctionsException e,
  ) {
    final semantic = _semanticCode(e);
    final message = (e.message ?? '').trim();
    final safeMessage = message.isEmpty ? null : message;

    switch (semantic) {
      case 'unauthenticated':
        return HealthScheduleMutationUnauthenticated(
          safeMessage ?? 'Usuário não autenticado.',
        );
      case 'permission-denied':
        return HealthScheduleMutationPermissionDenied(
          safeMessage ?? 'Sem permissão para esta operação da agenda.',
        );
      case 'not-found':
        return HealthScheduleMutationNotFound(
          safeMessage ?? 'Item de agenda não encontrado.',
        );
      case 'conflict':
        return HealthScheduleMutationConflict(
          safeMessage ??
              'O item mudou desde a última leitura (conflito de concorrência).',
        );
      case 'idempotency-conflict':
        return HealthScheduleMutationIdempotencyConflict(
          safeMessage ?? 'Mesma operação com intenção diferente da original.',
        );
      case 'already-completed':
        return HealthScheduleMutationAlreadyCompleted(
          asSuccess: false,
          message: safeMessage ?? 'Item já está concluído.',
        );
      case 'already-cancelled':
        return HealthScheduleMutationAlreadyCancelled(
          asSuccess: false,
          message: safeMessage ?? 'Item já está cancelado.',
        );
      case 'invalid-transition':
        return HealthScheduleMutationInvalidTransition(
          safeMessage ?? 'Transição de lifecycle inválida.',
        );
      case 'validation':
      case 'invalid-argument':
        return HealthScheduleMutationValidation(
          safeMessage ?? 'Dados inválidos para a operação da agenda.',
        );
      case 'integrity':
        return HealthScheduleMutationIntegrity(
          safeMessage ?? 'Estado da agenda inconsistente.',
        );
      case 'unavailable':
      case 'deadline-exceeded':
      case 'network-request-failed':
        return HealthScheduleMutationOffline(
          safeMessage ?? 'Sem conexão para mutar a agenda.',
        );
      case 'unexpected':
      case 'internal':
      default:
        debugPrint(
          '[HealthScheduleMutationGateway] callable falhou '
          'code=${e.code} semantic=$semantic',
        );
        return HealthScheduleMutationUnexpected(
          safeMessage ?? 'Falha inesperada na mutação da agenda.',
        );
    }
  }

  /// Preferência: details.code → code Firebase normalizado.
  static String _semanticCode(FirebaseFunctionsException e) {
    final fromDetails = _codeFromDetails(e.details);
    if (fromDetails != null) return fromDetails;

    final code = e.code.trim().toLowerCase();
    // invalid-argument no transport → validation de domínio.
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
