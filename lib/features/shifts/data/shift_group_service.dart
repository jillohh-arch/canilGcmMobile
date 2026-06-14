import 'package:cloud_firestore/cloud_firestore.dart';

import 'package:canil_gcm/features/shifts/domain/shift_group_model.dart';

class ShiftGroupService {
  ShiftGroupService({FirebaseFirestore? firestore})
      : _db = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _db;

  Future<ShiftGroupModel?> getShiftGroup(String groupId) async {
    final doc = await _db.collection('shift_groups').doc(groupId).get();
    if (!doc.exists) return null;
    return ShiftGroupModel.fromJson(doc.data()!, doc.id);
  }

  Future<ShiftAssignmentModel?> getUserShiftAssignment(String userId) async {
    final snapshot = await _db
        .collection('user_shift_assignments')
        .where('userId', isEqualTo: userId)
        .where('active', isEqualTo: true)
        .limit(1)
        .get();

    if (snapshot.docs.isEmpty) return null;
    final doc = snapshot.docs.first;
    return ShiftAssignmentModel.fromJson(doc.id, doc.data());
  }

  Future<ShiftGroupModel?> getUserShiftGroup(String userId) async {
    final assignment = await getUserShiftAssignment(userId);
    if (assignment == null) return null;
    return getShiftGroup(assignment.shiftGroupId);
  }

  /// Returns the user's shift info enriched from both assignment and group data
  Future<UserShiftInfo?> getUserShiftInfo(String userId) async {
    final assignment = await getUserShiftAssignment(userId);
    if (assignment == null) return null;

    final group = await getShiftGroup(assignment.shiftGroupId);
    if (group == null) return null;

    return UserShiftInfo(
      groupId: group.id,
      groupName: group.name,
      groupType: group.type,
      expectedStartHour: group.expectedStartHour,
      expectedEndHour: group.expectedEndHour,
      rotationOffset: assignment.rotationOffset,
    );
  }

  Stream<ShiftAssignmentModel?> watchUserShiftAssignment(String userId) {
    return _db
        .collection('user_shift_assignments')
        .where('userId', isEqualTo: userId)
        .where('active', isEqualTo: true)
        .limit(1)
        .snapshots()
        .map((snapshot) {
      if (snapshot.docs.isEmpty) return null;
      return ShiftAssignmentModel.fromJson(
        snapshot.docs.first.id,
        snapshot.docs.first.data(),
      );
    });
  }
}

/// Enriched shift info combining assignment + group data
class UserShiftInfo {
  final String groupId;
  final String groupName;
  final String groupType;
  final int expectedStartHour;
  final int expectedEndHour;
  final int rotationOffset;

  UserShiftInfo({
    required this.groupId,
    required this.groupName,
    required this.groupType,
    required this.expectedStartHour,
    required this.expectedEndHour,
    required this.rotationOffset,
  });

  String get scheduleDisplay {
    final start = expectedStartHour.toString().padLeft(2, '0');
    final end = expectedEndHour.toString().padLeft(2, '0');
    return '$start:00 - $end:00';
  }

  /// Returns true if current time is within expected shift hours
  bool isWithinShiftHours() {
    final now = DateTime.now();
    final currentHour = now.hour;

    if (expectedStartHour < expectedEndHour) {
      // Normal day shift (e.g., 7-19)
      return currentHour >= expectedStartHour && currentHour < expectedEndHour;
    } else {
      // Overnight shift (e.g., 19-7)
      return currentHour >= expectedStartHour || currentHour < expectedEndHour;
    }
  }

  /// Returns true if it's time to start shift (passed expected start by more than 30 min)
  bool shouldStartShift({int graceMinutes = 30}) {
    final now = DateTime.now();
    final currentHour = now.hour;
    final currentMinute = now.minute;

    // Check if we're past the expected start time + grace period
    if (currentHour > expectedStartHour) return true;
    if (currentHour == expectedStartHour && currentMinute > graceMinutes) return true;

    // For overnight shifts, also check if we're close to the end
    if (expectedStartHour > expectedEndHour) {
      // We're in the "next day" part of overnight
      if (currentHour < expectedEndHour) return true;
    }

    return false;
  }
}
