import 'package:canil_gcm/features/health/data/coexistence/nutrition/nutrition_merge_policy.dart';
import 'package:canil_gcm/features/health/domain/health_v1_models.dart';
import 'package:canil_gcm/features/health/domain/legacy_nutrition_views.dart';
import 'package:canil_gcm/features/health/domain/meal_occurrence.dart';
import 'package:canil_gcm/features/health/domain/nutrition_plan.dart';
import 'package:canil_gcm/features/health/domain/nutrition_read_models.dart';
import 'package:canil_gcm/features/health/domain/nutrition_read_state.dart';
import 'package:canil_gcm/features/health/domain/supplement_log.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Coexistence read source (§26–§29).
// Coordenador puro sobre delegates injetados. ZERO Firebase. ZERO write.
// NÃO conecta composition root de produção nesta fase.
// ─────────────────────────────────────────────────────────────────────────────

/// Contrato read-only de planos canônicos.
abstract interface class NutritionCanonicalPlanReader {
  Future<NutritionSourceBatch<NutritionPlan>> loadPlans(String dogId);
}

/// Contrato read-only de planos legados (view de compatibilidade).
abstract interface class NutritionLegacyPlanReader {
  Future<NutritionSourceBatch<LegacyNutritionPlanView>> loadPlans(String dogId);
}

/// Contrato read-only de meal logs canônicos.
abstract interface class NutritionCanonicalMealReader {
  Future<NutritionSourceBatch<MealLog>> loadMeals(
    String dogId, {
    DateTime? from,
    DateTime? to,
  });
}

/// Contrato read-only de refeições legadas (com collection key).
abstract interface class NutritionLegacyMealReader {
  /// `feeding_events` | `feedings` | …
  String get collectionKey;

  Future<NutritionSourceBatch<MealLog>> loadMeals(
    String dogId, {
    DateTime? from,
    DateTime? to,
  });
}

/// Supplement logs canônicos (administração).
abstract interface class NutritionCanonicalSupplementLogReader {
  Future<NutritionSourceBatch<SupplementLog>> loadSupplementLogs(String dogId);
}

/// Regime legado (`nutrition_supplements`) — nunca logs de administração.
abstract interface class NutritionLegacySupplementRegimenReader {
  Future<NutritionSourceBatch<LegacySupplementRegimenView>> loadRegimens(
    String dogId,
  );
}

/// Lote com disponibilidade explícita (erro ≠ empty).
final class NutritionSourceBatch<T> {
  const NutritionSourceBatch({
    required this.availability,
    this.items = const [],
    this.message,
    this.code,
  });

  NutritionSourceBatch.available(List<T> items)
    : availability = items.isEmpty
          ? NutritionSourceAvailability.empty
          : NutritionSourceAvailability.available,
      items = List.unmodifiable(items),
      message = null,
      code = null;

  const NutritionSourceBatch.empty({String? message})
    : this(availability: NutritionSourceAvailability.empty, message: message);

  const NutritionSourceBatch.error({String? message, String? code})
    : this(
        availability: NutritionSourceAvailability.error,
        message: message,
        code: code,
      );

  const NutritionSourceBatch.offline({String? message, String? code})
    : this(
        availability: NutritionSourceAvailability.offline,
        message: message,
        code: code,
      );

  final NutritionSourceAvailability availability;
  final List<T> items;
  final String? message;
  final String? code;
}

/// Coordenador de coexistência — somente leitura composta.
final class CoexistenceNutritionReadSource {
  CoexistenceNutritionReadSource({
    this.canonicalPlanReader,
    this.legacyPlanReader,
    this.canonicalMealReader,
    List<NutritionLegacyMealReader>? legacyMealReaders,
    this.canonicalSupplementLogReader,
    this.legacySupplementRegimenReader,
  }) : _legacyMealReaders = List.unmodifiable(legacyMealReaders ?? const []);

  final NutritionCanonicalPlanReader? canonicalPlanReader;
  final NutritionLegacyPlanReader? legacyPlanReader;
  final NutritionCanonicalMealReader? canonicalMealReader;
  final List<NutritionLegacyMealReader> _legacyMealReaders;
  final NutritionCanonicalSupplementLogReader? canonicalSupplementLogReader;
  final NutritionLegacySupplementRegimenReader? legacySupplementRegimenReader;

