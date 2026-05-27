import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

/// Resultado de uma busca de geocoding (forward search).
class GeocodingResult {
  final String label;
  final String? street;
  final String? city;
  final String? state;
  final LatLng point;

  const GeocodingResult({
    required this.label,
    this.street,
    this.city,
    this.state,
    required this.point,
  });

  @override
  String toString() => label;
}

/// Serviço de geocoding via Photon (OSM) para busca de endereços e POIs.
/// Usa debounce interno e user-agent conforme política de uso.
class OsmGeocodingService {
  static const _photonBaseUrl = 'https://photon.komoot.io/api/';
  static const _userAgent = 'CanilK9GCM/1.0 (canil.k9.gcm@limeira.sp.gov.br)';

  /// Bias de localização para priorizar resultados próximos (Limeira/SP).
  static const _defaultBiasLat = -22.5647;
  static const _defaultBiasLng = -47.4013;

  final http.Client _client;

  OsmGeocodingService({http.Client? client})
      : _client = client ?? http.Client();

  /// Busca endereços/POIs via Photon com bias geográfico.
  /// Retorna lista vazia em caso de erro ou query vazia.
  /// [query] texto digitado pelo usuário.
  /// [biasLat]/[biasLng] ponto de referência para priorizar resultados próximos.
  /// [limit] número máximo de resultados.
  Future<List<GeocodingResult>> search(
    String query, {
    double? biasLat,
    double? biasLng,
    int limit = 5,
  }) async {
    final trimmed = query.trim();
    if (trimmed.length < 3) return [];

    final params = <String, String>{
      'q': trimmed,
      'limit': '$limit',
      'lang': 'pt',
      'lat': '${biasLat ?? _defaultBiasLat}',
      'lon': '${biasLng ?? _defaultBiasLng}',
    };

    final uri = Uri.parse(_photonBaseUrl).replace(queryParameters: params);

    try {
      final response = await _client
          .get(uri, headers: {'User-Agent': _userAgent})
          .timeout(const Duration(seconds: 5));

      if (response.statusCode != 200) return [];

      final json = jsonDecode(response.body) as Map<String, dynamic>;
      final features = json['features'] as List<dynamic>? ?? [];

      return features.map((f) => _parseFeature(f as Map<String, dynamic>)).toList();
    } on TimeoutException {
      return [];
    } catch (_) {
      return [];
    }
  }

  /// Reverse geocoding via Photon: coordenada → endereço.
  Future<GeocodingResult?> reverse(LatLng point) async {
    final uri = Uri.parse('https://photon.komoot.io/reverse').replace(
      queryParameters: {
        'lat': '${point.latitude}',
        'lon': '${point.longitude}',
        'lang': 'pt',
      },
    );

    try {
      final response = await _client
          .get(uri, headers: {'User-Agent': _userAgent})
          .timeout(const Duration(seconds: 5));

      if (response.statusCode != 200) return null;

      final json = jsonDecode(response.body) as Map<String, dynamic>;
      final features = json['features'] as List<dynamic>? ?? [];

      if (features.isEmpty) return null;
      return _parseFeature(features.first as Map<String, dynamic>);
    } on TimeoutException {
      return null;
    } catch (_) {
      return null;
    }
  }

  GeocodingResult _parseFeature(Map<String, dynamic> feature) {
    final geometry = feature['geometry'] as Map<String, dynamic>;
    final coords = geometry['coordinates'] as List<dynamic>;
    final lng = (coords[0] as num).toDouble();
    final lat = (coords[1] as num).toDouble();

    final props = feature['properties'] as Map<String, dynamic>? ?? {};
    final name = props['name'] as String? ?? '';
    final street = props['street'] as String?;
    final city = props['city'] as String?;
    final state = props['state'] as String?;

    // Montar label legível
    final parts = <String>[];
    if (name.isNotEmpty) parts.add(name);
    if (street != null && street.isNotEmpty && street != name) {
      parts.add(street);
    }
    if (city != null && city.isNotEmpty) parts.add(city);

    final label = parts.isNotEmpty ? parts.join(', ') : '$lat, $lng';

    return GeocodingResult(
      label: label,
      street: street,
      city: city,
      state: state,
      point: LatLng(lat, lng),
    );
  }

  void dispose() {
    _client.close();
  }
}
