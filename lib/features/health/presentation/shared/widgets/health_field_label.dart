import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:canil_gcm/core/theme/app_theme.dart';

/// Label padronizado para campos de formulário Health.
class HealthFieldLabel extends StatelessWidget {
  final String text;
  final bool required;
  final Color accentColor;
  final EdgeInsetsGeometry padding;

  const HealthFieldLabel(
    this.text, {
    super.key,
    this.required = false,
    this.accentColor = AppTheme.primary,
    this.padding = const EdgeInsets.only(bottom: 6),
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: padding,
      child: Text.rich(
        TextSpan(
          text: text.toUpperCase(),
          style: GoogleFonts.inter(
            color: accentColor.withValues(alpha: 0.85),
            fontSize: 11,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.9,
          ),
          children: [
            if (required)
              TextSpan(
                text: ' *',
                style: GoogleFonts.inter(
                  color: AppTheme.error,
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                ),
              ),
          ],
        ),
      ),
    );
  }
}
