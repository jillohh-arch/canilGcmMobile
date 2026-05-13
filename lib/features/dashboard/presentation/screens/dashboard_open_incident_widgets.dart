part of 'dashboard_screen.dart';

class _DashboardOpenIncidentCard extends StatelessWidget {
  final Incident incident;
  final String dogName;
  final int additionalCount;
  final VoidCallback onContinue;
  final VoidCallback onQuickClose;

  const _DashboardOpenIncidentCard({
    required this.incident,
    required this.dogName,
    required this.additionalCount,
    required this.onContinue,
    required this.onQuickClose,
  });

  @override
  Widget build(BuildContext context) {
    final latestUpdate = incident.progressUpdates.isNotEmpty
        ? incident.progressUpdates.last
        : null;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF161618),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: const Color(0x33FBBF24)),
        boxShadow: const [
          BoxShadow(color: Color(0x14000000), blurRadius: 18, spreadRadius: 1),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _OpenIncidentHeader(
            incident: incident,
            dogName: dogName,
            additionalCount: additionalCount,
          ),
          const SizedBox(height: 12),
          _OpenIncidentMetrics(incident: incident),
          if (incident.outcomes.isNotEmpty) ...[
            const SizedBox(height: 10),
            _OpenIncidentOutcomeChips(outcomes: incident.outcomes),
          ],
          if (latestUpdate != null) ...[
            const SizedBox(height: 12),
            _OpenIncidentLatestUpdate(
              update: latestUpdate,
              fallbackDescription: incident.description,
            ),
          ],
          const SizedBox(height: 14),
          _OpenIncidentActions(
            onContinue: onContinue,
            onQuickClose: onQuickClose,
          ),
        ],
      ),
    );
  }
}
