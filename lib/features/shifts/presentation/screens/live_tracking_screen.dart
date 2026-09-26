import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:latlong2/latlong.dart' as ll2;

import 'package:canil_gcm/core/theme/app_map_style.dart';
import 'package:canil_gcm/core/theme/app_theme.dart';
import 'package:canil_gcm/core/widgets/app_feedback.dart';
import 'package:canil_gcm/features/shifts/presentation/viewmodels/live_tracking_viewmodel.dart';

part 'live_tracking_widgets.dart';

class LiveTrackingScreen extends StatefulWidget {
  final bool isLightMode;

  const LiveTrackingScreen({super.key, this.isLightMode = false});

  @override
  State<LiveTrackingScreen> createState() => _LiveTrackingScreenState();
}

class _LiveTrackingScreenState extends State<LiveTrackingScreen> {
  GoogleMapController? _mapController;
  late final LiveTrackingViewModel _viewModel;
  ll2.LatLng? _lastAnimatedPoint;

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
    _mapController?.dispose();
    super.dispose();
  }

  List<ll2.LatLng> get _routePoints => _viewModel.routePoints;
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
        _mapController?.animateCamera(
          CameraUpdate.newLatLng(
            AppMapStyle.toGoogleLatLng(latestPoint),
          ),
        );
      }
    }
  }

  Future<void> _startTracking() async {
    HapticFeedback.mediumImpact();

    final result = await _viewModel.startTracking();
    if (!result.isSuccess) {
      if (mounted && result.errorMessage != null) {
        AppFeedback.error(context, result.errorMessage!);
      }
      return;
    }

    _lastAnimatedPoint = result.initialPoint;
    if (result.initialPoint != null) {
      _mapController?.animateCamera(
        CameraUpdate.newLatLngZoom(
          AppMapStyle.toGoogleLatLng(result.initialPoint!),
          16.5,
        ),
      );
    }
    HapticFeedback.lightImpact();
  }

  Future<void> _stopAndSave() async {
    HapticFeedback.mediumImpact();
    final result = await _viewModel.stopAndBuildResult();
    if (!mounted) return;
    Navigator.pop(context, result.toMap());
  }

  String _formatDistance() {
    if (_totalDistanceMeters > 999) {
      return '${(_totalDistanceMeters / 1000).toStringAsFixed(2)} km';
    }
    return '${_totalDistanceMeters.toStringAsFixed(0)} m';
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
      backgroundColor: AppTheme.surfacePanelSoft,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: AppTheme.transparent,
        elevation: 0,
        leading: const _CloseTrackingButton(),
      ),
      body: Stack(
        children: [
          _TrackingMap(
            onMapCreated: (controller) => _mapController = controller,
            routePoints: _routePoints,
            isLightMode: widget.isLightMode,
          ),
          _TrackingControlPanel(
            isTracking: _isTracking,
            isLightMode: widget.isLightMode,
            distanceLabel: _formatDistance(),
            timeLabel: _formatTime(_elapsedSeconds),
            speedLabel: '${_calculateSpeed()} km/h',
            onStartTracking: _startTracking,
            onStopAndSave: _stopAndSave,
          ),
        ],
      ),
    );
  }
}
