part of 'dashboard_screen.dart';

class _OpenIncidentHeader extends StatelessWidget {
  final Incident incident;
  final String dogName;
  final int additionalCount;

  const _OpenIncidentHeader({
    required this.incident,
    required this.dogName,
    required this.additionalCount,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            color: const Color(0x14FBBF24),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: const Color(0x33FBBF24)),
          ),
          child: const Icon(
            Icons.radar_rounded,
            color: Color(0xFFFBBF24),
            size: 20,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'OCORRÊNCIA EM ANDAMENTO',
                style: GoogleFonts.inter(
                  color: const Color(0xFFFCD34D),
                  fontSize: 11,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 0.8,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                incident.location,
                style: GoogleFonts.inter(
                  color: Colors.white,
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '${incident.type ?? 'Ocorrência'} • $dogName',
                style: GoogleFonts.inter(
                  color: Colors.white54,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
        if (additionalCount > 0) _OpenIncidentAdditionalBadge(additionalCount),
      ],
    );
  }
}

class _OpenIncidentAdditionalBadge extends StatelessWidget {
  final int additionalCount;

  const _OpenIncidentAdditionalBadge(this.additionalCount);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white.withAlpha(10),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white12),
      ),
      child: Text(
        '+$additionalCount aberta(s)',
        style: GoogleFonts.inter(
          color: Colors.white70,
          fontSize: 10,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}
