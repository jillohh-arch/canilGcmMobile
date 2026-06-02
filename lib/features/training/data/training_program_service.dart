import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';

import 'package:canil_gcm/core/services/audit_service.dart';
import 'package:canil_gcm/features/training/domain/training_program.dart';

class TrainingProgramService {
  TrainingProgramService({FirebaseFirestore? firestore})
    : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  Stream<TrainingProgram?> watchProgram(String modality) {
    late final StreamController<TrainingProgram?> controller;
    StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? programSub;
    StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? moduleSub;
    final milestoneSubs =
        <String, StreamSubscription<QuerySnapshot<Map<String, dynamic>>>>{};
    final moduleDocs = <String, QueryDocumentSnapshot<Map<String, dynamic>>>{};
    final milestonesByModule = <String, List<TrainingMilestone>>{};
    DocumentSnapshot<Map<String, dynamic>>? programDoc;
    var isClosed = false;

    void emit() {
      if (isClosed) return;
      final doc = programDoc;
      if (doc == null || !doc.exists) {
        controller.add(null);
        return;
      }

      final modules = moduleDocs.values.map((moduleDoc) {
        final milestones = milestonesByModule[moduleDoc.id] ?? const [];
        return TrainingModule.fromFirestore(moduleDoc, milestones: milestones);
      }).toList()..sort((a, b) => a.order.compareTo(b.order));

      controller.add(TrainingProgram.fromFirestore(doc, modules: modules));
    }

    Future<void> cancelRemovedMilestoneSubs(Set<String> activeModuleIds) async {
      final removed = milestoneSubs.keys
          .where((moduleId) => !activeModuleIds.contains(moduleId))
          .toList();
      for (final moduleId in removed) {
        final sub = milestoneSubs.remove(moduleId);
        if (sub != null) {
          await sub.cancel();
        }
        milestonesByModule.remove(moduleId);
      }
    }

    void listenToMilestones(String moduleId) {
      if (milestoneSubs.containsKey(moduleId)) return;
      final milestonesRef = _firestore
          .collection('training_programs')
          .doc(modality)
          .collection('modules')
          .doc(moduleId)
          .collection('milestones')
          .orderBy('order');

      milestoneSubs[moduleId] = milestonesRef.snapshots().listen((snapshot) {
        milestonesByModule[moduleId] = snapshot.docs
            .map(TrainingMilestone.fromFirestore)
            .toList();
        emit();
      }, onError: controller.addError);
    }

    controller = StreamController<TrainingProgram?>(
      onListen: () {
        final programRef = _firestore
            .collection('training_programs')
            .doc(modality);

        programSub = programRef.snapshots().listen((snapshot) {
          programDoc = snapshot;
          moduleDocs.clear();
          milestonesByModule.clear();
          unawaited(cancelRemovedMilestoneSubs(const <String>{}));
          final previousModuleSub = moduleSub;
          if (previousModuleSub != null) {
            unawaited(previousModuleSub.cancel());
          }
          moduleSub = null;

          if (!snapshot.exists) {
            emit();
            return;
          }

          moduleSub = programRef
              .collection('modules')
              .orderBy('order')
              .snapshots()
              .listen((snapshot) {
                moduleDocs
                  ..clear()
                  ..addEntries(
                    snapshot.docs.map((doc) => MapEntry(doc.id, doc)),
                  );

                final activeModuleIds = moduleDocs.keys.toSet();
                unawaited(cancelRemovedMilestoneSubs(activeModuleIds));
                for (final moduleId in activeModuleIds) {
                  listenToMilestones(moduleId);
                }
                emit();
              }, onError: controller.addError);
        }, onError: controller.addError);
      },
      onCancel: () async {
        isClosed = true;
        await programSub?.cancel();
        await moduleSub?.cancel();
        for (final sub in milestoneSubs.values) {
          await sub.cancel();
        }
      },
    );

    return controller.stream;
  }

  Stream<TrainingProgress> watchProgress(String dogId, String modality) {
    return _firestore
        .collection('dogs')
        .doc(dogId)
        .collection('training')
        .doc(modality)
        .snapshots()
        .map((snapshot) => TrainingProgress.fromFirestore(snapshot, modality));
  }

