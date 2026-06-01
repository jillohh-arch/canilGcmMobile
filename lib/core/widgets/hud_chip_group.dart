import 'package:flutter/material.dart';

import 'package:canil_gcm/core/theme/app_theme.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

class HudChoiceChipGroup extends StatelessWidget {
  final String label;
  final List<String> options;
  final String? selectedOption;
  final Color accent;
  final ValueChanged<String> onSelected;
  final EdgeInsetsGeometry padding;

  const HudChoiceChipGroup({
    super.key,
    required this.label,
    required this.options,
    required this.selectedOption,
    required this.accent,
    required this.onSelected,
    this.padding = const EdgeInsets.only(bottom: 12),
  });

  @override
  Widget build(BuildContext context) {
    return _HudChipSection(
      label: label,
      padding: padding,
      children: options.map((option) {
        final isSelected = selectedOption == option;
        return ChoiceChip(
          label: Text(option),
          selected: isSelected,
          showCheckmark: false,
          backgroundColor: AppTheme.transparent,
          selectedColor: accent,
          shape: _chipShape(isSelected),
          labelStyle: _chipLabelStyle(isSelected),
          onSelected: (_) {
            HapticFeedback.selectionClick();
            onSelected(option);
          },
        );
      }).toList(),
    );
  }
}

class HudMultiChipGroup extends StatelessWidget {
  final String label;
  final List<String> options;
  final Set<String> selectedOptions;
  final Color accent;
  final ValueChanged<String> onToggle;
  final EdgeInsetsGeometry padding;

  const HudMultiChipGroup({
    super.key,
    required this.label,
    required this.options,
    required this.selectedOptions,
    required this.accent,
    required this.onToggle,
    this.padding = const EdgeInsets.only(bottom: 12),
  });

  @override
  Widget build(BuildContext context) {
    return _HudChipSection(
      label: label,
      padding: padding,
      children: options.map((option) {
        final isSelected = selectedOptions.contains(option);
        return FilterChip(
          label: Text(option),
          selected: isSelected,
          showCheckmark: false,
          backgroundColor: AppTheme.transparent,
          selectedColor: accent,
          shape: _chipShape(isSelected),
          labelStyle: _chipLabelStyle(isSelected),
          onSelected: (_) {
            HapticFeedback.selectionClick();
            onToggle(option);
          },
        );
      }).toList(),
    );
  }
}

class HudToggleChipGroup extends StatelessWidget {
  final String label;
  final List<String> options;
  final String? selectedOption;
  final Color accent;
  final ValueChanged<String?> onChanged;
  final EdgeInsetsGeometry padding;

  const HudToggleChipGroup({
    super.key,
    required this.label,
    required this.options,
    required this.selectedOption,
    required this.accent,
    required this.onChanged,
    this.padding = const EdgeInsets.only(bottom: 24),
  });

  @override
  Widget build(BuildContext context) {
    return _HudChipSection(
      label: label,
      padding: padding,
      children: options.map((option) {
        final isSelected = selectedOption == option;
        return ChoiceChip(
          label: Text(option),
          selected: isSelected,
          showCheckmark: false,
          backgroundColor: AppTheme.transparent,
          selectedColor: accent,
          shape: _chipShape(isSelected),
          labelStyle: _chipLabelStyle(isSelected),
          onSelected: (selected) {
            HapticFeedback.selectionClick();
            onChanged(selected ? option : null);
          },
        );
      }).toList(),
    );
  }
}

class _HudChipSection extends StatelessWidget {
  final String label;
  final List<Widget> children;
  final EdgeInsetsGeometry padding;

  const _HudChipSection({
    required this.label,
    required this.children,
    required this.padding,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: padding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label.toUpperCase(),
            style: GoogleFonts.inter(
              fontSize: 10,
              fontWeight: FontWeight.w800,
              color: AppTheme.textPrimary.withAlpha(138),
              letterSpacing: 1.0,
            ),
          ),
          const SizedBox(height: 12),
          Wrap(spacing: 8, runSpacing: 10, children: children),
        ],
      ),
    );
  }
}

OutlinedBorder _chipShape(bool isSelected) {
  return RoundedRectangleBorder(
    borderRadius: BorderRadius.circular(6),
    side: BorderSide(
      color: isSelected ? AppTheme.transparent : AppTheme.outline,
      width: 1,
    ),
  );
}

TextStyle _chipLabelStyle(bool isSelected) {
  return GoogleFonts.inter(
    fontWeight: isSelected ? FontWeight.w900 : FontWeight.w600,
    color: isSelected
        ? AppTheme.background
        : AppTheme.textPrimary.withAlpha(138),
  );
}
