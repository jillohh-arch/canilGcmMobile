part of 'daily_timeline_screen.dart';

extension _DailyTimelineProgressNodeMeta on _DailyTimelineScreenState {
  List<Widget> _buildProgressNodeMeta({
    required String authorLabel,
    required String timestampLabel,
    required String location,
    required _IncidentProgressStyle progressStyle,
  }) {
    if (authorLabel.isEmpty && timestampLabel.isEmpty && location.isEmpty) {
      return const [];
    }

    return [
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
          if (timestampLabel.isNotEmpty)
            _buildProgressMetaChip(
              icon: Icons.schedule_rounded,
              label: timestampLabel,
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
    ];
  }
}
