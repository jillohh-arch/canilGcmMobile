part of 'dynamic_activity_sheet.dart';

// ignore_for_file: invalid_use_of_protected_member

extension _DynamicActivitySheetStatus on _DynamicActivitySheetState {
  void _setSaveStatus(String status, {bool failed = false}) {
    if (!mounted) return;
    setState(() {
      _saveStatus = status;
      _saveFailed = failed;
    });
  }

  void _updateState(VoidCallback update) {
    if (!mounted) return;
    setState(update);
  }

  void _closeForm([bool result = false]) {
    if (_isSaving) {
      HapticFeedback.lightImpact();
      _showOperationalSnack(
        'Aguarde a sincronização terminar antes de sair.',
        backgroundColor: AppTheme.warningAccent,
        foregroundColor: AppTheme.background,
      );
      return;
    }

    Navigator.pop(context, result);
  }

  void _showOperationalSnack(
    String message, {
    Color backgroundColor = AppTheme.surfaceSnack,
    Color foregroundColor = AppTheme.textPrimary,
    IconData? icon,
  }) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        backgroundColor: backgroundColor,
        content: Row(
          children: [
            if (icon != null) ...[
              Icon(icon, size: 18, color: foregroundColor),
              const SizedBox(width: 10),
            ],
            Expanded(
              child: Text(
                message,
                style: GoogleFonts.inter(
                  color: foregroundColor,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _cleanSaveError(Object error) {
    final raw = error.toString();
    return raw
        .replaceFirst('Exception: ', '')
        .replaceFirst('FirebaseException: ', '')
        .trim();
  }

  String _formatTimeOfDay(DateTime value) {
    return const PtBrDateTimeService().time(value);
  }

  String _formatDatePtBr(DateTime value) {
    return const PtBrDateTimeService().date(value);
  }

  String _successSaveMessage() {
    return ActivityFormLabels.successSaveMessage(category: widget.category);
  }
}
