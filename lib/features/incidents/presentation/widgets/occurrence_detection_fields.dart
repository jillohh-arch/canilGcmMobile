import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:canil_gcm/core/widgets/hud_controls.dart';
import 'package:canil_gcm/core/widgets/tactical_text_field.dart';

part 'occurrence_detection_drug_list.dart';
part 'occurrence_detection_support_fields.dart';

class OccurrenceDetectionFields extends StatelessWidget {
  final List<Map<String, dynamic>> drugs;
  final List<String> drugOptions;
  final Color accentColor;
  final TextEditingController supportTeamController;
  final TextEditingController reportNumberController;
  final VoidCallback onAddDrug;
  final ValueChanged<int> onRemoveDrug;
  final void Function(Map<String, dynamic> drug, String type) onDrugTypeChanged;

  const OccurrenceDetectionFields({
    super.key,
    required this.drugs,
    required this.drugOptions,
    required this.accentColor,
    required this.supportTeamController,
    required this.reportNumberController,
    required this.onAddDrug,
    required this.onRemoveDrug,
    required this.onDrugTypeChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _DetectionDrugList(
          drugs: drugs,
          drugOptions: drugOptions,
          accentColor: accentColor,
          onAddDrug: onAddDrug,
          onRemoveDrug: onRemoveDrug,
          onDrugTypeChanged: onDrugTypeChanged,
        ),
        const SizedBox(height: 24),
        _DetectionSupportFields(
          supportTeamController: supportTeamController,
          reportNumberController: reportNumberController,
        ),
        const SizedBox(height: 24),
      ],
    );
  }
}
