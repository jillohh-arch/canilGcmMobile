part of 'training_log_screen.dart';

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
