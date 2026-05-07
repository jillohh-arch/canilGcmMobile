import 'package:flutter/material.dart';

import 'package:canil_gcm/core/domain/activity_subtype_ids.dart';
import 'occurrence_category_fields.dart';
import 'occurrence_detection_fields.dart';

class OccurrenceSpecificFields extends StatelessWidget {
  final String? subtype;
  final Map<String, dynamic> formData;
  final List<Map<String, dynamic>> drugs;
  final List<String> drugOptions;
  final Color accentColor;
  final Color detectionAccentColor;
  final TextEditingController supportTeamController;
  final TextEditingController reportNumberController;
  final TextEditingController garrisonController;
  final TextEditingController situationController;
  final TextEditingController outcomeController;
  final TextEditingController odorObjectController;
  final TextEditingController missingTimeController;
  final TextEditingController durationController;
  final TextEditingController terrainConditionController;
  final TextEditingController orderNumberController;
  final TextEditingController audienceController;
  final TextEditingController themeController;
  final VoidCallback onAddDrug;
  final ValueChanged<int> onRemoveDrug;
  final void Function(Map<String, dynamic> drug, String? type)
  onDrugTypeChanged;
  final ValueChanged<String?> onSearchTypeChanged;
  final VoidCallback onPullWeather;

  const OccurrenceSpecificFields({
    super.key,
    required this.subtype,
    required this.formData,
    required this.drugs,
    required this.drugOptions,
    required this.accentColor,
    required this.detectionAccentColor,
    required this.supportTeamController,
    required this.reportNumberController,
    required this.garrisonController,
    required this.situationController,
    required this.outcomeController,
    required this.odorObjectController,
    required this.missingTimeController,
    required this.durationController,
    required this.terrainConditionController,
    required this.orderNumberController,
    required this.audienceController,
    required this.themeController,
    required this.onAddDrug,
    required this.onRemoveDrug,
    required this.onDrugTypeChanged,
    required this.onSearchTypeChanged,
    required this.onPullWeather,
  });

  static bool handles(String? subtype) {
    return subtype == ActivitySubtypeIds.detection ||
        subtype == ActivitySubtypeIds.supportVehicle ||
        subtype == ActivitySubtypeIds.missingPerson ||
        subtype == ActivitySubtypeIds.serviceOrder ||
        subtype == ActivitySubtypeIds.event;
  }

  @override
  Widget build(BuildContext context) {
    return switch (subtype) {
      ActivitySubtypeIds.detection => OccurrenceDetectionFields(
        drugs: drugs,
        drugOptions: drugOptions,
        accentColor: detectionAccentColor,
        supportTeamController: supportTeamController,
        reportNumberController: reportNumberController,
        onAddDrug: onAddDrug,
        onRemoveDrug: onRemoveDrug,
        onDrugTypeChanged: onDrugTypeChanged,
      ),
      ActivitySubtypeIds.supportVehicle => OccurrenceSupportVehicleFields(
        garrisonController: garrisonController,
        situationController: situationController,
        outcomeController: outcomeController,
      ),
      ActivitySubtypeIds.missingPerson => OccurrenceMissingPersonFields(
        searchCaptureSubtype: ActivitySubtypeIds.searchCapture,
        selectedSearchType: formData['Tipo de Busca'] as String?,
        accentColor: accentColor,
        odorObjectController: odorObjectController,
        missingTimeController: missingTimeController,
        durationController: durationController,
        terrainConditionController: terrainConditionController,
        onPullWeather: onPullWeather,
        onSearchTypeChanged: onSearchTypeChanged,
      ),
      ActivitySubtypeIds.serviceOrder => OccurrenceServiceOrderFields(
        orderNumberController: orderNumberController,
      ),
      ActivitySubtypeIds.event => OccurrenceEventFields(
        audienceController: audienceController,
        themeController: themeController,
      ),
      _ => const SizedBox.shrink(),
    };
  }
}
