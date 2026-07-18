import 'package:canil_gcm/features/health/domain/health_v1_models.dart';
import 'package:canil_gcm/features/health/domain/legacy_nutrition_views.dart';
import 'package:canil_gcm/features/health/domain/nutrition_plan.dart';
import 'package:canil_gcm/features/health/domain/nutrition_read_models.dart';
import 'package:canil_gcm/features/health/domain/nutrition_read_state.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Merge / dedupe determinístico (§22, §30–§31 / D30) — auditoria adversarial.
//
// Proveniência canônico×legado: SOMENTE legacySource + legacyId (ambos).
// legacyId sozinho NUNCA deduplica.
// Sem heurística fedAt/amount/period.
// ─────────────────────────────────────────────────────────────────────────────

/// Envelope de refeição legada com collection de origem.
final class LegacyMealEnvelope {
  const LegacyMealEnvelope({
    required this.meal,
    required this.collectionKey,
  });

  final MealLog meal;

  /// `feeding_events` | `feedings` | outro (antes ou depois de normalizar).
  final String collectionKey;
}

final class NutritionMealMergeResult {
  const NutritionMealMergeResult({
    required this.items,
    required this.diagnostics,
  });

  final List<NutritionMealReadItem> items;
  final List<NutritionMergeDiagnostic> diagnostics;
}

/// Identidade de fonte legada para proveniência (forma canônica interna).
///
/// Representação: leaf collection id em snake/lower:
/// - `feeding_events`
/// - `feedings`
/// - `nutritional_prescriptions`
///
/// Aceita paths/alias comuns e **não** inventa equivalência entre collections
/// distintas (ex.: feedings ≠ feeding_events).
abstract final class NutritionLegacySourceIdentity {
  NutritionLegacySourceIdentity._();

  static const feedingEvents = 'feeding_events';
  static const feedings = 'feedings';

  /// Normaliza para leaf id comparável, ou `null` se vazio/irreconhecível.
  static String? normalize(String? raw) {
    if (raw == null) return null;
    var s = raw.trim().toLowerCase();
    if (s.isEmpty) return null;

    // Path: dogs/{id}/feeding_events → feeding_events
    if (s.contains('/')) {
      final parts = s.split('/').where((p) => p.isNotEmpty).toList();
      if (parts.isNotEmpty) s = parts.last;
    }
    // Prefixos acidentais
    if (s.startsWith('/')) s = s.substring(1);

    // Alias mínimos e determinísticos (sem mapear collections distintas).
    return switch (s) {
      'feeding_events' || 'feeding-events' || 'feedingevents' => feedingEvents,
      'feedings' || 'feeding' => feedings,
      _ => s,
    };
  }

  /// Proveniência inequívoca: source+id presentes e semanticamente iguais.
  static bool matchesProvenience({
    required String? canonicalLegacySource,
    required String? canonicalLegacyId,
    required String? legacyCollectionKey,
    required String legacyDocumentId,
  }) {
    final lid = canonicalLegacyId?.trim();
    if (lid == null || lid.isEmpty) return false;
    if (legacyDocumentId.trim() != lid) return false;

    final a = normalize(canonicalLegacySource);
    final b = normalize(legacyCollectionKey);
    if (a == null || b == null) return false;
    return a == b;
  }
}

abstract final class NutritionMergePolicy {
  NutritionMergePolicy._();

  static const feedingEvents = NutritionLegacySourceIdentity.feedingEvents;
  static const feedings = NutritionLegacySourceIdentity.feedings;

  /// Precedência entre collections legadas de refeição (§22).
  /// Ordem de rank é **independente** da ordem de chegada das Futures.
  static int legacyCollectionRank(String collectionKey) {
    final n = NutritionLegacySourceIdentity.normalize(collectionKey) ??
        collectionKey;
    return switch (n) {
      feedingEvents => 0, // vence
      feedings => 1,
      _ => 50,
    };
  }

