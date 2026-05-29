import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';

import 'package:canil_gcm/core/domain/notification_item.dart';
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

  static String calculateIntegrityHashV3For(
    Occurrence occurrence, {
    List<OccurrenceEvent> events = const [],
  }) {
    final payload = _buildHashPayloadV3(occurrence, events: events);
    final canonicalJson = _canonicalJson(payload);
    return sha256.convert(utf8.encode(canonicalJson)).toString();
  }

  Future<void> _finalizeOccurrence(Occurrence occurrence) async {
    try {
      final signatures = await _signatureRepository.getSignatures(
        occurrence.id,
      );
      final events = await _eventRepository.listByOccurrence(occurrence.id);
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
      );
      final integrityHash = calculateIntegrityHashV3(
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
        hashVersion: 3,
      );

      await _notifyOccurrenceFinalized(
        enrichedOccurrence,
        status: OccurrenceStatus.finalized,
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
    );
    final signedIds = signaturesBefore
        .where((signature) => signature.status == SignatureStatus.signed)
        .map((signature) => signature.handlerId)
        .toSet();
    final pendingCoSigners = occurrence.team.where(
      (member) =>
          member.role != TeamRole.titular &&
          !signedIds.contains(member.handlerId),
    );

    for (final member in pendingCoSigners) {
      await _signatureRepository.markSignatureExpired(
        occurrenceId: occurrence.id,
        handlerId: member.handlerId,
        reason: _pendingReason(occurrence, member.handlerId),
      );
    }

    final signatures = await _signatureRepository.getSignatures(occurrence.id);
    final events = await _eventRepository.listByOccurrence(occurrence.id);
    final enrichedOccurrence = occurrence.copyWith(
      signatures: signatures,
      finalReport: finalReport,
      results: _resultsFor(occurrence),
      details: _detailsFor(occurrence),
    );
    final integrityHash = calculateIntegrityHashV3(
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
      hashVersion: 3,
    );

    await _notifyOccurrenceFinalized(
      enrichedOccurrence,
      status: OccurrenceStatus.finalizedWithPending,
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

  static Map<String, dynamic> _buildHashPayloadV3(
    Occurrence occurrence, {
    List<OccurrenceEvent> events = const [],
  }) {
    final sortedTeam = List.of(occurrence.team)
      ..sort((a, b) => a.handlerId.compareTo(b.handlerId));
    final sortedSignatures = List<OccurrenceSignature>.from(
      occurrence.signatures,
    )..sort((a, b) => a.handlerId.compareTo(b.handlerId));
    final eventPayload =
        events.map((event) {
          final photoHashes =
              event.photoMetadata
                  .where((metadata) => metadata['sha256'] != null)
                  .map((metadata) => metadata['sha256'].toString())
                  .toList()
                ..sort();
          return {
            'category': event.category.toMap(),
            'description': event.description,
            'dog_handler_id': event.dogHandlerId,
            'gps_lat': event.gpsLat,
            'gps_lng': event.gpsLng,
            'id': event.id,
            'photo_hashes': photoHashes,
            'photo_urls': [...event.photoUrls]..sort(),
            'place_label': event.placeLabel,
            'timestamp': event.timestamp.toUtc().toIso8601String(),
            'title': event.title,
          };
        }).toList()..sort((a, b) {
          final byTimestamp = (a['timestamp'] as String).compareTo(
            b['timestamp'] as String,
          );
          if (byTimestamp != 0) return byTimestamp;
          return (a['id'] as String).compareTo(b['id'] as String);
        });
    final resultPayload =
        occurrence.results.map((result) => result.toMap()).toList()..sort();

    return {
      'details': _normalizeForHash(occurrence.details),
      'dog_id': occurrence.dogId,
      'final_report': occurrence.finalReport,
      'finalization_photo_hashes': [...occurrence.finalizationPhotoHashes]
        ..sort(),
      'finalization_photos': [...occurrence.finalizationPhotos]..sort(),
      'gps_accuracy': occurrence.gpsAccuracy,
      'gps_lat': occurrence.gpsLat,
      'gps_lng': occurrence.gpsLng,
      'hash_version': 3,
      'location_address': occurrence.locationAddress,
      'primary_handler_id': occurrence.primaryHandlerId,
      'primary_handler_ra': occurrence.primaryHandlerRa,
      'results': resultPayload,
      'shift_id': occurrence.shiftId,
      'vehicle_id': occurrence.vehicleId,
      'vehicle_label': occurrence.vehicleLabel,
      'vehicle_model': occurrence.vehicleModel,
      'vehicle_prefix': occurrence.vehiclePrefix,
      'vehicle_unit': occurrence.vehicleUnit,
      'signatures': sortedSignatures
          .map((signature) => signature.toHashPayload())
          .toList(),
      'started_at': occurrence.startedAt.toUtc().toIso8601String(),
      'team': sortedTeam.map((member) => member.toHashPayload()).toList(),
      'events': eventPayload,
      'type_code': occurrence.typeCode,
      'type_name': occurrence.typeName,
    };
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

  Future<void> _notifyOccurrenceFinalized(
    Occurrence occurrence, {
    required OccurrenceStatus status,
  }) async {
    for (final member in occurrence.team) {
      if (member.handlerId.trim().isEmpty) continue;
      await _notificationService.createNotification(
        userId: member.handlerId,
        type: NotificationType.occurrenceFinalized,
        occurrenceId: occurrence.id,
        occurrenceTitle: occurrence.typeName,
        additionalData: status.toMap(),
      );
    }
  }
}
