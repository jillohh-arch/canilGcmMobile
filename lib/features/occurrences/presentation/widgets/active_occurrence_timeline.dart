import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:canil_gcm/core/theme/app_theme.dart';
import 'package:canil_gcm/features/occurrences/domain/occurrence_event.dart';
import 'active_occurrence_event_card.dart';

class ActiveOccurrenceTimeline extends StatelessWidget {
  final List<OccurrenceEvent> events;
  final ValueChanged<OccurrenceEvent> onEventTap;
  final String? handlerName;
  final String? locationLabel;

  const ActiveOccurrenceTimeline({
    super.key,
    required this.events,
    required this.onEventTap,
    this.handlerName,
    this.locationLabel,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'REGISTRO OPERACIONAL',
              style: GoogleFonts.inter(
                color: AppTheme.primary,
                fontSize: 11,
                fontWeight: FontWeight.w600,
                letterSpacing: 1.2,
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: AppTheme.primary.withAlpha(25),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                '${events.length} evento${events.length != 1 ? 's' : ''}',
                style: GoogleFonts.inter(
                  color: AppTheme.primary,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),

        // Events list or empty state
        if (events.isEmpty)
          _EmptyState()
        else
          ...events.asMap().entries.map((entry) {
            final index = entry.key;
            final event = entry.value;
            return ActiveOccurrenceEventCard(
              event: event,
              isRecent: index == 0,
              onTap: () => onEventTap(event),
              handlerName: handlerName,
              locationLabel: locationLabel,
            );
          }),
      ],
    );
  }
}

class _EmptyState extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 16),
      decoration: BoxDecoration(
        color: Colors.white.withAlpha(5),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withAlpha(10)),
      ),
      child: Column(
        children: [
          Icon(
            Icons.timeline_outlined,
            color: Colors.white.withAlpha(60),
            size: 32,
          ),
          const SizedBox(height: 12),
          Text(
            'Adicione o primeiro evento\ndesta ocorrência',
            textAlign: TextAlign.center,
            style: GoogleFonts.inter(
              color: Colors.white.withAlpha(100),
              fontSize: 13,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }
}
