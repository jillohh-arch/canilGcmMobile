import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:canil_gcm/core/theme/app_theme.dart';
import 'package:canil_gcm/features/shifts/presentation/viewmodels/shift_group_viewmodel.dart';

/// Widget reutilizável que mostra o badge do plantão atual do GCM
class ShiftGroupBadge extends StatelessWidget {
  const ShiftGroupBadge({super.key, this.compact = false});

  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Consumer<ShiftGroupViewModel>(
      builder: (context, vm, _) {
        if (vm.isLoading) {
          return const SizedBox.shrink();
        }

        final shift = vm.currentShift;
        if (shift == null) {
          return const SizedBox.shrink();
        }

        final isWithin = vm.isWithinShiftHours;
        final isAdministrative = shift.groupType == 'administrative';
        final color = isAdministrative
            ? AppTheme.warning
            : isWithin
                ? AppTheme.success
                : AppTheme.attention;

        if (compact) {
          return Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.18),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: color.withValues(alpha: 0.4)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  isAdministrative
                      ? Icons.business_center_rounded
                      : Icons.schedule_rounded,
                  color: color,
                  size: 14,
                ),
                const SizedBox(width: 4),
                Text(
                  shift.groupName,
                  style: TextStyle(
                    color: color,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          );
        }

        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: color.withValues(alpha: 0.4)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                isAdministrative
                    ? Icons.business_center_rounded
                    : Icons.schedule_rounded,
                color: color,
                size: 18,
              ),
              const SizedBox(width: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    shift.groupName,
                    style: TextStyle(
                      color: color,
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  Text(
                    shift.scheduleDisplay,
                    style: TextStyle(
                      color: color.withValues(alpha: 0.85),
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}

/// Banner que sugere iniciar turno se estiver no horário esperado
class ShiftStartSuggestion extends StatelessWidget {
  const ShiftStartSuggestion({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<ShiftGroupViewModel>(
      builder: (context, vm, _) {
        if (vm.currentShift == null) {
          return const SizedBox.shrink();
        }

        if (!vm.shouldStartShift) {
          return const SizedBox.shrink();
        }

        return Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppTheme.attention.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppTheme.attention.withValues(alpha: 0.4)),
          ),
          child: Row(
            children: [
              Icon(
                Icons.notifications_active_rounded,
                color: AppTheme.attention,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      "Hora de iniciar o plantão",
                      style: TextStyle(
                        color: AppTheme.attention,
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      "Seu plantão ${vm.currentShift!.groupName} (${vm.currentShift!.scheduleDisplay}) já começou.",
                      style: TextStyle(
                        color: AppTheme.attention.withValues(alpha: 0.85),
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
