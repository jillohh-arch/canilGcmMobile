class ShiftGroupModel {
  final String id;
  final String name;
  final String type; // 'operational' | 'administrative'
  final int expectedStartHour;
  final int expectedEndHour;
  final String municipality;

  ShiftGroupModel({
    required this.id,
    required this.name,
    required this.type,
    required this.expectedStartHour,
    required this.expectedEndHour,
    required this.municipality,
  });

  factory ShiftGroupModel.fromJson(Map<String, dynamic> json, String id) {
    return ShiftGroupModel(
      id: id,
      name: json['name'] ?? '',
      type: json['type'] ?? 'operational',
      expectedStartHour: json['expectedStartHour'] ?? 7,
      expectedEndHour: json['expectedEndHour'] ?? 19,
      municipality: json['municipality'] ?? '',
    );
  }

  String get scheduleDisplay {
    final start = expectedStartHour.toString().padLeft(2, '0');
    final end = expectedEndHour.toString().padLeft(2, '0');
    return '$start:00 - $end:00';
  }
}

class ShiftAssignmentModel {
  final String id;
  final String userId;
  final String shiftGroupId;
  final int rotationOffset;

  ShiftAssignmentModel({
    required this.id,
    required this.userId,
    required this.shiftGroupId,
    required this.rotationOffset,
  });

  factory ShiftAssignmentModel.fromJson(String id, Map<String, dynamic> json) {
    return ShiftAssignmentModel(
      id: id,
      userId: json['userId'] ?? '',
      shiftGroupId: json['shiftGroupId'] ?? '',
      rotationOffset: json['rotationOffset'] ?? 0,
    );
  }
}
