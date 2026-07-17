import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:canil_gcm/core/theme/app_theme.dart';
import 'package:canil_gcm/features/health/presentation/schedule/health_schedule_controller.dart';
import 'package:canil_gcm/features/health/presentation/schedule/health_schedule_grouping.dart';
import 'package:canil_gcm/features/health/presentation/schedule/health_schedule_item_view.dart';
import 'package:canil_gcm/features/health/presentation/schedule/health_schedule_state.dart';
import 'package:canil_gcm/features/health/presentation/schedule/health_schedule_ui_filter.dart';
import 'package:canil_gcm/features/health/presentation/schedule/widgets/health_schedule_filter_chips.dart';
import 'package:canil_gcm/features/health/presentation/schedule/widgets/health_schedule_item_card.dart';
import 'package:canil_gcm/features/health/presentation/schedule/widgets/health_schedule_kpi_row.dart';
import 'package:canil_gcm/features/health/presentation/schedule/widgets/health_schedule_status_views.dart';
import 'package:canil_gcm/features/health/presentation/schedule/widgets/health_schedule_user_copy.dart';
import 'package:canil_gcm/features/health/presentation/timeline/widgets/health_timeline_refresh_banner.dart';

/// Shell visual da Agenda Preventiva (Fase 4B).
///
/// Consome [HealthScheduleController] da 4A. Reavalia temporalmente itens
/// carregados no foreground e em tick periódico — sem nova leitura da source.
class HealthScheduleView extends StatefulWidget {
  final HealthScheduleController controller;
  final String dogDisplayName;
  final double bottomPadding;

  /// Intervalo de reavaliação temporal (null = desliga tick automático).
  final Duration recomputeInterval;

  /// Clock opcional só para labels de horário nos cards.
  final DateTime Function()? now;

  const HealthScheduleView({
    super.key,
    required this.controller,
    required this.dogDisplayName,
    this.bottomPadding = 24,
    this.recomputeInterval = const Duration(minutes: 1),
    this.now,
  });

  @override
  State<HealthScheduleView> createState() => _HealthScheduleViewState();
}

class _HealthScheduleViewState extends State<HealthScheduleView>
    with WidgetsBindingObserver {
  HealthScheduleUiFilter _filter = HealthScheduleUiFilter.all;
  Timer? _recomputeTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _startRecomputeTimer();
  }

  @override
  void didUpdateWidget(covariant HealthScheduleView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.recomputeInterval != widget.recomputeInterval) {
      _startRecomputeTimer();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _recomputeTimer?.cancel();
    _recomputeTimer = null;
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      widget.controller.recomputeTemporalStates();
    }
  }

  void _startRecomputeTimer() {
    _recomputeTimer?.cancel();
    _recomputeTimer = null;
    if (widget.recomputeInterval <= Duration.zero) return;
    _recomputeTimer = Timer.periodic(widget.recomputeInterval, (_) {
      if (!mounted) return;
      widget.controller.recomputeTemporalStates();
    });
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.controller,
      builder: (context, _) {
        return _ScheduleBody(
          state: widget.controller.state,
          dogDisplayName: widget.dogDisplayName,
          bottomPadding: widget.bottomPadding,
          filter: _filter,
          onFilterChanged: (f) => setState(() => _filter = f),
          onRefresh: _canRefresh(widget.controller.state)
              ? widget.controller.refresh
              : null,
          now: widget.now,
        );
      },
    );
  }

  static bool _canRefresh(HealthScheduleState state) {
    return state is! HealthScheduleInitial;
  }
}

class _ScheduleBody extends StatelessWidget {
  final HealthScheduleState state;
  final String dogDisplayName;
  final double bottomPadding;
  final HealthScheduleUiFilter filter;
  final ValueChanged<HealthScheduleUiFilter> onFilterChanged;
  final Future<void> Function()? onRefresh;
  final DateTime Function()? now;

  const _ScheduleBody({
    required this.state,
    required this.dogDisplayName,
    required this.bottomPadding,
    required this.filter,
    required this.onFilterChanged,
    required this.onRefresh,
    required this.now,
  });

