import 'package:cloud_firestore/cloud_firestore.dart';

class TrainingProgram {
  final String id;
  final String name;
  final String modality;
  final int version;
  final bool active;
  final DateTime? updatedAt;
  final List<TrainingModule> modules;

  const TrainingProgram({
    required this.id,
    required this.name,
    required this.modality,
    required this.version,
    required this.active,
    required this.modules,
    this.updatedAt,
  });

  factory TrainingProgram.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> doc, {
    List<TrainingModule> modules = const [],
  }) {
    final data = doc.data() ?? const <String, dynamic>{};
    return TrainingProgram(
      id: doc.id,
      name: _readString(data, 'name') ?? doc.id,
      modality: _readString(data, 'modality') ?? doc.id,
      version: _readInt(data['version']) ?? 1,
      active: data['active'] != false,
      updatedAt: _readDate(data['updated_at'] ?? data['updatedAt']),
      modules: modules,
    );
  }

  TrainingProgram copyWith({List<TrainingModule>? modules}) {
    return TrainingProgram(
      id: id,
      name: name,
      modality: modality,
      version: version,
      active: active,
      updatedAt: updatedAt,
      modules: modules ?? this.modules,
    );
  }

  List<TrainingModule> get activeModules {
    final items = modules.where((module) => module.active).toList();
    items.sort((a, b) => a.order.compareTo(b.order));
    return items;
  }
}

class TrainingModule {
  final String id;
  final int order;
  final String name;
  final String description;
  final bool active;
  final List<TrainingMilestone> milestones;

  const TrainingModule({
    required this.id,
    required this.order,
    required this.name,
    required this.description,
    required this.active,
    required this.milestones,
  });

  factory TrainingModule.fromFirestore(
    QueryDocumentSnapshot<Map<String, dynamic>> doc, {
    List<TrainingMilestone> milestones = const [],
  }) {
    final data = doc.data();
    return TrainingModule(
      id: doc.id,
      order: _readInt(data['order']) ?? 0,
      name: _readString(data, 'name') ?? doc.id,
      description: _readString(data, 'description') ?? '',
      active: data['active'] != false,
      milestones: milestones,
    );
  }

  TrainingModule copyWith({List<TrainingMilestone>? milestones}) {
    return TrainingModule(
      id: id,
      order: order,
      name: name,
      description: description,
      active: active,
      milestones: milestones ?? this.milestones,
    );
  }

  List<TrainingMilestone> get activeMilestones {
    final items = milestones.where((milestone) => milestone.active).toList();
    items.sort((a, b) => a.order.compareTo(b.order));
    return items;
  }
}

class TrainingMilestone {
  final String id;
  final int order;
  final String label;
  final bool isRequired;
  final bool active;

  const TrainingMilestone({
    required this.id,
    required this.order,
    required this.label,
    required this.isRequired,
    required this.active,
  });

  factory TrainingMilestone.fromFirestore(
    QueryDocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data();
    return TrainingMilestone(
      id: doc.id,
      order: _readInt(data['order']) ?? 0,
      label: _readString(data, 'label') ?? doc.id,
      isRequired: data['required'] != false,
      active: data['active'] != false,
    );
  }
}

class TrainingProgress {
  final bool exists;
  final String modality;
  final String status;
  final String? currentModuleId;
  final int? programVersion;
  final DateTime? operationalSince;
  final List<String> completedModuleIds;
  final List<CompletedTrainingModule> completedModules;
  final Map<String, Map<String, TrainingMilestoneAchievement>>
  achievedMilestones;

  const TrainingProgress({
    required this.exists,
    required this.modality,
    required this.status,
    required this.completedModuleIds,
    required this.completedModules,
    required this.achievedMilestones,
    this.currentModuleId,
    this.programVersion,
    this.operationalSince,
  });

  factory TrainingProgress.initial(String modality) {
    return TrainingProgress(
      exists: false,
      modality: modality,
      status: 'in_formation',
      completedModuleIds: const [],
      completedModules: const [],
      achievedMilestones: const {},
    );
  }

  factory TrainingProgress.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> doc,
    String modality,
  ) {
    if (!doc.exists) return TrainingProgress.initial(modality);
    final data = doc.data() ?? const <String, dynamic>{};
    final completedModules = _readCompletedModules(data['completed_modules']);
    final completedIds = _readStringList(
      data['completed_module_ids'] ?? data['completedModules'],
    );
    return TrainingProgress(
      exists: true,
      modality: _readString(data, 'modality') ?? modality,
      status: _readString(data, 'status') ?? 'in_formation',
      currentModuleId:
          _readString(data, 'current_module') ??
          _readString(data, 'current_module_id') ??
          _readString(data, 'currentModuleId'),
      programVersion:
          _readInt(data['program_version']) ?? _readInt(data['programVersion']),
      operationalSince: _readDate(
        data['operational_since'] ?? data['operationalSince'],
      ),
      completedModuleIds: completedIds.isNotEmpty
          ? completedIds
          : completedModules.map((module) => module.moduleId).toList(),
      completedModules: completedModules,
      achievedMilestones: _readAchievedMilestones(data['achieved_milestones']),
    );
  }

  bool get isOperational => status == 'operational';

  Map<String, TrainingMilestoneAchievement> achievementsForModule(
    String moduleId,
  ) {
    return achievedMilestones[moduleId] ?? const {};
  }

  bool isMilestoneAchieved(String moduleId, String milestoneId) {
    return achievementsForModule(moduleId)[milestoneId]?.achieved == true;
  }

  CompletedTrainingModule? completedModule(String moduleId) {
    for (final module in completedModules) {
      if (module.moduleId == moduleId) return module;
    }
    return null;
  }
}

