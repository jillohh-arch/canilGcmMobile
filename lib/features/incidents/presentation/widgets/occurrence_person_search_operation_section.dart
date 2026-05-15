part of 'occurrence_grouped_sections.dart';

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
          backgroundColor: AppTheme.primary.withAlpha(50),
        ),
        const SizedBox(height: 16),
        trackingAction,
      ],
    );
  }
}
