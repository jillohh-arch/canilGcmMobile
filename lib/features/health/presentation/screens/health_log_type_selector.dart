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
                      style: GoogleFonts.inter(
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
