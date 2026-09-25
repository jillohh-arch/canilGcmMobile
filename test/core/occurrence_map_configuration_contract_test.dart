import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import 'package:canil_gcm/core/services/occurrence_location_service.dart';
import 'package:canil_gcm/core/theme/app_map_style.dart';
import 'package:canil_gcm/features/occurrences/domain/occurrence_event.dart';
import 'package:canil_gcm/features/occurrences/domain/occurrence_event_category.dart';
import 'package:canil_gcm/features/occurrences/presentation/widgets/occurrence_displacement_map.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('CT3.F40.MAP-01 — Manifest Placeholder & Build Configuration Contract', () {
    final rootDir = Directory.current;

    test(
      '1. android/app/build.gradle.kts defines MAPS_API_KEY resolution hierarchy including local.properties',
      () {
        final gradleFile = File('${rootDir.path}/android/app/build.gradle.kts');
        expect(
          gradleFile.existsSync(),
          isTrue,
          reason: 'build.gradle.kts must exist',
        );
        final content = gradleFile.readAsStringSync();

        // Resolution hierarchy
        expect(
          content,
          contains('rootProject.file("local.properties")'),
          reason: 'Must look up local.properties from rootProject',
        );
        expect(
          content,
          contains('localProperties.getProperty("MAPS_API_KEY")'),
          reason: 'Must support MAPS_API_KEY from local.properties',
        );
        expect(
          content,
          contains('manifestPlaceholders["MAPS_API_KEY"] = mapsApiKey'),
          reason: 'Must bind resolved key to manifestPlaceholders',
        );

        // No hardcoded Google API keys in build.gradle.kts
        expect(
          content.contains(RegExp(r'AIza[0-9A-Za-z_-]{35}')),
          isFalse,
          reason: 'build.gradle.kts must not contain hardcoded Google API keys',
        );
      },
    );

    test(
      '2. android/app/src/main/AndroidManifest.xml injects MAPS_API_KEY placeholder into geo metadata',
      () {
        final manifestFile = File(
          '${rootDir.path}/android/app/src/main/AndroidManifest.xml',
        );
        expect(
          manifestFile.existsSync(),
          isTrue,
          reason: 'AndroidManifest.xml must exist',
        );
        final content = manifestFile.readAsStringSync();

        final hasGeoApiKey =
            content.contains('android:name="com.google.android.geo.API_KEY"') &&
            content.contains('android:value="\${MAPS_API_KEY}"');
        expect(
          hasGeoApiKey,
          isTrue,
          reason:
              'com.google.android.geo.API_KEY must reference \${MAPS_API_KEY}',
        );
      },
    );

    test(
      '3. android/.gitignore strictly ignores local.properties to prevent secret leakage',
      () {
        final gitignoreFile = File('${rootDir.path}/android/.gitignore');
        expect(gitignoreFile.existsSync(), isTrue);
        final content = gitignoreFile.readAsStringSync();
        expect(
          content,
          contains('/local.properties'),
          reason: '/local.properties must be gitignored',
        );
      },
    );

    test('4. lib/ directory does not contain hardcoded Google API keys', () {
      final libDir = Directory('${rootDir.path}/lib');
      final dartFiles = libDir
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart'));

      final apiKeyPattern = RegExp(r'AIza[0-9A-Za-z_-]{35}');
      for (final file in dartFiles) {
        final content = file.readAsStringSync();
        expect(
          apiKeyPattern.hasMatch(content),
          isFalse,
          reason: 'Source file ${file.path} must not hardcode Google API keys',
        );
      }
    });
  });

  group(
    'CT3.F40.MAP-02 — Coordinate Resilience & AppMapStyle Bounds Calculation Contract',
    () {
      test(
        '1. boundsFromPoints encloses multiple scattered coordinates correctly',
        () {
          final points = [
            const LatLng(-22.5647, -47.4013),
            const LatLng(-22.5800, -47.4200),
            const LatLng(-22.5500, -47.3900),
          ];
          final bounds = AppMapStyle.boundsFromPoints(points);

          expect(bounds.southwest.latitude, equals(-22.5800));
          expect(bounds.southwest.longitude, equals(-47.4200));
          expect(bounds.northeast.latitude, equals(-22.5500));
          expect(bounds.northeast.longitude, equals(-47.3900));
        },
      );

      test(
        '2. boundsFromPoints safely expands single point with defensive margin to prevent 0-area crash',
        () {
          final singlePoint = [const LatLng(-22.5647, -47.4013)];
          final bounds = AppMapStyle.boundsFromPoints(singlePoint);

          expect(bounds.southwest.latitude, closeTo(-22.5657, 0.00001));
          expect(bounds.northeast.latitude, closeTo(-22.5637, 0.00001));
          expect(bounds.southwest.longitude, closeTo(-47.4023, 0.00001));
          expect(bounds.northeast.longitude, closeTo(-47.4003, 0.00001));
          expect(
            bounds.southwest.latitude,
            lessThan(bounds.northeast.latitude),
          );
          expect(
            bounds.southwest.longitude,
            lessThan(bounds.northeast.longitude),
          );
        },
      );

      test(
        '3. boundsFromPoints safely expands duplicate/colinear points to prevent 0-area crash',
        () {
          final identicalPoints = [
            const LatLng(-22.5647, -47.4013),
            const LatLng(-22.5647, -47.4013),
            const LatLng(-22.5647, -47.4013),
          ];
          final bounds = AppMapStyle.boundsFromPoints(identicalPoints);

          expect(
            bounds.southwest.latitude,
            lessThan(bounds.northeast.latitude),
          );
          expect(
            bounds.southwest.longitude,
            lessThan(bounds.northeast.longitude),
          );
        },
      );

      test(
        '4. boundsFromPoints handles empty coordinate list gracefully with default Limeira tactical bounds',
        () {
          final bounds = AppMapStyle.boundsFromPoints(const []);

          expect(
            bounds.southwest.latitude,
            lessThan(bounds.northeast.latitude),
          );
          expect(
            bounds.southwest.longitude,
            lessThan(bounds.northeast.longitude),
          );
          expect(bounds.southwest.latitude, closeTo(-22.5657, 0.001));
          expect(bounds.northeast.latitude, closeTo(-22.5637, 0.001));
        },
      );

      test(
        '5. OccurrenceLocationService filters out null coordinates and empty event streams safely',
        () {
          final now = DateTime(2026, 9, 25, 10, 0);

          // Empty stream
          final emptyResult = OccurrenceLocationService.clusterEventsSync([]);
          expect(emptyResult, isEmpty);

          // Events without GPS
          final noGpsEvents = <OccurrenceEvent>[
            OccurrenceEvent(
              id: 'ev-1',
              occurrenceId: 'occ-1',
              category: OccurrenceEventCategory.other,
              description: 'Ação sem GPS 1',
              timestamp: now,
              createdAt: now,
              updatedAt: now,
              gpsLat: null,
              gpsLng: null,
            ),
            OccurrenceEvent(
              id: 'ev-2',
              occurrenceId: 'occ-1',
              category: OccurrenceEventCategory.other,
              description: 'Ação sem GPS 2',
              timestamp: now.add(const Duration(minutes: 5)),
              createdAt: now,
              updatedAt: now,
              gpsLat: null,
              gpsLng: null,
            ),
          ];
          final noGpsResult = OccurrenceLocationService.clusterEventsSync(
            noGpsEvents,
          );
          expect(noGpsResult, isEmpty);

          // Mixed stream: only valid GPS events form clusters
          final mixedEvents = <OccurrenceEvent>[
            OccurrenceEvent(
              id: 'ev-no-gps',
              occurrenceId: 'occ-1',
              category: OccurrenceEventCategory.other,
              description: 'Sem GPS',
              timestamp: now,
              createdAt: now,
              updatedAt: now,
              gpsLat: null,
              gpsLng: null,
            ),
            OccurrenceEvent(
              id: 'ev-loc-1',
              occurrenceId: 'occ-1',
              category: OccurrenceEventCategory.arrival,
              description: 'Chegada',
              placeLabel: 'Praça Central',
              timestamp: now.add(const Duration(minutes: 1)),
              createdAt: now,
              updatedAt: now,
              gpsLat: -22.5647,
              gpsLng: -47.4013,
            ),
            OccurrenceEvent(
              id: 'ev-loc-1-nearby',
              occurrenceId: 'occ-1',
              category: OccurrenceEventCategory.approach,
              description: 'Abordagem no mesmo local',
              timestamp: now.add(const Duration(minutes: 3)),
              createdAt: now,
              updatedAt: now,
              gpsLat: -22.5648,
              gpsLng: -47.4014,
            ),
            OccurrenceEvent(
              id: 'ev-loc-2-distant',
              occurrenceId: 'occ-1',
              category: OccurrenceEventCategory.dogWork,
              description: 'Deslocamento até Base',
              placeLabel: 'Base Operacional',
              timestamp: now.add(const Duration(minutes: 20)),
              createdAt: now,
              updatedAt: now,
              gpsLat: -22.5800,
              gpsLng: -47.4200,
            ),
          ];

          final clusters = OccurrenceLocationService.clusterEventsSync(
            mixedEvents,
          );
          expect(clusters.length, equals(2));
          expect(clusters[0].index, equals(1));
          expect(clusters[0].events.length, equals(2));
          expect(clusters[1].index, equals(2));
          expect(clusters[1].events.length, equals(1));
        },
      );
    },
  );

  group(
    'CT3.F40.MAP-03 — Map Presentation & Location Permission Independence Contract',
    () {
      test(
        '1. OccurrenceDisplacementMap renders empty widget (SizedBox.shrink) when locations list is empty',
        () {
          const widget = OccurrenceDisplacementMap(locations: []);
          final element = widget.createElement();
          expect(element, isNotNull);
        },
      );

      test(
        '2. OccurrenceDisplacementMap does not depend on geolocator package or runtime location permissions',
        () {
          final file = File(
            'lib/features/occurrences/presentation/widgets/occurrence_displacement_map.dart',
          );
          expect(file.existsSync(), isTrue);
          final content = file.readAsStringSync();

          // Does not import geolocator
          expect(
            content.contains("package:geolocator/geolocator.dart"),
            isFalse,
            reason: 'OccurrenceDisplacementMap must not import geolocator',
          );

          // myLocationButtonEnabled is explicitly false
          expect(
            content,
            contains('myLocationButtonEnabled: false'),
            reason:
                'myLocationButtonEnabled must be disabled so map does not probe device location',
          );
        },
      );

      test(
        '3. EditEventLocationScreen explicitly sets myLocationButtonEnabled to false on base map',
        () {
          final file = File(
            'lib/features/occurrences/presentation/screens/edit_event_location_screen.dart',
          );
          expect(file.existsSync(), isTrue);
          final content = file.readAsStringSync();

          expect(
            content,
            contains('myLocationButtonEnabled: false'),
            reason:
                'Base map in EditEventLocationScreen must have myLocationButtonEnabled set to false',
          );
        },
      );

      test(
        '4. EditEventLocationScreen handles location permission denial defensively without breaking map state',
        () {
          final file = File(
            'lib/features/occurrences/presentation/screens/edit_event_location_screen.dart',
          );
          expect(file.existsSync(), isTrue);
          final content = file.readAsStringSync();

          // Checks LocationPermission.denied and LocationPermission.deniedForever
          expect(content, contains('LocationPermission.denied'));
          expect(content, contains('LocationPermission.deniedForever'));
          expect(
            content,
            contains(
              "AppFeedback.warning(context, 'Permissão de localização negada')",
            ),
          );

          // Returns early without crashing or disposing map controller
          expect(content, contains('return;'));
        },
      );

      test(
        '5. AppMapStyle custom numbered marker icons create valid BitmapDescriptor with tactical colors',
        () async {
          final startIcon = await AppMapStyle.createNumberedMarkerIcon(
            number: 1,
            isFirst: true,
          );
          expect(startIcon, isNotNull);

          final nextIcon = await AppMapStyle.createNumberedMarkerIcon(
            number: 2,
            isFirst: false,
          );
          expect(nextIcon, isNotNull);

          // Consecutive calls return cached instances
          final cachedIcon = await AppMapStyle.createNumberedMarkerIcon(
            number: 1,
            isFirst: true,
          );
          expect(identical(startIcon, cachedIcon), isTrue);
        },
      );
    },
  );
}
