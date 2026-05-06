import 'package:flutter/material.dart';

class OccurrenceActivePanel extends StatelessWidget {
  final Widget commandHeader;
  final Widget contextSummary;
  final Widget quickActions;
  final List<Widget> timelinePreview;

  const OccurrenceActivePanel({
    super.key,
    required this.commandHeader,
    required this.contextSummary,
    required this.quickActions,
    required this.timelinePreview,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        commandHeader,
        const SizedBox(height: 12),
        contextSummary,
        const SizedBox(height: 14),
        quickActions,
        ...timelinePreview,
      ],
    );
  }
}

class OccurrenceFinalizationPanel extends StatelessWidget {
  final Widget commandHeader;
  final Widget closeStep;

  const OccurrenceFinalizationPanel({
    super.key,
    required this.commandHeader,
    required this.closeStep,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [commandHeader, const SizedBox(height: 12), closeStep],
    );
  }
}
