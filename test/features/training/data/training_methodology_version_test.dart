import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:canil_gcm/features/training/data/training_program_service.dart';
import 'package:canil_gcm/features/training/domain/detection/detection_formation_session.dart';
import 'package:canil_gcm/features/training/domain/training_program.dart';

void main() {
  late FakeFirebaseFirestore firestore;
  late TrainingProgramService service;

  setUp(() {
    firestore = FakeFirebaseFirestore();
    service = TrainingProgramService(firestore: firestore);
  });

  test('watchProgram with programId loads physical versioned document', () async {
    final versionDoc = firestore
        .collection('training_programs')
        .doc('ragonha-v2');

    await versionDoc.set({
      'name': 'Método Ragonha',
      'modality': 'faro_deteccao',
      'version': 2,
      'status': 'published',
      'methodology_family_id': 'ragonha',
      'active': true,
    });
    await versionDoc.collection('modules').doc('modulo_caixa').set({
      'order': 1,
      'title': 'Caixas de Odor v2',
      'description': 'Treino de caixas',
      'active': true,
    });
    await versionDoc
        .collection('modules')
        .doc('modulo_caixa')
        .collection('milestones')
        .doc('marco_1')
        .set({
          'order': 1,
          'title': 'Indicação passiva refinada',
          'required': true,
          'active': true,
        });

    final program = await service
        .watchProgram('faro_deteccao', programId: 'ragonha-v2')
        .firstWhere(
          (p) =>
              p != null &&
              p.activeModules.isNotEmpty &&
              p.activeModules.first.activeMilestones.isNotEmpty,
        )
        .timeout(const Duration(seconds: 2));

    expect(program, isNotNull);
    expect(program!.id, 'ragonha-v2');
    expect(program.name, 'Método Ragonha');
    expect(program.version, 2);
    expect(program.methodologyFamilyId, 'ragonha');
    expect(program.activeModules.first.name, 'Caixas de Odor v2');
    expect(
      program.activeModules.first.activeMilestones.first.label,
      'Indicação passiva refinada',
    );
  });

  test('watchProgramForDog resolves versioned program from dog progress', () async {
    // 1. Seed versioned program
    final progRef = firestore
        .collection('training_programs')
        .doc('guarda-v2');
    await progRef.set({
      'name': 'Guarda e Proteção Avançada',
      'modality': 'guarda_protecao',
      'version': 2,
      'methodology_family_id': 'guarda-patrulha',
      'active': true,
    });
    await progRef.collection('modules').doc('m1').set({
      'order': 1,
      'name': 'Módulo 1 v2',
      'active': true,
    });
    await progRef.collection('modules').doc('m1').collection('milestones').doc('ms1').set({
      'order': 1,
      'label': 'Mordida Firme',
      'required': true,
      'active': true,
    });

    // 2. Seed dog training progress pointing to guarda-v2
    await firestore
        .collection('dogs')
        .doc('thor')
        .collection('training')
        .doc('guarda_protecao')
        .set({
          'status': 'in_formation',
          'program_id': 'guarda-v2',
          'program_version_id': 'guarda-v2',
          'methodology_family_id': 'guarda-patrulha',
          'methodology_display_name': 'Guarda e Proteção Avançada',
          'methodology_version': 2,
          'current_module': 'm1',
          'current_module_id': 'm1',
        });

    final program = await service
        .watchProgramForDog('thor', 'guarda_protecao')
        .firstWhere((p) => p != null && p.id == 'guarda-v2')
        .timeout(const Duration(seconds: 2));

    expect(program, isNotNull);
    expect(program!.id, 'guarda-v2');
    expect(program.name, 'Guarda e Proteção Avançada');
    expect(program.version, 2);
  });

  test('TrainingProgress.fromFirestore reads methodology lineage and assignment history', () async {
    final docRef = firestore
        .collection('dogs')
        .doc('atlas')
        .collection('training')
        .doc('busca_captura');

    await docRef.set({
      'status': 'in_formation',
      'program_id': 'bc-v3',
      'program_version_id': 'bc-v3',
      'methodology_family_id': 'mantrailing-k9',
      'methodology_display_name': 'Mantrailing Urbano',
      'methodology_version': 3,
      'assigned_at': Timestamp.fromDate(DateTime(2026, 9, 9, 10, 0)),
      'assigned_by': 'GCM Silva (RA 1024)',
      'initial_module_id': 'mod_pista_longa',
      'initial_module_justification': 'Cão já realizou nivelamento prévio',
      'assignment_history': [
        {
          'program_id': 'bc-v1',
          'program_version': 1,
          'assigned_at': '2026-01-01T00:00:00.000Z',
          'action': 'initial_assignment',
        },
        {
          'program_id': 'bc-v3',
          'program_version': 3,
          'assigned_at': '2026-09-09T10:00:00.000Z',
          'action': 'deliberate_migration',
          'justification': 'Migração para metodologia v3',
        },
      ],
    });

    final snapshot = await docRef.get();
    final progress = TrainingProgress.fromFirestore(snapshot, 'busca_captura');

    expect(progress.programId, 'bc-v3');
    expect(progress.programVersionId, 'bc-v3');
    expect(progress.methodologyFamilyId, 'mantrailing-k9');
    expect(progress.methodologyDisplayName, 'Mantrailing Urbano');
    expect(progress.methodologyVersion, 3);
    expect(progress.assignedBy, 'GCM Silva (RA 1024)');
    expect(progress.initialModuleId, 'mod_pista_longa');
    expect(progress.initialModuleJustification, 'Cão já realizou nivelamento prévio');
    expect(progress.assignmentHistory, hasLength(2));
    expect(progress.assignmentHistory.first['action'], 'initial_assignment');
    expect(progress.assignmentHistory.last['action'], 'deliberate_migration');
  });

  test('ensureProgressInitialized writes methodology lineage to Firestore', () async {
    final program = TrainingProgram(
      id: 'ragonha-v2',
      name: 'Método Ragonha',
      modality: 'faro_deteccao',
      version: 2,
      methodologyFamilyId: 'ragonha',
      active: true,
      modules: [
        TrainingModule(
          id: 'caixas',
          order: 1,
          name: 'Caixas',
          description: 'Caixas de odor',
          active: true,
          milestones: const [],
        ),
      ],
    );

    await service.ensureProgressInitialized(
      dogId: 'ares',
      program: program,
    );

    final doc = await firestore
        .collection('dogs')
        .doc('ares')
        .collection('training')
        .doc('faro_deteccao')
        .get();

    expect(doc.exists, true);
    final data = doc.data()!;
    expect(data['program_id'], 'ragonha-v2');
    expect(data['program_version_id'], 'ragonha-v2');
    expect(data['methodology_family_id'], 'ragonha');
    expect(data['methodology_display_name'], 'Método Ragonha');
    expect(data['methodology_version'], 2);
  });

  test('DetectionFormationSession.toJson stamps methodology lineage stamps', () {
    final session = DetectionFormationSession(
      dogId: 'zeus',
      dogName: 'Zeus',
      lineId: 'linear_1',
      lineName: 'Linear 1',
      lineType: 'linear',
      phase: 'phase_1',
      phaseName: 'Fase 1',
      boxCount: 6,
      odorPositionMode: 'manual',
      usedBall: true,
      odorMaterial: 'nose_mp',
      status: 'completed_by_criterion',
      startedAt: DateTime(2026, 9, 9, 12, 0),
      durationSeconds: 180,
      repetitions: const [],
      totalReps: 5,
      longestStreak: 5,
      currentStreak: 5,
      criterionMet: true,
      phaseAdvanced: true,
      handlerId: 'RA 9999',
      handlerName: 'Condutor Teste',
    );

    final json = session.toJson();

    expect(json['program_id'], 'ragonha-v1');
    expect(json['program_version_id'], 'ragonha-v1');
    expect(json['methodology_family_id'], 'ragonha');
    expect(json['methodology_display_name'], 'Método Ragonha');
    expect(json['methodology_version'], 1);

    final metadata = json['metadata'] as Map<String, dynamic>;
    expect(metadata['program_id'], 'ragonha-v1');
    expect(metadata['program_version_id'], 'ragonha-v1');
    expect(metadata['methodology_family_id'], 'ragonha');
    expect(metadata['methodology_display_name'], 'Método Ragonha');
    expect(metadata['methodology_version'], 1);
  });
}