  Stream<List<BonusTrainingMilestone>> watchBonusMilestones(
    String dogId,
    String modality,
  ) {
    return _progressRef(dogId, modality)
        .collection('bonus_milestones')
        .orderBy('completed_at', descending: true)
        .snapshots()
        .map(
          (snapshot) =>
              snapshot.docs.map(BonusTrainingMilestone.fromFirestore).toList(),
        );
  }

  List<TrainingBonusOffer> bonusOffersFor({
    required TrainingProgram program,
    required TrainingProgress progress,
    required List<BonusTrainingMilestone> completedBonuses,
  }) {
    if (!progress.isOperational) return const [];
    final completedBonusIds = completedBonuses
        .map((item) => _bonusMilestoneDocId(item.moduleId, item.milestoneId))
        .toSet();
    final offers = <TrainingBonusOffer>[];
    for (final module in program.activeModules) {
      final completedModule = progress.completedModule(module.id);
      if (completedModule == null) continue;
      final snapshotMilestoneIds = completedModule.milestones
          .map((item) => item.milestoneId)
          .toSet();
      for (final milestone in module.activeMilestones) {
        final bonusId = _bonusMilestoneDocId(module.id, milestone.id);
        if (snapshotMilestoneIds.contains(milestone.id)) continue;
        if (completedBonusIds.contains(bonusId)) continue;
        offers.add(TrainingBonusOffer(module: module, milestone: milestone));
      }
    }
    return offers;
  }

  Future<void> ensureProgressInitialized({
    required String dogId,
    required TrainingProgram program,
  }) async {
    final modules = program.activeModules;
    if (modules.isEmpty) return;

    final progressRef = _progressRef(dogId, program.modality);
    final specialtyRef = await _specialtyRefFor(dogId, program.modality);
    final entry = AuditService.buildInlineEntry(action: 'created');

    await _firestore.runTransaction((transaction) async {
      final progressSnap = await transaction.get(progressRef);
      final specialtySnap = await transaction.get(specialtyRef);

      final firstModule = modules.first;
      if (progressSnap.exists) {
        final progress = TrainingProgress.fromFirestore(
          progressSnap,
          program.modality,
        );
        if (_progressNeedsNormalization(progressSnap.data())) {
          final status = progress.isOperational
              ? 'operational'
              : 'in_formation';
          final currentModuleId = status == 'operational'
              ? null
              : progress.currentModuleId ?? firstModule.id;
          transaction.set(progressRef, {
            'modality': program.modality,
            'status': status,
            'current_module': currentModuleId,
            'current_module_id': currentModuleId,
            'program_version': progress.programVersion ?? program.version,
            'completed_module_ids': progress.completedModuleIds,
            'completed_modules': progress.completedModules
                .map(_completedModuleToJson)
                .toList(),
            'achieved_milestones': _achievedMilestonesToJson(
              progress.achievedMilestones,
            ),
            'operational_since': progress.operationalSince == null
                ? null
                : Timestamp.fromDate(progress.operationalSince!),
            'updated_at': FieldValue.serverTimestamp(),
            'audit_trail': FieldValue.arrayUnion([entry]),
          }, SetOptions(merge: true));
        }

        _syncSpecialtyInTransaction(
          transaction: transaction,
          specialtyRef: specialtyRef,
          specialtyExists: specialtySnap.exists,
          program: program,
          status: progress.isOperational ? 'operational' : 'in_formation',
          currentModuleId: progress.isOperational
              ? null
              : progress.currentModuleId ?? firstModule.id,
          completedModuleCount: progress.completedModuleIds.length,
          operationalSince: progress.operationalSince == null
              ? null
              : Timestamp.fromDate(progress.operationalSince!),
          entry: entry,
        );
        return;
      }

      transaction.set(progressRef, {
        'modality': program.modality,
        'status': 'in_formation',
        'current_module': firstModule.id,
        'current_module_id': firstModule.id,
        'program_version': program.version,
        'completed_module_ids': <String>[],
        'completed_modules': <Map<String, dynamic>>[],
        'achieved_milestones': <String, dynamic>{},
        'created_at': FieldValue.serverTimestamp(),
        'updated_at': FieldValue.serverTimestamp(),
        'audit_trail': [entry],
      });

      _syncSpecialtyInTransaction(
        transaction: transaction,
        specialtyRef: specialtyRef,
        specialtyExists: specialtySnap.exists,
        program: program,
        status: 'in_formation',
        currentModuleId: firstModule.id,
        completedModuleCount: 0,
        entry: entry,
      );
    });
  }

