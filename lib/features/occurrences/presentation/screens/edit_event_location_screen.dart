import 'dart:async';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart' as gmaps;
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';

import 'package:canil_gcm/core/services/osm_geocoding_service.dart';
import 'package:canil_gcm/core/theme/app_map_style.dart';
import 'package:canil_gcm/core/theme/app_theme.dart';
import 'package:canil_gcm/core/widgets/app_feedback.dart';
import 'package:canil_gcm/features/occurrences/domain/occurrence_event.dart';
import 'package:canil_gcm/features/occurrences/presentation/view_models/occurrence_view_model.dart';

/// Resultado retornado quando a tela opera em modo pickOnly.
class LocationPickResult {
  final double lat;
  final double lng;
  final String? label;
  final String source;

  const LocationPickResult({
    required this.lat,
    required this.lng,
    this.label,
    required this.source,
  });
}

/// Tela para editar/definir o local de uma ação (evento) de ocorrência.
/// Permite busca via Photon (OSM), usar GPS atual, ou arrastar pino no mapa.
/// Se [pickOnly] é true, retorna um [LocationPickResult] via Navigator.pop
/// sem persistir no Firestore (útil para novos eventos ainda não salvos).
class EditEventLocationScreen extends StatefulWidget {
  final OccurrenceEvent event;
  final int eventIndex;
  final int totalEvents;
  final bool pickOnly;

  const EditEventLocationScreen({
    super.key,
    required this.event,
    required this.eventIndex,
    required this.totalEvents,
    this.pickOnly = false,
  });

  @override
  State<EditEventLocationScreen> createState() =>
      _EditEventLocationScreenState();
}

class _EditEventLocationScreenState extends State<EditEventLocationScreen> {
  static const _cyan = AppTheme.primary;
  static const _bg = AppTheme.background;
  static const _divider = AppTheme.primaryDivider;
  static const _chipBg = AppTheme.primaryChipBackground;
  static const _chipBd = AppTheme.primaryChipBorder;
  static const _muted = AppTheme.textMuted;

  final _searchController = TextEditingController();
  final _geocodingService = OsmGeocodingService();
  gmaps.GoogleMapController? _mapController;

  Timer? _debounce;
  List<GeocodingResult> _suggestions = [];
  bool _isSearching = false;
  bool _isLoadingGps = false;
  bool _isSaving = false;

  LatLng? _selectedPoint;
  String? _selectedLabel;
  String _locationSource = 'gps_atual';

