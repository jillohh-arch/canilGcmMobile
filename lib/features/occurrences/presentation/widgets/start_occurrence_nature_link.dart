import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:canil_gcm/core/theme/app_theme.dart';
import 'package:canil_gcm/features/incidents/domain/occurrence_nature.dart';
import 'package:canil_gcm/features/incidents/presentation/widgets/occurrence_nature_search.dart';

class StartOccurrenceNatureLink extends StatelessWidget {
  final bool expanded;
  final String natureText;
  final TextEditingController controller;
  final FocusNode focusNode;
  final List<OccurrenceNature> natures;
  final VoidCallback onToggle;
  final ValueChanged<OccurrenceNature> onSelected;
  final ValueChanged<String> onChanged;

  const StartOccurrenceNatureLink({
    super.key,
    required this.expanded,
    required this.natureText,
    required this.controller,
    required this.focusNode,
    required this.natures,
    required this.onToggle,
    required this.onSelected,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        if (expanded) ...[
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppTheme.primary.withAlpha(10),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppTheme.primary.withAlpha(50)),
            ),
            child: OccurrenceNatureSearch(
              controller: controller,
              focusNode: focusNode,
              natures: natures,
              panelColor: const Color(0xFF0E1A1F),
              accent: AppTheme.primary,
              fieldBuilder: _buildField,
              onSelected: onSelected,
              onChanged: onChanged,
            ),
          ),
          const SizedBox(height: 14),
        ],
        GestureDetector(
          onTap: onToggle,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                expanded
                    ? Icons.keyboard_arrow_up_rounded
                    : Icons.add_rounded,
                color: AppTheme.primary,
                size: 20,
              ),
              const SizedBox(width: 8),
              Text(
                natureText.isEmpty
                    ? '+ Ajustar tipo de ocorrência (opcional)'
                    : 'Tipo: $natureText',
                style: GoogleFonts.inter(
                  color: AppTheme.primary,
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildField(
    BuildContext context,
    TextEditingController ctrl,
    FocusNode fn,
    ValueChanged<String> onChanged,
  ) {
    return TextField(
      controller: ctrl,
      focusNode: fn,
      onChanged: onChanged,
      style: GoogleFonts.inter(color: Colors.white, fontSize: 14),
      decoration: InputDecoration(
        hintText: 'Buscar natureza...',
        hintStyle: GoogleFonts.inter(
          color: Colors.white.withAlpha(100),
          fontSize: 14,
        ),
        prefixIcon: Icon(Icons.search, color: AppTheme.primary, size: 20),
        filled: true,
        fillColor: const Color(0xFF0E1A1F),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: AppTheme.primary.withAlpha(60)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: AppTheme.primary.withAlpha(60)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: AppTheme.primary),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      ),
    );
  }
}
