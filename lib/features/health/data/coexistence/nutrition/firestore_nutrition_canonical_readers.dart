import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import 'package:canil_gcm/features/health/data/coexistence/nutrition/coexistence_nutrition_read_source.dart';
import 'package:canil_gcm/features/health/data/coexistence/nutrition/nutrition_firestore_error.dart';
import 'package:canil_gcm/features/health/domain/health_v1_models.dart';
import 'package:canil_gcm/features/health/domain/nutrition_document_parser.dart';
import 'package:canil_gcm/features/health/domain/nutrition_plan.dart';
import 'package:canil_gcm/features/health/domain/supplement_log.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Adapters Firestore canônicos (5D Gate 4) — ZERO write.
// Reutilizam parsers 5C. Fail-closed: malformado ≠ empty / ≠ plan “ausente”.
// Active plan: NÃO usa where status==active limit(1) — integridade D3 no merge.
//
// G4-QUERY-INTEGRITY (MAJOR → CORRIGIDO):
// orderBy/where em campos obrigatórios (fed_at, administered_at) ocultaria
// documentos sem o campo *antes* do parser. Estratégia transitória:
// collection.get() → parse de TODOS → sort/range em memória.
// Paginação futura NÃO pode reintroduzir invisibilidade pré-parser.
// ─────────────────────────────────────────────────────────────────────────────

/// Caminhos canônicos congelados (Gate 4 / schema Health v1).
abstract final class NutritionCanonicalPaths {
  NutritionCanonicalPaths._();

  static const plans = 'nutrition_plans';
  static const mealLogs = 'meal_logs';
  static const supplementLogs = 'supplement_logs';
  // Backend-only — nunca lido pelo cliente.
  static const operations = 'nutrition_operations';
}

/// `dogs/{dogId}/nutrition_plans` — leitura completa da collection (sem limit 1).
///
/// Query final (Gate 4 integrity):
/// - collection: nutrition_plans (sub de dog)
/// - server filters: nenhum
/// - server orderBy: nenhum
/// - client order: nenhum (active resolvido no merge D3)
/// - limit / pagination: nenhum
/// - índice: nenhum
final class FirestoreNutritionCanonicalPlanReader
    implements NutritionCanonicalPlanReader {
  FirestoreNutritionCanonicalPlanReader({FirebaseFirestore? firestore})
    : _firestore = firestore;

  final FirebaseFirestore? _firestore;

  FirebaseFirestore get _db => _firestore ?? FirebaseFirestore.instance;

  @override
  Future<NutritionSourceBatch<NutritionPlan>> loadPlans(String dogId) async {
    final id = dogId.trim();
    if (id.isEmpty) {
      return const NutritionSourceBatch.error(
        code: 'missing_dog_id',
        message: 'dogId é obrigatório',
      );
    }

    try {
      // Full collection scan: todo documento alcança o parser (fail-closed).
      final snap = await _db
          .collection('dogs')
          .doc(id)
          .collection(NutritionCanonicalPaths.plans)
          .get();

      if (snap.docs.isEmpty) {
        return const NutritionSourceBatch.empty(
          message: 'Sem nutrition_plans canônicos',
        );
      }

      final plans = <NutritionPlan>[];
      for (final doc in snap.docs) {
        try {
          plans.add(
            NutritionPlanDocumentParser.parse(
              id: doc.id,
              dogId: id,
              data: NutritionFirestoreError.asObjectMap(doc.data()),
            ),
          );
        } on HealthDomainException catch (e) {
          debugPrint(
            '[CanonicalPlanReader] integridade dog=$id doc=${doc.id} '
            '[${e.code}]: ${e.message}',
          );
          return NutritionSourceBatch.error(
            code: e.code,
            message:
                'Documento canônico nutrition_plans/${doc.id} inválido: '
                '${e.message}',
          );
        } catch (e) {
          debugPrint(
            '[CanonicalPlanReader] parse falhou dog=$id doc=${doc.id}: $e',
          );
          return NutritionSourceBatch.error(
            code: 'canonical_plan_parse_error',
            message:
                'Documento canônico nutrition_plans/${doc.id} não pôde ser lido',
          );
        }
      }

      return NutritionSourceBatch.available(plans);
    } on FirebaseException catch (e) {
      debugPrint(
        '[CanonicalPlanReader] FirebaseException [${e.code}]: ${e.message}',
      );
      return NutritionFirestoreError.batchFromFirebaseException(
        e,
        sourceKey: NutritionCanonicalPaths.plans,
      );
    } catch (e) {
      debugPrint('[CanonicalPlanReader] unexpected: $e');
      return NutritionFirestoreError.batchFromUnknown(
        e,
        sourceKey: NutritionCanonicalPaths.plans,
      );
    }
  }
}

