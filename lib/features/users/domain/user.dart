class UserModel {
  final String ra;
  final String name; // Nome real do operador
  final String callsign; // Nome de guerra
  final String unit;
  final String accessLevel; // 'Admin' ou 'Condutor'
  final String? photoUrl;
  final bool isK9Instructor;
  final String? trainingRole;

  UserModel({
    required this.ra,
    this.name = '',
    required this.callsign,
    required this.unit,
    this.accessLevel = 'Condutor',
    this.photoUrl,
    this.isK9Instructor = false,
    this.trainingRole,
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
    );
  }

  static const _sentinel = Object();
}
