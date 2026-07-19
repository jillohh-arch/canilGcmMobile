import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import 'package:canil_gcm/features/health/data/coexistence/nutrition/coexistence_nutrition_read_source.dart';
import 'package:canil_gcm/features/health/data/coexistence/nutrition/nutrition_firestore_error.dart';
import 'package:canil_gcm/features/health/data/coexistence/nutrition/nutrition_merge_policy.dart';
import 'package:canil_gcm/features/health/domain/health_v1_models.dart';
import 'package:canil_gcm/features/health/domain/legacy_nutrition_views.dart';
import 'package:canil_gcm/features/health/legacy/legacy_health_adapters.dart';
import 'package:canil_gcm/features/health/legacy/legacy_nutrition_plan_adapter.dart';
import 'package:canil_gcm/features/health/legacy/legacy_supplement_regimen_adapter.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Delegates Firestore legados READ-ONLY (5D Gate 4).
// ZERO add/set/update/delete. Não dependem de NutritionService write-capable.
// ─────────────────────────────────────────────────────────────────────────────

/// Dual-read de planos legados:
/// `nutritional_prescriptions` + `nutrition_prescriptions`.
///
/// Query por collection:
/// - get() da subcoleção do dog (sem filtro composto)
/// - índice: nenhum novo
final class FirestoreNutritionLegacyPlanReader
    implements NutritionLegacyPlanReader {
  FirestoreNutritionLegacyPlanReader({
    FirebaseFirestore? firestore,
    LegacyNutritionPlanAdapter? adapter,
  }) : _firestore = firestore,
       _adapter = adapter ?? const LegacyNutritionPlanAdapter();

  final FirebaseFirestore? _firestore;
  final LegacyNutritionPlanAdapter _adapter;

  FirebaseFirestore get _db => _firestore ?? FirebaseFirestore.instance;

  static const _collections = <String>[
    'nutritional_prescriptions',
    'nutrition_prescriptions',
  ];

  @override
  Future<NutritionSourceBatch<LegacyNutritionPlanView>> loadPlans(
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
      final views = <LegacyNutritionPlanView>[];
      var sawDocs = false;
      String? firstIntegrity;

      for (final collectionKey in _collections) {
        final snap = await _db
            .collection('dogs')
            .doc(id)
            .collection(collectionKey)
            .get();
        if (snap.docs.isNotEmpty) sawDocs = true;

        for (final doc in snap.docs) {
          final result = _adapter.parse(
            sourceId: doc.id,
            dogId: id,
            data: NutritionFirestoreError.asLegacyDomainMap(doc.data()),
            legacySource: collectionKey,
          );
          if (result.hasValue) {
            views.add(result.value!);
          } else if (result.state == LegacyParseState.failure) {
            firstIntegrity ??=
                'legacy_plan_parse_error:$collectionKey/${doc.id}';
            debugPrint(
              '[LegacyPlanReader] parse failure $collectionKey/${doc.id}: '
              '${result.issues.map((i) => i.code).join(",")}',
            );
          }
        }
      }

      if (views.isEmpty && firstIntegrity != null && sawDocs) {
        // Docs existem mas nenhum parseável → erro de integridade, não empty.
        return NutritionSourceBatch.error(
          code: 'legacy_plan_integrity',
          message: 'Prescrições legadas inválidas ($firstIntegrity)',
        );
      }

      if (views.isEmpty) {
        return const NutritionSourceBatch.empty(message: 'Sem planos legados');
      }
      return NutritionSourceBatch.available(views);
    } on FirebaseException catch (e) {
      debugPrint(
        '[LegacyPlanReader] FirebaseException [${e.code}]: ${e.message}',
      );
      return NutritionFirestoreError.batchFromFirebaseException(
        e,
        sourceKey: 'nutritional_prescriptions',
      );
    } catch (e) {
      debugPrint('[LegacyPlanReader] unexpected: $e');
      return NutritionFirestoreError.batchFromUnknown(
        e,
        sourceKey: 'nutritional_prescriptions',
      );
    }
  }
}

