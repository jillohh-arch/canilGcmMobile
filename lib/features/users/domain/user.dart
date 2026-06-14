class UserModel {
  final String ra;
  final String name; // Nome real do operador
  final String callsign; // Nome de guerra
  final String unit;
  final String accessLevel; // 'Admin' ou 'Condutor'
  final String? photoUrl;
  final bool isK9Instructor;
  final String? trainingRole;
  final String? shiftGroupId;
  final String? shiftGroupName;
  final int? shiftGroupStartHour;
  final int? shiftGroupEndHour;

  UserModel({
    required this.ra,
    this.name = '',
    required this.callsign,
    required this.unit,
    this.accessLevel = 'Condutor',
    this.photoUrl,
    this.isK9Instructor = false,
    this.trainingRole,
    this.shiftGroupId,
    this.shiftGroupName,
    this.shiftGroupStartHour,
    this.shiftGroupEndHour,
  });

  factory UserModel.fromJson(Map<String, dynamic> json) {
    return UserModel(
      ra: (json['ra'] ?? json['id'] ?? '').toString(),
      name: json['name'] ?? '',
      callsign: json['callsign'] ?? json['callSign'] ?? '',
      unit: json['unit'] ?? '',
      accessLevel: json['accessLevel'] ?? 'Condutor',
      photoUrl: json['photoUrl'] ?? json['image_url'],
      isK9Instructor:
          json['is_k9_instructor'] == true ||
          json['training_role'] == 'instrutor_k9',
      trainingRole: json['training_role'],
      shiftGroupId: json['shift_group_id'],
      shiftGroupName: json['shift_group_name'],
      shiftGroupStartHour: json['shift_group_start_hour'],
      shiftGroupEndHour: json['shift_group_end_hour'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'ra': ra,
      'name': name,
      'callsign': callsign,
      'unit': unit,
      'accessLevel': accessLevel,
      'photoUrl': photoUrl,
      'is_k9_instructor': isK9Instructor,
      'training_role': trainingRole,
      'shift_group_id': shiftGroupId,
      'shift_group_name': shiftGroupName,
      'shift_group_start_hour': shiftGroupStartHour,
      'shift_group_end_hour': shiftGroupEndHour,
    };
  }

  UserModel copyWith({
    String? ra,
    String? name,
    String? callsign,
    String? unit,
    String? accessLevel,
    Object? photoUrl = _sentinel,
    bool? isK9Instructor,
    Object? trainingRole = _sentinel,
    Object? shiftGroupId = _sentinel,
    Object? shiftGroupName = _sentinel,
    Object? shiftGroupStartHour = _sentinel,
    Object? shiftGroupEndHour = _sentinel,
  }) {
    return UserModel(
      ra: ra ?? this.ra,
      name: name ?? this.name,
      callsign: callsign ?? this.callsign,
      unit: unit ?? this.unit,
      accessLevel: accessLevel ?? this.accessLevel,
      photoUrl: photoUrl == _sentinel ? this.photoUrl : photoUrl as String?,
      isK9Instructor: isK9Instructor ?? this.isK9Instructor,
      trainingRole: trainingRole == _sentinel
          ? this.trainingRole
          : trainingRole as String?,
      shiftGroupId: shiftGroupId == _sentinel
          ? this.shiftGroupId
          : shiftGroupId as String?,
      shiftGroupName: shiftGroupName == _sentinel
          ? this.shiftGroupName
          : shiftGroupName as String?,
      shiftGroupStartHour: shiftGroupStartHour == _sentinel
          ? this.shiftGroupStartHour
          : shiftGroupStartHour as int?,
      shiftGroupEndHour: shiftGroupEndHour == _sentinel
          ? this.shiftGroupEndHour
          : shiftGroupEndHour as int?,
    );
  }

  String? get shiftScheduleDisplay {
    if (shiftGroupStartHour == null || shiftGroupEndHour == null) return null;
    final start = shiftGroupStartHour.toString().padLeft(2, '0');
    final end = shiftGroupEndHour.toString().padLeft(2, '0');
    return '$start:00 - $end:00';
  }

  static const _sentinel = Object();
}
