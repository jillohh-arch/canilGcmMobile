part of 'live_tracking_screen.dart';

class _CloseTrackingButton extends StatelessWidget {
  const _CloseTrackingButton();

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.all(8),
      decoration: const BoxDecoration(
        color: Colors.black45,
        shape: BoxShape.circle,
      ),
      child: IconButton(
        icon: const Icon(Icons.close_rounded, color: Colors.white),
        onPressed: () => Navigator.pop(context),
      ),
    );
  }
}

class _TrackingMap extends StatelessWidget {
  final List<LatLng> routePoints;
  final bool isLightMode;
  final String mapStyle;
  final ValueChanged<GoogleMapController> onMapCreated;

  const _TrackingMap({
    required this.routePoints,
    required this.isLightMode,
    required this.mapStyle,
    required this.onMapCreated,
  });

  @override
  Widget build(BuildContext context) {
    return GoogleMap(
      initialCameraPosition: const CameraPosition(
        target: LatLng(-23.5505, -46.6333),
        zoom: 12,
      ),
      style: mapStyle,
      onMapCreated: onMapCreated,
      myLocationEnabled: true,
      myLocationButtonEnabled: false,
      zoomControlsEnabled: false,
      compassEnabled: false,
      polylines: {
        Polyline(
          polylineId: const PolylineId('tracking_route'),
          points: routePoints,
          color: isLightMode
              ? const Color(0xFF26C6DA)
              : const Color(0xFFFBBF24),
          width: 5,
          jointType: JointType.round,
          endCap: Cap.roundCap,
          startCap: Cap.roundCap,
        ),
      },
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
              color: Colors.black.withAlpha(180),
              border: const Border(
                top: BorderSide(color: Colors.white12, width: 1),
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
              ? const Color(0xFFC62828)
              : const Color(0xFF1B8A4C),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
          elevation: 0,
        ),
        child: Text(
          isTracking ? 'ENCERRAR E SALVAR' : 'INICIAR RASTREIO TÁTICO',
          style: GoogleFonts.inter(
            fontSize: 16,
            fontWeight: FontWeight.w900,
            color: Colors.white,
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
            color: Colors.white54,
            letterSpacing: 0.5,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: GoogleFonts.inter(
            fontSize: 24,
            fontWeight: FontWeight.w900,
            color: Colors.white,
          ),
        ),
      ],
    );
  }
}
