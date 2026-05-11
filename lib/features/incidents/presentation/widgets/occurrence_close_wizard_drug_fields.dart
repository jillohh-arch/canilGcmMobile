part of 'occurrence_close_wizard.dart';

extension _OccurrenceCloseWizardDrugFields on _OccurrenceCloseWizardState {
  Widget _drugRowsField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ...List.generate(_drugEntries.length, _buildDrugEntryRow),
        const SizedBox(height: 4),
        _addDrugEntryButton(),
      ],
    );
  }
}