  Future<void> setMilestoneAchievement({
    required String dogId,
    required TrainingProgram program,
    required TrainingModule module,
    required TrainingMilestone milestone,
    required bool achieved,
  }) async {
    final progressRef = _progressRef(dogId, program.modality);
    final specialtyRef = await _specialtyRefFor(dogId, program.modality);
    final entry = AuditService.buildInlineEntry(
      action: 'updated',
      fieldName: 'achieved_milestones',
    );
    final actor = _actorFromEntry(entry);

    await _firestore.runTransaction((transaction) async {
      final progressSnap = await transaction.get(progressRef);
      final specialtySnap = await transaction.get(specialtyRef);
      final progress = TrainingProgress.fromFirestore(
        progressSnap,
        program.modality,
      );
      if (progress.isOperational) {
        throw StateError('Cao ja esta operacional em ${program.name}.');
      }

      final currentModuleId = progress.currentModuleId ?? module.id;
      if (currentModuleId != module.id) {
        throw StateError('Somente o modulo atual pode receber marcos.');
      }

      final achievedMilestones = _achievedMilestonesToJson(
        progress.achievedMilestones,
      );
      final moduleMilestones = Map<String, dynamic>.from(
        achievedMilestones[module.id] as Map? ?? const <String, dynamic>{},
      );

      if (achieved) {
        moduleMilestones[milestone.id] = {
          'milestone_id': milestone.id,
          'label': milestone.label,
          'required': milestone.isRequired,
          'achieved': true,
          'achieved_at': Timestamp.now(),
          'achieved_by': actor,
          'program_version': program.version,
        };
      } else {
        moduleMilestones.remove(milestone.id);
      }
      achievedMilestones[module.id] = moduleMilestones;

      final payload = <String, dynamic>{
        'modality': program.modality,
        'program_version': program.version,
        'achieved_milestones': achievedMilestones,
        'updated_at': FieldValue.serverTimestamp(),
        'audit_trail': FieldValue.arrayUnion([entry]),
      };
      if (!progressSnap.exists) {
        payload.addAll({
          'status': 'in_formation',
          'current_module': module.id,
          'current_module_id': module.id,
          'completed_module_ids': <String>[],
          'completed_modules': <Map<String, dynamic>>[],
          'operational_since': null,
        });
      }
      transaction.set(progressRef, payload, SetOptions(merge: true));

      _syncSpecialtyInTransaction(
        transaction: transaction,
        specialtyRef: specialtyRef,
        specialtyExists: specialtySnap.exists,
        program: program,
        status: 'in_formation',
        currentModuleId: module.id,
        completedModuleCount: progress.completedModuleIds.length,
        entry: entry,
      );
    });
  }

