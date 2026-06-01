import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';

import 'package:canil_gcm/core/domain/notification_item.dart';
import 'package:canil_gcm/core/domain/occurrence_participation.dart';
import 'package:canil_gcm/core/domain/occurrence_signature.dart';
import 'package:canil_gcm/core/domain/occurrence_team_member.dart';
import 'package:canil_gcm/core/services/notification_service.dart';
import 'package:canil_gcm/features/occurrences/data/occurrence_event_repository.dart';
import 'package:canil_gcm/features/occurrences/data/occurrence_repository.dart';
import 'package:canil_gcm/features/occurrences/data/signature_repository.dart';
import 'package:canil_gcm/features/occurrences/domain/occurrence.dart';
import 'package:canil_gcm/features/occurrences/domain/occurrence_event.dart';
import 'package:canil_gcm/features/occurrences/domain/occurrence_result.dart';
import 'package:canil_gcm/features/occurrences/domain/occurrence_status.dart';

class OccurrenceFinalizationService {
  static final OccurrenceFinalizationService _instance =
      OccurrenceFinalizationService._internal();

  factory OccurrenceFinalizationService() => _instance;

  OccurrenceFinalizationService._internal()
    : _occurrenceRepository = OccurrenceRepository(FirebaseFirestore.instance),
      _signatureRepository = SignatureRepository(),
      _eventRepository = OccurrenceEventRepository(FirebaseFirestore.instance),
      _notificationService = NotificationService();

  final OccurrenceRepository _occurrenceRepository;
  final SignatureRepository _signatureRepository;
  final OccurrenceEventRepository _eventRepository;
  final NotificationService _notificationService;

  Future<void> checkDeadlines() async {
    try {
      final expiredOccurrences = await _occurrenceRepository
          .getExpiredOccurrences(DateTime.now());

      for (final occurrence in expiredOccurrences) {
        await notifyDeadlineExpired(occurrence);
      }
    } catch (error) {
      debugPrint(
        '[OccurrenceFinalizationService] Erro ao verificar prazos: $error',
      );
    }
  }

  Future<bool> checkForAutoFinalization(String occurrenceId) async {
    try {
      final allSigned = await _occurrenceRepository.areAllSignaturesCollected(
        occurrenceId,
      );
      if (!allSigned) return false;

      final occurrence = await _occurrenceRepository.getById(occurrenceId);
      if (occurrence == null ||
          occurrence.status != OccurrenceStatus.awaitingSignatures) {
        return false;
      }

      await _finalizeOccurrence(occurrence);
      return true;
    } catch (error) {
      debugPrint(
        '[OccurrenceFinalizationService] Erro ao verificar finalizacao automatica: $error',
      );
      return false;
    }
  }

  String calculateIntegrityHashV3(
    Occurrence occurrence, {
    List<OccurrenceEvent> events = const [],
  }) {
    return calculateIntegrityHashV3For(occurrence, events: events);
  }

  String calculateIntegrityHashV4(
    Occurrence occurrence, {
    List<OccurrenceEvent> events = const [],
  }) {
    return calculateIntegrityHashV4For(occurrence, events: events);
  }

  static String calculateIntegrityHashFor(
    Occurrence occurrence, {
    required int version,
    List<OccurrenceEvent> events = const [],
  }) {
    final payload = _buildHashPayload(
      occurrence,
      events: events,
      version: version,
    );
    final canonicalJson = _canonicalJson(payload);
    return sha256.convert(utf8.encode(canonicalJson)).toString();
  }

  static String calculateIntegrityHashV1For(
    Occurrence occurrence, {
    List<OccurrenceEvent> events = const [],
  }) {
    return calculateIntegrityHashFor(occurrence, version: 1, events: events);
  }

  static String calculateIntegrityHashV2For(
    Occurrence occurrence, {
    List<OccurrenceEvent> events = const [],
  }) {
    return calculateIntegrityHashFor(occurrence, version: 2, events: events);
  }

  static String calculateIntegrityHashV3For(
    Occurrence occurrence, {
    List<OccurrenceEvent> events = const [],
  }) {
    return calculateIntegrityHashFor(occurrence, version: 3, events: events);
  }

  static String calculateIntegrityHashV4For(
    Occurrence occurrence, {
    List<OccurrenceEvent> events = const [],
  }) {
    return calculateIntegrityHashFor(occurrence, version: 4, events: events);
  }

