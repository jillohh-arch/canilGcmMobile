import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:canil_gcm/core/theme/app_theme.dart';
import 'package:canil_gcm/features/health/presentation/timeline/widgets/health_timeline_user_copy.dart';

/// Bloco institucional discreto ao fim da timeline (mockup Histórico).
///
/// Só deve ser exibido quando [hasMore] == false.
class HealthTimelineInstitutionalFooter extends StatelessWidget {
  const HealthTimelineInstitutionalFooter({super.key, this.dogDisplayName});

  /// Nome do K9 para copy contextual (opcional).
  final String? dogDisplayName;

  @override
  Widget build(BuildContext context) {
    final name = dogDisplayName?.trim();
    final message = (name == null || name.isEmpty)
        ? HealthTimelineUserCopy.institutionalFooterGeneric
        : HealthTimelineUserCopy.institutionalFooterForDog(name);

    return Semantics(
      label: message,
      child: Container(
        margin: const EdgeInsets.fromLTRB(0, 8, 0, 8),
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          color: AppTheme.surfacePanelSoft.withValues(alpha: 0.9),
          border: Border.all(color: AppTheme.surfaceWhiteBorder),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              Icons.verified_user_outlined,
              size: 18,
              color: AppTheme.primary.withValues(alpha: 0.85),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                message,
                style: GoogleFonts.inter(
                  color: AppTheme.textSoft,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w500,
                  height: 1.4,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
