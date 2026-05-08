// ignore_for_file: invalid_use_of_protected_member

part of 'daily_timeline_screen.dart';

extension _DailyTimelineDateSelector on _DailyTimelineScreenState {
  Widget _buildDateSelector() {
    return Container(
      height: 96,
      margin: const EdgeInsets.symmetric(vertical: 6),
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        reverse: true,
        itemCount: 31,
        itemBuilder: (context, index) {
          final date = DateTime.now().subtract(Duration(days: index));
          final isSelected = _isSelectedTimelineDate(date);

          return _TimelineDateChip(
            date: date,
            isSelected: isSelected,
            onTap: () {
              HapticFeedback.selectionClick();
              setState(() => _selectedDate = date);
            },
          );
        },
      ),
    );
  }

  bool _isSelectedTimelineDate(DateTime date) {
    return date.year == _selectedDate.year &&
        date.month == _selectedDate.month &&
        date.day == _selectedDate.day;
  }
}
