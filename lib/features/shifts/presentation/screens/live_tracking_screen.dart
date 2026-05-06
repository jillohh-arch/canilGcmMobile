import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import 'package:canil_gcm/features/shifts/presentation/viewmodels/live_tracking_viewmodel.dart';

class LiveTrackingScreen extends StatefulWidget {
  final bool isLightMode;

  const LiveTrackingScreen({super.key, this.isLightMode = false});

  @override
  State<LiveTrackingScreen> createState() => _LiveTrackingScreenState();
}

class _LiveTrackingScreenState extends State<LiveTrackingScreen> {
  GoogleMapController? _mapController;
  late final LiveTrackingViewModel _viewModel;
  LatLng? _lastAnimatedPoint;

  final String _darkMapStyle = '''
  [
    {
      "elementType": "geometry",
      "stylers": [{"color": "#212121"}]
    },
    {
      "elementType": "labels.icon",
      "stylers": [{"visibility": "off"}]
    },
    {
      "elementType": "labels.text.fill",
      "stylers": [{"color": "#757575"}]
    },
    {
      "elementType": "labels.text.stroke",
      "stylers": [{"color": "#212121"}]
    },
    {
      "featureType": "administrative",
      "elementType": "geometry",
      "stylers": [{"color": "#757575"}]
    },
    {
      "featureType": "administrative.country",
      "elementType": "labels.text.fill",
      "stylers": [{"color": "#9e9e9e"}]
    },
    {
      "featureType": "administrative.land_parcel",
      "stylers": [{"visibility": "off"}]
    },
    {
      "featureType": "administrative.locality",
      "elementType": "labels.text.fill",
      "stylers": [{"color": "#bdbdbd"}]
    },
    {
      "featureType": "poi",
      "elementType": "labels.text.fill",
      "stylers": [{"color": "#757575"}]
    },
    {
      "featureType": "poi.park",
      "elementType": "geometry",
      "stylers": [{"color": "#181818"}]
    },
    {
      "featureType": "poi.park",
      "elementType": "labels.text.fill",
      "stylers": [{"color": "#616161"}]
    },
    {
      "featureType": "poi.park",
      "elementType": "labels.text.stroke",
      "stylers": [{"color": "#1b1b1b"}]
    },
    {
      "featureType": "road",
      "elementType": "geometry.fill",
      "stylers": [{"color": "#2c2c2c"}]
    },
    {
      "featureType": "road",
      "elementType": "labels.text.fill",
      "stylers": [{"color": "#8a8a8a"}]
    },
    {
      "featureType": "road.arterial",
      "elementType": "geometry",
      "stylers": [{"color": "#373737"}]
    },
    {
      "featureType": "road.highway",
      "elementType": "geometry",
      "stylers": [{"color": "#3c3c3c"}]
    },
    {
      "featureType": "road.highway.controlled_access",
      "elementType": "geometry",
      "stylers": [{"color": "#4e4e4e"}]
    },
    {
      "featureType": "road.local",
      "elementType": "labels.text.fill",
      "stylers": [{"color": "#616161"}]
    },
    {
      "featureType": "transit",
      "elementType": "labels.text.fill",
      "stylers": [{"color": "#757575"}]
    },
    {
      "featureType": "water",
      "elementType": "geometry",
      "stylers": [{"color": "#000000"}]
    },
    {
      "featureType": "water",
      "elementType": "labels.text.fill",
      "stylers": [{"color": "#3d3d3d"}]
    }
  ]
  ''';

  @override
  void initState() {
    super.initState();
    _viewModel = LiveTrackingViewModel()..addListener(_handleViewModelChanged);
  }

  @override
  void dispose() {
    _viewModel
      ..removeListener(_handleViewModelChanged)
      ..dispose();
    super.dispose();
  }

  List<LatLng> get _routePoints => _viewModel.routePoints;
  bool get _isTracking => _viewModel.isTracking;
  double get _totalDistanceMeters => _viewModel.totalDistanceMeters;
  int get _elapsedSeconds => _viewModel.elapsedSeconds;

  void _handleViewModelChanged() {
    if (!mounted) return;
    setState(() {});

    if (_isTracking && _routePoints.isNotEmpty) {
      final latestPoint = _routePoints.last;
      if (_lastAnimatedPoint != latestPoint) {
        _lastAnimatedPoint = latestPoint;
        _mapController?.animateCamera(CameraUpdate.newLatLng(latestPoint));
      }
    }
  }

