import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:canil_gcm/core/theme/app_map_style.dart';

void main() {
  group('FF-MAPS-01.GMAP.M1 — Interactive Maps CARTO Retirement & Google Maps Migration', () {
    const interactiveFiles = [
      'lib/features/history/presentation/widgets/gps_track_detail_widget.dart',
      'lib/features/occurrences/presentation/widgets/occurrence_displacement_map.dart',
      'lib/features/training/presentation/screens/gps_tracking_summary_screen.dart',
      'lib/features/training/presentation/screens/gps_tracking_screen.dart',
      'lib/features/shifts/presentation/screens/live_tracking_widgets.dart',
      'lib/features/shifts/presentation/screens/live_tracking_screen.dart',
      'lib/features/occurrences/presentation/screens/edit_event_location_screen.dart',
    ];

    test('1. No interactive map file imports flutter_map', () {
      for (final relativePath in interactiveFiles) {
        final file = File(relativePath);
        expect(file.existsSync(), isTrue, reason: 'File $relativePath must exist');
        final content = file.readAsStringSync();
        expect(
          content.contains("package:flutter_map/flutter_map.dart"),
          isFalse,
          reason: '$relativePath should not import flutter_map',
        );
        expect(
          content.contains("FlutterMap("),
          isFalse,
          reason: '$relativePath should not use FlutterMap widget',
        );
      }
    });

    test('2. No interactive map file references cartocdn.com or Carto dark tiles', () {
      for (final relativePath in interactiveFiles) {
        final file = File(relativePath);
        final content = file.readAsStringSync();
        expect(
          content.contains('cartocdn.com'),
          isFalse,
          reason: '$relativePath must not reference cartocdn.com',
        );
        expect(
          content.contains('basemaps.cartocdn.com'),
          isFalse,
          reason: '$relativePath must not reference basemaps.cartocdn.com',
        );
      }
    });

    test('3. Interactive map surfaces import and use google_maps_flutter', () {
      for (final relativePath in interactiveFiles) {
        final file = File(relativePath);
        final content = file.readAsStringSync();
        final hasGmapImport = content.contains('package:google_maps_flutter/google_maps_flutter.dart') ||
            relativePath.endsWith('live_tracking_widgets.dart'); // part of live_tracking_screen.dart
        expect(
          hasGmapImport,
          isTrue,
          reason: '$relativePath must have access to google_maps_flutter',
        );
      }
    });

    test('4. PDF static map generator (OsmStaticMapGenerator) remains preserved and untouched', () {
      final staticFile = File('lib/core/services/osm_static_map_generator.dart');
      expect(staticFile.existsSync(), isTrue);
      final content = staticFile.readAsStringSync();
      expect(
        content.contains('generateDisplacementMap'),
        isTrue,
        reason: 'OsmStaticMapGenerator must retain generateDisplacementMap contract',
      );
      expect(
        content.contains('package:flutter_map/flutter_map.dart'),
        isFalse,
        reason: 'OsmStaticMapGenerator never used flutter_map',
      );
    });

    test('5. AppMapStyle darkStyle is well-formed JSON and contains dark theme palette', () {
      expect(AppMapStyle.darkStyle.isNotEmpty, isTrue);
      expect(AppMapStyle.darkStyle.contains('#0d181e'), isTrue);
      expect(AppMapStyle.darkStyle.contains('#050d10'), isTrue);
    });

    test('6. AppMapStyle bounds calculation handles single and multiple points correctly', () {
      final points = [
        const LatLng(-22.5647, -47.4013),
        const LatLng(-22.5700, -47.4100),
      ];
      final bounds = AppMapStyle.boundsFromPoints(points);
      expect(bounds.southwest.latitude, lessThanOrEqualTo(-22.5700));
      expect(bounds.northeast.latitude, greaterThanOrEqualTo(-22.5647));
      expect(bounds.southwest.longitude, lessThanOrEqualTo(-47.4100));
      expect(bounds.northeast.longitude, greaterThanOrEqualTo(-47.4013));
    });

    test('7. AppMapStyle bounds calculation expands zero-area single point safely', () {
      final singlePoint = [const LatLng(-22.5647, -47.4013)];
      final bounds = AppMapStyle.boundsFromPoints(singlePoint);
      expect(bounds.southwest.latitude, lessThan(bounds.northeast.latitude));
      expect(bounds.southwest.longitude, lessThan(bounds.northeast.longitude));
    });

    test('8. AppMapStyle bounds calculation handles empty point list defensively', () {
      final bounds = AppMapStyle.boundsFromPoints(const []);
      expect(bounds.southwest.latitude, lessThan(bounds.northeast.latitude));
      expect(bounds.southwest.longitude, lessThan(bounds.northeast.longitude));
    });

    test('9. Recursive audit: ZERO files in lib/ import flutter_map', () {
      final libDir = Directory('lib');
      final dartFiles = libDir
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart'));

      for (final file in dartFiles) {
        final content = file.readAsStringSync();
        expect(
          content.contains("package:flutter_map/flutter_map.dart"),
          isFalse,
          reason: '${file.path} should not import flutter_map',
        );
      }
    });

    test('10. Recursive audit: cartocdn.com appears ONLY in osm_static_map_generator.dart', () {
      final libDir = Directory('lib');
      final dartFiles = libDir
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart'));

      for (final file in dartFiles) {
        final content = file.readAsStringSync();
        if (content.contains('cartocdn.com')) {
          final normalizedPath = file.path.replaceAll(r'\', '/');
          expect(
            normalizedPath.endsWith('lib/core/services/osm_static_map_generator.dart'),
            isTrue,
            reason: 'cartocdn.com is only permitted in osm_static_map_generator.dart, found in: ${file.path}',
          );
        }
      }
    });
  });
}
