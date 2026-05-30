import 'package:cloud_firestore/cloud_firestore.dart';

class VehicleCrewMember {
  final String handlerId;
  final String? authUid;
  final String? handlerEmail;
  final String role;
  final String status;
  final DateTime joinedAt;
  final DateTime? invitedAt;
  final DateTime? respondedAt;
  final String? invitedBy;
  final String? declineReason;

  const VehicleCrewMember({
    required this.handlerId,
    this.authUid,
    this.handlerEmail,
    required this.role,
    required this.status,
    required this.joinedAt,
    this.invitedAt,
    this.respondedAt,
    this.invitedBy,
    this.declineReason,
  });

  factory VehicleCrewMember.fromJson(Map<dynamic, dynamic> json) {
    return VehicleCrewMember(
      handlerId: _parseString(json['handler_id'] ?? json['handlerId']) ?? '',
      authUid: _parseString(json['auth_uid'] ?? json['authUid']),
      handlerEmail: _parseString(json['handler_email'] ?? json['handlerEmail']),
      role: _parseString(json['role']) ?? 'integrante',
      status: _parseString(json['status']) ?? 'accepted',
      joinedAt:
          _parseDate(json['joined_at'] ?? json['joinedAt']) ?? DateTime.now(),
      invitedAt: _parseDate(json['invited_at'] ?? json['invitedAt']),
      respondedAt: _parseDate(json['responded_at'] ?? json['respondedAt']),
      invitedBy: _parseString(json['invited_by'] ?? json['invitedBy']),
      declineReason: _parseString(
        json['decline_reason'] ?? json['declineReason'],
      ),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'handler_id': handlerId,
      if (authUid != null) 'auth_uid': authUid,
      if (handlerEmail != null) 'handler_email': handlerEmail,
      'role': role,
      'status': status,
      'joined_at': Timestamp.fromDate(joinedAt),
      if (invitedAt != null) 'invited_at': Timestamp.fromDate(invitedAt!),
      if (respondedAt != null) 'responded_at': Timestamp.fromDate(respondedAt!),
      if (invitedBy != null) 'invited_by': invitedBy,
      if (declineReason != null) 'decline_reason': declineReason,
    };
  }

  bool get isActive => status == 'titular' || status == 'accepted';
  bool get isPending => status == 'pending';
  bool get isDeclined => status == 'declined';
  bool get isTitular => role == 'titular' || status == 'titular';

  static DateTime? _parseDate(dynamic value) {
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

class VehicleCrew {
  final String id;
  final String vehicleId;
  final String vehicleLabel;
  final String? vehiclePrefix;
  final String? vehicleModel;
  final String? vehicleUnit;
  final int crewSize;
  final String serviceDogId;
  final String titularHandlerId;
  final bool active;
  final DateTime createdAt;
  final DateTime updatedAt;

  const VehicleCrew({
    required this.id,
    required this.vehicleId,
    required this.vehicleLabel,
    this.vehiclePrefix,
    this.vehicleModel,
    this.vehicleUnit,
    required this.crewSize,
    required this.serviceDogId,
    required this.titularHandlerId,
    required this.active,
    required this.createdAt,
    required this.updatedAt,
  });

  factory VehicleCrew.fromJson(Map<String, dynamic> json, String id) {
    return VehicleCrew(
      id: id,
      vehicleId: _parseString(json['vehicle_id']) ?? id,
      vehicleLabel: _parseString(json['vehicle_label']) ?? id,
      vehiclePrefix: _parseString(json['vehicle_prefix']),
      vehicleModel: _parseString(json['vehicle_model']),
      vehicleUnit: _parseString(json['vehicle_unit']),
      crewSize: _parseInt(json['crew_size']) ?? 1,
      serviceDogId: _parseString(json['service_dog_id']) ?? '',
      titularHandlerId: _parseString(json['titular_handler_id']) ?? '',
      active: _parseBool(json['active']) ?? true,
      createdAt: _parseDate(json['created_at']) ?? DateTime.now(),
      updatedAt: _parseDate(json['updated_at']) ?? DateTime.now(),
    );
  }

  static DateTime? _parseDate(dynamic value) {
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

  static int? _parseInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.round();
    if (value is String) return int.tryParse(value);
    return null;
  }

  static bool? _parseBool(dynamic value) {
    if (value is bool) return value;
    if (value is String) return value.trim().toLowerCase() == 'true';
    return null;
  }
}
