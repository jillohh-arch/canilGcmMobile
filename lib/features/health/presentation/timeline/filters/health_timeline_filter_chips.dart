import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:canil_gcm/core/theme/app_theme.dart';
import 'package:canil_gcm/features/health/presentation/timeline/filters/health_timeline_filter_labels.dart';
import 'package:canil_gcm/features/health/presentation/timeline/filters/health_timeline_filter_selection.dart';
import 'package:canil_gcm/features/health/presentation/timeline/filters/health_timeline_filter_session.dart';

/// Barra de chips dos filtros applied (compacta, 360px-safe).
class HealthTimelineFilterChipsBar extends StatelessWidget {
  const HealthTimelineFilterChipsBar({
    super.key,
    required this.session,
    this.onChanged,
  });

  final HealthTimelineFilterSession session;
  final VoidCallback? onChanged;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: session,
      builder: (context, _) {
        final selection = session.applied;
        if (selection.isEmpty) return const SizedBox.shrink();
        final chips = HealthTimelineFilterLabels.chipsFor(selection);
        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final chip in chips)
                _FilterChip(
                  data: chip,
                  onRemove: () async {
                    await _remove(session, chip.kind);
                    onChanged?.call();
                  },
                ),
            ],
          ),
        );
      },
    );
  }

  static Future<void> _remove(
    HealthTimelineFilterSession session,
    HealthTimelineFilterChipKind kind,
  ) {
    return switch (kind) {
      HealthTimelineFilterChipKind.types => session.removeAppliedTypes(),
      HealthTimelineFilterChipKind.period => session.removeAppliedPeriod(),
      HealthTimelineFilterChipKind.caseId => session.removeAppliedCaseId(),
      HealthTimelineFilterChipKind.professional =>
        session.removeAppliedProfessional(),
    };
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({required this.data, required this.onRemove});

  final HealthTimelineFilterChipData data;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final semantics = HealthTimelineFilterLabels.removeChipSemantics(
      data.label,
    );
    return Semantics(
      button: true,
      label: semantics,
      child: Material(
        color: AppTheme.transparent,
        child: InkWell(
          onTap: onRemove,
          borderRadius: BorderRadius.circular(20),
          child: Container(
            padding: const EdgeInsets.fromLTRB(10, 6, 8, 6),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              color: AppTheme.primary.withValues(alpha: 0.10),
              border: Border.all(
                color: AppTheme.primary.withValues(alpha: 0.35),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  data.label,
                  style: GoogleFonts.inter(
                    color: AppTheme.primary,
                    fontSize: 11.5,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.3,
                  ),
                ),
                const SizedBox(width: 4),
                const Icon(
                  Icons.close_rounded,
                  size: 14,
                  color: AppTheme.primary,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Helper puro para testes de chips a partir de selection.
List<HealthTimelineFilterChipData> chipsOf(
  HealthTimelineFilterSelection selection,
) => HealthTimelineFilterLabels.chipsFor(selection);
