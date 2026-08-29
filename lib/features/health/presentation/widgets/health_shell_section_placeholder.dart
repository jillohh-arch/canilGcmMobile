import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:canil_gcm/core/theme/app_theme.dart';
import 'package:canil_gcm/features/health/presentation/widgets/health_shell_section.dart';

/// Conteúdo estrutural neutro para testes e demos do shell.
///
/// **Não** é default de [HealthShellScreen]: a API exige builders
/// obrigatórios, de forma que placeholders só apareçam se o caller
/// os injetar explicitamente.
///
/// Não simula dados clínicos, K9, prontidão ou indicadores.
class HealthShellSectionPlaceholder extends StatelessWidget {
  /// Prefixo estável para asserts e para deixar o caráter temporário óbvio.
  static const String structuralBanner = 'SHELL ESTRUTURAL';

  final HealthShellSection section;
  final String? message;

  const HealthShellSectionPlaceholder({
    super.key,
    required this.section,
    this.message,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(section.icon, size: 36, color: AppTheme.textMuted),
            const SizedBox(height: 12),
            Text(
              structuralBanner,
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(
                color: AppTheme.primary,
                fontWeight: FontWeight.w800,
                fontSize: 11,
                letterSpacing: 1.2,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              section.label,
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(
                color: AppTheme.textPrimary,
                fontWeight: FontWeight.w700,
                fontSize: 16,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              message ??
                  'Placeholder estrutural do shell — não é conteúdo clínico. '
                      'Substitua este builder na integração real.',
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(
                color: AppTheme.textSoft,
                fontWeight: FontWeight.w500,
                fontSize: 13,
                height: 1.4,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
