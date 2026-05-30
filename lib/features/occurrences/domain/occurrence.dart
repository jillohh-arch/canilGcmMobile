import 'package:cloud_firestore/cloud_firestore.dart';

import 'package:canil_gcm/core/mixins/soft_deletable.dart';
import 'package:canil_gcm/core/domain/occurrence_participation.dart';
import 'package:canil_gcm/core/domain/occurrence_team_member.dart';
import 'package:canil_gcm/core/domain/occurrence_signature.dart';
import 'occurrence_result.dart';
import 'occurrence_status.dart';

class Occurrence with SoftDeletable {
  final String id;
  final String shiftId;
  final String primaryHandlerId;
  final String? primaryHandlerRa;
  final Map<String, dynamic>? createdBy;
  final String dogId;
  final String? serviceDogId;
  final String? crewId;
  final String? vehicleId;
  final String? vehicleLabel;
  final String? vehiclePrefix;
  final String? vehicleModel;
  final String? vehicleUnit;

  final String typeCode;
  final String typeName;

  final String? locationAddress;
  final double? gpsLat;
  final double? gpsLng;
  final double? gpsAccuracy;

  final DateTime startedAt;
  final DateTime? finalizedAt;
  final DateTime createdAt;
  final DateTime updatedAt;

  final OccurrenceStatus status;

  final String? finalReport;
  final List<OccurrenceResult> results;
  final Map<String, dynamic>? details;

  final String? integrityHash;
  final int? hashVersion;
  final String? pdfExportUrl;
  final int? durationTotal;
  final Map<String, dynamic>? finalizationDraft;

  final String? initialObservation;

  final List<String> finalizationPhotos;
  final List<String> finalizationPhotoHashes;

  final List<Map<String, dynamic>> auditTrail;

  // Campos da equipe e assinaturas
  final List<OccurrenceTeamMember> team;
  final int teamSizeMax;
  final DateTime? signatureRequestAt;
  final DateTime? signatureDeadline;
  final int signatureRound;
  final List<OccurrenceSignature> signatures;
  final List<OccurrenceParticipation> participations;
  final List<Map<String, dynamic>> correctionRequests;
  final String? participationStatus;
  final List<String> acceptedHandlerIds;
  final List<String> declinedHandlerIds;
  final List<String> pendingHandlerIds;
  final List<String> editAuthorizedHandlerIds;
  final int participationRevision;

  @override
  final DateTime? deletedAt;
  @override
  final String? deletedBy;
  @override
  final String? deleteReason;

  const Occurrence({
    required this.id,
    required this.shiftId,
    required this.primaryHandlerId,
    this.primaryHandlerRa,
    this.createdBy,
    required this.dogId,
    this.serviceDogId,
    this.crewId,
    this.vehicleId,
    this.vehicleLabel,
    this.vehiclePrefix,
    this.vehicleModel,
    this.vehicleUnit,
    required this.typeCode,
    required this.typeName,
    this.locationAddress,
    this.gpsLat,
    this.gpsLng,
    this.gpsAccuracy,
    required this.startedAt,
    this.finalizedAt,
    required this.createdAt,
    required this.updatedAt,
    this.status = OccurrenceStatus.inProgress,
    this.finalReport,
    this.results = const [],
    this.details,
    this.integrityHash,
    this.hashVersion,
    this.pdfExportUrl,
    this.durationTotal,
    this.finalizationDraft,
    this.initialObservation,
    this.finalizationPhotos = const [],
    this.finalizationPhotoHashes = const [],
    this.auditTrail = const [],
    this.team = const [],
    this.signatures = const [],
    this.participations = const [],
    this.correctionRequests = const [],
    this.teamSizeMax = 3,
    this.signatureRequestAt,
    this.signatureDeadline,
    this.signatureRound = 0,
    this.deletedAt,
    this.deletedBy,
    this.deleteReason,
    this.participationStatus,
    this.acceptedHandlerIds = const [],
    this.declinedHandlerIds = const [],
    this.pendingHandlerIds = const [],
    this.editAuthorizedHandlerIds = const [],
    this.participationRevision = 0,
  });