/// `dogs/{dogId}/meal_logs` — scan completo + range/sort em memória.
///
/// Query final (Gate 4 integrity — **transitória até paginação**):
/// - collection: meal_logs
/// - server filters: nenhum (evita ocultar docs sem `fed_at`)
/// - server orderBy: nenhum
/// - client: parse de TODOS os docs → fail-closed
/// - client range: `from`/`to` sobre `meal.fedAt` **após** parse OK
/// - client order: fedAt DESC, tie-break id
/// - limit / pagination: nenhum (DEFERRED Gate 5+)
/// - índice: nenhum composto
///
/// **Invariante:** documento sem `fed_at` (ou outro campo obrigatório) **não**
/// pode ser excluído pela query — vira integrity error no parser.
final class FirestoreNutritionCanonicalMealReader
    implements NutritionCanonicalMealReader {
  FirestoreNutritionCanonicalMealReader({FirebaseFirestore? firestore})
    : _firestore = firestore;

  final FirebaseFirestore? _firestore;

  FirebaseFirestore get _db => _firestore ?? FirebaseFirestore.instance;

  @override
  Future<NutritionSourceBatch<MealLog>> loadMeals(
    String dogId, {
    DateTime? from,
    DateTime? to,
  }) async {
    final id = dogId.trim();
    if (id.isEmpty) {
      return const NutritionSourceBatch.error(
        code: 'missing_dog_id',
        message: 'dogId é obrigatório',
      );
    }

    try {
      // G4-QUERY-INTEGRITY: NÃO usar orderBy/where em fed_at no servidor.
      // Docs sem fed_at sumiriam da snapshot e escapariam do parser.
      final snap = await _db
          .collection('dogs')
          .doc(id)
          .collection(NutritionCanonicalPaths.mealLogs)
          .get();

      if (snap.docs.isEmpty) {
        return const NutritionSourceBatch.empty(
          message: 'Sem meal_logs canônicos',
        );
      }

      final meals = <MealLog>[];
      for (final doc in snap.docs) {
        try {
          meals.add(
            MealLogDocumentParser.parse(
              id: doc.id,
              dogId: id,
              data: NutritionFirestoreError.asObjectMap(doc.data()),
            ),
          );
        } on HealthDomainException catch (e) {
          debugPrint(
            '[CanonicalMealReader] integridade dog=$id doc=${doc.id} '
            '[${e.code}]: ${e.message}',
          );
          return NutritionSourceBatch.error(
            code: e.code,
            message:
                'Documento canônico meal_logs/${doc.id} inválido: ${e.message}',
          );
        } catch (e) {
          debugPrint(
            '[CanonicalMealReader] parse falhou dog=$id doc=${doc.id}: $e',
          );
          return NutritionSourceBatch.error(
            code: 'canonical_meal_parse_error',
            message: 'Documento canônico meal_logs/${doc.id} não pôde ser lido',
          );
        }
      }

      // Integridade da collection OK — só então projeta range e ordena.
      final fromUtc = from?.toUtc();
      final toUtc = to?.toUtc();
      final filtered = meals.where((m) {
        final fed = m.fedAt.toUtc();
        if (fromUtc != null && fed.isBefore(fromUtc)) return false;
        if (toUtc != null && !fed.isBefore(toUtc)) return false;
        return true;
      }).toList();

      filtered.sort((a, b) {
        final byTime = b.fedAt.compareTo(a.fedAt);
        if (byTime != 0) return byTime;
        return a.id.compareTo(b.id);
      });

      if (filtered.isEmpty) {
        return const NutritionSourceBatch.empty(
          message: 'Sem meal_logs canônicos no intervalo',
        );
      }
      return NutritionSourceBatch.available(filtered);
    } on FirebaseException catch (e) {
      debugPrint(
        '[CanonicalMealReader] FirebaseException [${e.code}]: ${e.message}',
      );
      return NutritionFirestoreError.batchFromFirebaseException(
        e,
        sourceKey: NutritionCanonicalPaths.mealLogs,
      );
    } catch (e) {
      debugPrint('[CanonicalMealReader] unexpected: $e');
      return NutritionFirestoreError.batchFromUnknown(
        e,
        sourceKey: NutritionCanonicalPaths.mealLogs,
      );
    }
  }
}

