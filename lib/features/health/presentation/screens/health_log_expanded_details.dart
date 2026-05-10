part of 'health_log_screen.dart';

class _HealthExpandedDetails extends StatelessWidget {
  final HealthLogModel log;
  final Color color;

  const _HealthExpandedDetails({required this.log, required this.color});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const SizedBox(height: 10),
        const Divider(color: Colors.white12),
        const SizedBox(height: 6),
        if (log.weight != null)
          _DetailRow(
            icon: Icons.monitor_weight_outlined,
            label: 'Peso',
            value: '${log.weight!.toStringAsFixed(1)} kg',
            color: color,
          ),
        if (log.healthObservations.isNotEmpty) ...[
          const SizedBox(height: 6),
          _DetailRow(
            icon: Icons.notes_rounded,
            label: 'Observações',
            value: log.healthObservations,
            color: color,
          ),
        ],
      ],
    );
  }
}

class _DetailRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color color;

  const _DetailRow({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 14, color: color.withAlpha(180)),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label.toUpperCase(),
                style: GoogleFonts.poppins(
                  fontSize: 8,
                  fontWeight: FontWeight.w700,
                  color: Colors.white70,
                  letterSpacing: 0.8,
                ),
              ),
              Text(
                value,
                style: GoogleFonts.poppins(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: Colors.white70,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
