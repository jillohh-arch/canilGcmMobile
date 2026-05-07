import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class ActivityTrackingAction extends StatelessWidget {
  final bool hasRoute;
  final num? distanceMeters;
  final String startLabel;
  final IconData startIcon;
  final Color startBackgroundColor;
  final Color startForegroundColor;
  final VoidCallback onStart;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry capturedMargin;

  const ActivityTrackingAction({
    super.key,
    required this.hasRoute,
    required this.distanceMeters,
    required this.startLabel,
    required this.startIcon,
    required this.startBackgroundColor,
    required this.startForegroundColor,
    required this.onStart,
    this.padding = EdgeInsets.zero,
    this.capturedMargin = EdgeInsets.zero,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: padding,
      child: hasRoute ? _buildCapturedRoute() : _buildStartButton(),
    );
  }

  Widget _buildCapturedRoute() {
    return Container(
      padding: const EdgeInsets.all(16),
      margin: capturedMargin,
      decoration: BoxDecoration(
        color: const Color(0xFF1B8A4C).withAlpha(40),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: const Color(0xFF1B8A4C)),
      ),
      child: Row(
        children: [
          const Icon(Icons.check_circle_rounded, color: Color(0xFF1B8A4C)),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'Rota capturada: ${(distanceMeters ?? 0).toStringAsFixed(0)} m',
              style: GoogleFonts.inter(
                color: Colors.white,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStartButton() {
    return SizedBox(
      width: double.infinity,
      height: 56,
      child: ElevatedButton.icon(
        onPressed: onStart,
        icon: Icon(startIcon, color: startForegroundColor),
        label: Text(
          startLabel,
          style: GoogleFonts.inter(
            fontSize: 14,
            fontWeight: FontWeight.w800,
            color: startForegroundColor,
          ),
        ),
        style: ElevatedButton.styleFrom(
          backgroundColor: startBackgroundColor,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
          elevation: 0,
        ),
      ),
    );
  }
}
