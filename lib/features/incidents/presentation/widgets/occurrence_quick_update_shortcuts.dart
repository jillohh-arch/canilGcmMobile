import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class OccurrenceQuickUpdateShortcuts extends StatelessWidget {
  final List<String> titles;
  final String? selectedTitle;
  final Color accent;
  final ValueChanged<String> onSelected;

  const OccurrenceQuickUpdateShortcuts({
    super.key,
    required this.titles,
    required this.selectedTitle,
    required this.accent,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    if (titles.isEmpty) {
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'ATALHOS DE ANDAMENTO',
          style: GoogleFonts.inter(
            fontSize: 10,
            fontWeight: FontWeight.w800,
            color: Colors.white54,
            letterSpacing: 1.0,
          ),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: titles.map((title) {
            final isSelected = selectedTitle == title;
            return FilterChip(
              label: Text(title),
              selected: isSelected,
              showCheckmark: false,
              backgroundColor: Colors.transparent,
              selectedColor: accent.withValues(alpha: 0.82),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(6),
                side: BorderSide(
                  color: isSelected ? Colors.transparent : Colors.white12,
                ),
              ),
              labelStyle: GoogleFonts.inter(
                color: isSelected ? Colors.black : Colors.white70,
                fontWeight: FontWeight.w800,
                fontSize: 12,
              ),
              onSelected: (_) => onSelected(title),
            );
          }).toList(),
        ),
        if (selectedTitle != null) ...[
          const SizedBox(height: 8),
          Text(
            'Atalho ativo: $selectedTitle',
            style: GoogleFonts.inter(
              color: accent.withValues(alpha: 0.92),
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ],
    );
  }
}
