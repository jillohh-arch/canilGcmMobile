import 'package:canil_gcm/features/health/domain/health_v1_enums_ext.dart';
import 'package:canil_gcm/features/health/presentation/timeline/detail/health_timeline_detail_resolution.dart';
import 'package:canil_gcm/features/health/presentation/timeline/detail/health_timeline_detail_target.dart';
import 'package:canil_gcm/features/health/presentation/timeline/health_timeline_entry_view.dart';
import 'package:canil_gcm/features/health/presentation/timeline/models/health_timeline_detail_reference.dart';

/// Resolver puro de navegação contextual (allowlist).
///
/// Sem BuildContext, sem Navigator, sem Firestore, sem imports da source 3C.
///
/// ## Matriz (pós-auditoria)
/// | origem | destino | kind | status |
/// | health_events | — | none | unsupported |
/// | weight_records | histórico de peso | relatedHistory | resolved |
/// | feeding_* | histórico alimentação | relatedHistory | resolved |
/// | vacinas | histórico vacinação | relatedHistory | resolved |
/// | raw hostil | — | none | unsupported |
/// | type×source mismatch | — | none | unavailable |
abstract final class HealthTimelineDetailResolver {
  HealthTimelineDetailResolver._();

  // Constantes locais (espelham collections 3C sem acoplar à camada data).
  static const sourceWeightRecords = 'weight_records';
  static const sourceFeedingEvents = 'feeding_events';
  static const sourceFeedings = 'feedings';
  static const sourceVacinas = 'vacinas';
  static const sourceHealthEvents = 'health_events';

  static const _allowlist = <String>{
    sourceWeightRecords,
    sourceFeedingEvents,
    sourceFeedings,
    sourceVacinas,
  };

  /// Resolve a partir da referência tipada + dogId (+ type opcional da entry).
  static HealthTimelineDetailResolution resolve({
    required String dogId,
    HealthTimelineDetailReference? reference,
    HealthTimelineTypeView? entryType,
  }) {
    final dog = dogId.trim();
    if (dog.isEmpty) {
      return const HealthTimelineDetailUnavailable(
        HealthTimelineDetailUnavailableReason.incompleteReference,
      );
    }
    if (reference == null) {
      return const HealthTimelineDetailUnavailable(
        HealthTimelineDetailUnavailableReason.missingReference,
      );
    }

    final sourceType = reference.sourceType.trim();
    final sourceId = reference.sourceId.trim();
    if (sourceType.isEmpty || sourceId.isEmpty) {
      return const HealthTimelineDetailUnavailable(
        HealthTimelineDetailUnavailableReason.invalidSourceId,
      );
    }

    // Allowlist explícita — nunca route dinâmica a partir de raw.
    if (!_allowlist.contains(sourceType)) {
      return const HealthTimelineDetailUnsupported();
    }

    // Conservador: type conhecido incompatível com source → unavailable.
    if (!_isCompatible(entryType, sourceType)) {
      return const HealthTimelineDetailUnavailable(
        HealthTimelineDetailUnavailableReason.typeSourceMismatch,
      );
    }

    return switch (sourceType) {
      sourceWeightRecords => HealthTimelineDetailResolved(
        WeightHistoryTarget(dogId: dog, sourceId: sourceId),
      ),
      sourceFeedingEvents || sourceFeedings => HealthTimelineDetailResolved(
        NutritionHistoryTarget(
          dogId: dog,
          sourceId: sourceId,
          sourceCollection: sourceType,
        ),
      ),
      sourceVacinas => HealthTimelineDetailResolved(
        VaccinationHistoryTarget(dogId: dog, sourceId: sourceId),
      ),
      _ => const HealthTimelineDetailUnsupported(),
    };
  }

  /// Conveniência a partir da entry de apresentação.
  static HealthTimelineDetailResolution resolveEntry(
    HealthTimelineEntryView entry,
  ) {
    return resolve(
      dogId: entry.dogId,
      reference: entry.detailReference,
      entryType: entry.type,
    );
  }

  /// Única fonte de verdade para affordance de toque.
  static bool isNavigable(HealthTimelineEntryView entry) {
    return resolveEntry(entry) is HealthTimelineDetailResolved;
  }

  static bool _isCompatible(HealthTimelineTypeView? type, String sourceType) {
    final known = type?.known;
    if (known == null) {
      // Unknown type: não bloqueia allowlist (dado legado); só source manda.
      return true;
    }
    return switch (sourceType) {
      sourceWeightRecords => known == HealthTimelineType.weight,
      sourceFeedingEvents || sourceFeedings => known == HealthTimelineType.meal,
      sourceVacinas => known == HealthTimelineType.vaccination,
      _ => false,
    };
  }
}