  @override
  void initState() {
    super.initState();
    // Inicializar com coordenada existente
    if (widget.event.gpsLat != null && widget.event.gpsLng != null) {
      _selectedPoint = LatLng(widget.event.gpsLat!, widget.event.gpsLng!);
      _selectedLabel = widget.event.placeLabel;
      _locationSource = widget.event.locationSource ?? 'gps_atual';
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    _geocodingService.dispose();
    _mapController?.dispose();
    super.dispose();
  }

  void _onSearchChanged(String query) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), () {
      _performSearch(query);
    });
  }

  Future<void> _performSearch(String query) async {
    if (query.trim().length < 3) {
      setState(() => _suggestions = []);
      return;
    }

    setState(() => _isSearching = true);

    final results = await _geocodingService.search(
      query,
      biasLat: _selectedPoint?.latitude,
      biasLng: _selectedPoint?.longitude,
    );

    if (mounted) {
      setState(() {
        _suggestions = results;
        _isSearching = false;
      });
    }
  }

  void _onSuggestionSelected(GeocodingResult result) {
    setState(() {
      _selectedPoint = result.point;
      _selectedLabel = result.label;
      _locationSource = 'busca';
      _suggestions = [];
      _searchController.text = result.label;
    });
    _animateToPoint(result.point);
  }

  Future<void> _useCurrentLocation() async {
    setState(() => _isLoadingGps = true);

    try {
      final permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        final requested = await Geolocator.requestPermission();
        if (requested == LocationPermission.denied ||
            requested == LocationPermission.deniedForever) {
          if (mounted) {
            AppFeedback.warning(context, 'Permissão de localização negada');
          }
          return;
        }
      }

      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
        ),
      );

      final point = LatLng(position.latitude, position.longitude);

      // Reverse geocoding para obter label
      final result = await _geocodingService.reverse(point);

      if (mounted) {
        setState(() {
          _selectedPoint = point;
          _selectedLabel = result?.label;
          _locationSource = 'gps_atual';
          _searchController.clear();
          _suggestions = [];
        });
        _animateToPoint(point);
      }
    } catch (e) {
      if (mounted) {
        AppFeedback.error(context, 'Erro ao obter localização: $e');
      }
    } finally {
      if (mounted) setState(() => _isLoadingGps = false);
    }
  }

  void _onMapTap(LatLng point) {
    setState(() {
      _selectedPoint = point;
      _locationSource = 'ajuste_manual';
      _selectedLabel = null;
    });
    // Reverse geocoding em background
    _geocodingService.reverse(point).then((result) {
      if (mounted && result != null) {
        setState(() => _selectedLabel = result.label);
      }
    });
  }

  void _animateToPoint(LatLng point) {
    _mapController?.animateCamera(
      gmaps.CameraUpdate.newLatLngZoom(
        gmaps.LatLng(point.latitude, point.longitude),
        16.0,
      ),
    );
  }

  Future<void> _save() async {
    if (_selectedPoint == null) return;

    // Modo pick-only: retorna resultado sem persistir
    if (widget.pickOnly) {
      Navigator.of(context).pop(
        LocationPickResult(
          lat: _selectedPoint!.latitude,
          lng: _selectedPoint!.longitude,
          label: _selectedLabel,
          source: _locationSource,
        ),
      );
      return;
    }

    setState(() => _isSaving = true);

    try {
      final vm = context.read<OccurrenceViewModel>();

      // O repositório gera auditoria automaticamente (compara old vs new)
      await vm.updateEventLocation(
        occurrenceId: widget.event.occurrenceId,
        eventId: widget.event.id,
        lat: _selectedPoint!.latitude,
        lng: _selectedPoint!.longitude,
        placeLabel: _selectedLabel,
        locationSource: _locationSource,
      );

      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        AppFeedback.error(context, 'Erro ao salvar: $e');
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      body: SafeArea(
        child: Column(
          children: [
            _buildAppBar(),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildContextCard(),
                    const SizedBox(height: 18),
                    _buildSearchSection(),
                    if (_suggestions.isNotEmpty) _buildSuggestions(),
                    _buildOrDivider(),
                    _buildGpsButton(),
                    const SizedBox(height: 18),
                    _buildMiniMap(),
                    if (_isEditing) _buildAuditWarning(),
                    const SizedBox(height: 18),
                    _buildSaveButton(),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  bool get _isEditing =>
      widget.event.gpsLat != null || widget.event.gpsLng != null;

  Widget _buildAppBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: _divider)),
      ),
      child: Row(
        children: [
          GestureDetector(
            onTap: () => Navigator.of(context).pop(),
            child: Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8),
                color: _chipBg,
                border: Border.all(color: _chipBd),
              ),
              child: const Icon(Icons.chevron_left, color: _cyan, size: 20),
            ),
          ),
          const SizedBox(width: 14),
          Text(
            'LOCAL DA AÇÃO',
            style: GoogleFonts.inter(
              color: _cyan,
              fontSize: 13,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.4,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildContextCard() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: Border.all(color: _divider),
        borderRadius: BorderRadius.circular(12),
        color: AppTheme.primary.withAlpha(10),
      ),
      child: Row(
        children: [
          Container(
            width: 30,
            height: 30,
            decoration: const BoxDecoration(
              color: _cyan,
              shape: BoxShape.circle,
            ),
            alignment: Alignment.center,
            child: Text(
              '${widget.eventIndex}',
              style: GoogleFonts.ibmPlexMono(
                color: AppTheme.surfacePanelStrong,
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${_formatTime(widget.event.timestamp)} · ação ${widget.eventIndex} de ${widget.totalEvents}',
                  style: GoogleFonts.ibmPlexMono(
                    color: _muted,
                    fontSize: 11,
                    letterSpacing: 0.4,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  widget.event.title ?? 'Evento',
                  style: GoogleFonts.inter(
                    color: AppTheme.textPrimary,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'BUSCAR LOCAL',
          style: GoogleFonts.inter(
            color: _cyan,
            fontSize: 12,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.2,
          ),
        ),
        const SizedBox(height: 9),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
          decoration: BoxDecoration(
            border: Border.all(color: _cyan),
            borderRadius: BorderRadius.circular(11),
            color: AppTheme.primary.withAlpha(15),
          ),
          child: Row(
            children: [
              const Icon(Icons.search, color: _cyan, size: 18),
              const SizedBox(width: 10),
              Expanded(
                child: TextField(
                  controller: _searchController,
                  onChanged: _onSearchChanged,
                  style: GoogleFonts.inter(
                    color: AppTheme.textPrimary,
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                  ),
                  decoration: InputDecoration(
                    hintText: 'Endereço, POI ou rua...',
                    hintStyle: GoogleFonts.inter(color: _muted, fontSize: 15),
                    border: InputBorder.none,
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(vertical: 10),
                  ),
                ),
              ),
              if (_searchController.text.isNotEmpty)
                GestureDetector(
                  onTap: () {
                    _searchController.clear();
                    setState(() => _suggestions = []);
                  },
                  child: const Icon(Icons.close, color: _muted, size: 18),
                ),
              if (_isSearching)
                const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 1.5,
                    color: _cyan,
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildSuggestions() {
    return Container(
      margin: const EdgeInsets.only(top: 8),
      decoration: BoxDecoration(
        border: Border.all(color: _divider),
        borderRadius: BorderRadius.circular(11),
        color: AppTheme.surfacePanelStrong,
      ),
      child: Column(
        children: _suggestions.asMap().entries.map((entry) {
          final idx = entry.key;
          final result = entry.value;
          final isLast = idx == _suggestions.length - 1;
          return GestureDetector(
            onTap: () => _onSuggestionSelected(result),
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                border: isLast
                    ? null
                    : Border(bottom: BorderSide(color: _divider)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Padding(
                    padding: EdgeInsets.only(top: 2),
                    child: Icon(Icons.place, color: _cyan, size: 16),
                  ),
                  const SizedBox(width: 11),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          result.label,
                          style: GoogleFonts.inter(
                            color: AppTheme.textPrimary,
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        if (result.city != null) ...[
                          const SizedBox(height: 2),
                          Text(
                            [result.street, result.city, result.state]
                                .where((s) => s != null && s.isNotEmpty)
                                .join(', '),
                            style: GoogleFonts.inter(
                              color: _muted,
                              fontSize: 11,
                              height: 1.4,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildOrDivider() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 2),
      child: Row(
        children: [
          Expanded(child: Container(height: 1, color: _divider)),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Text(
              'ou',
              style: GoogleFonts.inter(
                color: _muted,
                fontSize: 11,
                letterSpacing: 0.8,
              ),
            ),
          ),
          Expanded(child: Container(height: 1, color: _divider)),
        ],
      ),
    );
  }

  Widget _buildGpsButton() {
    return GestureDetector(
      onTap: _isLoadingGps ? null : _useCurrentLocation,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(13),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(11),
          color: _chipBg,
          border: Border.all(color: _chipBd),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (_isLoadingGps)
              const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                  strokeWidth: 1.5,
                  color: _cyan,
                ),
              )
            else
              const Icon(Icons.my_location, color: _cyan, size: 18),
            const SizedBox(width: 9),
            Text(
              'Usar minha localização atual',
              style: GoogleFonts.inter(
                color: _cyan,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMiniMap() {
    final center = _selectedPoint ?? const LatLng(-22.5647, -47.4013);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          height: 170,
          decoration: BoxDecoration(
            border: Border.all(color: _divider),
            borderRadius: BorderRadius.circular(13),
          ),
          clipBehavior: Clip.antiAlias,
          child: Stack(
            children: [
              gmaps.GoogleMap(
                initialCameraPosition: gmaps.CameraPosition(
                  target: gmaps.LatLng(center.latitude, center.longitude),
                  zoom: _selectedPoint != null ? 16.0 : 13.0,
                ),
                style: AppMapStyle.darkStyle,
                rotateGesturesEnabled: false,
                zoomControlsEnabled: false,
                myLocationButtonEnabled: false,
                mapToolbarEnabled: false,
                onMapCreated: (controller) => _mapController = controller,
                onTap: (point) =>
                    _onMapTap(LatLng(point.latitude, point.longitude)),
                markers: _selectedPoint != null
                    ? {
                        gmaps.Marker(
                          markerId: const gmaps.MarkerId('selected_pin'),
                          position: gmaps.LatLng(
                            _selectedPoint!.latitude,
                            _selectedPoint!.longitude,
                          ),
                          icon: gmaps.BitmapDescriptor.defaultMarkerWithHue(
                            gmaps.BitmapDescriptor.hueCyan,
                          ),
                          infoWindow: gmaps.InfoWindow(
                            title: _selectedLabel ?? 'Local Selecionado',
                          ),
                        ),
                      }
                    : {},
              ),
              // Tag "arraste o pino"
              Positioned(
                top: 10,
                left: 10,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 9,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: AppTheme.background.withAlpha(199),
                    border: Border.all(color: _divider),
                    borderRadius: BorderRadius.circular(7),
                  ),
                  child: Text(
                    'toque para ajustar',
                    style: GoogleFonts.ibmPlexMono(
                      color: AppTheme.textSecondary,
                      fontSize: 10,
                      letterSpacing: 0.2,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        // Coordenadas
        if (_selectedPoint != null)
          Padding(
            padding: const EdgeInsets.only(top: 11),
            child: Row(
              children: [
                Text(
                  'COORD.',
                  style: GoogleFonts.inter(
                    color: _muted,
                    fontSize: 11,
                    letterSpacing: 1.0,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  '${_selectedPoint!.latitude.toStringAsFixed(4)}, ${_selectedPoint!.longitude.toStringAsFixed(4)}',
                  style: GoogleFonts.ibmPlexMono(
                    color: _cyan,
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _buildAuditWarning() {
    return Container(
      margin: const EdgeInsets.only(top: 16),
      padding: const EdgeInsets.all(11),
      decoration: BoxDecoration(
        border: Border.all(color: AppTheme.warning.withAlpha(64)),
        borderRadius: BorderRadius.circular(11),
        color: AppTheme.warning.withAlpha(13),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('⚠️', style: TextStyle(fontSize: 14)),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              'Você está corrigindo o local desta ação. A alteração fica registrada na trilha de auditoria, sem apagar o ponto original.',
              style: GoogleFonts.inter(
                color: AppTheme.textSecondary,
                fontSize: 12,
                height: 1.45,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSaveButton() {
    final enabled = _selectedPoint != null && !_isSaving;
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton(
        onPressed: enabled ? _save : null,
        style: ElevatedButton.styleFrom(
          backgroundColor: _cyan,
          disabledBackgroundColor: _cyan.withAlpha(60),
          foregroundColor: AppTheme.surfacePanelStrong,
          padding: const EdgeInsets.all(15),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
        child: _isSaving
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: AppTheme.surfacePanelStrong,
                ),
              )
            : Text(
                'Salvar local',
                style: GoogleFonts.inter(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.2,
                ),
              ),
      ),
    );
  }

  String _formatTime(DateTime dt) {
    final h = dt.hour.toString().padLeft(2, '0');
    final m = dt.minute.toString().padLeft(2, '0');
    return '${h}h$m';
  }
}
