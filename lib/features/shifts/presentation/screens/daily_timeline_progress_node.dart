part of 'daily_timeline_screen.dart';

extension _DailyTimelineProgressNode on _DailyTimelineScreenState {
  Widget _buildIncidentProgressNode({
    required dynamic step,
    required int index,
    required bool isLast,
    required Color accent,
  }) {
    final stepMap = step is Map ? step : <String, dynamic>{};
    final title = (stepMap['title']?.toString().trim().isNotEmpty ?? false)
        ? stepMap['title'].toString().trim()
        : 'Atualização operacional';
    final description = stepMap['description']?.toString().trim() ?? '';
    final progressStyle = _resolveIncidentProgressStyle(title, description);
    final ts = _coerceTimelineDate(stepMap['timestamp']);
    final tsLabel = _formatProgressTimestamp(ts);
    final location = stepMap['location']?.toString().trim() ?? '';
    final authorLabel = _resolveProgressAuthorLabel(stepMap);

    return Padding(
      padding: EdgeInsets.only(bottom: isLast ? 8 : 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 34,
            child: Column(
              children: [
                Container(
                  width: 30,
                  height: 30,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: progressStyle.iconBackground,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                      color: progressStyle.iconColor.withAlpha(170),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: progressStyle.iconColor.withAlpha(70),
                        blurRadius: 14,
                      ),
                    ],
                  ),
                  child: Icon(
                    progressStyle.icon,
                    size: 15,
                    color: progressStyle.iconColor,
                  ),
                ),
                if (!isLast)
                  Container(
                    width: 2,
                    height: 58,
                    margin: const EdgeInsets.only(top: 6),
                    decoration: BoxDecoration(
                      color: progressStyle.borderColor.withAlpha(120),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: progressStyle.backgroundColor.withAlpha(225),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(
                  color: progressStyle.borderColor.withAlpha(185),
                ),
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    progressStyle.borderColor.withAlpha(32),
                    const Color(0xFF0B1020),
                    const Color(0xFF070B14),
                  ],
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'ETAPA ${(index + 1).toString().padLeft(2, '0')}',
                        style: GoogleFonts.robotoMono(
                          color: accent.withAlpha(210),
                          fontSize: 9,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 0.9,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          title.toUpperCase(),
                          style: GoogleFonts.oxanium(
                            color: progressStyle.titleColor,
                            fontSize: 12,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 0.8,
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (authorLabel.isNotEmpty ||
                      tsLabel.isNotEmpty ||
                      location.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        if (authorLabel.isNotEmpty)
                          _buildProgressMetaChip(
                            icon: Icons.badge_outlined,
                            label: authorLabel,
                            color: progressStyle.iconColor,
                          ),
                        if (tsLabel.isNotEmpty)
                          _buildProgressMetaChip(
                            icon: Icons.schedule_rounded,
                            label: tsLabel,
                            color: progressStyle.iconColor,
                          ),
                        if (location.isNotEmpty)
                          _buildProgressMetaChip(
                            icon: Icons.place_outlined,
                            label: location,
                            color: progressStyle.iconColor,
                          ),
                      ],
                    ),
                  ],
                  if (description.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    Text(
                      description,
                      style: GoogleFonts.inter(
                        color: Colors.white70,
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        height: 1.4,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
