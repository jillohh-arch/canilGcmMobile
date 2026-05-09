part of 'active_shift_dashboard_screen.dart';

class _HealthAlertBanner extends StatelessWidget {
  final String dogId;

  const _HealthAlertBanner({required this.dogId});

  @override
  Widget build(BuildContext context) {
    final hVM = Provider.of<HealthViewModel>(context);
    final now = DateTime.now();
    final horizon = now.add(const Duration(days: 7));

    final alerts = hVM.healthLogs.where((log) {
      if (log.dogId != dogId) return false;
      if (!log.healthObservations.contains('Retorno agendado:')) return false;
      try {
        final raw = log.healthObservations
            .split('Retorno agendado:')
            .last
            .trim();
        final parts = raw.split('/');
        if (parts.length != 3) return false;
        final date = DateTime(
          int.parse(parts[2]),
          int.parse(parts[1]),
          int.parse(parts[0]),
        );
        return date.isAfter(now.subtract(const Duration(days: 1))) &&
            date.isBefore(horizon);
      } catch (_) {
        return false;
      }
    }).toList();

    if (alerts.isEmpty) {
      return const SliverToBoxAdapter(child: SizedBox.shrink());
    }

    final nextLog = alerts.first;
    final rawDate = nextLog.healthObservations
        .split('Retorno agendado:')
        .last
        .trim()
        .split('\n')
        .first
        .trim();

    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: _hudPanel.withAlpha(235),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: _hudAmber, width: 1.5),
            boxShadow: [
              BoxShadow(
                color: _hudAmber.withAlpha(40),
                blurRadius: 16,
                spreadRadius: 1,
              ),
            ],
          ),
          child: Row(
            children: [
              const Icon(
                Icons.warning_amber_rounded,
                color: _hudAmber,
                size: 28,
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'ALERTA DE SAÚDE',
                      style: GoogleFonts.robotoMono(
                        color: _hudAmber,
                        fontSize: 11,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 1.2,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${nextLog.logType} — Retorno agendado: $rawDate',
                      style: GoogleFonts.inter(
                        color: Colors.white70,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
