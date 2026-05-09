part of 'training_log_screen.dart';

class _TrainingSectionLabel extends StatelessWidget {
  final String title;

  const _TrainingSectionLabel(this.title);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Text(
        title.toUpperCase(),
        style: GoogleFonts.poppins(
          color: Colors.white38,
          fontWeight: FontWeight.w800,
          fontSize: 10,
          letterSpacing: 1.2,
        ),
      ),
    );
  }
}

class _TrainingTypeSelector extends StatelessWidget {
  final List<String> trainingTypes;
  final String selectedTrainingType;
  final ValueChanged<String> onSelected;

  const _TrainingTypeSelector({
    required this.trainingTypes,
    required this.selectedTrainingType,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: trainingTypes.map((type) {
        final isSelected = selectedTrainingType == type;
        final (icon, color) = _trainingSessionStyle(type);
        return GestureDetector(
          onTap: () => onSelected(type),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
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
                  size: 18,
                  color: isSelected ? color : Colors.white38,
                ),
                const SizedBox(width: 8),
                Text(
                  type,
                  style: GoogleFonts.poppins(
                    fontSize: 14,
                    fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                    color: isSelected ? color : Colors.white60,
                  ),
                ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }
}

class _SubstanceSelector extends StatelessWidget {
  final List<String> substances;
  final String? selectedSubstance;
  final ValueChanged<String?> onSelected;

  const _SubstanceSelector({
    required this.substances,
    required this.selectedSubstance,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _TrainingSectionLabel('Substância Procurada'),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: substances.map((substance) {
            final isSelected = selectedSubstance == substance;
            return FilterChip(
              label: Text(substance),
              labelStyle: GoogleFonts.poppins(
                fontSize: 13,
                color: isSelected ? Colors.black : Colors.white70,
                fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
              ),
              backgroundColor: colorScheme.surfaceContainerHighest,
              selectedColor: AppTheme.amber,
              selected: isSelected,
              onSelected: (value) => onSelected(value ? substance : null),
            );
          }).toList(),
        ),
      ],
    );
  }
}

class _ScentMetricsFields extends StatelessWidget {
  final TextEditingController searchDurationController;
  final TextEditingController hidingTimeController;

  const _ScentMetricsFields({
    required this.searchDurationController,
    required this.hidingTimeController,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _TrainingSectionLabel('Métricas de Desempenho'),
        Row(
          children: [
            Expanded(
              child: TextFormField(
                controller: searchDurationController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Duração (segundos)',
                  prefixIcon: Icon(Icons.timer_rounded),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: TextFormField(
                controller: hidingTimeController,
                decoration: const InputDecoration(
                  labelText: 'Ocultação (ex: 15min)',
                  prefixIcon: Icon(Icons.timelapse_rounded),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _EnvironmentalTrainingFields extends StatelessWidget {
  final TextEditingController weatherController;
  final TextEditingController humidityController;
  final TextEditingController locationController;
  final TextEditingController windDirectionController;

  const _EnvironmentalTrainingFields({
    required this.weatherController,
    required this.humidityController,
    required this.locationController,
    required this.windDirectionController,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _TrainingSectionLabel('Condições Ambientais'),
        Row(
          children: [
            Expanded(
              child: TextFormField(
                controller: weatherController,
                decoration: const InputDecoration(
                  labelText: 'Clima',
                  prefixIcon: Icon(Icons.cloud_outlined),
                ),
                validator: _requiredField,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: TextFormField(
                controller: humidityController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Umidade (%)',
                  prefixIcon: Icon(Icons.water_drop_outlined),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: TextFormField(
                controller: locationController,
                decoration: const InputDecoration(
                  labelText: 'Local',
                  prefixIcon: Icon(Icons.location_on_outlined),
                ),
                validator: _requiredField,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: TextFormField(
                controller: windDirectionController,
                decoration: const InputDecoration(
                  labelText: 'Dir. Vento',
                  prefixIcon: Icon(Icons.air),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _TrainingNotesField extends StatelessWidget {
  final TextEditingController controller;

  const _TrainingNotesField({required this.controller});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _TrainingSectionLabel('Notas do Condutor'),
        TextFormField(
          controller: controller,
          maxLines: 4,
          decoration: const InputDecoration(
            labelText: 'Comportamento, detalhes, evolução...',
            alignLabelWithHint: true,
          ),
          validator: (value) => value == null || value.isEmpty
              ? 'Adicione ao menos uma nota'
              : null,
        ),
      ],
    );
  }
}

class _SaveTrainingButton extends StatelessWidget {
  final String selectedTrainingType;
  final VoidCallback onPressed;

  const _SaveTrainingButton({
    required this.selectedTrainingType,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 56,
      child: Consumer<TrainingViewModel>(
        builder: (context, viewModel, child) {
          final (_, color) = _trainingSessionStyle(selectedTrainingType);
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
                : const Icon(Icons.save_rounded, size: 22),
            label: Text(
              viewModel.isLoading ? 'SALVANDO...' : 'SALVAR TREINO',
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: color,
              foregroundColor: Colors.black,
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

String? _requiredField(String? value) {
  return value == null || value.isEmpty ? 'Obrigatório' : null;
}

(IconData, Color) _trainingSessionStyle(String type) {
  switch (type) {
    case 'Faro':
      return (Icons.track_changes_rounded, const Color(0xFFFFB300));
    case 'Proteção':
      return (Icons.shield_rounded, const Color(0xFFEF5350));
    case 'Obediência':
      return (Icons.school_rounded, const Color(0xFF42A5F5));
    default:
      return (Icons.fitness_center_rounded, AppTheme.amber);
  }
}
