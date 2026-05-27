import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

class ResolvedLocation {
  final String address;
  final LatLng point;
  final double accuracy;

  const ResolvedLocation({
    required this.address,
    required this.point,
    this.accuracy = 0.0,
  });
}

class LocationResolutionService {
  const LocationResolutionService();

  Future<ResolvedLocation> currentHighAccuracy() async {
    final position = await Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(accuracy: LocationAccuracy.high),
    );
    final point = LatLng(position.latitude, position.longitude);
    final address = await addressForPoint(point);
    return ResolvedLocation(
      address: address,
      point: point,
      accuracy: position.accuracy,
    );
  }

  Future<String> addressForPoint(LatLng point) async {
    try {
      final placemarks = await placemarkFromCoordinates(
        point.latitude,
        point.longitude,
      );
      if (placemarks.isNotEmpty) {
        final address = _formatPlacemark(placemarks.first);
        if (address.isNotEmpty) {
          return address;
        }
      }
    } catch (_) {
      // Mantém a coordenada quando o endereço textual não puder ser resolvido.
    }

    return _coordinateLabel(point);
  }

  String _formatPlacemark(Placemark placemark) {
    return [
      placemark.thoroughfare,
      placemark.subLocality ?? placemark.subAdministrativeArea,
      placemark.locality,
    ].where((part) => part != null && part.trim().isNotEmpty).join(', ');
  }

  String _coordinateLabel(LatLng point) {
    return '${point.latitude.toStringAsFixed(6)}, '
        '${point.longitude.toStringAsFixed(6)}';
  }
}
