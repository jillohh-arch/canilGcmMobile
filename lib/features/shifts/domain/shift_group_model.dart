import 'package:cloud_firestore/cloud_firestore.dart';

const _millisecondsPerDay = 86400000;

class ShiftGroupModel {
  final String id;
  final String code;
  final String name;
  final String type; // operational | administrative
  final String scheduleType; // two_by_two | weekdays | custom
  final int expectedStartHour;
  final int expectedEndHour;
  final String municipality;
  final DateTime? anchorDate;
  final List<int> workPattern;
  final bool active;
  final ShiftNotificationSettings notifications;

  ShiftGroupModel({
    required this.id,
    required this.code,
    required this.name,
    required this.type,
    required this.scheduleType,
    required this.expectedStartHour,
    required this.expectedEndHour,
    required this.municipality,
    required this.anchorDate,
    required this.workPattern,
    required this.active,
    required this.notifications,
  });

  factory ShiftGroupModel.fromJson(Map<String, dynamic> json, String id) {
    final type = _string(json['type'], fallback: 'operational');
    return ShiftGroupModel(
      id: id,
      code: _string(json['code'], fallback: id).toUpperCase(),
      name: _string(json['name']),
      type: type,
      scheduleType: _scheduleType(
        json['scheduleType'] ?? json['schedule_type'],
        type,
      ),
      expectedStartHour: _hour(
        json['expectedStartHour'] ?? json['expected_start_hour'],
        json['start_time'],
        fallback: 7,
      ),
      expectedEndHour: _hour(
        json['expectedEndHour'] ?? json['expected_end_hour'],
        json['end_time'],
        fallback: 19,
      ),
      municipality: _string(json['municipality'] ?? json['municipio']),
      anchorDate: _dateOnly(json['anchorDate'] ?? json['anchor_date']),
      workPattern: _workPattern(json['workPattern'] ?? json['work_pattern']),
      active: _bool(json['active'], fallback: true),
      notifications: ShiftNotificationSettings.fromJson(
        json['notifications'] is Map<String, dynamic>
            ? json['notifications'] as Map<String, dynamic>
            : const <String, dynamic>{},
      ),
    );
  }

  bool get isAdministrative => type == 'administrative';
  bool get isOvernight => expectedStartHour >= expectedEndHour;

  String get scheduleDisplay {
    final start = expectedStartHour.toString().padLeft(2, '0');
    final end = expectedEndHour.toString().padLeft(2, '0');
    return '$start:00 - $end:00${isOvernight ? ' (+1 dia)' : ''}';
  }

  bool isOnDutyAt(DateTime moment) {
    final today = expectedWindowForDate(moment);
    if (today?.contains(moment) == true) return true;

    final previousDay = moment.subtract(const Duration(days: 1));
    final previous = expectedWindowForDate(previousDay);
    return previous?.contains(moment) == true;
  }

  bool isWorkDay(DateTime date) {
    if (!active) return false;

    if (scheduleType == 'weekdays') {
      return date.weekday >= DateTime.monday && date.weekday <= DateTime.friday;
    }

    if (scheduleType == 'two_by_two') {
      final anchor = anchorDate;
      if (anchor == null) return false;
      final diff =
          _startOfDay(date).millisecondsSinceEpoch -
          _startOfDay(anchor).millisecondsSinceEpoch;
      final days = diff ~/ _millisecondsPerDay;
      final cycleIndex = ((days % 4) + 4) % 4;
      return workPattern.contains(cycleIndex);
    }

    return false;
  }

  ShiftWindow? expectedWindowForDate(DateTime date) {
    if (!isWorkDay(date)) return null;

    final day = _startOfDay(date);
    final start = DateTime(day.year, day.month, day.day, expectedStartHour);
    var end = DateTime(day.year, day.month, day.day, expectedEndHour);
    if (isOvernight) {
      end = end.add(const Duration(days: 1));
    }
    return ShiftWindow(start: start, end: end);
  }
}

class ShiftAssignmentModel {
  final String id;
  final String userId;
  final String shiftGroupId;
  final bool active;
  final DateTime? assignedAt;
  final DateTime? endedAt;

  ShiftAssignmentModel({
    required this.id,
    required this.userId,
    required this.shiftGroupId,
    required this.active,
    required this.assignedAt,
    required this.endedAt,
  });

  factory ShiftAssignmentModel.fromJson(String id, Map<String, dynamic> json) {
    return ShiftAssignmentModel(
      id: id,
      userId: _string(
        json['user_ra'] ??
            json['ra'] ??
            json['handlerId'] ??
            json['userId'] ??
            json['user_id'],
      ),
      shiftGroupId: _string(json['shiftGroupId'] ?? json['shift_group_id']),
      active: _bool(json['active'], fallback: true),
      assignedAt: _date(json['assignedAt'] ?? json['assigned_at']),
      endedAt: _date(json['endedAt'] ?? json['ended_at']),
    );
  }
}

