part of 'health_log_screen.dart';

class _HealthFilterBar extends StatelessWidget {
  final List<String> filters;
  final String selectedFilter;
  final ValueChanged<String> onSelected;

  const _HealthFilterBar({
    required this.filters,
    required this.selectedFilter,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 52,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        children: filters.map((filter) {
          final isSelected = selectedFilter == filter;
          final (_, color) = _iconAndColor(
            filter == 'Todos' ? 'Consulta' : filter,
          );
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: FilterChip(
              selected: isSelected,
              label: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (filter != 'Todos') ...[
                    Icon(
                      _logIcon(filter),
                      size: 13,
                      color: isSelected
                          ? color
                          : AppTheme.textPrimary.withAlpha(179),
                    ),
                    const SizedBox(width: 4),
                  ],
                  Text(filter),
                ],
              ),
              labelStyle: GoogleFonts.inter(
                fontSize: 12,
                fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                color: isSelected ? color : AppTheme.textPrimary.withAlpha(179),
              ),
              backgroundColor: Theme.of(
                context,
              ).colorScheme.surfaceContainerHighest,
              selectedColor: color.withAlpha(40),
              side: BorderSide(
                color: isSelected ? color : AppTheme.textPrimary.withAlpha(31),
              ),
              checkmarkColor: color,
              onSelected: (_) => onSelected(filter),
            ),
          );
        }).toList(),
      ),
    );
  }
}
