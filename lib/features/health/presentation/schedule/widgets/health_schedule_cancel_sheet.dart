import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:canil_gcm/core/theme/app_theme.dart';
import 'package:canil_gcm/features/health/presentation/schedule/health_schedule_action_availability.dart';
import 'package:canil_gcm/features/health/presentation/schedule/health_schedule_mutation_user_copy.dart';
import 'package:canil_gcm/features/health/presentation/shared/widgets/health_field_label.dart';

/// Sheet de cancelamento com motivo obrigatório.
///
/// Retorna o motivo trimado ou null se cancelado pelo usuário.
Future<String?> showHealthScheduleCancelSheet(
  BuildContext context, {
  String? itemTitle,
}) {
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppTheme.surfacePanel,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (ctx) {
      return _CancelReasonSheet(itemTitle: itemTitle);
    },
  );
}

class _CancelReasonSheet extends StatefulWidget {
  final String? itemTitle;

  const _CancelReasonSheet({this.itemTitle});

  @override
  State<_CancelReasonSheet> createState() => _CancelReasonSheetState();
}

class _CancelReasonSheetState extends State<_CancelReasonSheet> {
  final _controller = TextEditingController();
  String? _error;
  bool _submitting = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _confirm() {
    if (_submitting) return;
    final reason = _controller.text.trim();
    if (reason.isEmpty) {
      setState(
        () => _error = HealthScheduleMutationUserCopy.cancelReasonRequired,
      );
      return;
    }
    if (reason.length >
        HealthScheduleActionAvailability.maxCancelReasonLength) {
      setState(
        () => _error = HealthScheduleMutationUserCopy.cancelReasonTooLong,
      );
      return;
    }
    setState(() {
      _submitting = true;
      _error = null;
    });
    Navigator.of(context).pop(reason);
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.viewInsetsOf(context).bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 12, 16, 16 + bottom),
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
            HealthScheduleMutationUserCopy.cancelSheetTitle,
            style: GoogleFonts.inter(
              color: AppTheme.textPrimary,
              fontWeight: FontWeight.w700,
              fontSize: 17,
            ),
          ),
          if (widget.itemTitle != null &&
              widget.itemTitle!.trim().isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              widget.itemTitle!.trim(),
              style: GoogleFonts.inter(
                color: AppTheme.textSecondary,
                fontWeight: FontWeight.w500,
                fontSize: 13.5,
              ),
            ),
          ],
          const SizedBox(height: 16),
          HealthFieldLabel(
            HealthScheduleMutationUserCopy.cancelReasonLabel,
            required: true,
            accentColor: AppTheme.error,
          ),
          TextField(
            key: const ValueKey('schedule-cancel-reason'),
            controller: _controller,
            enabled: !_submitting,
            maxLines: 3,
            maxLength: HealthScheduleActionAvailability.maxCancelReasonLength,
            autofocus: true,
            style: GoogleFonts.inter(
              color: AppTheme.textPrimary,
              fontWeight: FontWeight.w500,
              fontSize: 14,
            ),
            decoration: InputDecoration(
              hintText: 'Descreva o motivo',
              hintStyle: GoogleFonts.inter(
                color: AppTheme.textMuted,
                fontSize: 14,
              ),
              errorText: _error,
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
                borderSide: const BorderSide(color: AppTheme.error, width: 1.2),
              ),
            ),
            onChanged: (_) {
              if (_error != null) setState(() => _error = null);
            },
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  key: const ValueKey('schedule-cancel-dismiss'),
                  onPressed: _submitting
                      ? null
                      : () => Navigator.of(context).pop(),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppTheme.textSecondary,
                    side: BorderSide(color: AppTheme.outline),
                    minimumSize: const Size.fromHeight(48),
                  ),
                  child: Text(
                    HealthScheduleMutationUserCopy.cancelDismiss,
                    style: GoogleFonts.inter(fontWeight: FontWeight.w600),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FilledButton(
                  key: const ValueKey('schedule-cancel-confirm'),
                  onPressed: _submitting ? null : _confirm,
                  style: FilledButton.styleFrom(
                    backgroundColor: AppTheme.error,
                    foregroundColor: AppTheme.textPrimary,
                    minimumSize: const Size.fromHeight(48),
                  ),
                  child: Text(
                    HealthScheduleMutationUserCopy.cancelConfirm,
                    style: GoogleFonts.inter(fontWeight: FontWeight.w700),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
