import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:canil_gcm/core/theme/app_theme.dart';

class StartOccurrenceCta extends StatelessWidget {
  final bool isLoading;
  final VoidCallback onPressed;

  const StartOccurrenceCta({
    super.key,
    this.isLoading = false,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            AppTheme.background.withAlpha(0),
            AppTheme.background,
          ],
          stops: const [0.0, 0.3],
        ),
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          width: double.infinity,
          height: 56,
          child: ElevatedButton(
            onPressed: isLoading ? null : onPressed,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primary,
              foregroundColor: AppTheme.background,
              disabledBackgroundColor: AppTheme.primary.withAlpha(100),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
              elevation: 0,
            ),
            child: isLoading
                ? SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.5,
                      color: AppTheme.background,
                    ),
                  )
                : Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Text('▶', style: TextStyle(fontSize: 14)),
                      const SizedBox(width: 10),
                      Text(
                        'INICIAR OCORRÊNCIA',
                        style: GoogleFonts.inter(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 1.0,
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
