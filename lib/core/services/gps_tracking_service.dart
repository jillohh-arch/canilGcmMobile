import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:path_provider/path_provider.dart';

import 'location_tracking_service.dart';

/// Resultado de uma sessão de rastreamento GPS.
class GpsTrackResult {
  final List<GpsTrackPoint> points;
  final List<GpsFieldEvent> events;
  final double distanceMeters;
  final int durationSeconds;
  final DateTime startedAt;
  final DateTime endedAt;
  final GpsTrackingSessionConfig? sessionConfig;
  final String? result;
  final String? observation;
  final String? finishReason;
  final String? localDraftId;
  final String? localDraftPath;

  const GpsTrackResult({
    required this.points,
    this.events = const [],
    required this.distanceMeters,
    required this.durationSeconds,
    required this.startedAt,
    required this.endedAt,
    this.sessionConfig,
    this.result,
    this.observation,
    this.finishReason,
    this.localDraftId,
    this.localDraftPath,
  });

  static Future<List<GpsTrackResult>> loadLocalDrafts({
    String? modality,
    String? phase,
    String? dogId,
  }) async {
    try {
      final baseDir = await getApplicationSupportDirectory();
      final draftsDir = Directory(
        '${baseDir.path}${Platform.pathSeparator}gps_track_drafts',
      );
      if (!await draftsDir.exists()) return [];

      final drafts = <GpsTrackResult>[];
      await for (final entity in draftsDir.list()) {
        if (entity is! File || !entity.path.endsWith('.json')) continue;
        try {
          final payload =
              jsonDecode(await entity.readAsString()) as Map<String, dynamic>;
          final draft = GpsTrackResult.fromJson(
            payload,
            localDraftPath: entity.path,
          );
          final config = draft.sessionConfig;
          if (modality != null && config?.modality != modality) continue;
          if (phase != null && config?.phase != phase) continue;
          if (dogId != null && config?.dogId != dogId) continue;
          drafts.add(draft);
        } catch (error) {
          debugPrint('[GpsTrackingService] Rascunho GPS invalido: $error');
        }
      }
      drafts.sort((a, b) => a.endedAt.compareTo(b.endedAt));
      return drafts;
    } catch (error) {
      debugPrint('[GpsTrackingService] Erro ao carregar rascunhos GPS: $error');
      return [];
    }
  }

  factory GpsTrackResult.fromJson(
    Map<String, dynamic> json, {
    String? localDraftPath,
  }) {
    final rawPoints = json['points'] ?? json['path'];
    final points = rawPoints is List
        ? rawPoints
              .whereType<Map>()
              .map(
                (point) =>
                    GpsTrackPoint.fromJson(Map<String, dynamic>.from(point)),
              )
              .toList()
        : <GpsTrackPoint>[];
    final rawEvents = json['events'];
    final events = rawEvents is List
        ? rawEvents
              .whereType<Map>()
              .map(
                (event) =>
                    GpsFieldEvent.fromJson(Map<String, dynamic>.from(event)),
              )
              .toList()
        : <GpsFieldEvent>[];
    final configJson = json['session_config'];
    final startedAt = _readDate(json['started_at']) ?? DateTime.now();
    final endedAt =
        _readDate(json['ended_at']) ??
        _readDate(json['updated_at']) ??
        startedAt;

    return GpsTrackResult(
      points: points,
      events: events,
      distanceMeters: _readDouble(json['distance_m']),
      durationSeconds: _readInt(json['duration_s']),
      startedAt: startedAt,
      endedAt: endedAt,
      sessionConfig: configJson is Map
          ? GpsTrackingSessionConfig.fromJson(
              Map<String, dynamic>.from(configJson),
            )
          : null,
      result: json['result']?.toString(),
      observation: json['observation']?.toString(),
      finishReason: json['finish_reason']?.toString(),
      localDraftId: json['draft_id']?.toString(),
      localDraftPath: localDraftPath,
    );
  }

  static DateTime? _readDate(dynamic value) {
    if (value is String && value.isNotEmpty) {
      return DateTime.tryParse(value);
    }
    if (value is num) {
      return DateTime.fromMillisecondsSinceEpoch(value.toInt());
    }
    return null;
  }

