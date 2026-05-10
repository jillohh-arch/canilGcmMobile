import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import 'occurrence_quick_action.dart';

part 'occurrence_quick_action_options_header.dart';
part 'occurrence_quick_action_options_tile.dart';

class OccurrenceQuickActionOptionsSheet extends StatelessWidget {
  final OccurrenceQuickAction action;
  final Color backgroundColor;
  final Color panelColor;

  const OccurrenceQuickActionOptionsSheet({
    super.key,
    required this.action,
    required this.backgroundColor,
    required this.panelColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.all(14),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: action.color.withAlpha(145)),
        boxShadow: [
          BoxShadow(color: action.color.withAlpha(42), blurRadius: 24),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _QuickActionOptionsHeader(
            action: action,
            onClose: () => Navigator.of(context).pop(),
          ),
          const SizedBox(height: 12),
          _QuickActionOptionsDivider(color: action.color),
          const SizedBox(height: 12),
          ...action.options.map(
            (option) =>
                _QuickActionOptionTile(option: option, panelColor: panelColor),
          ),
        ],
      ),
    );
  }
}

class _QuickActionOptionsDivider extends StatelessWidget {
  final Color color;

  const _QuickActionOptionsDivider({required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 2,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [color, color.withAlpha(24), Colors.transparent],
        ),
      ),
    );
  }
}
