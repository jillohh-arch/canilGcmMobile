import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:canil_gcm/core/theme/app_theme.dart';
import 'package:canil_gcm/features/health/presentation/schedule/health_schedule_ui_filter.dart';

/// Chips horizontais de filtro de leitura da Agenda.
///
/// Seleção preenchida em cyan (referência mockup), touch target ≥ 40.
class HealthScheduleFilterChips extends StatelessWidget {
  final HealthScheduleUiFilter selected;
  final ValueChanged<HealthScheduleUiFilter> onSelected;

  const HealthScheduleFilterChips({
    super.key,
    required this.selected,
    required this.onSelected,
  });

  static const filters = HealthScheduleUiFilter.values;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 40,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: filters.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final filter = filters[index];
          final isSelected = filter == selected;
          return Semantics(
            button: true,
            selected: isSelected,
            label: filter.label,
            child: Material(
              color: AppTheme.transparent,
              child: InkWell(
                borderRadius: BorderRadius.circular(20),
                onTap: () => onSelected(filter),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 160),
                  constraints: const BoxConstraints(minHeight: 36),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? AppTheme.primary
                        : AppTheme.surfacePanel.withValues(alpha: 0.92),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: isSelected
                          ? AppTheme.primary
                          : AppTheme.outline.withValues(alpha: 0.75),
                    ),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    filter.label,
                    style: GoogleFonts.inter(
                      color: isSelected
                          ? AppTheme.nightBlue
                          : AppTheme.textSecondary,
                      fontSize: 12.5,
                      fontWeight: isSelected
                          ? FontWeight.w700
                          : FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
