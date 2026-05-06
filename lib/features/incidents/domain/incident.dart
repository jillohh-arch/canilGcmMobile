import 'package:cloud_firestore/cloud_firestore.dart';

import 'package:canil_gcm/utils/firestore_date.dart';

class IncidentProgressUpdate {
  final String title;
  final String description;
  final DateTime timestamp;
  final String? location;
  final double? latitude;
  final double? longitude;
  final String? authorId;
  final String? authorName;
  final List<Map<String, dynamic>> attachments;

  const IncidentProgressUpdate({
    required this.title,
    required this.description,
    required this.timestamp,
    this.location,
    this.latitude,
    this.longitude,
    this.authorId,
    this.authorName,
    this.attachments = const [],
  });

  factory IncidentProgressUpdate.fromJson(Map<String, dynamic> json) {
    return IncidentProgressUpdate(
      title: json['title'] as String? ?? 'Atualização operacional',
      description: json['description'] as String? ?? '',
      timestamp: parseFirestoreDate(json['timestamp']),
      location: json['location'] as String?,
      latitude: (json['latitude'] as num?)?.toDouble(),
      longitude: (json['longitude'] as num?)?.toDouble(),
      authorId: json['authorId'] as String?,
      authorName: json['authorName'] as String?,
      attachments: json['attachments'] != null
          ? List<Map<String, dynamic>>.from(
              (json['attachments'] as List).map(
                (e) => Map<String, dynamic>.from(e as Map),
              ),
            )
          : const [],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'title': title,
      'description': description,
      'timestamp': Timestamp.fromDate(timestamp),
      if (location != null && location!.isNotEmpty) 'location': location,
      if (latitude != null) 'latitude': latitude,
      if (longitude != null) 'longitude': longitude,
      if (authorId != null && authorId!.isNotEmpty) 'authorId': authorId,
      if (authorName != null && authorName!.isNotEmpty)
        'authorName': authorName,
      if (attachments.isNotEmpty) 'attachments': attachments,
    };
  }
}

class Incident {
  final String id;
  final String dogId;
  final String dogName;
  final String handlerId;
  final DateTime date;
  final String location;
  final String description;
  final String result;

  /// Tipo de ocorrência: 'Busca de Entorpecentes', 'Apoio à Viatura', etc.
  final String? type;
  final Map<String, dynamic>? extraFields;
  final List<Map<String, dynamic>>? mediaAttachments;

  final String status;
  final bool? operationalSuccess;
  final List<String> outcomes;
  final DateTime startedAt;
  final DateTime? endedAt;
  final DateTime updatedAt;
  final List<IncidentProgressUpdate> progressUpdates;

  Incident({
    required this.id,
    required this.dogId,
    this.dogName = '',
    required this.handlerId,
    required this.date,
    required this.location,
    required this.description,
    required this.result,
    this.type,
    this.extraFields,
    this.mediaAttachments,
    this.status = 'Concluída',
    this.operationalSuccess,
    this.outcomes = const [],
    DateTime? startedAt,
    this.endedAt,
    DateTime? updatedAt,
    this.progressUpdates = const [],
  }) : startedAt = startedAt ?? date,
       updatedAt = updatedAt ?? date;

  factory Incident.fromJson(Map<String, dynamic> json) {
    final date = parseFirestoreDate(json['date']);
    final legacyResult = json['result'] as String? ?? '';

    final progressUpdates = json['progressUpdates'] != null
        ? List<IncidentProgressUpdate>.from(
            (json['progressUpdates'] as List).map(
              (e) => IncidentProgressUpdate.fromJson(
                Map<String, dynamic>.from(e as Map),
              ),
            ),
          )
        : const <IncidentProgressUpdate>[];

    final outcomes = json['outcomes'] != null
        ? List<String>.from(json['outcomes'] as List)
        : _inferLegacyOutcomes(legacyResult, json['type'] as String?);

    return Incident(
      id: json['id'] as String? ?? '',
      dogId: json['dogId'] as String? ?? '',
      dogName: json['dogName'] as String? ?? '',
      handlerId: json['handlerId'] as String? ?? '',
      date: date,
      location: json['location'] as String? ?? '',
      description: json['description'] as String? ?? '',
      result: legacyResult,
      type: json['type'] as String?,
      extraFields: json['extraFields'] != null
          ? Map<String, dynamic>.from(json['extraFields'] as Map)
          : null,
      mediaAttachments: json['mediaAttachments'] != null
          ? List<Map<String, dynamic>>.from(
              (json['mediaAttachments'] as List).map(
                (e) => Map<String, dynamic>.from(e as Map),
              ),
            )
          : null,
      status: json['status'] as String? ?? _inferLegacyStatus(legacyResult),
      operationalSuccess: json.containsKey('operationalSuccess')
          ? json['operationalSuccess'] as bool?
          : _inferLegacySuccess(legacyResult),
      outcomes: outcomes,
      startedAt: json['startedAt'] != null
          ? parseFirestoreDate(json['startedAt'])
          : date,
      endedAt: json['endedAt'] != null
          ? parseFirestoreDate(json['endedAt'])
          : null,
      updatedAt: json['updatedAt'] != null
          ? parseFirestoreDate(json['updatedAt'])
          : date,
      progressUpdates: progressUpdates,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'dogId': dogId,
      'dogName': dogName,
      'handlerId': handlerId,
      'date': Timestamp.fromDate(date),
      'location': location,
      'description': description,
      'result': result,
      'status': status,
      'operationalSuccess': operationalSuccess,
      'outcomes': outcomes,
      'startedAt': Timestamp.fromDate(startedAt),
      'updatedAt': Timestamp.fromDate(updatedAt),
      if (endedAt != null) 'endedAt': Timestamp.fromDate(endedAt!),
      if (type != null) 'type': type,
      if (extraFields != null) 'extraFields': extraFields,
      if (mediaAttachments != null) 'mediaAttachments': mediaAttachments,
      if (progressUpdates.isNotEmpty)
        'progressUpdates': progressUpdates.map((e) => e.toJson()).toList(),
    };
  }

