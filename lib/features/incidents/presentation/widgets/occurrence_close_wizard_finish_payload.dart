part of 'occurrence_close_wizard.dart';

extension _OccurrenceCloseWizardFinishPayload on _OccurrenceCloseWizardState {
  Map<String, dynamic> _buildFinishDetails() {
    final details = <String, dynamic>{};
    _detailControllers.forEach((key, controller) {
      details[key] = controller.text.trim();
    });

    if (_selectedResults.contains('Droga apreendida')) {
      _writeDrugDetails(details);
    }

    return details;
  }

  void _writeDrugDetails(Map<String, dynamic> details) {
    final drugs = _drugEntries
        .map(
          (entry) => {
            'tipo': entry.type,
            'quantidade': entry.quantityController.text.trim(),
          },
        )
        .where(
          (entry) =>
              entry['tipo']!.trim().isNotEmpty ||
              entry['quantidade']!.trim().isNotEmpty,
        )
        .toList();

    details['drogas'] = drugs;
    if (drugs.isEmpty) return;

    details['droga_tipo'] = drugs.first['tipo'];
    details['droga_quantidade'] = drugs.first['quantidade'];
  }
}
