// ignore_for_file: invalid_use_of_protected_member

part of 'daily_timeline_screen.dart';

extension _DailyTimelineEvolutionFilterChips on _DailyTimelineScreenState {
  Widget _buildTrainingFilterChips() {
    return SizedBox(
      height: 48,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        children: [
          _FilterChip(
            label: 'Todos',
            selected: _selectedTrainingFilter == null,
            onTap: () {
              HapticFeedback.selectionClick();
              setState(() => _selectedTrainingFilter = null);
            },
          ),
          ..._trainingCategories.map(
            (cat) => Padding(
              padding: const EdgeInsets.only(left: 8),
              child: _FilterChip(
                label: cat,
                selected: _selectedTrainingFilter == cat,
                onTap: () {
                  HapticFeedback.selectionClick();
                  setState(
                    () => _selectedTrainingFilter =
                        _selectedTrainingFilter == cat ? null : cat,
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}