/// `dogs/{dogId}/supplement_logs` — scan completo + sort em memória.
///
/// Query final (Gate 4 integrity — **transitória até paginação**):
/// - collection: supplement_logs
/// - server filters / orderBy: nenhum (evita ocultar docs sem `administered_at`)
/// - client: parse de TODOS → fail-closed → sort administeredAt DESC
/// - limit / pagination: nenhum (DEFERRED Gate 5+)
/// - índice: nenhum composto
///
/// **Invariante:** documento sem `administered_at` vira integrity error,
/// nunca exclusão silenciosa pela query.
final class FirestoreNutritionCanonicalSupplementLogReader
    implements NutritionCanonicalSupplementLogReader {
  FirestoreNutritionCanonicalSupplementLogReader({FirebaseFirestore? firestore})
    : _firestore = firestore;

  final FirebaseFirestore? _firestore;

  FirebaseFirestore get _db => _firestore ?? FirebaseFirestore.instance;

  @override
  Future<NutritionSourceBatch<SupplementLog>> loadSupplementLogs(
    String dogId,
  ) async {
    final id = dogId.trim();
    if (id.isEmpty) {
      return const NutritionSourceBatch.error(
        code: 'missing_dog_id',
        message: 'dogId é obrigatório',
      );
    }

    try {
      // G4-QUERY-INTEGRITY: NÃO orderBy administered_at no servidor.
      final snap = await _db
          .collection('dogs')
          .doc(id)
          .collection(NutritionCanonicalPaths.supplementLogs)
          .get();

      if (snap.docs.isEmpty) {
        return const NutritionSourceBatch.empty(
          message: 'Sem supplement_logs canônicos',
        );
      }

      final logs = <SupplementLog>[];
      for (final doc in snap.docs) {
        try {
          logs.add(
            SupplementLogDocumentParser.parse(
              id: doc.id,
              dogId: id,
              data: NutritionFirestoreError.asObjectMap(doc.data()),
            ),
          );
        } on HealthDomainException catch (e) {
          debugPrint(
            '[CanonicalSupplementLogReader] integridade dog=$id doc=${doc.id} '
            '[${e.code}]: ${e.message}',
          );
          return NutritionSourceBatch.error(
            code: e.code,
            message:
                'Documento canônico supplement_logs/${doc.id} inválido: '
                '${e.message}',
          );
        } catch (e) {
          debugPrint(
            '[CanonicalSupplementLogReader] parse falhou dog=$id '
            'doc=${doc.id}: $e',
          );
          return NutritionSourceBatch.error(
            code: 'canonical_supplement_parse_error',
            message:
                'Documento canônico supplement_logs/${doc.id} não pôde ser lido',
          );
        }
      }

      logs.sort((a, b) {
        final byTime = b.administeredAt.compareTo(a.administeredAt);
        if (byTime != 0) return byTime;
        return a.id.compareTo(b.id);
      });

      return NutritionSourceBatch.available(logs);
    } on FirebaseException catch (e) {
      debugPrint(
        '[CanonicalSupplementLogReader] FirebaseException [${e.code}]: '
        '${e.message}',
      );
      return NutritionFirestoreError.batchFromFirebaseException(
        e,
        sourceKey: NutritionCanonicalPaths.supplementLogs,
      );
    } catch (e) {
      debugPrint('[CanonicalSupplementLogReader] unexpected: $e');
      return NutritionFirestoreError.batchFromUnknown(
        e,
        sourceKey: NutritionCanonicalPaths.supplementLogs,
      );
    }
  }
}