  Future<void> _centerToUserLocation() async {
    final currentLatLng = await _viewModel.getCurrentLatLng();
    if (currentLatLng == null || _mapController == null) return;

    await _mapController!.animateCamera(
      CameraUpdate.newLatLngZoom(currentLatLng, 16.0),
    );
  }

  Future<void> _startTracking() async {
    HapticFeedback.mediumImpact();

    final result = await _viewModel.startTracking();
    if (!result.isSuccess) {
      if (mounted && result.errorMessage != null) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(result.errorMessage!)));
      }
      return;
    }

    if (_mapController != null) {
      _lastAnimatedPoint = result.initialPoint;
      await _mapController!.animateCamera(
        CameraUpdate.newLatLngZoom(result.initialPoint!, 16.5),
      );
      HapticFeedback.lightImpact();
    }
  }

  Future<void> _stopAndSave() async {
    HapticFeedback.mediumImpact();
    final result = await _viewModel.stopAndBuildResult();
    if (!mounted) return;
    Navigator.pop(context, result.toMap());
  }

  String _formatTime(int seconds) {
    final minutes = (seconds / 60).floor();
    final remainingSeconds = seconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${remainingSeconds.toString().padLeft(2, '0')}';
  }

  String _calculateSpeed() {
    if (_elapsedSeconds == 0) return '0.0';
    final speed = (_totalDistanceMeters / _elapsedSeconds) * 3.6;
    return speed.toStringAsFixed(1);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: Container(
          margin: const EdgeInsets.all(8),
          decoration: const BoxDecoration(
            color: Colors.black45,
            shape: BoxShape.circle,
          ),
          child: IconButton(
            icon: const Icon(Icons.close_rounded, color: Colors.white),
            onPressed: () => Navigator.pop(context),
          ),
        ),
      ),
      body: Stack(
        children: [
          GoogleMap(
            initialCameraPosition: const CameraPosition(
              target: LatLng(-23.5505, -46.6333),
              zoom: 12,
            ),
            style: _darkMapStyle,
            onMapCreated: (controller) {
              _mapController = controller;
              _centerToUserLocation();
            },
            myLocationEnabled: true,
            myLocationButtonEnabled: false,
            zoomControlsEnabled: false,
            compassEnabled: false,
            polylines: {
              Polyline(
                polylineId: const PolylineId('tracking_route'),
                points: _routePoints,
                color: widget.isLightMode
                    ? const Color(0xFF26C6DA)
                    : const Color(0xFFFBBF24),
                width: 5,
                jointType: JointType.round,
                endCap: Cap.roundCap,
                startCap: Cap.roundCap,
              ),
            },
          ),
          Align(
            alignment: Alignment.bottomCenter,
            child: ClipRect(
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 10.0, sigmaY: 10.0),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.fromLTRB(20, 24, 20, 40),
                  decoration: BoxDecoration(
                    color: Colors.black.withAlpha(180),
                    border: const Border(
                      top: BorderSide(color: Colors.white12, width: 1),
                    ),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          _MetricBox(
                            label: 'DISTANCIA',
                            value: _totalDistanceMeters > 999
                                ? '${(_totalDistanceMeters / 1000).toStringAsFixed(2)} km'
                                : '${_totalDistanceMeters.toStringAsFixed(0)} m',
                          ),
                          _MetricBox(
                            label: 'TEMPO',
                            value: _formatTime(_elapsedSeconds),
                          ),
                          if (!widget.isLightMode)
                            _MetricBox(
                              label: 'VELOCIDADE',
                              value: '${_calculateSpeed()} km/h',
                            ),
                        ],
                      ),
                      const SizedBox(height: 24),
                      SizedBox(
                        width: double.infinity,
                        height: 56,
                        child: ElevatedButton(
                          onPressed: _isTracking
                              ? _stopAndSave
                              : _startTracking,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: _isTracking
                                ? const Color(0xFFC62828)
                                : const Color(0xFF1B8A4C),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(6),
                            ),
                            elevation: 0,
                          ),
                          child: Text(
                            _isTracking
                                ? 'ENCERRAR E SALVAR'
                                : 'INICIAR RASTREIO TATICO',
                            style: GoogleFonts.inter(
                              fontSize: 16,
                              fontWeight: FontWeight.w900,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MetricBox extends StatelessWidget {
  final String label;
  final String value;

  const _MetricBox({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: GoogleFonts.inter(
            fontSize: 10,
            fontWeight: FontWeight.bold,
            color: Colors.white54,
            letterSpacing: 0.5,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: GoogleFonts.inter(
            fontSize: 24,
            fontWeight: FontWeight.w900,
            color: Colors.white,
          ),
        ),
      ],
    );
  }
}