  Future<void> _finalizeOccurrence(Occurrence occurrence) async {
    try {
      final signatures = await _signatureRepository.getSignatures(
        occurrence.id,
        activeRoundOnly: false,
      );
      final events = await _eventRepository.listByOccurrence(occurrence.id);
      final participations = await _loadParticipations(occurrence.id);
      final correctionRequests = await _loadCorrectionRequests(occurrence.id);
      final finalReport = _finalReportFor(occurrence);
      if (finalReport == null) {
        throw StateError(
          'Relato final ausente; nao e seguro selar a ocorrencia',
        );
      }

      final enrichedOccurrence = occurrence.copyWith(
        signatures: signatures,
        finalReport: finalReport,
        results: _resultsFor(occurrence),
        details: _detailsFor(occurrence),
        participations: participations,
        correctionRequests: correctionRequests,
      );
      final integrityHash = calculateIntegrityHashV4(
        enrichedOccurrence,
        events: events,
      );

      await _occurrenceRepository.finalize(
        id: occurrence.id,
        integrityHash: integrityHash,
        finalReport: finalReport,
        results: enrichedOccurrence.results,
        details: enrichedOccurrence.details,
        finalizationPhotos: occurrence.finalizationPhotos,
        finalizationPhotoHashes: occurrence.finalizationPhotoHashes,
        hashVersion: 4,
      );

      debugPrint(
        '[OccurrenceFinalizationService] Ocorrencia ${occurrence.id} finalizada automaticamente',
      );
    } catch (error) {
      debugPrint(
        '[OccurrenceFinalizationService] Erro ao finalizar ocorrencia: $error',
      );
    }
  }

  Future<bool> finalizeWithPending(String occurrenceId) async {
    final occurrence = await _occurrenceRepository.getById(occurrenceId);
    if (occurrence == null ||
        occurrence.status != OccurrenceStatus.awaitingSignatures) {
      return false;
    }

    final deadline = occurrence.signatureDeadline;
    if (deadline != null && DateTime.now().isBefore(deadline)) {
      throw StateError('O prazo de assinatura ainda nao venceu');
    }

    final finalReport = _finalReportFor(occurrence);
    if (finalReport == null) {
      throw StateError(
        'Relato final ausente; nao e seguro finalizar com pendencia',
      );
    }

    final signaturesBefore = await _signatureRepository.getSignatures(
      occurrence.id,
      activeRoundOnly: false,
    );
    final signedIds = signaturesBefore
        .where((signature) => signature.status == SignatureStatus.signed)
        .map((signature) => signature.handlerId)
        .toSet();
    final pendingCoSigners = occurrence.team.where(
      (member) =>
          member.role != TeamRole.titular &&
          _isAcceptedForSignature(occurrence, member.handlerId) &&
          !signedIds.contains(member.handlerId),
    );

    for (final member in pendingCoSigners) {
      await _signatureRepository.markSignatureExpired(
        occurrenceId: occurrence.id,
        handlerId: member.handlerId,
        reason: _pendingReason(occurrence, member.handlerId),
      );
    }

    final signatures = await _signatureRepository.getSignatures(
      occurrence.id,
      activeRoundOnly: false,
    );
    final events = await _eventRepository.listByOccurrence(occurrence.id);
    final participations = await _loadParticipations(occurrence.id);
    final correctionRequests = await _loadCorrectionRequests(occurrence.id);
    final enrichedOccurrence = occurrence.copyWith(
      signatures: signatures,
      finalReport: finalReport,
      results: _resultsFor(occurrence),
      details: _detailsFor(occurrence),
      participations: participations,
      correctionRequests: correctionRequests,
    );
    final integrityHash = calculateIntegrityHashV4(
      enrichedOccurrence,
      events: events,
    );

    await _occurrenceRepository.finalizeWithPending(
      id: occurrence.id,
      integrityHash: integrityHash,
      finalReport: finalReport,
      results: enrichedOccurrence.results,
      details: enrichedOccurrence.details,
      finalizationPhotos: occurrence.finalizationPhotos,
      finalizationPhotoHashes: occurrence.finalizationPhotoHashes,
      hashVersion: 4,
    );

    return true;
  }

  Future<void> notifyDeadlineExpired(Occurrence occurrence) async {
    debugPrint(
      '[OccurrenceFinalizationService] Prazo vencido para ocorrencia ${occurrence.id}',
    );

    final primaryRa = occurrence.primaryHandlerRa;
    if (primaryRa == null || primaryRa.isEmpty) return;
    final deadlineKey =
        occurrence.signatureDeadline?.millisecondsSinceEpoch.toString() ??
        'sem_prazo';
    await _notificationService.createNotification(
      userId: primaryRa,
      type: NotificationType.deadlineWarning,
      occurrenceId: occurrence.id,
      occurrenceTitle: occurrence.typeName,
      additionalData: 'deadline_expired:$deadlineKey',
      notificationId: 'deadline_${occurrence.id}_$deadlineKey',
      deduplicate: true,
    );
  }

