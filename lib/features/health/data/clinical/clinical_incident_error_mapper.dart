import 'package:cloud_functions/cloud_functions.dart';
import 'package:canil_gcm/features/health/domain/clinical_incident_errors.dart';

abstract final class ClinicalIncidentErrorMapper {
  ClinicalIncidentErrorMapper._();

  static ClinicalIncidentFailure map(Object error) {
    if (error is ClinicalIncidentFailure) return error;

    if (error is FirebaseFunctionsException) {
      final code = error.code.toLowerCase().trim();
      final detailsCode = _extractDetailsCode(error.details);
      final effectiveCode = detailsCode ?? code;

      final message = error.message?.trim().isNotEmpty == true
          ? error.message!.trim()
          : 'Erro na operação de intercorrência.';

      switch (effectiveCode) {
        case 'permission-denied':
        case 'permission_denied':
        case 'unauthenticated':
          return ClinicalIncidentPermissionDenied(
            message: message,
            cause: error,
          );
        case 'not-found':
        case 'not_found':
          return ClinicalIncidentNotFound(
            message: message,
            cause: error,
          );
        case 'failed-precondition':
        case 'failed_precondition':
        case 'already-exists':
        case 'already_exists':
        case 'idempotency-conflict':
        case 'conflict':
          return ClinicalIncidentConflict(
            message: message,
            cause: error,
          );
        case 'invalid-argument':
        case 'invalid_argument':
        case 'validation':
          return ClinicalIncidentValidation(
            message: message,
            cause: error,
          );
        case 'unavailable':
        case 'deadline-exceeded':
          return ClinicalIncidentOffline(
            message: message,
            cause: error,
          );
        default:
          return ClinicalIncidentUnexpected(
            message: message,
            cause: error,
          );
      }
    }

    final str = error.toString().toLowerCase();
    if (str.contains('network') ||
        str.contains('connection') ||
        str.contains('offline') ||
        str.contains('socket')) {
      return ClinicalIncidentOffline(
        message: 'Sem conexão com o servidor.',
        cause: error,
      );
    }

    return ClinicalIncidentUnexpected(
      message: 'Erro inesperado: $error',
      cause: error,
    );
  }

  static String? _extractDetailsCode(Object? details) {
    if (details is Map) {
      final code = details['code'];
      if (code is String && code.isNotEmpty) return code.toLowerCase().trim();
    }
    return null;
  }
}