  /// Dedupe legado feeding_events × feedings pelo mesmo document id.
  static NutritionMealMergeResult mergeLegacyMealCollections({
    required Iterable<LegacyMealEnvelope> envelopes,
  }) {
    final byId = <String, LegacyMealEnvelope>{};
    final diagnostics = <NutritionMergeDiagnostic>[];

    // Rank fixo — não depende da ordem de chegada.
    final sorted = envelopes.toList()
      ..sort((a, b) {
        final r = legacyCollectionRank(
          a.collectionKey,
        ).compareTo(legacyCollectionRank(b.collectionKey));
        if (r != 0) return r;
        return a.meal.id.compareTo(b.meal.id);
      });

    for (final env in sorted) {
      final normalizedKey =
          NutritionLegacySourceIdentity.normalize(env.collectionKey) ??
          env.collectionKey;
      final normalizedEnv = LegacyMealEnvelope(
        meal: env.meal,
        collectionKey: normalizedKey,
      );

      final existing = byId[normalizedEnv.meal.id];
      if (existing == null) {
        byId[normalizedEnv.meal.id] = normalizedEnv;
        continue;
      }
      final existingRank = legacyCollectionRank(existing.collectionKey);
      final newRank = legacyCollectionRank(normalizedEnv.collectionKey);
      if (newRank < existingRank) {
        if (_payloadDiverges(existing.meal, normalizedEnv.meal)) {
          diagnostics.add(
            NutritionMergeDiagnostic(
              code: 'legacy_meal_payload_conflict',
              message:
                  'Payload divergente para id=${normalizedEnv.meal.id}; '
                  'vence ${normalizedEnv.collectionKey} sobre '
                  '${existing.collectionKey}',
              primaryKey: normalizedEnv.collectionKey,
              secondaryKey: existing.collectionKey,
            ),
          );
        }
        byId[normalizedEnv.meal.id] = normalizedEnv;
      } else if (newRank > existingRank) {
        if (_payloadDiverges(existing.meal, normalizedEnv.meal)) {
          diagnostics.add(
            NutritionMergeDiagnostic(
              code: 'legacy_meal_payload_conflict',
              message:
                  'Payload divergente para id=${normalizedEnv.meal.id}; '
                  'vence ${existing.collectionKey} sobre '
                  '${normalizedEnv.collectionKey}',
              primaryKey: existing.collectionKey,
              secondaryKey: normalizedEnv.collectionKey,
            ),
          );
        }
      }
    }

    final items = byId.values
        .map(
          (e) => NutritionMealReadItem(
            meal: e.meal,
            origin: e.collectionKey == feedingEvents
                ? NutritionDataOrigin.legacyFeedingEvents
                : e.collectionKey == feedings
                ? NutritionDataOrigin.legacyFeedings
                : NutritionDataOrigin.legacy,
            mergeKey: 'legacy:${e.collectionKey}:${e.meal.id}',
            collectionKey: e.collectionKey,
          ),
        )
        .toList(growable: false);

    return NutritionMealMergeResult(
      items: items,
      diagnostics: List.unmodifiable(diagnostics),
    );
  }

  /// Merge canônico × legado.
  ///
  /// Dedupe **somente** com proveniência inequívoca:
  /// `normalize(legacySource) + legacyId` == `normalize(collection) + id`.
  ///
  /// `legacyId` sozinho **nunca** suprime legado.
  static NutritionMealMergeResult mergeCanonicalAndLegacyMeals({
    required Iterable<MealLog> canonical,
    required Iterable<NutritionMealReadItem> legacyItems,
  }) {
    final diagnostics = <NutritionMergeDiagnostic>[];
    final merged = <String, NutritionMealReadItem>{};

    for (final meal in canonical) {
      final key = 'canonical:${meal.id}';
      merged[key] = NutritionMealReadItem(
        meal: meal,
        origin: NutritionDataOrigin.canonical,
        mergeKey: key,
      );
    }

    for (final item in legacyItems) {
      final meal = item.meal;
      final collection =
          item.collectionKey ??
          NutritionLegacySourceIdentity.normalize(meal.legacySource) ??
          '';
      final id = meal.id;

      final matchedCanonical = _findProvenienceMatch(
        canonical: canonical,
        legacyCollectionKey: collection,
        legacyDocumentId: id,
      );

      if (matchedCanonical != null) {
        diagnostics.add(
          NutritionMergeDiagnostic(
            code: 'legacy_suppressed_by_canonical_provenience',
            message:
                'Legado $collection/$id suprimido por MealLog canônico '
                '${matchedCanonical.id} (legacySource+legacyId)',
            primaryKey: 'canonical:${matchedCanonical.id}',
            secondaryKey: '$collection:$id',
          ),
        );
        continue;
      }

      // Diagnóstico opcional: mesmo legacyId sem source match → preservar ambos.
      final idOnlyHint = _canonicalWithSameLegacyIdOnly(
        canonical: canonical,
        legacyDocumentId: id,
      );
      if (idOnlyHint != null) {
        diagnostics.add(
          NutritionMergeDiagnostic(
            code: 'insufficient_provenience_same_legacy_id',
            message:
                'Mesmo legacyId="$id" sem legacySource inequívoco; '
                'ambos preservados (sem dedupe)',
            primaryKey: 'canonical:${idOnlyHint.id}',
            secondaryKey: '$collection:$id',
          ),
        );
      }

      final key = item.mergeKey;
      merged.putIfAbsent(key, () => item);
    }

    final list = merged.values.toList();
    _sortMealsDesc(list);

    return NutritionMealMergeResult(
      items: List.unmodifiable(list),
      diagnostics: List.unmodifiable(diagnostics),
    );
  }

