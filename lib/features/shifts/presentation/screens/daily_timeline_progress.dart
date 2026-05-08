part of 'daily_timeline_screen.dart';

extension _DailyTimelineProgress on _DailyTimelineScreenState {
  Widget _buildIncidentProgressTimeline({
    required List updates,
    required Color accent,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(10, 12, 10, 4),
      decoration: BoxDecoration(
        color: const Color(0xFF070B14).withAlpha(230),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: accent.withAlpha(95)),
        boxShadow: [
          BoxShadow(
            color: accent.withAlpha(24),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        children: [
          for (var index = 0; index < updates.length; index++)
            _buildIncidentProgressNode(
              step: updates[index],
              index: index,
              isLast: index == updates.length - 1,
              accent: accent,
            ),
        ],
      ),
    );
  }

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
    final rawTimestamp = stepMap['timestamp'];
    final ts = _coerceTimelineDate(rawTimestamp);
    final tsLabel = ts == null
        ? ''
        : '${ts.day.toString().padLeft(2, '0')}/${ts.month.toString().padLeft(2, '0')} ${ts.hour.toString().padLeft(2, '0')}:${ts.minute.toString().padLeft(2, '0')}';
    final location = stepMap['location']?.toString().trim() ?? '';
    final authorName = stepMap['authorName']?.toString().trim() ?? '';
    final authorId = stepMap['authorId']?.toString().trim() ?? '';
    final authorLabel = authorName.isNotEmpty
        ? authorName
        : authorId.isNotEmpty
        ? 'RA $authorId'
        : '';

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

  Widget _buildProgressMetaChip({
    required IconData icon,
    required String label,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: color.withAlpha(18),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withAlpha(85)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color.withAlpha(210), size: 12),
          const SizedBox(width: 5),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 180),
            child: Text(
              label,
              style: GoogleFonts.robotoMono(
                color: Colors.white60,
                fontSize: 9,
                fontWeight: FontWeight.w700,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  DateTime? _coerceTimelineDate(dynamic value) {
    if (value == null) return null;
    if (value is DateTime) return value;
    if (value is String) return DateTime.tryParse(value);

    try {
      final dynamic maybeTimestamp = value;
      final converted = maybeTimestamp.toDate();
      if (converted is DateTime) {
        return converted;
      }
    } catch (_) {
      return null;
    }

    return null;
  }
}
