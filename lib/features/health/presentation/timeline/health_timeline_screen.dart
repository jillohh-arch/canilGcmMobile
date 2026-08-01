import 'package:flutter/material.dart';

import 'package:canil_gcm/core/widgets/app_feedback.dart';
import 'package:canil_gcm/features/health/presentation/timeline/detail/health_timeline_detail_resolution.dart';
import 'package:canil_gcm/features/health/presentation/timeline/detail/health_timeline_detail_resolver.dart';
import 'package:canil_gcm/features/health/presentation/timeline/detail/health_timeline_detail_target.dart';
import 'package:canil_gcm/features/health/presentation/timeline/detail/health_timeline_navigation_coordinator.dart';
import 'package:canil_gcm/features/health/presentation/timeline/filters/health_timeline_filter_chips.dart';
import 'package:canil_gcm/features/health/presentation/timeline/filters/health_timeline_filter_session.dart';
import 'package:canil_gcm/features/health/presentation/timeline/filters/health_timeline_filter_sheet.dart';
import 'package:canil_gcm/features/health/presentation/timeline/filters/health_timeline_quick_type_chips.dart';
import 'package:canil_gcm/features/health/presentation/timeline/health_timeline_controller.dart';
import 'package:canil_gcm/features/health/presentation/timeline/health_timeline_entry_view.dart';
import 'package:canil_gcm/features/health/presentation/timeline/health_timeline_state.dart';
import 'package:canil_gcm/features/health/presentation/timeline/widgets/health_timeline_view.dart';

/// Composição real da aba **Histórico** (3E-A / 3E-E).
///
/// ## Ownership
/// Recebe [controller] e [filterSession] **injetados** (não cria em [build]).
/// Quem instancia deve [dispose] do controller/session no lifecycle apropriado
/// (3E-B).
///
/// ## Hierarquia visual (3E-E)
/// 1. título + Filtros (onde estou);
/// 2. quick type chips (como filtro rápido);
/// 3. chips de filtros applied;
/// 4. lista da timeline.
class HealthTimelineScreen extends StatefulWidget {
  const HealthTimelineScreen({
    super.key,
    required this.controller,
    required this.filterSession,
    required this.onNavigate,
    this.dogDisplayName,
    this.now,
    this.bottomPadding = 24,
    this.onUnavailableMessage,
  });

  final HealthTimelineController controller;
  final HealthTimelineFilterSession filterSession;
  final Future<void> Function(HealthTimelineDetailTarget target) onNavigate;
  final String? dogDisplayName;
  final DateTime Function()? now;
  final double bottomPadding;
  final void Function(String message)? onUnavailableMessage;

  @override
  State<HealthTimelineScreen> createState() => _HealthTimelineScreenState();
}

class _HealthTimelineScreenState extends State<HealthTimelineScreen> {
  late final HealthTimelineNavigationCoordinator _coordinator;

  @override
  void initState() {
    super.initState();
    // Callbacks do coordinator são **métodos de State** (não capturam
    // widget.onNavigate no init). Assim rebuilds do Entry nunca deixam
    // o coordinator com closure stale (3E-D2).
    _coordinator = HealthTimelineNavigationCoordinator(
      onNavigate: _forwardNavigate,
      onUnavailable: _forwardUnavailable,
      onNavigateError: _forwardNavigateError,
    );
  }

  Future<void> _forwardNavigate(HealthTimelineDetailTarget target) async {
    await widget.onNavigate(target);
  }

  void _forwardUnavailable(String message) {
    final handler = widget.onUnavailableMessage;
    if (handler != null) {
      handler(message);
      return;
    }
    if (!mounted) return;
    AppFeedback.info(context, message);
  }

  void _forwardNavigateError(Object error, StackTrace stackTrace) {
    debugPrint('[HealthTimeline] navigate error: $error');
    debugPrintStack(stackTrace: stackTrace);
    if (!mounted) return;
    AppFeedback.error(
      context,
      error,
      fallback: 'Não foi possível abrir o histórico relacionado.',
    );
  }

  void _onEntryTap(HealthTimelineEntryView entry) {
    if (!HealthTimelineDetailResolver.isNavigable(entry)) return;
    // ignore: discarded_futures
    _coordinator.onEntryTap(entry);
  }

  Future<void> _openFilters() async {
    await showHealthTimelineFilterSheet(
      context: context,
      session: widget.filterSession,
    );
  }

  String? _navigationLabel(HealthTimelineEntryView entry) {
    final r = HealthTimelineDetailResolver.resolveEntry(entry);
    if (r is! HealthTimelineDetailResolved) return null;
    return r.target.navigationActionLabel;
  }

  /// Bloco institucional somente após fim da paginação, com itens carregados.
  static bool _shouldShowInstitutionalFooter(HealthTimelineState state) {
    return switch (state) {
      HealthTimelineData(:final snapshot) =>
        !snapshot.hasMore && snapshot.items.isNotEmpty,
      _ => false,
    };
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([widget.controller, widget.filterSession]),
      builder: (context, _) {
        final session = widget.filterSession;
        final showFooter = _shouldShowInstitutionalFooter(
          widget.controller.state,
        );
        // SizedBox.expand: no slot do HealthShell (IndexedStack), o Column
        // precisa ocupar a altura máxima para o Expanded interno da lista
        // receber viewport real — sem isso a lista colapsa.
        return SizedBox.expand(
          child: HealthTimelineView(
            controller: widget.controller,
            contextLabel: widget.dogDisplayName,
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
            entryNavigationLabel: _navigationLabel,
            showInstitutionalFooter: showFooter,
            // 3E-E: quick filters e chips active **abaixo** do título.
            belowHeader: Column(
              key: const ValueKey('health-timeline-filter-controls'),
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 2, bottom: 6),
                  child: HealthTimelineQuickTypeChips(
                    key: const ValueKey('health-timeline-quick-filters'),
                    session: session,
                  ),
                ),
                // Single-type já suprimido em FilterLabels (sem ALIMENTAÇÃO
                // duplicando chip Nutrição da faixa rápida).
                HealthTimelineFilterChipsBar(session: session),
              ],
            ),
          ),
        );
      },
    );
  }
}
