import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:canil_gcm/core/theme/app_theme.dart';

/// Cabeçalho do módulo Health v1.0 (abaixo do App Shell global).
///
/// Reproduz o bloco do mockup 01:
/// - título "SAÚDE E PRONTIDÃO"
/// - subtítulo institucional
/// - ação "+ Registrar" (callback isolado, sem I/O)
class HealthModuleHeader extends StatelessWidget {
  static const String title = 'SAÚDE E PRONTIDÃO';
  static const String subtitle =
      'Situação operacional, cuidados e registros do K9';

  final VoidCallback? onRegister;
  final String registerLabel;

  const HealthModuleHeader({
    super.key,
    this.onRegister,
    this.registerLabel = 'Registrar',
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 360;
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: GoogleFonts.inter(
                      color: AppTheme.textPrimary,
                      fontSize: compact ? 18 : 20,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.4,
                      height: 1.15,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: GoogleFonts.inter(
                      color: AppTheme.textSecondary,
                      fontSize: compact ? 12 : 13,
                      fontWeight: FontWeight.w500,
                      height: 1.35,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            _RegisterButton(
              label: registerLabel,
              onPressed: onRegister,
              compact: compact,
            ),
          ],
        );
      },
    );
  }
}

class _RegisterButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final bool compact;

  const _RegisterButton({
    required this.label,
    required this.onPressed,
    required this.compact,
  });

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null;
    return Semantics(
      button: true,
      enabled: enabled,
      label: '+ $label',
      excludeSemantics: true,
      child: Material(
        color: AppTheme.transparent,
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(12),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            constraints: const BoxConstraints(minHeight: 44),
            padding: EdgeInsets.symmetric(
              horizontal: compact ? 12 : 14,
              vertical: compact ? 9 : 10,
            ),
            decoration: BoxDecoration(
              color: enabled
                  ? AppTheme.primary.withValues(alpha: 0.10)
                  : AppTheme.surfacePanel,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: enabled
                    ? AppTheme.primary.withValues(alpha: 0.85)
                    : AppTheme.outline,
                width: 1.2,
              ),
            ),
            alignment: Alignment.center,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.add_rounded,
                  size: compact ? 16 : 18,
                  color: enabled ? AppTheme.primary : AppTheme.textMuted,
                ),
                const SizedBox(width: 4),
                Text(
                  label,
                  style: GoogleFonts.inter(
                    color: enabled ? AppTheme.primary : AppTheme.textMuted,
                    fontSize: compact ? 12 : 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
