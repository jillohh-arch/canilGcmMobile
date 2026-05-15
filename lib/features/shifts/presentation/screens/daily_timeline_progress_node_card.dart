part of 'daily_timeline_screen.dart';

extension _DailyTimelineProgressNodeCard on _DailyTimelineScreenState {
  Widget _buildProgressNodeCard({
    required int index,
    required String title,
    required String description,
    required String authorLabel,
    required String timestampLabel,
    required String location,
    required Color accent,
    required _IncidentProgressStyle progressStyle,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: progressStyle.backgroundColor.withAlpha(225),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: progressStyle.borderColor.withAlpha(185)),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            progressStyle.borderColor.withAlpha(32),
            const Color(0xFF0B1020),
            AppTheme.background,
          ],
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildProgressNodeHeader(
            index: index,
            title: title,
            accent: accent,
            progressStyle: progressStyle,
          ),
          ..._buildProgressNodeMeta(
            authorLabel: authorLabel,
            timestampLabel: timestampLabel,
            location: location,
            progressStyle: progressStyle,
          ),
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
    );
  }
}