  factory Occurrence.fromMap(Map<String, dynamic> map, String id) {
    return Occurrence(
      id: id,
      shiftId: _parseString(map['shift_id']) ?? '',
      primaryHandlerId: _parseString(map['primary_handler_id']) ?? '',
      primaryHandlerRa: _parseString(map['primary_handler_ra']),
      createdBy: _parseStringMap(map['created_by']),
      dogId: _parseString(map['dog_id']) ?? '',
      serviceDogId:
          _parseString(map['service_dog_id']) ?? _parseString(map['dog_id']),
      crewId: _parseString(map['crew_id']),
      vehicleId: _parseString(map['vehicle_id']),
      vehicleLabel: _parseString(map['vehicle_label']),
      vehiclePrefix: _parseString(map['vehicle_prefix']),
      vehicleModel: _parseString(map['vehicle_model']),
      vehicleUnit: _parseString(map['vehicle_unit']),
      typeCode: _parseString(map['type_code']) ?? '',
      typeName: _parseString(map['type_name']) ?? '',
      locationAddress: _parseString(map['location_address']),
      gpsLat: _parseDouble(map['gps_lat']),
      gpsLng: _parseDouble(map['gps_lng']),
      gpsAccuracy: _parseDouble(map['gps_accuracy']),
      startedAt: _parseDateTime(map['started_at']) ?? DateTime.now(),
      finalizedAt: _parseDateTime(map['finalized_at']),
      createdAt: _parseDateTime(map['created_at']) ?? DateTime.now(),
      updatedAt: _parseDateTime(map['updated_at']) ?? DateTime.now(),
      status: OccurrenceStatus.fromMap(_parseString(map['status'])),
      finalReport: _parseString(map['final_report']),
      results: _parseResults(map['results']),
      details: _parseStringMap(map['details']),
      integrityHash: _parseString(map['integrity_hash']),
      hashVersion: _parseInt(map['hash_version']),
      pdfExportUrl: _parseString(map['pdf_export_url']),
      durationTotal: _parseInt(map['duration_total']),
      finalizationDraft: _parseStringMap(map['finalization_draft']),
      initialObservation: _parseString(map['initial_observation']),
      finalizationPhotos:
          (map['finalization_photos'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          const [],
      finalizationPhotoHashes:
          (map['finalization_photo_hashes'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          const [],
      auditTrail: _parseMapList(map['audit_trail']),
      team: _parseTeamMembers(map['team']),
      signatures: _parseSignatures(map['signatures']),
      participations: _parseParticipations(map['participations']),
      correctionRequests: _parseMapList(map['correction_requests']),
      teamSizeMax: _parseInt(map['team_size_max']) ?? 3,
      signatureRequestAt: _parseDateTime(map['signature_request_at']),
      signatureDeadline: _parseDateTime(map['signature_deadline']),
      signatureRound: _parseInt(map['signature_round']) ?? 0,
      participationStatus: _parseString(map['participation_status']),
      acceptedHandlerIds: _parseStringList(map['accepted_handler_ids']),
      declinedHandlerIds: _parseStringList(map['declined_handler_ids']),
      pendingHandlerIds: _parseStringList(map['pending_handler_ids']),
      editAuthorizedHandlerIds: _parseStringList(
        map['edit_authorized_handler_ids'],
      ),
      participationRevision: _parseInt(map['participation_revision']) ?? 0,
      deletedAt: SoftDeletable.parseDeletedAt(map['deleted_at']),
      deletedBy: _parseString(map['deleted_by']),
      deleteReason:
          _parseString(map['deleted_reason']) ??
          _parseString(map['delete_reason']),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'shift_id': shiftId,
      'primary_handler_id': primaryHandlerId,
      'primary_handler_ra': primaryHandlerRa,
      'created_by': createdBy,
      'dog_id': dogId,
      'service_dog_id': serviceDogId ?? dogId,
      'crew_id': crewId,
      'vehicle_id': vehicleId,
      'vehicle_label': vehicleLabel,
      'vehicle_prefix': vehiclePrefix,
      'vehicle_model': vehicleModel,
      'vehicle_unit': vehicleUnit,
      'type_code': typeCode,
      'type_name': typeName,
      'location_address': locationAddress,
      'gps_lat': gpsLat,
      'gps_lng': gpsLng,
      'gps_accuracy': gpsAccuracy,
      'started_at': Timestamp.fromDate(startedAt),
      'finalized_at': finalizedAt != null
          ? Timestamp.fromDate(finalizedAt!)
          : null,
      'created_at': Timestamp.fromDate(createdAt),
      'updated_at': Timestamp.fromDate(updatedAt),
      'status': status.toMap(),
      'final_report': finalReport,
      'results': results.map((r) => r.toMap()).toList(),
      'details': details,
      'integrity_hash': integrityHash,
      'hash_version': hashVersion,
      'pdf_export_url': pdfExportUrl,
      'duration_total': durationTotal,
      'finalization_draft': finalizationDraft,
      'initial_observation': initialObservation,
      'finalization_photos': finalizationPhotos,
      'finalization_photo_hashes': finalizationPhotoHashes,
      'audit_trail': auditTrail,
      'team': team.map((member) => member.toJson()).toList(),
      'team_handler_ids': teamHandlerIds,
      'team_emails': teamEmails,
      'team_auth_uids': teamAuthUids,
      'team_auth_keys': teamAuthKeys,
      'team_size_max': teamSizeMax,
      'signature_round': signatureRound,
      'signature_request_at': signatureRequestAt != null
          ? Timestamp.fromDate(signatureRequestAt!)
          : null,
      'signature_deadline': signatureDeadline != null
          ? Timestamp.fromDate(signatureDeadline!)
          : null,
      'participation_status': participationStatus,
      'accepted_handler_ids': acceptedHandlerIds,
      'declined_handler_ids': declinedHandlerIds,
      'pending_handler_ids': pendingHandlerIds,
      'edit_authorized_handler_ids': editAuthorizedHandlerIds,
      'edit_authorized_emails': editAuthorizedEmails,
      'participation_revision': participationRevision,
      ...softDeleteFields(),
    };
  }

  Occurrence copyWith({
    String? id,
    String? shiftId,
    String? primaryHandlerId,
    String? primaryHandlerRa,
    Map<String, dynamic>? createdBy,
    String? dogId,
    String? serviceDogId,
    String? crewId,
    String? vehicleId,
    String? vehicleLabel,
    String? vehiclePrefix,
    String? vehicleModel,
    String? vehicleUnit,
    String? typeCode,
    String? typeName,
    String? locationAddress,
    double? gpsLat,
    double? gpsLng,
    double? gpsAccuracy,
    DateTime? startedAt,
    DateTime? finalizedAt,
    DateTime? createdAt,
    DateTime? updatedAt,
    OccurrenceStatus? status,
    String? finalReport,
    List<OccurrenceResult>? results,
    Map<String, dynamic>? details,
    String? integrityHash,
    int? hashVersion,
    String? pdfExportUrl,
    int? durationTotal,
    Map<String, dynamic>? finalizationDraft,
    String? initialObservation,
    List<String>? finalizationPhotos,
    List<String>? finalizationPhotoHashes,
    List<Map<String, dynamic>>? auditTrail,
    List<OccurrenceTeamMember>? team,
    List<OccurrenceSignature>? signatures,
    List<OccurrenceParticipation>? participations,
    List<Map<String, dynamic>>? correctionRequests,
    int? teamSizeMax,
    DateTime? signatureRequestAt,
    DateTime? signatureDeadline,
    int? signatureRound,
    String? participationStatus,
    List<String>? acceptedHandlerIds,
    List<String>? declinedHandlerIds,
    List<String>? pendingHandlerIds,
    List<String>? editAuthorizedHandlerIds,
    int? participationRevision,
    DateTime? deletedAt,
    String? deletedBy,
    String? deleteReason,
  }) {
    return Occurrence(
      id: id ?? this.id,
      shiftId: shiftId ?? this.shiftId,
      primaryHandlerId: primaryHandlerId ?? this.primaryHandlerId,
      primaryHandlerRa: primaryHandlerRa ?? this.primaryHandlerRa,
      createdBy: createdBy ?? this.createdBy,
      dogId: dogId ?? this.dogId,
      serviceDogId: serviceDogId ?? this.serviceDogId,
      crewId: crewId ?? this.crewId,
      vehicleId: vehicleId ?? this.vehicleId,
      vehicleLabel: vehicleLabel ?? this.vehicleLabel,
      vehiclePrefix: vehiclePrefix ?? this.vehiclePrefix,
      vehicleModel: vehicleModel ?? this.vehicleModel,
      vehicleUnit: vehicleUnit ?? this.vehicleUnit,
      typeCode: typeCode ?? this.typeCode,
      typeName: typeName ?? this.typeName,
      locationAddress: locationAddress ?? this.locationAddress,
      gpsLat: gpsLat ?? this.gpsLat,
      gpsLng: gpsLng ?? this.gpsLng,
      gpsAccuracy: gpsAccuracy ?? this.gpsAccuracy,
      startedAt: startedAt ?? this.startedAt,
      finalizedAt: finalizedAt ?? this.finalizedAt,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      status: status ?? this.status,
      finalReport: finalReport ?? this.finalReport,
      results: results ?? this.results,
      details: details ?? this.details,
      integrityHash: integrityHash ?? this.integrityHash,
      hashVersion: hashVersion ?? this.hashVersion,
      pdfExportUrl: pdfExportUrl ?? this.pdfExportUrl,
      durationTotal: durationTotal ?? this.durationTotal,
      finalizationDraft: finalizationDraft ?? this.finalizationDraft,
      initialObservation: initialObservation ?? this.initialObservation,
      finalizationPhotos: finalizationPhotos ?? this.finalizationPhotos,
      finalizationPhotoHashes:
          finalizationPhotoHashes ?? this.finalizationPhotoHashes,
      auditTrail: auditTrail ?? this.auditTrail,
      team: team ?? this.team,
      signatures: signatures ?? this.signatures,
      participations: participations ?? this.participations,
      correctionRequests: correctionRequests ?? this.correctionRequests,
      teamSizeMax: teamSizeMax ?? this.teamSizeMax,
      signatureRequestAt: signatureRequestAt ?? this.signatureRequestAt,
      signatureDeadline: signatureDeadline ?? this.signatureDeadline,
      signatureRound: signatureRound ?? this.signatureRound,
      participationStatus: participationStatus ?? this.participationStatus,
      acceptedHandlerIds: acceptedHandlerIds ?? this.acceptedHandlerIds,
      declinedHandlerIds: declinedHandlerIds ?? this.declinedHandlerIds,
      pendingHandlerIds: pendingHandlerIds ?? this.pendingHandlerIds,
      editAuthorizedHandlerIds:
          editAuthorizedHandlerIds ?? this.editAuthorizedHandlerIds,
      participationRevision:
          participationRevision ?? this.participationRevision,
      deletedAt: deletedAt ?? this.deletedAt,
      deletedBy: deletedBy ?? this.deletedBy,
      deleteReason: deleteReason ?? this.deleteReason,
    );
  }

  List<String> get teamHandlerIds {
    final ids = <String>{
      if (primaryHandlerRa != null && primaryHandlerRa!.trim().isNotEmpty)
        primaryHandlerRa!.trim(),
      for (final member in team)
        if (member.handlerId.trim().isNotEmpty) member.handlerId.trim(),
    }.toList()..sort();
    return ids;
  }

  List<String> get teamEmails {
    final emails = <String>{
      for (final member in team)
        if (member.handlerEmail?.trim().isNotEmpty == true)
          member.handlerEmail!.trim().toLowerCase(),
      for (final ra in teamHandlerIds) _emailForRa(ra),
    }.toList()..sort();
    return emails;
  }

  List<String> get editAuthorizedEmails {
    final authorized = editAuthorizedHandlerIds.isNotEmpty
        ? editAuthorizedHandlerIds
        : teamHandlerIds;
    final emails = <String>{
      for (final member in team)
        if (authorized.contains(member.handlerId) &&
            member.handlerEmail?.trim().isNotEmpty == true)
          member.handlerEmail!.trim().toLowerCase(),
      for (final ra in authorized) _emailForRa(ra),
    }.toList()..sort();
    return emails;
  }

  List<String> get teamAuthUids {
    final uids = <String>{
      for (final member in team)
        if (member.authUid?.trim().isNotEmpty == true) member.authUid!.trim(),
    }.toList()..sort();
    return uids;
  }

  List<String> get teamAuthKeys {
    final keys = <String>{
      for (final member in team)
        if (member.handlerId.trim().isNotEmpty &&
            member.authUid?.trim().isNotEmpty == true)
          '${member.handlerId.trim()}:${member.authUid!.trim()}',
    }.toList()..sort();
    return keys;
  }

  bool get hasVehicleCrew => vehicleId?.trim().isNotEmpty == true;
  String get effectiveServiceDogId =>
      serviceDogId?.trim().isNotEmpty == true ? serviceDogId!.trim() : dogId;

  static DateTime? _parseDateTime(dynamic value) {
    if (value == null) return null;
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    if (value is String) return DateTime.tryParse(value);
    return null;
  }

  static String? _parseString(dynamic value) {
    if (value == null) return null;
    final text = value.toString().trim();
    return text.isEmpty ? null : text;
  }

  static double? _parseDouble(dynamic value) {
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value.replaceAll(',', '.'));
    return null;
  }

  static int? _parseInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.round();
    if (value is String) return int.tryParse(value);
    return null;
  }

  static Map<String, dynamic>? _parseStringMap(dynamic value) {
    if (value == null || value is! Map) return null;
    return value.map((key, item) => MapEntry(key.toString(), item));
  }

  static List<Map<String, dynamic>> _parseMapList(dynamic value) {
    if (value is! List) return const [];
    return value
        .whereType<Map>()
        .map(
          (item) => item.map((key, value) => MapEntry(key.toString(), value)),
        )
        .toList();
  }

  static List<OccurrenceResult> _parseResults(dynamic value) {
    if (value is! List) return const [];
    return value.map((item) {
      if (item is Map) {
        final map = item.map((key, value) => MapEntry(key.toString(), value));
        return OccurrenceResult.fromMap(
          _parseString(map['code']) ??
              _parseString(map['type']) ??
              _parseString(map['result']) ??
              _parseString(map['value']) ??
              _parseString(map['id']),
        );
      }
      return OccurrenceResult.fromMap(_parseString(item));
    }).toList();
  }

  static List<OccurrenceTeamMember> _parseTeamMembers(dynamic value) {
    if (value is Map) {
      final conductors = value['conductors'];
      final serviceDog = value['service_dog'];
      if (conductors is! List) return const [];
      final dogMap = serviceDog is Map ? serviceDog : const {};
      return conductors.whereType<Map>().map((item) {
        final merged = <String, dynamic>{
          ...item.map((key, value) => MapEntry(key.toString(), value)),
          if (dogMap['dog_id'] != null || dogMap['id'] != null)
            'dog_id': dogMap['dog_id'] ?? dogMap['id'],
          if (dogMap['name'] != null) 'dog_name': dogMap['name'],
          if (dogMap['matricula'] != null) 'dog_matricula': dogMap['matricula'],
          if (dogMap['breed'] != null) 'dog_breed': dogMap['breed'],
        };
        return OccurrenceTeamMember.fromJson(merged);
      }).toList();
    }
    if (value is! List) return const [];
    return value
        .whereType<Map>()
        .map((item) => OccurrenceTeamMember.fromJson(item))
        .toList();
  }

  static List<OccurrenceSignature> _parseSignatures(dynamic value) {
    if (value is! List) return const [];
    return value
        .whereType<Map>()
        .map((item) => OccurrenceSignature.fromJson(item))
        .toList();
  }

  static String _emailForRa(String ra) {
    return '${ra.trim().toLowerCase()}@gcm.com.br';
  }

  static List<String> _parseStringList(dynamic value) {
    if (value is! List) return const [];
    final parsed =
        value
            .map(_parseString)
            .whereType<String>()
            .where((item) => item.isNotEmpty)
            .toSet()
            .toList()
          ..sort();
    return parsed;
  }

  static List<OccurrenceParticipation> _parseParticipations(dynamic value) {
    if (value is! List) return const [];
    return value
        .whereType<Map>()
        .map(OccurrenceParticipation.fromJson)
        .where((participation) => participation.handlerId.isNotEmpty)
        .toList();
  }
}
