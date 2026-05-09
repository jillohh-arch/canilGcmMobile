part of 'active_shift_dashboard_screen.dart';

class _TodayActivitiesCard extends StatelessWidget {
  final String dogId;
  const _TodayActivitiesCard({required this.dogId});

  @override
  Widget build(BuildContext context) {
    final tVM = Provider.of<TrainingViewModel>(context);
    final iVM = Provider.of<IncidentViewModel>(context);
    final hVM = Provider.of<HealthViewModel>(context);

    final now = DateTime.now();
    final startOfDay = DateTime(now.year, now.month, now.day);
    final endOfDay = startOfDay.add(const Duration(days: 1));

    // Gather today's entries
    final List<_ActivityEntry> entries = [];

    for (final t in tVM.trainings) {
      if (t.dogId != dogId) continue;
      if (t.date.isBefore(startOfDay) || t.date.isAfter(endOfDay)) continue;
      final isRoutine = [
        'Passeio',
        'Lazer/Brincadeira',
        'Brincadeira',
        'Condicionamento Físico',
        'Alimentação',
        'Limpeza',
        'Descanso',
        'Escovação',
        'Outros',
      ].contains(t.trainingType);
      entries.add(
        _ActivityEntry(
          time: t.date,
          label: t.trainingType,
          icon: isRoutine ? Icons.pets_rounded : Icons.track_changes_rounded,
          color: isRoutine ? const Color(0xFF43A047) : const Color(0xFFFFB300),
        ),
      );
    }

    for (final i in iVM.incidents) {
      if (i.dogId != dogId) continue;
      if (i.date.isBefore(startOfDay) || i.date.isAfter(endOfDay)) continue;
      entries.add(
        _ActivityEntry(
          time: i.date,
          label: i.type ?? 'Ocorrência',
          icon: Icons.shield_outlined,
          color: const Color(0xFFE53935),
        ),
      );
    }

    for (final h in hVM.healthLogs) {
      if (h.dogId != dogId) continue;
      if (h.date.isBefore(startOfDay) || h.date.isAfter(endOfDay)) continue;
      entries.add(
        _ActivityEntry(
          time: h.date,
          label: h.logType,
          icon: Icons.vaccines_rounded,
          color: const Color(0xFF8E24AA),
        ),
      );
    }

    entries.sort((a, b) => b.time.compareTo(a.time)); // most recent first

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
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  const Icon(
                    Icons.history_edu_rounded,
                    color: _hudCyan,
                    size: 16,
                  ),
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
                padding: const EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 2,
                ),
                decoration: BoxDecoration(
                  color: _hudAmber.withAlpha(28),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: _hudAmber.withAlpha(120)),
                ),
                child: Text(
                  '${entries.length}',
                  style: GoogleFonts.robotoMono(
                    fontSize: 11,
                    fontWeight: FontWeight.w900,
                    color: _hudAmber,
                    letterSpacing: 0.6,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (entries.isEmpty)
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Center(
                child: Text(
                  'Nenhuma atividade registrada hoje',
                  style: GoogleFonts.inter(color: Colors.white54, fontSize: 13),
                ),
              ),
            )
          else
            ...entries.take(5).map((e) => _ActivityRow(entry: e)),
          if (entries.length > 5)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                '+ ${entries.length - 5} mais — ver Linha do Tempo',
                style: GoogleFonts.inter(
                  color: Colors.white38,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
                textAlign: TextAlign.center,
              ),
            ),
        ],
      ),
    );
  }
}

class _ActivityEntry {
  final DateTime time;
  final String label;
  final IconData icon;
  final Color color;
  _ActivityEntry({
    required this.time,
    required this.label,
    required this.icon,
    required this.color,
  });
}

class _ActivityRow extends StatelessWidget {
  final _ActivityEntry entry;
  const _ActivityRow({required this.entry});

  @override
  Widget build(BuildContext context) {
    final timeStr =
        '${entry.time.hour.toString().padLeft(2, '0')}:${entry.time.minute.toString().padLeft(2, '0')}';
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: entry.color.withAlpha(40),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: entry.color.withAlpha(110)),
              boxShadow: [
                BoxShadow(color: entry.color.withAlpha(30), blurRadius: 12),
              ],
            ),
            child: Icon(entry.icon, color: entry.color, size: 18),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              entry.label,
              style: GoogleFonts.oxanium(
                color: Colors.white,
                fontWeight: FontWeight.w800,
                fontSize: 14,
                letterSpacing: 0.6,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Text(
            timeStr,
            style: GoogleFonts.robotoMono(
              color: _hudCyan.withAlpha(170),
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _PulsingIndicator extends StatefulWidget {
  @override
  __PulsingIndicatorState createState() => __PulsingIndicatorState();
}

class __PulsingIndicatorState extends State<_PulsingIndicator>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 1),
    )..repeat(reverse: true);
    _animation = Tween(begin: 2.0, end: 10.0).animate(_controller);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        AnimatedBuilder(
          animation: _animation,
          builder: (context, child) {
            return Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: _hudGreen,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: _hudGreen.withAlpha(150),
                    blurRadius: _animation.value,
                    spreadRadius: _animation.value / 2,
                  ),
                ],
              ),
            );
          },
        ),
        const SizedBox(width: 8),
        Text(
          'EM PATRULHA',
          style: GoogleFonts.robotoMono(
            fontSize: 10,
            fontWeight: FontWeight.bold,
            color: _hudGreen,
            letterSpacing: 1.0,
          ),
        ),
      ],
    );
  }
}
