import 'package:cloud_firestore/cloud_firestore.dart';

import 'package:canil_gcm/features/health/data/coexistence/nutrition/coexistence_nutrition_read_source.dart';
import 'package:canil_gcm/features/health/domain/nutrition_read_state.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Mapeamento Firebase → NutritionSourceBatch (erro ≠ empty; offline ≠ empty).
// ─────────────────────────────────────────────────────────────────────────────

/// Helper compartilhado pelos readers Firestore de Nutrição.
abstract final class NutritionFirestoreError {
  NutritionFirestoreError._();

  static bool looksLikeOffline(FirebaseException e) {
    final code = e.code.toLowerCase();
    if (code == 'unavailable' || code == 'network-request-failed') {
      return true;
    }
    final lower = (e.message ?? e.toString()).toLowerCase();
    return lower.contains('unavailable') ||
        lower.contains('network') ||
        lower.contains('offline') ||
        lower.contains('socket');
  }

  static NutritionSourceBatch<T> batchFromFirebaseException<T>(
    FirebaseException e, {
    required String sourceKey,
  }) {
    if (looksLikeOffline(e)) {
      return NutritionSourceBatch.offline(
        code: e.code,
        message: 'Fonte $sourceKey offline',
      );
    }
    return NutritionSourceBatch.error(
      code: e.code,
      message: e.message ?? 'Falha ao ler $sourceKey',
    );
  }

  static NutritionSourceBatch<T> batchFromUnknown<T>(
    Object error, {
    required String sourceKey,
  }) {
    if (error is FirebaseException) {
      return batchFromFirebaseException(error, sourceKey: sourceKey);
    }
    return NutritionSourceBatch.error(
      code: 'nutrition_read_exception',
      message: error.toString(),
    );
  }

  static NutritionSourceAvailability availabilityFromFirebase(
    FirebaseException e,
  ) {
    return looksLikeOffline(e)
        ? NutritionSourceAvailability.offline
        : NutritionSourceAvailability.error;
  }

  /// Materializa map Firestore → `Map<String, Object?>` (Timestamp intacto).
  static Map<String, Object?> asObjectMap(Map<String, dynamic> data) {
    return data.map((key, value) => MapEntry(key, value as Object?));
  }

  /// Materializa payload legado para o domínio puro, removendo tipos do SDK.
  ///
  /// Adapters legados podem preservar o payload original em value objects
  /// imutáveis. Por isso não basta o parser de data aceitar [Timestamp]: todo
  /// Timestamp, inclusive em campos auxiliares/nested, precisa virar DateTime.
  static Map<String, Object?> asLegacyDomainMap(Map<String, dynamic> data) {
    return data.map((key, value) => MapEntry(key, _toDomainValue(value)));
  }

  static Object? _toDomainValue(Object? value) {
    if (value is Timestamp) return value.toDate().toUtc();
    if (value is Map) {
      return value.map(
        (key, nested) => MapEntry(key.toString(), _toDomainValue(nested)),
      );
    }
    if (value is Iterable) {
      return value.map(_toDomainValue).toList(growable: false);
    }
    return value;
  }
}
