import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

part 'occurrence_compact_location_actions.dart';
part 'occurrence_compact_map_adjust_button.dart';

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
        _OccurrenceCompactLocationActions(
          hasLocation: hasLocation,
          gpsColor: gpsColor,
          timeColor: timeColor,
          onCaptureGps: onCaptureGps,
          onSetCurrentTime: onSetCurrentTime,
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
