part of 'occurrence_grouped_sections.dart';

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
            _OccurrenceNatureField(controller: natureController),
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
            _SearchDurationFields(
              missingTimeController: missingTimeController,
              durationController: durationController,
            ),
          ],
        ),
        const SizedBox(height: 12),
        _SearchOperationTheaterSection(
          terrainConditionController: terrainConditionController,
          topActionRow: topActionRow,
          locationTimeRow: locationTimeRow,
          trackingAction: trackingAction,
          onPullWeather: onPullWeather,
        ),
        const SizedBox(height: 12),
        _OccurrenceReportAttachmentsSection(
          descriptionField: descriptionField,
          imageGallery: imageGallery,
        ),
      ],
    );
  }
}

class _SearchDurationFields extends StatelessWidget {
  final TextEditingController missingTimeController;
  final TextEditingController durationController;

  const _SearchDurationFields({
    required this.missingTimeController,
    required this.durationController,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
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
    );
  }
}

class _SearchOperationTheaterSection extends StatelessWidget {
  final TextEditingController terrainConditionController;
  final Widget topActionRow;
  final Widget locationTimeRow;
  final Widget trackingAction;
  final VoidCallback onPullWeather;

  const _SearchOperationTheaterSection({
    required this.terrainConditionController,
    required this.topActionRow,
    required this.locationTimeRow,
    required this.trackingAction,
    required this.onPullWeather,
  });

  @override
  Widget build(BuildContext context) {
    return HudExpansionSection(
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
    );
  }
}
