import 'package:cloud_firestore/cloud_firestore.dart';

class ActiveShiftSession {
  final String? shiftId;
  final String handlerId;
  final String dogId;
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
  final String status;

  const ActiveShiftSession({
    this.shiftId,
    required this.handlerId,
    required this.dogId,
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
    this.status = 'active',
  });

  factory ActiveShiftSession.fromJson(Map<String, dynamic> json) {
    return ActiveShiftSession(
      shiftId: json['shiftId'] as String?,
      handlerId: json['handlerId'] as String? ?? '',
      dogId: json['dogId'] as String? ?? '',
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
      status: json['status'] as String? ?? 'active',
    );
  }

  ActiveShiftSession copyWith({
    String? shiftId,
    String? handlerId,
    String? dogId,
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
    String? status,
  }) {
    return ActiveShiftSession(
      shiftId: shiftId ?? this.shiftId,
      handlerId: handlerId ?? this.handlerId,
      dogId: dogId ?? this.dogId,
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
      status: status ?? this.status,
    );
  }

  bool get isActive => status == 'active' && dogId.isNotEmpty;
  bool get hasVehicle => vehicleId?.trim().isNotEmpty == true;

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
