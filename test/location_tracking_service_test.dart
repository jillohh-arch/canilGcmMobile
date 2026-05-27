import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

import 'package:canil_gcm/core/services/location_tracking_service.dart';

void main() {
  late LocationTrackingService service;

  setUp(() {
    service = LocationTrackingService();
  });

  Position createPosition({
    required double lat,
    required double lng,
    double accuracy = 10.0,
    DateTime? timestamp,
  }) {
    return Position(
      latitude: lat,
      longitude: lng,
      accuracy: accuracy,
      altitude: 0,
      altitudeAccuracy: 0,
      heading: 0,
      headingAccuracy: 0,
      speed: 0,
      speedAccuracy: 0,
      timestamp: timestamp ?? DateTime(2026, 5, 10, 10, 0, 0),
    );
  }

  group('LocationTrackingService', () {
    group('distanceBetween', () {
      test('returns 0 for same point', () {
        const point = LatLng(-22.5667, -47.4017);
        final distance = service.distanceBetween(point, point);
        expect(distance, 0.0);
      });

      test('returns positive distance for different points', () {
        const from = LatLng(-22.5667, -47.4017);
        const to = LatLng(-22.5670, -47.4020);
        final distance = service.distanceBetween(from, to);
        expect(distance, greaterThan(0));
      });

      test('returns reasonable distance for known points', () {
        // ~111km per degree of latitude
        const from = LatLng(-22.0, -47.0);
        const to = LatLng(-23.0, -47.0);
        final distance = service.distanceBetween(from, to);
        // Should be approximately 111km
        expect(distance, greaterThan(100000));
        expect(distance, lessThan(120000));
      });
    });

    group('shouldAcceptPosition', () {
      test('rejects position with low accuracy', () {
        final position = createPosition(
          lat: -22.5667,
          lng: -47.4017,
          accuracy: 50.0, // > 40m threshold
        );
        final result = service.shouldAcceptPosition(position, null);
        expect(result, isFalse);
      });

      test('accepts first position with good accuracy', () {
        final position = createPosition(
          lat: -22.5667,
          lng: -47.4017,
          accuracy: 10.0,
        );
        final result = service.shouldAcceptPosition(position, null);
        expect(result, isTrue);
      });

      test('rejects position too close to previous (< 1m)', () {
        final previous = createPosition(
          lat: -22.5667000,
          lng: -47.4017000,
          timestamp: DateTime(2026, 5, 10, 10, 0, 0),
        );
        // Same point essentially
        final position = createPosition(
          lat: -22.5667000,
          lng: -47.4017000,
          timestamp: DateTime(2026, 5, 10, 10, 0, 5),
        );
        final result = service.shouldAcceptPosition(position, previous);
        expect(result, isFalse);
      });

      test('rejects position with unrealistic speed', () {
        final previous = createPosition(
          lat: -22.5667,
          lng: -47.4017,
          timestamp: DateTime(2026, 5, 10, 10, 0, 0),
        );
        // ~1km away in 1 second = 1000 m/s (way above 8.5 m/s threshold)
        final position = createPosition(
          lat: -22.5757,
          lng: -47.4017,
          timestamp: DateTime(2026, 5, 10, 10, 0, 1),
        );
        final result = service.shouldAcceptPosition(position, previous);
        expect(result, isFalse);
      });

      test('accepts position with reasonable speed', () {
        final previous = createPosition(
          lat: -22.566700,
          lng: -47.401700,
          timestamp: DateTime(2026, 5, 10, 10, 0, 0),
        );
        // ~5m away in 2 seconds = 2.5 m/s (below 8.5 m/s threshold)
        final position = createPosition(
          lat: -22.566745,
          lng: -47.401700,
          timestamp: DateTime(2026, 5, 10, 10, 0, 2),
        );
        final result = service.shouldAcceptPosition(position, previous);
        expect(result, isTrue);
      });
    });

    group('trackingLocationSettings', () {
      test('returns AndroidSettings with bestForNavigation accuracy', () {
        final settings = service.trackingLocationSettings;
        expect(settings, isA<AndroidSettings>());
        expect((settings as AndroidSettings).accuracy, LocationAccuracy.bestForNavigation);
      });

      test('has distance filter of 2 meters', () {
        final settings = service.trackingLocationSettings as AndroidSettings;
        expect(settings.distanceFilter, 2);
      });
    });
  });
}
