part of 'daily_timeline_screen.dart';

extension _DailyTimelineProgressHelpers on _DailyTimelineScreenState {
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

  String _formatProgressTimestamp(DateTime? timestamp) {
    if (timestamp == null) return '';

    final day = timestamp.day.toString().padLeft(2, '0');
    final month = timestamp.month.toString().padLeft(2, '0');
    final hour = timestamp.hour.toString().padLeft(2, '0');
    final minute = timestamp.minute.toString().padLeft(2, '0');
    return '$day/$month $hour:$minute';
  }

  String _resolveProgressAuthorLabel(Map stepMap) {
    final authorName = stepMap['authorName']?.toString().trim() ?? '';
    final authorId = stepMap['authorId']?.toString().trim() ?? '';

    if (authorName.isNotEmpty) return authorName;
    if (authorId.isNotEmpty) return 'RA $authorId';
    return '';
  }
}
