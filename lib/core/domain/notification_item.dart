import 'package:cloud_firestore/cloud_firestore.dart';

enum NotificationType {
  vehicleCrewInvitation,
  vehicleCrewInvitationAccepted,
  vehicleCrewInvitationDeclined,
  occurrenceParticipationRequested,
  occurrenceParticipationAccepted,
  occurrenceParticipationDeclined,
  signatureRequested,
  signatureCompleted,
  signatureDeclined,
  correctionRequested,
  deadlineWarning,
  occurrenceFinalized,
  amendmentCreated,
  trainingPromotionRequested,
  trainingPromotionApproved,
  trainingPromotionRejected,
  trainingBonusMilestoneAvailable,
  shiftStartReminder,
  shiftEndReminder,
  shiftOverdueReminder;

  String toMap() => switch (this) {
    vehicleCrewInvitation => 'vehicle_crew_invitation',
    vehicleCrewInvitationAccepted => 'vehicle_crew_invitation_accepted',
    vehicleCrewInvitationDeclined => 'vehicle_crew_invitation_declined',
    occurrenceParticipationRequested => 'occurrence_participation_requested',
    occurrenceParticipationAccepted => 'occurrence_participation_accepted',
    occurrenceParticipationDeclined => 'occurrence_participation_declined',
    signatureRequested => 'signature_requested',
    signatureCompleted => 'signature_completed',
    signatureDeclined => 'signature_declined',
    correctionRequested => 'correction_requested',
    deadlineWarning => 'deadline_warning',
    occurrenceFinalized => 'occurrence_finalized',
    amendmentCreated => 'amendment_created',
    trainingPromotionRequested => 'training_promotion_requested',
    trainingPromotionApproved => 'training_promotion_approved',
    trainingPromotionRejected => 'training_promotion_rejected',
    trainingBonusMilestoneAvailable => 'training_bonus_milestone_available',
    shiftStartReminder => 'shift_start_reminder',
    shiftEndReminder => 'shift_end_reminder',
    shiftOverdueReminder => 'shift_overdue_reminder',
  };

