class UserModel {
  final String ra;
  final String name; // Nome real do operador
  final String callsign; // Nome de guerra
  final String unit;
  final String accessLevel; // 'Admin' ou 'Condutor'
  final String? photoUrl;

  UserModel({
    required this.ra,
    this.name = '',
    required this.callsign,
    required this.unit,
    this.accessLevel = 'Condutor',
    this.photoUrl,
  });

  factory UserModel.fromJson(Map<String, dynamic> json) {
    return UserModel(
      ra: json['ra'] ?? '',
      name: json['name'] ?? '',
      callsign: json['callsign'] ?? '',
      unit: json['unit'] ?? '',
      accessLevel: json['accessLevel'] ?? 'Condutor',
      photoUrl: json['photoUrl'],
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
    };
  }

  UserModel copyWith({
    String? ra,
    String? name,
    String? callsign,
    String? unit,
    String? accessLevel,
    Object? photoUrl = _sentinel,
  }) {
    return UserModel(
      ra: ra ?? this.ra,
      name: name ?? this.name,
      callsign: callsign ?? this.callsign,
      unit: unit ?? this.unit,
      accessLevel: accessLevel ?? this.accessLevel,
      photoUrl: photoUrl == _sentinel ? this.photoUrl : photoUrl as String?,
    );
  }

  static const _sentinel = Object();
}
