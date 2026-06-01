import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

import 'location_tracking_service.dart';

/// Resultado de uma sessão de rastreamento GPS.
class GpsTrackResult {
  final List<GpsTrackPoint> points;
  final double distanceMeters;
  final int durationSeconds;
  final DateTime startedAt;
  final DateTime endedAt;

  const GpsTrackResult({
    required this.points,
    required this.distanceMeters,
    required this.durationSeconds,
    required this.startedAt,
    required this.endedAt,
  });

  double get avgSpeedKmh {
    if (durationSeconds <= 0) return 0;
    return (distanceMeters / 1000) / (durationSeconds / 3600);
  }

  int get avgPaceSecondsPerKm {
    if (distanceMeters <= 0) return 0;
    return (durationSeconds / (distanceMeters / 1000)).round();
  }

  String get avgPaceFormatted {
    final pace = avgPaceSecondsPerKm;
    final min = pace ~/ 60;
    final sec = pace % 60;
    return "$min'${sec.toString().padLeft(2, '0')}\"";
  }

  List<LatLng> get polyline => points.map((p) => LatLng(p.lat, p.lng)).toList();

  Map<String, dynamic> toJson() {
    return {
      'points': points.map((p) => p.toJson()).toList(),
      'distance_m': distanceMeters.round(),
      'duration_s': durationSeconds,
      'avg_pace_s_per_km': avgPaceSecondsPerKm,
      'avg_speed_kmh': double.parse(avgSpeedKmh.toStringAsFixed(1)),
      'started_at': startedAt.toIso8601String(),
      'ended_at': endedAt.toIso8601String(),
    };
  }
}

/// Um ponto capturado pelo GPS.
class GpsTrackPoint {
  final double lat;
  final double lng;
  final DateTime timestamp;
  final double accuracy;

  const GpsTrackPoint({
    required this.lat,
    required this.lng,
    required this.timestamp,
    required this.accuracy,
  });

  LatLng get latLng => LatLng(lat, lng);

  Map<String, dynamic> toJson() => {
    'lat': double.parse(lat.toStringAsFixed(6)),
    'lng': double.parse(lng.toStringAsFixed(6)),
    'ts': timestamp.millisecondsSinceEpoch,
    'acc': accuracy.round(),
  };

  factory GpsTrackPoint.fromPosition(Position p) => GpsTrackPoint(
    lat: p.latitude,
    lng: p.longitude,
    timestamp: p.timestamp,
    accuracy: p.accuracy,
  );
}

/// Estados do rastreamento.
enum GpsTrackingState { idle, preparing, tracking, paused, finished }

/// Serviço de rastreamento GPS reutilizável.
///
/// Captura pontos, filtra ruído (precisão, saltos, deriva parado),
/// calcula métricas em tempo real, suporta pausa/retomar.
///
/// Singleton: a instância persiste enquanto o rastreamento está ativo,
/// permitindo sair da tela e voltar sem perder a sessão.
class GpsTrackingService extends ChangeNotifier {
  static GpsTrackingService? _activeInstance;

  /// Retorna a instância ativa (se houver rastreamento em andamento).
  static GpsTrackingService? get activeInstance => _activeInstance;

  /// Cria ou retorna a instância ativa.
  factory GpsTrackingService() {
    if (_activeInstance != null && _activeInstance!.isActive) {
      return _activeInstance!;
    }
    _activeInstance = GpsTrackingService._();
    return _activeInstance!;
  }

  GpsTrackingService._();

  final LocationTrackingService _locationService = LocationTrackingService();

  // ─── Configuração de filtro ──────────────────────────────────────
  static const double _maxAccuracy = 25.0; // metros
  static const double _maxSpeedMs = 8.5; // ~30 km/h (corrida rápida)
  static const double _minMovementMeters = 3.0; // ignora deriva < 3m
  static const double _stationarySpeedMs = 0.3; // < 1 km/h = parado

  // ─── Estado ──────────────────────────────────────────────────────
  GpsTrackingState _state = GpsTrackingState.idle;
  final List<GpsTrackPoint> _points = [];
  StreamSubscription<Position>? _positionSub;
  Timer? _timer;
  Position? _lastAccepted;

  double _distanceMeters = 0.0;
  int _elapsedSeconds = 0;
  DateTime? _startedAt;
  DateTime? _endedAt;
  String _activityLabel = '';

  // ─── Getters públicos ────────────────────────────────────────────
  GpsTrackingState get state => _state;
  bool get isTracking => _state == GpsTrackingState.tracking;
  bool get isPaused => _state == GpsTrackingState.paused;
  bool get isActive =>
      _state == GpsTrackingState.tracking || _state == GpsTrackingState.paused;
  bool get isFinished => _state == GpsTrackingState.finished;

  double get distanceMeters => _distanceMeters;
  double get distanceKm => _distanceMeters / 1000;
  int get elapsedSeconds => _elapsedSeconds;
  String get activityLabel => _activityLabel;
  DateTime? get startedAt => _startedAt;

  List<GpsTrackPoint> get points => List.unmodifiable(_points);
  List<LatLng> get polyline =>
      _points.map((p) => LatLng(p.lat, p.lng)).toList();

  LatLng? get currentPosition =>
      _points.isNotEmpty ? _points.last.latLng : null;

