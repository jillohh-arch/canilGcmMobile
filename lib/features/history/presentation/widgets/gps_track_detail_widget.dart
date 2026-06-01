import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:latlong2/latlong.dart';

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
    final bounds = LatLngBounds.fromPoints(points);

    return FlutterMap(
      options: MapOptions(
        initialCameraFit: CameraFit.bounds(
          bounds: bounds,
          padding: const EdgeInsets.all(30),
        ),
        interactionOptions: const InteractionOptions(
          flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
        ),
      ),
      children: [
        TileLayer(
          urlTemplate:
              'https://{s}.basemaps.cartocdn.com/dark_all/{z}/{x}/{y}@2x.png',
          subdomains: const ['a', 'b', 'c', 'd'],
          userAgentPackageName: 'com.gcm.limeira.canilk9',
          maxZoom: 19,
        ),
        PolylineLayer(
          polylines: [
            Polyline(points: points, color: AppTheme.primary, strokeWidth: 4),
          ],
        ),
        MarkerLayer(
          markers: [
            // Start (green)
            Marker(
              point: points.first,
              width: 14,
              height: 14,
              child: Container(
                decoration: BoxDecoration(
                  color: AppTheme.success,
                  shape: BoxShape.circle,
                  border: Border.all(color: AppTheme.background, width: 2),
                ),
              ),
            ),
            // End (red)
            Marker(
              point: points.last,
              width: 14,
              height: 14,
              child: Container(
                decoration: BoxDecoration(
                  color: AppTheme.error,
                  shape: BoxShape.circle,
                  border: Border.all(color: AppTheme.background, width: 2),
                ),
              ),
            ),
          ],
        ),
      ],
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
