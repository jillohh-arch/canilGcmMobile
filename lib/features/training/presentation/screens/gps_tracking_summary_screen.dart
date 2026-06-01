import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:latlong2/latlong.dart';

import 'package:canil_gcm/core/services/gps_tracking_service.dart';
import 'package:canil_gcm/core/theme/app_theme.dart';

/// Tela de resumo após finalizar o rastreamento GPS.
///
/// Mostra mapa da rota completa + 4 métricas + confirmar/descartar.
/// Ao confirmar, retorna o [GpsTrackResult] via Navigator.pop para o caller.
class GpsTrackingSummaryScreen extends StatefulWidget {
  final GpsTrackResult result;
  final String activityLabel;
  final String dogName;
  final String handlerName;

  const GpsTrackingSummaryScreen({
    super.key,
    required this.result,
    required this.activityLabel,
    required this.dogName,
    required this.handlerName,
  });

  @override
  State<GpsTrackingSummaryScreen> createState() =>
      _GpsTrackingSummaryScreenState();
}

class _GpsTrackingSummaryScreenState extends State<GpsTrackingSummaryScreen> {
  bool _confirmed = false;

  @override
  Widget build(BuildContext context) {
    final route = widget.result.polyline;
    final bottomPad = MediaQuery.of(context).padding.bottom;

    return Scaffold(
      backgroundColor: AppTheme.background,
      body: Column(
        children: [
          // Header
          SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'RASTREAMENTO CONCLUÍDO',
                    style: GoogleFonts.inter(
                      color: AppTheme.success,
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.5,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    widget.activityLabel,
                    style: GoogleFonts.inter(
                      color: AppTheme.textPrimary,
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    '${widget.dogName} · ${widget.handlerName} · ${_formatDateRange()}',
                    style: GoogleFonts.inter(
                      color: AppTheme.textTertiary,
                      fontSize: 11.5,
                    ),
                  ),
                ],
              ),
            ),
          ),
          // Map
          SizedBox(height: 230, child: _buildMap(route)),
          // Metrics grid
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                Row(
                  children: [
                    _buildMetricTile(
                      'Distância',
                      (widget.result.distanceMeters / 1000).toStringAsFixed(2),
                      'km',
                    ),
                    const SizedBox(width: 9),
                    _buildMetricTile(
                      'Tempo',
                      _formatDuration(widget.result.durationSeconds),
                      null,
                    ),
                  ],
                ),
                const SizedBox(height: 9),
                Row(
                  children: [
                    _buildMetricTile(
                      'Ritmo médio',
                      widget.result.avgPaceFormatted,
                      '/km',
                    ),
                    const SizedBox(width: 9),
                    _buildMetricTile(
                      'Velocidade média',
                      widget.result.avgSpeedKmh.toStringAsFixed(1),
                      'km/h',
                    ),
                  ],
                ),
              ],
            ),
          ),
          const Spacer(),
          // Actions
          Padding(
            padding: EdgeInsets.fromLTRB(16, 0, 16, 18 + bottomPad),
            child: Row(
              children: [
                // Discard
                Expanded(
                  flex: 3,
                  child: _DiscardButton(onDiscard: () => _onDiscard(context)),
                ),
                const SizedBox(width: 11),
                // Confirm (return result to form)
                Expanded(
                  flex: 5,
                  child: _ConfirmButton(onConfirm: () => _onConfirm(context)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMap(List<LatLng> route) {
    if (route.isEmpty) {
      return Container(
        color: AppTheme.surfacePanelSoft,
        alignment: Alignment.center,
        child: Text(
          'Sem pontos registrados',
          style: GoogleFonts.inter(color: AppTheme.textMuted),
        ),
      );
    }

    // Calcular bounds
    final bounds = LatLngBounds.fromPoints(route);

    return FlutterMap(
      options: MapOptions(
        initialCameraFit: CameraFit.bounds(
          bounds: bounds,
          padding: const EdgeInsets.all(40),
        ),
        interactionOptions: const InteractionOptions(
          flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
        ),
      ),
      children: [
        TileLayer(
          urlTemplate:
              'https://{s}.basemaps.cartocdn.com/dark_all/{z}/{x}/{y}@2x.png',
          subdomains: const ['a', 'b', 'c', 'd'],
          userAgentPackageName: 'com.gcm.limeira.canilk9',
          maxZoom: 19,
        ),
        PolylineLayer(
          polylines: [
            Polyline(points: route, color: AppTheme.primary, strokeWidth: 4.5),
          ],
        ),
        MarkerLayer(
          markers: [
            // Start (green)
            Marker(
              point: route.first,
              width: 16,
              height: 16,
              child: Container(
                decoration: BoxDecoration(
                  color: AppTheme.success,
                  shape: BoxShape.circle,
                  border: Border.all(color: AppTheme.background, width: 2.5),
                ),
              ),
            ),
            // End (red flag)
            Marker(
              point: route.last,
              width: 18,
              height: 18,
              child: Container(
                decoration: BoxDecoration(
                  color: AppTheme.error,
                  shape: BoxShape.circle,
                  border: Border.all(color: AppTheme.background, width: 2),
                ),
                child: const Icon(
                  Icons.flag_rounded,
                  color: AppTheme.textPrimary,
                  size: 10,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildMetricTile(String label, String value, String? unit) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(13),
        decoration: BoxDecoration(
          color: AppTheme.surfaceWhiteOverlayWeak,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: AppTheme.surfaceWhiteBorderSubtle,
            width: 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label.toUpperCase(),
              style: GoogleFonts.inter(
                color: AppTheme.textMuted,
                fontSize: 9,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.6,
              ),
            ),
            const SizedBox(height: 4),
            RichText(
              text: TextSpan(
                children: [
                  TextSpan(
                    text: value,
                    style: GoogleFonts.ibmPlexMono(
                      color: AppTheme.textPrimary,
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  if (unit != null)
                    TextSpan(
                      text: ' $unit',
                      style: GoogleFonts.ibmPlexMono(
                        color: AppTheme.textMuted,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
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

  String _formatDateRange() {
    final start = widget.result.startedAt;
    final end = widget.result.endedAt;
    final day =
        '${start.day.toString().padLeft(2, '0')}/${start.month.toString().padLeft(2, '0')}';
    final startTime =
        '${start.hour.toString().padLeft(2, '0')}:${start.minute.toString().padLeft(2, '0')}';
    final endTime =
        '${end.hour.toString().padLeft(2, '0')}:${end.minute.toString().padLeft(2, '0')}';
    return '$day, $startTime – $endTime';
  }

  String _formatDuration(int seconds) {
    final h = seconds ~/ 3600;
    final m = (seconds % 3600) ~/ 60;
    final s = seconds % 60;
    if (h > 0) {
      return '${h}h${m.toString().padLeft(2, '0')}';
    }
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  void _onConfirm(BuildContext context) {
    if (_confirmed) return; // Previne múltiplos cliques
    setState(() => _confirmed = true);
    HapticFeedback.heavyImpact();
    // Retorna o resultado para o caller (formulário de condicionamento)
    Navigator.of(context).pop(widget.result);
  }

  void _onDiscard(BuildContext context) {
    HapticFeedback.mediumImpact();
    // Retorna null — descartou o rastreamento
    Navigator.of(context).pop(null);
  }
}

class _DiscardButton extends StatelessWidget {
  final VoidCallback onDiscard;
  const _DiscardButton({required this.onDiscard});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onDiscard,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 16),
        decoration: BoxDecoration(
          color: AppTheme.error.withAlpha(36),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppTheme.error.withAlpha(115), width: 1.5),
        ),
        alignment: Alignment.center,
        child: Text(
          'Descartar',
          style: GoogleFonts.inter(
            color: AppTheme.error,
            fontSize: 14,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
    );
  }
}

class _ConfirmButton extends StatelessWidget {
  final VoidCallback onConfirm;
  const _ConfirmButton({required this.onConfirm});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onConfirm,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 16),
        decoration: BoxDecoration(
          color: AppTheme.primary,
          borderRadius: BorderRadius.circular(14),
        ),
        alignment: Alignment.center,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.check_rounded,
              color: AppTheme.background,
              size: 17,
            ),
            const SizedBox(width: 8),
            Text(
              'Confirmar rota',
              style: GoogleFonts.inter(
                color: AppTheme.background,
                fontSize: 14,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