  static double _readDouble(dynamic value) {
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '') ?? 0;
  }

  static int _readInt(dynamic value) {
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

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
      'path': points.map((p) => p.toJson()).toList(),
      'events': events.map((event) => event.toJson()).toList(),
      'distance_m': distanceMeters.round(),
      'duration_s': durationSeconds,
      'avg_pace_s_per_km': avgPaceSecondsPerKm,
      'avg_speed_kmh': double.parse(avgSpeedKmh.toStringAsFixed(1)),
      'started_at': startedAt.toIso8601String(),
      'ended_at': endedAt.toIso8601String(),
      'finish_reason': finishReason ?? 'manual',
      'offline_synced': true,
      if (sessionConfig != null) 'session_config': sessionConfig!.toJson(),
      if (result != null) 'result': result,
      if (observation != null && observation!.trim().isNotEmpty)
        'observation': observation!.trim(),
    };
  }

  GpsTrackResult copyWith({
    List<GpsTrackPoint>? points,
    List<GpsFieldEvent>? events,
    double? distanceMeters,
    int? durationSeconds,
    DateTime? startedAt,
    DateTime? endedAt,
    GpsTrackingSessionConfig? sessionConfig,
    String? result,
    String? observation,
    String? finishReason,
    String? localDraftId,
    String? localDraftPath,
  }) {
    return GpsTrackResult(
      points: points ?? this.points,
      events: events ?? this.events,
      distanceMeters: distanceMeters ?? this.distanceMeters,
      durationSeconds: durationSeconds ?? this.durationSeconds,
      startedAt: startedAt ?? this.startedAt,
      endedAt: endedAt ?? this.endedAt,
      sessionConfig: sessionConfig ?? this.sessionConfig,
      result: result ?? this.result,
      observation: observation ?? this.observation,
      finishReason: finishReason ?? this.finishReason,
      localDraftId: localDraftId ?? this.localDraftId,
      localDraftPath: localDraftPath ?? this.localDraftPath,
    );
  }

  Future<void> persistLocalDraft() async {
    final path = localDraftPath;
    if (path == null || path.isEmpty) return;
    try {
      final payload = {
        'draft_id': localDraftId,
        ...toJson(),
        'offline_synced': false,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      };
      await File(path).writeAsString(jsonEncode(payload), flush: true);
    } catch (error) {
      debugPrint('[GpsTrackingService] Erro ao atualizar rascunho GPS: $error');
    }
  }

  Future<void> deleteLocalDraft() async {
    final path = localDraftPath;
    if (path == null || path.isEmpty) return;
    try {
      final file = File(path);
      if (await file.exists()) {
        await file.delete();
      }
    } catch (error) {
      debugPrint('[GpsTrackingService] Erro ao remover rascunho GPS: $error');
    }
  }
}

class GpsTrackingSessionConfig {
  final String modality;
  final String phase;
  final String? dogId;
  final String? dogName;
  final String? moduleId;
  final String? moduleName;
  final String? milestoneId;
  final String? milestoneLabel;
  final String conductor;
  final String figurante;
  final String odorObject;
  final String ambiente;

  const GpsTrackingSessionConfig({
    required this.modality,
    required this.phase,
    this.dogId,
    this.dogName,
    this.moduleId,
    this.moduleName,
    this.milestoneId,
    this.milestoneLabel,
    required this.conductor,
    required this.figurante,
    required this.odorObject,
    required this.ambiente,
  });

  factory GpsTrackingSessionConfig.fromJson(Map<String, dynamic> json) {
    return GpsTrackingSessionConfig(
      modality: json['modality']?.toString() ?? '',
      phase: json['phase']?.toString() ?? 'formation',
      dogId: json['dog_id']?.toString() ?? json['dogId']?.toString(),
      dogName: json['dog_name']?.toString() ?? json['dogName']?.toString(),
      moduleId: json['module_id']?.toString() ?? json['moduleId']?.toString(),
      moduleName:
          json['module_name']?.toString() ?? json['moduleName']?.toString(),
      milestoneId:
          json['milestone_id']?.toString() ?? json['milestoneId']?.toString(),
      milestoneLabel:
          json['milestone_label']?.toString() ??
          json['milestoneLabel']?.toString(),
      conductor: json['conductor']?.toString() ?? '',
      figurante: json['figurante']?.toString() ?? '',
      odorObject:
          json['odor_object']?.toString() ??
          json['odorObject']?.toString() ??
          '',
      ambiente: json['ambiente']?.toString() ?? '',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'modality': modality,
      'phase': phase,
      if (dogId != null) 'dog_id': dogId,
      if (dogName != null) 'dog_name': dogName,
      if (moduleId != null) 'module_id': moduleId,
      if (moduleName != null) 'module_name': moduleName,
      if (milestoneId != null) 'milestone_id': milestoneId,
      if (milestoneLabel != null) 'milestone_label': milestoneLabel,
      'conductor': conductor,
      'figurante': figurante,
      'odor_object': odorObject,
      'ambiente': ambiente,
    };
  }
}

