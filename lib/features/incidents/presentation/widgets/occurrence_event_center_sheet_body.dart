part of 'occurrence_event_center_sheet.dart';

extension _OccurrenceEventCenterBody on _OccurrenceEventCenterSheetState {
  Widget _buildSheetBody(
    BuildContext context,
    OccurrenceEventCategory selectedCategory,
  ) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _EventCenterHeader(
          accentColor: widget.accentColor,
          onClose: () => Navigator.of(context).pop(),
        ),
        const SizedBox(height: 10),
        _buildCategoryTabs(),
        const SizedBox(height: 14),
        _EventSuggestionsTitle(category: selectedCategory),
        const SizedBox(height: 10),
        ...selectedCategory.actions.map(
          (action) => _EventActionTile(
            action: action,
            panelColor: widget.panelColor,
            onTap: () => _selectAction(context, action),
          ),
        ),
        const SizedBox(height: 12),
        _CustomEventComposer(
          controller: widget.controller,
          focusNode: widget.focusNode,
          accentColor: widget.accentColor,
          backgroundColor: widget.backgroundColor,
          onSubmit: () => _submitCustomEvent(context, selectedCategory.color),
        ),
      ],
    );
  }
}

class _EventSuggestionsTitle extends StatelessWidget {
  final OccurrenceEventCategory category;

  const _EventSuggestionsTitle({required this.category});

  @override
  Widget build(BuildContext context) {
    return Text(
      'EVENTOS SUGERIDOS',
      style: GoogleFonts.inter(
        color: category.color,
        fontSize: 10,
        fontWeight: FontWeight.w900,
        letterSpacing: 1.4,
      ),
    );
  }
}
