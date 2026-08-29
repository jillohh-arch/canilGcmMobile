import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:canil_gcm/core/theme/app_theme.dart';
import 'package:canil_gcm/features/health/presentation/shared/forms/health_form_controller.dart';

/// Diálogo padrão de saída com alterações não salvas.
///
/// Retorna `true` se o usuário confirmar a saída, `false` se cancelar.
Future<bool> showHealthUnsavedChangesDialog(
  BuildContext context, {
  String title = 'Alterações não salvas',
  String message =
      'Há alterações que ainda não foram salvas. Deseja sair sem salvar?',
  String confirmLabel = 'Sair sem salvar',
  String cancelLabel = 'Continuar editando',
}) async {
  final result = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (dialogContext) {
      return AlertDialog(
        backgroundColor: AppTheme.surfacePanel,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: Text(
          title,
          style: GoogleFonts.inter(
            color: AppTheme.textPrimary,
            fontWeight: FontWeight.w700,
            fontSize: 18,
          ),
        ),
        content: Text(
          message,
          style: GoogleFonts.inter(
            color: AppTheme.textSecondary,
            fontWeight: FontWeight.w500,
            fontSize: 14,
            height: 1.4,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(
              cancelLabel,
              style: GoogleFonts.inter(
                color: AppTheme.textSecondary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(
              confirmLabel,
              style: GoogleFonts.inter(
                color: AppTheme.error,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      );
    },
  );
  return result ?? false;
}

/// Intercepta pop do Navigator quando o formulário está dirty ou submitting.
///
/// Composição deliberada: não força layout; apenas protege a navegação.
/// - dirty: solicita confirmação antes de sair;
/// - submitting: bloqueia saída sem diálogo (evita perda no meio do save);
/// - pristine: permite pop normal (`canPop: true`).
///
/// Stateful para impedir diálogo duplicado em pops concorrentes (back
/// repetido enquanto o diálogo já está aberto).
class HealthUnsavedChangesGuard extends StatefulWidget {
  final HealthFormController controller;
  final Widget child;
  final String dialogTitle;
  final String dialogMessage;

  const HealthUnsavedChangesGuard({
    super.key,
    required this.controller,
    required this.child,
    this.dialogTitle = 'Alterações não salvas',
    this.dialogMessage =
        'Há alterações que ainda não foram salvas. Deseja sair sem salvar?',
  });

  @override
  State<HealthUnsavedChangesGuard> createState() =>
      _HealthUnsavedChangesGuardState();
}

class _HealthUnsavedChangesGuardState extends State<HealthUnsavedChangesGuard> {
  /// Impede reentrância: segundo back enquanto o diálogo está aberto.
  bool _exitConfirmationInFlight = false;

  bool get _shouldBlockPop =>
      widget.controller.isDirty || widget.controller.isSubmitting;

  Future<void> _handlePopInvoked(bool didPop, Object? result) async {
    if (didPop) return;
    if (widget.controller.isSubmitting) return;
    if (_exitConfirmationInFlight) return;
    if (!widget.controller.isDirty) return;

    _exitConfirmationInFlight = true;
    try {
      final shouldLeave = await showHealthUnsavedChangesDialog(
        context,
        title: widget.dialogTitle,
        message: widget.dialogMessage,
      );
      if (!shouldLeave) return;
      if (!mounted) return;
      // Navigator.pop força a saída mesmo com canPop:false; o PopScope
      // recebe didPop:true e não reabre o diálogo.
      Navigator.of(context).pop(result);
    } finally {
      _exitConfirmationInFlight = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.controller,
      builder: (context, _) {
        return PopScope(
          canPop: !_shouldBlockPop,
          onPopInvokedWithResult: (didPop, result) {
            // Fire-and-forget controlado: o flag de reentrância serializa
            // confirmações concorrentes sem bloquear o frame atual.
            _handlePopInvoked(didPop, result);
          },
          child: widget.child,
        );
      },
    );
  }
}
