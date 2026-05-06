import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

class OccurrenceLocationMap extends StatelessWidget {
  final LatLng location;
  final ValueChanged<LatLng> onLocationChanged;

  const OccurrenceLocationMap({
    super.key,
    required this.location,
    required this.onLocationChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Toque no mapa para ajustar o ponto exato.',
          style: GoogleFonts.inter(
            color: Colors.white54,
            fontSize: 11,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: SizedBox(
            height: 220,
            child: GoogleMap(
              initialCameraPosition: CameraPosition(target: location, zoom: 18),
              myLocationButtonEnabled: false,
              zoomControlsEnabled: false,
              onTap: onLocationChanged,
              markers: {
                Marker(
                  markerId: const MarkerId('occurrence_location'),
                  position: location,
                  draggable: true,
                  onDragEnd: onLocationChanged,
                ),
              },
            ),
          ),
        ),
      ],
    );
  }
}
