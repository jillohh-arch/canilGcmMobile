import 'dart:math';

import 'package:canil_gcm/features/occurrences/domain/occurrence_event.dart';
import 'package:geocoding/geocoding.dart';

/// Um local agrupado (cluster) de eventos próximos (~50m).
class OccurrenceLocation {
  final int index; // 1-based
  final double lat;
  final double lng;
  final String label; // nome resolvido via reverse geocoding
  final DateTime arrivedAt; // timestamp do primeiro evento no cluster
  final List<OccurrenceEvent> events;

  const OccurrenceLocation({
    required this.index,
    required this.lat,
    required this.lng,
    required this.label,
    required this.arrivedAt,
    required this.events,
  });
}

/// Agrupa eventos por proximidade geográfica e resolve nomes via reverse geocoding.
class OccurrenceLocationService {
  /// Raio em metros para considerar eventos no mesmo local.
  static const double _clusterRadiusMeters = 60.0;

  /// Agrupa eventos por local (raio ~60m) na ordem cronológica.
  /// Eventos sem coordenada são ignorados no agrupamento.
  /// Retorna lista de locais na ordem de chegada.
  static Future<List<OccurrenceLocation>> clusterEvents(
    List<OccurrenceEvent> events,
  ) async {
    final sorted = [...events]
      ..sort((a, b) => a.timestamp.compareTo(b.timestamp));

    final clusters = <_Cluster>[];

    for (final event in sorted) {
      if (event.gpsLat == null || event.gpsLng == null) continue;

      final lat = event.gpsLat!;
      final lng = event.gpsLng!;

      // Procurar cluster existente dentro do raio
      _Cluster? match;
      for (final cluster in clusters) {
        if (_distanceMeters(cluster.lat, cluster.lng, lat, lng) <=
            _clusterRadiusMeters) {
          match = cluster;
          break;
        }
      }

      if (match != null) {
        match.events.add(event);
      } else {
        clusters.add(_Cluster(lat: lat, lng: lng, events: [event]));
      }
    }

    // Resolver nomes via reverse geocoding (prioriza place_label do evento)
    final locations = <OccurrenceLocation>[];
    for (var i = 0; i < clusters.length; i++) {
      final cluster = clusters[i];
      // Usar place_label do primeiro evento do cluster se disponível
      final existingLabel = cluster.events
          .where((e) => e.placeLabel != null && e.placeLabel!.isNotEmpty)
          .map((e) => e.placeLabel!)
          .firstOrNull;
      final label =
          existingLabel ?? await _resolveLabel(cluster.lat, cluster.lng);
      locations.add(
        OccurrenceLocation(
          index: i + 1,
          lat: cluster.lat,
          lng: cluster.lng,
          label: label,
          arrivedAt: cluster.events.first.timestamp,
          events: cluster.events,
        ),
      );
    }

    return locations;
  }

  /// Versão síncrona (sem geocoding) para uso no PDF ou quando offline.
  static List<OccurrenceLocation> clusterEventsSync(
    List<OccurrenceEvent> events,
  ) {
    final sorted = [...events]
      ..sort((a, b) => a.timestamp.compareTo(b.timestamp));

    final clusters = <_Cluster>[];

    for (final event in sorted) {
      if (event.gpsLat == null || event.gpsLng == null) continue;

      final lat = event.gpsLat!;
      final lng = event.gpsLng!;

      _Cluster? match;
      for (final cluster in clusters) {
        if (_distanceMeters(cluster.lat, cluster.lng, lat, lng) <=
            _clusterRadiusMeters) {
          match = cluster;
          break;
        }
      }

      if (match != null) {
        match.events.add(event);
      } else {
        clusters.add(_Cluster(lat: lat, lng: lng, events: [event]));
      }
    }

    return clusters.asMap().entries.map((entry) {
      final i = entry.key;
      final cluster = entry.value;
      // Usar place_label do primeiro evento do cluster se disponível
      final existingLabel = cluster.events
          .where((e) => e.placeLabel != null && e.placeLabel!.isNotEmpty)
          .map((e) => e.placeLabel!)
          .firstOrNull;
      return OccurrenceLocation(
        index: i + 1,
        lat: cluster.lat,
        lng: cluster.lng,
        label: existingLabel ?? 'Local ${i + 1}',
        arrivedAt: cluster.events.first.timestamp,
        events: cluster.events,
      );
    }).toList();
  }

  /// Resolve um nome legível a partir de coordenadas via reverse geocoding nativo.
  static Future<String> _resolveLabel(double lat, double lng) async {
    try {
      final placemarks = await placemarkFromCoordinates(lat, lng);
      if (placemarks.isNotEmpty) {
        final p = placemarks.first;
        // Prioridade: nome do local > rua > bairro
        if (p.name != null && p.name!.isNotEmpty && p.name != p.postalCode) {
          return p.name!;
        }
        final parts = <String>[];
        if (p.thoroughfare != null && p.thoroughfare!.isNotEmpty) {
          parts.add(p.thoroughfare!);
        }
        if (p.subLocality != null && p.subLocality!.isNotEmpty) {
          parts.add(p.subLocality!);
        }
        if (parts.isNotEmpty) return parts.join(', ');
        if (p.locality != null && p.locality!.isNotEmpty) {
          return p.locality!;
        }
      }
    } catch (_) {
      // Fallback silencioso
    }
    return 'Local';
  }

  /// Distância em metros entre dois pontos (Haversine).
  static double _distanceMeters(
    double lat1,
    double lng1,
    double lat2,
    double lng2,
  ) {
    const earthRadius = 6371000.0; // metros
    final dLat = _toRad(lat2 - lat1);
    final dLng = _toRad(lng2 - lng1);
    final a =
        sin(dLat / 2) * sin(dLat / 2) +
        cos(_toRad(lat1)) * cos(_toRad(lat2)) * sin(dLng / 2) * sin(dLng / 2);
    final c = 2 * atan2(sqrt(a), sqrt(1 - a));
    return earthRadius * c;
  }

  static double _toRad(double deg) => deg * pi / 180;
}

class _Cluster {
  final double lat;
  final double lng;
  final List<OccurrenceEvent> events;

  _Cluster({required this.lat, required this.lng, required this.events});
}