enum GpsFieldEventType { caoIndicou, checagem, perdeuRastro, alvoEncontrado }

extension GpsFieldEventTypeX on GpsFieldEventType {
  String get key => switch (this) {
    GpsFieldEventType.caoIndicou => 'cao_indicou',
    GpsFieldEventType.checagem => 'checagem',
    GpsFieldEventType.perdeuRastro => 'perdeu_rastro',
    GpsFieldEventType.alvoEncontrado => 'alvo_encontrado',
  };

  String get label => switch (this) {
    GpsFieldEventType.caoIndicou => 'Cão indicou',
    GpsFieldEventType.checagem => 'Checagem',
    GpsFieldEventType.perdeuRastro => 'Perdeu rastro',
    GpsFieldEventType.alvoEncontrado => 'Alvo encontrado',
  };
}

class GpsFieldEvent {
  final String id;
  final GpsFieldEventType type;
  final DateTime timestamp;
  final GpsTrackPoint? point;

  const GpsFieldEvent({
    required this.id,
    required this.type,
    required this.timestamp,
    this.point,
  });

  factory GpsFieldEvent.fromJson(Map<String, dynamic> json) {
    final typeKey = json['type']?.toString() ?? '';
    final pointJson = json['position'];
    return GpsFieldEvent(
      id: json['id']?.toString() ?? 'event_${json['ts'] ?? ''}',
      type: GpsFieldEventType.values.firstWhere(
        (type) => type.key == typeKey,
        orElse: () => GpsFieldEventType.checagem,
      ),
      timestamp:
          GpsTrackResult._readDate(json['timestamp']) ??
          GpsTrackResult._readDate(json['ts']) ??
          DateTime.now(),
      point: pointJson is Map
          ? GpsTrackPoint.fromJson(Map<String, dynamic>.from(pointJson))
          : (json['lat'] != null && json['lng'] != null
                ? GpsTrackPoint.fromJson(json)
                : null),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'type': type.key,
      'label': type.label,
      'timestamp': timestamp.toIso8601String(),
      'ts': timestamp.millisecondsSinceEpoch,
      if (point != null) ...{
        'position': point!.toJson(),
        'lat': point!.lat,
        'lng': point!.lng,
        'accuracy': point!.accuracy,
      },
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

  factory GpsTrackPoint.fromJson(Map<dynamic, dynamic> json) => GpsTrackPoint(
    lat: GpsTrackResult._readDouble(json['lat']),
    lng: GpsTrackResult._readDouble(json['lng']),
    timestamp:
        GpsTrackResult._readDate(json['timestamp']) ??
        GpsTrackResult._readDate(json['ts']) ??
        DateTime.now(),
    accuracy: GpsTrackResult._readDouble(json['accuracy'] ?? json['acc']),
  );

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
  final List<GpsFieldEvent> _events = [];
  StreamSubscription<Position>? _positionSub;
  Timer? _timer;
  Position? _lastAccepted;

  double _distanceMeters = 0.0;
  int _elapsedSeconds = 0;
  DateTime? _startedAt;
  DateTime? _endedAt;
  String _activityLabel = '';
  GpsTrackingSessionConfig? _sessionConfig;
  String? _finishReason;
  String? _localDraftId;
  File? _localDraftFile;

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
  GpsTrackingSessionConfig? get sessionConfig => _sessionConfig;

  List<GpsTrackPoint> get points => List.unmodifiable(_points);
  List<GpsFieldEvent> get events => List.unmodifiable(_events);
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
  Future<String?> start({
    required String activityLabel,
    GpsTrackingSessionConfig? sessionConfig,
  }) async {
    if (isActive) return null; // já está ativo

    _state = GpsTrackingState.preparing;
    _activityLabel = activityLabel;
    _sessionConfig = sessionConfig;
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
    _sessionConfig = sessionConfig;
    _startedAt = DateTime.now();
    await _prepareLocalDraft();
    _lastAccepted = position;
    _points.add(GpsTrackPoint.fromPosition(position));
    await _persistLocalDraft();

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

  void addEvent(GpsFieldEventType type) {
    if (!isActive && !isFinished) return;
    final timestamp = DateTime.now();
    final point = _points.isNotEmpty ? _points.last : null;
    _events.add(
      GpsFieldEvent(
        id: '${type.key}_${timestamp.microsecondsSinceEpoch}',
        type: type,
        timestamp: timestamp,
        point: point,
      ),
    );
    unawaited(_persistLocalDraft());
    notifyListeners();
  }

  /// Finaliza o rastreamento e retorna o resultado.
  Future<GpsTrackResult> finish({String finishReason = 'manual'}) async {
    _timer?.cancel();
    _timer = null;
    await _positionSub?.cancel();
    _positionSub = null;
    _endedAt = DateTime.now();
    _finishReason = finishReason;
    _state = GpsTrackingState.finished;
    await _persistLocalDraft();
    _activeInstance = null;
    notifyListeners();

    return GpsTrackResult(
      points: List.from(_points),
      events: List.from(_events),
      distanceMeters: _distanceMeters,
      durationSeconds: _elapsedSeconds,
      startedAt: _startedAt ?? DateTime.now(),
      endedAt: _endedAt!,
      sessionConfig: _sessionConfig,
      finishReason: _finishReason,
      localDraftId: _localDraftId,
      localDraftPath: _localDraftFile?.path,
    );
  }

  /// Descarta a sessão sem salvar.
  void discard() {
    _timer?.cancel();
    _positionSub?.cancel();
    unawaited(_deleteCurrentDraft());
    _reset();
    _state = GpsTrackingState.idle;
    _activeInstance = null;
    notifyListeners();
  }

  // ─── Internos ────────────────────────────────────────────────────

  Future<void> _prepareLocalDraft() async {
    try {
      final baseDir = await getApplicationSupportDirectory();
      final draftsDir = Directory(
        '${baseDir.path}${Platform.pathSeparator}gps_track_drafts',
      );
      if (!await draftsDir.exists()) {
        await draftsDir.create(recursive: true);
      }
      final stamp = DateTime.now().toUtc().toIso8601String().replaceAll(
        RegExp(r'[^0-9]'),
        '',
      );
      _localDraftId = 'gps_$stamp';
      _localDraftFile = File(
        '${draftsDir.path}${Platform.pathSeparator}$_localDraftId.json',
      );
    } catch (error) {
      debugPrint('[GpsTrackingService] Erro ao preparar rascunho GPS: $error');
      _localDraftId = null;
      _localDraftFile = null;
    }
  }

  Future<void> _persistLocalDraft() async {
    final file = _localDraftFile;
    final draftId = _localDraftId;
    if (file == null || draftId == null) return;

    final payload = {
      'draft_id': draftId,
      'activity_label': _activityLabel,
      'state': _state.name,
      if (_sessionConfig != null) 'session_config': _sessionConfig!.toJson(),
      'started_at': _startedAt?.toIso8601String(),
      'ended_at': _endedAt?.toIso8601String(),
      'distance_m': _distanceMeters.round(),
      'duration_s': _elapsedSeconds,
      'points': _points.map((point) => point.toJson()).toList(),
      'path': _points.map((point) => point.toJson()).toList(),
      'events': _events.map((event) => event.toJson()).toList(),
      'finish_reason': _finishReason,
      'offline_synced': false,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    };

    try {
      await file.writeAsString(jsonEncode(payload), flush: true);
    } catch (error) {
      debugPrint('[GpsTrackingService] Erro ao persistir rascunho GPS: $error');
    }
  }

  Future<void> _deleteCurrentDraft() async {
    final file = _localDraftFile;
    if (file == null) return;
    try {
      if (await file.exists()) {
        await file.delete();
      }
    } catch (error) {
      debugPrint('[GpsTrackingService] Erro ao descartar rascunho GPS: $error');
    }
  }

  void _reset() {
    _points.clear();
    _distanceMeters = 0.0;
    _elapsedSeconds = 0;
    _startedAt = null;
    _endedAt = null;
    _lastAccepted = null;
    _events.clear();
    _sessionConfig = null;
    _finishReason = null;
    _localDraftId = null;
    _localDraftFile = null;
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
      unawaited(_persistLocalDraft());
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
    unawaited(_persistLocalDraft());
    notifyListeners();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _positionSub?.cancel();
    super.dispose();
  }
}
