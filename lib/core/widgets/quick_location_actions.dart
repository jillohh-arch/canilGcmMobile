import 'package:flutter/material.dart';

import 'package:canil_gcm/core/theme/app_theme.dart';
import 'package:google_fonts/google_fonts.dart';

class QuickLocationActions extends StatelessWidget {
  final Color backgroundColor;
  final Color gpsColor;
  final Color timeColor;
  final VoidCallback onCaptureGps;
  final VoidCallback onSetCurrentTime;

  const QuickLocationActions({
    super.key,
    required this.backgroundColor,
    required this.gpsColor,
    required this.timeColor,
    required this.onCaptureGps,
    required this.onSetCurrentTime,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: ElevatedButton.icon(
            onPressed: onCaptureGps,
            icon: const Icon(
              Icons.gps_fixed_rounded,
              size: 18,
              color: AppTheme.background,
            ),
            label: Text(
              'CAPTURAR GPS',
              style: GoogleFonts.inter(
                fontSize: 10,
                color: backgroundColor,
                fontWeight: FontWeight.w900,
                letterSpacing: 1.0,
              ),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: gpsColor,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(6),
              ),
              padding: const EdgeInsets.symmetric(vertical: 16),
              elevation: 2,
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: ElevatedButton.icon(
            onPressed: onSetCurrentTime,
            icon: const Icon(
              Icons.schedule_rounded,
              size: 18,
              color: AppTheme.textPrimary,
            ),
            label: Text(
              'HORA ATUAL',
              style: GoogleFonts.inter(
                fontSize: 10,
                color: AppTheme.textPrimary,
                fontWeight: FontWeight.w900,
                letterSpacing: 1.0,
              ),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: timeColor.withAlpha(160),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(6),
              ),
              padding: const EdgeInsets.symmetric(vertical: 16),
              elevation: 2,
            ),
          ),
        ),
      ],
    );
  }
}
