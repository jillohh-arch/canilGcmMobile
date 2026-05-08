part of 'daily_timeline_screen.dart';

extension _DailyTimelineEntryTrackingRoute on _DailyTimelineScreenState {
  List<Widget> _buildTimelineRouteSection(_TimelineEntry entry) {
    final route = _timelineTrackingRoute(entry);
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

  List<LatLng> _timelineTrackingRoute(_TimelineEntry entry) {
    final rawRoute =
        entry.details['_trackingRoute'] ?? entry.details['_trackingroute'];
    if (rawRoute is! List) {
      return const [];
    }

    return rawRoute
        .whereType<Map>()
        .map<LatLng>(
          (point) => LatLng(
            (point['lat'] as num).toDouble(),
            (point['lng'] as num).toDouble(),
          ),
        )
        .toList();
  }
}
