import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:canil_gcm/core/utils/firestore_date.dart';
import 'package:canil_gcm/core/mixins/soft_deletable.dart';

class HealthLogModel with SoftDeletable {
  final String? id;
  final String dogId;
  final String dogName;
  final DateTime date;
  final String
  type; // 'vaccination' | 'antiparasitic' | 'exam' | 'consultation' | 'medication' | 'symptom' | 'surgery' | 'other'
  final String? subtype; // e.g., "V10", "Bravecto", "Hemograma"
  final double? weight;
  final String healthObservations;
  final DateTime? nextDueDate;
  final String? professionalCrmv;
  final String? professionalClinic;
  final String? attachmentUrl;
  final double? costBrl;
  final String? createdBy;
  final String? vetName; // backing vet name for legacy compatibility
  final List<Map<String, dynamic>>? mediaAttachments;
  final List<Map<String, dynamic>> auditTrail;

  @override
  final DateTime? deletedAt;
  @override
  final String? deletedBy;
  @override
  final String? deleteReason;

  HealthLogModel({
    this.id,
    required this.dogId,
    this.dogName = '',
    required this.date,
    required this.type,
    this.subtype,
    this.weight,
    required this.healthObservations,
    this.nextDueDate,
    this.professionalCrmv,
    this.professionalClinic,
    this.attachmentUrl,
    this.costBrl,
    this.createdBy,
    this.vetName,
    this.mediaAttachments,
    this.auditTrail = const [],
    this.deletedAt,
    this.deletedBy,
    this.deleteReason,
  });

  String get logType {
    switch (type) {
      case 'vaccination':
        return 'Vacina';
      case 'antiparasitic':
        return 'Antiparasitário';
      case 'exam':
        return 'Exame';
      case 'consultation':
        return 'Consulta';
      case 'medication':
        return 'Medicação';
      case 'symptom':
        return 'Sintoma';
      case 'surgery':
        return 'Cirurgia';
      case 'other':
      default:
        return 'Outro';
    }
  }

  List<String> get vaccines =>
      (type == 'vaccination' && subtype != null) ? [subtype!] : const [];

  factory HealthLogModel.fromJson(Map<String, dynamic> json, [String? docId]) {
    final typeVal = json['type'] ?? mapLegacyLogType(json['logType']);

    DateTime? parsedNextDueDate;
    if (json['nextDueDate'] != null) {
      parsedNextDueDate = parseFirestoreDate(json['nextDueDate']);
    }

    return HealthLogModel(
      id: docId ?? json['id'],
      dogId: json['dogId'] ?? '',
      dogName: json['dogName'] ?? '',
      date: parseFirestoreDate(json['date']),
      type: typeVal,
      subtype:
          json['subtype'] ??
          (json['vaccines'] != null && (json['vaccines'] as List).isNotEmpty
              ? (json['vaccines'] as List).first.toString()
              : null),
      weight: json['weight'] != null
          ? (json['weight'] as num).toDouble()
          : null,
      healthObservations: json['healthObservations'] ?? '',
      nextDueDate: parsedNextDueDate,
      professionalCrmv: json['professionalCrmv'],
      professionalClinic: json['professionalClinic'],
      attachmentUrl: json['attachmentUrl'],
      costBrl: json['costBrl'] != null
          ? (json['costBrl'] as num).toDouble()
          : null,
      createdBy: json['createdBy'],
      vetName: json['vetName'] ?? json['vetName'],
      mediaAttachments: json['mediaAttachments'] != null
          ? List<Map<String, dynamic>>.from(
              (json['mediaAttachments'] as List).map(
                (e) => Map<String, dynamic>.from(e as Map),
              ),
            )
          : null,
      auditTrail:
          (json['audit_trail'] as List<dynamic>?)
              ?.whereType<Map>()
              .map(
                (e) => e.map((key, value) => MapEntry(key.toString(), value)),
              )
              .toList() ??
          const [],
      deletedAt: SoftDeletable.parseDeletedAt(
        json['deleted_at'] ?? json['deletedAt'],
      ),
      deletedBy: json['deleted_by'] ?? json['deletedBy'],
      deleteReason:
          json['deleted_reason'] ??
          json['delete_reason'] ??
          json['deleteReason'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      if (id != null) 'id': id,
      'dogId': dogId,
      'dogName': dogName,
      'date': Timestamp.fromDate(date),
      'type': type,
      if (subtype != null) 'subtype': subtype,
      if (weight != null) 'weight': weight,
      'healthObservations': healthObservations,
      if (nextDueDate != null) 'nextDueDate': Timestamp.fromDate(nextDueDate!),
      if (professionalCrmv != null) 'professionalCrmv': professionalCrmv,
      if (professionalClinic != null) 'professionalClinic': professionalClinic,
      if (attachmentUrl != null) 'attachmentUrl': attachmentUrl,
      if (costBrl != null) 'costBrl': costBrl,
      if (createdBy != null) 'createdBy': createdBy,
      if (vetName != null) 'vetName': vetName,
      if (mediaAttachments != null) 'mediaAttachments': mediaAttachments,
      'audit_trail': auditTrail,
      ...softDeleteFields(),
    };
  }

  HealthLogModel copyWith({
    String? id,
    String? dogId,
    String? dogName,
    DateTime? date,
    String? type,
    String? subtype,
    double? weight,
    String? healthObservations,
    DateTime? nextDueDate,
    String? professionalCrmv,
    String? professionalClinic,
    String? attachmentUrl,
    double? costBrl,
    String? createdBy,
    String? vetName,
    List<Map<String, dynamic>>? mediaAttachments,
    List<Map<String, dynamic>>? auditTrail,
    DateTime? deletedAt,
    String? deletedBy,
    String? deleteReason,
  }) {
    return HealthLogModel(
      id: id ?? this.id,
      dogId: dogId ?? this.dogId,
      dogName: dogName ?? this.dogName,
      date: date ?? this.date,
      type: type ?? this.type,
      subtype: subtype ?? this.subtype,
      weight: weight ?? this.weight,
      healthObservations: healthObservations ?? this.healthObservations,
      nextDueDate: nextDueDate ?? this.nextDueDate,
      professionalCrmv: professionalCrmv ?? this.professionalCrmv,
      professionalClinic: professionalClinic ?? this.professionalClinic,
      attachmentUrl: attachmentUrl ?? this.attachmentUrl,
      costBrl: costBrl ?? this.costBrl,
      createdBy: createdBy ?? this.createdBy,
      vetName: vetName ?? this.vetName,
      mediaAttachments: mediaAttachments ?? this.mediaAttachments,
      auditTrail: auditTrail ?? this.auditTrail,
      deletedAt: deletedAt ?? this.deletedAt,
      deletedBy: deletedBy ?? this.deletedBy,
      deleteReason: deleteReason ?? this.deleteReason,
    );
  }

  static String mapLegacyLogType(String? legacy) {
    if (legacy == 'Vacina') return 'vaccination';
    if (legacy == 'Consulta') return 'consultation';
    if (legacy == 'Exame') return 'exam';
    if (legacy == 'Medicação') return 'medication';
    if (legacy == 'Banho') return 'other';
    if (legacy == 'Pesagem') return 'other';
    return 'other';
  }
}