class TrainingMilestoneAchievement {
  final String milestoneId;
  final String label;
  final bool isRequired;
  final bool achieved;
  final DateTime? achievedAt;
  final String? achievedBy;
  final int? programVersion;

  const TrainingMilestoneAchievement({
    required this.milestoneId,
    required this.label,
    required this.isRequired,
    required this.achieved,
    this.achievedAt,
    this.achievedBy,
    this.programVersion,
  });

  factory TrainingMilestoneAchievement.fromJson(
    String milestoneId,
    Map<String, dynamic> json,
  ) {
    return TrainingMilestoneAchievement(
      milestoneId: _readString(json, 'milestone_id') ?? milestoneId,
      label: _readString(json, 'label') ?? milestoneId,
      isRequired: json['required'] != false,
      achieved: json['achieved'] == true,
      achievedAt: _readDate(json['achieved_at']),
      achievedBy: _readString(json, 'achieved_by'),
      programVersion: _readInt(json['program_version']),
    );
  }
}

class CompletedTrainingModule {
  final String moduleId;
  final int moduleOrder;
  final String moduleName;
  final int? programVersion;
  final DateTime? completedAt;
  final String? completedBy;
  final List<TrainingMilestoneAchievement> milestones;

  const CompletedTrainingModule({
    required this.moduleId,
    required this.moduleOrder,
    required this.moduleName,
    required this.milestones,
    this.programVersion,
    this.completedAt,
    this.completedBy,
  });

  factory CompletedTrainingModule.fromJson(Map<String, dynamic> json) {
    return CompletedTrainingModule(
      moduleId: _readString(json, 'module_id') ?? '',
      moduleOrder: _readInt(json['module_order']) ?? 0,
      moduleName: _readString(json, 'module_name') ?? '',
      programVersion: _readInt(json['program_version']),
      completedAt: _readDate(json['completed_at']),
      completedBy: _readString(json, 'completed_by'),
      milestones: _readMilestoneAchievementList(json['milestones']),
    );
  }
}

class BonusTrainingMilestone {
  final String id;
  final String moduleId;
  final int moduleOrder;
  final String moduleName;
  final String milestoneId;
  final int milestoneOrder;
  final String label;
  final bool isRequired;
  final int? programVersion;
  final DateTime? completedAt;
  final String? completedBy;

  const BonusTrainingMilestone({
    required this.id,
    required this.moduleId,
    required this.moduleOrder,
    required this.moduleName,
    required this.milestoneId,
    required this.milestoneOrder,
    required this.label,
    required this.isRequired,
    this.programVersion,
    this.completedAt,
    this.completedBy,
  });

  factory BonusTrainingMilestone.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data() ?? const <String, dynamic>{};
    return BonusTrainingMilestone(
      id: doc.id,
      moduleId: _readString(data, 'module_id') ?? '',
      moduleOrder: _readInt(data['module_order']) ?? 0,
      moduleName: _readString(data, 'module_name') ?? '',
      milestoneId: _readString(data, 'milestone_id') ?? doc.id,
      milestoneOrder: _readInt(data['milestone_order']) ?? 0,
      label: _readString(data, 'label') ?? doc.id,
      isRequired: data['required'] != false,
      programVersion: _readInt(data['program_version']),
      completedAt: _readDate(data['completed_at']),
      completedBy: _readString(data, 'by') ?? _readString(data, 'completed_by'),
    );
  }
}

class TrainingBonusOffer {
  final TrainingModule module;
  final TrainingMilestone milestone;

  const TrainingBonusOffer({required this.module, required this.milestone});

  String get id => '${module.id}__${milestone.id}';
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

List<String> _readStringList(dynamic value) {
  if (value is! List) return const [];
  return value
      .map((item) => item.toString().trim())
      .where((item) => item.isNotEmpty)
      .toList();
}

List<CompletedTrainingModule> _readCompletedModules(dynamic value) {
  if (value is! List) return const [];
  return value
      .whereType<Map>()
      .map((item) => CompletedTrainingModule.fromJson(_stringKeyMap(item)))
      .where((module) => module.moduleId.isNotEmpty)
      .toList();
}

List<TrainingMilestoneAchievement> _readMilestoneAchievementList(
  dynamic value,
) {
  if (value is! List) return const [];
  return value.whereType<Map>().map((item) {
    final data = _stringKeyMap(item);
    final id = _readString(data, 'milestone_id') ?? '';
    return TrainingMilestoneAchievement.fromJson(id, data);
  }).toList();
}

Map<String, Map<String, TrainingMilestoneAchievement>> _readAchievedMilestones(
  dynamic value,
) {
  if (value is! Map) return const {};
  final result = <String, Map<String, TrainingMilestoneAchievement>>{};
  for (final moduleEntry in value.entries) {
    final moduleId = moduleEntry.key.toString();
    final moduleValue = moduleEntry.value;
    if (moduleValue is! Map) continue;
    final milestones = <String, TrainingMilestoneAchievement>{};
    for (final milestoneEntry in moduleValue.entries) {
      final milestoneId = milestoneEntry.key.toString();
      final milestoneValue = milestoneEntry.value;
      if (milestoneValue is! Map) continue;
      milestones[milestoneId] = TrainingMilestoneAchievement.fromJson(
        milestoneId,
        _stringKeyMap(milestoneValue),
      );
    }
    result[moduleId] = milestones;
  }
  return result;
}

Map<String, dynamic> _stringKeyMap(Map<dynamic, dynamic> value) {
  return value.map((key, item) => MapEntry(key.toString(), item));
}
