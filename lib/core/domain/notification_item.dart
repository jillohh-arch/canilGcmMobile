import 'package:cloud_firestore/cloud_firestore.dart';

enum NotificationType {
  signatureRequested,
  signatureCompleted,
  deadlineWarning,
  occurrenceFinalized,
  amendmentCreated;

  String toMap() => switch (this) {
        signatureRequested => 'signature_requested',
        signatureCompleted => 'signature_completed',
        deadlineWarning => 'deadline_warning',
        occurrenceFinalized => 'occurrence_finalized',
        amendmentCreated => 'amendment_created',
      };

  static NotificationType fromMap(String? value) {
    final normalized = value?.trim().toLowerCase();
    if (normalized == null || normalized.isEmpty) {
      return NotificationType.signatureRequested;
    }
    if (normalized == 'signature_requested') {
      return NotificationType.signatureRequested;
    }
    if (normalized == 'signature_completed') {
      return NotificationType.signatureCompleted;
    }
    if (normalized == 'deadline_warning') {
      return NotificationType.deadlineWarning;
    }
    if (normalized == 'occurrence_finalized') {
      return NotificationType.occurrenceFinalized;
    }
    if (normalized == 'amendment_created') {
      return NotificationType.amendmentCreated;
    }
    return NotificationType.signatureRequested;
  }
}

class NotificationItem {
  final String id;
  final NotificationType type;
  final String occurrenceId;
  final String occurrenceTitle;
  final DateTime createdAt;
  DateTime? readAt;
  final String? additionalData; // Para dados extras como handlerId, etc.

  NotificationItem({
    required this.id,
    required this.type,
    required this.occurrenceId,
    required this.occurrenceTitle,
    required this.createdAt,
    this.readAt,
    this.additionalData,
  });

  factory NotificationItem.fromJson(Map<String, dynamic> json, String id) {
    return NotificationItem(
      id: id,
      type: NotificationType.fromMap(json['type']),
      occurrenceId: json['occurrence_id'] ?? '',
      occurrenceTitle: json['occurrence_title'] ?? '',
      createdAt: json['created_at']?.toDate() ?? DateTime.now(),
      readAt: json['read_at']?.toDate(),
      additionalData: json['additional_data'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'type': type.toMap(),
      'occurrence_id': occurrenceId,
      'occurrence_title': occurrenceTitle,
      'created_at': Timestamp.fromDate(createdAt),
      'read_at': readAt != null ? Timestamp.fromDate(readAt!) : null,
      'additional_data': additionalData,
    };
  }

  NotificationItem markAsRead() {
    return NotificationItem(
      id: id,
      type: type,
      occurrenceId: occurrenceId,
      occurrenceTitle: occurrenceTitle,
      createdAt: createdAt,
      readAt: DateTime.now(),
      additionalData: additionalData,
    );
  }

  bool get isUnread => readAt == null;
}