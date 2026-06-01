import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:latlong2/latlong.dart';

import 'package:canil_gcm/core/services/gps_tracking_service.dart';
import 'package:canil_gcm/core/theme/app_theme.dart';

import 'gps_tracking_summary_screen.dart';

/// Tela de rastreamento GPS ao vivo.
///
/// Mostra mapa OSM dark com a rota sendo desenhada, métricas em tempo real,
/// e controles de pausar/retomar/finalizar.
///
/// Ao finalizar, navega para o summary e retorna o [GpsTrackResult] via pop.
class GpsTrackingScreen extends StatefulWidget {
  final String activityLabel;
  final String dogName;
  final String handlerName;
  final GpsTrackingService trackingService;

  const GpsTrackingScreen({
    super.key,
    required this.activityLabel,
    required this.dogName,
    required this.handlerName,
    required this.trackingService,
  });

  @override
  State<GpsTrackingScreen> createState() => _GpsTrackingScreenState();
}

class _GpsTrackingScreenState extends State<GpsTrackingScreen> {
  late final MapController _mapController;
  bool _mapReady = false;

  GpsTrackingService get _service => widget.trackingService;

  @override
  void initState() {
    super.initState();
    _mapController = MapController();
    _service.addListener(_onServiceUpdate);
    _startIfNeeded();
  }

