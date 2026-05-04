import 'package:flutter/material.dart';

import 'activity_weather_button.dart';
import 'hud_chip_group.dart';
import 'hud_controls.dart';
import 'tactical_text_field.dart';

class ScentWorkActivityFields extends StatelessWidget {
  final Color accentColor;
  final Color odorAccentColor;
  final String? selectedWindDirection;
  final String? selectedDifficulty;
  final String? selectedFinalResponse;
  final String? selectedOdor;
  final TextEditingController temperatureController;
  final TextEditingController humidityController;
  final void Function(String label, String? value) onChipChanged;
  final ValueChanged<String?> onOdorChanged;
  final VoidCallback onPullWeather;

  const ScentWorkActivityFields({
    super.key,
    required this.accentColor,
    required this.odorAccentColor,
    required this.selectedWindDirection,
    required this.selectedDifficulty,
    required this.selectedFinalResponse,
    required this.selectedOdor,
    required this.temperatureController,
    required this.humidityController,
    required this.onChipChanged,
    required this.onOdorChanged,
    required this.onPullWeather,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        HudToggleChipGroup(
          label: 'Direção do Vento',
          options: const ['Face', 'Cauda', 'Lateral', 'Sem Vento'],
          selectedOption: selectedWindDirection,
          accent: accentColor,
          onChanged: (value) => onChipChanged('Direção do Vento', value),
        ),
        HudToggleChipGroup(
          label: 'Dificuldade',
          options: const [
            'Cenário Limpo',
            'Distratores',
            'Efeito Chaminé',
            'Delta T',
          ],
          selectedOption: selectedDifficulty,
          accent: accentColor,
          onChanged: (value) => onChipChanged('Dificuldade', value),
        ),
        HudToggleChipGroup(
          label: 'Resposta Final',
          options: const ['Sentado', 'Deitado', 'Ativo', 'Congelamento'],
          selectedOption: selectedFinalResponse,
          accent: accentColor,
          onChanged: (value) => onChipChanged('Resposta Final', value),
        ),
        const SizedBox(height: 12),
        Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: HudSelectField<String>(
            label: 'Tipo de Odor',
            icon: Icons.science_rounded,
            value: selectedOdor,
            placeholder: 'Selecione o odor',
            accent: odorAccentColor,
            items: const [
              'Maconha',
              'Cocaína',
              'Crack',
              'Sintéticos',
              'Nose MP',
              'Outros',
            ],
            labelBuilder: (item) => item,
            onChanged: onOdorChanged,
          ),
        ),
        Row(
          children: [
            Expanded(
              child: TacticalTextField(
                controller: temperatureController,
                keyboardType: TextInputType.number,
                labelText: 'Temp (°C)',
                prefixIcon: Icons.thermostat_rounded,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: TacticalTextField(
                controller: humidityController,
                keyboardType: TextInputType.number,
                labelText: 'Umidade (%)',
                prefixIcon: Icons.water_drop_rounded,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        ActivityWeatherButton(
          label: 'CAPTURAR CLIMA (GPS)',
          onPressed: onPullWeather,
          backgroundColor: const Color(0xFF1B4F72),
          height: 44,
        ),
        const SizedBox(height: 12),
      ],
    );
  }
}
