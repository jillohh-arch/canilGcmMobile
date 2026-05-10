part of 'occurrence_category_fields.dart';

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