  static Map<String, dynamic> _buildHashPayload(
    Occurrence occurrence, {
    List<OccurrenceEvent> events = const [],
    required int version,
  }) {
    final includePhotoHashes = version >= 2;
    final includeTeamAndSignatures = version >= 3;
    final includeCrewReview = version >= 4;
    final sortedTeam = List.of(occurrence.team)
      ..sort((a, b) => a.handlerId.compareTo(b.handlerId));
    final sortedSignatures =
        List<OccurrenceSignature>.from(occurrence.signatures)..sort((a, b) {
          final byRound = a.round.compareTo(b.round);
          if (byRound != 0) return byRound;
          return a.handlerId.compareTo(b.handlerId);
        });
    final sortedParticipations = List.of(occurrence.participations)
      ..sort((a, b) => a.handlerId.compareTo(b.handlerId));
    final correctionPayload =
        occurrence.correctionRequests.map(_normalizeForHash).toList()
          ..sort((a, b) => _canonicalJson(a).compareTo(_canonicalJson(b)));
    final eventPayload =
        events.where((event) => !event.isDeleted).map((event) {
          final photoHashes = _sortedStringValues(
            event.photoMetadata.map((metadata) => metadata['sha256']),
          );
          final payload = {
            'category': event.category.toMap(),
            'description': event.description,
            'dog_handler_id': event.dogHandlerId,
            'gps_lat': event.gpsLat,
            'gps_lng': event.gpsLng,
            'id': event.id,
            'photo_urls': _stringArray(event.photoUrls),
            'place_label': event.placeLabel,
            'timestamp': event.timestamp.toUtc().toIso8601String(),
            'title': event.title,
          };
          if (includePhotoHashes) {
            payload['photo_hashes'] = photoHashes;
          }
          return payload;
        }).toList()..sort((a, b) {
          final byTimestamp = (a['timestamp'] as String).compareTo(
            b['timestamp'] as String,
          );
          if (byTimestamp != 0) return byTimestamp;
          return (a['id'] as String).compareTo(b['id'] as String);
        });
    final resultPayload = _stringArray(
      occurrence.results.map((result) => result.toMap()),
    );

    final payload = {
      'details': _normalizeForHash(occurrence.details),
      'dog_id': occurrence.dogId,
      'final_report': occurrence.finalReport,
      'finalization_photos': _stringArray(occurrence.finalizationPhotos),
      'gps_accuracy': occurrence.gpsAccuracy,
      'gps_lat': occurrence.gpsLat,
      'gps_lng': occurrence.gpsLng,
      'hash_version': version,
      'location_address': occurrence.locationAddress,
      'primary_handler_id': occurrence.primaryHandlerId,
      'primary_handler_ra': occurrence.primaryHandlerRa,
      'results': resultPayload,
      'shift_id': occurrence.shiftId,
      if (includeCrewReview) 'crew_id': occurrence.crewId,
      if (includeCrewReview) 'service_dog_id': occurrence.effectiveServiceDogId,
      'vehicle_id': occurrence.vehicleId,
      'vehicle_label': occurrence.vehicleLabel,
      'vehicle_model': occurrence.vehicleModel,
      'vehicle_prefix': occurrence.vehiclePrefix,
      'vehicle_unit': occurrence.vehicleUnit,
      'started_at': occurrence.startedAt.toUtc().toIso8601String(),
      'events': eventPayload,
      'type_code': occurrence.typeCode,
      'type_name': occurrence.typeName,
    };
    if (includePhotoHashes) {
      payload['finalization_photo_hashes'] = [
        ..._stringArray(occurrence.finalizationPhotoHashes),
      ];
    }
    if (includeTeamAndSignatures) {
      payload['team'] = sortedTeam
          .map((member) => member.toHashPayload())
          .toList();
      payload['signatures'] = sortedSignatures
          .map((signature) => signature.toHashPayload())
          .toList();
    }
    if (includeCrewReview) {
      payload['accepted_handler_ids'] = _stringArray(
        occurrence.acceptedHandlerIds,
      );
      payload['declined_handler_ids'] = _stringArray(
        occurrence.declinedHandlerIds,
      );
      payload['edit_authorized_handler_ids'] = _stringArray(
        occurrence.editAuthorizedHandlerIds,
      );
      payload['participation_revision'] = occurrence.participationRevision;
      payload['participation_status'] = occurrence.participationStatus;
      payload['pending_handler_ids'] = _stringArray(
        occurrence.pendingHandlerIds,
      );
      payload['signature_round'] = occurrence.signatureRound;
      payload['participations'] = sortedParticipations
          .map((participation) => participation.toHashPayload())
          .toList();
      payload['correction_requests'] = correctionPayload;
    }
    return payload;
  }

