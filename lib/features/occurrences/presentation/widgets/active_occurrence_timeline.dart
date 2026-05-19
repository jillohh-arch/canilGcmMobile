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
  final String? errorMessage;
  final VoidCallback? onRetry;

  const ActiveOccurrenceTimeline({
    super.key,
    required this.events,
    required this.onEventTap,
    this.handlerName,
    this.locationLabel,
    this.errorMessage,
    this.onRetry,
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

        if (errorMessage != null)
          _ErrorState(message: errorMessage!, onRetry: onRetry)
        else if (events.isEmpty)
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

class _ErrorState extends StatelessWidget {
  final String message;
  final VoidCallback? onRetry;

  const _ErrorState({required this.message, this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
      decoration: BoxDecoration(
        color: const Color(0xFFE53935).withAlpha(12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE53935).withAlpha(60)),
      ),
      child: Column(
        children: [
          const Icon(
            Icons.warning_amber_rounded,
            color: Color(0xFFE53935),
            size: 32,
          ),
          const SizedBox(height: 12),
          Text(
            'Erro ao carregar eventos',
            style: GoogleFonts.inter(
              color: Colors.white,
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            message,
            textAlign: TextAlign.center,
            style: GoogleFonts.inter(
              color: Colors.white.withAlpha(160),
              fontSize: 12,
              height: 1.4,
            ),
          ),
          if (onRetry != null) ...[
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded, size: 16),
              label: Text(
                'Tentar novamente',
                style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600),
              ),
              style: OutlinedButton.styleFrom(
                foregroundColor: const Color(0xFF4DD0E1),
                side: const BorderSide(color: Color(0xFF4DD0E1)),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              ),
            ),
          ],
        ],
      ),
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
