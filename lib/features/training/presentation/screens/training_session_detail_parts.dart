part of 'training_log_screen.dart';

class _SessionExpandedDetails extends StatelessWidget {
  final TrainingSessionModel session;
  final Color color;

  const _SessionExpandedDetails({required this.session, required this.color});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 12),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              if (session.weather.isNotEmpty)
                _DetailChip(
                  icon: Icons.cloud_outlined,
                  label: session.weather,
                  color: color,
                ),
              if (session.humidity != null)
                _DetailChip(
                  icon: Icons.water_drop_outlined,
                  label: '${session.humidity!.round()}% umidade',
                  color: color,
                ),
              if (session.windDirection != null)
                _DetailChip(
                  icon: Icons.air,
                  label: 'Vento: ${session.windDirection}',
                  color: color,
                ),
              if (session.hidingTime != null)
                _DetailChip(
                  icon: Icons.timer_outlined,
                  label: 'Ocultação: ${session.hidingTime}',
                  color: color,
                ),
            ],
          ),
        ),
        if (session.handlerNotes.isNotEmpty) ...[
          const SizedBox(height: 12),
          _SessionNotesBox(notes: session.handlerNotes, color: color),
        ],
      ],
    );
  }
}

class _SessionNotesBox extends StatelessWidget {
  final String notes;
  final Color color;

  const _SessionNotesBox({required this.notes, required this.color});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: const Color(0xFF070B14).withAlpha(210),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: color.withAlpha(90)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.notes_rounded, size: 15, color: color.withAlpha(210)),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                notes,
                style: GoogleFonts.inter(
                  fontSize: 12,
                  color: Colors.white70,
                  fontWeight: FontWeight.w500,
                  height: 1.35,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DetailChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;

  const _DetailChip({
    required this.icon,
    required this.label,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
      decoration: BoxDecoration(
        color: color.withAlpha(18),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withAlpha(95)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color.withAlpha(220)),
          const SizedBox(width: 6),
          Text(
            label,
            style: GoogleFonts.robotoMono(
              fontSize: 10,
              color: Colors.white70,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}
