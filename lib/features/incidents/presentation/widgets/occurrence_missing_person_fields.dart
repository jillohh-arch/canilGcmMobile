part of 'occurrence_category_fields.dart';

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
        _MissingPersonDurationRow(
          missingTimeController: missingTimeController,
          durationController: durationController,
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

class _MissingPersonDurationRow extends StatelessWidget {
  final TextEditingController missingTimeController;
  final TextEditingController durationController;

  const _MissingPersonDurationRow({
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
