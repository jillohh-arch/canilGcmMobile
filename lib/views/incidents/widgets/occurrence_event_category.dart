import 'package:flutter/material.dart';

import 'occurrence_quick_action.dart';

class OccurrenceEventCategory {
  final String title;
  final IconData icon;
  final Color color;
  final List<OccurrenceQuickAction> actions;

  const OccurrenceEventCategory({
    required this.title,
    required this.icon,
    required this.color,
    required this.actions,
  });
}
