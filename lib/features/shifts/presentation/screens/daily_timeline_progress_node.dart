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
          _buildProgressNodeRail(isLast: isLast, progressStyle: progressStyle),
          const SizedBox(width: 10),
          Expanded(
            child: _buildProgressNodeCard(
              index: index,
              title: title,
              description: description,
              authorLabel: authorLabel,
              timestampLabel: tsLabel,
              location: location,
              accent: accent,
              progressStyle: progressStyle,
            ),
          ),
        ],
      ),
    );
  }
}
