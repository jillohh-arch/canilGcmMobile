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
  final String? dogId;
  final String? dogName;
  final String? dogMatricula;
  final String? dogBreed;
  final TeamRole role;
  final DateTime addedAt;
  final String addedBy;
  final String? addedByUid;

  const OccurrenceTeamMember({
    required this.handlerId,
    this.authUid,
    this.handlerEmail,
    this.displayName,
    this.dogId,
    this.dogName,
    this.dogMatricula,
    this.dogBreed,
    required this.role,
    required this.addedAt,
    required this.addedBy,
    this.addedByUid,
  });

  factory OccurrenceTeamMember.fromJson(Map<dynamic, dynamic> json) {
    return OccurrenceTeamMember(
      handlerId:
          _parseString(
            json['handler_id'] ??
                json['handlerId'] ??
                json['handler_ra'] ??
                json['ra'],
          ) ??
          '',
      authUid: _parseString(json['auth_uid'] ?? json['authUid']),
      handlerEmail: _parseString(json['handler_email'] ?? json['handlerEmail']),
      displayName: _parseString(
        json['display_name'] ??
            json['displayName'] ??
            json['handler_name'] ??
            json['name'],
      ),
      dogId: _parseString(json['dog_id'] ?? json['dogId']),
      dogName: _parseString(json['dog_name'] ?? json['dogName']),
      dogMatricula: _parseString(
        json['dog_matricula'] ?? json['dogMatricula'] ?? json['matricula'],
      ),
      dogBreed: _parseString(json['dog_breed'] ?? json['dogBreed']),
      role: TeamRole.fromMap(_parseString(json['role'])),
      addedAt:
          _parseDateTime(json['added_at'] ?? json['addedAt']) ?? DateTime.now(),
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
      if (dogId != null) 'dog_id': dogId,
      if (dogName != null) 'dog_name': dogName,
      if (dogMatricula != null) 'dog_matricula': dogMatricula,
      if (dogBreed != null) 'dog_breed': dogBreed,
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
      if (dogId != null) 'dog_id': dogId,
      if (dogName != null) 'dog_name': dogName,
      if (dogMatricula != null) 'dog_matricula': dogMatricula,
      if (dogBreed != null) 'dog_breed': dogBreed,
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
    String? dogId,
    String? dogName,
    String? dogMatricula,
    String? dogBreed,
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
      dogId: dogId ?? this.dogId,
      dogName: dogName ?? this.dogName,
      dogMatricula: dogMatricula ?? this.dogMatricula,
      dogBreed: dogBreed ?? this.dogBreed,
      role: role ?? this.role,
      addedAt: addedAt ?? this.addedAt,
      addedBy: addedBy ?? this.addedBy,
      addedByUid: addedByUid ?? this.addedByUid,
    );
  }

  bool get hasServiceDog => dogId?.trim().isNotEmpty == true;

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
