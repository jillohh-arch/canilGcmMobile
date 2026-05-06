import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class OccurrenceCompactLocationBlock extends StatelessWidget {
  final bool hasLocation;
  final bool showMapAdjust;
  final Color gpsColor;
  final Color timeColor;
  final Color accentColor;
  final Widget locationField;
  final Widget timeField;
  final VoidCallback onCaptureGps;
  final VoidCallback onSetCurrentTime;
  final VoidCallback onAdjustMap;

  const OccurrenceCompactLocationBlock({
    super.key,
    required this.hasLocation,
    required this.showMapAdjust,
    required this.gpsColor,
    required this.timeColor,
    required this.accentColor,
    required this.locationField,
    required this.timeField,
    required this.onCaptureGps,
    required this.onSetCurrentTime,
    required this.onAdjustMap,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: _OccurrenceMiniCommandButton(
                icon: Icons.gps_fixed_rounded,
                label: hasLocation ? 'ATUALIZAR GPS' : 'CAPTURAR GPS',
                color: gpsColor,
                onTap: onCaptureGps,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _OccurrenceMiniCommandButton(
                icon: Icons.schedule_rounded,
                label: 'HORA ATUAL',
                color: timeColor,
                onTap: onSetCurrentTime,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        locationField,
        const SizedBox(height: 12),
        timeField,
        if (showMapAdjust) ...[
          const SizedBox(height: 12),
          _OccurrenceMapAdjustButton(
            accentColor: accentColor,
            onTap: onAdjustMap,
          ),
        ],
      ],
    );
  }
}

class _OccurrenceMiniCommandButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _OccurrenceMiniCommandButton({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 54,
      child: OutlinedButton.icon(
        onPressed: onTap,
        icon: Icon(icon, color: color, size: 18),
        label: Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: GoogleFonts.robotoMono(
            color: Colors.white,
            fontSize: 10,
            fontWeight: FontWeight.w900,
            letterSpacing: 1.0,
          ),
        ),
        style: OutlinedButton.styleFrom(
          backgroundColor: color.withAlpha(16),
          side: BorderSide(color: color.withAlpha(125)),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
          padding: const EdgeInsets.symmetric(horizontal: 10),
        ),
      ),
    );
  }
}

class _OccurrenceMapAdjustButton extends StatelessWidget {
  final Color accentColor;
  final VoidCallback onTap;

  const _OccurrenceMapAdjustButton({
    required this.accentColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(6),
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        decoration: BoxDecoration(
          color: accentColor.withAlpha(13),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: accentColor.withAlpha(95)),
        ),
        child: Row(
          children: [
            Icon(Icons.map_rounded, color: accentColor, size: 18),
            const SizedBox(width: 9),
            Expanded(
              child: Text(
                'AJUSTAR PONTO NO MAPA',
                style: GoogleFonts.robotoMono(
                  color: Colors.white,
                  fontSize: 10,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1.2,
                ),
              ),
            ),
            Icon(Icons.open_in_full_rounded, color: accentColor, size: 16),
          ],
        ),
      ),
    );
  }
}