/// Uma collection legada de refeição (`feeding_events` ou `feedings`).
///
/// Query (com from/to):
/// - where fed_at >= from / < to
/// - orderBy fed_at DESC
///
/// Sem range: orderBy fed_at DESC.
final class FirestoreNutritionLegacyMealReader
    implements NutritionLegacyMealReader {
  FirestoreNutritionLegacyMealReader({
    required this.collectionKey,
    FirebaseFirestore? firestore,
    LegacyNutritionAdapter? adapter,
  }) : _firestore = firestore,
       _adapter = adapter ?? const LegacyNutritionAdapter();

  @override
  final String collectionKey;

  final FirebaseFirestore? _firestore;
  final LegacyNutritionAdapter _adapter;

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

    final key =
        NutritionLegacySourceIdentity.normalize(collectionKey) ?? collectionKey;

    try {
      Query<Map<String, dynamic>> q = _db
          .collection('dogs')
          .doc(id)
          .collection(key);

      if (from != null) {
        q = q.where(
          'fed_at',
          isGreaterThanOrEqualTo: Timestamp.fromDate(from.toUtc()),
        );
      }
      if (to != null) {
        q = q.where('fed_at', isLessThan: Timestamp.fromDate(to.toUtc()));
      }
      q = q.orderBy('fed_at', descending: true);

      final snap = await q.get();
      if (snap.docs.isEmpty) {
        return NutritionSourceBatch.empty(message: 'Sem refeições em $key');
      }

      final meals = <MealLog>[];
      String? firstIntegrity;
      for (final doc in snap.docs) {
        final data = NutritionFirestoreError.asLegacyDomainMap(doc.data());
        // Garante proveniência de collection no adapter.
        final withSource = Map<String, Object?>.from(data)
          ..putIfAbsent('legacy_source', () => key);
        final result = _adapter.parse(
          sourceId: doc.id,
          dogId: id,
          data: withSource,
        );
        var value = result.value;
        if (value is LegacyHealthRecordView &&
            result.state == LegacyParseState.partial) {
          // Produção legada possui refeições com `fed_by` textual, sem
          // uid/role suficientes para RecordedBy. O adapter puro preserva esses
          // docs como view; para a UI read-only, materializamos um ator técnico
          // de compatibilidade que nunca é apresentado como autoria real.
          final fedBy = withSource['fed_by']?.toString().trim();
          final reparsed = _adapter.parse(
            sourceId: doc.id,
            dogId: id,
            data: Map<String, Object?>.from(withSource)
              ..['recorded_by'] = <String, Object?>{
                'uid': 'legacy-unattributed:${doc.id}',
                'name': fedBy == null || fedBy.isEmpty
                    ? 'Autoria legada não informada'
                    : fedBy,
                'internal_role': 'legacy',
              },
          );
          value = reparsed.value;
        }
        if (value is MealLog) {
          meals.add(value);
        } else if (result.state == LegacyParseState.failure) {
          firstIntegrity ??= '$key/${doc.id}';
          debugPrint(
            '[LegacyMealReader] parse failure $key/${doc.id}: '
            '${result.issues.map((i) => i.code).join(",")}',
          );
        }
        // partial sem MealLog (ex.: incomplete author → LegacyHealthRecordView)
        // não entra no batch de meals; não mascara como empty se houver outros.
      }

      if (meals.isEmpty && firstIntegrity != null) {
        return NutritionSourceBatch.error(
          code: 'legacy_meal_integrity',
          message: 'Refeições legadas inválidas ($firstIntegrity)',
        );
      }
      if (meals.isEmpty) {
        // Docs existem mas só views não-MealLog (autoria incompleta etc.).
        // Não é empty de “zero documentos”: reporta erro de fonte se saw docs.
        if (snap.docs.isNotEmpty) {
          return NutritionSourceBatch.error(
            code: 'legacy_meal_unmapped',
            message: 'Documentos em $key não mapearam para MealLog utilizável',
          );
        }
        return NutritionSourceBatch.empty(message: 'Sem refeições em $key');
      }
      return NutritionSourceBatch.available(meals);
    } on FirebaseException catch (e) {
      debugPrint(
        '[LegacyMealReader] $key FirebaseException [${e.code}]: ${e.message}',
      );
      return NutritionFirestoreError.batchFromFirebaseException(
        e,
        sourceKey: key,
      );
    } catch (e) {
      debugPrint('[LegacyMealReader] $key unexpected: $e');
      return NutritionFirestoreError.batchFromUnknown(e, sourceKey: key);
    }
  }
}

/// `dogs/{dogId}/nutrition_supplements` — regimes legados (≠ administração).
///
/// Query: get() da subcoleção; sem order/limit obrigatórios.
final class FirestoreNutritionLegacySupplementRegimenReader
    implements NutritionLegacySupplementRegimenReader {
  FirestoreNutritionLegacySupplementRegimenReader({
    FirebaseFirestore? firestore,
    LegacySupplementRegimenAdapter? adapter,
  }) : _firestore = firestore,
       _adapter = adapter ?? const LegacySupplementRegimenAdapter();

  final FirebaseFirestore? _firestore;
  final LegacySupplementRegimenAdapter _adapter;

  FirebaseFirestore get _db => _firestore ?? FirebaseFirestore.instance;

  static const collectionKey = 'nutrition_supplements';

  @override
  Future<NutritionSourceBatch<LegacySupplementRegimenView>> loadRegimens(
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
      final snap = await _db
          .collection('dogs')
          .doc(id)
          .collection(collectionKey)
          .get();

      if (snap.docs.isEmpty) {
        return const NutritionSourceBatch.empty(
          message: 'Sem nutrition_supplements legados',
        );
      }

      final regimens = <LegacySupplementRegimenView>[];
      String? firstIntegrity;
      for (final doc in snap.docs) {
        final result = _adapter.parse(
          sourceId: doc.id,
          dogId: id,
          data: NutritionFirestoreError.asLegacyDomainMap(doc.data()),
          legacySource: collectionKey,
        );
        if (result.hasValue) {
          regimens.add(result.value!);
        } else if (result.state == LegacyParseState.failure) {
          firstIntegrity ??= doc.id;
          debugPrint(
            '[LegacySupplementRegimenReader] parse failure ${doc.id}: '
            '${result.issues.map((i) => i.code).join(",")}',
          );
        }
      }

      if (regimens.isEmpty && firstIntegrity != null) {
        return NutritionSourceBatch.error(
          code: 'legacy_regimen_integrity',
          message: 'Regimes legados inválidos ($firstIntegrity)',
        );
      }
      if (regimens.isEmpty) {
        return const NutritionSourceBatch.empty(
          message: 'Sem regimes legados utilizáveis',
        );
      }
      return NutritionSourceBatch.available(regimens);
    } on FirebaseException catch (e) {
      debugPrint(
        '[LegacySupplementRegimenReader] FirebaseException [${e.code}]: '
        '${e.message}',
      );
      return NutritionFirestoreError.batchFromFirebaseException(
        e,
        sourceKey: collectionKey,
      );
    } catch (e) {
      debugPrint('[LegacySupplementRegimenReader] unexpected: $e');
      return NutritionFirestoreError.batchFromUnknown(
        e,
        sourceKey: collectionKey,
      );
    }
  }
}