  static NotificationType fromMap(String? value) {
    final normalized = value?.trim().toLowerCase();
    if (normalized == null || normalized.isEmpty) {
      return NotificationType.signatureRequested;
    }
    if (normalized == 'vehicle_crew_invitation') {
      return NotificationType.vehicleCrewInvitation;
    }
    if (normalized == 'vehicle_crew_invitation_accepted') {
      return NotificationType.vehicleCrewInvitationAccepted;
    }
    if (normalized == 'vehicle_crew_invitation_declined') {
      return NotificationType.vehicleCrewInvitationDeclined;
    }
    if (normalized == 'occurrence_participation_requested') {
      return NotificationType.occurrenceParticipationRequested;
    }
    if (normalized == 'occurrence_participation_accepted') {
      return NotificationType.occurrenceParticipationAccepted;
    }
    if (normalized == 'occurrence_participation_declined') {
      return NotificationType.occurrenceParticipationDeclined;
    }
    if (normalized == 'signature_requested') {
      return NotificationType.signatureRequested;
    }
    if (normalized == 'signature_completed') {
      return NotificationType.signatureCompleted;
    }
    if (normalized == 'signature_declined') {
      return NotificationType.signatureDeclined;
    }
    if (normalized == 'correction_requested') {
      return NotificationType.correctionRequested;
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
    if (normalized == 'training_promotion_requested') {
      return NotificationType.trainingPromotionRequested;
    }
    if (normalized == 'training_promotion_approved') {
      return NotificationType.trainingPromotionApproved;
    }
    if (normalized == 'training_promotion_rejected') {
      return NotificationType.trainingPromotionRejected;
    }
    if (normalized == 'training_bonus_milestone_available') {
      return NotificationType.trainingBonusMilestoneAvailable;
    }
    if (normalized == 'shift_start_reminder') {
      return NotificationType.shiftStartReminder;
    }
    if (normalized == 'shift_end_reminder') {
      return NotificationType.shiftEndReminder;
    }
    if (normalized == 'shift_overdue_reminder' ||
        normalized == 'shift_open_reminder') {
      return NotificationType.shiftOverdueReminder;
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
  final DateTime? resolvedAt;
  final DateTime? archivedAt;
  final bool actionRequired;
  final String? targetScreen;
  final String? additionalData;
  final String? promotionRequestId;
  final String? dogId;
  final String? dogName;
  final String? modality;
  final String? moduleId;
  final String? moduleName;
  final String? milestoneId;
  final String? milestoneLabel;
  final String? decisionReason;

  NotificationItem({
    required this.id,
    required this.type,
    required this.occurrenceId,
    required this.occurrenceTitle,
    required this.createdAt,
    this.readAt,
    this.resolvedAt,
    this.archivedAt,
    this.actionRequired = false,
    this.targetScreen,
    this.additionalData,
    this.promotionRequestId,
    this.dogId,
    this.dogName,
    this.modality,
    this.moduleId,
    this.moduleName,
    this.milestoneId,
    this.milestoneLabel,
    this.decisionReason,
  });

  factory NotificationItem.fromJson(Map<String, dynamic> json, String id) {
    return NotificationItem(
      id: id,
      type: NotificationType.fromMap(json['type']),
      occurrenceId: _stringValue(json['occurrence_id']) ?? '',
      occurrenceTitle: _stringValue(json['occurrence_title']) ?? '',
      createdAt: _dateValue(json['created_at']) ?? DateTime.now(),
      readAt: _dateValue(json['read_at']),
      resolvedAt: _dateValue(json['resolved_at']),
      archivedAt: _dateValue(json['archived_at']),
      actionRequired: _boolValue(json['action_required']),
      targetScreen: _stringValue(json['target_screen']),
      additionalData: _stringValue(json['additional_data']),
      promotionRequestId: _stringValue(json['promotion_request_id']),
      dogId: _stringValue(json['dog_id']),
      dogName: _stringValue(json['dog_name']),
      modality: _stringValue(json['modality']),
      moduleId: _stringValue(json['module_id']),
      moduleName: _stringValue(json['module_name']),
      milestoneId: _stringValue(json['milestone_id']),
      milestoneLabel: _stringValue(json['milestone_label']),
      decisionReason: _stringValue(json['decision_reason']),
    );
  }

  Map<String, dynamic> toJson() {
    final data = <String, dynamic>{
      'type': type.toMap(),
      'occurrence_id': occurrenceId,
      'occurrence_title': occurrenceTitle,
      'created_at': Timestamp.fromDate(createdAt),
      'read_at': readAt != null ? Timestamp.fromDate(readAt!) : null,
      'action_required': actionRequired,
      'additional_data': additionalData,
    };
    if (resolvedAt != null) {
      data['resolved_at'] = Timestamp.fromDate(resolvedAt!);
    }
    if (archivedAt != null) {
      data['archived_at'] = Timestamp.fromDate(archivedAt!);
    }
    if (targetScreen != null) data['target_screen'] = targetScreen;
    if (promotionRequestId != null) {
      data['promotion_request_id'] = promotionRequestId;
    }
    if (dogId != null) data['dog_id'] = dogId;
    if (dogName != null) data['dog_name'] = dogName;
    if (modality != null) data['modality'] = modality;
    if (moduleId != null) data['module_id'] = moduleId;
    if (moduleName != null) data['module_name'] = moduleName;
    if (milestoneId != null) data['milestone_id'] = milestoneId;
    if (milestoneLabel != null) data['milestone_label'] = milestoneLabel;
    if (decisionReason != null) data['decision_reason'] = decisionReason;
    return data;
  }

  NotificationItem markAsRead() {
    return NotificationItem(
      id: id,
      type: type,
      occurrenceId: occurrenceId,
      occurrenceTitle: occurrenceTitle,
      createdAt: createdAt,
      readAt: DateTime.now(),
      resolvedAt: resolvedAt,
      archivedAt: archivedAt,
      actionRequired: actionRequired,
      targetScreen: targetScreen,
      additionalData: additionalData,
      promotionRequestId: promotionRequestId,
      dogId: dogId,
      dogName: dogName,
      modality: modality,
      moduleId: moduleId,
      moduleName: moduleName,
      milestoneId: milestoneId,
      milestoneLabel: milestoneLabel,
      decisionReason: decisionReason,
    );
  }

  bool get isUnread => readAt == null;
  bool get isResolved => resolvedAt != null;
  bool get isArchived => archivedAt != null;

  /// Pendencia real para badge/tela: requer acao e ainda nao foi resolvida.
  ///
  /// Nao depende de `readAt`: marcar como lida so tira realce visual.
  /// Nao depende de `archivedAt`: pendencia aberta nao deve ser arquivavel.
  bool get isOpenAction => actionRequired && resolvedAt == null;

  bool get isNotice => !isOpenAction;
  bool get canBeArchived => !isOpenAction;

  String? get vehicleCrewId => _firstNonEmpty([additionalData, occurrenceId]);

  String? get resolvedPromotionRequestId => _firstNonEmpty([
    promotionRequestId,
    type == NotificationType.trainingPromotionRequested ? additionalData : null,
  ]);

  bool get isVehicleCrewNotification => switch (type) {
    NotificationType.vehicleCrewInvitation ||
    NotificationType.vehicleCrewInvitationAccepted ||
    NotificationType.vehicleCrewInvitationDeclined => true,
    _ => false,
  };

  bool get isTrainingPromotionNotification => switch (type) {
    NotificationType.trainingPromotionRequested ||
    NotificationType.trainingPromotionApproved ||
    NotificationType.trainingPromotionRejected ||
    NotificationType.trainingBonusMilestoneAvailable => true,
    _ => false,
  };

  bool get isShiftReminderNotification => switch (type) {
    NotificationType.shiftStartReminder ||
    NotificationType.shiftEndReminder ||
    NotificationType.shiftOverdueReminder => true,
    _ => false,
  };

  static DateTime? _dateValue(Object? value) {
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    return null;
  }

  static bool _boolValue(Object? value) {
    if (value is bool) return value;
    if (value is num) return value != 0;
    if (value is String) {
      final normalized = value.trim().toLowerCase();
      return normalized == 'true' || normalized == '1' || normalized == 'yes';
    }
    return false;
  }

  static String? _stringValue(Object? value) {
    final text = value?.toString().trim();
    if (text == null || text.isEmpty) return null;
    return text;
  }

  static String? _firstNonEmpty(Iterable<String?> values) {
    for (final value in values) {
      final text = _stringValue(value);
      if (text != null) return text;
    }
    return null;
  }
}
