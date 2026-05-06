class UserModel {
  final String ra;
  final String name; // Nome real do operador
  final String callsign; // Nome de guerra
  final String unit;
  final String accessLevel; // 'Admin' ou 'Condutor'
  final String? photoUrl;
  final List<String> userBadges; // Gamification V1
  final int xp; // Pontos de experiência

  UserModel({
    required this.ra,
    this.name = '',
    required this.callsign,
    required this.unit,
    this.accessLevel = 'Condutor',
    this.photoUrl,
    this.userBadges = const [],
    this.xp = 0,
  });

  factory UserModel.fromJson(Map<String, dynamic> json) {
    return UserModel(
      ra: json['ra'] ?? '',
      name: json['name'] ?? '',
      callsign: json['callsign'] ?? '',
      unit: json['unit'] ?? '',
      accessLevel: json['accessLevel'] ?? 'Condutor',
      photoUrl: json['photoUrl'],
      userBadges: json['userBadges'] != null
          ? List<String>.from(json['userBadges'])
          : [],
      xp: json['xp'] ?? 0,
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
      'userBadges': userBadges,
      'xp': xp,
    };
  }

  UserModel copyWith({
    String? ra,
    String? name,
    String? callsign,
    String? unit,
    String? accessLevel,
    Object? photoUrl = _sentinel,
    List<String>? userBadges,
    int? xp,
  }) {
    return UserModel(
      ra: ra ?? this.ra,
      name: name ?? this.name,
      callsign: callsign ?? this.callsign,
      unit: unit ?? this.unit,
      accessLevel: accessLevel ?? this.accessLevel,
      photoUrl: photoUrl == _sentinel ? this.photoUrl : photoUrl as String?,
      userBadges: userBadges ?? this.userBadges,
      xp: xp ?? this.xp,
    );
  }

  static const _sentinel = Object();
}
