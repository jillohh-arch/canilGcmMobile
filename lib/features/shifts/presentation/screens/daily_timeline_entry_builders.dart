part of 'daily_timeline_screen.dart';

extension _DailyTimelineEntryBuilders on _DailyTimelineScreenState {
  String _resolveTimelineDogName(String dogId, DogViewModel dogVM) {
    for (final dog in dogVM.dogs) {
      if (dog.id == dogId) return dog.name;
    }

    return 'K9';
  }

  ({DateTime start, DateTime end}) _selectedTimelineDayRange() {
    final start = DateTime(
      _selectedDate.year,
      _selectedDate.month,
      _selectedDate.day,
    );

    return (start: start, end: start.add(const Duration(days: 1)));
  }

  bool _isWithinSelectedTimelineDay(
    DateTime date,
    ({DateTime start, DateTime end}) range,
  ) {
    return !date.isBefore(range.start) && date.isBefore(range.end);
  }
}
