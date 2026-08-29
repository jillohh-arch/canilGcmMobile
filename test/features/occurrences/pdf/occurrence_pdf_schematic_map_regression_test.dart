// FF-OCC-05.H1.C3 — REGRESSION GUARD: the occurrence PDF has no external
// basemap provider in its runtime dependency graph.
//
// Physical defect (H1):
//   CARTO stopped serving anonymous clean raster tiles. It now returns a
//   genuine 256x256 cartographic tile with "API KEY REQUIRED /
//   carto.com/basemaps/apikey" watermarked over the real map. Status, MIME,
//   decode and dimensions are all legitimate, so no transport-level check can
//   tell a clean tile from a stamped one (proved in H1.C1).
//
// Decision (H1.C2):
//   The PDF stops requesting external raster entirely and always renders the
//   schematic map, which is deterministic and network-independent.
//
// What this guard asserts:
//   Generation succeeds AND no basemap host is ever contacted. The harness
//   records every outbound attempt at the dart:io layer, so absence here is
//   evidence rather than assumption. The rendered schematic appearance is
//   validated physically, not by matching compressed PDF bytes.

import 'package:flutter_test/flutter_test.dart';

import 'package:canil_gcm/core/services/pdf_generator/occurrence_pdf_generator.dart';
import 'package:canil_gcm/features/dogs/domain/dog.dart';
import 'package:canil_gcm/features/occurrences/domain/occurrence.dart';
import 'package:canil_gcm/features/occurrences/domain/occurrence_event.dart';
import 'package:canil_gcm/features/occurrences/domain/occurrence_event_category.dart';
import 'package:canil_gcm/features/occurrences/domain/occurrence_status.dart';

import 'pdf_diagnostic_harness.dart';

final _t0 = DateTime(2026, 8, 29, 10, 0);

/// Any host that would mean the PDF still depends on a basemap provider.
const _basemapHostFragment = 'cartocdn';

/// The exact host the pre-fix implementation contacted.
const _cartoHost = 'a.basemaps.cartocdn.com';

Dog _dog() => Dog(
  id: 'dog-c3',
  name: 'Thor',
  breed: 'Pastor Belga Malinois',
  dateOfBirth: DateTime(2021, 3, 10),
  registrationNumber: 'K9-0001',
);

/// Occurrence carrying valid GPS, which is what used to trigger the
/// single-point basemap request.
Occurrence _occurrence() => Occurrence(
  id: 'occ-c3',
  shiftId: 'shift-c3',
  primaryHandlerId: 'handler-c3',
  primaryHandlerRa: '99999',
  dogId: 'dog-c3',
  typeCode: 'BUSCA',
  typeName: 'Busca com K9',
  locationAddress: 'Rua Sintetica, 100 - Limeira/SP',
  gpsLat: -22.5645,
  gpsLng: -47.4017,
  gpsAccuracy: 8.0,
  startedAt: _t0,
  finalizedAt: _t0.add(const Duration(hours: 2)),
  createdAt: _t0,
  updatedAt: _t0.add(const Duration(hours: 2)),
  status: OccurrenceStatus.finalized,
  finalReport: 'Relato sintetico para regressao de mapa esquematico.',
  integrityHash: 'a' * 64,
  hashVersion: 2,
);

OccurrenceEvent _geoEvent({
  required int i,
  required double lat,
  required double lng,
  required OccurrenceEventCategory category,
}) {
  final ts = _t0.add(Duration(minutes: 7 * i));
  return OccurrenceEvent(
    id: 'evt-c3-$i',
    occurrenceId: 'occ-c3',
    category: category,
    timestamp: ts,
    title: 'Evento sintetico $i',
    gpsLat: lat,
    gpsLng: lng,
    placeLabel: 'Ponto sintetico $i',
    createdAt: ts,
    updatedAt: ts,
  );
}

/// Three separated GPS points, which is what used to trigger the displacement
/// basemap request.
List<OccurrenceEvent> _displacementEvents() => [
  _geoEvent(
    i: 0,
    lat: -22.5645,
    lng: -47.4017,
    category: OccurrenceEventCategory.opening,
  ),
  _geoEvent(
    i: 1,
    lat: -22.5700,
    lng: -47.4100,
    category: OccurrenceEventCategory.arrival,
  ),
  _geoEvent(
    i: 2,
    lat: -22.5800,
    lng: -47.4200,
    category: OccurrenceEventCategory.closure,
  ),
];

/// Hosts contacted since the last reset, as a set for readable assertions.
Set<String> _hostsTouched() => attemptedNetworkHosts.toSet();

void main() {
  group('FF-OCC-05 — occurrence PDF is basemap-provider independent', () {
    setUpAll(installHermeticPdfHarness);
    tearDownAll(uninstallHermeticPdfHarness);

    setUp(attemptedNetworkHosts.clear);

    test(
      'single-point map: PDF generates and no basemap host is contacted',
      () async {
        final bytes = await OccurrencePdfGenerator().generate(
          occurrence: _occurrence(),
          events: const [],
          dog: _dog(),
          handlerName: 'GCM Silva',
          handlerRa: '99999',
        );

        expect(
          bytes.length,
          greaterThan(0),
          reason: 'The PDF must still be produced without any basemap raster.',
        );

        expect(
          _hostsTouched(),
          isNot(contains(_cartoHost)),
          reason:
              'The pre-fix implementation fetched tiles from $_cartoHost. A '
              'request here means the PDF regained a provider dependency.',
        );

        expect(
          _hostsTouched().where((h) => h.contains(_basemapHostFragment)),
          isEmpty,
          reason:
              'No basemap host may be contacted at all — not the original one '
              'and not a substitute: ${_hostsTouched()}',
        );
      },
    );

    test(
      'displacement map: PDF generates and no basemap host is contacted',
      () async {
        // Asserted independently of the single-point case: the two map sections
        // were separate request paths, so one passing never implied the other.
        final bytes = await OccurrencePdfGenerator().generate(
          occurrence: _occurrence(),
          events: _displacementEvents(),
          dog: _dog(),
          handlerName: 'GCM Silva',
          handlerRa: '99999',
        );

        expect(
          bytes.length,
          greaterThan(0),
          reason:
              'The displacement page must still render from the schematic path.',
        );

        expect(
          _hostsTouched(),
          isNot(contains(_cartoHost)),
          reason:
              'The displacement map used to fetch its own tile set from '
              '$_cartoHost.',
        );

        expect(
          _hostsTouched().where((h) => h.contains(_basemapHostFragment)),
          isEmpty,
          reason:
              'No basemap host may be contacted for the displacement page: '
              '${_hostsTouched()}',
        );
      },
    );
  });
}
