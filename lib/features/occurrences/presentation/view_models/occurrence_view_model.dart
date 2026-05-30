import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import 'package:canil_gcm/core/domain/notification_item.dart';
import 'package:canil_gcm/core/domain/occurrence_team_member.dart';
import 'package:canil_gcm/core/services/audit_service.dart';
import 'package:canil_gcm/core/services/handler_identity_service.dart';
import 'package:canil_gcm/core/services/notification_service.dart';
import 'package:canil_gcm/core/services/pdf_generator/occurrence_pdf_generator.dart';
import 'package:canil_gcm/features/dogs/domain/dog.dart';
import 'package:canil_gcm/features/occurrences/data/occurrence_event_repository.dart';
import 'package:canil_gcm/features/occurrences/data/occurrence_repository.dart';
import 'package:canil_gcm/features/occurrences/data/signature_repository.dart';
import 'package:canil_gcm/features/occurrences/domain/occurrence.dart';
import 'package:canil_gcm/features/occurrences/domain/occurrence_event.dart';
import 'package:canil_gcm/features/occurrences/domain/occurrence_event_category.dart';
import 'package:canil_gcm/features/occurrences/domain/occurrence_nature.dart';
import 'package:canil_gcm/features/occurrences/domain/occurrence_result.dart';
import 'package:canil_gcm/features/occurrences/domain/occurrence_status.dart';

class OccurrenceViewModel extends ChangeNotifier {
  final OccurrenceRepository _repository;
  final OccurrenceEventRepository _eventRepository;
  final SignatureRepository _signatureRepository;

