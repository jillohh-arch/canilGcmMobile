import 'package:flutter/foundation.dart';

import 'package:canil_gcm/features/health/domain/health_restriction_history_reader.dart';
import 'package:canil_gcm/features/health/domain/health_v1_enums_ext.dart';
import 'package:canil_gcm/features/health/domain/operational_restriction.dart';
import 'package:canil_gcm/features/health/presentation/timeline/health_history_item.dart';
import 'package:canil_gcm/features/health/presentation/timeline/health_timeline_entry_view.dart';
import 'package:canil_gcm/features/health/presentation/timeline/health_timeline_grouping.dart';
import 'package:canil_gcm/features/health/presentation/timeline/health_timeline_page.dart';
import 'package:canil_gcm/features/health/presentation/timeline/health_timeline_query.dart';
import 'package:canil_gcm/features/health/presentation/timeline/health_timeline_source.dart';

/// Source de apresentação que compõe o histórico clínico do cão
/// combinando as entradas canônicas da timeline com os eventos
/// de ciclo de vida de restrições operacionais.
///
/// Invariantes:
/// - Escopo estrito por [dogId]: Dog A nunca recebe restrições de Dog B;
/// - Derivação somente de campos persistidos autoritativos;
/// - Deduplicação por (restrictionId + fase);
/// - Ordenação cronológica determinística (`occurredAt DESC`, desempate `id ASC`);
/// - Respeito aos filtros de período (ex.: 7 dias) e tipos;
/// - Degradação graciosa: falha na leitura de restrições preserva a timeline canônica;
/// - Zero synthetic ClinicalEvents criados ou esperados.
class HealthHistoryPresentationTimelineSource implements HealthTimelineSource {
  HealthHistoryPresentationTimelineSource({
    required HealthTimelineSource primarySource,
    required HealthRestrictionHistoryReader restrictionReader,
  }) : _primarySource = primarySource,
       _restrictionReader = restrictionReader;

  final HealthTimelineSource _primarySource;
  final HealthRestrictionHistoryReader _restrictionReader;

  @override
  Future<HealthTimelinePage> loadPage(HealthTimelineQuery query) async {
    // 1. Carrega página da timeline primária (canônica / coexistência)
    final primaryPage = await _primarySource.loadPage(query);

    // Se o filtro de tipos for restrito e NÃO incluir restrição, retorna imediatamente
    if (query.types.isNotEmpty &&
        !query.types.contains(HealthTimelineType.restriction)) {
      return primaryPage;
    }

    // 2. Consulta restrições operacionais do cão com degradação graciosa
    List<OperationalRestriction> restrictions;
    try {
      restrictions = await _restrictionReader.getRestrictionsForDog(query.dogId);
    } catch (e) {
      debugPrint(
        '[HealthHistoryPresentationTimelineSource] erro ao carregar restrições para ${query.dogId}: $e. '
        'Mantendo timeline primária sem interrupção.',
      );
      return primaryPage;
    }

    if (restrictions.isEmpty) {
      return primaryPage;
    }

    // 3. Derivação e filtragem dos eventos de ciclo de vida
    final seenKeys = <String>{};
    final restrictionEntries = <HealthTimelineEntryView>[];

    for (final restriction in restrictions) {
      // Isolamento estrito de cão
      if (restriction.dogId.trim() != query.dogId.trim()) {
        continue;
      }

      final lifecycleItems = HealthRestrictionLifecycleDeriver.derive(
        restriction,
      );
      for (final item in lifecycleItems) {
        // Proteção contra duplicação: restrictionId + phase
        final dedupeKey = '${item.restrictionId}#${item.phase.name}';
        if (!seenKeys.add(dedupeKey)) {
          continue;
        }

        // Filtro de período (inclusivo)
        if (!_matchesPeriod(item.occurredAt, query.period)) {
          continue;
        }

        restrictionEntries.add(item.toEntryView());
      }
    }

    if (restrictionEntries.isEmpty) {
      return primaryPage;
    }

    // 4. Mesclagem cronológica determinística com primaryPage.items
    final merged = mergeTimelineEntries(
      existing: primaryPage.items,
      incoming: restrictionEntries,
    );

    return HealthTimelinePage(
      items: merged,
      nextCursor: primaryPage.nextCursor,
      hasMore: primaryPage.hasMore,
    );
  }

  static bool _matchesPeriod(DateTime occurredAt, HealthTimelinePeriod period) {
    if (period.start != null && occurredAt.isBefore(period.start!)) {
      return false;
    }
    if (period.end != null && occurredAt.isAfter(period.end!)) {
      return false;
    }
    return true;
  }
}
