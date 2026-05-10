part of 'occurrence_category_fields.dart';

class OccurrenceServiceOrderFields extends StatelessWidget {
  final TextEditingController orderNumberController;

  const OccurrenceServiceOrderFields({
    super.key,
    required this.orderNumberController,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        TacticalTextField(
          controller: orderNumberController,
          labelText: 'Número da Ordem de Serviço',
          prefixIcon: Icons.numbers,
        ),
        const SizedBox(height: 24),
      ],
    );
  }
}
