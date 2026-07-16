import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:canil_gcm/core/theme/app_theme.dart';
import 'package:canil_gcm/features/health/presentation/timeline/health_timeline_controller.dart';
import 'package:canil_gcm/features/health/presentation/timeline/health_timeline_entry_view.dart';
import 'package:canil_gcm/features/health/presentation/timeline/health_timeline_grouping.dart';
import 'package:canil_gcm/features/health/presentation/timeline/health_timeline_query.dart';
import 'package:canil_gcm/features/health/presentation/timeline/health_timeline_state.dart';
import 'package:canil_gcm/features/health/presentation/timeline/widgets/health_timeline_day_section.dart';
import 'package:canil_gcm/features/health/presentation/timeline/widgets/health_timeline_formatters.dart';
import 'package:canil_gcm/features/health/presentation/timeline/widgets/health_timeline_load_more.dart';
import 'package:canil_gcm/features/health/presentation/timeline/widgets/health_timeline_refresh_banner.dart';
import 'package:canil_gcm/features/health/presentation/timeline/widgets/health_timeline_status_views.dart';
import 'package:canil_gcm/features/health/presentation/timeline/widgets/health_timeline_user_copy.dart';

/// View principal da Timeline do Histórico Clínico (Fase 3B).
///
/// Consome [HealthTimelineController] / [HealthTimelineState] da 3A.
/// Não busca dados, não monta query Firestore, não decide regras clínicas.
///
/// Isolada: não conecta shell / aba Histórico / navegação de detalhe.
class HealthTimelineView extends StatelessWidget {
  final HealthTimelineController controller;

  /// Callback opcional de toque no card (não resolve rota).
  final ValueChanged<HealthTimelineEntryView>? onEntryTap;

  /// Se informado, chevron/tap só para entries em que retorna true (3D).
  final bool Function(HealthTimelineEntryView entry)? entryNavigable;

  /// Ação visual de filtros (lógica completa em 3D).
  final VoidCallback? onFilterRequested;

  /// Limpar filtros aplicados (empty filtrado / 3D).
  final VoidCallback? onClearFilters;

  /// Contagem visual de filtros ativos (opcional; sobrescreve derivação da query).
  final int? activeFilterCount;

  /// Alternativa booleana a [activeFilterCount].
  final bool? hasActiveFilters;

  /// Rótulo de contexto do K9 (apenas apresentação; sem fetch de Dog).
  final String? contextLabel;

  /// "Agora" injetável para labels HOJE/ONTEM estáveis em testes.
  final DateTime Function()? now;

  /// Padding inferior extra (ex.: safe area / bottom nav do host).
  final double bottomPadding;

  const HealthTimelineView({
    super.key,
    required this.controller,
    this.onEntryTap,
    this.entryNavigable,
    this.onFilterRequested,
    this.onClearFilters,
    this.activeFilterCount,
    this.hasActiveFilters,
    this.contextLabel,
    this.now,
    this.bottomPadding = 24,
  });

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        return _TimelineBody(
          state: controller.state,
          onRefresh: _canRefresh(controller.state) ? controller.refresh : null,
          onLoadMore: controller.loadMore,
          onEntryTap: onEntryTap,
          entryNavigable: entryNavigable,
          onFilterRequested: onFilterRequested,
          onClearFilters: onClearFilters,
          activeFilterCount: activeFilterCount,
          hasActiveFilters: hasActiveFilters,
          contextLabel: contextLabel,
          now: now,
          bottomPadding: bottomPadding,
        );
      },
    );
  }

  static bool _canRefresh(HealthTimelineState state) {
    return state is! HealthTimelineInitial;
  }
}

class _TimelineBody extends StatelessWidget {
  final HealthTimelineState state;
  final Future<void> Function()? onRefresh;
  final Future<void> Function() onLoadMore;
  final ValueChanged<HealthTimelineEntryView>? onEntryTap;
  final bool Function(HealthTimelineEntryView entry)? entryNavigable;
  final VoidCallback? onFilterRequested;
  final VoidCallback? onClearFilters;
  final int? activeFilterCount;
  final bool? hasActiveFilters;
  final String? contextLabel;
  final DateTime Function()? now;
  final double bottomPadding;

  const _TimelineBody({
    required this.state,
    required this.onRefresh,
    required this.onLoadMore,
    required this.onEntryTap,
    required this.entryNavigable,
    required this.onFilterRequested,
    required this.onClearFilters,
    required this.activeFilterCount,
    required this.hasActiveFilters,
    required this.contextLabel,
    required this.now,
    required this.bottomPadding,
  });

