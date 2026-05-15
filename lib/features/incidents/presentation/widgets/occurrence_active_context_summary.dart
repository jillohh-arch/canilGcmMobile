import 'package:flutter/material.dart';
import 'package:canil_gcm/core/theme/app_theme.dart';
import 'package:google_fonts/google_fonts.dart';

part 'occurrence_active_context_chip.dart';
part 'occurrence_active_context_header.dart';

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
          _OccurrenceActiveContextHeader(
            accentColor: accentColor,
            onEdit: onEdit,
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
                color: AppTheme.primary,
                backgroundColor: backgroundColor,
              ),
              _OccurrenceContextChip(
                icon: Icons.groups_rounded,
                label: 'Equipe',
                value: team,
                color: AppTheme.warning,
                backgroundColor: backgroundColor,
              ),
              _OccurrenceContextChip(
                icon: Icons.schedule_rounded,
                label: 'Iniciada',
                value: startedLabel,
                color: AppTheme.success,
                backgroundColor: backgroundColor,
              ),
            ],
          ),
        ],
      ),
    );
  }
}