class ShiftNotificationSettings {
  final bool endReminderEnabled;
  final int overdueAfterMinutes;
  final bool overdueReminderEnabled;
  final int overdueRepeatMinutes;
  final int startLeadMinutes;
  final bool startReminderEnabled;

  const ShiftNotificationSettings({
    required this.endReminderEnabled,
    required this.overdueAfterMinutes,
    required this.overdueReminderEnabled,
    required this.overdueRepeatMinutes,
    required this.startLeadMinutes,
    required this.startReminderEnabled,
  });

  factory ShiftNotificationSettings.fromJson(Map<String, dynamic> json) {
    return ShiftNotificationSettings(
      endReminderEnabled: _bool(
        json['endReminderEnabled'] ?? json['end_reminder_enabled'],
        fallback: true,
      ),
      overdueAfterMinutes: _int(
        json['overdueAfterMinutes'] ?? json['overdue_after_minutes'],
        fallback: 30,
      ),
      overdueReminderEnabled: _bool(
        json['overdueReminderEnabled'] ?? json['overdue_reminder_enabled'],
        fallback: true,
      ),
      overdueRepeatMinutes: _int(
        json['overdueRepeatMinutes'] ?? json['overdue_repeat_minutes'],
        fallback: 60,
      ),
      startLeadMinutes: _int(
        json['startLeadMinutes'] ?? json['start_lead_minutes'],
        fallback: 15,
      ),
      startReminderEnabled: _bool(
        json['startReminderEnabled'] ?? json['start_reminder_enabled'],
        fallback: true,
      ),
    );
  }
}

class ShiftWindow {
  final DateTime start;
  final DateTime end;

  const ShiftWindow({required this.start, required this.end});

  bool contains(DateTime moment) {
    return !moment.isBefore(start) && moment.isBefore(end);
  }
}

bool _bool(dynamic value, {required bool fallback}) {
  if (value is bool) return value;
  if (value is num) return value != 0;
  if (value is String) {
    final parsed = value.trim().toLowerCase();
    if (['true', '1', 'sim', 'yes', 'active'].contains(parsed)) return true;
    if (['false', '0', 'nao', 'não', 'no', 'inactive'].contains(parsed)) {
      return false;
    }
  }
  return fallback;
}

DateTime? _date(dynamic value) {
  if (value == null) return null;
  if (value is DateTime) return value;
  if (value is Timestamp) return value.toDate();
  if (value is String) return DateTime.tryParse(value);
  return null;
}

DateTime? _dateOnly(dynamic value) {
  final parsed = _date(value);
  if (parsed != null) return _startOfDay(parsed);

  if (value is String) {
    final match = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(value);
    if (match == null) return null;
    return DateTime(
      int.parse(match.group(1)!),
      int.parse(match.group(2)!),
      int.parse(match.group(3)!),
    );
  }
  return null;
}

int _hour(dynamic hourValue, dynamic timeValue, {required int fallback}) {
  final direct = _int(hourValue, fallback: -1);
  if (direct >= 0 && direct <= 23) return direct;

  if (timeValue is String) {
    final match = RegExp(r'^(\d{1,2}):').firstMatch(timeValue.trim());
    if (match != null) {
      final parsed = int.tryParse(match.group(1)!);
      if (parsed != null && parsed >= 0 && parsed <= 23) return parsed;
    }
  }

  return fallback;
}

int _int(dynamic value, {required int fallback}) {
  if (value is int) return value;
  if (value is num) return value.round();
  if (value is String) return int.tryParse(value) ?? fallback;
  return fallback;
}

String _scheduleType(dynamic value, String type) {
  if (value == 'two_by_two' || value == 'weekdays' || value == 'custom') {
    return value as String;
  }
  return type == 'administrative' ? 'weekdays' : 'two_by_two';
}

DateTime _startOfDay(DateTime date) {
  return DateTime(date.year, date.month, date.day);
}

String _string(dynamic value, {String fallback = ''}) {
  if (value == null) return fallback;
  final parsed = value.toString().trim();
  return parsed.isEmpty ? fallback : parsed;
}

List<int> _workPattern(dynamic value) {
  final raw = value is List ? value : const [0, 1];
  final parsed =
      raw
          .map((item) => _int(item, fallback: -1))
          .where((item) => item >= 0 && item <= 3)
          .toSet()
          .toList()
        ..sort();
  return parsed.isEmpty ? [0, 1] : parsed;
}
