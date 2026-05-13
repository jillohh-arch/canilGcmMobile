part of 'dashboard_screen.dart';

class _OpenIncidentLatestUpdate extends StatelessWidget {
  final IncidentProgressUpdate update;
  final String fallbackDescription;

  const _OpenIncidentLatestUpdate({
    required this.update,
    required this.fallbackDescription,
  });

  @override
  Widget build(BuildContext context) {
    final description = update.description.isNotEmpty
        ? update.description
        : fallbackDescription;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withAlpha(6),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: Colors.white12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            update.title.toUpperCase(),
            style: GoogleFonts.inter(
              color: Colors.white54,
              fontSize: 10,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.6,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            description,
            style: GoogleFonts.inter(
              color: Colors.white70,
              fontSize: 12,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }
}
