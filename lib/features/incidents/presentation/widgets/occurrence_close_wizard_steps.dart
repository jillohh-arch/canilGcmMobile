part of 'occurrence_close_wizard.dart';

extension _OccurrenceCloseWizardSteps on _OccurrenceCloseWizardState {
  Widget _buildStep() {
    return switch (_currentStep) {
      0 => _buildReportStep(),
      1 => _buildResultStep(),
      _ => _buildDetailsStep(),
    };
  }
}
