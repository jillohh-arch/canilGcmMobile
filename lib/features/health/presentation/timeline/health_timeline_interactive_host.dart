import 'package:flutter/material.dart';

import 'package:canil_gcm/features/health/presentation/timeline/detail/health_timeline_detail_resolver.dart';
import 'package:canil_gcm/features/health/presentation/timeline/detail/health_timeline_detail_target.dart';
import 'package:canil_gcm/features/health/presentation/timeline/detail/health_timeline_navigation_coordinator.dart';
import 'package:canil_gcm/features/health/presentation/timeline/filters/health_timeline_filter_chips.dart';
import 'package:canil_gcm/features/health/presentation/timeline/filters/health_timeline_filter_session.dart';
import 'package:canil_gcm/features/health/presentation/timeline/filters/health_timeline_filter_sheet.dart';
import 'package:canil_gcm/features/health/presentation/timeline/health_timeline_controller.dart';
import 'package:canil_gcm/features/health/presentation/timeline/health_timeline_entry_view.dart';
import 'package:canil_gcm/features/health/presentation/timeline/widgets/health_timeline_user_copy.dart';
import 'package:canil_gcm/features/health/presentation/timeline/widgets/health_timeline_view.dart';

/// Host isolado 3D-E: Timeline + filtros + resolver + navegação injetável.
///
/// Sem MainRoot, sem Firestore, sem source 3C embutida.
class HealthTimelineInteractiveHost extends StatefulWidget {
  const HealthTimelineInteractiveHost({
    super.key,
    required this.controller,
    required this.filterSession,
    required this.onNavigate,
    this.contextLabel,
    this.now,
    this.bottomPadding = 24,
    this.onUnavailableMessage,
  });

  final HealthTimelineController controller;
  final HealthTimelineFilterSession filterSession;
  final Future<void> Function(HealthTimelineDetailTarget target) onNavigate;
  final String? contextLabel;
  final DateTime Function()? now;
  final double bottomPadding;
  final void Function(String message)? onUnavailableMessage;

  @override
  State<HealthTimelineInteractiveHost> createState() =>
      _HealthTimelineInteractiveHostState();
}

class _HealthTimelineInteractiveHostState
    extends State<HealthTimelineInteractiveHost> {
  late final HealthTimelineNavigationCoordinator _coordinator;

  @override
  void initState() {
    super.initState();
    _coordinator = HealthTimelineNavigationCoordinator(
      onNavigate: widget.onNavigate,
      onUnavailable: (msg) {
        final handler = widget.onUnavailableMessage;
        if (handler != null) {
          handler(msg);
          return;
        }
        if (!mounted) return;
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(msg)));
      },
    );
  }

  Future<void> _openFilters() async {
    await showHealthTimelineFilterSheet(
      context: context,
      session: widget.filterSession,
    );
  }

  void _onEntryTap(HealthTimelineEntryView entry) {
    if (!HealthTimelineDetailResolver.isNavigable(entry)) return;
    // ignore: discarded_futures
    _coordinator.onEntryTap(entry);
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([widget.controller, widget.filterSession]),
      builder: (context, _) {
        final session = widget.filterSession;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            HealthTimelineFilterChipsBar(session: session),
            Expanded(
              child: HealthTimelineView(
                controller: widget.controller,
                contextLabel: widget.contextLabel,
                now: widget.now,
                bottomPadding: widget.bottomPadding,
                onFilterRequested: _openFilters,
                activeFilterCount: session.activeFilterCount,
                hasActiveFilters: session.hasActiveFilters,
                onClearFilters: session.hasActiveFilters
                    ? () => session.clearApplied()
                    : null,
                onEntryTap: _onEntryTap,
                entryNavigable: HealthTimelineDetailResolver.isNavigable,
              ),
            ),
          ],
        );
      },
    );
  }
}

/// Copy extra 3D (clear filters).
abstract final class HealthTimeline3dUserCopy {
  HealthTimeline3dUserCopy._();

  static const clearFilters = 'Limpar filtros';
  static const emptyFilteredMessage =
      'Nenhum registro corresponde aos filtros aplicados.';
}

// Re-export convenience for harness tests.
String get healthTimelineClearFiltersLabel =>
    HealthTimeline3dUserCopy.clearFilters;
String get healthTimelineEmptyFilteredMessage =>
    HealthTimeline3dUserCopy.emptyFilteredMessage;
String get healthTimelineFilterAction => HealthTimelineUserCopy.filterAction;
