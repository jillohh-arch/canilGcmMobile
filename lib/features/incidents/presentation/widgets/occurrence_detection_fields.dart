import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:canil_gcm/widgets/hud_controls.dart';
import 'package:canil_gcm/widgets/tactical_text_field.dart';

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
        Text(
          'ENTORPECENTES LOCALIZADOS',
          style: GoogleFonts.inter(
            fontSize: 10,
            fontWeight: FontWeight.w800,
            color: Colors.white54,
            letterSpacing: 1.0,
          ),
        ),
        const SizedBox(height: 12),
        ...List.generate(drugs.length, _buildDrugRow),
        OutlinedButton.icon(
          onPressed: onAddDrug,
          icon: const Icon(Icons.add, size: 16, color: Colors.white),
          label: Text(
            'ADICIONAR ENTORPECENTE',
            style: GoogleFonts.inter(
              fontSize: 10,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          style: OutlinedButton.styleFrom(
            side: const BorderSide(color: Colors.white24),
          ),
        ),
        const SizedBox(height: 24),
        TacticalTextField(
          controller: supportTeamController,
          labelText: 'Equipe de Apoio (GCMs)',
          prefixIcon: Icons.group,
        ),
        const SizedBox(height: 16),
        TacticalTextField(
          controller: reportNumberController,
          labelText: 'Número do BO',
          prefixIcon: Icons.assignment,
        ),
        const SizedBox(height: 24),
      ],
    );
  }

  Widget _buildDrugRow(int index) {
    final drug = drugs[index];
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Expanded(
            flex: 2,
            child: HudSelectField<String>(
              label: 'Entorpecente',
              icon: Icons.science_rounded,
              value: drugOptions.contains(drug['tipo'])
                  ? drug['tipo'] as String?
                  : 'Outros',
              placeholder: 'Tipo',
              accent: accentColor,
              items: drugOptions,
              labelBuilder: (item) => item,
              onChanged: (value) {
                if (value != null) {
                  onDrugTypeChanged(drug, value);
                }
              },
            ),
          ),
          const SizedBox(width: 8),
          if (drug['tipo'] == 'Outros')
            Expanded(
              flex: 2,
              child: TacticalTextField(
                controller: drug['especificar'],
                labelText: 'Especificar',
              ),
            ),
          if (drug['tipo'] == 'Outros') const SizedBox(width: 8),
          Expanded(
            child: TacticalTextField(
              controller: drug['quantidade'],
              labelText: 'Qtd/G',
              keyboardType: TextInputType.number,
            ),
          ),
          IconButton(
            icon: const Icon(Icons.remove_circle, color: Colors.redAccent),
            onPressed: () => onRemoveDrug(index),
          ),
        ],
      ),
    );
  }
}
