part of 'dog_details_screen.dart';

class _MissionLog extends StatelessWidget {
  final Dog dog;
  const _MissionLog({required this.dog});

  @override
  Widget build(BuildContext context) {
    final tVM = Provider.of<TrainingViewModel>(context);
    final hVM = Provider.of<HealthViewModel>(context);
    final iVM = Provider.of<IncidentViewModel>(context);

    final List<_TimelineItem> items = [];

    for (var t in tVM.trainings) {
      final isScent = t.trainingType == 'Faro';
      items.add(
        _TimelineItem(
          date: t.date,
          title:
              '${t.trainingType}${t.substanceUsed != null ? " · ${t.substanceUsed}" : ""}',
          subtitle: t.location,
          icon: isScent
              ? Icons.track_changes_rounded
              : (t.trainingType == 'Proteção'
                    ? Icons.shield_rounded
                    : Icons.school_rounded),
          color: const Color(0xFFFFB300),
          tag: 'TREINO',
        ),
      );
    }
    for (var h in hVM.healthLogs) {
      final (icon, color) = _healthIconAndColor(h.logType);
      items.add(
        _TimelineItem(
          date: h.date,
          title: h.logType,
          subtitle: h.vaccines.isNotEmpty
              ? h.vaccines.join(', ')
              : h.healthObservations,
          icon: icon,
          color: color,
          tag: 'SAÚDE',
        ),
      );
    }
    for (var i in iVM.incidents) {
      items.add(
        _TimelineItem(
          date: i.date,
          title: i.type ?? 'Ocorrência',
          subtitle: '${i.result} · ${i.location}',
          icon: Icons.report_rounded,
          color: const Color(0xFF4ECDE4),
          tag: 'OCORRÊNCIA',
        ),
      );
    }

    items.sort((a, b) => b.date.compareTo(a.date));
    final visible = items.take(12).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              'LOG DE MISSÕES',
              style: GoogleFonts.poppins(
                fontSize: 11,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.4,
                color: Colors.white38,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(child: Container(height: 1, color: Colors.white10)),
          ],
        ),
        const SizedBox(height: 16),
        if (visible.isEmpty)
          Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Column(
                children: [
                  Icon(Icons.timeline_rounded, size: 40, color: Colors.white12),
                  const SizedBox(height: 8),
                  Text(
                    'Nenhuma atividade registrada',
                    style: GoogleFonts.poppins(
                      fontSize: 13,
                      color: Colors.white24,
                    ),
                  ),
                ],
              ),
            ),
          )
        else
          ...List.generate(visible.length, (i) {
            final item = visible[i];
            final isLast = i == visible.length - 1;
            return _TimelineRow(item: item, isLast: isLast);
          }),
      ],
    );
  }

  (IconData, Color) _healthIconAndColor(String logType) {
    switch (logType) {
      case 'Vacina':
        return (Icons.vaccines_rounded, const Color(0xFFEF5350));
      case 'Consulta':
        return (Icons.local_hospital_rounded, const Color(0xFF66BB6A));
      case 'Exame':
        return (Icons.biotech_rounded, const Color(0xFF7E57C2));
      case 'Medicação':
        return (Icons.medication_rounded, const Color(0xFFFF7043));
      case 'Banho':
        return (Icons.water_drop_rounded, const Color(0xFF29B6F6));
      default:
        return (Icons.medical_services_rounded, const Color(0xFFEF5350));
    }
  }
}

class _TimelineItem {
  final DateTime date;
  final String title;
  final String subtitle;
  final IconData icon;
  final Color color;
  final String tag;
  _TimelineItem({
    required this.date,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.color,
    required this.tag,
  });
}

class _TimelineRow extends StatelessWidget {
  final _TimelineItem item;
  final bool isLast;
  const _TimelineRow({required this.item, required this.isLast});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final dateStr =
        '${item.date.day.toString().padLeft(2, '0')}/${item.date.month.toString().padLeft(2, '0')}/${item.date.year.toString().substring(2)}';

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 36,
            child: Column(
              children: [
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: item.color.withAlpha(30),
                    border: Border.all(
                      color: item.color.withAlpha(120),
                      width: 1.5,
                    ),
                  ),
                  child: Icon(item.icon, color: item.color, size: 16),
                ),
                if (!isLast)
                  Expanded(
                    child: Container(
                      width: 1.5,
                      color: Colors.white10,
                      margin: const EdgeInsets.symmetric(vertical: 4),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(bottom: isLast ? 0 : 14),
              child: Container(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                decoration: BoxDecoration(
                  color: cs.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: cs.outlineVariant, width: 0.5),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: item.color.withAlpha(30),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            item.tag,
                            style: GoogleFonts.poppins(
                              fontSize: 8,
                              fontWeight: FontWeight.w800,
                              color: item.color,
                              letterSpacing: 0.5,
                            ),
                          ),
                        ),
                        Text(
                          dateStr,
                          style: GoogleFonts.poppins(
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                            color: Colors.white30,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      item.title,
                      style: GoogleFonts.poppins(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                    if (item.subtitle.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        item.subtitle,
                        style: GoogleFonts.poppins(
                          fontSize: 11,
                          color: Colors.white38,
                          fontWeight: FontWeight.w500,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
