import 'package:flutter/material.dart';

import '../../../widgets/activity_weather_button.dart';
import '../../../widgets/hud_chip_group.dart';
import '../../../widgets/hud_expansion_section.dart';
import '../../../widgets/tactical_text_field.dart';

class OccurrenceDetectionGroupedSections extends StatelessWidget {
  final TextEditingController natureController;
  final List<Widget> specificFields;
  final Widget topActionRow;
  final Widget locationTimeRow;
  final Widget descriptionField;
  final Widget imageGallery;

  const OccurrenceDetectionGroupedSections({
    super.key,
    required this.natureController,
    required this.specificFields,
    required this.topActionRow,
    required this.locationTimeRow,
    required this.descriptionField,
    required this.imageGallery,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        HudExpansionSection(
          title: 'Detalhes da apreensão',
          icon: Icons.shield_rounded,
          iconColor: Colors.orangeAccent,
          initiallyExpanded: true,
          children: [
            TacticalTextField(
              controller: natureController,
              labelText: 'Natureza da ocorrência',
              prefixIcon: Icons.category_rounded,
            ),
            const SizedBox(height: 16),
            ...specificFields,
          ],
        ),
        const SizedBox(height: 12),
        HudExpansionSection(
          title: 'Contexto & Local',
          icon: Icons.location_on_rounded,
          iconColor: const Color(0xFF4ECDE4),
          children: [topActionRow, const SizedBox(height: 16), locationTimeRow],
        ),
        const SizedBox(height: 12),
        HudExpansionSection(
          title: 'Relatório & Anexos',
          icon: Icons.photo_library_rounded,
          iconColor: const Color(0xFF1B8A4C),
          children: [
            descriptionField,
            const SizedBox(height: 24),
            imageGallery,
          ],
        ),
      ],
    );
  }
}

class OccurrencePersonSearchGroupedSections extends StatelessWidget {
  final TextEditingController natureController;
  final String searchCaptureSubtype;
  final String? selectedSearchType;
  final Color accentColor;
  final TextEditingController odorObjectController;
  final TextEditingController missingTimeController;
  final TextEditingController durationController;
  final TextEditingController terrainConditionController;
  final ValueChanged<String?> onSearchTypeChanged;
  final VoidCallback onPullWeather;
  final Widget topActionRow;
  final Widget locationTimeRow;
  final Widget trackingAction;
  final Widget descriptionField;
  final Widget imageGallery;

  const OccurrencePersonSearchGroupedSections({
    super.key,
    required this.natureController,
    required this.searchCaptureSubtype,
    required this.selectedSearchType,
    required this.accentColor,
    required this.odorObjectController,
    required this.missingTimeController,
    required this.durationController,
    required this.terrainConditionController,
    required this.onSearchTypeChanged,
    required this.onPullWeather,
    required this.topActionRow,
    required this.locationTimeRow,
    required this.trackingAction,
    required this.descriptionField,
    required this.imageGallery,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        HudExpansionSection(
          title: 'Detalhes da Busca',
          icon: Icons.person_search_rounded,
          iconColor: Colors.redAccent,
          initiallyExpanded: true,
          children: [
            TacticalTextField(
              controller: natureController,
              labelText: 'Natureza da ocorrência',
              prefixIcon: Icons.category_rounded,
            ),
            const SizedBox(height: 16),
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
          ],
        ),
        const SizedBox(height: 12),
        HudExpansionSection(
          title: 'Teatro de Operações',
          icon: Icons.terrain_rounded,
          iconColor: Colors.amber,
          children: [
            topActionRow,
            const SizedBox(height: 16),
            locationTimeRow,
            const SizedBox(height: 16),
            TacticalTextField(
              controller: terrainConditionController,
              labelText: 'Condições / Terreno',
              prefixIcon: Icons.terrain,
            ),
            const SizedBox(height: 16),
            ActivityWeatherButton(
              label: 'PUXAR CLIMA ATUAL (GPS)',
              onPressed: onPullWeather,
              backgroundColor: const Color(0xFF4ECDE4).withAlpha(50),
            ),
            const SizedBox(height: 16),
            trackingAction,
          ],
        ),
        const SizedBox(height: 12),
        HudExpansionSection(
          title: 'Relatório & Anexos',
          icon: Icons.photo_library_rounded,
          iconColor: const Color(0xFF1B8A4C),
          children: [
            descriptionField,
            const SizedBox(height: 24),
            imageGallery,
          ],
        ),
      ],
    );
  }
}
