part of 'daily_timeline_screen.dart';

extension _DailyTimelineEntryTracking on _DailyTimelineScreenState {
  List<Widget> _buildTimelineTrackingSections(
    _TimelineEntry entry,
    Color color,
  ) {
    return [
      ..._buildTimelineDistanceSection(entry, color),
      ..._buildTimelineRouteSection(entry),
    ];
  }

  List<Widget> _buildTimelineDistanceSection(
    _TimelineEntry entry,
    Color color,
  ) {
    final rawDistance =
        entry.details['_trackingDistance'] ??
        entry.details['_trackingdistance'];
    if (rawDistance is! num) {
      return const [];
    }

    final distance = rawDistance.toDouble();
    final distanceLabel = distance > 999
        ? '${(distance / 1000).toStringAsFixed(1)} km'
        : '${distance.toStringAsFixed(1)} m';

    return [
      const SizedBox(height: 8),
      Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: const Color(0xFF070B14).withAlpha(220),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: color.withAlpha(140), width: 1),
        ),
        child: Row(
          children: [
            Icon(Icons.straighten_rounded, color: color, size: 16),
            const SizedBox(width: 8),
            Text(
              'DISTÂNCIA TOTAL PERCORRIDA: ',
              style: GoogleFonts.robotoMono(
                color: color.withAlpha(210),
                fontSize: 10,
                fontWeight: FontWeight.w800,
              ),
            ),
            Text(
              distanceLabel,
              style: GoogleFonts.oxanium(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.w900,
                letterSpacing: 0.5,
              ),
            ),
          ],
        ),
      ),
    ];
  }

  List<Widget> _buildTimelineRouteSection(_TimelineEntry entry) {
    final rawRoute =
        entry.details['_trackingRoute'] ?? entry.details['_trackingroute'];
    if (rawRoute is! List) {
      return const [];
    }

    final route = rawRoute
        .map<LatLng>(
          (point) => LatLng(
            (point['lat'] as num).toDouble(),
            (point['lng'] as num).toDouble(),
          ),
        )
        .toList();

    if (route.isEmpty) {
      return const [];
    }

    return [
      const SizedBox(height: 12),
      ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: SizedBox(
          height: 200,
          width: double.infinity,
          child: GoogleMap(
            style: _darkMapStyle,
            initialCameraPosition: CameraPosition(
              target: route.first,
              zoom: 15,
            ),
            onMapCreated: (controller) {
              Future.delayed(const Duration(milliseconds: 500), () {
                controller.animateCamera(
                  CameraUpdate.newLatLngBounds(_getBounds(route), 32),
                );
              });
            },
            polylines: {
              Polyline(
                polylineId: PolylineId(
                  'route_${entry.time.millisecondsSinceEpoch}',
                ),
                points: route,
                color: const Color(0xFFFBBF24),
                width: 4,
              ),
            },
            scrollGesturesEnabled: false,
            zoomGesturesEnabled: false,
            tiltGesturesEnabled: false,
            rotateGesturesEnabled: false,
            myLocationButtonEnabled: false,
            zoomControlsEnabled: false,
            mapToolbarEnabled: false,
          ),
        ),
      ),
    ];
  }
}
