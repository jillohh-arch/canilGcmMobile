part of 'active_shift_dashboard_screen.dart';

class _TodayActivitiesCard extends StatelessWidget {
  final String dogId;

  const _TodayActivitiesCard({required this.dogId});

  @override
  Widget build(BuildContext context) {
    final entries = _collectTodayActivityEntries(context, dogId);

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: _hudPanel.withAlpha(235),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: _hudCyan.withAlpha(85)),
        boxShadow: [BoxShadow(color: _hudCyan.withAlpha(20), blurRadius: 18)],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _TodayActivitiesHeader(count: entries.length),
          const SizedBox(height: 16),
          if (entries.isEmpty)
            const _TodayActivitiesEmptyState()
          else
            ...entries.take(5).map((entry) => _ActivityRow(entry: entry)),
          if (entries.length > 5)
            _TodayActivitiesOverflowLabel(remaining: entries.length - 5),
        ],
      ),
    );
  }
}

class _TodayActivitiesHeader extends StatelessWidget {
  final int count;

  const _TodayActivitiesHeader({required this.count});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Row(
          children: [
            const Icon(Icons.history_edu_rounded, color: _hudCyan, size: 16),
            const SizedBox(width: 8),
            Text(
              'ATIVIDADES DE HOJE',
              style: GoogleFonts.robotoMono(
                fontSize: 10,
                fontWeight: FontWeight.w800,
                color: Colors.white60,
                letterSpacing: 1.0,
              ),
            ),
          ],
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          decoration: BoxDecoration(
            color: _hudAmber.withAlpha(28),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: _hudAmber.withAlpha(120)),
          ),
          child: Text(
            '$count',
            style: GoogleFonts.robotoMono(
              fontSize: 11,
              fontWeight: FontWeight.w900,
              color: _hudAmber,
              letterSpacing: 0.6,
            ),
          ),
        ),
      ],
    );
  }
}

class _TodayActivitiesEmptyState extends StatelessWidget {
  const _TodayActivitiesEmptyState();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Center(
        child: Text(
          'Nenhuma atividade registrada hoje',
          style: GoogleFonts.inter(color: Colors.white54, fontSize: 13),
        ),
      ),
    );
  }
}

class _TodayActivitiesOverflowLabel extends StatelessWidget {
  final int remaining;

  const _TodayActivitiesOverflowLabel({required this.remaining});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Text(
        '+ $remaining mais — ver Linha do Tempo',
        style: GoogleFonts.inter(
          color: Colors.white38,
          fontSize: 11,
          fontWeight: FontWeight.w600,
        ),
        textAlign: TextAlign.center,
      ),
    );
  }
}