  @override
  Widget build(BuildContext context) {
    final header = _AgendaHeader(dogDisplayName: dogDisplayName);
    final chips = HealthScheduleFilterChips(
      selected: filter,
      onSelected: onFilterChanged,
    );

    return switch (state) {
      HealthScheduleInitial() => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          header,
          const SizedBox(height: 12),
          chips,
          const Expanded(
            child: HealthScheduleSurfaceMessage(
              key: ValueKey('schedule-initial'),
              icon: Icons.event_available_rounded,
              title: 'Agenda preventiva',
              message: 'Selecione um K9 para ver os cuidados programados.',
            ),
          ),
        ],
      ),
      HealthScheduleLoading() => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          header,
          const SizedBox(height: 12),
          chips,
          const Expanded(child: HealthScheduleLoadingView()),
        ],
      ),
      HealthScheduleEmpty(:final isRefreshing) => _scrollable(
        header: header,
        chips: chips,
        child: Column(
          children: [
            if (isRefreshing)
              const Padding(
                padding: EdgeInsets.only(bottom: 8),
                child: LinearProgressIndicator(minHeight: 2),
              ),
            const Expanded(
              child: HealthScheduleSurfaceMessage(
                key: ValueKey('schedule-empty'),
                icon: Icons.event_note_rounded,
                title: HealthScheduleUserCopy.emptyTitle,
                message: HealthScheduleUserCopy.emptyMessage,
              ),
            ),
          ],
        ),
      ),
      HealthScheduleError(:final message) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          header,
          const SizedBox(height: 12),
          chips,
          Expanded(
            child: HealthScheduleSurfaceMessage(
              key: const ValueKey('schedule-error'),
              icon: Icons.error_outline_rounded,
              iconColor: AppTheme.error,
              title: HealthScheduleUserCopy.errorTitle,
              message: message,
              actionLabel: onRefresh != null
                  ? HealthScheduleUserCopy.retryLabel
                  : null,
              onAction: onRefresh == null
                  ? null
                  : () {
                      // ignore: discarded_futures
                      onRefresh!();
                    },
            ),
          ),
        ],
      ),
      HealthScheduleOffline(:final lastKnown) =>
        lastKnown != null
            ? _dataBody(
                header: header,
                chips: chips,
                snapshot: lastKnown,
                offlineBanner: true,
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  header,
                  const SizedBox(height: 12),
                  chips,
                  Expanded(
                    child: HealthScheduleSurfaceMessage(
                      key: const ValueKey('schedule-offline'),
                      icon: Icons.cloud_off_rounded,
                      iconColor: AppTheme.warning,
                      title: HealthScheduleUserCopy.offlineTitle,
                      message: HealthScheduleUserCopy.offlineMessage,
                      actionLabel: onRefresh != null
                          ? HealthScheduleUserCopy.retryLabel
                          : null,
                      onAction: onRefresh == null
                          ? null
                          : () {
                              // ignore: discarded_futures
                              onRefresh!();
                            },
                    ),
                  ),
                ],
              ),
      HealthScheduleData(:final snapshot) => _dataBody(
        header: header,
        chips: chips,
        snapshot: snapshot,
        offlineBanner: false,
      ),
    };
  }

  Widget _scrollable({
    required Widget header,
    required Widget chips,
    required Widget child,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        header,
        const SizedBox(height: 12),
        chips,
        Expanded(child: child),
      ],
    );
  }

  Widget _dataBody({
    required Widget header,
    required Widget chips,
    required HealthScheduleSnapshot snapshot,
    required bool offlineBanner,
  }) {
    final clock = now?.call() ?? DateTime.now().toUtc();
    final filtered = filterScheduleItems(snapshot.items, filter, now: clock);
    final groups = groupScheduleItems(filtered);
    final kpiGroups = groupScheduleItems(snapshot.items);

    final sections = <Widget>[
      if (snapshot.isRefreshing)
        const Padding(
          padding: EdgeInsets.only(bottom: 8),
          child: LinearProgressIndicator(minHeight: 2),
        ),
      if (snapshot.hasRefreshFailure)
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: HealthTimelineRefreshBanner(
            message:
                '${HealthScheduleUserCopy.refreshFailedPrefix}: ${snapshot.lastRefreshError}',
            offline: snapshot.lastRefreshWasOffline,
            onRetry: onRefresh == null
                ? null
                : () {
                    // ignore: discarded_futures
                    onRefresh!();
                  },
          ),
        ),
      if (offlineBanner)
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: HealthTimelineRefreshBanner(
            message: HealthScheduleUserCopy.offlineMessage,
            offline: true,
            onRetry: onRefresh == null
                ? null
                : () {
                    // ignore: discarded_futures
                    onRefresh!();
                  },
          ),
        ),
      HealthScheduleKpiRow(groups: kpiGroups),
      const SizedBox(height: 16),
      ..._buildSections(groups),
      if (filtered.isEmpty)
        Padding(
          padding: const EdgeInsets.only(top: 24),
          child: Text(
            filter == HealthScheduleUiFilter.all
                ? HealthScheduleUserCopy.emptyMessage
                : 'Nenhum item neste filtro.',
            textAlign: TextAlign.center,
            style: GoogleFonts.inter(
              color: AppTheme.textSecondary,
              fontSize: 13.5,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
    ];

    final list = ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: EdgeInsets.only(bottom: bottomPadding),
      children: sections,
    );

    final body = onRefresh == null
        ? list
        : RefreshIndicator(
            color: AppTheme.primary,
            backgroundColor: AppTheme.surfacePanel,
            onRefresh: onRefresh!,
            child: list,
          );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        header,
        const SizedBox(height: 14),
        chips,
        const SizedBox(height: 14),
        Expanded(child: body),
      ],
    );
  }

  List<Widget> _buildSections(HealthScheduleGroups groups) {
    final blocks =
        <({String title, Color color, List<HealthScheduleItemView> items})>[
          (
            title: HealthScheduleUserCopy.sectionAttention,
            color: AppTheme.error,
            items: groups.overdue,
          ),
          (
            title: HealthScheduleUserCopy.sectionPending,
            color: AppTheme.warning,
            items: groups.pending,
          ),
          (
            title: HealthScheduleUserCopy.sectionToday,
            color: AppTheme.primary,
            items: groups.today,
          ),
          (
            title: HealthScheduleUserCopy.sectionUpcoming,
            color: AppTheme.success,
            items: groups.upcoming,
          ),
          (
            title: HealthScheduleUserCopy.sectionScheduled,
            color: AppTheme.primary,
            items: groups.scheduled,
          ),
        ];

    final widgets = <Widget>[];
    for (final block in blocks) {
      if (block.items.isEmpty) continue;
      widgets.add(
        _SectionHeader(
          title: block.title,
          color: block.color,
          count: block.items.length,
        ),
      );
      for (var i = 0; i < block.items.length; i++) {
        if (i > 0) widgets.add(const SizedBox(height: 8));
        widgets.add(HealthScheduleItemCard(item: block.items[i], now: now));
      }
      widgets.add(const SizedBox(height: 16));
    }
    return widgets;
  }
}

class _AgendaHeader extends StatelessWidget {
  final String dogDisplayName;

  const _AgendaHeader({required this.dogDisplayName});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          HealthScheduleUserCopy.title,
          style: GoogleFonts.inter(
            color: AppTheme.textPrimary,
            fontSize: 15,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.9,
            height: 1.2,
          ),
        ),
        const SizedBox(height: 3),
        Text(
          HealthScheduleUserCopy.subtitle(dogDisplayName),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: GoogleFonts.inter(
            color: AppTheme.textSecondary,
            fontSize: 13,
            fontWeight: FontWeight.w500,
            height: 1.3,
          ),
        ),
      ],
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  final Color color;
  final int count;

  const _SectionHeader({
    required this.title,
    required this.color,
    required this.count,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              title,
              style: GoogleFonts.inter(
                color: color,
                fontSize: 12,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.8,
              ),
            ),
          ),
          Text(
            '$count',
            style: GoogleFonts.inter(
              color: AppTheme.textTertiary,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}
