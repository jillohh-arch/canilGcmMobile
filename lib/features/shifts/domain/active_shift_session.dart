import 'package:cloud_firestore/cloud_firestore.dart';

class ActiveShiftSession {
  final String? shiftId;
  final String handlerId;
  final String dogId;
  final DateTime startedAt;
  final DateTime? updatedAt;
  final DateTime? endedAt;
  final DateTime? lastDogSwitchAt;
  final String status;

  const ActiveShiftSession({
    this.shiftId,
    required this.handlerId,
    required this.dogId,
    required this.startedAt,
    this.updatedAt,
    this.endedAt,
    this.lastDogSwitchAt,
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
      status: status ?? this.status,
    );
  }

  bool get isActive => status == 'active' && dogId.isNotEmpty;

  static DateTime? _parseDate(dynamic value) {
    if (value is Timestamp) return value.toDate();
    if (value is String && value.isNotEmpty) return DateTime.tryParse(value);
    return null;
  }
}
