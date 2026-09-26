import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:latlong2/latlong.dart' as ll2;

import 'package:canil_gcm/core/services/gps_tracking_service.dart';
import 'package:canil_gcm/core/theme/app_map_style.dart';
import 'package:canil_gcm/core/theme/app_theme.dart';
import 'package:canil_gcm/core/widgets/app_feedback.dart';

import 'gps_tracking_summary_screen.dart';

/// Tela de rastreamento GPS ao vivo.
///
/// Mostra mapa dark com a rota sendo desenhada, métricas em tempo real,
/// e controles de pausar/retomar/finalizar.
///
/// Ao finalizar, navega para o summary e retorna o [GpsTrackResult] via pop.
class GpsTrackingScreen extends StatefulWidget {
  final String activityLabel;
  final String dogName;
  final String handlerName;
  final GpsTrackingService trackingService;
  final GpsTrackingSessionConfig? sessionConfig;
  final bool enableFieldEvents;

  const GpsTrackingScreen({
    super.key,
    required this.activityLabel,
    required this.dogName,
    required this.handlerName,
    required this.trackingService,
    this.sessionConfig,
    this.enableFieldEvents = false,
  });

  @override
  State<GpsTrackingScreen> createState() => _GpsTrackingScreenState();
}

class _GpsTrackingScreenState extends State<GpsTrackingScreen> {
  GoogleMapController? _mapController;
  bool _mapReady = false;

  GpsTrackingService get _service => widget.trackingService;

  @override
  void initState() {
    super.initState();
    _service.addListener(_onServiceUpdate);
    _startIfNeeded();
  }

  Future<void> _startIfNeeded() async {
    if (_service.isActive) return; // já está rastreando (voltou da background)
    final error = await _service.start(
      activityLabel: widget.activityLabel,
      sessionConfig: widget.sessionConfig,
    );
    if (error != null && mounted) {
      AppFeedback.error(context, error);
      Navigator.of(context).pop();
    }
  }

  void _onServiceUpdate() {
    if (!mounted) return;
    setState(() {});
    // Centralizar mapa na posição atual
    if (_mapReady && _service.currentPosition != null && _mapController != null) {
      _mapController!.animateCamera(
        CameraUpdate.newLatLng(
          AppMapStyle.toGoogleLatLng(_service.currentPosition!),
        ),
      );
    }
  }

  @override
  void dispose() {
    _service.removeListener(_onServiceUpdate);
    _mapController?.dispose();
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

  Future<void> _onFinishTap({String finishReason = 'manual'}) async {
    HapticFeedback.heavyImpact();
    final result = await _service.finish(finishReason: finishReason);
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

  Future<void> _onFieldEventTap(GpsFieldEventType type) async {
    HapticFeedback.mediumImpact();
    _service.addEvent(type);
    if (type == GpsFieldEventType.alvoEncontrado) {
      await _onFinishTap(finishReason: type.key);
    }
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
    final rawCenter = _service.currentPosition ?? const ll2.LatLng(-22.5646, -47.4015);
    final center = AppMapStyle.toGoogleLatLng(rawCenter);
    final route = AppMapStyle.toGoogleLatLngList(_service.polyline);

    final markers = <Marker>{};

    if (_service.startPosition != null) {
      markers.add(
        Marker(
          markerId: const MarkerId('start'),
          position: AppMapStyle.toGoogleLatLng(_service.startPosition!),
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen),
          infoWindow: const InfoWindow(title: 'Início'),
        ),
      );
    }

    if (_service.currentPosition != null) {
      markers.add(
        Marker(
          markerId: const MarkerId('current'),
          position: AppMapStyle.toGoogleLatLng(_service.currentPosition!),
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueCyan),
          infoWindow: const InfoWindow(title: 'Posição Atual'),
        ),
      );
    }

    for (int i = 0; i < _service.events.length; i++) {
      final event = _service.events[i];
      if (event.point != null) {
        markers.add(
          Marker(
            markerId: MarkerId('event_$i'),
            position: AppMapStyle.toGoogleLatLng(event.point!.latLng),
            icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueOrange),
            infoWindow: InfoWindow(
              title: event.type.label,
              snippet: 'Evento #${i + 1}',
            ),
          ),
        );
      }
    }

    return Stack(
      children: [
        GoogleMap(
          initialCameraPosition: CameraPosition(
            target: center,
            zoom: 17,
          ),
          style: AppMapStyle.darkStyle,
          rotateGesturesEnabled: false,
          zoomControlsEnabled: false,
          myLocationButtonEnabled: false,
          mapToolbarEnabled: false,
          onMapCreated: (controller) {
            _mapController = controller;
            _mapReady = true;
          },
          polylines: route.length >= 2
              ? {
                  Polyline(
                    polylineId: const PolylineId('tracking_route'),
                    points: route,
                    color: AppTheme.primary,
                    width: 5,
                  ),
                }
              : {},
          markers: markers,
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
          if (widget.enableFieldEvents) ...[
            _buildFieldEventPanel(),
            const SizedBox(height: 14),
          ],
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
                  onTap: () => _onFinishTap(),
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

  Widget _buildFieldEventPanel() {
    const events = [
      GpsFieldEventType.caoIndicou,
      GpsFieldEventType.checagem,
      GpsFieldEventType.perdeuRastro,
      GpsFieldEventType.alvoEncontrado,
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'EVENTOS DE CAMPO',
          style: GoogleFonts.inter(
            color: AppTheme.textMuted,
            fontSize: 9,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.8,
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: events.map((type) {
            final count = _service.events
                .where((event) => event.type == type)
                .length;
            return GestureDetector(
              onTap: () => _onFieldEventTap(type),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: _eventColor(type).withAlpha(30),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: _eventColor(type).withAlpha(90)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(_eventIcon(type), color: _eventColor(type), size: 15),
                    const SizedBox(width: 6),
                    Text(
                      count > 0 ? '${type.label} ($count)' : type.label,
                      style: GoogleFonts.inter(
                        color: _eventColor(type),
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            );
          }).toList(),
        ),
      ],
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

  Color _eventColor(GpsFieldEventType type) {
    return switch (type) {
      GpsFieldEventType.caoIndicou => AppTheme.primary,
      GpsFieldEventType.checagem => AppTheme.warning,
      GpsFieldEventType.perdeuRastro => AppTheme.error,
      GpsFieldEventType.alvoEncontrado => AppTheme.success,
    };
  }

  IconData _eventIcon(GpsFieldEventType type) {
    return switch (type) {
      GpsFieldEventType.caoIndicou => Icons.flag_outlined,
      GpsFieldEventType.checagem => Icons.search_rounded,
      GpsFieldEventType.perdeuRastro => Icons.report_problem_outlined,
      GpsFieldEventType.alvoEncontrado => Icons.check_circle_outline_rounded,
    };
  }
}
