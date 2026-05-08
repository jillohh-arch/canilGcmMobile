part of 'daily_timeline_screen.dart';

extension _DailyTimelineIncidentCloseForm on _DailyTimelineScreenState {
  Widget _buildIncidentCloseSheetContent({
    required BuildContext sheetContext,
    required Incident incident,
    required TextEditingController noteController,
    required Set<String> selectedOutcomes,
    required bool operationalSuccess,
    required ValueChanged<bool> onOperationalSuccessChanged,
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
          color: const Color(0xFF161618),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: Colors.white10),
        ),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildIncidentQuickSheetHeader(
                title: 'ENCERRAR OCORRÊNCIA',
                incident: incident,
                badgeStyle: const _IncidentBadgeStyle(
                  icon: Icons.task_alt_rounded,
                  iconColor: Color(0xFF4ADE80),
                  textColor: Color(0xFF86EFAC),
                  backgroundColor: Color(0x144ADE80),
                  borderColor: Color(0x334ADE80),
                ),
              ),
              const SizedBox(height: 18),
              _buildIncidentCloseOperationalOutcomeSection(
                operationalSuccess: operationalSuccess,
                onChanged: onOperationalSuccessChanged,
              ),
              const SizedBox(height: 18),
              _buildIncidentCloseResultsSection(
                incident: incident,
                selectedOutcomes: selectedOutcomes,
                onOutcomeSelected: onOutcomeSelected,
              ),
              const SizedBox(height: 18),
              _buildIncidentCloseNoteField(noteController),
              const SizedBox(height: 18),
              _buildIncidentCloseActions(
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
