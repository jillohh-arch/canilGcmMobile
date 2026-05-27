import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:canil_gcm/core/theme/app_theme.dart';
import 'package:canil_gcm/features/occurrences/domain/occurrence_event.dart';
import 'active_occurrence_event_card.dart';

class ActiveOccurrenceTimeline extends StatelessWidget {
  final List<OccurrenceEvent> events;
  final ValueChanged<OccurrenceEvent> onEventTap;
  final ValueChanged<OccurrenceEvent>? onLocationTap;
  final String? handlerName;
  final String? locationLabel;
  final String? errorMessage;
  final VoidCallback? onRetry;

  const ActiveOccurrenceTimeline({
    super.key,
    required this.events,
    required this.onEventTap,
    this.onLocationTap,
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
            final isFirst = index == 0;
            final isLast = index == events.length - 1;

            return IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _TimelineConnector(
                    isFirst: isFirst,
                    isLast: isLast,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ActiveOccurrenceEventCard(
                      event: event,
                      isRecent: isFirst,
                      onTap: () => onEventTap(event),
                      onLocationTap: onLocationTap != null
                          ? () => onLocationTap!(event)
                          : null,
                      handlerName: handlerName,
                      locationLabel: locationLabel,
                    ),
                  ),
                ],
              ),
            );
          }),
      ],
    );
  }
}

class _TimelineConnector extends StatelessWidget {
  final bool isFirst;
  final bool isLast;

  const _TimelineConnector({required this.isFirst, required this.isLast});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 20,
      child: Column(
        children: [
          // Line above dot
          Expanded(
            child: Container(
              width: 2,
              color: isFirst ? Colors.transparent : AppTheme.primary.withAlpha(40),
            ),
          ),
          // Dot
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: isFirst ? AppTheme.primary : Colors.transparent,
              border: Border.all(
                color: AppTheme.primary,
                width: isFirst ? 0 : 1.5,
              ),
            ),
          ),
          // Line below dot
          Expanded(
            child: Container(
              width: 2,
              color: isLast ? Colors.transparent : AppTheme.primary.withAlpha(40),
            ),
          ),
        ],
      ),
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
