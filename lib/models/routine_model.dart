import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:canil_gcm/utils/firestore_date.dart';

/// Represents an operational routine entry (Alimentação, Limpeza, Passeio, etc.)
/// stored in the Firestore 'routines' collection, separate from 'trainings'.
class RoutineModel {
  final String? id;
  final String dogId;
  final String dogName;
  final String handlerId;

  /// Activity type: 'Alimentação', 'Limpeza', 'Passeio', 'Descanso',
  /// 'Brincadeira', 'Escovação', 'Outros'
  final String activityType;

  /// Operational status: 'Concluído', 'Em andamento', 'Cancelado'
  final String status;

  final DateTime timestamp;
  final String? notes;
  final List<Map<String, dynamic>>? mediaAttachments;
  final Map<String, dynamic>? metadata;

  RoutineModel({
    this.id,
    required this.dogId,
    this.dogName = '',
    required this.handlerId,
    required this.activityType,
    required this.status,
    required this.timestamp,
    this.notes,
    this.mediaAttachments,
    this.metadata,
  });

  factory RoutineModel.fromJson(Map<String, dynamic> json, [String? docId]) {
    return RoutineModel(
      id: docId ?? json['id'],
      dogId: json['dogId'] ?? '',
      dogName: json['dogName'] ?? '',
      handlerId: json['handlerId'] ?? '',
      activityType: json['activityType'] ?? 'Outros',
      status: json['status'] ?? 'Concluído',
      timestamp: parseFirestoreDate(json['timestamp']),
      notes: json['notes'],
      mediaAttachments: json['mediaAttachments'] != null
          ? List<Map<String, dynamic>>.from(
              (json['mediaAttachments'] as List).map(
                (e) => Map<String, dynamic>.from(e as Map),
              ),
            )
          : null,
      metadata: json['metadata'] != null
          ? Map<String, dynamic>.from(json['metadata'] as Map)
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      if (id != null) 'id': id,
      'dogId': dogId,
      'dogName': dogName,
      'handlerId': handlerId,
      'activityType': activityType,
      'status': status,
      'timestamp': Timestamp.fromDate(timestamp),
      if (notes != null && notes!.isNotEmpty) 'notes': notes,
      if (mediaAttachments != null && mediaAttachments!.isNotEmpty)
        'mediaAttachments': mediaAttachments,
      if (metadata != null && metadata!.isNotEmpty) 'metadata': metadata,
    };
  }
}
