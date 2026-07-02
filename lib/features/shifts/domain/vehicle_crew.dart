import 'package:cloud_firestore/cloud_firestore.dart';

/// Papel de um membro dentro de uma guarnição.
/// Used for crew function assignment validation in ShiftService
/// and display in UI.
enum CrewRole {
  motorista('motorista'),
  encarregado('encarregado'),
  auxiliar_1('auxiliar_1'),
  auxiliar_2('auxiliar_2'),
  k9('k9');

  const CrewRole(this.value);
  final String value;

  static CrewRole? fromString(String? value) {
    if (value == null) return null;
    try {
      return CrewRole.values.firstWhere((r) => r.value == value);
    } catch (_) {
      return null;
    }
  }

  static const List<String> valuesList = [
    'motorista',
    'encarregado',
    'auxiliar_1',
    'auxiliar_2',
    'k9',
  ];

  static bool isValid(String? value) =>
      value != null && valuesList.contains(value);
}

class VehicleCrewMember {
  final String handlerId;
  final String? authUid;
  final String? handlerEmail;
  final String? name;
  final String role; // 'motorista' | 'encarregado' | 'auxiliar_1' | 'auxiliar_2' | 'k9'
  final String status; // 'active' | 'ended' | 'pending' | 'declined'
  final DateTime joinedAt;
  final DateTime? leftAt;
  final DateTime? invitedAt;
  final DateTime? respondedAt;
  final String? invitedBy;
  final String? declineReason;
  final String? dogId; // snapshot do cão no momento da saída

  const VehicleCrewMember({
    required this.handlerId,
    this.authUid,
    this.handlerEmail,
    this.name,
    required this.role,
    required this.status,
    required this.joinedAt,
    this.leftAt,
    this.invitedAt,
    this.respondedAt,
    this.invitedBy,
    this.declineReason,
    this.dogId,
  });

  factory VehicleCrewMember.fromJson(Map<dynamic, dynamic> json) {
    return VehicleCrewMember(
      handlerId: _parseString(json['handler_id'] ?? json['handlerId']) ?? '',
      authUid: _parseString(json['auth_uid'] ?? json['authUid']),
      handlerEmail: _parseString(json['handler_email'] ?? json['handlerEmail']),
      name: _parseString(json['name']),
      role: _parseString(json['role']) ?? '',
      status: _parseString(json['status']) ?? 'pending',
      joinedAt:
          _parseDate(json['joined_at'] ?? json['joinedAt']) ?? DateTime.now(),
      leftAt: _parseDate(json['left_at'] ?? json['leftAt']),
      invitedAt: _parseDate(json['invited_at'] ?? json['invitedAt']),
      respondedAt: _parseDate(json['responded_at'] ?? json['respondedAt']),
      invitedBy: _parseString(json['invited_by'] ?? json['invitedBy']),
      declineReason: _parseString(
        json['decline_reason'] ?? json['declineReason'],
      ),
      dogId: _parseString(json['dog_id']),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'handler_id': handlerId,
      if (authUid != null) 'auth_uid': authUid,
      if (handlerEmail != null) 'handler_email': handlerEmail,
      if (name != null) 'name': name,
      'role': role,
      'status': status,
      'joined_at': Timestamp.fromDate(joinedAt),
      if (leftAt != null) 'left_at': Timestamp.fromDate(leftAt!),
      if (invitedAt != null) 'invited_at': Timestamp.fromDate(invitedAt!),
      if (respondedAt != null) 'responded_at': Timestamp.fromDate(respondedAt!),
      if (invitedBy != null) 'invited_by': invitedBy,
      if (declineReason != null) 'decline_reason': declineReason,
      if (dogId != null) 'dog_id': dogId,
    };
  }

  bool get isActive => status == 'active';
  bool get isPending => status == 'pending';
  bool get isDeclined => status == 'declined';
  bool get isEnded => status == 'ended';
  bool get hasLeft => leftAt != null || isEnded;

  /// Retorna o papel legado (titular/membro) para compatibilidade de leitura.
  bool get isLegacyTitular =>
      role == 'titular' || status == 'titular';

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
  final DateTime? endedAt;
  final DateTime updatedAt;
  final List<Map<String, dynamic>>? dogChanges;

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
    this.endedAt,
    required this.updatedAt,
    this.dogChanges,
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
      endedAt: _parseDate(json['ended_at']),
      updatedAt: _parseDate(json['updated_at']) ?? DateTime.now(),
      dogChanges: (json['dog_changes'] as List<dynamic>?)
          ?.map((e) => Map<String, dynamic>.from(e as Map))
          .toList(),
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
