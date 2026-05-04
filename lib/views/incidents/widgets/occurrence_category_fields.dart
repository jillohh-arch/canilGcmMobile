import 'package:flutter/material.dart';

import '../../../widgets/activity_weather_button.dart';
import '../../../widgets/hud_chip_group.dart';
import '../../../widgets/tactical_text_field.dart';

class OccurrenceSupportVehicleFields extends StatelessWidget {
  final TextEditingController garrisonController;
  final TextEditingController situationController;
  final TextEditingController outcomeController;

  const OccurrenceSupportVehicleFields({
    super.key,
    required this.garrisonController,
    required this.situationController,
    required this.outcomeController,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        TacticalTextField(
          controller: garrisonController,
          labelText: 'Guarnição apoiada',
          prefixIcon: Icons.local_police,
        ),
        const SizedBox(height: 16),
        TacticalTextField(
          controller: situationController,
          labelText: 'Situação encontrada',
          prefixIcon: Icons.warning,
        ),
        const SizedBox(height: 16),
        TacticalTextField(
          controller: outcomeController,
          labelText: 'Desfecho da intervenção',
          prefixIcon: Icons.check_circle,
        ),
        const SizedBox(height: 24),
      ],
    );
  }
}

class OccurrenceMissingPersonFields extends StatelessWidget {
  final String searchCaptureSubtype;
  final String? selectedSearchType;
  final Color accentColor;
  final TextEditingController odorObjectController;
  final TextEditingController missingTimeController;
  final TextEditingController durationController;
  final TextEditingController terrainConditionController;
  final ValueChanged<String?> onSearchTypeChanged;
  final VoidCallback onPullWeather;

  const OccurrenceMissingPersonFields({
    super.key,
    required this.searchCaptureSubtype,
    required this.selectedSearchType,
    required this.accentColor,
    required this.odorObjectController,
    required this.missingTimeController,
    required this.durationController,
    required this.terrainConditionController,
    required this.onSearchTypeChanged,
    required this.onPullWeather,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        HudToggleChipGroup(
          label: 'Tipo de Busca',
          options: [searchCaptureSubtype, 'Pessoa Desaparecida'],
          selectedOption: selectedSearchType,
          accent: accentColor,
          onChanged: onSearchTypeChanged,
        ),
        TacticalTextField(
          controller: odorObjectController,
          labelText: 'Objeto Fonte de Odor',
          prefixIcon: Icons.search,
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: TacticalTextField(
                controller: missingTimeController,
                labelText: 'Tempo Desaparecido',
                prefixIcon: Icons.access_time,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: TacticalTextField(
                controller: durationController,
                labelText: 'Duração (Busca)',
                prefixIcon: Icons.timer,
                keyboardType: TextInputType.number,
              ),
            ),
          ],
        ),
        const SizedBox(height: 24),
        TacticalTextField(
          controller: terrainConditionController,
          labelText: 'Condições / Terreno',
          prefixIcon: Icons.terrain,
        ),
        const SizedBox(height: 12),
        ActivityWeatherButton(
          label: 'PUXAR CLIMA ATUAL (GPS)',
          onPressed: onPullWeather,
          backgroundColor: const Color(0xFF1B8A4C),
        ),
        const SizedBox(height: 24),
      ],
    );
  }
}

class OccurrenceServiceOrderFields extends StatelessWidget {
  final TextEditingController orderNumberController;

  const OccurrenceServiceOrderFields({
    super.key,
    required this.orderNumberController,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        TacticalTextField(
          controller: orderNumberController,
          labelText: 'Número da Ordem de Serviço',
          prefixIcon: Icons.numbers,
        ),
        const SizedBox(height: 24),
      ],
    );
  }
}

class OccurrenceEventFields extends StatelessWidget {
  final TextEditingController audienceController;
  final TextEditingController themeController;

  const OccurrenceEventFields({
    super.key,
    required this.audienceController,
    required this.themeController,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        TacticalTextField(
          controller: audienceController,
          keyboardType: TextInputType.number,
          labelText: 'Público estimado',
          prefixIcon: Icons.groups_rounded,
        ),
        const SizedBox(height: 16),
        TacticalTextField(
          controller: themeController,
          labelText: 'Tema (Ex: Cão Cidadão)',
          prefixIcon: Icons.lightbulb_rounded,
        ),
        const SizedBox(height: 24),
      ],
    );
  }
}
