import 'dart:math';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'package:canil_gcm/core/theme/app_theme.dart';
import 'package:http/http.dart' as http;

import 'package:canil_gcm/core/services/occurrence_location_service.dart';

/// Gera uma imagem estática de mapa OSM (tiles CartoDB dark) com pinos e trilha.
/// Usado para embutir no PDF sem depender de Google Maps API key.
class OsmStaticMapGenerator {
  static const _tileUrl =
      'https://a.basemaps.cartocdn.com/dark_all/{z}/{x}/{y}.png';
  static const _userAgent = 'CanilK9GCM/1.0 (canil.k9.gcm@limeira.sp.gov.br)';
  static const _tileSize =
      256; // tiles padrão (sem @2x) para economizar memória
  static const _maxTiles = 9; // máximo de tiles para evitar OOM

  final http.Client _client;

  OsmStaticMapGenerator({http.Client? client})
    : _client = client ?? http.Client();

  /// Gera imagem PNG do mapa de deslocamento com pinos numerados e trilha.
  /// [locations] lista de locais clusterizados.
  /// [width]/[height] dimensões da imagem em pixels.
  /// Retorna bytes PNG ou null em caso de erro.
  Future<Uint8List?> generateDisplacementMap(
    List<OccurrenceLocation> locations, {
    int width = 600,
    int height = 320,
  }) async {
    if (locations.isEmpty) return null;

    try {
      // Calcular bounds e zoom
      final points = locations.map((l) => _LatLng(l.lat, l.lng)).toList();
      final bounds = _calculateBounds(points);
      final zoom = _calculateZoom(bounds, width, height);
      final center = _LatLng(
        (bounds.north + bounds.south) / 2,
        (bounds.east + bounds.west) / 2,
      );

      // Calcular quais tiles precisamos
      final tiles = _calculateRequiredTiles(center, zoom, width, height);

      // Baixar tiles em paralelo
      final tileImages = await _downloadTiles(tiles, zoom);

      // Compor imagem final
      final image = await _compositeImage(
        tileImages: tileImages,
        tiles: tiles,
        center: center,
        zoom: zoom,
        width: width,
        height: height,
        locations: locations,
      );

      return image;
    } catch (e) {
      debugPrint('[OsmStaticMap] Erro ao gerar mapa: $e');
      return null;
    }
  }

  /// Gera imagem PNG de mapa simples com um único pino (para a página de localização).
  Future<Uint8List?> generateSinglePointMap(
    double lat,
    double lng, {
    int width = 600,
    int height = 320,
    int zoom = 15,
  }) async {
    try {
      final center = _LatLng(lat, lng);
      final tiles = _calculateRequiredTiles(center, zoom, width, height);
      final tileImages = await _downloadTiles(tiles, zoom);

      final image = await _compositeImage(
        tileImages: tileImages,
        tiles: tiles,
        center: center,
        zoom: zoom,
        width: width,
        height: height,
        locations: [
          OccurrenceLocation(
            index: 1,
            lat: lat,
            lng: lng,
            label: '',
            arrivedAt: DateTime.now(),
            events: const [],
          ),
        ],
      );

      return image;
    } catch (e) {
      debugPrint('[OsmStaticMap] Erro ao gerar mapa single: $e');
      return null;
    }
  }

  // ─── Tile math ──────────────────────────────────────────────────────

  List<_TileCoord> _calculateRequiredTiles(
    _LatLng center,
    int zoom,
    int width,
    int height,
  ) {
    final centerX = _lngToTileX(center.lng, zoom);
    final centerY = _latToTileY(center.lat, zoom);

    var tilesX = (width / _tileSize).ceil() + 1;
    var tilesY = (height / _tileSize).ceil() + 1;

    // Limitar para evitar OOM em dispositivos com pouca RAM
    if (tilesX * tilesY > _maxTiles) {
      tilesX = 3;
      tilesY = 3;
    }

    final startTileX = (centerX - tilesX / 2).floor();
    final startTileY = (centerY - tilesY / 2).floor();

    final tiles = <_TileCoord>[];
    for (var y = startTileY; y <= startTileY + tilesY; y++) {
      for (var x = startTileX; x <= startTileX + tilesX; x++) {
        tiles.add(_TileCoord(x, y, zoom));
      }
    }
    return tiles;
  }

  Future<Map<_TileCoord, ui.Image>> _downloadTiles(
    List<_TileCoord> tiles,
    int zoom,
  ) async {
    final results = <_TileCoord, ui.Image>{};
    final maxTile = (1 << zoom);

    final futures = tiles.map((tile) async {
      // Wrap tile X for world wrapping
      final wrappedX = tile.x % maxTile;
      if (wrappedX < 0 || tile.y < 0 || tile.y >= maxTile) return;

      final url = _tileUrl
          .replaceAll('{z}', '$zoom')
          .replaceAll('{x}', '$wrappedX')
          .replaceAll('{y}', '${tile.y}');

      try {
        final response = await _client
            .get(Uri.parse(url), headers: {'User-Agent': _userAgent})
            .timeout(const Duration(seconds: 8));

        if (response.statusCode == 200) {
          final codec = await ui.instantiateImageCodec(response.bodyBytes);
          final frame = await codec.getNextFrame();
          results[tile] = frame.image;
        }
      } catch (_) {
        // Tile indisponível — será área escura
      }
    });

    await Future.wait(futures);
    return results;
  }

