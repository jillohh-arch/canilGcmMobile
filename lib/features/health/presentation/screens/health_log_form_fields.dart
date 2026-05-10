part of 'health_log_screen.dart';

class _VaccineNameField extends StatelessWidget {
  final TextEditingController controller;

  const _VaccineNameField({required this.controller});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SectionLabel(label: 'Nome da Vacina'),
        const SizedBox(height: 10),
        TextFormField(
          controller: controller,
          decoration: const InputDecoration(
            labelText: 'Ex: V10, Antirrábica, Giardíase...',
            prefixIcon: Icon(Icons.vaccines_rounded),
          ),
          validator: (value) => value == null || value.isEmpty
              ? 'Informe o nome da vacina'
              : null,
        ),
      ],
    );
  }
}

class _HealthWeightField extends StatelessWidget {
  final TextEditingController controller;

  const _HealthWeightField({required this.controller});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SectionLabel(label: 'Peso Atual'),
        const SizedBox(height: 10),
        TextFormField(
          controller: controller,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(
            labelText: 'Ex: 28.5 kg',
            prefixIcon: Icon(Icons.monitor_weight_outlined),
          ),
        ),
      ],
    );
  }
}

class _HealthObservationField extends StatelessWidget {
  final TextEditingController controller;

  const _HealthObservationField({required this.controller});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SectionLabel(label: 'Observações Clínicas'),
        const SizedBox(height: 10),
        TextFormField(
          controller: controller,
          maxLines: 4,
          decoration: const InputDecoration(
            labelText: 'Sintomas, dosagem, histórico...',
            alignLabelWithHint: true,
          ),
          validator: (value) => value == null || value.isEmpty
              ? 'Adicione ao menos uma observação'
              : null,
        ),
      ],
    );
  }
}
