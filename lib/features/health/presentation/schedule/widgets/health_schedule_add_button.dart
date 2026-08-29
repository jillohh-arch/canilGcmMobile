import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:canil_gcm/core/theme/app_theme.dart';
import 'package:canil_gcm/features/health/presentation/schedule/health_schedule_mutation_user_copy.dart';

/// CTA inferior "Adicionar agendamento" (referência mockup Agenda Preventiva).
class HealthScheduleAddButton extends StatelessWidget {
  final VoidCallback? onPressed;
  final bool compact;

  const HealthScheduleAddButton({
    super.key,
    required this.onPressed,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final label = compact
        ? HealthScheduleMutationUserCopy.addToSchedule
        : HealthScheduleMutationUserCopy.addScheduleCta;

    return Semantics(
      button: true,
      enabled: onPressed != null,
      label: label,
      child: SizedBox(
        width: double.infinity,
        height: 50,
        child: FilledButton.icon(
          key: const ValueKey('schedule-add-button'),
          onPressed: onPressed,
          icon: const Icon(Icons.add_rounded, size: 22),
          label: Text(
            label,
            style: GoogleFonts.inter(
              fontWeight: FontWeight.w800,
              fontSize: 14,
              letterSpacing: 0.2,
            ),
          ),
          style: FilledButton.styleFrom(
            backgroundColor: AppTheme.primary,
            foregroundColor: AppTheme.nightBlue,
            disabledBackgroundColor: AppTheme.outline,
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        ),
      ),
    );
  }
}