  LatLng? get startPosition => _points.isNotEmpty ? _points.first.latLng : null;

  double get avgSpeedKmh {
    if (_elapsedSeconds <= 0) return 0;
    return (_distanceMeters / 1000) / (_elapsedSeconds / 3600);
  }

  int get avgPaceSecondsPerKm {
    if (_distanceMeters <= 0) return 0;
    return (_elapsedSeconds / (_distanceMeters / 1000)).round();
  }

  String get avgPaceFormatted {
    final pace = avgPaceSecondsPerKm;
    final min = pace ~/ 60;
    final sec = pace % 60;
    return "$min'${sec.toString().padLeft(2, '0')}\"";
  }

  String get elapsedFormatted {
    final h = _elapsedSeconds ~/ 3600;
    final m = (_elapsedSeconds % 3600) ~/ 60;
    final s = _elapsedSeconds % 60;
    if (h > 0) return '${h}h${m.toString().padLeft(2, '0')}';
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  // ─── Ações ───────────────────────────────────────────────────────

  /// Inicia o rastreamento. Retorna erro ou null se OK.
  Future<String?> start({required String activityLabel}) async {
    if (isActive) return null; // já está ativo

    _state = GpsTrackingState.preparing;
    _activityLabel = activityLabel;
    notifyListeners();

    final permError = await _locationService.validatePermissions();
    if (permError != null) {
      _state = GpsTrackingState.idle;
      notifyListeners();
      return permError;
    }

    final position = await _locationService.getCurrentPosition(
      skipPermissionCheck: true,
    );
    if (position == null) {
      _state = GpsTrackingState.idle;
      notifyListeners();
      return 'Não foi possível obter a localização atual.';
    }

    _reset();
    _startedAt = DateTime.now();
    _lastAccepted = position;
    _points.add(GpsTrackPoint.fromPosition(position));

    _state = GpsTrackingState.tracking;
    _startTimer();
    _startListening();
    notifyListeners();
    return null;
  }

  /// Pausa o rastreamento (para de somar tempo/distância, mas mantém o stream).
  void pause() {
    if (_state != GpsTrackingState.tracking) return;
    _state = GpsTrackingState.paused;
    _timer?.cancel();
    _timer = null;
    notifyListeners();
  }

  /// Retoma o rastreamento após pausa.
  void resume() {
    if (_state != GpsTrackingState.paused) return;
    _state = GpsTrackingState.tracking;
    _startTimer();
    notifyListeners();
  }

  /// Finaliza o rastreamento e retorna o resultado.
  Future<GpsTrackResult> finish() async {
    _timer?.cancel();
    _timer = null;
    await _positionSub?.cancel();
    _positionSub = null;
    _endedAt = DateTime.now();
    _state = GpsTrackingState.finished;
    _activeInstance = null;
    notifyListeners();

    return GpsTrackResult(
      points: List.from(_points),
      distanceMeters: _distanceMeters,
      durationSeconds: _elapsedSeconds,
      startedAt: _startedAt ?? DateTime.now(),
      endedAt: _endedAt!,
    );
  }

  /// Descarta a sessão sem salvar.
  void discard() {
    _timer?.cancel();
    _positionSub?.cancel();
    _reset();
    _state = GpsTrackingState.idle;
    _activeInstance = null;
    notifyListeners();
  }

  // ─── Internos ────────────────────────────────────────────────────

  void _reset() {
    _points.clear();
    _distanceMeters = 0.0;
    _elapsedSeconds = 0;
    _startedAt = null;
    _endedAt = null;
    _lastAccepted = null;
  }

  void _startTimer() {
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      _elapsedSeconds++;
      notifyListeners();
    });
  }

  void _startListening() {
    _positionSub = _locationService.getPositionStream().listen(_onPosition);
  }

  void _onPosition(Position position) {
    // Não processar se pausado
    if (_state != GpsTrackingState.tracking) return;

    // Filtro 1: precisão ruim
    if (position.accuracy > _maxAccuracy) return;

    // Filtro 2: sem posição anterior aceita
    if (_lastAccepted == null) {
      _lastAccepted = position;
      _points.add(GpsTrackPoint.fromPosition(position));
      notifyListeners();
      return;
    }

    final prev = _lastAccepted!;
    final distance = Geolocator.distanceBetween(
      prev.latitude,
      prev.longitude,
      position.latitude,
      position.longitude,
    );

    // Filtro 3: movimento mínimo (ignora deriva parado)
    if (distance < _minMovementMeters) return;

    // Filtro 4: velocidade impossível (salto de GPS)
    final timeDiff =
        position.timestamp.difference(prev.timestamp).inMilliseconds.abs() /
        1000;
    if (timeDiff <= 0) return;
    final speed = distance / timeDiff;
    if (speed > _maxSpeedMs) return;

    // Filtro 5: velocidade muito baixa = praticamente parado (deriva)
    if (speed < _stationarySpeedMs && distance < 5.0) return;

    // Ponto aceito — somar distância e registrar
    _distanceMeters += distance;
    _lastAccepted = position;
    _points.add(GpsTrackPoint.fromPosition(position));
    notifyListeners();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _positionSub?.cancel();
    super.dispose();
  }
}