  Future<void> _startIfNeeded() async {
    if (_service.isActive) return; // já está rastreando (voltou da background)
    final error = await _service.start(activityLabel: widget.activityLabel);
    if (error != null && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error), backgroundColor: AppTheme.error),
      );
      Navigator.of(context).pop();
    }
  }

  void _onServiceUpdate() {
    if (!mounted) return;
    setState(() {});
    // Centralizar mapa na posição atual
    if (_mapReady && _service.currentPosition != null) {
      _mapController.move(
        _service.currentPosition!,
        _mapController.camera.zoom,
      );
    }
  }

  @override
  void dispose() {
    _service.removeListener(_onServiceUpdate);
    super.dispose();
  }

  void _onPauseTap() {
    HapticFeedback.mediumImpact();
    if (_service.isTracking) {
      _service.pause();
    } else if (_service.isPaused) {
      _service.resume();
    }
  }

  Future<void> _onFinishTap() async {
    HapticFeedback.heavyImpact();
    final result = await _service.finish();
    if (!mounted) return;
    // Navega para o summary e aguarda o resultado (confirm ou discard)
    final confirmed = await Navigator.of(context).push<GpsTrackResult?>(
      MaterialPageRoute(
        builder: (_) => GpsTrackingSummaryScreen(
          result: result,
          activityLabel: widget.activityLabel,
          dogName: widget.dogName,
          handlerName: widget.handlerName,
        ),
      ),
    );
    if (!mounted) return;
    // Retorna o resultado (ou null se descartou) para o caller
    Navigator.of(context).pop(confirmed);
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: true, // Back sai da tela mas NÃO para o rastreamento
      child: Scaffold(
        backgroundColor: AppTheme.background,
        body: Column(
          children: [
            _buildHeader(),
            Expanded(child: _buildMap()),
            _buildMetricsPanel(),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return SafeArea(
      bottom: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 6, 14, 8),
        child: Row(
          children: [
            // Back button
            GestureDetector(
              onTap: () => Navigator.of(context).pop(),
              child: Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: AppTheme.primaryChipBackground,
                  borderRadius: BorderRadius.circular(9),
                  border: Border.all(
                    color: AppTheme.primaryChipBorder,
                    width: 1,
                  ),
                ),
                alignment: Alignment.center,
                child: const Text(
                  '‹',
                  style: TextStyle(
                    color: AppTheme.primary,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 11),
            // Title
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.activityLabel,
                    style: GoogleFonts.inter(
                      color: AppTheme.textPrimary,
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  Text(
                    '${widget.dogName} · ${widget.handlerName}',
                    style: GoogleFonts.inter(
                      color: AppTheme.textTertiary,
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
            // GPS signal badge
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
              decoration: BoxDecoration(
                color: AppTheme.primaryChipBackground,
                borderRadius: BorderRadius.circular(7),
                border: Border.all(color: AppTheme.primaryChipBorder, width: 1),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.gps_fixed,
                    color: AppTheme.primary,
                    size: 12,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    'GPS',
                    style: GoogleFonts.inter(
                      color: AppTheme.primary,
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMap() {
    final center = _service.currentPosition ?? const LatLng(-22.5646, -47.4015);
    final route = _service.polyline;

    return Stack(
      children: [
        FlutterMap(
          mapController: _mapController,
          options: MapOptions(
            initialCenter: center,
            initialZoom: 17,
            onMapReady: () => _mapReady = true,
            interactionOptions: const InteractionOptions(
              flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
            ),
          ),
          children: [
            // OSM dark tiles
            TileLayer(
              urlTemplate:
                  'https://{s}.basemaps.cartocdn.com/dark_all/{z}/{x}/{y}@2x.png',
              subdomains: const ['a', 'b', 'c', 'd'],
              userAgentPackageName: 'com.gcm.limeira.canilk9',
              maxZoom: 19,
            ),
            // Route polyline
            if (route.length >= 2)
              PolylineLayer(
                polylines: [
                  Polyline(
                    points: route,
                    color: AppTheme.primary,
                    strokeWidth: 4.5,
                  ),
                ],
              ),
            // Markers
            MarkerLayer(
              markers: [
                // Start marker (green)
                if (_service.startPosition != null)
                  Marker(
                    point: _service.startPosition!,
                    width: 16,
                    height: 16,
                    child: Container(
                      decoration: BoxDecoration(
                        color: AppTheme.success,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: AppTheme.background,
                          width: 2.5,
                        ),
                      ),
                    ),
                  ),
                // Current position (cyan, pulsing)
                if (_service.currentPosition != null)
                  Marker(
                    point: _service.currentPosition!,
                    width: 20,
                    height: 20,
                    child: Container(
                      decoration: BoxDecoration(
                        color: AppTheme.primary,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: AppTheme.background,
                          width: 2.5,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: AppTheme.primary.withAlpha(153),
                            blurRadius: 12,
                            spreadRadius: 4,
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ),
        // Recording badge
        Positioned(
          top: 12,
          left: 0,
          right: 0,
          child: Center(child: _buildRecordingBadge()),
        ),
      ],
    );
  }

  Widget _buildRecordingBadge() {
    final isPaused = _service.isPaused;
    final color = isPaused ? AppTheme.warning : AppTheme.success;
    final label = isPaused ? 'PAUSADO' : 'RASTREANDO';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
      decoration: BoxDecoration(
        color: AppTheme.background.withAlpha(209),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: color.withAlpha(80), width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 7),
          Text(
            label,
            style: GoogleFonts.inter(
              color: color,
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.4,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMetricsPanel() {
    return Container(
      decoration: const BoxDecoration(
        color: AppTheme.background,
        border: Border(
          top: BorderSide(color: AppTheme.primaryDivider, width: 1),
        ),
      ),
      padding: EdgeInsets.fromLTRB(
        16,
        16,
        16,
        16 + MediaQuery.of(context).padding.bottom,
      ),
      child: Column(
        children: [
          // Hero distance
          Text(
            _service.distanceKm.toStringAsFixed(2),
            style: GoogleFonts.ibmPlexMono(
              color: AppTheme.textPrimary,
              fontSize: 46,
              fontWeight: FontWeight.w900,
              letterSpacing: -1,
            ),
          ),
          Text(
            'km',
            style: GoogleFonts.inter(
              color: AppTheme.textMuted,
              fontSize: 12,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(height: 14),
          // Metrics grid
          Row(
            children: [
              _buildMetricCard('Tempo', _service.elapsedFormatted),
              const SizedBox(width: 9),
              _buildMetricCard('Ritmo /km', _service.avgPaceFormatted),
              const SizedBox(width: 9),
              _buildMetricCard('km/h', _service.avgSpeedKmh.toStringAsFixed(1)),
            ],
          ),
          const SizedBox(height: 16),
          // Controls
          Row(
            children: [
              // Pause/Resume
              Expanded(
                child: GestureDetector(
                  onTap: _onPauseTap,
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    decoration: BoxDecoration(
                      color: _service.isPaused
                          ? AppTheme.success
                          : AppTheme.warning.withAlpha(36),
                      borderRadius: BorderRadius.circular(14),
                      border: _service.isPaused
                          ? null
                          : Border.all(
                              color: AppTheme.warning.withAlpha(102),
                              width: 1.5,
                            ),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      _service.isPaused ? 'Retomar' : 'Pausar',
                      style: GoogleFonts.inter(
                        color: _service.isPaused
                            ? AppTheme.background
                            : AppTheme.warning,
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 11),
              // Finish
              Expanded(
                child: GestureDetector(
                  onTap: _onFinishTap,
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    decoration: BoxDecoration(
                      color: AppTheme.error.withAlpha(36),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: AppTheme.error.withAlpha(115),
                        width: 1.5,
                      ),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      'Finalizar',
                      style: GoogleFonts.inter(
                        color: AppTheme.error,
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildMetricCard(String label, String value) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
        decoration: BoxDecoration(
          color: AppTheme.surfaceWhiteOverlayWeak,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: AppTheme.surfaceWhiteBorderSubtle,
            width: 1,
          ),
        ),
        child: Column(
          children: [
            Text(
              value,
              style: GoogleFonts.ibmPlexMono(
                color: AppTheme.textPrimary,
                fontSize: 16,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 3),
            Text(
              label,
              style: GoogleFonts.inter(
                color: AppTheme.textMuted,
                fontSize: 8.5,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.5,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
