part of 'occurrence_event_center_sheet.dart';

// ignore_for_file: invalid_use_of_protected_member

extension _OccurrenceEventCenterTabs on _OccurrenceEventCenterSheetState {
  Widget _buildCategoryTabs() {
    return SizedBox(
      height: 48,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: widget.categories.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final category = widget.categories[index];
          return _EventCategoryPill(
            category: category,
            panelColor: widget.panelColor,
            selected: index == _selectedIndex,
            onTap: () => _selectCategory(index),
          );
        },
      ),
    );
  }

  void _selectCategory(int index) {
    HapticFeedback.selectionClick();
    setState(() => _selectedIndex = index);
  }
}
