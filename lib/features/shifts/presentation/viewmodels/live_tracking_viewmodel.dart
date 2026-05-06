import 'dart:async';
import 'dart:collection';

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

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
  static const double _maxAcceptedAccuracyMeters = 40;
  static const double _maxAcceptedSpeedMetersPerSecond = 8.5;

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

  LocationSettings get trackingLocationSettings {
    return AndroidSettings(
      accuracy: LocationAccuracy.bestForNavigation,
      distanceFilter: 2,
      intervalDuration: const Duration(seconds: 2),
      foregroundNotificationConfig: const ForegroundNotificationConfig(
        notificationTitle: 'Rastreamento K9 ativo',
        notificationText: 'Capturando o caminho mesmo com a tela bloqueada.',
        notificationChannelName: 'Rastreamento K9',
        enableWakeLock: true,
        setOngoing: true,
      ),
    );
  }

  Future<LatLng?> getCurrentLatLng() async {
    final position = await _getCurrentPosition(skipPermissionCheck: true);
    if (position == null) return null;
    return LatLng(position.latitude, position.longitude);
  }

  Future<LiveTrackingStartResult> startTracking() async {
    final permissionError = await _validatePermissions();
    if (permissionError != null) {
      return LiveTrackingStartResult.error(permissionError);
    }

    final position = await _getCurrentPosition();
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

    _positionStream =
        Geolocator.getPositionStream(
          locationSettings: trackingLocationSettings,
        ).listen((position) {
          if (!_shouldAcceptPosition(position)) return;

          final newPoint = LatLng(position.latitude, position.longitude);
          if (_routePoints.isNotEmpty) {
            final lastPoint = _routePoints.last;
            final distance = Geolocator.distanceBetween(
              lastPoint.latitude,
              lastPoint.longitude,
              newPoint.latitude,
              newPoint.longitude,
            );
            _totalDistanceMeters += distance;
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

  bool _shouldAcceptPosition(Position position) {
    if (position.accuracy > _maxAcceptedAccuracyMeters) {
      return false;
    }

    final previous = _lastAcceptedPosition;
    if (previous == null) return true;

    final distance = Geolocator.distanceBetween(
      previous.latitude,
      previous.longitude,
      position.latitude,
      position.longitude,
    );
    if (distance < 1) return false;

    final previousTimestamp = previous.timestamp;
    final currentTimestamp = position.timestamp;
    final seconds =
        currentTimestamp.difference(previousTimestamp).inMilliseconds.abs() /
        1000;
    if (seconds <= 0) return false;

    final speed = distance / seconds;
    return speed <= _maxAcceptedSpeedMetersPerSecond;
  }

  Future<String?> _validatePermissions() async {
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      return 'Ative o GPS do aparelho.';
    }

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        return 'Permissao de localizacao negada.';
      }
    }

    if (permission == LocationPermission.deniedForever) {
      return 'Permissao de localizacao bloqueada nas configuracoes.';
    }

    return null;
  }

  Future<Position?> _getCurrentPosition({
    bool skipPermissionCheck = false,
  }) async {
    if (!skipPermissionCheck) {
      final permissionError = await _validatePermissions();
      if (permissionError != null) return null;
    }

    return Geolocator.getCurrentPosition(
      locationSettings: trackingLocationSettings,
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
