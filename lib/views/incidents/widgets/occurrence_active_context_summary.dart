import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class OccurrenceActiveContextSummary extends StatelessWidget {
  final Color accentColor;
  final Color panelColor;
  final Color backgroundColor;
  final String location;
  final String team;
  final String startedLabel;
  final VoidCallback onEdit;

  const OccurrenceActiveContextSummary({
    super.key,
    required this.accentColor,
    required this.panelColor,
    required this.backgroundColor,
    required this.location,
    required this.team,
    required this.startedLabel,
    required this.onEdit,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: panelColor.withAlpha(175),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: accentColor.withAlpha(65)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.fact_check_rounded, color: accentColor, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'CONTEXTO DA OCORRÊNCIA',
                  style: GoogleFonts.robotoMono(
                    color: accentColor,
                    fontSize: 10,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.3,
                  ),
                ),
              ),
              TextButton.icon(
                onPressed: onEdit,
                icon: const Icon(Icons.edit_rounded, size: 15),
                label: Text(
                  'EDITAR',
                  style: GoogleFonts.robotoMono(
                    fontSize: 10,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.8,
                  ),
                ),
                style: TextButton.styleFrom(
                  foregroundColor: accentColor,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  minimumSize: const Size(0, 34),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _OccurrenceContextChip(
                icon: Icons.location_on_rounded,
                label: 'Local',
                value: location,
                color: const Color(0xFF00E5FF),
                backgroundColor: backgroundColor,
              ),
              _OccurrenceContextChip(
                icon: Icons.groups_rounded,
                label: 'Equipe',
                value: team,
                color: const Color(0xFFFFB84D),
                backgroundColor: backgroundColor,
              ),
              _OccurrenceContextChip(
                icon: Icons.schedule_rounded,
                label: 'Iniciada',
                value: startedLabel,
                color: const Color(0xFF00F5A0),
                backgroundColor: backgroundColor,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _OccurrenceContextChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color color;
  final Color backgroundColor;

  const _OccurrenceContextChip({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
    required this.backgroundColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minHeight: 38, maxWidth: 230),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: backgroundColor.withAlpha(145),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withAlpha(75)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 15),
          const SizedBox(width: 7),
          Flexible(
            child: RichText(
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              text: TextSpan(
                children: [
                  TextSpan(
                    text: '$label: ',
                    style: GoogleFonts.robotoMono(
                      color: Colors.white54,
                      fontSize: 10,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 0.7,
                    ),
                  ),
                  TextSpan(
                    text: value,
                    style: GoogleFonts.inter(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
