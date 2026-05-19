import 'dart:async';

import 'package:flutter/foundation.dart';

import 'package:canil_gcm/features/occurrences/data/occurrence_event_repository.dart';
import 'package:canil_gcm/features/occurrences/data/occurrence_repository.dart';
import 'package:canil_gcm/features/occurrences/domain/occurrence.dart';
import 'package:canil_gcm/features/occurrences/domain/occurrence_event.dart';
import 'package:canil_gcm/features/occurrences/domain/occurrence_result.dart';
import 'package:canil_gcm/features/occurrences/domain/occurrence_status.dart';

class OccurrenceViewModel extends ChangeNotifier {
  final OccurrenceRepository _repository;
  final OccurrenceEventRepository _eventRepository;

  OccurrenceViewModel({
    required OccurrenceRepository repository,
    required OccurrenceEventRepository eventRepository,
  })  : _repository = repository,
        _eventRepository = eventRepository;

  // ─── Estado ─────────────────────────────────────────────────────────

  List<Occurrence> _occurrences = [];
  Occurrence? _openOccurrence;
  List<OccurrenceEvent> _events = [];
  bool _isLoading = false;
  String? _error;

  StreamSubscription<List<Occurrence>>? _occurrencesSub;
  StreamSubscription<Occurrence?>? _openSub;
  StreamSubscription<List<OccurrenceEvent>>? _eventsSub;

  // ─── Getters ────────────────────────────────────────────────────────

  List<Occurrence> get occurrences => _occurrences;
  Occurrence? get openOccurrence => _openOccurrence;
  bool get hasOpen => _openOccurrence != null;
  List<OccurrenceEvent> get events => _events;
  bool get isLoading => _isLoading;
  String? get error => _error;

  // ─── Carregamento ───────────────────────────────────────────────────

  void watchByDog(String dogId) {
    _occurrencesSub?.cancel();
    _occurrencesSub = _repository.watchByDog(dogId).listen(
      (list) {
        _occurrences = list;
        notifyListeners();
      },
      onError: (e) {
        _error = 'Erro ao carregar ocorrências: $e';
        notifyListeners();
      },
    );
  }

  void watchOpen(String dogId) {
    _openSub?.cancel();
    _openSub = _repository.watchOpen(dogId).listen(
      (occ) {
        _openOccurrence = occ;
        notifyListeners();
      },
      onError: (e) {
        debugPrint('[OccurrenceViewModel] watchOpen error: $e');
      },
    );
  }

  void watchEvents(String occurrenceId) {
    _eventsSub?.cancel();
    _eventsSub = _eventRepository.watchByOccurrence(occurrenceId).listen(
      (list) {
        _events = list;
        notifyListeners();
      },
      onError: (e, stack) {
        debugPrint('[OccurrenceVM] watchEvents error: $e');
        debugPrint('[OccurrenceVM] stack: $stack');
        _error = 'Erro ao carregar eventos: $e';
        notifyListeners();
      },
    );
  }

  // ─── Criação ────────────────────────────────────────────────────────

  Future<Occurrence> createOccurrence({
    required String id,
    required String shiftId,
    required String dogId,
    required String primaryHandlerId,
    required String typeCode,
    required String typeName,
    String? locationAddress,
    double? gpsLat,
    double? gpsLng,
    double? gpsAccuracy,
    String? initialObservation,
  }) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final now = DateTime.now();
      final occurrence = Occurrence(
        id: id,
        shiftId: shiftId,
        primaryHandlerId: primaryHandlerId,
        dogId: dogId,
        typeCode: typeCode,
        typeName: typeName,
        locationAddress: locationAddress,
        gpsLat: gpsLat,
        gpsLng: gpsLng,
        gpsAccuracy: gpsAccuracy,
        startedAt: now,
        createdAt: now,
        updatedAt: now,
        status: OccurrenceStatus.inProgress,
        initialObservation: initialObservation,
      );

      final created = await _repository.create(occurrence);
      _openOccurrence = created;
      notifyListeners();
      return created;
    } catch (e) {
      _error = 'Erro ao criar ocorrência: $e';
      notifyListeners();
      rethrow;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  // ─── Atualização ───────────────────────────────────────────────────

  Future<void> updateOccurrence(
    String id,
    Map<String, dynamic> updates,
  ) async {
    try {
      await _repository.update(id, updates);
    } catch (e) {
      _error = 'Erro ao atualizar ocorrência: $e';
      notifyListeners();
    }
  }

  // ─── Finalização ───────────────────────────────────────────────────

  Future<void> finalizeOccurrence({
    required String id,
    required String integrityHash,
    required String finalReport,
    required List<OccurrenceResult> results,
    Map<String, dynamic>? details,
  }) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      await _repository.finalize(
        id: id,
        integrityHash: integrityHash,
        finalReport: finalReport,
        results: results,
        details: details,
      );
      _openOccurrence = null;
      notifyListeners();
    } catch (e) {
      _error = 'Erro ao finalizar ocorrência: $e';
      notifyListeners();
      rethrow;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  // ─── Cancelamento ──────────────────────────────────────────────────

  Future<void> cancelOccurrence(String id, String userId, String reason) async {
    try {
      await _repository.softDelete(id, userId, reason);
      _openOccurrence = null;
      notifyListeners();
    } catch (e) {
      _error = 'Erro ao cancelar ocorrência: $e';
      notifyListeners();
    }
  }

  // ─── Eventos ───────────────────────────────────────────────────────

  Future<OccurrenceEvent> addEvent(OccurrenceEvent event) async {
    try {
      return await _eventRepository.create(event);
    } catch (e) {
      _error = 'Erro ao adicionar evento: $e';
      notifyListeners();
      rethrow;
    }
  }

  Future<void> updateEvent(
    String occurrenceId,
    String eventId,
    Map<String, dynamic> updates,
  ) async {
    try {
      await _eventRepository.update(occurrenceId, eventId, updates);
    } catch (e) {
      _error = 'Erro ao atualizar evento: $e';
      notifyListeners();
    }
  }

  Future<void> deleteEvent(
    String occurrenceId,
    String eventId,
    String userId,
    String reason,
  ) async {
    try {
      await _eventRepository.softDelete(occurrenceId, eventId, userId, reason);
    } catch (e) {
      _error = 'Erro ao excluir evento: $e';
      notifyListeners();
    }
  }

  // ─── Utilitários ───────────────────────────────────────────────────

  void clearError() {
    _error = null;
    notifyListeners();
  }

  @override
  void dispose() {
    _occurrencesSub?.cancel();
    _openSub?.cancel();
    _eventsSub?.cancel();
    super.dispose();
  }
}
