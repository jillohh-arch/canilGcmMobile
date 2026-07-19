import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';

import 'package:canil_gcm/features/health/domain/health_nutrition_mutation_errors.dart';

/// Mapeia erros Firebase Functions → falhas tipadas de Nutrição.
///
/// Prioriza `details.code` estruturado (HttpsError.details no backend).
/// Distingue `idempotency_conflict` de `meal_occurrence_conflict`.
abstract final class HealthNutritionFunctionsErrorMapper {
  HealthNutritionFunctionsErrorMapper._();

  static HealthNutritionMutationFailure map(Object error) {
    if (error is HealthNutritionMutationFailure) {
      return error;
    }
    if (error is FirebaseFunctionsException) {
      return _fromFirebase(error);
    }
    debugPrint(
      '[HealthNutritionMutationGateway] erro não-Firebase: ${error.runtimeType}',
    );
    return const HealthNutritionMutationUnexpected();
  }

  static HealthNutritionMutationFailure _fromFirebase(
    FirebaseFunctionsException e,
  ) {
    final detailCode = _codeFromDetails(e.details);
    final transport = e.code.trim().toLowerCase();
    final semantic = (detailCode ?? transport).toLowerCase();
    final message = (e.message ?? '').trim();
    final safeMessage = message.isEmpty ? null : message;

    // Semantic detail codes first (mesmo sob failed-precondition).
    switch (semantic) {
      case 'idempotency_conflict':
      case 'idempotency-conflict':
        return HealthNutritionMutationIdempotencyConflict(
          safeMessage ??
              'Mesma operação com intenção diferente da original.',
          'idempotency_conflict',
        );
      case 'meal_occurrence_conflict':
        return HealthNutritionMutationMealOccurrenceConflict(
          safeMessage ??
              'Conflito na mesma refeição planejada (materialização divergente).',
          'meal_occurrence_conflict',
        );
      case 'unauthenticated':
        return HealthNutritionMutationUnauthenticated(
          safeMessage ?? 'Usuário não autenticado.',
          detailCode,
        );
      case 'permission-denied':
      case 'permission_denied':
        return HealthNutritionMutationPermissionDenied(
          safeMessage ?? 'Sem permissão para registrar nutrição.',
          detailCode,
        );
      case 'not-found':
      case 'not_found':
      case 'nutrition_plan_not_found':
      case 'planned_meal_not_found':
      case 'supplement_regimen_not_found':
        return HealthNutritionMutationNotFound(
          safeMessage ?? 'Recurso de nutrição não encontrado.',
          detailCode ?? semantic,
        );
      case 'validation':
      case 'invalid-argument':
      case 'invalid_argument':
      case 'supplement_regimen_requires_plan':
        return HealthNutritionMutationValidation(
          safeMessage ?? 'Dados inválidos para a operação de nutrição.',
          detailCode: detailCode ?? semantic,
        );
      case 'integrity':
      case 'receipt_integrity':
      case 'nutrition_plan_integrity':
        return HealthNutritionMutationIntegrity(
          safeMessage ?? 'Estado de nutrição inconsistente.',
          detailCode ?? semantic,
        );
      case 'conflict':
        return HealthNutritionMutationConflict(
          safeMessage ?? 'Conflito na mutação de nutrição.',
          detailCode,
        );
      case 'nutrition_plan_cancelled':
      case 'nutrition_plan_not_effective_at_fed_at':
      case 'failed-precondition':
      case 'failed_precondition':
        return HealthNutritionMutationFailedPrecondition(
          safeMessage ?? 'Pré-condição de nutrição não satisfeita.',
          detailCode: detailCode ?? semantic,
        );
      case 'unavailable':
      case 'deadline-exceeded':
      case 'deadline_exceeded':
        return HealthNutritionMutationUnavailable(
          safeMessage ?? 'Serviço de nutrição temporariamente indisponível.',
          detailCode ?? transport,
        );
      case 'network-request-failed':
      case 'network_request_failed':
        return HealthNutritionMutationNetwork(
          safeMessage ?? 'Sem conexão para mutar nutrição.',
          detailCode ?? transport,
        );
      case 'internal':
      case 'unexpected':
      default:
        // Transport-only fallback for common codes without details.
        if (transport == 'unauthenticated') {
          return HealthNutritionMutationUnauthenticated(
            safeMessage ?? 'Usuário não autenticado.',
            detailCode,
          );
        }
        if (transport == 'permission-denied') {
          return HealthNutritionMutationPermissionDenied(
            safeMessage ?? 'Sem permissão para registrar nutrição.',
            detailCode,
          );
        }
        if (transport == 'invalid-argument') {
          return HealthNutritionMutationValidation(
            safeMessage ?? 'Dados inválidos para a operação de nutrição.',
            detailCode: detailCode,
          );
        }
        if (transport == 'not-found') {
          return HealthNutritionMutationNotFound(
            safeMessage ?? 'Recurso de nutrição não encontrado.',
            detailCode,
          );
        }
        if (transport == 'unavailable' || transport == 'deadline-exceeded') {
          return HealthNutritionMutationUnavailable(
            safeMessage ?? 'Serviço de nutrição temporariamente indisponível.',
            transport,
          );
        }
        if (transport == 'failed-precondition') {
          return HealthNutritionMutationFailedPrecondition(
            safeMessage ?? 'Pré-condição de nutrição não satisfeita.',
            detailCode: detailCode,
          );
        }
        debugPrint(
          '[HealthNutritionMutationGateway] callable falhou '
          'code=${e.code} detail=$detailCode',
        );
        return HealthNutritionMutationUnexpected(
          safeMessage ?? 'Falha inesperada na mutação de nutrição.',
          detailCode,
        );
    }
  }

  static String? _codeFromDetails(Object? details) {
    if (details is Map) {
      final raw = details['code'] ?? details['appCode'] ?? details['errorCode'];
      if (raw is String && raw.trim().isNotEmpty) {
        return raw.trim();
      }
    }
    return null;
  }
}
