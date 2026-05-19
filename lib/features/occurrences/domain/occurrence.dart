import 'package:cloud_firestore/cloud_firestore.dart';

import 'package:canil_gcm/core/mixins/soft_deletable.dart';
import 'occurrence_result.dart';
import 'occurrence_status.dart';

class Occurrence with SoftDeletable {
  final String id;
  final String shiftId;
  final String primaryHandlerId;
  final String dogId;

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
  final String? pdfExportUrl;

  final String? initialObservation;

  final List<Map<String, dynamic>> auditTrail;

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
    required this.dogId,
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
    this.pdfExportUrl,
    this.initialObservation,
    this.auditTrail = const [],
    this.deletedAt,
    this.deletedBy,
    this.deleteReason,
  });

  factory Occurrence.fromMap(Map<String, dynamic> map, String id) {
    return Occurrence(
      id: id,
      shiftId: map['shift_id'] as String? ?? '',
      primaryHandlerId: map['primary_handler_id'] as String? ?? '',
      dogId: map['dog_id'] as String? ?? '',
      typeCode: map['type_code'] as String? ?? '',
      typeName: map['type_name'] as String? ?? '',
      locationAddress: map['location_address'] as String?,
      gpsLat: (map['gps_lat'] as num?)?.toDouble(),
      gpsLng: (map['gps_lng'] as num?)?.toDouble(),
      gpsAccuracy: (map['gps_accuracy'] as num?)?.toDouble(),
      startedAt: _parseDateTime(map['started_at']) ?? DateTime.now(),
      finalizedAt: _parseDateTime(map['finalized_at']),
      createdAt: _parseDateTime(map['created_at']) ?? DateTime.now(),
      updatedAt: _parseDateTime(map['updated_at']) ?? DateTime.now(),
      status: OccurrenceStatus.fromMap(map['status'] as String?),
      finalReport: map['final_report'] as String?,
      results: (map['results'] as List<dynamic>?)
              ?.map((e) => OccurrenceResult.fromMap(e as String?))
              .toList() ??
          const [],
      details: map['details'] as Map<String, dynamic>?,
      integrityHash: map['integrity_hash'] as String?,
      pdfExportUrl: map['pdf_export_url'] as String?,
      initialObservation: map['initial_observation'] as String?,
      auditTrail: (map['audit_trail'] as List<dynamic>?)
              ?.map((e) => Map<String, dynamic>.from(e as Map))
              .toList() ??
          const [],
      deletedAt: SoftDeletable.parseDeletedAt(map['deleted_at']),
      deletedBy: map['deleted_by'] as String?,
      deleteReason: map['delete_reason'] as String?,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'shift_id': shiftId,
      'primary_handler_id': primaryHandlerId,
      'dog_id': dogId,
      'type_code': typeCode,
      'type_name': typeName,
      'location_address': locationAddress,
      'gps_lat': gpsLat,
      'gps_lng': gpsLng,
      'gps_accuracy': gpsAccuracy,
      'started_at': Timestamp.fromDate(startedAt),
      'finalized_at':
          finalizedAt != null ? Timestamp.fromDate(finalizedAt!) : null,
      'created_at': Timestamp.fromDate(createdAt),
      'updated_at': Timestamp.fromDate(updatedAt),
      'status': status.toMap(),
      'final_report': finalReport,
      'results': results.map((r) => r.toMap()).toList(),
      'details': details,
      'integrity_hash': integrityHash,
      'pdf_export_url': pdfExportUrl,
      'initial_observation': initialObservation,
      'audit_trail': auditTrail,
      ...softDeleteFields(),
    };
  }

  Occurrence copyWith({
    String? id,
    String? shiftId,
    String? primaryHandlerId,
    String? dogId,
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
    String? pdfExportUrl,
    String? initialObservation,
    List<Map<String, dynamic>>? auditTrail,
    DateTime? deletedAt,
    String? deletedBy,
    String? deleteReason,
  }) {
    return Occurrence(
      id: id ?? this.id,
      shiftId: shiftId ?? this.shiftId,
      primaryHandlerId: primaryHandlerId ?? this.primaryHandlerId,
      dogId: dogId ?? this.dogId,
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
      pdfExportUrl: pdfExportUrl ?? this.pdfExportUrl,
      initialObservation: initialObservation ?? this.initialObservation,
      auditTrail: auditTrail ?? this.auditTrail,
      deletedAt: deletedAt ?? this.deletedAt,
      deletedBy: deletedBy ?? this.deletedBy,
      deleteReason: deleteReason ?? this.deleteReason,
    );
  }

  static DateTime? _parseDateTime(dynamic value) {
    if (value == null) return null;
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    if (value is String) return DateTime.tryParse(value);
    return null;
  }
}
