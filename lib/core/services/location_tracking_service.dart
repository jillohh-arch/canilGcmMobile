import 'dart:async';

import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

/// Serviu00e7o que encapsula toda interau00e7u00e3o com o Geolocator (GPS).
///
/// Responsu00e1vel por: validau00e7u00e3o de permissu00f5es, obtenu00e7u00e3o de posiu00e7u00e3o,
/// streaming de posiu00e7u00f5es e cu00e1lculo de distu00e2ncia entre pontos.
class LocationTrackingService {
  static const double maxAcceptedAccuracyMeters = 40;
  static const double maxAcceptedSpeedMetersPerSecond = 8.5;

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

  /// Valida permissu00f5es de localizau00e7u00e3o. Retorna mensagem de erro ou null se OK.
  Future<String?> validatePermissions() async {
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

  /// Obtu00e9m a posiu00e7u00e3o atual. Retorna null se nu00e3o for possu00edvel.
  Future<Position?> getCurrentPosition({
    bool skipPermissionCheck = false,
  }) async {
    if (!skipPermissionCheck) {
      final permissionError = await validatePermissions();
      if (permissionError != null) return null;
    }

    return Geolocator.getCurrentPosition(
      locationSettings: trackingLocationSettings,
    );
  }

  /// Converte Position em LatLng. Retorna null se posiu00e7u00e3o for null.
  Future<LatLng?> getCurrentLatLng() async {
    final position = await getCurrentPosition(skipPermissionCheck: true);
    if (position == null) return null;
    return LatLng(position.latitude, position.longitude);
  }

  /// Inicia stream de posiu00e7u00f5es com as configurau00e7u00f5es de tracking.
  Stream<Position> getPositionStream() {
    return Geolocator.getPositionStream(
      locationSettings: trackingLocationSettings,
    );
  }

  /// Calcula distu00e2ncia em metros entre dois pontos.
  double distanceBetween(LatLng from, LatLng to) {
    return Geolocator.distanceBetween(
      from.latitude,
      from.longitude,
      to.latitude,
      to.longitude,
    );
  }

  /// Verifica se uma posiu00e7u00e3o deve ser aceita com base em precisu00e3o e velocidade.
  bool shouldAcceptPosition(Position position, Position? previous) {
    if (position.accuracy > maxAcceptedAccuracyMeters) {
      return false;
    }

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
    return speed <= maxAcceptedSpeedMetersPerSecond;
  }
}
