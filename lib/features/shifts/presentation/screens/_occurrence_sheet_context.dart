part of 'dynamic_activity_sheet.dart';

// ignore_for_file: invalid_use_of_protected_member

extension _OccurrenceSheetContext on _DynamicActivitySheetState {
  Widget _buildOccurrenceActiveContextSummary(Color tColor) {
    final startedAt = _occurrenceStartedAt() ?? _resolveFormTimestamp();
    final startedLabel = _formatTimeOfDay(startedAt);
    final location = _locationController.text.trim().isEmpty
        ? 'Local pendente'
        : _locationController.text.trim();
    final team = _equipeController.text.trim().isEmpty
        ? 'Equipe pendente'
        : _equipeController.text.trim();

    return OccurrenceActiveContextSummary(
      accentColor: tColor,
      panelColor: _kHudPanel,
      backgroundColor: _kHudBackground,
      location: location,
      team: team,
      startedLabel: startedLabel,
      onEdit: () => _showOccurrenceInitialDataSheet(tColor),
    );
  }
}