  OccurrenceViewModel({
    required OccurrenceRepository repository,
    required OccurrenceEventRepository eventRepository,
    SignatureRepository? signatureRepository,
  }) : _repository = repository,
       _eventRepository = eventRepository,
       _signatureRepository = signatureRepository ?? SignatureRepository();

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
    String? serviceDogId,
    String? crewId,
    required String primaryHandlerId,
    String? primaryHandlerRa,
    String? vehicleId,
    String? vehicleLabel,
    String? vehiclePrefix,
    String? vehicleModel,
    String? vehicleUnit,
    List<OccurrenceTeamMember>? teamSnapshot,
    int? teamSizeMax,
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
      final titularRa = primaryHandlerRa?.trim();
      final titularTeam = titularRa == null || titularRa.isEmpty
          ? <OccurrenceTeamMember>[]
          : [
              OccurrenceTeamMember(
                handlerId: titularRa,
                authUid: primaryHandlerId.isEmpty ? null : primaryHandlerId,
                handlerEmail: HandlerIdentityService.emailFromRa(titularRa),
                role: TeamRole.titular,
                addedAt: now,
                addedBy: titularRa,
                addedByUid: primaryHandlerId.isEmpty ? null : primaryHandlerId,
              ),
            ];
      final resolvedTeam = teamSnapshot
          ?.where((member) => member.handlerId.isNotEmpty)
          .toList();
      final occurrence = Occurrence(
        id: id,
        shiftId: shiftId,
        primaryHandlerId: primaryHandlerId,
        primaryHandlerRa: titularRa,
        createdBy: {
          if (titularRa != null && titularRa.isNotEmpty) 'ra': titularRa,
          if (primaryHandlerId.isNotEmpty) 'uid': primaryHandlerId,
        },
        dogId: dogId,
        serviceDogId: serviceDogId ?? dogId,
        crewId: crewId,
        vehicleId: vehicleId,
        vehicleLabel: vehicleLabel,
        vehiclePrefix: vehiclePrefix,
        vehicleModel: vehicleModel,
        vehicleUnit: vehicleUnit,
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
        team: resolvedTeam?.isNotEmpty == true ? resolvedTeam! : titularTeam,
        teamSizeMax: teamSizeMax ?? 3,
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

      await _notifyTeamOccurrenceOpened(created);

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

  Future<void> _notifyTeamOccurrenceOpened(Occurrence occurrence) async {
    final notificationService = NotificationService();
    final primaryRa = occurrence.primaryHandlerRa?.trim();
    final recipients = occurrence.team.where((member) {
      final handlerId = member.handlerId.trim();
      return handlerId.isNotEmpty && handlerId != primaryRa;
    });

    for (final member in recipients) {
      try {
        final handlerId = member.handlerId.trim();
        await notificationService.createNotification(
          userId: handlerId,
          type: NotificationType.occurrenceParticipationRequested,
          occurrenceId: occurrence.id,
          occurrenceTitle: occurrence.typeName,
          additionalData: primaryRa,
          notificationId: 'opened_${occurrence.id}_$handlerId',
          deduplicate: true,
          targetScreen: 'occurrence_active',
          actionRequired: true,
        );
      } catch (error) {
        debugPrint(
          '[OccurrenceViewModel] Falha ao notificar integrante ${member.handlerId}: $error',
        );
      }
    }
  }

  Future<void> _createInitialArrivalEvent({
    required String occurrenceId,
    required DateTime startedAt,
    String? locationAddress,
    double? gpsLat,
    double? gpsLng,
  }) async {
    try {
      final hasGps = gpsLat != null && gpsLng != null;
      final address = locationAddress ?? 'não informado';

      final entry = AuditService.buildInlineEntry(action: 'created');
      entry['automatic'] = true;

      final event = OccurrenceEvent(
        id: const Uuid().v4(),
        occurrenceId: occurrenceId,
        category: OccurrenceEventCategory.opening,
        timestamp: startedAt,
        title: 'Início da ocorrência',
        description: 'Ocorrência iniciada no endereço: $address.',
        gpsLat: gpsLat,
        gpsLng: gpsLng,
        placeLabel: locationAddress,
        locationSource: hasGps ? 'gps_atual' : null,
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
    List<String> finalizationPhotos = const [],
    List<String> finalizationPhotoHashes = const [],
    int hashVersion = 2,
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
        finalizationPhotos: finalizationPhotos,
        finalizationPhotoHashes: finalizationPhotoHashes,
        hashVersion: hashVersion,
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

  Future<void> closeForSignatures({
    required String id,
    required String finalReport,
    required List<OccurrenceResult> results,
    Map<String, dynamic>? details,
    List<String> finalizationPhotos = const [],
    List<String> finalizationPhotoHashes = const [],
    Duration signatureDeadline = const Duration(hours: 48),
  }) async {
    if (_isLoading) return;

    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final occurrence = await _repository.getById(id);
      if (occurrence == null) {
        throw StateError('Ocorrencia nao encontrada.');
      }

      await _repository.closeForSignatures(
        occurrenceId: id,
        signatureDeadline: signatureDeadline,
        finalReport: finalReport,
        results: results,
        details: details,
        finalizationPhotos: finalizationPhotos,
        finalizationPhotoHashes: finalizationPhotoHashes,
      );

      _openSub?.cancel();
      _openSub = null;
      _openOccurrence = null;
      notifyListeners();
    } catch (e) {
      _error = 'Erro ao fechar ocorrencia para assinaturas: $e';
      notifyListeners();
      rethrow;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

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

  /// Atualiza o local de um evento com auditoria automática (via repositório).
  Future<void> updateEventLocation({
    required String occurrenceId,
    required String eventId,
    required double lat,
    required double lng,
    String? placeLabel,
    String? locationSource,
  }) async {
    final updates = <String, dynamic>{
      'gps_lat': lat,
      'gps_lng': lng,
      'place_label': placeLabel,
      'location_source': locationSource,
    };
    await updateEvent(occurrenceId, eventId, updates);
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
    final signatures = occurrence.signatures.isNotEmpty
        ? occurrence.signatures
        : await _signatureRepository.getSignatures(occurrence.id);
    final enrichedOccurrence = occurrence.copyWith(signatures: signatures);
    final generator = OccurrencePdfGenerator();
    return generator.generate(
      occurrence: enrichedOccurrence,
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
