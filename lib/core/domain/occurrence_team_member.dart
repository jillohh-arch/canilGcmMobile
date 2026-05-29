import 'package:cloud_firestore/cloud_firestore.dart';

enum TeamRole {
  titular,
  integrante;

  String toMap() => switch (this) {
        titular => 'titular',
        integrante => 'integrante',
      };

  static TeamRole fromMap(String? value) {
    final normalized = value?.trim().toLowerCase();
    if (normalized == 'titular') {
      return TeamRole.titular;
    }
    return TeamRole.integrante;
  }
}

class OccurrenceTeamMember {
  /// RA do condutor. Esta e a identidade operacional canonica da Frente C.
  final String handlerId;

  /// UID tecnico do Firebase Auth, usado apenas como evidencia auxiliar.
  final String? authUid;
  final String? handlerEmail;
  final String? displayName;
  final TeamRole role;
  final DateTime addedAt;
  final String addedBy;
  final String? addedByUid;

  const OccurrenceTeamMember({
    required this.handlerId,
    this.authUid,
    this.handlerEmail,
    this.displayName,
    required this.role,
    required this.addedAt,
    required this.addedBy,
    this.addedByUid,
  });

  factory OccurrenceTeamMember.fromJson(Map<dynamic, dynamic> json) {
    return OccurrenceTeamMember(
      handlerId: _parseString(json['handler_id'] ?? json['handlerId']) ?? '',
      authUid: _parseString(json['auth_uid'] ?? json['authUid']),
      handlerEmail: _parseString(json['handler_email'] ?? json['handlerEmail']),
      displayName: _parseString(json['display_name'] ?? json['displayName']),
      role: TeamRole.fromMap(_parseString(json['role'])),
      addedAt: _parseDateTime(json['added_at'] ?? json['addedAt']) ??
          DateTime.now(),
      addedBy: _parseString(json['added_by'] ?? json['addedBy']) ?? '',
      addedByUid: _parseString(json['added_by_uid'] ?? json['addedByUid']),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'handler_id': handlerId,
      if (authUid != null) 'auth_uid': authUid,
      if (handlerEmail != null) 'handler_email': handlerEmail,
      if (displayName != null) 'display_name': displayName,
      'role': role.toMap(),
      'added_at': Timestamp.fromDate(addedAt),
      'added_by': addedBy,
      if (addedByUid != null) 'added_by_uid': addedByUid,
    };
  }

  Map<String, dynamic> toHashPayload() {
    return {
      'handler_id': handlerId,
      if (authUid != null) 'auth_uid': authUid,
      if (handlerEmail != null) 'handler_email': handlerEmail,
      if (displayName != null) 'display_name': displayName,
      'role': role.toMap(),
      'added_at': addedAt.toUtc().toIso8601String(),
      'added_by': addedBy,
      if (addedByUid != null) 'added_by_uid': addedByUid,
    };
  }

  OccurrenceTeamMember copyWith({
    String? handlerId,
    String? authUid,
    String? handlerEmail,
    String? displayName,
    TeamRole? role,
    DateTime? addedAt,
    String? addedBy,
    String? addedByUid,
  }) {
    return OccurrenceTeamMember(
      handlerId: handlerId ?? this.handlerId,
      authUid: authUid ?? this.authUid,
      handlerEmail: handlerEmail ?? this.handlerEmail,
      displayName: displayName ?? this.displayName,
      role: role ?? this.role,
      addedAt: addedAt ?? this.addedAt,
      addedBy: addedBy ?? this.addedBy,
      addedByUid: addedByUid ?? this.addedByUid,
    );
  }

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
