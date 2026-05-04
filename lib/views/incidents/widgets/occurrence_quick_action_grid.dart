import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'occurrence_quick_action.dart';
import 'occurrence_quick_action_card.dart';

class OccurrenceQuickActionGrid extends StatelessWidget {
  final Color accentColor;
  final List<OccurrenceQuickAction> actions;
  final bool enabled;
  final ValueChanged<OccurrenceQuickAction> onActionSelected;
  final VoidCallback onOpenEventCenter;

  const OccurrenceQuickActionGrid({
    super.key,
    required this.accentColor,
    required this.actions,
    required this.enabled,
    required this.onActionSelected,
    required this.onOpenEventCenter,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.bolt_rounded, color: accentColor, size: 22),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'REGISTROS RÁPIDOS',
                    style: GoogleFonts.robotoMono(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 1.5,
                    ),
                  ),
                  Text(
                    'Somente atalhos úteis para atuação no local.',
                    style: GoogleFonts.inter(
                      color: Colors.white54,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        LayoutBuilder(
          builder: (context, constraints) {
            final width = (constraints.maxWidth - 10) / 2;
            return Wrap(
              spacing: 10,
              runSpacing: 10,
              children: actions
                  .map(
                    (action) => OccurrenceQuickActionCard(
                      title: action.title,
                      icon: action.icon,
                      color: action.color,
                      assetPath: action.assetPath,
                      width: width,
                      enabled: enabled,
                      onTap: () => onActionSelected(action),
                    ),
                  )
                  .toList(),
            );
          },
        ),
        const SizedBox(height: 10),
        SizedBox(
          width: double.infinity,
          height: 50,
          child: OutlinedButton.icon(
            onPressed: enabled ? onOpenEventCenter : null,
            icon: Icon(Icons.add_rounded, color: accentColor),
            label: Text(
              'OUTRO EVENTO / CENTRAL',
              style: GoogleFonts.robotoMono(
                fontWeight: FontWeight.w900,
                letterSpacing: 1.0,
              ),
            ),
            style: OutlinedButton.styleFrom(
              foregroundColor: accentColor,
              side: BorderSide(color: accentColor.withAlpha(150)),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(6),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
