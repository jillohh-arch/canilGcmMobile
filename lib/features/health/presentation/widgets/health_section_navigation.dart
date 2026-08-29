import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:canil_gcm/core/theme/app_theme.dart';
import 'package:canil_gcm/features/health/presentation/widgets/health_shell_section.dart';

/// Navegação interna do shell Health: Resumo | Histórico | Agenda | Nutrição.
///
/// Visual alinhado ao mockup 01 (pill selecionada com borda cyan).
/// Em larguras estreitas reduz tipografia/ícone sem trocar de padrão.
class HealthSectionNavigation extends StatelessWidget {
  final HealthShellSection selected;
  final ValueChanged<HealthShellSection> onSelected;

  const HealthSectionNavigation({
    super.key,
    required this.selected,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final compact = width < 380;
        final veryCompact = width < 340;

        return Container(
          width: double.infinity,
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: AppTheme.surfacePanel.withValues(alpha: 0.92),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppTheme.surfaceWhiteBorder),
          ),
          child: Row(
            children: [
              for (final section in HealthShellSection.navigationOrder)
                Expanded(
                  child: _SectionNavItem(
                    section: section,
                    selected: selected == section,
                    compact: compact,
                    veryCompact: veryCompact,
                    onTap: () => onSelected(section),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _SectionNavItem extends StatelessWidget {
  final HealthShellSection section;
  final bool selected;
  final bool compact;
  final bool veryCompact;
  final VoidCallback onTap;

  const _SectionNavItem({
    required this.section,
    required this.selected,
    required this.compact,
    required this.veryCompact,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final iconSize = veryCompact ? 14.0 : (compact ? 15.0 : 16.0);
    final fontSize = veryCompact ? 10.0 : (compact ? 11.0 : 12.0);
    final horizontalPad = veryCompact ? 2.0 : (compact ? 4.0 : 6.0);

    return Semantics(
      button: true,
      selected: selected,
      label: section.label,
      // Evita Semantics duplicada do InkWell/Text.
      excludeSemantics: true,
      child: Material(
        color: AppTheme.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(11),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            curve: Curves.easeOut,
            constraints: const BoxConstraints(minHeight: 44),
            padding: EdgeInsets.symmetric(
              horizontal: horizontalPad,
              vertical: 10,
            ),
            decoration: BoxDecoration(
              color: selected
                  ? AppTheme.primary.withValues(alpha: 0.14)
                  : AppTheme.transparent,
              borderRadius: BorderRadius.circular(11),
              border: Border.all(
                color: selected
                    ? AppTheme.primary.withValues(alpha: 0.90)
                    : AppTheme.transparent,
                width: 1.2,
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  section.icon,
                  size: iconSize,
                  color: selected
                      ? AppTheme.primary
                      : AppTheme.textSecondary.withValues(alpha: 0.85),
                ),
                SizedBox(width: veryCompact ? 3 : 5),
                Flexible(
                  child: Text(
                    section.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: GoogleFonts.inter(
                      color: selected
                          ? AppTheme.primary
                          : AppTheme.textSecondary,
                      fontSize: fontSize,
                      fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                      letterSpacing: selected ? 0.1 : 0,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
