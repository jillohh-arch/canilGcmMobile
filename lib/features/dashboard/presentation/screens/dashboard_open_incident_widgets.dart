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
          Row(
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
              if (additionalCount > 0)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
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
                ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _IncidentDashboardPill(
                icon: Icons.schedule_rounded,
                label: 'Aberta',
                value: _formatDashboardIncidentRelative(incident.startedAt),
              ),
              _IncidentDashboardPill(
                icon: Icons.update_rounded,
                label: 'Atualizada',
                value: _formatDashboardIncidentTimestamp(incident.updatedAt),
              ),
              if (incident.outcomes.isNotEmpty)
                _IncidentDashboardPill(
                  icon: Icons.fact_check_rounded,
                  label: 'Resultados',
                  value: '${incident.outcomes.length} marcados',
                ),
            ],
          ),
          if (incident.outcomes.isNotEmpty) ...[
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: incident.outcomes
                  .map(
                    (outcome) => _QuickIncidentChip(
                      label: outcome,
                      selected: true,
                      icon: Icons.fact_check_rounded,
                      selectedTextColor: const Color(0xFFFCD34D),
                      selectedIconColor: const Color(0xFFFBBF24),
                      selectedBorderColor: const Color(0x33FBBF24),
                      selectedBackgroundColor: const Color(0x14FBBF24),
                      onTap: () {},
                    ),
                  )
                  .toList(),
            ),
          ],
          if (latestUpdate != null) ...[
            const SizedBox(height: 12),
            Container(
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
                    latestUpdate.title.toUpperCase(),
                    style: GoogleFonts.inter(
                      color: Colors.white54,
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.6,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    latestUpdate.description.isNotEmpty
                        ? latestUpdate.description
                        : incident.description,
                    style: GoogleFonts.inter(
                      color: Colors.white70,
                      fontSize: 12,
                      height: 1.4,
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: onContinue,
                  icon: const Icon(Icons.playlist_add_check_rounded, size: 16),
                  label: Text(
                    'Continuar ocorrência',
                    style: GoogleFonts.inter(
                      fontWeight: FontWeight.w800,
                      fontSize: 12,
                    ),
                  ),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white70,
                    side: const BorderSide(color: Colors.white12),
                    padding: const EdgeInsets.symmetric(vertical: 13),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(6),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FilledButton.icon(
                  onPressed: onQuickClose,
                  icon: const Icon(Icons.task_alt_rounded, size: 16),
                  label: Text(
                    'Encerrar agora',
                    style: GoogleFonts.inter(
                      fontWeight: FontWeight.w900,
                      fontSize: 12,
                    ),
                  ),
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFFFBBF24),
                    foregroundColor: Colors.black,
                    padding: const EdgeInsets.symmetric(vertical: 13),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(6),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _formatDashboardIncidentRelative(DateTime startedAt) {
    final diff = DateTime.now().difference(startedAt);
    if (diff.inDays > 0) return '${diff.inDays}d';
    if (diff.inHours > 0) {
      return '${diff.inHours}h ${diff.inMinutes.remainder(60)}m';
    }
    return '${diff.inMinutes.clamp(0, 59)}m';
  }

  String _formatDashboardIncidentTimestamp(DateTime timestamp) {
    return '${timestamp.day.toString().padLeft(2, '0')}/${timestamp.month.toString().padLeft(2, '0')} '
        '${timestamp.hour.toString().padLeft(2, '0')}:${timestamp.minute.toString().padLeft(2, '0')}';
  }
}
