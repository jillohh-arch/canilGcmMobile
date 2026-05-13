part of 'dashboard_screen.dart';

class _QuickCloseHeader extends StatelessWidget {
  final Incident incident;

  const _QuickCloseHeader({required this.incident});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            color: const Color(0x144ADE80),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: const Color(0x334ADE80)),
          ),
          child: const Icon(
            Icons.task_alt_rounded,
            color: Color(0xFF4ADE80),
            size: 20,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'ENCERRAR OCORRÊNCIA',
                style: GoogleFonts.inter(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 0.8,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '${incident.type ?? 'Ocorrência'} - ${incident.location}',
                style: GoogleFonts.inter(
                  color: Colors.white54,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _QuickCloseSectionLabel extends StatelessWidget {
  final String label;

  const _QuickCloseSectionLabel(this.label);

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      style: GoogleFonts.inter(
        color: Colors.white54,
        fontSize: 10,
        fontWeight: FontWeight.w800,
        letterSpacing: 0.6,
      ),
    );
  }
}
