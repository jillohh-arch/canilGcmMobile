part of 'occurrence_grouped_sections.dart';

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
