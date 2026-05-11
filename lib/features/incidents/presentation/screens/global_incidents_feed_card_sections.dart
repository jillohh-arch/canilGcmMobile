part of 'global_incidents_screen.dart';

class _GlobalIncidentCardTags extends StatelessWidget {
  final Incident incident;

  const _GlobalIncidentCardTags({required this.incident});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Row(
      children: [
        _GlobalIncidentTag(
          icon: Icons.location_on_rounded,
          text: incident.location,
          color: const Color(0xFF4ECDE4),
        ),
        const SizedBox(width: 8),
        _GlobalIncidentTag(
          icon: Icons.badge_outlined,
          text: 'RA ${incident.handlerId}',
          color: cs.onSurfaceVariant,
        ),
      ],
    );
  }
}

class _GlobalIncidentTimestamp extends StatelessWidget {
  final String label;

  const _GlobalIncidentTimestamp({required this.label});

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      style: GoogleFonts.poppins(
        fontSize: 10,
        color: Colors.white30,
        fontWeight: FontWeight.w500,
      ),
    );
  }
}

class _GlobalIncidentDescription extends StatelessWidget {
  final String description;

  const _GlobalIncidentDescription({required this.description});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: cs.outlineVariant, width: 0.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'RELATÓRIO',
            style: GoogleFonts.poppins(
              fontSize: 8,
              fontWeight: FontWeight.w800,
              color: const Color(0xFF4ECDE4),
              letterSpacing: 0.8,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            description,
            style: GoogleFonts.poppins(
              fontSize: 12,
              color: Colors.white70,
              fontWeight: FontWeight.w400,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }
}
