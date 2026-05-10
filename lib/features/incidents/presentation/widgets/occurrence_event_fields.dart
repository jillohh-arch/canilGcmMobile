part of 'occurrence_category_fields.dart';

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
