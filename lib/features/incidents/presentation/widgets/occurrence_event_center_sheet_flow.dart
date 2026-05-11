part of 'occurrence_event_center_sheet.dart';

extension _OccurrenceEventCenterFlow on _OccurrenceEventCenterSheetState {
  void _submitCustomEvent(BuildContext context, Color color) {
    final description = widget.controller.text.trim();
    if (description.isEmpty) {
      widget.focusNode.requestFocus();
      return;
    }

    _selectAction(
      context,
      OccurrenceQuickAction(
        title: 'Evento personalizado',
        description: description,
        icon: Icons.edit_note_rounded,
        color: color,
      ),
    );
  }

  void _selectAction(BuildContext context, OccurrenceQuickAction action) {
    Navigator.of(context).pop();
    widget.onActionSelected(action);
  }
}