  Future<NutritionReadResult<NutritionCoexistenceSnapshot>> loadSnapshot(
    String dogId, {
    DateTime? mealsFrom,
    DateTime? mealsTo,
  }) async {
    if (dogId.trim().isEmpty) {
      return const NutritionReadResult.error(
        code: 'missing_dog_id',
        message: 'dogId é obrigatório',
      );
    }

    final planStatuses = <NutritionSourceStatus>[];
    final mealStatuses = <NutritionSourceStatus>[];
    final canonicalPlans = <NutritionPlan>[];
    final legacyPlans = <LegacyNutritionPlanView>[];
    final canonicalMeals = <MealLog>[];
    final legacyEnvelopes = <LegacyMealEnvelope>[];
    final canonicalLogs = <SupplementLog>[];
    var canonicalSupplementLogAvailability =
        NutritionSourceAvailability.notConfigured;
    final legacyRegimens = <LegacySupplementRegimenView>[];
    final allDiagnostics = <NutritionMergeDiagnostic>[];

    // ── plans ──────────────────────────────────────────────────────────────
    final cPlan = canonicalPlanReader;
    if (cPlan != null) {
      try {
        final batch = await cPlan.loadPlans(dogId);
        planStatuses.add(
          NutritionSourceStatus(
            origin: NutritionDataOrigin.canonical,
            availability: batch.availability,
            message: batch.message,
            code: batch.code,
            sourceKey: 'nutrition_plans',
          ),
        );
        if (batch.availability == NutritionSourceAvailability.available ||
            batch.availability == NutritionSourceAvailability.empty) {
          // Isolamento por dogId (defesa).
          canonicalPlans.addAll(batch.items.where((p) => p.dogId == dogId));
        }
      } catch (e) {
        planStatuses.add(
          NutritionSourceStatus(
            origin: NutritionDataOrigin.canonical,
            availability: NutritionSourceAvailability.error,
            message: e.toString(),
            code: 'canonical_plan_exception',
            sourceKey: 'nutrition_plans',
          ),
        );
      }
    }

    final lPlan = legacyPlanReader;
    if (lPlan != null) {
      try {
        final batch = await lPlan.loadPlans(dogId);
        planStatuses.add(
          NutritionSourceStatus(
            origin: NutritionDataOrigin.legacy,
            availability: batch.availability,
            message: batch.message,
            code: batch.code,
            sourceKey: 'nutritional_prescriptions',
          ),
        );
        if (batch.availability == NutritionSourceAvailability.available ||
            batch.availability == NutritionSourceAvailability.empty) {
          legacyPlans.addAll(batch.items.where((p) => p.dogId == dogId));
        }
      } catch (e) {
        planStatuses.add(
          NutritionSourceStatus(
            origin: NutritionDataOrigin.legacy,
            availability: NutritionSourceAvailability.error,
            message: e.toString(),
            code: 'legacy_plan_exception',
            sourceKey: 'nutritional_prescriptions',
          ),
        );
      }
    }

    // ── meals ──────────────────────────────────────────────────────────────
    final cMeal = canonicalMealReader;
    if (cMeal != null) {
      try {
        final batch = await cMeal.loadMeals(
          dogId,
          from: mealsFrom,
          to: mealsTo,
        );
        mealStatuses.add(
          NutritionSourceStatus(
            origin: NutritionDataOrigin.canonical,
            availability: batch.availability,
            message: batch.message,
            code: batch.code,
            sourceKey: 'meal_logs',
          ),
        );
        if (batch.availability == NutritionSourceAvailability.available ||
            batch.availability == NutritionSourceAvailability.empty) {
          canonicalMeals.addAll(batch.items.where((m) => m.dogId == dogId));
        }
      } catch (e) {
        mealStatuses.add(
          NutritionSourceStatus(
            origin: NutritionDataOrigin.canonical,
            availability: NutritionSourceAvailability.error,
            message: e.toString(),
            code: 'canonical_meal_exception',
            sourceKey: 'meal_logs',
          ),
        );
      }
    }

    for (final reader in _legacyMealReaders) {
      try {
        final batch = await reader.loadMeals(
          dogId,
          from: mealsFrom,
          to: mealsTo,
        );
        mealStatuses.add(
          NutritionSourceStatus(
            origin: reader.collectionKey == NutritionMergePolicy.feedingEvents
                ? NutritionDataOrigin.legacyFeedingEvents
                : reader.collectionKey == NutritionMergePolicy.feedings
                ? NutritionDataOrigin.legacyFeedings
                : NutritionDataOrigin.legacy,
            availability: batch.availability,
            message: batch.message,
            code: batch.code,
            sourceKey: reader.collectionKey,
          ),
        );
        if (batch.availability == NutritionSourceAvailability.available ||
            batch.availability == NutritionSourceAvailability.empty) {
          for (final m in batch.items.where((m) => m.dogId == dogId)) {
            legacyEnvelopes.add(
              LegacyMealEnvelope(meal: m, collectionKey: reader.collectionKey),
            );
          }
        }
      } catch (e) {
        mealStatuses.add(
          NutritionSourceStatus(
            origin: NutritionDataOrigin.legacy,
            availability: NutritionSourceAvailability.error,
            message: e.toString(),
            code: 'legacy_meal_exception',
            sourceKey: reader.collectionKey,
          ),
        );
      }
    }

    // ── supplements ────────────────────────────────────────────────────────
    final cSupp = canonicalSupplementLogReader;
    if (cSupp != null) {
      try {
        final batch = await cSupp.loadSupplementLogs(dogId);
        canonicalSupplementLogAvailability = batch.availability;
        if (batch.availability == NutritionSourceAvailability.available) {
          canonicalLogs.addAll(batch.items.where((s) => s.dogId == dogId));
        }
        if (batch.availability == NutritionSourceAvailability.error ||
            batch.availability == NutritionSourceAvailability.offline) {
          allDiagnostics.add(
            NutritionMergeDiagnostic(
              code: 'supplement_log_source_error',
              message:
                  batch.message ?? 'Falha ao ler supplement_logs canônicos',
            ),
          );
        }
      } catch (_) {
        canonicalSupplementLogAvailability = NutritionSourceAvailability.error;
        // Falha de supplement não mascara meals/plans; fica sem logs.
        allDiagnostics.add(
          const NutritionMergeDiagnostic(
            code: 'supplement_log_source_error',
            message: 'Falha ao ler supplement_logs canônicos',
          ),
        );
      }
    }

    final lSupp = legacySupplementRegimenReader;
    if (lSupp != null) {
      try {
        final batch = await lSupp.loadRegimens(dogId);
        if (batch.availability == NutritionSourceAvailability.available) {
          legacyRegimens.addAll(batch.items.where((s) => s.dogId == dogId));
        }
      } catch (_) {
        allDiagnostics.add(
          const NutritionMergeDiagnostic(
            code: 'legacy_regimen_source_error',
            message: 'Falha ao ler nutrition_supplements legados',
          ),
        );
      }
    }

    // ── merge ──────────────────────────────────────────────────────────────
    final legacyMerged = NutritionMergePolicy.mergeLegacyMealCollections(
      envelopes: legacyEnvelopes,
    );
    allDiagnostics.addAll(legacyMerged.diagnostics);

    final mealsMerged = NutritionMergePolicy.mergeCanonicalAndLegacyMeals(
      canonical: canonicalMeals,
      legacyItems: legacyMerged.items,
    );
    allDiagnostics.addAll(mealsMerged.diagnostics);

    final activePlan = NutritionMergePolicy.resolveActivePlan(
      canonical: canonicalPlans,
      legacy: legacyPlans,
    );
    if (activePlan is NutritionActivePlanIntegrityConflict) {
      allDiagnostics.add(
        NutritionMergeDiagnostic(
          code: activePlan.code,
          message:
              'D3 violado: ${activePlan.activeCount} NutritionPlan active '
              'para dog=$dogId; ids=${activePlan.activePlanIds.join(",")}',
          primaryKey: dogId,
        ),
      );
    }

    final snapshot = NutritionCoexistenceSnapshot(
      dogId: dogId,
      canonicalPlans: List.unmodifiable(canonicalPlans),
      legacyPlans: List.unmodifiable(legacyPlans),
      canonicalMeals: List.unmodifiable(canonicalMeals),
      legacyMeals: List.unmodifiable(
        legacyEnvelopes.map((e) => e.meal).toList(),
      ),
      canonicalSupplementLogs: List.unmodifiable(canonicalLogs),
      canonicalSupplementLogAvailability: canonicalSupplementLogAvailability,
      legacySupplementRegimens: List.unmodifiable(legacyRegimens),
      planSources: List.unmodifiable(planStatuses),
      mealSources: List.unmodifiable(mealStatuses),
      mergedMeals: mealsMerged.items,
      activePlan: activePlan,
      mergeDiagnostics: List.unmodifiable(allDiagnostics),
    );

    final anyConfigured = planStatuses.isNotEmpty || mealStatuses.isNotEmpty;
    if (!anyConfigured) {
      return const NutritionReadResult.error(
        code: 'no_sources_configured',
        message: 'Nenhuma fonte de nutrição configurada',
      );
    }

    final planUsable =
        planStatuses.isEmpty || planStatuses.any((s) => s.isUsable);
    final mealUsable =
        mealStatuses.isEmpty || mealStatuses.any((s) => s.isUsable);
    final allFailed =
        planStatuses.isNotEmpty &&
        planStatuses.every((s) => s.isFailure) &&
        mealStatuses.isNotEmpty &&
        mealStatuses.every((s) => s.isFailure);

    if (allFailed || (!planUsable && !mealUsable && planStatuses.isNotEmpty)) {
      final all = [...planStatuses, ...mealStatuses];
      final allOffline =
          all.isNotEmpty &&
          all.every(
            (s) => s.availability == NutritionSourceAvailability.offline,
          );
      if (allOffline) {
        return const NutritionReadResult.offline(
          message: 'Fontes de nutrição offline',
          code: 'nutrition_offline',
        );
      }
      return const NutritionReadResult.error(
        message: 'Não foi possível carregar nutrição',
        code: 'nutrition_unavailable',
      );
    }

    final hasData =
        activePlan != null ||
        mealsMerged.items.isNotEmpty ||
        canonicalLogs.isNotEmpty ||
        legacyRegimens.isNotEmpty;

    if (!hasData && !snapshot.isPartiallyFailed) {
      return NutritionReadResult.empty(
        message: 'Sem registros de nutrição para $dogId',
      );
    }

    // §29: canonical error + legacy data → degraded (e vice-versa).
    if (snapshot.isPartiallyFailed && hasData) {
      return NutritionReadResult.degraded(
        snapshot,
        code: 'partial_source_failure',
        message: 'Leitura parcial: uma ou mais fontes falharam',
      );
    }

    if (!hasData && snapshot.isPartiallyFailed) {
      // Só falhas parciais sem dados — ainda error, não empty.
      return const NutritionReadResult.error(
        message: 'Fontes falharam sem dados utilizáveis',
        code: 'nutrition_unavailable',
      );
    }

    return NutritionReadResult.data(snapshot);
  }

