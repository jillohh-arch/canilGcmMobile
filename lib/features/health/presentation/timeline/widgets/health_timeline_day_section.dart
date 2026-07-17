import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:canil_gcm/core/theme/app_theme.dart';
import 'package:canil_gcm/features/health/presentation/timeline/health_timeline_entry_view.dart';
import 'package:canil_gcm/features/health/presentation/timeline/health_timeline_grouping.dart';
import 'package:canil_gcm/features/health/presentation/timeline/widgets/health_timeline_entry_card.dart';
import 'package:canil_gcm/features/health/presentation/timeline/widgets/health_timeline_formatters.dart';
import 'package:canil_gcm/features/health/presentation/timeline/widgets/health_timeline_marker.dart';
import 'package:canil_gcm/features/health/presentation/timeline/widgets/health_timeline_type_visuals.dart';

/// Header discreto de um dia da timeline.
class HealthTimelineDayHeader extends StatelessWidget {
  final DateTime date;
  final DateTime? now;

  const HealthTimelineDayHeader({super.key, required this.date, this.now});

  @override
  Widget build(BuildContext context) {
    final label = HealthTimelineFormatters.dayGroupLabel(date, now: now);
    return Padding(
      padding: const EdgeInsets.only(left: 36, bottom: 8, top: 4),
      child: Semantics(
        header: true,
        label: label,
        child: Text(
          label,
          style: GoogleFonts.inter(
            color: AppTheme.textMuted,
            fontSize: 12,
            fontWeight: FontWeight.w800,
            letterSpacing: 1.1,
          ),
        ),
      ),
    );
  }
}

/// Seção visual de um dia: header discreto + rail + cards.
///
/// Preferir slots flat em [HealthTimelineView] com lazy builder.
/// Esta seção permanece útil para harness isolado de um único dia.
class HealthTimelineDaySection extends StatelessWidget {
  final HealthTimelineDayGroup group;
  final DateTime? now;
  final ValueChanged<HealthTimelineEntryView>? onEntryTap;

  const HealthTimelineDaySection({
    super.key,
    required this.group,
    this.now,
    this.onEntryTap,
  });

  @override
  Widget build(BuildContext context) {
    final entries = group.entries;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        HealthTimelineDayHeader(date: group.date, now: now),
        for (var i = 0; i < entries.length; i++) ...[
          if (i > 0) const SizedBox(height: 10),
          HealthTimelineEntryRow(
            entry: entries[i],
            isFirst: i == 0,
            isLast: i == entries.length - 1,
            onEntryTap: onEntryTap,
          ),
        ],
      ],
    );
  }
}

/// Linha individual: marker + rail com altura do card (sem [IntrinsicHeight]).
class HealthTimelineEntryRow extends StatelessWidget {
  final HealthTimelineEntryView entry;
  final bool isFirst;
  final bool isLast;
  final ValueChanged<HealthTimelineEntryView>? onEntryTap;
  final String? navigationActionLabel;

  const HealthTimelineEntryRow({
    super.key,
    required this.entry,
    required this.isFirst,
    required this.isLast,
    this.onEntryTap,
    this.navigationActionLabel,
  });

  @override
  Widget build(BuildContext context) {
    final visual = HealthTimelineTypeVisuals.resolve(entry.type);

    return Stack(
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 36),
          child: HealthTimelineEntryCard(
            entry: entry,
            onTap: onEntryTap,
            navigationActionLabel: navigationActionLabel,
          ),
        ),
        Positioned(
          left: 0,
          top: 0,
          bottom: 0,
          width: 28,
          child: ExcludeSemantics(
            child: CustomPaint(
              painter: HealthTimelineRailPainter(
                isFirst: isFirst,
                isLast: isLast,
                accent: visual.accent,
                cancelled: entry.isCancelled,
              ),
            ),
          ),
        ),
      ],
    );
  }
}
