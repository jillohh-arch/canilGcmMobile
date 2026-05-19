import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:canil_gcm/core/theme/app_theme.dart';

class StartOccurrenceTimeChips extends StatelessWidget {
  final int selectedIndex;
  final String formattedTime;
  final ValueChanged<int> onSelected;
  final VoidCallback onEditTap;

  const StartOccurrenceTimeChips({
    super.key,
    required this.selectedIndex,
    required this.formattedTime,
    required this.onSelected,
    required this.onEditTap,
  });

  @override
  Widget build(BuildContext context) {
    final chips = [
      _ChipData('Agora', 0),
      _ChipData('Há 5min', 1),
      _ChipData('Há 15min', 2),
      _ChipData('Editar', 3),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.schedule_rounded, color: AppTheme.primary, size: 14),
            const SizedBox(width: 6),
            Text(
              'HORÁRIO DE INÍCIO',
              style: GoogleFonts.inter(
                color: AppTheme.primary,
                fontSize: 10,
                fontWeight: FontWeight.w600,
                letterSpacing: 1.2,
              ),
            ),
            const Spacer(),
            Text(
              formattedTime,
              style: GoogleFonts.inter(
                color: Colors.white.withAlpha(180),
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: chips.map((chip) {
            final isSelected = chip.index == selectedIndex;
            return GestureDetector(
              onTap: () {
                HapticFeedback.lightImpact();
                if (chip.index == 3) {
                  onEditTap();
                } else {
                  onSelected(chip.index);
                }
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  color: isSelected
                      ? AppTheme.primary.withAlpha(25)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: isSelected
                        ? AppTheme.primary
                        : AppTheme.primary.withAlpha(60),
                    width: isSelected ? 1.5 : 1,
                  ),
                ),
                child: Text(
                  chip.label,
                  style: GoogleFonts.inter(
                    color: isSelected ? AppTheme.primary : Colors.white.withAlpha(180),
                    fontSize: 12,
                    fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }
}

class _ChipData {
  final String label;
  final int index;
  const _ChipData(this.label, this.index);
}