  @override
  Widget build(BuildContext context) {
    final filtersActive = _resolveHasActiveFilters();
    final filterCount = _resolveFilterCount();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _TimelineHeader(
          contextLabel: contextLabel,
          onFilterRequested: onFilterRequested,
          activeFilterCount: filterCount,
          hasActiveFilters: filtersActive,
        ),
        Expanded(child: _body(filtersActive: filtersActive)),
      ],
    );
  }

  Widget _body({required bool filtersActive}) {
    return switch (state) {
      HealthTimelineInitial() => const HealthTimelineSurfaceMessage(
        key: ValueKey('timeline-initial'),
        icon: Icons.timeline_outlined,
        title: HealthTimelineUserCopy.initialTitle,
        message: HealthTimelineUserCopy.initialMessage,
      ),
      HealthTimelineLoading() => const HealthTimelineLoadingView(
        key: ValueKey('timeline-loading'),
      ),
      HealthTimelineEmpty(:final isRefreshing) => _EmptyShell(
        key: const ValueKey('timeline-empty'),
        hasActiveFilters: filtersActive,
        isRefreshing: isRefreshing,
        onRefresh: onRefresh,
        onFilterRequested: onFilterRequested,
        onClearFilters: onClearFilters,
      ),
      // lastKnown em Error/Offline: controller 3A preserva via Data na prática;
      // se lastKnown vier preenchido (mesma identidade), respeitar a semântica.
      HealthTimelineError(:final message, :final lastKnown) =>
        lastKnown != null && lastKnown.items.isNotEmpty
            ? _DataList(
                key: const ValueKey('timeline-error-with-data'),
                snapshot: lastKnown.copyWith(
                  lastRefreshError: HealthTimelineUserCopy.sanitizeMessage(
                    message,
                    fallback: HealthTimelineUserCopy.errorMessage,
                  ),
                  lastRefreshWasOffline: false,
                ),
                onRefresh: onRefresh,
                onLoadMore: onLoadMore,
                onEntryTap: onEntryTap,
                entryNavigable: entryNavigable,
                now: now,
                bottomPadding: bottomPadding,
              )
            : HealthTimelineErrorStateView(
                key: const ValueKey('timeline-error'),
                message: HealthTimelineUserCopy.sanitizeMessage(
                  message,
                  fallback: HealthTimelineUserCopy.errorMessage,
                ),
                onRetry: onRefresh == null ? null : () => onRefresh!(),
              ),
      HealthTimelineOffline(:final lastKnown) =>
        lastKnown != null && lastKnown.items.isNotEmpty
            ? _DataList(
                key: const ValueKey('timeline-offline-with-data'),
                snapshot: lastKnown.copyWith(
                  lastRefreshError: HealthTimelineUserCopy.refreshOffline,
                  lastRefreshWasOffline: true,
                ),
                onRefresh: onRefresh,
                onLoadMore: onLoadMore,
                onEntryTap: onEntryTap,
                entryNavigable: entryNavigable,
                now: now,
                bottomPadding: bottomPadding,
              )
            : HealthTimelineOfflineStateView(
                key: const ValueKey('timeline-offline'),
                onRetry: onRefresh == null ? null : () => onRefresh!(),
              ),
      HealthTimelineData(:final snapshot) => _DataList(
        key: const ValueKey('timeline-data'),
        snapshot: snapshot,
        onRefresh: onRefresh,
        onLoadMore: onLoadMore,
        onEntryTap: onEntryTap,
        entryNavigable: entryNavigable,
        now: now,
        bottomPadding: bottomPadding,
      ),
    };
  }

  bool _resolveHasActiveFilters() {
    if (hasActiveFilters != null) return hasActiveFilters!;
    final count = activeFilterCount;
    if (count != null) return count > 0;
    return _queryHasStructuralFilters(_queryOf(state));
  }

  int _resolveFilterCount() {
    if (activeFilterCount != null) {
      return HealthTimelineFormatters.normalizeFilterCount(activeFilterCount);
    }
    final q = _queryOf(state);
    if (q == null) return 0;
    var n = 0;
    if (q.types.isNotEmpty) n++;
    if (!q.period.isUnbounded) n++;
    if (q.caseId != null) n++;
    if (q.professional != null) n++;
    return n;
  }

  static HealthTimelineQuery? _queryOf(HealthTimelineState state) {
    return switch (state) {
      HealthTimelineLoading(:final query) => query,
      HealthTimelineData(:final snapshot) => snapshot.query,
      HealthTimelineEmpty(:final query) => query,
      HealthTimelineError(:final query) => query,
      HealthTimelineOffline(:final query) => query,
      HealthTimelineInitial() => null,
    };
  }

  static bool _queryHasStructuralFilters(HealthTimelineQuery? query) {
    if (query == null) return false;
    return query.types.isNotEmpty ||
        !query.period.isUnbounded ||
        query.caseId != null ||
        query.professional != null;
  }
}

