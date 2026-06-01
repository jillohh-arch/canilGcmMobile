import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:latlong2/latlong.dart';

import 'package:canil_gcm/core/theme/app_theme.dart';
import 'package:canil_gcm/features/shifts/presentation/viewmodels/live_tracking_viewmodel.dart';

part 'live_tracking_widgets.dart';

class LiveTrackingScreen extends StatefulWidget {
  final bool isLightMode;

  const LiveTrackingScreen({super.key, this.isLightMode = false});

  @override
  State<LiveTrackingScreen> createState() => _LiveTrackingScreenState();
}

class _LiveTrackingScreenState extends State<LiveTrackingScreen> {
  final MapController _mapController = MapController();
  late final LiveTrackingViewModel _viewModel;
  LatLng? _lastAnimatedPoint;

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
    _mapController.dispose();
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
        _mapController.move(latestPoint, _mapController.camera.zoom);
      }
    }
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

    _lastAnimatedPoint = result.initialPoint;
    _mapController.move(result.initialPoint!, 16.5);
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
            mapController: _mapController,
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
