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
              child: Text(
                'REGISTROS RÁPIDOS',
                style: GoogleFonts.inter(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1.5,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        LayoutBuilder(
          builder: (context, constraints) {
            final cardWidth = (constraints.maxWidth - 10) / 2;
            return Column(
              children: [
                for (var i = 0; i < actions.length; i += 2) ...[
                  Row(
                    children: [
                      OccurrenceQuickActionCard(
                        title: actions[i].title,
                        icon: actions[i].icon,
                        color: actions[i].color,
                        assetPath: actions[i].assetPath,
                        width: cardWidth,
                        enabled: enabled,
                        onTap: () => onActionSelected(actions[i]),
                      ),
                      const SizedBox(width: 10),
                      if (i + 1 < actions.length)
                        OccurrenceQuickActionCard(
                          title: actions[i + 1].title,
                          icon: actions[i + 1].icon,
                          color: actions[i + 1].color,
                          assetPath: actions[i + 1].assetPath,
                          width: cardWidth,
                          enabled: enabled,
                          onTap: () => onActionSelected(actions[i + 1]),
                        )
                      else
                        SizedBox(width: cardWidth),
                    ],
                  ),
                  const SizedBox(height: 10),
                ],
              ],
            );
          },
        ),
        SizedBox(
          width: double.infinity,
          height: 46,
          child: OutlinedButton.icon(
            onPressed: enabled ? onOpenEventCenter : null,
            icon: Icon(Icons.add_rounded, color: accentColor),
            label: Text(
              'OUTRO EVENTO / CENTRAL',
              style: GoogleFonts.inter(
                fontSize: 11,
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
