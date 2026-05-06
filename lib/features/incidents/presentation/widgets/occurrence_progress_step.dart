import 'package:flutter/material.dart';

class OccurrenceProgressStep extends StatelessWidget {
  final Widget? activeConsole;
  final List<Widget> shortcutWidgets;
  final Widget updateField;
  final List<Widget> timelineWidgets;

  const OccurrenceProgressStep({
    super.key,
    this.activeConsole,
    required this.shortcutWidgets,
    required this.updateField,
    required this.timelineWidgets,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (activeConsole != null) ...[
          activeConsole!,
          const SizedBox(height: 14),
        ],
        ...shortcutWidgets,
        const SizedBox(height: 12),
        updateField,
        ...timelineWidgets,
      ],
    );
  }
}
