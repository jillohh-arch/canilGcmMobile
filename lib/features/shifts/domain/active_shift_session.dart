import 'package:cloud_firestore/cloud_firestore.dart';

class ActiveShiftSession {
  final String? shiftId;
  final String handlerId;
  final String? authUid;
  final String? handlerEmail;
  final String dogId;
  final String? serviceDogId;
  final DateTime startedAt;
  final DateTime? updatedAt;
  final DateTime? endedAt;
  final DateTime? lastDogSwitchAt;
  final String? vehicleId;
  final String? vehicleLabel;
  final String? vehiclePrefix;
  final String? vehicleModel;
  final String? vehicleUnit;
  final DateTime? vehicleJoinedAt;
  final String? vehicleCrewId;
  final String? crewRole;
  final String? crewStatus;
  final String? shiftGroupId;
  final String? shiftGroupCode;
  final String? shiftGroupLabel;
  final String status;

  const ActiveShiftSession({
    this.shiftId,
    required this.handlerId,
    this.authUid,
    this.handlerEmail,
    required this.dogId,
    this.serviceDogId,
    required this.startedAt,
    this.updatedAt,
    this.endedAt,
    this.lastDogSwitchAt,
    this.vehicleId,
    this.vehicleLabel,
    this.vehiclePrefix,
    this.vehicleModel,
    this.vehicleUnit,
    this.vehicleJoinedAt,
    this.vehicleCrewId,
    this.crewRole,
    this.crewStatus,
    this.shiftGroupId,
    this.shiftGroupCode,
    this.shiftGroupLabel,
    this.status = 'active',
  });

  factory ActiveShiftSession.fromJson(Map<String, dynamic> json) {
    final resolvedDogId = _parseString(
      json['service_dog_id'] ??
          json['serviceDogId'] ??
          json['dogId'] ??
          json['currentDogId'] ??
          json['initialDogId'],
    );

    return ActiveShiftSession(
      shiftId: json['shiftId'] as String?,
      handlerId: json['handlerId'] as String? ?? '',
      authUid: _parseString(json['auth_uid'] ?? json['authUid']),
      handlerEmail: _parseString(json['handler_email'] ?? json['handlerEmail']),
      dogId: resolvedDogId ?? '',
      serviceDogId: resolvedDogId,
      startedAt: _parseDate(json['startedAt']) ?? DateTime.now(),
      updatedAt: _parseDate(json['updatedAt']),
      endedAt: _parseDate(json['endedAt']),
      lastDogSwitchAt: _parseDate(json['lastDogSwitchAt']),
      vehicleId: _parseString(json['vehicle_id'] ?? json['vehicleId']),
      vehicleLabel: _parseString(json['vehicle_label'] ?? json['vehicleLabel']),
      vehiclePrefix: _parseString(
        json['vehicle_prefix'] ?? json['vehiclePrefix'],
      ),
      vehicleModel: _parseString(json['vehicle_model'] ?? json['vehicleModel']),
      vehicleUnit: _parseString(json['vehicle_unit'] ?? json['vehicleUnit']),
      vehicleJoinedAt: _parseDate(
        json['vehicle_joined_at'] ?? json['vehicleJoinedAt'],
      ),
      vehicleCrewId: _parseString(
        json['vehicle_crew_id'] ?? json['vehicleCrewId'] ?? json['crew_id'],
      ),
      crewRole: _parseString(json['crew_role'] ?? json['crewRole']),
      crewStatus: _parseString(json['crew_status'] ?? json['crewStatus']),
      shiftGroupId: _parseString(
        json['shift_group_id'] ?? json['shiftGroupId'],
      ),
      shiftGroupCode: _parseString(
        json['shift_group_code'] ?? json['shiftGroupCode'],
      ),
      shiftGroupLabel: _parseString(
        json['shift_group_label'] ?? json['shiftGroupLabel'],
      ),
      status: json['status'] as String? ?? 'active',
    );
  }

  ActiveShiftSession copyWith({
    String? shiftId,
    String? handlerId,
    String? authUid,
    String? handlerEmail,
    String? dogId,
    String? serviceDogId,
    DateTime? startedAt,
    DateTime? updatedAt,
    DateTime? endedAt,
    DateTime? lastDogSwitchAt,
    String? vehicleId,
    String? vehicleLabel,
    String? vehiclePrefix,
    String? vehicleModel,
    String? vehicleUnit,
    DateTime? vehicleJoinedAt,
    String? vehicleCrewId,
    String? crewRole,
    String? crewStatus,
    String? shiftGroupId,
    String? shiftGroupCode,
    String? shiftGroupLabel,
    String? status,
  }) {
    return ActiveShiftSession(
      shiftId: shiftId ?? this.shiftId,
      handlerId: handlerId ?? this.handlerId,
      authUid: authUid ?? this.authUid,
      handlerEmail: handlerEmail ?? this.handlerEmail,
      dogId: dogId ?? this.dogId,
      serviceDogId: serviceDogId ?? this.serviceDogId,
      startedAt: startedAt ?? this.startedAt,
      updatedAt: updatedAt ?? this.updatedAt,
      endedAt: endedAt ?? this.endedAt,
      lastDogSwitchAt: lastDogSwitchAt ?? this.lastDogSwitchAt,
      vehicleId: vehicleId ?? this.vehicleId,
      vehicleLabel: vehicleLabel ?? this.vehicleLabel,
      vehiclePrefix: vehiclePrefix ?? this.vehiclePrefix,
      vehicleModel: vehicleModel ?? this.vehicleModel,
      vehicleUnit: vehicleUnit ?? this.vehicleUnit,
      vehicleJoinedAt: vehicleJoinedAt ?? this.vehicleJoinedAt,
      vehicleCrewId: vehicleCrewId ?? this.vehicleCrewId,
      crewRole: crewRole ?? this.crewRole,
      crewStatus: crewStatus ?? this.crewStatus,
      shiftGroupId: shiftGroupId ?? this.shiftGroupId,
      shiftGroupCode: shiftGroupCode ?? this.shiftGroupCode,
      shiftGroupLabel: shiftGroupLabel ?? this.shiftGroupLabel,
      status: status ?? this.status,
    );
  }

  bool get isActive => status == 'active';
  bool get hasK9 => effectiveServiceDogId.isNotEmpty;
  bool get hasVehicle => vehicleId?.trim().isNotEmpty == true;
  String get effectiveServiceDogId =>
      serviceDogId?.trim().isNotEmpty == true ? serviceDogId!.trim() : dogId;

  static DateTime? _parseDate(dynamic value) {
    if (value is Timestamp) return value.toDate();
    if (value is String && value.isNotEmpty) return DateTime.tryParse(value);
    return null;
  }

  static String? _parseString(dynamic value) {
    if (value == null) return null;
    final text = value.toString().trim();
    return text.isEmpty ? null : text;
  }
}
