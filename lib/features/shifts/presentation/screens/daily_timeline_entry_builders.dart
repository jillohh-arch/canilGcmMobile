part of 'daily_timeline_screen.dart';

extension _DailyTimelineEntryBuilders on _DailyTimelineScreenState {
  String _resolveTimelineDogName(String dogId, DogViewModel dogVM) {
    return dogVM.dogs
        .firstWhere(
          (dog) => dog.id == dogId,
          orElse: () => dogVM.dogs.isNotEmpty
              ? dogVM.dogs.first
              : throw Exception('Cão não encontrado'),
        )
        .name;
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
