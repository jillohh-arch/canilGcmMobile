part of 'daily_timeline_screen.dart';

extension _DailyTimelineIncidentProgressShortcuts on _DailyTimelineScreenState {
  List<_IncidentQuickProgressShortcut> _quickProgressShortcutsForSubtype(
    String? subtype,
  ) {
    final typeShortcuts = _typeProgressShortcutsForSubtype(subtype);
    if (typeShortcuts.isEmpty) {
      return _commonIncidentProgressShortcuts;
    }

    return [...typeShortcuts, ..._commonIncidentProgressShortcuts];
  }
}
