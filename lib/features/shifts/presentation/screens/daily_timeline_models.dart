part of 'daily_timeline_screen.dart';

class _IncidentQuickProgressShortcut {
  final String title;
  final String template;

  const _IncidentQuickProgressShortcut({
    required this.title,
    required this.template,
  });
}

class _IncidentProgressStyle {
  final IconData icon;
  final Color iconColor;
  final Color iconBackground;
  final Color titleColor;
  final Color backgroundColor;
  final Color borderColor;

  const _IncidentProgressStyle({
    required this.icon,
    required this.iconColor,
    required this.iconBackground,
    required this.titleColor,
    required this.backgroundColor,
    required this.borderColor,
  });
}

class _IncidentBadgeStyle {
  final IconData icon;
  final Color iconColor;
  final Color textColor;
  final Color backgroundColor;
  final Color borderColor;

  const _IncidentBadgeStyle({
    required this.icon,
    required this.iconColor,
    required this.textColor,
    required this.backgroundColor,
    required this.borderColor,
  });
}

class _TimelineEntry {
  final String? id;
  final String category;
  final dynamic originalModel;
  final DateTime time;
  final String title;
  final String location;
  final String type;
  final Map<String, dynamic> details;

  _TimelineEntry({
    this.id,
    required this.category,
    this.originalModel,
    required this.time,
    required this.title,
    required this.location,
    required this.type,
    required this.details,
  });
}

class _TimelineListData {
  final List<_TimelineEntry> entries;
  final String dogName;
  final bool hasOpenIncidents;

  const _TimelineListData({
    required this.entries,
    required this.dogName,
    required this.hasOpenIncidents,
  });
}

class _TimelineTilePresentation {
  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  final String mainMetric;

  const _TimelineTilePresentation({
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
    required this.mainMetric,
  });
}

typedef _DailyTrainingSummary = ({
  double minutes,
  String? primaryCategory,
  Set<String> categories,
});

final _hudBackground = AppTheme.background;
const _hudPanel = const Color(0xFF0E1A1F);
final _hudCyan = AppTheme.primary;
const _hudAmber = Color(0xFFFBBF24);