class _TimelineHeader extends StatelessWidget {
  final String? contextLabel;
  final VoidCallback? onFilterRequested;
  final int activeFilterCount;
  final bool hasActiveFilters;

  const _TimelineHeader({
    required this.contextLabel,
    required this.onFilterRequested,
    required this.activeFilterCount,
    required this.hasActiveFilters,
  });

  @override
  Widget build(BuildContext context) {
    final subtitle = contextLabel == null || contextLabel!.trim().isEmpty
        ? HealthTimelineUserCopy.subtitleDefault
        : 'Linha do tempo da saúde de ${contextLabel!.trim()}';

    final filterSemantics = !hasActiveFilters
        ? HealthTimelineUserCopy.filterAction
        : activeFilterCount > 0
        ? '${HealthTimelineUserCopy.filterAction}, $activeFilterCount ativos'
        : '${HealthTimelineUserCopy.filterAction} ativos';

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 12, 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  HealthTimelineUserCopy.title,
                  style: GoogleFonts.inter(
                    color: AppTheme.textPrimary,
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.4,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: GoogleFonts.inter(
                    color: AppTheme.textSoft,
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
          if (onFilterRequested != null)
            Semantics(
              button: true,
              label: filterSemantics,
              excludeSemantics: true,
              child: Material(
                color: AppTheme.transparent,
                child: InkWell(
                  onTap: onFilterRequested,
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: hasActiveFilters
                            ? AppTheme.primary.withValues(alpha: 0.55)
                            : AppTheme.primary.withValues(alpha: 0.35),
                      ),
                      color: hasActiveFilters
                          ? AppTheme.primary.withValues(alpha: 0.10)
                          : AppTheme.transparent,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.filter_list_rounded,
                          size: 18,
                          color: AppTheme.primary,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          HealthTimelineUserCopy.filterAction,
                          style: GoogleFonts.inter(
                            color: AppTheme.primary,
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        if (hasActiveFilters && activeFilterCount > 0) ...[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: AppTheme.primary.withValues(alpha: 0.18),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              '$activeFilterCount',
                              style: GoogleFonts.inter(
                                color: AppTheme.primary,
                                fontSize: 11,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _EmptyShell extends StatelessWidget {
  final bool hasActiveFilters;
  final bool isRefreshing;
  final Future<void> Function()? onRefresh;
  final VoidCallback? onFilterRequested;
  final VoidCallback? onClearFilters;

  const _EmptyShell({
    super.key,
    required this.hasActiveFilters,
    required this.isRefreshing,
    required this.onRefresh,
    required this.onFilterRequested,
    required this.onClearFilters,
  });

  @override
  Widget build(BuildContext context) {
    final body = HealthTimelineEmptyView(
      hasActiveFilters: hasActiveFilters,
      onFilterRequested: onFilterRequested,
      onClearFilters: onClearFilters,
    );

    if (onRefresh == null) return body;

    return RefreshIndicator(
      color: AppTheme.primary,
      backgroundColor: AppTheme.surfacePanel,
      onRefresh: onRefresh!,
      child: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          if (isRefreshing)
            const SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.only(top: 8),
                child: LinearProgressIndicator(
                  minHeight: 2,
                  color: AppTheme.primary,
                  backgroundColor: AppTheme.primaryOverlay,
                ),
              ),
            ),
          SliverFillRemaining(hasScrollBody: false, child: body),
        ],
      ),
    );
  }
}

/// Slot flat para [ListView.builder] (lazy).
sealed class _TimelineSlot {
  const _TimelineSlot();
}

final class _ProgressSlot extends _TimelineSlot {
  const _ProgressSlot();
}

final class _BannerSlot extends _TimelineSlot {
  const _BannerSlot({required this.offline, required this.message});
  final bool offline;
  final String message;
}

final class _DayHeaderSlot extends _TimelineSlot {
  const _DayHeaderSlot({required this.date});
  final DateTime date;
}

final class _EntrySlot extends _TimelineSlot {
  const _EntrySlot({
    required this.entry,
    required this.isFirst,
    required this.isLast,
  });
  final HealthTimelineEntryView entry;
  final bool isFirst;
  final bool isLast;
}

final class _DayGapSlot extends _TimelineSlot {
  const _DayGapSlot();
}

final class _LoadMoreSlot extends _TimelineSlot {
  const _LoadMoreSlot();
}

class _DataList extends StatelessWidget {
  final HealthTimelineSnapshot snapshot;
  final Future<void> Function()? onRefresh;
  final Future<void> Function() onLoadMore;
  final ValueChanged<HealthTimelineEntryView>? onEntryTap;
  final bool Function(HealthTimelineEntryView entry)? entryNavigable;
  final DateTime Function()? now;
  final double bottomPadding;

  const _DataList({
    super.key,
    required this.snapshot,
    required this.onRefresh,
    required this.onLoadMore,
    required this.onEntryTap,
    required this.entryNavigable,
    required this.now,
    required this.bottomPadding,
  });

  ValueChanged<HealthTimelineEntryView>? _tapFor(
    HealthTimelineEntryView entry,
  ) {
    final handler = onEntryTap;
    if (handler == null) return null;
    final gate = entryNavigable;
    if (gate != null && !gate(entry)) return null;
    return handler;
  }

  @override
  Widget build(BuildContext context) {
    final referenceNow = now?.call();
    final groups = groupTimelineByDay(snapshot.items);
    final slots = _buildSlots(groups);
    // Durante refresh: controller 3A limpa lastRefreshError e loadMoreError.
    // UI reforça prioridade visual — sem botão load more ativo.
    final refreshing = snapshot.isRefreshing;

    final list = ListView.builder(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: EdgeInsets.fromLTRB(16, 8, 16, bottomPadding),
      itemCount: slots.length,
      itemBuilder: (context, index) {
        final slot = slots[index];
        return switch (slot) {
          _ProgressSlot() => const Padding(
            padding: EdgeInsets.only(bottom: 8),
            child: LinearProgressIndicator(
              minHeight: 2,
              color: AppTheme.primary,
              backgroundColor: AppTheme.primaryOverlay,
            ),
          ),
          _BannerSlot(:final offline, :final message) => Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: HealthTimelineRefreshBanner(
              offline: offline,
              message: message,
              onRetry: onRefresh == null ? null : () => onRefresh!(),
            ),
          ),
          _DayHeaderSlot(:final date) => HealthTimelineDayHeader(
            date: date,
            now: referenceNow,
          ),
          _EntrySlot(:final entry, :final isFirst, :final isLast) => Padding(
            padding: EdgeInsets.only(bottom: isLast ? 0 : 10),
            child: HealthTimelineEntryRow(
              entry: entry,
              isFirst: isFirst,
              isLast: isLast,
              onEntryTap: _tapFor(entry),
            ),
          ),
          _DayGapSlot() => const SizedBox(height: 18),
          _LoadMoreSlot() => HealthTimelineLoadMore(
            hasMore: snapshot.hasMore && !refreshing,
            isLoadingMore: snapshot.isLoadingMore && !refreshing,
            loadMoreError: refreshing ? null : snapshot.loadMoreError,
            onLoadMore: refreshing
                ? null
                : (snapshot.hasMore || snapshot.loadMoreError != null)
                ? () => onLoadMore()
                : null,
          ),
        };
      },
    );

    if (onRefresh == null) return list;

    return RefreshIndicator(
      color: AppTheme.primary,
      backgroundColor: AppTheme.surfacePanel,
      onRefresh: onRefresh!,
      child: list,
    );
  }

  List<_TimelineSlot> _buildSlots(List<HealthTimelineDayGroup> groups) {
    final refreshing = snapshot.isRefreshing;
    // Banner de falha some enquanto nova tentativa (isRefreshing) está em curso.
    final showBanner =
        snapshot.hasRefreshFailure &&
        !refreshing &&
        snapshot.lastRefreshError != null;

    final slots = <_TimelineSlot>[];
    if (refreshing) {
      slots.add(const _ProgressSlot());
    }
    if (showBanner) {
      slots.add(
        _BannerSlot(
          offline: snapshot.lastRefreshWasOffline,
          message: snapshot.lastRefreshWasOffline
              ? HealthTimelineUserCopy.refreshOffline
              : HealthTimelineUserCopy.refreshError,
        ),
      );
    }
    for (var g = 0; g < groups.length; g++) {
      if (g > 0) slots.add(const _DayGapSlot());
      final group = groups[g];
      slots.add(_DayHeaderSlot(date: group.date));
      final entries = group.entries;
      for (var i = 0; i < entries.length; i++) {
        slots.add(
          _EntrySlot(
            entry: entries[i],
            isFirst: i == 0,
            isLast: i == entries.length - 1,
          ),
        );
      }
    }
    slots.add(const _LoadMoreSlot());
    return slots;
  }
}
