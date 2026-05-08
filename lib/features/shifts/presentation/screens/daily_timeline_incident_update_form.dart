part of 'daily_timeline_screen.dart';

extension _DailyTimelineIncidentUpdateForm on _DailyTimelineScreenState {
  Widget _buildIncidentUpdateSheetContent({
    required BuildContext sheetContext,
    required Incident incident,
    required List<_IncidentQuickProgressShortcut> shortcuts,
    required String? selectedShortcut,
    required Set<String> selectedOutcomes,
    required TextEditingController noteController,
    required void Function(
      _IncidentQuickProgressShortcut shortcut,
      bool isSelected,
    )
    onShortcutSelected,
    required void Function(String outcome, bool isSelected) onOutcomeSelected,
    required Future<void> Function() onSave,
  }) {
    return Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        bottom: MediaQuery.of(sheetContext).viewInsets.bottom + 16,
        top: 16,
      ),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: const Color(0xFF0F1923),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: const Color(0xFF4ECDE4).withAlpha(60)),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF4ECDE4).withAlpha(15),
              blurRadius: 24,
              spreadRadius: 2,
            ),
          ],
        ),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildIncidentUpdateHeader(incident),
              ..._buildIncidentUpdateShortcutSection(
                shortcuts: shortcuts,
                selectedShortcut: selectedShortcut,
                onShortcutSelected: onShortcutSelected,
              ),
              const SizedBox(height: 18),
              _buildIncidentUpdateOutcomeSection(
                incident: incident,
                selectedOutcomes: selectedOutcomes,
                onOutcomeSelected: onOutcomeSelected,
              ),
              const SizedBox(height: 18),
              _buildIncidentUpdateNoteField(noteController),
              const SizedBox(height: 18),
              _buildIncidentUpdateActions(
                sheetContext: sheetContext,
                onSave: onSave,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
