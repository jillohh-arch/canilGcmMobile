import 'package:flutter/material.dart';

import 'hud_controls.dart';
import 'tactical_text_field.dart';

class HealthActivityFields extends StatelessWidget {
  final String? subtype;
  final String consultationSubtype;
  final String vaccineSubtype;
  final String examSubtype;
  final String bathSubtype;
  final Color accentColor;
  final TextEditingController responsibleController;
  final TextEditingController reasonController;
  final TextEditingController vaccineTypeController;
  final TextEditingController examTypeController;
  final TextEditingController bathProductsController;
  final TextEditingController returnDateController;
  final String? selectedVaccine;
  final ValueChanged<String?> onVaccineChanged;
  final VoidCallback onPickReturnDate;

  const HealthActivityFields({
    super.key,
    required this.subtype,
    required this.consultationSubtype,
    required this.vaccineSubtype,
    required this.examSubtype,
    required this.bathSubtype,
    required this.accentColor,
    required this.responsibleController,
    required this.reasonController,
    required this.vaccineTypeController,
    required this.examTypeController,
    required this.bathProductsController,
    required this.returnDateController,
    required this.selectedVaccine,
    required this.onVaccineChanged,
    required this.onPickReturnDate,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 16),
        TacticalTextField(
          controller: responsibleController,
          labelText: subtype == bathSubtype
              ? 'Nome do(a) Responsável'
              : 'Nome do(a) Veterinário(a)',
          prefixIcon: Icons.person_rounded,
        ),
        if (subtype == consultationSubtype || subtype == examSubtype) ...[
          const SizedBox(height: 24),
          TacticalTextField(
            controller: reasonController,
            labelText: 'Motivo',
            prefixIcon: Icons.info_outline_rounded,
          ),
        ],
        if (subtype == vaccineSubtype) ...[
          const SizedBox(height: 16),
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: HudSelectField<String>(
              label: 'Tipo de Vacina *',
              icon: Icons.vaccines_outlined,
              value: selectedVaccine,
              placeholder: 'Selecione o tipo de vacina',
              accent: accentColor,
              items: const [
                'V10/V8',
                'Antirrábica',
                'Giárdia',
                'Gripe Canina',
                'Leishmaniose',
                'Outra',
              ],
              labelBuilder: (item) => item,
              onChanged: onVaccineChanged,
            ),
          ),
        ],
        if (subtype == examSubtype) ...[
          const SizedBox(height: 16),
          TacticalTextField(
            controller: examTypeController,
            labelText: 'Tipo de Exame',
            prefixIcon: Icons.biotech_rounded,
          ),
        ],
        if (subtype == bathSubtype) ...[
          const SizedBox(height: 16),
          TacticalTextField(
            controller: bathProductsController,
            labelText: 'Produtos Utilizados (para controle de alergias)',
            prefixIcon: Icons.spa_rounded,
          ),
        ],
        if (subtype == consultationSubtype || subtype == vaccineSubtype) ...[
          const SizedBox(height: 24),
          TacticalTextField(
            controller: returnDateController,
            keyboardType: TextInputType.datetime,
            readOnly: true,
            onTap: onPickReturnDate,
            labelText: subtype == vaccineSubtype
                ? 'Data da Próxima Dose *'
                : 'Data de Retorno (Opcional)',
            prefixIcon: Icons.calendar_month_rounded,
          ),
        ],
      ],
    );
  }
}
