import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart' as gmaps;
import 'package:latlong2/latlong.dart' as ll2;

/// Utilitários de estilo e conversão para o Google Maps no K9 Ops Mobile.
class AppMapStyle {
  AppMapStyle._();

  /// Estilo escuro tático para Google Maps alinhado com a paleta dark do app.
  static const String darkStyle = '''
[
  {
    "elementType": "geometry",
    "stylers": [{"color": "#0d181e"}]
  },
  {
    "elementType": "labels.icon",
    "stylers": [{"visibility": "off"}]
  },
  {
    "elementType": "labels.text.fill",
    "stylers": [{"color": "#758a99"}]
  },
  {
    "elementType": "labels.text.stroke",
    "stylers": [{"color": "#050d10"}]
  },
  {
    "featureType": "administrative",
    "elementType": "geometry",
    "stylers": [{"color": "#2c3b42"}]
  },
  {
    "featureType": "administrative.country",
    "elementType": "labels.text.fill",
    "stylers": [{"color": "#8ec3b9"}]
  },
  {
    "featureType": "administrative.land_parcel",
    "stylers": [{"visibility": "off"}]
  },
  {
    "featureType": "administrative.locality",
    "elementType": "labels.text.fill",
    "stylers": [{"color": "#b0c4cc"}]
  },
  {
    "featureType": "poi",
    "elementType": "labels.text.fill",
    "stylers": [{"color": "#5a7280"}]
  },
  {
    "featureType": "poi.park",
    "elementType": "geometry.fill",
    "stylers": [{"color": "#091f24"}]
  },
  {
    "featureType": "poi.park",
    "elementType": "labels.text.fill",
    "stylers": [{"color": "#3c7680"}]
  },
  {
    "featureType": "road",
    "elementType": "geometry.fill",
    "stylers": [{"color": "#17272e"}]
  },
  {
    "featureType": "road",
    "elementType": "labels.text.fill",
    "stylers": [{"color": "#7a8a92"}]
  },
  {
    "featureType": "road.arterial",
    "elementType": "geometry",
    "stylers": [{"color": "#1d323b"}]
  },
  {
    "featureType": "road.highway",
    "elementType": "geometry",
    "stylers": [{"color": "#23404c"}]
  },
  {
    "featureType": "road.highway",
    "elementType": "geometry.stroke",
    "stylers": [{"color": "#12252c"}]
  },
  {
    "featureType": "road.local",
    "elementType": "labels.text.fill",
    "stylers": [{"color": "#5a7280"}]
  },
  {
    "featureType": "transit",
    "elementType": "labels.text.fill",
    "stylers": [{"color": "#5a7280"}]
  },
  {
    "featureType": "water",
    "elementType": "geometry",
    "stylers": [{"color": "#050d10"}]
  },
  {
    "featureType": "water",
    "elementType": "labels.text.fill",
    "stylers": [{"color": "#3d5560"}]
  }
]
''';

  /// Converte LatLng do latlong2 para o Google Maps LatLng
  static gmaps.LatLng toGoogleLatLng(ll2.LatLng point) {
    return gmaps.LatLng(point.latitude, point.longitude);
  }

  /// Converte lista de LatLng do latlong2 para lista de Google Maps LatLng
  static List<gmaps.LatLng> toGoogleLatLngList(Iterable<ll2.LatLng> points) {
    return points.map(toGoogleLatLng).toList();
  }

  /// Calcula LatLngBounds para envolver uma lista de pontos no Google Maps
  static gmaps.LatLngBounds boundsFromPoints(Iterable<gmaps.LatLng> points) {
    if (points.isEmpty) {
      // Centro tático Limeira/SP caso chamada defensiva sem pontos
      return gmaps.LatLngBounds(
        southwest: const gmaps.LatLng(-22.5657, -47.4023),
        northeast: const gmaps.LatLng(-22.5637, -47.4003),
      );
    }
    double minLat = points.first.latitude;
    double maxLat = points.first.latitude;
    double minLng = points.first.longitude;
    double maxLng = points.first.longitude;

    for (final p in points) {
      if (p.latitude < minLat) minLat = p.latitude;
      if (p.latitude > maxLat) maxLat = p.latitude;
      if (p.longitude < minLng) minLng = p.longitude;
      if (p.longitude > maxLng) maxLng = p.longitude;
    }

    // Margem mínima para evitar bounds com área zero (ponto único ou colinear idêntico)
    if (minLat == maxLat) {
      minLat -= 0.001;
      maxLat += 0.001;
    }
    if (minLng == maxLng) {
      minLng -= 0.001;
      maxLng += 0.001;
    }

    return gmaps.LatLngBounds(
      southwest: gmaps.LatLng(minLat, minLng),
      northeast: gmaps.LatLng(maxLat, maxLng),
    );
  }

  static final Map<String, gmaps.BitmapDescriptor> _markerCache = {};

  /// Cria ou recupera ícone circular customizado para marcador do Google Maps
  static Future<gmaps.BitmapDescriptor> createCircularMarkerIcon({
    required Color color,
    Color borderColor = const Color(0xFF050D10),
    double size = 48.0,
  }) async {
    final key = 'circ_${color.toARGB32()}_${borderColor.toARGB32()}_$size';
    if (_markerCache.containsKey(key)) return _markerCache[key]!;

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    final center = Offset(size / 2, size / 2);
    final radius = (size / 2) - 4;

    final fillPaint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;
    final strokePaint = Paint()
      ..color = borderColor
      ..strokeWidth = 4.0
      ..style = PaintingStyle.stroke;

    canvas.drawCircle(center, radius, fillPaint);
    canvas.drawCircle(center, radius, strokePaint);

    final img = await recorder.endRecording().toImage(size.toInt(), size.toInt());
    final byteData = await img.toByteData(format: ui.ImageByteFormat.png);
    final descriptor = gmaps.BitmapDescriptor.bytes(byteData!.buffer.asUint8List());
    _markerCache[key] = descriptor;
    return descriptor;
  }

  /// Cria ou recupera ícone numerado para pinos de deslocamento
  static Future<gmaps.BitmapDescriptor> createNumberedMarkerIcon({
    required int number,
    required bool isFirst,
  }) async {
    final key = 'num_${number}_$isFirst';
    if (_markerCache.containsKey(key)) return _markerCache[key]!;

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    const size = 64.0;
    const center = Offset(size / 2, size / 2);
    const radius = 26.0;

    final fillPaint = Paint()
      ..color = isFirst ? const Color(0xFF2ECC71) : const Color(0xFF4DD0E1)
      ..style = PaintingStyle.fill;
    final strokePaint = Paint()
      ..color = const Color(0xFF050D10)
      ..strokeWidth = 4.0
      ..style = PaintingStyle.stroke;

    canvas.drawCircle(center, radius, fillPaint);
    canvas.drawCircle(center, radius, strokePaint);

    final textPainter = TextPainter(
      text: TextSpan(
        text: '$number',
        style: const TextStyle(
          color: Color(0xFF050D10),
          fontSize: 24,
          fontWeight: FontWeight.w700,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();

    textPainter.paint(
      canvas,
      center - Offset(textPainter.width / 2, textPainter.height / 2),
    );

    final img = await recorder.endRecording().toImage(size.toInt(), size.toInt());
    final byteData = await img.toByteData(format: ui.ImageByteFormat.png);
    final descriptor = gmaps.BitmapDescriptor.bytes(byteData!.buffer.asUint8List());
    _markerCache[key] = descriptor;
    return descriptor;
  }
}
