import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import 'package:canil_gcm/core/theme/app_map_style.dart';
import 'package:canil_gcm/core/theme/app_theme.dart';

/// Widget reutilizável que exibe o mapa da rota GPS + métricas
/// no detalhe do histórico. Recebe o objeto `gps_track` do metadata.
class GpsTrackDetailWidget extends StatelessWidget {
  final Map<String, dynamic> gpsTrack;

  const GpsTrackDetailWidget({super.key, required this.gpsTrack});

  @override
  Widget build(BuildContext context) {
    final points = _parsePoints();
    if (points.isEmpty) return const SizedBox.shrink();

    final distanceM = (gpsTrack['distance_m'] as num?)?.toDouble() ?? 0;
    final durationS = (gpsTrack['duration_s'] as num?)?.toInt() ?? 0;
    final avgPace = (gpsTrack['avg_pace_s_per_km'] as num?)?.toInt() ?? 0;
    final avgSpeed = (gpsTrack['avg_speed_kmh'] as num?)?.toDouble() ?? 0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Section label
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Text(
            'RASTREAMENTO GPS',
            style: GoogleFonts.inter(
              color: AppTheme.primary,
              fontSize: 10,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.2,
            ),
          ),
        ),
        // Map
        ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: SizedBox(height: 200, child: _buildMap(points)),
        ),
        const SizedBox(height: 12),
        // Metrics grid
        Row(
          children: [
            _metric('Distância', '${(distanceM / 1000).toStringAsFixed(2)} km'),
            const SizedBox(width: 8),
            _metric('Tempo', _formatDuration(durationS)),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            _metric('Ritmo', _formatPace(avgPace)),
            const SizedBox(width: 8),
            _metric('Vel. média', '${avgSpeed.toStringAsFixed(1)} km/h'),
          ],
        ),
        const SizedBox(height: 16),
      ],
    );
  }

  Widget _buildMap(List<LatLng> points) {
    final bounds = AppMapStyle.boundsFromPoints(points);

    return GoogleMap(
      initialCameraPosition: CameraPosition(
        target: points.first,
        zoom: 15,
      ),
      style: AppMapStyle.darkStyle,
      rotateGesturesEnabled: false,
      zoomControlsEnabled: false,
      myLocationButtonEnabled: false,
      mapToolbarEnabled: false,
      onMapCreated: (controller) {
        controller.animateCamera(
          CameraUpdate.newLatLngBounds(bounds, 30),
        );
      },
      polylines: {
        Polyline(
          polylineId: const PolylineId('gps_track'),
          points: points,
          color: AppTheme.primary,
          width: 4,
        ),
      },
      markers: {
        Marker(
          markerId: const MarkerId('start'),
          position: points.first,
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen),
        ),
        Marker(
          markerId: const MarkerId('end'),
          position: points.last,
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
        ),
      },
    );
  }

  Widget _metric(String label, String value) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 10),
        decoration: BoxDecoration(
          color: AppTheme.surfaceWhiteOverlayWeak,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: AppTheme.surfaceWhiteBorderSubtle,
            width: 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label.toUpperCase(),
              style: GoogleFonts.inter(
                color: AppTheme.textMuted,
                fontSize: 8.5,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.5,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              value,
              style: GoogleFonts.ibmPlexMono(
                color: AppTheme.textPrimary,
                fontSize: 15,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<LatLng> _parsePoints() {
    final raw = gpsTrack['points'];
    if (raw is! List || raw.isEmpty) return [];
    return raw
        .whereType<Map>()
        .map((p) {
          final lat = (p['lat'] as num?)?.toDouble();
          final lng = (p['lng'] as num?)?.toDouble();
          if (lat == null || lng == null) return null;
          return LatLng(lat, lng);
        })
        .whereType<LatLng>()
        .toList();
  }

  String _formatDuration(int seconds) {
    final h = seconds ~/ 3600;
    final m = (seconds % 3600) ~/ 60;
    final s = seconds % 60;
    if (h > 0) return '${h}h${m.toString().padLeft(2, '0')}';
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  String _formatPace(int paceSeconds) {
    if (paceSeconds <= 0) return '--';
    final min = paceSeconds ~/ 60;
    final sec = paceSeconds % 60;
    return "$min'${sec.toString().padLeft(2, '0')}\"/km";
  }
}
