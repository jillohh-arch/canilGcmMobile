part of 'daily_timeline_screen.dart';

extension _DailyTimelineItem on _DailyTimelineScreenState {
  Widget _buildTimelineTile({
    required _TimelineEntry entry,
    required int index,
    required int total,
    required String dogId,
    required String dogName,
  }) {
    final current = entry;
    final incident = current.originalModel is Incident
        ? current.originalModel as Incident
        : null;
    final isActiveIncident = incident?.isInProgress ?? false;
    final timeStr =
        "${current.time.hour.toString().padLeft(2, '0')}:${current.time.minute.toString().padLeft(2, '0')}";

    IconData icon;
    Color color;
    switch (current.type) {
      case 'Treino':
        icon = Icons.track_changes_rounded;
        color = const Color(0xFFFFB300);
        break;
      case 'Rotina':
        icon = Icons.pets_rounded;
        color = const Color(0xFF43A047);
        break;
      case 'Ocorrência':
        icon = isActiveIncident
            ? Icons.pending_actions_rounded
            : Icons.shield_outlined;
        color = isActiveIncident ? _hudAmber : const Color(0xFFE53935);
        break;
      case 'Saude':
        icon = Icons.vaccines_rounded;
        color = const Color(0xFF8E24AA);
        break;
      default:
        icon = Icons.info_outline;
        color = Colors.blueGrey;
    }

    final cleanTitle = _cleanTimelineTitle(current);
    final subtitle = _buildTimelineSubtitle(current, timeStr);

    String mainMetric = '';
    if (current.type == 'Treino' && current.details['Duração'] != null) {
      mainMetric = current.details['Duração'];
    }
    if (isActiveIncident) {
      mainMetric = 'EM ANDAMENTO';
    } else if (current.type == 'Ocorrência' &&
        current.details['Resultado'] != null) {
      mainMetric = current.details['Resultado'].toString().toUpperCase();
    }

    return TimelineTile(
      alignment: TimelineAlign.manual,
      lineXY: 0.12,
      isFirst: index == 0,
      isLast: index == total - 1,
      beforeLineStyle: LineStyle(color: color.withAlpha(90), thickness: 2.5),
      afterLineStyle: LineStyle(color: color.withAlpha(70), thickness: 2.5),
      indicatorStyle: IndicatorStyle(
        width: 40,
        height: 40,
        drawGap: true,
        indicator: Container(
          decoration: BoxDecoration(
            color: const Color(0xFF070B14),
            shape: BoxShape.circle,
            border: Border.all(color: color, width: 1.4),
            boxShadow: [
              BoxShadow(
                color: color.withAlpha(140),
                blurRadius: 16,
                spreadRadius: 2,
              ),
            ],
          ),
          child: Center(child: Icon(icon, color: color, size: 19)),
        ),
      ),
      endChild: Padding(
        padding: const EdgeInsets.only(left: 14, right: 4, bottom: 16, top: 4),
        child: Card(
          elevation: 0,
          color: const Color(0xFF0B1020),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(6),
            side: BorderSide(color: color.withAlpha(150), width: 1),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: Container(
              decoration: BoxDecoration(
                border: Border(left: BorderSide(color: color, width: 4)),
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    color.withAlpha(32),
                    const Color(0xFF0F1726),
                    const Color(0xFF070B14),
                  ],
                ),
                boxShadow: [
                  BoxShadow(
                    color: color.withAlpha(45),
                    blurRadius: 18,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: Theme(
                data: Theme.of(
                  context,
                ).copyWith(dividerColor: Colors.transparent),
                child: ExpansionTile(
                  onExpansionChanged: (expanded) {
                    if (expanded) HapticFeedback.lightImpact();
                  },
                  iconColor: color,
                  collapsedIconColor: color.withAlpha(180),
                  tilePadding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
                  title: Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Container(
                        width: 34,
                        height: 34,
                        margin: const EdgeInsets.only(right: 10),
                        decoration: BoxDecoration(
                          color: const Color(0xFF070B14),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: color.withAlpha(170)),
                          boxShadow: [
                            BoxShadow(
                              color: color.withAlpha(60),
                              blurRadius: 12,
                            ),
                          ],
                        ),
                        child: Icon(icon, color: color, size: 17),
                      ),
                      Expanded(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              cleanTitle.toUpperCase(),
                              style: GoogleFonts.oxanium(
                                color: Colors.white,
                                fontWeight: FontWeight.w900,
                                fontSize: 15,
                                letterSpacing: 1.1,
                              ),
                              softWrap: true,
                            ),
                            const SizedBox(height: 5),
                            Text(
                              subtitle,
                              style: GoogleFonts.robotoMono(
                                color: Colors.white60,
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                              ),
                              softWrap: true,
                            ),
                            if (mainMetric.isNotEmpty) ...[
                              const SizedBox(height: 9),
                              Align(
                                alignment: Alignment.centerLeft,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 9,
                                    vertical: 5,
                                  ),
                                  decoration: BoxDecoration(
                                    color: color.withAlpha(20),
                                    borderRadius: BorderRadius.circular(4),
                                    border: Border.all(
                                      color: color.withAlpha(120),
                                    ),
                                  ),
                                  child: Text(
                                    mainMetric,
                                    style: GoogleFonts.oxanium(
                                      color: color,
                                      fontWeight: FontWeight.w900,
                                      fontSize: 11,
                                      letterSpacing: 0.7,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          ..._buildTimelineExpandedContent(
                            entry: current,
                            color: color,
                            dogId: dogId,
                            dogName: dogName,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
