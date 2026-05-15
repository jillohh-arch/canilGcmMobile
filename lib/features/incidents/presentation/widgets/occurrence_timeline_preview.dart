import 'package:flutter/material.dart';
import 'package:canil_gcm/core/theme/app_theme.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:canil_gcm/features/incidents/domain/incident.dart';

part 'occurrence_timeline_event_visuals.dart';
part 'occurrence_timeline_event_body.dart';
part 'occurrence_timeline_leading_visual.dart';
part 'occurrence_timeline_meta.dart';
part 'occurrence_timeline_tile_card.dart';

class OccurrenceTimelinePreview extends StatelessWidget {
  final List<IncidentProgressUpdate> updates;
  final Color accent;
  final ValueChanged<int>? onEventTap;

  const OccurrenceTimelinePreview({
    super.key,
    required this.updates,
    required this.accent,
    this.onEventTap,
  });

  @override
  Widget build(BuildContext context) {
    if (updates.isEmpty) {
      return const SizedBox.shrink();
    }

    final visibleEntries = updates.asMap().entries.toList().reversed.take(5);
    final hiddenCount = updates.length > 5 ? updates.length - 5 : 0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 16),
        Row(
          children: [
            Container(
              width: 3,
              height: 18,
              decoration: BoxDecoration(
                color: accent,
                borderRadius: BorderRadius.circular(3),
                boxShadow: [
                  BoxShadow(color: accent.withAlpha(75), blurRadius: 10),
                ],
              ),
            ),
            const SizedBox(width: 9),
            Expanded(
              child: Text(
                'REGISTRO OPERACIONAL',
                style: GoogleFonts.inter(
                  fontSize: 12,
                  fontWeight: FontWeight.w900,
                  color: Colors.white,
                  letterSpacing: 1.4,
                ),
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
              decoration: BoxDecoration(
                color: accent.withAlpha(16),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: accent.withAlpha(95)),
              ),
              child: Text(
                '${updates.length} evento${updates.length == 1 ? '' : 's'}',
                style: GoogleFonts.inter(
                  color: accent,
                  fontSize: 9,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 0.8,
                ),
              ),
            ),
          ],
        ),
        if (hiddenCount > 0) ...[
          const SizedBox(height: 7),
          Text(
            'Mostrando os 5 eventos mais recentes. Toque em um registro para editar detalhes.',
            style: GoogleFonts.inter(
              color: Colors.white54,
              fontSize: 11,
              fontWeight: FontWeight.w600,
              height: 1.3,
            ),
          ),
        ],
        const SizedBox(height: 12),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
          decoration: BoxDecoration(
            color: const Color(0xFF0E1A1F).withAlpha(190),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: accent.withAlpha(70)),
          ),
          child: Column(
            children: [
              ...visibleEntries.map(
                (entry) => _OccurrenceTimelineTile(
                  update: entry.value,
                  accent: accent,
                  isLatest: entry.key == updates.length - 1,
                  onTap: onEventTap == null
                      ? null
                      : () => onEventTap!(entry.key),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
