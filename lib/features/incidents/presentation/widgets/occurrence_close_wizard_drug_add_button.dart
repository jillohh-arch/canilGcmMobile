part of 'occurrence_close_wizard.dart';

extension _OccurrenceCloseWizardDrugAddButton on _OccurrenceCloseWizardState {
  Widget _addDrugEntryButton() {
    return OutlinedButton.icon(
      onPressed: widget.isSaving
          ? null
          : () {
              HapticFeedback.selectionClick();
              _addDrugEntry();
            },
      icon: const Icon(Icons.add_rounded, size: 18),
      label: Text(
        'ADICIONAR ENTORPECENTE',
        style: GoogleFonts.robotoMono(
          fontSize: 11,
          fontWeight: FontWeight.w900,
          letterSpacing: 1.0,
        ),
      ),
      style: OutlinedButton.styleFrom(
        foregroundColor: _OccurrenceCloseWizardState._cyan,
        side: BorderSide(
          color: _OccurrenceCloseWizardState._cyan.withAlpha(120),
        ),
        padding: const EdgeInsets.symmetric(vertical: 13),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    );
  }
}
