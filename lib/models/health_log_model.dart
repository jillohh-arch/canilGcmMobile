import 'package:cloud_firestore/cloud_firestore.dart';
import '../utils/firestore_date.dart';

class HealthLogModel {
  final String? id;
  final String dogId;
  final String dogName;
  final DateTime date;
  final String logType; // 'Vacina', 'Rotina', 'Emergência'
  final double? weight;
  final List<String> vaccines;
  final String healthObservations;
  final String? vetName;
  final List<Map<String, dynamic>>? mediaAttachments;

  HealthLogModel({
    this.id,
    required this.dogId,
    this.dogName = '',
    required this.date,
    this.logType = 'Rotina',
    this.weight,
    this.vaccines = const [],
    required this.healthObservations,
    this.vetName,
    this.mediaAttachments,
  });

  factory HealthLogModel.fromJson(Map<String, dynamic> json, [String? docId]) {
    return HealthLogModel(
      id: docId ?? json['id'],
      dogId: json['dogId'] ?? '',
      dogName: json['dogName'] ?? '',
      date: parseFirestoreDate(json['date']),
      logType: json['logType'] ?? 'Rotina',
      weight: json['weight'] != null
          ? (json['weight'] as num).toDouble()
          : null,
      vaccines: json['vaccines'] != null
          ? List<String>.from(json['vaccines'])
          : [],
      healthObservations: json['healthObservations'] ?? '',
      vetName: json['vetName'] as String?,
      mediaAttachments: json['mediaAttachments'] != null
          ? List<Map<String, dynamic>>.from(
              (json['mediaAttachments'] as List).map(
                (e) => Map<String, dynamic>.from(e as Map),
              ),
            )
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      if (id != null) 'id': id,
      'dogId': dogId,
      'dogName': dogName,
      'date': Timestamp.fromDate(date),
      'logType': logType,
      if (weight != null) 'weight': weight,
      'vaccines': vaccines,
      'healthObservations': healthObservations,
      if (vetName != null) 'vetName': vetName,
      if (mediaAttachments != null) 'mediaAttachments': mediaAttachments,
    };
  }
}
