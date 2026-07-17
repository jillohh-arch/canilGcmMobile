import 'package:flutter/material.dart';

import 'package:canil_gcm/features/health/presentation/timeline/detail/health_timeline_detail_target.dart';
import 'package:canil_gcm/features/health/presentation/timeline/filters/health_timeline_filter_session.dart';
import 'package:canil_gcm/features/health/presentation/timeline/health_timeline_controller.dart';
import 'package:canil_gcm/features/health/presentation/timeline/health_timeline_screen.dart';
import 'package:canil_gcm/features/health/presentation/timeline/widgets/health_timeline_user_copy.dart';

/// Host isolado 3D/3E-A: reexporta a composição de [HealthTimelineScreen].
///
/// Mantido para harness/testes 3D sem renomear imports.
class HealthTimelineInteractiveHost extends StatelessWidget {
  const HealthTimelineInteractiveHost({
    super.key,
    required this.controller,
    required this.filterSession,
    required this.onNavigate,
    this.contextLabel,
    this.now,
    this.bottomPadding = 24,
    this.onUnavailableMessage,
  });

  final HealthTimelineController controller;
  final HealthTimelineFilterSession filterSession;
  final Future<void> Function(HealthTimelineDetailTarget target) onNavigate;
  final String? contextLabel;
  final DateTime Function()? now;
  final double bottomPadding;
  final void Function(String message)? onUnavailableMessage;

  @override
  Widget build(BuildContext context) {
    return HealthTimelineScreen(
      controller: controller,
      filterSession: filterSession,
      onNavigate: onNavigate,
      dogDisplayName: contextLabel,
      now: now,
      bottomPadding: bottomPadding,
      onUnavailableMessage: onUnavailableMessage,
    );
  }
}

/// Copy extra 3D/3E.
abstract final class HealthTimeline3dUserCopy {
  HealthTimeline3dUserCopy._();

  static const clearFilters = 'Limpar filtros';
  static const emptyFilteredMessage =
      'Nenhum registro corresponde aos filtros aplicados.';
}

String get healthTimelineClearFiltersLabel =>
    HealthTimeline3dUserCopy.clearFilters;
String get healthTimelineEmptyFilteredMessage =>
    HealthTimeline3dUserCopy.emptyFilteredMessage;
String get healthTimelineFilterAction => HealthTimelineUserCopy.filterAction;