  /// Resolve plano ativo canônico/legado sem mascarar violação D3.
  ///
  /// - 0 active canônico → fallback legado (se houver)
  /// - 1 active canônico → [NutritionActiveCanonicalPlan]
  /// - >1 active canônico → [NutritionActivePlanIntegrityConflict]
  static NutritionActivePlanRef? resolveActivePlan({
    required Iterable<NutritionPlan> canonical,
    required Iterable<LegacyNutritionPlanView> legacy,
  }) {
    final actives = canonical
        .where((p) => p.status == NutritionPlanStatus.active)
        .toList(growable: false);

    if (actives.length > 1) {
      // Ordenação estável só para diagnóstico — NÃO escolhe um plano.
      final ordered = [...actives]
        ..sort((a, b) {
          final byFrom = a.validFrom.compareTo(b.validFrom);
          if (byFrom != 0) return byFrom;
          return a.id.compareTo(b.id);
        });
      return NutritionActivePlanIntegrityConflict(ordered);
    }
    if (actives.length == 1) {
      return NutritionActiveCanonicalPlan(actives.single);
    }

    final l = _latestLegacy(legacy);
    if (l != null) {
      return NutritionActiveLegacyPlan(l);
    }
    return null;
  }

  static MealLog? _findProvenienceMatch({
    required Iterable<MealLog> canonical,
    required String legacyCollectionKey,
    required String legacyDocumentId,
  }) {
    for (final m in canonical) {
      if (NutritionLegacySourceIdentity.matchesProvenience(
        canonicalLegacySource: m.legacySource,
        canonicalLegacyId: m.legacyId,
        legacyCollectionKey: legacyCollectionKey,
        legacyDocumentId: legacyDocumentId,
      )) {
        return m;
      }
    }
    return null;
  }

  static MealLog? _canonicalWithSameLegacyIdOnly({
    required Iterable<MealLog> canonical,
    required String legacyDocumentId,
  }) {
    final id = legacyDocumentId.trim();
    if (id.isEmpty) return null;
    for (final m in canonical) {
      final lid = m.legacyId?.trim();
      if (lid != id) continue;
      final src = NutritionLegacySourceIdentity.normalize(m.legacySource);
      if (src == null) return m;
    }
    return null;
  }

  static LegacyNutritionPlanView? _latestLegacy(
    Iterable<LegacyNutritionPlanView> plans,
  ) {
    LegacyNutritionPlanView? best;
    for (final p in plans) {
      if (best == null ||
          p.vigentFrom.isAfter(best.vigentFrom) ||
          (p.vigentFrom.isAtSameMomentAs(best.vigentFrom) &&
              p.id.compareTo(best.id) < 0)) {
        best = p;
      }
    }
    return best;
  }

  static void _sortMealsDesc(List<NutritionMealReadItem> list) {
    list.sort((a, b) {
      final byTime = b.fedAt.compareTo(a.fedAt);
      if (byTime != 0) return byTime;
      return a.mergeKey.compareTo(b.mergeKey);
    });
  }

  static bool _payloadDiverges(MealLog a, MealLog b) {
    return a.offeredGrams != b.offeredGrams ||
        a.fedAt != b.fedAt ||
        a.period != b.period ||
        a.consumedGrams != b.consumedGrams ||
        a.acceptance != b.acceptance;
  }
}
