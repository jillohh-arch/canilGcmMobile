part of 'global_incidents_screen.dart';

class _GlobalIncidentsEmptyState extends StatelessWidget {
  const _GlobalIncidentsEmptyState();

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
        ],
      ),
    );
  }
}
