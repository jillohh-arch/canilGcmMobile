part of 'occurrence_timeline_preview.dart';

class _TimelineLeadingVisual extends StatelessWidget {
  final IncidentProgressUpdate update;
  final _OccurrenceEventVisual eventVisual;
  final bool isLatest;

  const _TimelineLeadingVisual({
    required this.update,
    required this.eventVisual,
    required this.isLatest,
  });

  @override
  Widget build(BuildContext context) {
    final eventColor = eventVisual.color;
    final assetPath = eventVisual.assetPath;

    return SizedBox(
      width: 48,
      child: Column(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: eventColor.withAlpha(isLatest ? 35 : 18),
              shape: BoxShape.circle,
              border: Border.all(color: eventColor.withAlpha(150)),
            ),
            child: assetPath == null
                ? Icon(eventVisual.icon, color: eventColor, size: 20)
                : Padding(
                    padding: const EdgeInsets.all(1.5),
                    child: Image.asset(
                      assetPath,
                      fit: BoxFit.contain,
                      errorBuilder: (context, error, stackTrace) =>
                          Icon(eventVisual.icon, color: eventColor, size: 20),
                    ),
                  ),
          ),
          const SizedBox(height: 6),
          Text(
            _formatHour(update.timestamp),
            textAlign: TextAlign.center,
            style: GoogleFonts.robotoMono(
              color: Colors.white70,
              fontSize: 10,
              fontWeight: FontWeight.w900,
              letterSpacing: 0.6,
            ),
          ),
        ],
      ),
    );
  }
}

String _formatHour(DateTime timestamp) {
  return '${timestamp.hour.toString().padLeft(2, '0')}:${timestamp.minute.toString().padLeft(2, '0')}';
}
