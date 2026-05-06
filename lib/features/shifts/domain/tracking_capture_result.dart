class TrackingCaptureResult {
  final List<Map<String, double>> route;
  final double distanceMeters;
  final int durationSeconds;

  const TrackingCaptureResult({
    required this.route,
    required this.distanceMeters,
    required this.durationSeconds,
  });

  Map<String, dynamic> toMap() {
    return {
      'route': route,
      'distanceMeters': distanceMeters,
      'durationSeconds': durationSeconds,
    };
  }
}
