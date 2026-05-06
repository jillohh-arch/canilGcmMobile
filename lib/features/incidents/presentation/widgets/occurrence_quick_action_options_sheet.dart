import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import 'occurrence_quick_action.dart';

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
          _buildHeader(context),
          const SizedBox(height: 12),
          Container(
            height: 2,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  action.color,
                  action.color.withAlpha(24),
                  Colors.transparent,
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          ...action.options.map(
            (option) =>
                _QuickActionOptionTile(option: option, panelColor: panelColor),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            color: action.color.withAlpha(18),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: action.color.withAlpha(120)),
          ),
          child: Icon(action.icon, color: action.color, size: 20),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                action.title.toUpperCase(),
                style: GoogleFonts.robotoMono(
                  color: action.color,
                  fontSize: 12,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1.5,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                'Selecione o tipo de evento.',
                style: GoogleFonts.inter(
                  color: Colors.white54,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
        IconButton(
          onPressed: () => Navigator.of(context).pop(),
          icon: const Icon(Icons.close_rounded),
          color: Colors.white54,
        ),
      ],
    );
  }
}

class _QuickActionOptionTile extends StatelessWidget {
  final OccurrenceQuickAction option;
  final Color panelColor;

  const _QuickActionOptionTile({
    required this.option,
    required this.panelColor,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        borderRadius: BorderRadius.circular(6),
        onTap: () {
          HapticFeedback.selectionClick();
          Navigator.of(context).pop(option);
        },
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: panelColor.withAlpha(210),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: option.color.withAlpha(80)),
          ),
          child: Row(
            children: [
              Icon(option.icon, color: option.color, size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      option.title,
                      style: GoogleFonts.oxanium(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      option.description,
                      style: GoogleFonts.inter(
                        color: Colors.white54,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        height: 1.25,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
