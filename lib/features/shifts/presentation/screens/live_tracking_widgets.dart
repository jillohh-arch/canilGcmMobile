part of 'live_tracking_screen.dart';

class _CloseTrackingButton extends StatelessWidget {
  const _CloseTrackingButton();

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: AppTheme.background.withAlpha(115),
        shape: BoxShape.circle,
      ),
      child: IconButton(
        icon: const Icon(Icons.close_rounded, color: AppTheme.textPrimary),
        onPressed: () => Navigator.pop(context),
      ),
    );
  }
}

class _TrackingMap extends StatelessWidget {
  final void Function(GoogleMapController controller)? onMapCreated;
  final List<ll2.LatLng> routePoints;
  final bool isLightMode;

  const _TrackingMap({
    required this.onMapCreated,
    required this.routePoints,
    required this.isLightMode,
  });

  @override
  Widget build(BuildContext context) {
    final gmapRoute = AppMapStyle.toGoogleLatLngList(routePoints);

    return GoogleMap(
      initialCameraPosition: const CameraPosition(
        target: LatLng(-22.5647, -47.4013), // Limeira/SP
        zoom: 14,
      ),
      style: isLightMode ? null : AppMapStyle.darkStyle,
      rotateGesturesEnabled: false,
      zoomControlsEnabled: false,
      myLocationButtonEnabled: false,
      mapToolbarEnabled: false,
      onMapCreated: onMapCreated,
      polylines: gmapRoute.isNotEmpty
          ? {
              Polyline(
                polylineId: const PolylineId('live_tracking_route'),
                points: gmapRoute,
                color: isLightMode ? AppTheme.primary : AppTheme.warningAccent,
                width: 5,
                jointType: JointType.round,
                startCap: Cap.roundCap,
                endCap: Cap.roundCap,
              ),
            }
          : {},
      markers: gmapRoute.isNotEmpty
          ? {
              Marker(
                markerId: const MarkerId('current_pos'),
                position: gmapRoute.last,
                icon: BitmapDescriptor.defaultMarkerWithHue(
                  isLightMode ? BitmapDescriptor.hueAzure : BitmapDescriptor.hueOrange,
                ),
              ),
            }
          : {},
    );
  }
}

class _TrackingControlPanel extends StatelessWidget {
  final bool isTracking;
  final bool isLightMode;
  final String distanceLabel;
  final String timeLabel;
  final String speedLabel;
  final VoidCallback onStartTracking;
  final VoidCallback onStopAndSave;

  const _TrackingControlPanel({
    required this.isTracking,
    required this.isLightMode,
    required this.distanceLabel,
    required this.timeLabel,
    required this.speedLabel,
    required this.onStartTracking,
    required this.onStopAndSave,
  });

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.bottomCenter,
      child: ClipRect(
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10.0, sigmaY: 10.0),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(20, 24, 20, 40),
            decoration: BoxDecoration(
              color: AppTheme.background.withAlpha(180),
              border: Border(
                top: BorderSide(
                  color: AppTheme.textPrimary.withAlpha(31),
                  width: 1,
                ),
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    _MetricBox(label: 'DISTÂNCIA', value: distanceLabel),
                    _MetricBox(label: 'TEMPO', value: timeLabel),
                    if (!isLightMode)
                      _MetricBox(label: 'VELOCIDADE', value: speedLabel),
                  ],
                ),
                const SizedBox(height: 24),
                _TrackingActionButton(
                  isTracking: isTracking,
                  onStartTracking: onStartTracking,
                  onStopAndSave: onStopAndSave,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _TrackingActionButton extends StatelessWidget {
  final bool isTracking;
  final VoidCallback onStartTracking;
  final VoidCallback onStopAndSave;

  const _TrackingActionButton({
    required this.isTracking,
    required this.onStartTracking,
    required this.onStopAndSave,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 56,
      child: ElevatedButton(
        onPressed: isTracking ? onStopAndSave : onStartTracking,
        style: ElevatedButton.styleFrom(
          backgroundColor: isTracking
              ? AppTheme.statusAlert
              : AppTheme.successOperational,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
          elevation: 0,
        ),
        child: Text(
          isTracking ? 'ENCERRAR E SALVAR' : 'INICIAR RASTREIO TÁTICO',
          style: GoogleFonts.inter(
            fontSize: 16,
            fontWeight: FontWeight.w900,
            color: AppTheme.textPrimary,
          ),
        ),
      ),
    );
  }
}

class _MetricBox extends StatelessWidget {
  final String label;
  final String value;

  const _MetricBox({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: GoogleFonts.inter(
            fontSize: 10,
            fontWeight: FontWeight.bold,
            color: AppTheme.textPrimary.withAlpha(138),
            letterSpacing: 0.5,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: GoogleFonts.inter(
            fontSize: 24,
            fontWeight: FontWeight.w900,
            color: AppTheme.textPrimary,
          ),
        ),
      ],
    );
  }
}
