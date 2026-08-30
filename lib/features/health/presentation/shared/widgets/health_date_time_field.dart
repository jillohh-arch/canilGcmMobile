import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import 'package:canil_gcm/core/theme/app_theme.dart';
import 'package:canil_gcm/features/health/presentation/shared/widgets/health_field_label.dart';

/// Campo de seleção de data e/ou hora no padrão visual do app.
///
/// Não cria [TextEditingController] interno mutável em `build`: o valor
/// exibido é derivado de [value]. O caller controla o estado.
class HealthDateTimeField extends StatelessWidget {
  final String label;
  final DateTime? value;
  final ValueChanged<DateTime>? onChanged;
  final bool includeTime;
  final bool required;
  final bool enabled;
  final Color accentColor;
  final String? hintText;
  final DateTime? firstDate;
  final DateTime? lastDate;

  const HealthDateTimeField({
    super.key,
    required this.label,
    required this.value,
    this.onChanged,
    this.includeTime = false,
    this.required = false,
    this.enabled = true,
    this.accentColor = AppTheme.primary,
    this.hintText,
    this.firstDate,
    this.lastDate,
  });

  @override
  Widget build(BuildContext context) {
    final display = value == null
        ? (hintText ??
              (includeTime ? 'Selecionar data e hora' : 'Selecionar data'))
        : (includeTime
              ? DateFormat('dd/MM/yyyy HH:mm').format(value!)
              : DateFormat('dd/MM/yyyy').format(value!));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        HealthFieldLabel(label, required: required, accentColor: accentColor),
        Semantics(
          button: true,
          enabled: enabled && onChanged != null,
          label: '$label, $display',
          child: Material(
            color: AppTheme.transparent,
            child: InkWell(
              onTap: enabled && onChanged != null ? () => _pick(context) : null,
              borderRadius: BorderRadius.circular(8),
              child: InputDecorator(
                decoration: InputDecoration(
                  filled: false,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 14,
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: const BorderSide(color: AppTheme.outline),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: const BorderSide(color: AppTheme.outline),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide(color: accentColor, width: 1.2),
                  ),
                  suffixIcon: Icon(
                    includeTime
                        ? Icons.event_available_outlined
                        : Icons.calendar_today_outlined,
                    color: accentColor.withValues(alpha: 0.85),
                    size: 20,
                  ),
                ),
                child: Text(
                  display,
                  style: GoogleFonts.inter(
                    color: value == null
                        ? AppTheme.textMuted
                        : AppTheme.textPrimary,
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _pick(BuildContext context) async {
    final now = DateTime.now();
    final first = firstDate ?? DateTime(2000);
    final last = lastDate ?? DateTime(now.year + 10);
    // Clamp evita ArgumentError do DatePicker quando [value] está fora da faixa.
    final initial = _clampDate(value ?? now, first, last);

    final pickedDate = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: first,
      lastDate: last,
    );
    if (pickedDate == null) return;
    if (!includeTime) {
      onChanged?.call(
        DateTime(pickedDate.year, pickedDate.month, pickedDate.day),
      );
      return;
    }

    if (!context.mounted) return;
    final pickedTime = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(initial),
    );
    if (pickedTime == null) return;

    onChanged?.call(
      DateTime(
        pickedDate.year,
        pickedDate.month,
        pickedDate.day,
        pickedTime.hour,
        pickedTime.minute,
      ),
    );
  }

  static DateTime _clampDate(DateTime value, DateTime first, DateTime last) {
    if (value.isBefore(first)) return first;
    if (value.isAfter(last)) return last;
    return value;
  }
}
