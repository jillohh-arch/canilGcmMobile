import 'package:cloud_firestore/cloud_firestore.dart';

enum OccurrenceParticipationStatus {
  included,
  pending,
  accepted,
  correctionRequested,
  declined;

  String toMap() => switch (this) {
    included => 'included',
    pending => 'pending',
    accepted => 'accepted',
    correctionRequested => 'correction_requested',
    declined => 'declined',
  };

  static OccurrenceParticipationStatus fromMap(String? value) {
    final normalized = value?.trim().toLowerCase();
    if (normalized == 'pending' || normalized == 'pendente') {
      return OccurrenceParticipationStatus.pending;
    }
    if (normalized == 'accepted' || normalized == 'aceito') {
      return OccurrenceParticipationStatus.accepted;
    }
    if (normalized == 'correction_requested' ||
        normalized == 'correcao_solicitada') {
      return OccurrenceParticipationStatus.correctionRequested;
    }
    if (normalized == 'declined' || normalized == 'recusado') {
      return OccurrenceParticipationStatus.declined;
    }
    return OccurrenceParticipationStatus.included;
  }
}

class OccurrenceParticipation {
  final String handlerId;
  final OccurrenceParticipationStatus status;
  final String? declineReason;
  final DateTime at;
  final String? updatedBy;

  const OccurrenceParticipation({
    required this.handlerId,
    required this.status,
    this.declineReason,
    required this.at,
    this.updatedBy,
  });

  factory OccurrenceParticipation.fromJson(Map<dynamic, dynamic> json) {
    return OccurrenceParticipation(
      handlerId:
          _parseString(json['handler_id'] ?? json['handlerId'] ?? json['ra']) ??
          '',
      status: OccurrenceParticipationStatus.fromMap(
        _parseString(json['status']),
      ),
      declineReason: _parseString(
        json['decline_reason'] ?? json['declineReason'],
      ),
      at: _parseDateTime(json['at'] ?? json['updated_at']) ?? DateTime.now(),
      updatedBy: _parseString(json['updated_by'] ?? json['updatedBy']),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'handler_id': handlerId,
      'status': status.toMap(),
      if (declineReason != null) 'decline_reason': declineReason,
      'at': Timestamp.fromDate(at),
      if (updatedBy != null) 'updated_by': updatedBy,
    };
  }

  Map<String, dynamic> toHashPayload() {
    return {
      'handler_id': handlerId,
      'status': status.toMap(),
      if (declineReason != null) 'decline_reason': declineReason,
      'at': at.toUtc().toIso8601String(),
      if (updatedBy != null) 'updated_by': updatedBy,
    };
  }

  bool get isIncluded =>
      status == OccurrenceParticipationStatus.included ||
      status == OccurrenceParticipationStatus.accepted;

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
}
