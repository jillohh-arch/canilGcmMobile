import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:latlong2/latlong.dart';

import 'package:canil_gcm/core/services/occurrence_location_service.dart';
import 'package:canil_gcm/core/theme/app_theme.dart';

/// Widget que exibe o mapa de deslocamento de uma ocorrência:
/// pinos numerados por local, trilha conectando, legenda com horários.
/// Tocar num pino chama [onLocationTap] com o índice do local.
class OccurrenceDisplacementMap extends StatelessWidget {
  final List<OccurrenceLocation> locations;
  final void Function(int locationIndex)? onLocationTap;

  const OccurrenceDisplacementMap({
    super.key,
    required this.locations,
    this.onLocationTap,
  });

  @override
  Widget build(BuildContext context) {
    if (locations.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Section label
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Row(
            children: [
              Text(
                'DESLOCAMENTO',
                style: GoogleFonts.inter(
                  color: AppTheme.primary,
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.2,
                ),
              ),
              const Spacer(),
              Text(
                '${locations.length} ${locations.length == 1 ? 'local' : 'locais'}',
                style: GoogleFonts.ibmPlexMono(
                  color: AppTheme.textMuted,
                  fontSize: 10,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
        // Map
        ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: SizedBox(height: 200, child: _buildMap()),
        ),
        const SizedBox(height: 10),
        // Legend
        ..._buildLegend(),
        // Note
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Text(
            'Cada parada marca o local onde uma ou mais ações foram registradas.',
            style: GoogleFonts.inter(
              color: AppTheme.textMuted,
              fontSize: 10.5,
              height: 1.4,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildMap() {
    final points = locations.map((l) => LatLng(l.lat, l.lng)).toList();
    final bounds = LatLngBounds.fromPoints(points);

    return FlutterMap(
      options: MapOptions(
        initialCameraFit: CameraFit.bounds(
          bounds: bounds,
          padding: const EdgeInsets.all(40),
        ),
        interactionOptions: const InteractionOptions(
          flags: InteractiveFlag.pinchZoom | InteractiveFlag.drag,
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
        // Trilha conectando os locais
        if (points.length > 1)
          PolylineLayer(
            polylines: [
              Polyline(
                points: points,
                color: AppTheme.primary,
                strokeWidth: 2.5,
              ),
            ],
          ),
        // Pinos numerados
        MarkerLayer(
          markers: locations.map((loc) {
            final isFirst = loc.index == 1;
            return Marker(
              point: LatLng(loc.lat, loc.lng),
              width: 28,
              height: 28,
              child: GestureDetector(
                onTap: () => onLocationTap?.call(loc.index),
                child: Container(
                  decoration: BoxDecoration(
                    color: isFirst ? AppTheme.success : AppTheme.primary,
                    shape: BoxShape.circle,
                    border: Border.all(color: AppTheme.background, width: 2.5),
                    boxShadow: [
                      BoxShadow(
                        color: (isFirst ? AppTheme.success : AppTheme.primary)
                            .withAlpha(50),
                        blurRadius: 6,
                        spreadRadius: 2,
                      ),
                    ],
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    '${loc.index}',
                    style: GoogleFonts.ibmPlexMono(
                      color: const Color(0xFF04181D),
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }

  List<Widget> _buildLegend() {
    final timeFormat = DateFormat('HH:mm');
    return locations.map((loc) {
      final isFirst = loc.index == 1;
      return Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: GestureDetector(
          onTap: () => onLocationTap?.call(loc.index),
          child: Row(
            children: [
              Container(
                width: 22,
                height: 22,
                decoration: BoxDecoration(
                  color: isFirst ? AppTheme.success : AppTheme.primary,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: (isFirst ? AppTheme.success : AppTheme.primary)
                          .withAlpha(30),
                      blurRadius: 4,
                      spreadRadius: 1,
                    ),
                  ],
                ),
                alignment: Alignment.center,
                child: Text(
                  '${loc.index}',
                  style: GoogleFonts.ibmPlexMono(
                    color: const Color(0xFF04181D),
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  loc.label,
                  style: GoogleFonts.inter(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Text(
                timeFormat.format(loc.arrivedAt),
                style: GoogleFonts.ibmPlexMono(
                  color: AppTheme.textMuted,
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      );
    }).toList();
  }
}
