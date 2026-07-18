import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:canil_gcm/core/theme/app_theme.dart';
import 'package:canil_gcm/features/health/domain/health_v1_enums_ext.dart';
import 'package:canil_gcm/features/health/presentation/schedule/health_schedule_mutation_user_copy.dart';
import 'package:canil_gcm/features/health/presentation/schedule/widgets/health_schedule_formatters.dart';
import 'package:canil_gcm/features/health/presentation/shared/widgets/health_field_label.dart';

/// Campo compacto + bottom sheet visual para [ScheduleType].
///
/// Usa o mesmo mapeamento de ícone/label dos cards da Agenda
/// ([HealthScheduleFormatters]).
class HealthScheduleTypePickerField extends StatelessWidget {
  final ScheduleType value;
  final ValueChanged<ScheduleType>? onChanged;
  final bool enabled;
  final bool required;

  const HealthScheduleTypePickerField({
    super.key,
    required this.value,
    this.onChanged,
    this.enabled = true,
    this.required = true,
  });

  @override
  Widget build(BuildContext context) {
    final label = HealthScheduleFormatters.typeLabel(value);
    final icon = HealthScheduleFormatters.typeIcon(value);
    final canOpen = enabled && onChanged != null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        HealthFieldLabel(
          HealthScheduleMutationUserCopy.fieldType,
          required: required,
        ),
        Semantics(
          button: true,
          enabled: canOpen,
          label: '${HealthScheduleMutationUserCopy.fieldType}, $label',
          child: Material(
            color: AppTheme.transparent,
            child: InkWell(
              key: const ValueKey('schedule-form-type'),
              borderRadius: BorderRadius.circular(10),
              onTap: canOpen ? () => _openSheet(context) : null,
              child: InputDecorator(
                decoration: InputDecoration(
                  filled: false,
                  contentPadding: const EdgeInsets.fromLTRB(10, 10, 10, 10),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: const BorderSide(color: AppTheme.outline),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: const BorderSide(color: AppTheme.outline),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: const BorderSide(
                      color: AppTheme.primary,
                      width: 1.2,
                    ),
                  ),
                  suffixIcon: Icon(
                    Icons.expand_more_rounded,
                    color: canOpen
                        ? AppTheme.textSecondary
                        : AppTheme.textMuted,
                  ),
                ),
                child: Row(
                  children: [
                    _TypeIconBadge(icon: icon, selected: true, compact: true),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        label,
                        style: GoogleFonts.inter(
                          color: AppTheme.textPrimary,
                          fontWeight: FontWeight.w700,
                          fontSize: 14.5,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _openSheet(BuildContext context) async {
    final selected = await showHealthScheduleTypePickerSheet(
      context,
      selected: value,
    );
    if (selected != null) {
      onChanged?.call(selected);
    }
  }
}

/// Cabeçalho compacto read-only do tipo (formulário Edit).
class HealthScheduleTypeReadOnlyHeader extends StatelessWidget {
  final ScheduleType scheduleType;
  final String? subtitle;

  const HealthScheduleTypeReadOnlyHeader({
    super.key,
    required this.scheduleType,
    this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    final label = HealthScheduleFormatters.typeLabel(scheduleType);
    final icon = HealthScheduleFormatters.typeIcon(scheduleType);
    final sub = (subtitle ?? HealthScheduleMutationUserCopy.typeManualHint)
        .trim();

    return Semantics(
      label: '$label, $sub',
      child: Container(
        key: const ValueKey('schedule-form-type-readonly'),
        padding: const EdgeInsets.fromLTRB(10, 10, 12, 10),
        decoration: BoxDecoration(
          color: AppTheme.surfacePanelSoft.withValues(alpha: 0.9),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppTheme.outline.withValues(alpha: 0.7)),
        ),
        child: Row(
          children: [
            _TypeIconBadge(icon: icon, selected: false, compact: true),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: GoogleFonts.inter(
                      color: AppTheme.textPrimary,
                      fontWeight: FontWeight.w700,
                      fontSize: 14.5,
                    ),
                  ),
                  if (sub.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      sub,
                      style: GoogleFonts.inter(
                        color: AppTheme.textTertiary,
                        fontWeight: FontWeight.w500,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Bottom sheet de seleção de tipo (identidade Health).
Future<ScheduleType?> showHealthScheduleTypePickerSheet(
  BuildContext context, {
  required ScheduleType selected,
}) {
  return showModalBottomSheet<ScheduleType>(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppTheme.surfacePanel,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (ctx) {
      return SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppTheme.outline,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Text(
                HealthScheduleMutationUserCopy.typeSheetTitle,
                style: GoogleFonts.inter(
                  color: AppTheme.textPrimary,
                  fontWeight: FontWeight.w700,
                  fontSize: 17,
                ),
              ),
              const SizedBox(height: 12),
              ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.sizeOf(ctx).height * 0.55,
                ),
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: ScheduleType.values.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    final type = ScheduleType.values[index];
                    final isSelected = type == selected;
                    final label = HealthScheduleFormatters.typeLabel(type);
                    final icon = HealthScheduleFormatters.typeIcon(type);
                    return Material(
                      color: AppTheme.transparent,
                      child: InkWell(
                        key: ValueKey('schedule-type-option-${type.wireName}'),
                        borderRadius: BorderRadius.circular(12),
                        onTap: () => Navigator.of(ctx).pop(type),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 140),
                          padding: const EdgeInsets.fromLTRB(10, 10, 12, 10),
                          decoration: BoxDecoration(
                            color: isSelected
                                ? AppTheme.primary.withValues(alpha: 0.12)
                                : AppTheme.surfacePanelSoft.withValues(
                                    alpha: 0.85,
                                  ),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: isSelected
                                  ? AppTheme.primary.withValues(alpha: 0.55)
                                  : AppTheme.outline.withValues(alpha: 0.7),
                            ),
                          ),
                          child: Row(
                            children: [
                              _TypeIconBadge(
                                icon: icon,
                                selected: isSelected,
                                compact: false,
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  label,
                                  style: GoogleFonts.inter(
                                    color: AppTheme.textPrimary,
                                    fontWeight: isSelected
                                        ? FontWeight.w700
                                        : FontWeight.w600,
                                    fontSize: 14.5,
                                  ),
                                ),
                              ),
                              if (isSelected)
                                const Icon(
                                  Icons.check_circle_rounded,
                                  color: AppTheme.primary,
                                  size: 20,
                                ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
}

class _TypeIconBadge extends StatelessWidget {
  final IconData icon;
  final bool selected;
  final bool compact;

  const _TypeIconBadge({
    required this.icon,
    required this.selected,
    required this.compact,
  });

  @override
  Widget build(BuildContext context) {
    final size = compact ? 36.0 : 40.0;
    final iconSize = compact ? 18.0 : 20.0;
    final accent = selected ? AppTheme.primary : AppTheme.textSecondary;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: accent.withValues(alpha: selected ? 0.16 : 0.10),
        borderRadius: BorderRadius.circular(11),
        border: Border.all(
          color: accent.withValues(alpha: selected ? 0.40 : 0.22),
        ),
      ),
      child: Icon(icon, color: accent.withValues(alpha: 0.95), size: iconSize),
    );
  }
}
