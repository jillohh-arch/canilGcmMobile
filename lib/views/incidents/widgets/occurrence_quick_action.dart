import 'package:flutter/material.dart';

class OccurrenceQuickAction {
  final String title;
  final String description;
  final IconData icon;
  final Color color;
  final String? assetPath;
  final List<OccurrenceQuickAction> options;

  const OccurrenceQuickAction({
    required this.title,
    required this.description,
    required this.icon,
    required this.color,
    this.assetPath,
    this.options = const [],
  });
}
