import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import 'package:canil_gcm/core/widgets/quick_location_actions.dart';
import 'occurrence_location_map.dart';

class OccurrenceLocationStep extends StatelessWidget {
  final Widget locationField;
  final Widget timeField;
  final LatLng? selectedLocation;
  final Color backgroundColor;
  final Color gpsColor;
  final Color timeColor;
  final VoidCallback onCaptureGps;
  final VoidCallback onSetCurrentTime;
  final ValueChanged<LatLng> onLocationChanged;

  const OccurrenceLocationStep({
    super.key,
    required this.locationField,
    required this.timeField,
    required this.selectedLocation,
    required this.backgroundColor,
    required this.gpsColor,
    required this.timeColor,
    required this.onCaptureGps,
    required this.onSetCurrentTime,
    required this.onLocationChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        QuickLocationActions(
          backgroundColor: backgroundColor,
          gpsColor: gpsColor,
          timeColor: timeColor,
          onCaptureGps: onCaptureGps,
          onSetCurrentTime: onSetCurrentTime,
        ),
        const SizedBox(height: 16),
        locationField,
        const SizedBox(height: 12),
        timeField,
        if (selectedLocation != null) ...[
          const SizedBox(height: 14),
          OccurrenceLocationMap(
            location: selectedLocation!,
            onLocationChanged: onLocationChanged,
          ),
        ],
      ],
    );
  }
}
