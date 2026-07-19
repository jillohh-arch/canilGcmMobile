import 'package:cloud_firestore/cloud_firestore.dart';

import 'package:canil_gcm/features/health/data/coexistence/nutrition/coexistence_nutrition_read_source.dart';
import 'package:canil_gcm/features/health/data/coexistence/nutrition/firestore_nutrition_canonical_readers.dart';
import 'package:canil_gcm/features/health/data/coexistence/nutrition/firestore_nutrition_legacy_readers.dart';
import 'package:canil_gcm/features/health/data/coexistence/nutrition/nutrition_merge_policy.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Composition factory — default de produção = Firestore real (Gate 4).
// Não usa Empty/fake como default silencioso.
// ─────────────────────────────────────────────────────────────────────────────

/// Monta [CoexistenceNutritionReadSource] com delegates Firestore reais.
abstract final class CoexistenceNutritionReadSourceFactory {
  CoexistenceNutritionReadSourceFactory._();

  /// Default Health v1: dual-read canônico + legado, zero write.
  ///
  /// **Local preparado ≠ produção ativada**: Rules de leitura canônica
  /// precisam de deploy (Gate 5). Até lá, leituras canônicas autenticadas
  /// em produção podem falhar com permission-denied.
  static CoexistenceNutritionReadSource forFirestore({
    FirebaseFirestore? firestore,
  }) {
    return CoexistenceNutritionReadSource(
      canonicalPlanReader: FirestoreNutritionCanonicalPlanReader(
        firestore: firestore,
      ),
      legacyPlanReader: FirestoreNutritionLegacyPlanReader(
        firestore: firestore,
      ),
      canonicalMealReader: FirestoreNutritionCanonicalMealReader(
        firestore: firestore,
      ),
      legacyMealReaders: [
        FirestoreNutritionLegacyMealReader(
          collectionKey: NutritionMergePolicy.feedingEvents,
          firestore: firestore,
        ),
        FirestoreNutritionLegacyMealReader(
          collectionKey: NutritionMergePolicy.feedings,
          firestore: firestore,
        ),
      ],
      canonicalSupplementLogReader:
          FirestoreNutritionCanonicalSupplementLogReader(firestore: firestore),
      legacySupplementRegimenReader:
          FirestoreNutritionLegacySupplementRegimenReader(firestore: firestore),
    );
  }
}
