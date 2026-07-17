import 'package:flutter/material.dart';

import 'package:canil_gcm/features/health/presentation/schedule/health_schedule_controller.dart';
import 'package:canil_gcm/features/health/presentation/schedule/health_schedule_view.dart';

/// Slot da aba Agenda no shell Health v1 (Fase 4B).
///
/// Ownership do [controller] fica no composition root ([HealthV1EntryScreen]).
class HealthScheduleScreen extends StatelessWidget {
  final HealthScheduleController controller;
  final String dogDisplayName;
  final double bottomPadding;
  final Duration recomputeInterval;
  final DateTime Function()? now;

  const HealthScheduleScreen({
    super.key,
    required this.controller,
    required this.dogDisplayName,
    this.bottomPadding = 24,
    this.recomputeInterval = const Duration(minutes: 1),
    this.now,
  });

  @override
  Widget build(BuildContext context) {
    return HealthScheduleView(
      controller: controller,
      dogDisplayName: dogDisplayName,
      bottomPadding: bottomPadding,
      recomputeInterval: recomputeInterval,
      now: now,
    );
  }
}
