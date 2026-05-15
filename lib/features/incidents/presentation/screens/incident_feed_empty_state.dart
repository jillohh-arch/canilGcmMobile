part of 'incident_form_screen.dart';

class _IncidentFeedEmptyState extends StatelessWidget {
  const _IncidentFeedEmptyState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.report_off_rounded,
            size: 56,
            color: Colors.white.withAlpha(30),
          ),
          const SizedBox(height: 12),
          Text(
            'Nenhuma ocorrÃªncia registrada',
            style: GoogleFonts.inter(
              fontSize: 14,
              color: Colors.white.withAlpha(60),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Toque em "Nova" para registrar',
            style: GoogleFonts.inter(
              fontSize: 12,
              color: Colors.white.withAlpha(40),
            ),
          ),
        ],
      ),
    );
  }
}
