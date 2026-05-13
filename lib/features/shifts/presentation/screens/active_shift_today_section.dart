part of 'active_shift_dashboard_screen.dart';

/// Seção "ATIVIDADES DE HOJE" com timeline de registros do dia.
class _TodayActivitiesSection extends StatelessWidget {
  final String dogId;
  const _TodayActivitiesSection({required this.dogId});

  @override
  Widget build(BuildContext context) {
    final trainingVM = Provider.of<TrainingViewModel>(context);
    final healthVM = Provider.of<HealthViewModel>(context);
    final incidentVM = Provider.of<IncidentViewModel>(context);
    final routineVM = Provider.of<RoutineViewModel>(context);

    final todayEntries = _buildTodayEntries(
      trainingVM,
      healthVM,
      incidentVM,
      routineVM,
    );

    // Exibir no máximo 2 na home
    final displayEntries = todayEntries.take(2).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(
              Icons.calendar_today_rounded,
              color: _hudCyan,
              size: 14,
            ),
            const SizedBox(width: 6),
            Text(
              'ATIVIDADES DE HOJE',
              style: GoogleFonts.robotoMono(
                color: _hudCyan,
                fontSize: 11,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.4,
              ),
            ),
            const Spacer(),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: _hudCyan.withAlpha(20),
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: _hudCyan.withAlpha(60)),
              ),
              child: Text(
                '${todayEntries.length} registro${todayEntries.length != 1 ? 's' : ''}',
                style: GoogleFonts.robotoMono(
                  color: _hudCyan,
                  fontSize: 9,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (todayEntries.isEmpty)
          _buildEmptyState()
        else
          Container(
            decoration: BoxDecoration(
              color: _hudPanel.withAlpha(200),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: _hudCyan.withAlpha(30)),
            ),
            child: Column(
              children: [
                for (int i = 0; i < displayEntries.length; i++) ...[
                  if (i > 0)
                    Divider(
                      height: 1,
                      color: Colors.white.withAlpha(10),
                      indent: 14,
                      endIndent: 14,
                    ),
                  displayEntries[i],
                ],
                if (todayEntries.length > 2)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Text(
                      '+ ${todayEntries.length - 2} mais — ver Linha do Tempo',
                      style: GoogleFonts.inter(
                        color: Colors.white38,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _buildEmptyState() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: _hudPanel.withAlpha(200),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _hudCyan.withAlpha(30)),
      ),
      child: Text(
        'Comece o dia registrando passeio, limpeza, alimentação ou treino.',
        style: GoogleFonts.inter(color: Colors.white38, fontSize: 12),
        textAlign: TextAlign.center,
      ),
    );
  }

  List<Widget> _buildTodayEntries(
    TrainingViewModel trainingVM,
    HealthViewModel healthVM,
    IncidentViewModel incidentVM,
    RoutineViewModel routineVM,
  ) {
    final now = DateTime.now();
    final entries = <_TodayEntry>[];

    for (final s in trainingVM.trainings) {
      if (_isToday(s.date, now)) {
        entries.add(_TodayEntry(
          time: s.date,
          icon: Icons.track_changes_rounded,
          iconColor: _hudAmber,
          title: 'Treino • ${s.trainingType}',
          subtitle: s.location,
        ));
      }
    }

    for (final h in healthVM.healthLogs) {
      if (_isToday(h.date, now)) {
        entries.add(_TodayEntry(
          time: h.date,
          icon: Icons.medical_services_outlined,
          iconColor: const Color(0xFFAB47BC),
          title: h.logType,
          subtitle: h.healthObservations,
        ));
      }
    }

    for (final i in incidentVM.incidents) {
      if (_isToday(i.date, now)) {
        entries.add(_TodayEntry(
          time: i.date,
          icon: Icons.local_police_outlined,
          iconColor: _hudDanger,
          title: 'Ocorrência • ${i.type ?? 'Evento'}',
          subtitle: i.location,
        ));
      }
    }

    for (final r in routineVM.routines) {
      if (_isToday(r.timestamp, now)) {
        entries.add(_TodayEntry(
          time: r.timestamp,
          icon: _routineIcon(r.activityType),
          iconColor: _hudGreen,
          title: r.activityType,
          subtitle: r.notes ?? '',
        ));
      }
    }

    entries.sort((a, b) => b.time.compareTo(a.time));
    return entries;
  }

  bool _isToday(DateTime date, DateTime now) {
    return date.year == now.year &&
        date.month == now.month &&
        date.day == now.day;
  }

  IconData _routineIcon(String type) {
    switch (type) {
      case 'Passeio':
        return Icons.directions_walk_rounded;
      case 'Alimentação':
        return Icons.restaurant_rounded;
      case 'Limpeza':
        return Icons.cleaning_services_rounded;
      case 'Escovação':
        return Icons.brush_rounded;
      case 'Descanso':
        return Icons.hotel_rounded;
      default:
        return Icons.pets_rounded;
    }
  }
}

/// Entrada individual na timeline de hoje.
class _TodayEntry extends StatelessWidget {
  final DateTime time;
  final IconData icon;
  final Color iconColor;
  final String title;
  final String subtitle;

  const _TodayEntry({
    required this.time,
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    final hour =
        '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(
        children: [
          SizedBox(
            width: 40,
            child: Text(
              hour,
              style: GoogleFonts.robotoMono(
                color: _hudCyan,
                fontSize: 11,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: iconColor.withAlpha(20),
              shape: BoxShape.circle,
              border: Border.all(color: iconColor.withAlpha(80)),
            ),
            child: Icon(icon, color: iconColor, size: 15),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: GoogleFonts.inter(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                if (subtitle.isNotEmpty)
                  Text(
                    subtitle,
                    style: GoogleFonts.inter(
                      color: Colors.white38,
                      fontSize: 10,
                      fontWeight: FontWeight.w500,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
              ],
            ),
          ),
          const Icon(
            Icons.chevron_right_rounded,
            color: Colors.white24,
            size: 18,
          ),
        ],
      ),
    );
  }
}
