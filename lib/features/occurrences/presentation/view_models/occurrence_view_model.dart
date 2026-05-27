import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import 'package:canil_gcm/core/services/audit_service.dart';
import 'package:canil_gcm/core/services/pdf_generator/occurrence_pdf_generator.dart';
import 'package:canil_gcm/features/dogs/domain/dog.dart';
import 'package:canil_gcm/features/occurrences/data/occurrence_event_repository.dart';
import 'package:canil_gcm/features/occurrences/data/occurrence_repository.dart';
import 'package:canil_gcm/features/occurrences/domain/occurrence.dart';
import 'package:canil_gcm/features/occurrences/domain/occurrence_event.dart';
import 'package:canil_gcm/features/occurrences/domain/occurrence_event_category.dart';
import 'package:canil_gcm/features/occurrences/domain/occurrence_nature.dart';
import 'package:canil_gcm/features/occurrences/domain/occurrence_result.dart';
import 'package:canil_gcm/features/occurrences/domain/occurrence_status.dart';

class OccurrenceViewModel extends ChangeNotifier {
  final OccurrenceRepository _repository;
  final OccurrenceEventRepository _eventRepository;

  OccurrenceViewModel({
    required OccurrenceRepository repository,
    required OccurrenceEventRepository eventRepository,
  }) : _repository = repository,
       _eventRepository = eventRepository;

  // ─── Estado ─────────────────────────────────────────────────────────

  List<Occurrence> _occurrences = [];
  Occurrence? _openOccurrence;
  List<OccurrenceEvent> _events = [];
  List<OccurrenceNature> _natures = OccurrenceNatureSeed.items;
  bool _isLoading = false;
  String? _error;

  StreamSubscription<List<Occurrence>>? _occurrencesSub;
  StreamSubscription<Occurrence?>? _openSub;
  StreamSubscription<List<OccurrenceEvent>>? _eventsSub;

  // ─── Getters ────────────────────────────────────────────────────────

  List<Occurrence> get occurrences => _occurrences;
  Occurrence? get openOccurrence => _openOccurrence;
  bool get hasOpen => _openOccurrence != null;
  bool get isWatchingOpen => _openSub != null;
  List<OccurrenceEvent> get events => _events;
  List<OccurrenceNature> get natures => _natures;
  bool get isLoading => _isLoading;
  String? get error => _error;

  // ─── Carregamento ───────────────────────────────────────────────────

  void watchByDog(String dogId) {
    _occurrencesSub?.cancel();
    _occurrencesSub = _repository
        .watchByDog(dogId)
        .listen(
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
    _openSub = _repository
        .watchOpen(dogId)
        .listen(
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
    _eventsSub = _eventRepository
        .watchByOccurrence(occurrenceId)
        .listen(
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

  Future<List<OccurrenceNature>> fetchNatures() async {
    try {
      final natures = await _repository.getOccurrenceNatures();
      _natures = natures.isNotEmpty ? natures : OccurrenceNatureSeed.items;
      notifyListeners();
      return _natures;
    } catch (e) {
      debugPrint('[OccurrenceViewModel] Erro ao carregar naturezas: $e');
      _natures = OccurrenceNatureSeed.items;
      notifyListeners();
      return _natures;
    }
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
    DateTime? startedAt,
  }) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final now = DateTime.now();
      final resolvedStartedAt = startedAt ?? now;
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
        startedAt: resolvedStartedAt,
        createdAt: now,
        updatedAt: now,
        status: OccurrenceStatus.inProgress,
        initialObservation: initialObservation,
      );

      final created = await _repository.create(occurrence);
      _openOccurrence = created;
      notifyListeners();

      await _createInitialArrivalEvent(
        occurrenceId: created.id,
        startedAt: resolvedStartedAt,
        locationAddress: locationAddress,
        gpsLat: gpsLat,
        gpsLng: gpsLng,
      );

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

  // ─── Evento Inicial ─────────────────────────────────────────────────

  Future<void> _createInitialArrivalEvent({
    required String occurrenceId,
    required DateTime startedAt,
    String? locationAddress,
    double? gpsLat,
    double? gpsLng,
  }) async {
    try {
      final parts = <String>['Binômio em local'];
      if (gpsLat != null && gpsLng != null) {
        parts.add('GPS capturado');
      }
      parts.add('Aguardando próxima ação');

      final entry = AuditService.buildInlineEntry(action: 'created');
      entry['automatic'] = true;

      final event = OccurrenceEvent(
        id: const Uuid().v4(),
        occurrenceId: occurrenceId,
        category: OccurrenceEventCategory.opening,
        timestamp: startedAt,
        title: 'Registro de ocorrência aberto',
        description: parts.join(' · '),
        gpsLat: gpsLat,
        gpsLng: gpsLng,
        createdAt: startedAt,
        updatedAt: startedAt,
        auditTrail: [entry],
      );

      await _eventRepository.create(event);
    } catch (e) {
      debugPrint('[OccurrenceVM] Falha ao criar evento inicial: $e');
    }
  }

  // ─── Atualização ───────────────────────────────────────────────────

  Future<void> updateOccurrence(String id, Map<String, dynamic> updates) async {
    try {
      await _repository.update(id, updates);
    } catch (e) {
      _error = 'Erro ao atualizar ocorrência: $e';
      notifyListeners();
    }
  }

  /// Salva draft de finalização de forma leve (sem ler o documento inteiro).
  Future<void> saveDraft(String id, Map<String, dynamic> draft) async {
    try {
      await _repository.saveDraft(id, draft);
    } catch (e) {
      debugPrint('[OccurrenceVM] Erro ao salvar draft: $e');
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
    // Proteção client-side contra dupla finalização
    if (_isLoading) return;
    if (_openOccurrence != null && _openOccurrence!.status.isClosed) {
      _error = 'Ocorrência já finalizada.';
      notifyListeners();
      return;
    }

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
      // Cancelar o stream para evitar que re-emita o valor antigo
      _openSub?.cancel();
      _openSub = null;
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

  Future<void> updateDurationSoFar(String id, int seconds) async {
    try {
      await _repository.update(id, {'duration_so_far': seconds});
    } catch (_) {}
  }

  void clearError() {
    _error = null;
    notifyListeners();
  }

  /// Busca uma ocorrência por ID diretamente do Firestore.
  Future<Occurrence?> getById(String id) async {
    return _repository.getById(id);
  }

  Future<Occurrence?> findOpen(String dogId) async {
    return _repository.findOpen(dogId);
  }

  Future<List<OccurrenceEvent>> getEvents(String occurrenceId) async {
    return _eventRepository.listByOccurrence(occurrenceId);
  }

  // ─── PDF ────────────────────────────────────────────────────────────

  /// Gera o PDF institucional da ocorrência e retorna os bytes.
  Future<Uint8List> generatePdf({
    required Occurrence occurrence,
    required List<OccurrenceEvent> events,
    required Dog dog,
    required String handlerName,
    required String handlerRa,
  }) async {
    final generator = OccurrencePdfGenerator();
    return generator.generate(
      occurrence: occurrence,
      events: events,
      dog: dog,
      handlerName: handlerName,
      handlerRa: handlerRa,
    );
  }

  Future<void> recordPdfAccess({
    required String occurrenceId,
    required String action,
    String? pdfUrl,
  }) {
    return _repository.recordPdfAccess(
      id: occurrenceId,
      action: action,
      pdfUrl: pdfUrl,
    );
  }

  @override
  void dispose() {
    _occurrencesSub?.cancel();
    _openSub?.cancel();
    _eventsSub?.cancel();
    super.dispose();
  }
}
