import 'package:flutter/material.dart';

import 'package:canil_gcm/core/widgets/hud_chip_group.dart';

class SearchCaptureActivityFields extends StatelessWidget {
  final String? selectedTrailAge;
  final String? selectedTerrain;
  final String? selectedOdorArticle;
  final Color accent;
  final void Function(String label, String? value) onChanged;
  final Widget trackingAction;

  const SearchCaptureActivityFields({
    super.key,
    required this.selectedTrailAge,
    required this.selectedTerrain,
    required this.selectedOdorArticle,
    required this.accent,
    required this.onChanged,
    required this.trackingAction,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        HudToggleChipGroup(
          label: 'Idade da Trilha',
          options: const ['< 30 min', '30m - 2h', '2h - 6h', '> 6h'],
          selectedOption: selectedTrailAge,
          accent: accent,
          onChanged: (value) => onChanged('Idade da Trilha', value),
        ),
        HudToggleChipGroup(
          label: 'Terreno',
          options: const ['Urbano', 'Mata', 'Rural', 'Misto'],
          selectedOption: selectedTerrain,
          accent: accent,
          onChanged: (value) => onChanged('Terreno', value),
        ),
        HudToggleChipGroup(
          label: 'Artigo de Odor',
          options: const ['Roupa', 'Objeto', 'Veículo', 'Odor de Cena'],
          selectedOption: selectedOdorArticle,
          accent: accent,
          onChanged: (value) => onChanged('Artigo de Odor', value),
        ),
        trackingAction,
      ],
    );
  }
}

class WalkTrackingActivityFields extends StatelessWidget {
  final String? selectedFloorType;
  final String? selectedLeadType;
  final Color accent;
  final void Function(String label, String? value) onChanged;
  final Widget trackingAction;

  const WalkTrackingActivityFields({
    super.key,
    required this.selectedFloorType,
    required this.selectedLeadType,
    required this.accent,
    required this.onChanged,
    required this.trackingAction,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        HudToggleChipGroup(
          label: 'Tipo de Piso',
          options: const ['Asfalto', 'Grama', 'Terra', 'Misto'],
          selectedOption: selectedFloorType,
          accent: accent,
          onChanged: (value) => onChanged('Tipo de Piso', value),
        ),
        HudToggleChipGroup(
          label: 'Guia',
          options: const ['Curta', 'Longa', 'Livre'],
          selectedOption: selectedLeadType,
          accent: accent,
          onChanged: (value) => onChanged('Guia', value),
        ),
        const SizedBox(height: 12),
        trackingAction,
      ],
    );
  }
}
