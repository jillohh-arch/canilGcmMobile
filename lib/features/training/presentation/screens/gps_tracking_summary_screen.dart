import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:latlong2/latlong.dart' as ll2;

import 'package:canil_gcm/core/services/gps_tracking_service.dart';
import 'package:canil_gcm/core/theme/app_map_style.dart';
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
  String _result = 'completa';
  final TextEditingController _observationController = TextEditingController();

  bool get _hasSessionResult => widget.result.sessionConfig != null;

  @override
  void dispose() {
    _observationController.dispose();
    super.dispose();
  }

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
          if (_hasSessionResult)
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                child: Column(
                  children: [
                    _buildLinkCard(),
                    const SizedBox(height: 10),
                    _buildResultCard(),
                  ],
                ),
              ),
            )
          else
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

  Widget _buildMap(List<ll2.LatLng> route) {
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

    final gmapRoute = AppMapStyle.toGoogleLatLngList(route);
    final bounds = AppMapStyle.boundsFromPoints(gmapRoute);

    return GoogleMap(
      initialCameraPosition: CameraPosition(
        target: gmapRoute.first,
        zoom: 15,
      ),
      style: AppMapStyle.darkStyle,
      rotateGesturesEnabled: false,
      zoomControlsEnabled: false,
      myLocationButtonEnabled: false,
      mapToolbarEnabled: false,
      onMapCreated: (controller) {
        controller.animateCamera(
          CameraUpdate.newLatLngBounds(bounds, 40),
        );
      },
      polylines: {
        Polyline(
          polylineId: const PolylineId('summary_route'),
          points: gmapRoute,
          color: AppTheme.primary,
          width: 4,
        ),
      },
      markers: {
        Marker(
          markerId: const MarkerId('start'),
          position: gmapRoute.first,
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen),
        ),
        Marker(
          markerId: const MarkerId('end'),
          position: gmapRoute.last,
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
        ),
      },
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

  Widget _buildLinkCard() {
    final config = widget.result.sessionConfig;
    if (config == null) return const SizedBox.shrink();
    final isFormation = config.phase == 'formation';
    final linkText = isFormation
        ? [
            if (config.moduleName != null) config.moduleName!,
            if (config.milestoneLabel != null) config.milestoneLabel!,
          ].join(' · ')
        : 'Manutenção operacional sem vínculo a módulo';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.primary.withAlpha(12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.primary.withAlpha(55)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            isFormation ? 'VÍNCULO DA SESSÃO' : 'SESSÃO OPERACIONAL',
            style: GoogleFonts.inter(
              color: AppTheme.primary,
              fontSize: 9,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.8,
            ),
          ),
          const SizedBox(height: 5),
          Text(
            linkText,
            style: GoogleFonts.inter(
              color: AppTheme.textPrimary,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            'Figurante: ${config.figurante} · Odor: ${config.odorObject} · Ambiente: ${config.ambiente}',
            style: GoogleFonts.inter(
              color: AppTheme.textMuted,
              fontSize: 10.5,
              height: 1.35,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildResultCard() {
    const options = {
      'completa': 'Completa',
      'parcial': 'Parcial',
      'sem_exito': 'Sem êxito',
    };

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.surfaceWhiteOverlayWeak,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.surfaceWhiteBorderSubtle),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'RESULTADO DA SESSÃO',
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
            children: options.entries.map((entry) {
              final selected = _result == entry.key;
              return ChoiceChip(
                selected: selected,
                label: Text(entry.value),
                onSelected: (_) => setState(() => _result = entry.key),
                selectedColor: AppTheme.primary.withAlpha(45),
                backgroundColor: AppTheme.textPrimary.withAlpha(12),
                labelStyle: GoogleFonts.inter(
                  color: selected ? AppTheme.primary : AppTheme.textSecondary,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                ),
                side: BorderSide(
                  color: selected
                      ? AppTheme.primary.withAlpha(100)
                      : AppTheme.textPrimary.withAlpha(20),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _observationController,
            minLines: 2,
            maxLines: 4,
            style: GoogleFonts.inter(color: AppTheme.textPrimary, fontSize: 12),
            decoration: InputDecoration(
              hintText: 'Observação opcional da sessão',
              hintStyle: GoogleFonts.inter(
                color: AppTheme.textMuted,
                fontSize: 12,
              ),
              filled: true,
              fillColor: AppTheme.background.withAlpha(130),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(
                  color: AppTheme.textPrimary.withAlpha(20),
                ),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(
                  color: AppTheme.textPrimary.withAlpha(20),
                ),
              ),
              focusedBorder: const OutlineInputBorder(
                borderSide: BorderSide(color: AppTheme.primary),
              ),
            ),
          ),
        ],
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

  Future<void> _onConfirm(BuildContext context) async {
    if (_confirmed) return;
    setState(() => _confirmed = true);
    HapticFeedback.heavyImpact();
    var result = widget.result;
    if (_hasSessionResult) {
      result = result.copyWith(
        result: _result,
        observation: _observationController.text.trim(),
      );
      await result.persistLocalDraft();
    }
    if (!context.mounted) return;
    Navigator.of(context).pop(result);
  }

  Future<void> _onDiscard(BuildContext context) async {
    HapticFeedback.mediumImpact();
    await widget.result.deleteLocalDraft();
    if (!context.mounted) return;
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
