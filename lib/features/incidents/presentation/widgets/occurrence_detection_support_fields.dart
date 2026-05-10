part of 'occurrence_detection_fields.dart';

class _DetectionSupportFields extends StatelessWidget {
  final TextEditingController supportTeamController;
  final TextEditingController reportNumberController;

  const _DetectionSupportFields({
    required this.supportTeamController,
    required this.reportNumberController,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        TacticalTextField(
          controller: supportTeamController,
          labelText: 'Equipe de Apoio (GCMs)',
          prefixIcon: Icons.group,
        ),
        const SizedBox(height: 16),
        TacticalTextField(
          controller: reportNumberController,
          labelText: 'Número do BO',
          prefixIcon: Icons.assignment,
        ),
      ],
    );
  }
}