  Future<void> completeCurrentModule({
    required String dogId,
    required TrainingProgram program,
    required TrainingModule module,
  }) async {
    final modules = program.activeModules;
    if (modules.isEmpty) return;

    final progressRef = _progressRef(dogId, program.modality);
    final specialtyRef = await _specialtyRefFor(dogId, program.modality);
    final entry = AuditService.buildInlineEntry(
      action: 'updated',
      fieldName: 'completed_modules',
    );
    final actor = _actorFromEntry(entry);
    final completedAt = Timestamp.now();

    await _firestore.runTransaction((transaction) async {
      final progressSnap = await transaction.get(progressRef);
      final specialtySnap = await transaction.get(specialtyRef);
      final progress = TrainingProgress.fromFirestore(
        progressSnap,
        program.modality,
      );
      if (progress.isOperational) {
        throw StateError('Cao ja esta operacional em ${program.name}.');
      }

      final currentModuleId = progress.currentModuleId ?? modules.first.id;
      if (currentModuleId != module.id) {
        throw StateError('Somente o modulo atual pode ser concluido.');
      }

      final achievements = progress.achievementsForModule(module.id);
      final missingRequired = module.activeMilestones
          .where(
            (milestone) =>
                milestone.isRequired &&
                achievements[milestone.id]?.achieved != true,
          )
          .toList();
      if (missingRequired.isNotEmpty) {
        throw StateError(
          'Marque os marcos obrigatorios antes de concluir o modulo.',
        );
      }

      final completedIds = {...progress.completedModuleIds, module.id}.toList();
      final existingCompleted = progress.completedModules
          .where((item) => item.moduleId != module.id)
          .map(_completedModuleToJson)
          .toList();
      final moduleSnapshot = {
        'module_id': module.id,
        'module_order': module.order,
        'module_name': module.name,
        'program_version': program.version,
        'completed_at': completedAt,
        'completed_by': actor,
        'milestones': module.activeMilestones.map((milestone) {
          final achieved = achievements[milestone.id];
          return {
            'milestone_id': milestone.id,
            'order': milestone.order,
            'label': milestone.label,
            'required': milestone.isRequired,
            'achieved': achieved?.achieved == true,
            'achieved_at': achieved?.achievedAt == null
                ? null
                : Timestamp.fromDate(achieved!.achievedAt!),
            'achieved_by': achieved?.achievedBy,
            'program_version': program.version,
          };
        }).toList(),
      };
      existingCompleted.add(moduleSnapshot);

      final moduleIndex = modules.indexWhere((item) => item.id == module.id);
      final nextModule = moduleIndex >= 0 && moduleIndex < modules.length - 1
          ? modules[moduleIndex + 1]
          : null;
      final isOperational = nextModule == null;

      transaction.set(progressRef, {
        'modality': program.modality,
        'status': isOperational ? 'operational' : 'in_formation',
        'current_module': isOperational ? null : nextModule.id,
        'current_module_id': isOperational ? null : nextModule.id,
        'program_version': program.version,
        'completed_module_ids': completedIds,
        'completed_modules': existingCompleted,
        'operational_since': isOperational ? completedAt : null,
        'updated_at': FieldValue.serverTimestamp(),
        'audit_trail': FieldValue.arrayUnion([entry]),
      }, SetOptions(merge: true));

      _syncSpecialtyInTransaction(
        transaction: transaction,
        specialtyRef: specialtyRef,
        specialtyExists: specialtySnap.exists,
        program: program,
        status: isOperational ? 'operational' : 'in_formation',
        currentModuleId: nextModule?.id,
        completedModuleCount: completedIds.length,
        operationalSince: isOperational ? completedAt : null,
        entry: entry,
      );
    });
  }

  Future<void> completeBonusMilestone({
    required String dogId,
    required TrainingProgram program,
    required TrainingModule module,
    required TrainingMilestone milestone,
  }) async {
    final progressRef = _progressRef(dogId, program.modality);
    final bonusRef = progressRef
        .collection('bonus_milestones')
        .doc(_bonusMilestoneDocId(module.id, milestone.id));
    final entry = AuditService.buildInlineEntry(
      action: 'created',
      fieldName: 'bonus_milestones',
    );
    final actor = _actorFromEntry(entry);

    await _firestore.runTransaction((transaction) async {
      final progressSnap = await transaction.get(progressRef);
      final progress = TrainingProgress.fromFirestore(
        progressSnap,
        program.modality,
      );
      if (!progress.isOperational) {
        throw StateError(
          'Marco-bonus so pode ser registrado para cao formado.',
        );
      }
      if (progress.completedModule(module.id) == null) {
        throw StateError('Modulo original nao esta concluido no snapshot.');
      }
      final bonusSnap = await transaction.get(bonusRef);
      if (bonusSnap.exists) {
        throw StateError('Marco-bonus ja registrado.');
      }

      transaction.set(bonusRef, {
        'module_id': module.id,
        'module_order': module.order,
        'module_name': module.name,
        'milestone_id': milestone.id,
        'milestone_order': milestone.order,
        'label': milestone.label,
        'required': milestone.isRequired,
        'program_version': program.version,
        'completed_at': FieldValue.serverTimestamp(),
        'by': actor,
        'completed_by': actor,
        'created_at': FieldValue.serverTimestamp(),
        'updated_at': FieldValue.serverTimestamp(),
        'audit_trail': [entry],
      });
    });
  }

  DocumentReference<Map<String, dynamic>> _progressRef(
    String dogId,
    String modality,
  ) {
    return _firestore
        .collection('dogs')
        .doc(dogId)
        .collection('training')
        .doc(modality);
  }

