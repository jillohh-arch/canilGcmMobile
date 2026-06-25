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
    for (final field in const [
      'user_ra',
      'ra',
      'handlerId',
      'userId',
      'user_id',
    ]) {
      final snapshot = await _db
          .collection('user_shift_assignments')
          .where(field, isEqualTo: userId)
          .where('active', isEqualTo: true)
          .limit(1)
          .get();

      if (snapshot.docs.isNotEmpty) {
        final doc = snapshot.docs.first;
        return ShiftAssignmentModel.fromJson(doc.id, doc.data());
      }
    }

    final doc = await _db
        .collection('user_shift_assignments')
        .doc(userId)
        .get();
    if (!doc.exists || doc.data()?['active'] == false) return null;
    return ShiftAssignmentModel.fromJson(doc.id, doc.data()!);
  }

  Future<ShiftGroupModel?> getUserShiftGroup(String userId) async {
    final assignment = await getUserShiftAssignment(userId);
    if (assignment == null) return null;
    return getShiftGroup(assignment.shiftGroupId);
  }

  Future<UserShiftInfo?> getUserShiftInfo(String userId) async {
    final assignment = await getUserShiftAssignment(userId);
    if (assignment == null) return null;

    final group = await getShiftGroup(assignment.shiftGroupId);
    if (group == null) return null;

    return UserShiftInfo(assignment: assignment, group: group);
  }

  Stream<ShiftAssignmentModel?> watchUserShiftAssignment(String userId) {
    return _db
        .collection('user_shift_assignments')
        .where('user_ra', isEqualTo: userId)
        .where('active', isEqualTo: true)
        .limit(1)
        .snapshots()
        .asyncMap((snapshot) async {
          if (snapshot.docs.isNotEmpty) {
            final doc = snapshot.docs.first;
            return ShiftAssignmentModel.fromJson(doc.id, doc.data());
          }

          return getUserShiftAssignment(userId);
        });
  }
}

class UserShiftInfo {
  final ShiftAssignmentModel assignment;
  final ShiftGroupModel group;

  UserShiftInfo({required this.assignment, required this.group});

  String get groupId => group.id;
  String get groupName => group.name;
  String get groupType => group.type;
  int get expectedStartHour => group.expectedStartHour;
  int get expectedEndHour => group.expectedEndHour;
  String get scheduleDisplay => group.scheduleDisplay;

  bool isWithinShiftHours() {
    return group.isOnDutyAt(DateTime.now());
  }

  bool shouldStartShift({int graceMinutes = 30}) {
    final now = DateTime.now();
    final window = group.expectedWindowForDate(now);
    if (window == null) return false;

    final reminderTime = window.start.add(Duration(minutes: graceMinutes));
    return now.isAfter(reminderTime) && now.isBefore(window.end);
  }
}
