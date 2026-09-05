import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:intl/intl.dart';

import 'package:canil_gcm/core/services/occurrence_location_service.dart';
import 'package:canil_gcm/core/theme/app_map_style.dart';
import 'package:canil_gcm/core/theme/app_theme.dart';

/// Widget que exibe o mapa de deslocamento de uma ocorrência:
/// pinos numerados por local, trilha conectando, legenda com horários.
/// Tocar num pino chama [onLocationTap] com o índice do local.
class OccurrenceDisplacementMap extends StatefulWidget {
  final List<OccurrenceLocation> locations;
  final void Function(int locationIndex)? onLocationTap;

  const OccurrenceDisplacementMap({
    super.key,
    required this.locations,
    this.onLocationTap,
  });

  @override
  State<OccurrenceDisplacementMap> createState() =>
      _OccurrenceDisplacementMapState();
}

class _OccurrenceDisplacementMapState extends State<OccurrenceDisplacementMap> {
  final Map<int, BitmapDescriptor> _customIcons = {};

  @override
  void initState() {
    super.initState();
    _loadMarkerIcons();
  }

  @override
  void didUpdateWidget(OccurrenceDisplacementMap oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.locations != oldWidget.locations) {
      _loadMarkerIcons();
    }
  }

  Future<void> _loadMarkerIcons() async {
    for (final loc in widget.locations) {
      final icon = await AppMapStyle.createNumberedMarkerIcon(
        number: loc.index,
        isFirst: loc.index == 1,
      );
      if (mounted) {
        setState(() {
          _customIcons[loc.index] = icon;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.locations.isEmpty) return const SizedBox.shrink();

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
                '${widget.locations.length} ${widget.locations.length == 1 ? 'local' : 'locais'}',
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
    final points = widget.locations
        .map((l) => LatLng(l.lat, l.lng))
        .toList();
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
          CameraUpdate.newLatLngBounds(bounds, 40),
        );
      },
      polylines: points.length > 1
          ? {
              Polyline(
                polylineId: const PolylineId('displacement_track'),
                points: points,
                color: AppTheme.primary,
                width: 3,
              ),
            }
          : {},
      markers: widget.locations.map((loc) {
        final isFirst = loc.index == 1;
        final icon = _customIcons[loc.index] ??
            BitmapDescriptor.defaultMarkerWithHue(
              isFirst ? BitmapDescriptor.hueGreen : BitmapDescriptor.hueCyan,
            );
        return Marker(
          markerId: MarkerId('loc_${loc.index}'),
          position: LatLng(loc.lat, loc.lng),
          icon: icon,
          infoWindow: InfoWindow(
            title: 'Local ${loc.index}',
            snippet: loc.label,
          ),
          onTap: () => widget.onLocationTap?.call(loc.index),
        );
      }).toSet(),
    );
  }

  List<Widget> _buildLegend() {
    final timeFormat = DateFormat('HH:mm');
    return widget.locations.map((loc) {
      final isFirst = loc.index == 1;
      return Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: GestureDetector(
          onTap: () => widget.onLocationTap?.call(loc.index),
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
                    color: AppTheme.background,
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
                    color: AppTheme.textPrimary,
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