  Incident copyWith({
    String? id,
    String? dogId,
    String? dogName,
    String? handlerId,
    DateTime? date,
    String? location,
    String? description,
    String? result,
    String? type,
    Map<String, dynamic>? extraFields,
    List<Map<String, dynamic>>? mediaAttachments,
    String? status,
    bool? operationalSuccess,
    List<String>? outcomes,
    DateTime? startedAt,
    Object? endedAt = _sentinel,
    DateTime? updatedAt,
    List<IncidentProgressUpdate>? progressUpdates,
  }) {
    return Incident(
      id: id ?? this.id,
      dogId: dogId ?? this.dogId,
      dogName: dogName ?? this.dogName,
      handlerId: handlerId ?? this.handlerId,
      date: date ?? this.date,
      location: location ?? this.location,
      description: description ?? this.description,
      result: result ?? this.result,
      type: type ?? this.type,
      extraFields: extraFields ?? this.extraFields,
      mediaAttachments: mediaAttachments ?? this.mediaAttachments,
      status: status ?? this.status,
      operationalSuccess: operationalSuccess ?? this.operationalSuccess,
      outcomes: outcomes ?? this.outcomes,
      startedAt: startedAt ?? this.startedAt,
      endedAt: endedAt == _sentinel ? this.endedAt : endedAt as DateTime?,
      updatedAt: updatedAt ?? this.updatedAt,
      progressUpdates: progressUpdates ?? this.progressUpdates,
    );
  }

  bool get isInProgress => status == 'Em andamento' || status == 'Aberta';
  bool get isClosed => status == 'Concluída' || status == 'Cancelada';

  String get displayResult {
    if (result.isNotEmpty) {
      return result;
    }
    if (status == 'Em andamento' || status == 'Aberta') {
      return 'Em andamento';
    }
    if (status == 'Cancelada') {
      return 'Cancelada';
    }
    if (outcomes.isNotEmpty) {
      return outcomes.join(' • ');
    }
    if (operationalSuccess == true) {
      return 'Êxito';
    }
    if (operationalSuccess == false) {
      return 'Sem êxito';
    }
    return 'Ocorrência registrada';
  }

  static const _sentinel = Object();

  static String _inferLegacyStatus(String result) {
    final normalized = result.toLowerCase();
    if (normalized.contains('cancel')) {
      return 'Cancelada';
    }
    if (normalized.contains('andamento') || normalized.contains('aberta')) {
      return 'Em andamento';
    }
    return 'Concluída';
  }

  static bool? _inferLegacySuccess(String result) {
    final normalized = result.toLowerCase();
    if (normalized.contains('êxito') ||
        normalized.contains('exito') ||
        normalized.contains('sucesso') ||
        normalized.contains('apreensão') ||
        normalized.contains('apreensao') ||
        normalized.contains('localiz')) {
      return true;
    }
    if (normalized.contains('negativo') ||
        normalized.contains('falso') ||
        normalized.contains('sem êxito') ||
        normalized.contains('sem exito')) {
      return false;
    }
    return null;
  }

  static List<String> _inferLegacyOutcomes(String result, String? type) {
    final normalized = result.toLowerCase();
    final outcomes = <String>[];

    if (normalized.contains('apreensão') || normalized.contains('apreensao')) {
      outcomes.add('Droga apreendida');
    }
    if (normalized.contains('sucesso') && type == 'Busca de Pessoa') {
      outcomes.add('Pessoa localizada');
    }
    if (normalized.contains('apoio')) {
      outcomes.add('Apoio prestado');
    }

    return outcomes;
  }
}
