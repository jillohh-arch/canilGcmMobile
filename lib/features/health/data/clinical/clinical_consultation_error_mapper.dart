import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';

import 'package:canil_gcm/features/health/domain/clinical_consultation_errors.dart';

/// Mapeia erros Firebase Functions → falhas tipadas de Consulta.
///
/// Prioriza `details.code` estruturado, que o backend emite em `appError`
/// (`mapClinicalError`). O código de transporte é apenas o segundo sinal:
/// `conflict`, `idempotency-conflict` e `integrity` compartilham
/// `failed-precondition`, então o transporte sozinho não distingue.
///
/// Denials de capability trazem também `reason` e `action`
/// (`clinicalCapabilityDenied`).
abstract final class ClinicalConsultationErrorMapper {
  ClinicalConsultationErrorMapper._();

  static ClinicalConsultationFailure map(Object error) {
    if (error is ClinicalConsultationFailure) return error;
    if (error is FirebaseFunctionsException) return _fromFirebase(error);
    if (error is FormatException) {
      debugPrint('[ClinicalConsultationGateway] resposta ilegível: $error');
      return const ClinicalConsultationUnexpected(
        message: 'Resposta inesperada do servidor clínico.',
      );
    }
    debugPrint(
      '[ClinicalConsultationGateway] erro não-Firebase: ${error.runtimeType}',
    );
    return const ClinicalConsultationUnexpected();
  }

  static ClinicalConsultationFailure _fromFirebase(
    FirebaseFunctionsException e,
  ) {
    final details = _details(e.details);
    final detailCode = _string(details, 'code');
    final reason = _string(details, 'reason');
    final action = _string(details, 'action');
    final transport = e.code.trim().toLowerCase();
    final semantic = (detailCode ?? transport).toLowerCase();
    final message = (e.message ?? '').trim();
    final safeMessage = message.isEmpty ? null : message;

    switch (semantic) {
      case 'permission-denied':
        // Capability clínica ausente vs escopo de K9 negado: são ações
        // diferentes para o usuário.
        if (reason == 'dog-scope-denied' ||
            reason == 'authorization-state-invalid') {
          return ClinicalConsultationDogAccessDenied(message: safeMessage);
        }
        return ClinicalConsultationNotAuthorized(
          message: safeMessage,
          action: action,
        );

      case 'unauthenticated':
        return ClinicalConsultationUnauthenticated(message: safeMessage);

      case 'idempotency-conflict':
        return ClinicalConsultationIdempotencyConflict(message: safeMessage);

      case 'not-found':
        return ClinicalConsultationCaseNotFound(message: safeMessage);

      case 'validation':
      case 'invalid-argument':
        return ClinicalConsultationValidationFailure(
          message: safeMessage,
          reason: reason ?? detailCode,
        );

      case 'conflict':
      case 'integrity':
      case 'failed-precondition':
        return ClinicalConsultationCaseNotWritable(
          message: safeMessage,
          reason: reason ?? detailCode,
        );

      case 'unavailable':
      case 'not-found-function':
        return ClinicalConsultationUnavailable(message: safeMessage);

      default:
        // `internal` inclui o caso de callable não publicado no ambiente.
        debugPrint(
          '[ClinicalConsultationGateway] código não classificado: '
          '$semantic (transport=$transport)',
        );
        return ClinicalConsultationUnexpected(message: safeMessage);
    }
  }

  static Map<String, dynamic>? _details(Object? raw) {
    if (raw is Map) return Map<String, dynamic>.from(raw);
    return null;
  }

  static String? _string(Map<String, dynamic>? details, String key) {
    final value = details?[key];
    if (value is String && value.trim().isNotEmpty) return value.trim();
    return null;
  }
}
