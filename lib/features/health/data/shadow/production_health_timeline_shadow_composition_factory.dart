// Copyright 2024 GCM Health. All rights reserved.
//
// PRODUCTION HEALTH TIMELINE SHADOW COMPOSITION FACTORY (4C-C-C-H3B1).
//
// Pure production composition connecting FirebaseFirestore to coexistence sources,
// canonical readers, bridge, adapter, runner, and shadow composition factory.

import 'package:cloud_firestore/cloud_firestore.dart';

import 'package:canil_gcm/features/health/data/canonical/timeline/raw_canonical_nutrition_shadow_bridge.dart';
import 'package:canil_gcm/features/health/data/canonical/timeline/raw_canonical_nutrition_source.dart';
import 'package:canil_gcm/features/health/data/coexistence/nutrition/firestore_nutrition_canonical_readers.dart';
import 'package:canil_gcm/features/health/data/coexistence/timeline/coexistence_health_timeline_source.dart';
import 'package:canil_gcm/features/health/data/shadow/health_timeline_shadow_composition_factory.dart';
import 'package:canil_gcm/features/health/data/shadow/health_timeline_shadow_models.dart';
import 'package:canil_gcm/features/health/data/shadow/health_timeline_shadow_runner.dart';
import 'package:canil_gcm/features/health/data/shadow/health_timeline_shadow_runner_executor.dart';

/// Construtor de composição produtiva que encapsula a fiação de dependências
/// do [FirebaseFirestore] para a [HealthTimelineShadowCompositionFactory].
abstract final class ProductionHealthTimelineShadowCompositionFactory {
  ProductionHealthTimelineShadowCompositionFactory._();

  /// Instancia uma [HealthTimelineShadowCompositionFactory] vinculada ao [firestore].
  ///
  /// Se [firestore] não for fornecido, resolve para [FirebaseFirestore.instance].
  static HealthTimelineShadowCompositionFactory forFirestore({
    FirebaseFirestore? firestore,
    HealthTimelineShadowObserver? observer,
    HealthTimelineShadowRunnerExecutor runnerExecutor =
        const DefaultHealthTimelineShadowRunnerExecutor(),
    Duration shadowTimeout = const Duration(seconds: 5),
  }) {
    final resolvedFirestore = firestore ?? FirebaseFirestore.instance;

    return HealthTimelineShadowCompositionFactory(
      coexistenceSourceFactory: () =>
          CoexistenceHealthTimelineSourceFactory.forFirestore(
            firestore: resolvedFirestore,
          ),
      runnerFactory: () {
        final mealReader = FirestoreNutritionCanonicalMealReader(
          firestore: resolvedFirestore,
        );

        final supplementReader = FirestoreNutritionCanonicalSupplementLogReader(
          firestore: resolvedFirestore,
        );

        final rawSource = ReaderBackedRawCanonicalNutritionFirstPageSource(
          mealReader: mealReader,
          supplementReader: supplementReader,
        );

        final bridge = RawCanonicalNutritionShadowBridge(rawSource: rawSource);

        final comparator = RawCanonicalNutritionShadowBridgeAdapter(
          bridge: bridge,
        );

        return HealthTimelineNutritionShadowRunner(comparator: comparator);
      },
      observer: observer,
      runnerExecutor: runnerExecutor,
      shadowTimeout: shadowTimeout,
    );
  }
}