  Future<Uint8List?> _compositeImage({
    required Map<_TileCoord, ui.Image> tileImages,
    required List<_TileCoord> tiles,
    required _LatLng center,
    required int zoom,
    required int width,
    required int height,
    required List<OccurrenceLocation> locations,
  }) async {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(
      recorder,
      Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
    );

    // Fundo escuro
    canvas.drawRect(
      Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
      Paint()..color = AppTheme.surfaceNavigation,
    );

    // Posicionar tiles
    final centerPixelX = _lngToTileX(center.lng, zoom) * _tileSize;
    final centerPixelY = _latToTileY(center.lat, zoom) * _tileSize;
    final offsetX = width / 2 - centerPixelX;
    final offsetY = height / 2 - centerPixelY;

    for (final tile in tiles) {
      final image = tileImages[tile];
      if (image == null) continue;

      final dx = tile.x * _tileSize + offsetX;
      final dy = tile.y * _tileSize + offsetY;

      canvas.drawImageRect(
        image,
        Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
        Rect.fromLTWH(dx, dy, _tileSize.toDouble(), _tileSize.toDouble()),
        Paint()..filterQuality = FilterQuality.high,
      );
    }

    // Converter locais para pixels
    final pixelPoints = locations.map((loc) {
      final px = _lngToTileX(loc.lng, zoom) * _tileSize + offsetX;
      final py = _latToTileY(loc.lat, zoom) * _tileSize + offsetY;
      return Offset(px, py);
    }).toList();

    // Desenhar trilha (polyline)
    if (pixelPoints.length > 1) {
      final path = Path()..moveTo(pixelPoints[0].dx, pixelPoints[0].dy);
      for (var i = 1; i < pixelPoints.length; i++) {
        path.lineTo(pixelPoints[i].dx, pixelPoints[i].dy);
      }
      canvas.drawPath(
        path,
        Paint()
          ..color = AppTheme.primary
          ..strokeWidth = 3.0
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round,
      );
    }

    // Desenhar pinos
    for (var i = 0; i < locations.length; i++) {
      final loc = locations[i];
      final point = pixelPoints[i];
      final isFirst = loc.index == 1;
      final color = isFirst ? AppTheme.success : AppTheme.primary;

      // Sombra
      canvas.drawCircle(
        point + const Offset(0, 2),
        14,
        Paint()..color = AppTheme.background.withAlpha(80),
      );

      // Círculo principal
      canvas.drawCircle(point, 13, Paint()..color = color);

      // Borda escura
      canvas.drawCircle(
        point,
        13,
        Paint()
          ..color = AppTheme.background
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.5,
      );

      // Número
      final textPainter = TextPainter(
        text: TextSpan(
          text: '${loc.index}',
          style: const TextStyle(
            color: AppTheme.surfacePanelStrong,
            fontSize: 12,
            fontWeight: FontWeight.w700,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      textPainter.paint(
        canvas,
        point - Offset(textPainter.width / 2, textPainter.height / 2),
      );
    }

    // Converter para PNG
    final picture = recorder.endRecording();
    final img = await picture.toImage(width, height);
    final byteData = await img.toByteData(format: ui.ImageByteFormat.png);

    // Liberar memória GPU
    img.dispose();
    for (final image in tileImages.values) {
      image.dispose();
    }

    return byteData?.buffer.asUint8List();
  }

  // ─── Geo math ───────────────────────────────────────────────────────

  _Bounds _calculateBounds(List<_LatLng> points) {
    var north = -90.0, south = 90.0, east = -180.0, west = 180.0;
    for (final p in points) {
      if (p.lat > north) north = p.lat;
      if (p.lat < south) south = p.lat;
      if (p.lng > east) east = p.lng;
      if (p.lng < west) west = p.lng;
    }
    return _Bounds(north: north, south: south, east: east, west: west);
  }

  int _calculateZoom(_Bounds bounds, int width, int height) {
    for (var z = 18; z >= 1; z--) {
      final x1 = _lngToTileX(bounds.west, z) * _tileSize;
      final x2 = _lngToTileX(bounds.east, z) * _tileSize;
      final y1 = _latToTileY(bounds.north, z) * _tileSize;
      final y2 = _latToTileY(bounds.south, z) * _tileSize;

      final mapWidth = (x2 - x1).abs();
      final mapHeight = (y2 - y1).abs();

      // Deixar padding de 20% em cada lado
      if (mapWidth < width * 0.6 && mapHeight < height * 0.6) {
        return z;
      }
    }
    return 13;
  }

  double _lngToTileX(double lng, int zoom) {
    return (lng + 180.0) / 360.0 * (1 << zoom);
  }

  double _latToTileY(double lat, int zoom) {
    final latRad = lat * pi / 180.0;
    return (1 - log(tan(latRad) + 1 / cos(latRad)) / pi) / 2 * (1 << zoom);
  }

  void dispose() {
    _client.close();
  }
}

// ─── Helpers ────────────────────────────────────────────────────────

class _LatLng {
  final double lat;
  final double lng;
  const _LatLng(this.lat, this.lng);
}

class _Bounds {
  final double north;
  final double south;
  final double east;
  final double west;
  const _Bounds({
    required this.north,
    required this.south,
    required this.east,
    required this.west,
  });
}

class _TileCoord {
  final int x;
  final int y;
  final int zoom;
  const _TileCoord(this.x, this.y, this.zoom);

  @override
  bool operator ==(Object other) =>
      other is _TileCoord && x == other.x && y == other.y && zoom == other.zoom;

  @override
  int get hashCode => Object.hash(x, y, zoom);
}
