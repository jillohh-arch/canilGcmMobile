part of 'health_log_screen.dart';

class _HealthLogTypeSelector extends StatelessWidget {
  final List<String> logTypes;
  final String selectedLogType;
  final ValueChanged<String> onSelected;

  const _HealthLogTypeSelector({
    required this.logTypes,
    required this.selectedLogType,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SectionLabel(label: 'Tipo de Registro'),
        const SizedBox(height: 10),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: logTypes.map((type) {
            final isSelected = selectedLogType == type;
            final (icon, color) = _iconAndColor(type);
            return GestureDetector(
              onTap: () => onSelected(type),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: isSelected
                      ? color.withAlpha(40)
                      : colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                    color: isSelected ? color : Colors.white12,
                    width: isSelected ? 1.5 : 0.5,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      icon,
                      size: 16,
                      color: isSelected ? color : Colors.white70,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      type,
                      style: GoogleFonts.poppins(
                        fontSize: 13,
                        fontWeight: isSelected
                            ? FontWeight.w700
                            : FontWeight.w500,
                        color: isSelected ? color : Colors.white60,
                      ),
                    ),
                  ],
                ),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }
}

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

class _SaveHealthLogButton extends StatelessWidget {
  final String selectedLogType;
  final VoidCallback onPressed;

  const _SaveHealthLogButton({
    required this.selectedLogType,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final (_, selectedColor) = _iconAndColor(selectedLogType);

    return SizedBox(
      width: double.infinity,
      height: 56,
      child: Consumer<HealthViewModel>(
        builder: (context, viewModel, child) {
          return ElevatedButton.icon(
            icon: viewModel.isLoading
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      color: Colors.black,
                      strokeWidth: 2,
                    ),
                  )
                : Icon(_logIcon(selectedLogType), size: 22),
            label: Text(
              viewModel.isLoading ? 'SALVANDO...' : 'SALVAR PRONTUÁRIO',
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: selectedColor,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(6),
              ),
            ),
            onPressed: viewModel.isLoading ? null : onPressed,
          );
        },
      ),
    );
  }
}