  String _bonusMilestoneDocId(String moduleId, String milestoneId) {
    return '${moduleId}__$milestoneId'.replaceAll('/', '_');
  }

  Future<DocumentReference<Map<String, dynamic>>> _specialtyRefFor(
    String dogId,
    String modality,
  ) async {
    final collection = _firestore
        .collection('dogs')
        .doc(dogId)
        .collection('specialties');
    final existing = await collection
        .where('type', isEqualTo: modality)
        .limit(1)
        .get();
    if (existing.docs.isNotEmpty) return existing.docs.first.reference;
    return collection.doc(modality);
  }

  void _syncSpecialtyInTransaction({
    required Transaction transaction,
    required DocumentReference<Map<String, dynamic>> specialtyRef,
    required bool specialtyExists,
    required TrainingProgram program,
    required String status,
    required String? currentModuleId,
    required int completedModuleCount,
    required Map<String, dynamic> entry,
    Timestamp? operationalSince,
  }) {
    final progress = program.activeModules.isEmpty
        ? 0
        : ((completedModuleCount / program.activeModules.length) * 100)
              .round()
              .clamp(0, 100);
    final payload = <String, dynamic>{
      'type': program.modality,
      'name': program.name,
      'status': status,
      'state': status,
      'program_version': program.version,
      'current_module': currentModuleId,
      'current_phase': currentModuleId,
      'progress_percentage': status == 'operational' ? 100 : progress,
      'updated_at': FieldValue.serverTimestamp(),
      'audit_trail': specialtyExists ? FieldValue.arrayUnion([entry]) : [entry],
    };
    if (!specialtyExists) {
      payload['created_at'] = FieldValue.serverTimestamp();
      payload['started_at'] = FieldValue.serverTimestamp();
    }
    if (operationalSince != null) {
      payload['operational_since'] = operationalSince;
    }

    transaction.set(specialtyRef, payload, SetOptions(merge: true));
  }

  bool _progressNeedsNormalization(Map<String, dynamic>? data) {
    if (data == null) return true;
    return data['modality'] is! String ||
        data['status'] is! String ||
        data['program_version'] is! int ||
        data['completed_module_ids'] is! List ||
        data['completed_modules'] is! List ||
        data['achieved_milestones'] is! Map;
  }

  Map<String, dynamic> _achievedMilestonesToJson(
    Map<String, Map<String, TrainingMilestoneAchievement>> value,
  ) {
    return value.map((moduleId, milestones) {
      return MapEntry(
        moduleId,
        milestones.map((milestoneId, achievement) {
          return MapEntry(milestoneId, {
            'milestone_id': achievement.milestoneId,
            'label': achievement.label,
            'required': achievement.isRequired,
            'achieved': achievement.achieved,
            'achieved_at': achievement.achievedAt == null
                ? null
                : Timestamp.fromDate(achievement.achievedAt!),
            'achieved_by': achievement.achievedBy,
            'program_version': achievement.programVersion,
          });
        }),
      );
    });
  }

  Map<String, dynamic> _completedModuleToJson(CompletedTrainingModule module) {
    return {
      'module_id': module.moduleId,
      'module_order': module.moduleOrder,
      'module_name': module.moduleName,
      'program_version': module.programVersion,
      'completed_at': module.completedAt == null
          ? null
          : Timestamp.fromDate(module.completedAt!),
      'completed_by': module.completedBy,
      'milestones': module.milestones.map((milestone) {
        return {
          'milestone_id': milestone.milestoneId,
          'label': milestone.label,
          'required': milestone.isRequired,
          'achieved': milestone.achieved,
          'achieved_at': milestone.achievedAt == null
              ? null
              : Timestamp.fromDate(milestone.achievedAt!),
          'achieved_by': milestone.achievedBy,
          'program_version': milestone.programVersion,
        };
      }).toList(),
    };
  }

  String _actorFromEntry(Map<String, dynamic> entry) {
    final byRa = entry['by_ra']?.toString().trim();
    if (byRa != null && byRa.isNotEmpty) return byRa;
    final by = entry['by']?.toString().trim();
    if (by != null && by.isNotEmpty) return by;
    return 'desconhecido';
  }
}
