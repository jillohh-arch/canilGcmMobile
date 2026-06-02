import 'package:cloud_firestore/cloud_firestore.dart';

class TrainingPromotionRequest {
  final String id;
  final String dogId;
  final String dogName;
  final String modality;
  final String moduleId;
  final String moduleName;
  final int moduleOrder;
  final int programVersion;
  final String requesterRa;
  final String requesterName;
  final String status;
  final String? decisionBy;
  final String? decisionReason;
  final DateTime? requestedAt;
  final DateTime? decidedAt;
  final List<Map<String, dynamic>> marksSnapshot;

  const TrainingPromotionRequest({
    required this.id,
    required this.dogId,
    required this.dogName,
    required this.modality,
    required this.moduleId,
    required this.moduleName,
    required this.moduleOrder,
    required this.programVersion,
    required this.requesterRa,
    required this.requesterName,
    required this.status,
    required this.marksSnapshot,
    this.decisionBy,
    this.decisionReason,
    this.requestedAt,
    this.decidedAt,
  });

  factory TrainingPromotionRequest.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data() ?? const <String, dynamic>{};
    return TrainingPromotionRequest(
      id: doc.id,
      dogId: _readString(data, 'dog_id') ?? '',
      dogName: _readString(data, 'dog_name') ?? '',
      modality: _readString(data, 'modality') ?? '',
      moduleId: _readString(data, 'module_id') ?? '',
      moduleName: _readString(data, 'module_name') ?? '',
      moduleOrder: _readInt(data['module_order']) ?? 0,
      programVersion: _readInt(data['program_version']) ?? 1,
      requesterRa: _readString(data, 'requester_ra') ?? '',
      requesterName: _readString(data, 'requester_name') ?? '',
      status: _readString(data, 'status') ?? 'pending',
      decisionBy: _readString(data, 'decision_by'),
      decisionReason: _readString(data, 'decision_reason'),
      requestedAt: _readDate(data['requested_at'] ?? data['created_at']),
      decidedAt: _readDate(data['decided_at']),
      marksSnapshot: _readMapList(data['marks_snapshot']),
    );
  }

  bool get isPending => status == 'pending';
  bool get isApproved => status == 'approved';
  bool get isRejected => status == 'rejected';
}

String? _readString(Map<String, dynamic> data, String key) {
  final value = data[key];
  if (value == null) return null;
  final text = value.toString().trim();
  return text.isEmpty ? null : text;
}

int? _readInt(dynamic value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  if (value is String) return int.tryParse(value);
  return null;
}

DateTime? _readDate(dynamic value) {
  if (value is Timestamp) return value.toDate();
  if (value is DateTime) return value;
  if (value is String) return DateTime.tryParse(value);
  return null;
}

List<Map<String, dynamic>> _readMapList(dynamic value) {
  if (value is! List) return const [];
  return value
      .whereType<Map>()
      .map((item) => item.map((key, value) => MapEntry(key.toString(), value)))
      .toList();
}
