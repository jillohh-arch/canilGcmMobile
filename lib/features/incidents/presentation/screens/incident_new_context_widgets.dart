part of 'incident_form_screen.dart';

class _IncidentStartContextRow extends StatelessWidget {
  final DateTime timestamp;

  const _IncidentStartContextRow({required this.timestamp});

  @override
  Widget build(BuildContext context) {
    final timeStr =
        '${timestamp.hour.toString().padLeft(2, '0')}:${timestamp.minute.toString().padLeft(2, '0')}';
    final dateStr =
        '${timestamp.day.toString().padLeft(2, '0')}/${timestamp.month.toString().padLeft(2, '0')}/${timestamp.year}';

    return Row(
      children: [
        Expanded(
          child: _IncidentInfoCard(
            icon: Icons.location_on_rounded,
            label: 'LOCAL ATUAL',
            body: Text(
              'Obtendo localização GPS...',
              style: GoogleFonts.inter(
                fontSize: 13,
                color: Colors.white70,
                height: 1.4,
              ),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _IncidentInfoCard(
            icon: Icons.access_time_rounded,
            label: 'HORA ATUAL',
            body: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  timeStr,
                  style: GoogleFonts.oxanium(
                    fontSize: 24,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  dateStr,
                  style: GoogleFonts.inter(fontSize: 11, color: Colors.white54),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
