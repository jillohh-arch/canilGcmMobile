import 'dart:async';
import 'dart:collection';

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import 'package:canil_gcm/core/services/location_tracking_service.dart';
import 'package:canil_gcm/features/shifts/domain/tracking_capture_result.dart';

class LiveTrackingStartResult {
  final String? errorMessage;
  final LatLng? initialPoint;

  const LiveTrackingStartResult._({this.errorMessage, this.initialPoint});

  const LiveTrackingStartResult.success(LatLng initialPoint)
    : this._(initialPoint: initialPoint);

  const LiveTrackingStartResult.error(String errorMessage)
    : this._(errorMessage: errorMessage);

  bool get isSuccess => errorMessage == null && initialPoint != null;
}

class LiveTrackingViewModel extends ChangeNotifier {
  final LocationTrackingService _locationService = LocationTrackingService();

  final List<LatLng> _routePoints = [];
  StreamSubscription<Position>? _positionStream;
  Timer? _timer;
  Position? _lastAcceptedPosition;

  bool _isTracking = false;
  double _totalDistanceMeters = 0.0;
  int _elapsedSeconds = 0;

  bool get isTracking => _isTracking;
  double get totalDistanceMeters => _totalDistanceMeters;
  int get elapsedSeconds => _elapsedSeconds;
  UnmodifiableListView<LatLng> get routePoints =>
      UnmodifiableListView(_routePoints);

  Future<LatLng?> getCurrentLatLng() async {
    return _locationService.getCurrentLatLng();
  }

  Future<LiveTrackingStartResult> startTracking() async {
    final permissionError = await _locationService.validatePermissions();
    if (permissionError != null) {
      return LiveTrackingStartResult.error(permissionError);
    }

    final position = await _locationService.getCurrentPosition();
    if (position == null) {
      return const LiveTrackingStartResult.error(
        'Nao foi possivel obter a localizacao atual.',
      );
    }

    final currentLatLng = LatLng(position.latitude, position.longitude);

    await _positionStream?.cancel();
    _timer?.cancel();

    _routePoints
      ..clear()
      ..add(currentLatLng);
    _isTracking = true;
    _totalDistanceMeters = 0.0;
    _elapsedSeconds = 0;
    _lastAcceptedPosition = position;
    notifyListeners();

    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      _elapsedSeconds++;
      notifyListeners();
    });

    _positionStream = _locationService.getPositionStream().listen((position) {
      if (!_locationService.shouldAcceptPosition(
        position,
        _lastAcceptedPosition,
      )) {
        return;
      }

      final newPoint = LatLng(position.latitude, position.longitude);
      if (_routePoints.isNotEmpty) {
        final lastPoint = _routePoints.last;
        _totalDistanceMeters += _locationService.distanceBetween(
          lastPoint,
          newPoint,
        );
      }

      _routePoints.add(newPoint);
      _lastAcceptedPosition = position;
      notifyListeners();
    });

    return LiveTrackingStartResult.success(currentLatLng);
  }

  Future<TrackingCaptureResult> stopAndBuildResult() async {
    await _stopTracking();
    return TrackingCaptureResult(
      route: _routePoints
          .map((point) => {'lat': point.latitude, 'lng': point.longitude})
          .toList(),
      distanceMeters: _totalDistanceMeters,
      durationSeconds: _elapsedSeconds,
    );
  }

  Future<void> _stopTracking() async {
    _timer?.cancel();
    _timer = null;
    await _positionStream?.cancel();
    _positionStream = null;
    _isTracking = false;
    notifyListeners();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _positionStream?.cancel();
    super.dispose();
  }
}