  Future<List<OccurrenceParticipation>> _loadParticipations(
    String occurrenceId,
  ) async {
    final snapshot = await FirebaseFirestore.instance
        .collection('occurrences')
        .doc(occurrenceId)
        .collection('participations')
        .get();
    return snapshot.docs
        .map((doc) => OccurrenceParticipation.fromJson(doc.data()))
        .where((participation) => participation.handlerId.isNotEmpty)
        .toList();
  }

  Future<List<Map<String, dynamic>>> _loadCorrectionRequests(
    String occurrenceId,
  ) async {
    final snapshot = await FirebaseFirestore.instance
        .collection('occurrences')
        .doc(occurrenceId)
        .collection('correction_requests')
        .get();
    return snapshot.docs.map((doc) => {'id': doc.id, ...doc.data()}).toList();
  }

  static String _canonicalJson(dynamic value) {
    if (value is Map) {
      final sortedKeys = value.keys.map((key) => key.toString()).toList()
        ..sort();
      final normalized = <String, dynamic>{};
      for (final key in sortedKeys) {
        normalized[key] = _normalizeForHash(value[key]);
      }
      return jsonEncode(normalized);
    }
    return jsonEncode(_normalizeForHash(value));
  }

  static dynamic _normalizeForHash(dynamic value) {
    if (value == null) return null;
    if (value is Timestamp) return value.toDate().toUtc().toIso8601String();
    if (value is DateTime) return value.toUtc().toIso8601String();
    if (value is Map) {
      final sortedKeys = value.keys.map((key) => key.toString()).toList()
        ..sort();
      return {for (final key in sortedKeys) key: _normalizeForHash(value[key])};
    }
    if (value is Iterable) {
      return value.map(_normalizeForHash).toList();
    }
    return value;
  }

  static List<String> _stringArray(Iterable<dynamic> values) {
    return {
      for (final value in values)
        if (_stringValue(value) != null) _stringValue(value)!,
    }.toList()..sort();
  }

  static List<String> _sortedStringValues(Iterable<dynamic> values) {
    return [
      for (final value in values)
        if (_stringValue(value) != null) _stringValue(value)!,
    ]..sort();
  }

  static String? _stringValue(dynamic value) {
    if (value == null) return null;
    final text = value.toString().trim();
    return text.isEmpty ? null : text;
  }

  static String? _finalReportFor(Occurrence occurrence) {
    final report = occurrence.finalReport?.trim();
    if (report != null && report.isNotEmpty) return report;
    final draftReport = occurrence.finalizationDraft?['final_report']
        ?.toString()
        .trim();
    if (draftReport != null && draftReport.isNotEmpty) return draftReport;
    return null;
  }

  static List<OccurrenceResult> _resultsFor(Occurrence occurrence) {
    if (occurrence.results.isNotEmpty) return occurrence.results;
    final rawResults = occurrence.finalizationDraft?['results'];
    if (rawResults is! List) return const [];
    return rawResults
        .map((value) => value?.toString())
        .whereType<String>()
        .map(OccurrenceResult.fromMap)
        .toList();
  }

  static Map<String, dynamic>? _detailsFor(Occurrence occurrence) {
    if (occurrence.details != null) return occurrence.details;
    final rawDetails = occurrence.finalizationDraft?['details'];
    if (rawDetails is! Map) return null;
    return rawDetails.map((key, value) => MapEntry(key.toString(), value));
  }

  static String _pendingReason(Occurrence occurrence, String handlerId) {
    final invitedAt = occurrence.signatureRequestAt?.toUtc().toIso8601String();
    final deadline = occurrence.signatureDeadline?.toUtc().toIso8601String();
    return 'Convidado em ${invitedAt ?? 'data nao registrada'}; nao assinou no prazo de ${deadline ?? 'prazo nao registrado'}';
  }

  static bool _isAcceptedForSignature(Occurrence occurrence, String handlerId) {
    if (occurrence.acceptedHandlerIds.isEmpty &&
        occurrence.participationRevision == 0) {
      return true;
    }
    return occurrence.acceptedHandlerIds.contains(handlerId);
  }
}