  Future<NutritionReadResult<NutritionTodayReadModel>> loadToday(
    String dogId, {
    required DateTime serverNow,
  }) async {
    final snapResult = await loadSnapshot(dogId);
    return projectTodayFromSnapshot(
      dogId: dogId,
      snapshotResult: snapResult,
      serverNow: serverNow,
    );
  }

  /// Projeção normativa única de dados comunicados como pertencentes a hoje.
  ///
  /// Listas do snapshot permanecem históricas até passarem por este filtro.
  /// Projeta a visão diária a partir de um snapshot já resolvido.
  ///
  /// Esta é a única implementação normativa da projeção. Consumidores que
  /// já carregaram o snapshot devem reutilizá-la para evitar uma segunda
  /// leitura e manter plano, execuções e diagnósticos atomicamente coerentes.
  NutritionReadResult<NutritionTodayReadModel> projectTodayFromSnapshot({
    required String dogId,
    required NutritionReadResult<NutritionCoexistenceSnapshot> snapshotResult,
    required DateTime serverNow,
  }) {
    if (snapshotResult.isError) {
      return NutritionReadResult.error(
        message: snapshotResult.message,
        code: snapshotResult.code,
      );
    }
    if (snapshotResult.isOffline) {
      return NutritionReadResult.offline(
        message: snapshotResult.message,
        code: snapshotResult.code,
      );
    }
    if (snapshotResult.isEmpty) {
      return NutritionReadResult.empty(message: snapshotResult.message);
    }

    final snap = snapshotResult.value;
    if (snap == null) {
      return const NutritionReadResult.error(
        code: 'missing_snapshot',
        message: 'Snapshot ausente',
      );
    }

    final tzName = switch (snap.activePlan) {
      NutritionActiveCanonicalPlan(:final plan) => plan.timezone,
      // Conflito D3: não inventar TZ a partir de um active arbitrário.
      NutritionActivePlanIntegrityConflict() => NutritionPlan.defaultTimezone,
      _ => NutritionPlan.defaultTimezone,
    };
    final localDate = LocalServiceDate.fromInstant(serverNow, timezone: tzName);

    final mealsToday = snap.mergedMeals
        .where((item) {
          final itemDate = LocalServiceDate.fromInstant(
            item.fedAt,
            timezone: tzName,
          );
          return itemDate == localDate;
        })
        .toList(growable: false);

    // BLOCO A: filtrar SupplementLogs pelo dia local.
    // MANTER fonte canônica completa (snap.canonicalSupplementLogs) para
    // Timeline/Histórico futuro. A projeção diária é separada.
    // §5D-Gate5C.4B: `startInclusive <= administeredAt < endExclusive`.
    final supplementLogsToday = snap.canonicalSupplementLogs
        .where((log) {
          final logDate = LocalServiceDate.fromInstant(
            log.administeredAt,
            timezone: tzName,
          );
          return logDate == localDate;
        })
        .toList(growable: false);

    final today = NutritionTodayReadModel(
      dogId: dogId,
      localServiceDate: localDate.isoDate,
      timezone: tzName,
      activePlan: snap.activePlan,
      meals: mealsToday,
      canonicalSupplementLogs: supplementLogsToday,
      canonicalSupplementLogsAvailable: !snap.hasSupplementLogSourceFailure,
      legacySupplementRegimens: snap.legacySupplementRegimens,
    );

    if (snapshotResult.isDegraded) {
      return NutritionReadResult.degraded(
        today,
        message: snapshotResult.message,
        code: snapshotResult.code,
      );
    }
    return NutritionReadResult.data(today);
  }
}
