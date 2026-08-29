import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:canil_gcm/core/theme/app_theme.dart';
import 'package:canil_gcm/features/health/presentation/shared/forms/health_form_controller.dart';

/// Área padronizada de ações de formulário (salvar / feedback).
///
/// Conceito arquitetural: StickySaveBar. Implementação deliberadamente
/// enxuta — o sticky é responsabilidade do [HealthFormScaffold.bottomBar].
class HealthFormActions extends StatelessWidget {
  final HealthFormController controller;
  final VoidCallback onSubmit;
  final String submitLabel;
  final String submittingLabel;
  final Color accentColor;
  final bool enabled;

  const HealthFormActions({
    super.key,
    required this.controller,
    required this.onSubmit,
    this.submitLabel = 'SALVAR',
    this.submittingLabel = 'SALVANDO...',
    this.accentColor = AppTheme.primary,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final isSubmitting = controller.isSubmitting;
        final canPress = enabled && controller.canSubmit && !isSubmitting;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (controller.hasError && controller.errorMessage != null) ...[
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: AppTheme.error.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: AppTheme.error.withValues(alpha: 0.45),
                  ),
                ),
                child: Text(
                  controller.errorMessage!,
                  softWrap: true,
                  style: GoogleFonts.inter(
                    color: AppTheme.error,
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                  ),
                ),
              ),
              const SizedBox(height: 10),
            ],
            SizedBox(
              height: 52,
              child: ElevatedButton(
                onPressed: canPress ? onSubmit : null,
                style: ElevatedButton.styleFrom(
                  backgroundColor: accentColor,
                  disabledBackgroundColor: AppTheme.outline,
                  foregroundColor: AppTheme.background,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                child: isSubmitting
                    ? Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.2,
                              valueColor: AlwaysStoppedAnimation<Color>(
                                AppTheme.textPrimary,
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Text(
                            submittingLabel,
                            style: GoogleFonts.inter(
                              fontWeight: FontWeight.w800,
                              fontSize: 13,
                              letterSpacing: 0.6,
                              color: AppTheme.textPrimary,
                            ),
                          ),
                        ],
                      )
                    : Text(
                        submitLabel,
                        style: GoogleFonts.inter(
                          fontWeight: FontWeight.w800,
                          fontSize: 13,
                          letterSpacing: 0.6,
                          color: canPress
                              ? AppTheme.background
                              : AppTheme.textMuted,
                        ),
                      ),
              ),
            ),
          ],
        );
      },
    );
  }
}
