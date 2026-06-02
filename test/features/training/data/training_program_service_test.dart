import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:canil_gcm/features/training/data/training_program_service.dart';
import 'package:canil_gcm/features/training/domain/training_program.dart';

void main() {
  late FakeFirebaseFirestore firestore;
  late TrainingProgramService service;

  setUp(() {
    firestore = FakeFirebaseFirestore();
    service = TrainingProgramService(firestore: firestore);
  });

  test('monta curriculo com modulos e marcos ativos em ordem', () async {
    final programRef = firestore
        .collection('training_programs')
        .doc('busca_captura');

    await programRef.set({
      'name': 'Busca & Captura',
      'modality': 'busca_captura',
      'version': 1,
      'active': true,
    });
    await programRef.collection('modules').doc('modulo_2').set({
      'order': 2,
      'name': 'Modulo 2',
      'description': 'Segundo modulo',
      'active': true,
    });
    await programRef.collection('modules').doc('modulo_1').set({
      'order': 1,
      'name': 'Modulo 1',
      'description': 'Primeiro modulo',
      'active': true,
    });
    await programRef
        .collection('modules')
        .doc('modulo_1')
        .collection('milestones')
        .doc('marco_2')
        .set({
          'order': 2,
          'label': 'Segundo marco',
          'required': false,
          'active': true,
        });
    await programRef
        .collection('modules')
        .doc('modulo_1')
        .collection('milestones')
        .doc('marco_1')
        .set({
          'order': 1,
          'label': 'Primeiro marco',
          'required': true,
          'active': true,
        });

    final program = await service
        .watchProgram('busca_captura')
        .firstWhere(
          (program) =>
              program != null &&
              program.activeModules.length == 2 &&
              program.activeModules.first.activeMilestones.length == 2,
        )
        .timeout(const Duration(seconds: 2));

    expect(program, isNotNull);
    expect(program!.name, 'Busca & Captura');
    expect(program.activeModules.map((module) => module.id), [
      'modulo_1',
      'modulo_2',
    ]);
    expect(program.activeModules.first.activeMilestones.map((m) => m.label), [
      'Primeiro marco',
      'Segundo marco',
    ]);
    expect(program.activeModules.first.activeMilestones.last.isRequired, false);
  });

  test('progressao ausente retorna estado inicial de formacao', () async {
    final progress = await service
        .watchProgress('bono', 'busca_captura')
        .first
        .timeout(const Duration(seconds: 2));

    expect(progress.exists, false);
    expect(progress.status, 'in_formation');
    expect(progress.currentModuleId, isNull);
    expect(progress.completedModuleIds, isEmpty);
  });

  test(
    'inicializa progressao canonica e espelha specialty em formacao',
    () async {
      final program = _programWithTwoModules();

      await service.ensureProgressInitialized(dogId: 'thor', program: program);

      final progress = await firestore
          .collection('dogs')
          .doc('thor')
          .collection('training')
          .doc('busca_captura')
          .get();
      expect(progress.data()!['status'], 'in_formation');
      expect(progress.data()!['current_module'], 'modulo_1');
      expect(progress.data()!['program_version'], 1);

      final specialty = await firestore
          .collection('dogs')
          .doc('thor')
          .collection('specialties')
          .doc('busca_captura')
          .get();
      expect(specialty.data()!['type'], 'busca_captura');
      expect(specialty.data()!['status'], 'in_formation');
      expect(specialty.data()!['current_module'], 'modulo_1');
    },
  );

  test('normaliza progressao legada e permite salvar marco depois', () async {
    final program = _programWithTwoModules();
    final module = program.activeModules.first;
    final milestone = module.activeMilestones.first;

    await firestore
        .collection('dogs')
        .doc('thor')
        .collection('training')
        .doc('busca_captura')
        .set({'status': 'em_formacao', 'currentModuleId': 'modulo_1'});

    await service.ensureProgressInitialized(dogId: 'thor', program: program);

    final normalized = await firestore
        .collection('dogs')
        .doc('thor')
        .collection('training')
        .doc('busca_captura')
        .get();
    final normalizedData = normalized.data()!;
    expect(normalizedData['modality'], 'busca_captura');
    expect(normalizedData['status'], 'in_formation');
    expect(normalizedData['current_module'], 'modulo_1');
    expect(normalizedData['completed_module_ids'], isEmpty);
    expect(normalizedData['completed_modules'], isEmpty);
    expect(normalizedData['achieved_milestones'], isEmpty);

    await service.setMilestoneAchievement(
      dogId: 'thor',
      program: program,
      module: module,
      milestone: milestone,
      achieved: true,
    );

    final progress = await firestore
        .collection('dogs')
        .doc('thor')
        .collection('training')
        .doc('busca_captura')
        .get();
    final achievements =
        progress.data()!['achieved_milestones'] as Map<String, dynamic>;
    expect(achievements['modulo_1'], contains('marco_1'));

    final specialty = await firestore
        .collection('dogs')
        .doc('thor')
        .collection('specialties')
        .doc('busca_captura')
        .get();
    expect(specialty.data()!['status'], 'in_formation');
  });

  test('marca marco e conclui modulo com snapshot integro', () async {
    final program = _programWithTwoModules();
    final module = program.activeModules.first;
    final milestone = module.activeMilestones.first;

    await service.ensureProgressInitialized(dogId: 'thor', program: program);
    await service.setMilestoneAchievement(
      dogId: 'thor',
      program: program,
      module: module,
      milestone: milestone,
      achieved: true,
    );
    await service.completeCurrentModule(
      dogId: 'thor',
      program: program,
      module: module,
    );

    final progress = await firestore
        .collection('dogs')
        .doc('thor')
        .collection('training')
        .doc('busca_captura')
        .get();
    final data = progress.data()!;
    expect(data['status'], 'in_formation');
    expect(data['current_module'], 'modulo_2');
    expect(data['completed_module_ids'], ['modulo_1']);

    final completed = data['completed_modules'] as List<dynamic>;
    expect(completed, hasLength(1));
    final snapshot = completed.single as Map<String, dynamic>;
    expect(snapshot['module_id'], 'modulo_1');
    expect(snapshot['program_version'], 1);
    final milestones = snapshot['milestones'] as List<dynamic>;
    expect(milestones.single['label'], 'Marco obrigatorio');
    expect(milestones.single['required'], true);
    expect(milestones.single['achieved'], true);

    final specialty = await firestore
        .collection('dogs')
        .doc('thor')
        .collection('specialties')
        .doc('busca_captura')
        .get();
    expect(specialty.data()!['status'], 'in_formation');
    expect(specialty.data()!['current_module'], 'modulo_2');
  });

  test(
    'concluir ultimo modulo torna operacional e sincroniza specialty',
    () async {
      final program = _programWithOneModule();
      final module = program.activeModules.single;
      final milestone = module.activeMilestones.single;

      await service.ensureProgressInitialized(dogId: 'bono', program: program);
      await service.setMilestoneAchievement(
        dogId: 'bono',
        program: program,
        module: module,
        milestone: milestone,
        achieved: true,
      );
      await service.completeCurrentModule(
        dogId: 'bono',
        program: program,
        module: module,
      );

      final progress = await firestore
          .collection('dogs')
          .doc('bono')
          .collection('training')
          .doc('busca_captura')
          .get();
      expect(progress.data()!['status'], 'operational');
      expect(progress.data()!['current_module'], isNull);
      expect(progress.data()!['operational_since'], isNotNull);

      final specialty = await firestore
          .collection('dogs')
          .doc('bono')
          .collection('specialties')
          .doc('busca_captura')
          .get();
      expect(specialty.data()!['status'], 'operational');
      expect(specialty.data()!['operational_since'], isNotNull);
      expect(specialty.data()!['progress_percentage'], 100);
    },
  );

  test('marco bonus e aditivo e nao altera snapshot original', () async {
    final program = TrainingProgram(
      id: 'busca_captura',
      name: 'Busca & Captura',
      modality: 'busca_captura',
      version: 2,
      active: true,
      modules: [
        TrainingModule(
          id: 'modulo_1',
          order: 1,
          name: 'Modulo 1',
          description: 'Modulo de teste',
          active: true,
          milestones: const [
            TrainingMilestone(
              id: 'marco_original',
              order: 1,
              label: 'Marco original',
              isRequired: true,
              active: true,
            ),
            TrainingMilestone(
              id: 'marco_bonus',
              order: 2,
              label: 'Marco bonus',
              isRequired: true,
              active: true,
            ),
          ],
        ),
      ],
    );

    final progressRef = firestore
        .collection('dogs')
        .doc('bono')
        .collection('training')
        .doc('busca_captura');
    await progressRef.set({
      'modality': 'busca_captura',
      'status': 'operational',
      'current_module': null,
      'current_module_id': null,
      'program_version': 1,
      'completed_module_ids': ['modulo_1'],
      'completed_modules': [
        {
          'module_id': 'modulo_1',
          'module_order': 1,
          'module_name': 'Modulo 1',
          'program_version': 1,
          'milestones': [
            {
              'milestone_id': 'marco_original',
              'order': 1,
              'label': 'Marco original',
              'required': true,
              'achieved': true,
              'program_version': 1,
            },
          ],
        },
      ],
      'achieved_milestones': const <String, dynamic>{},
      'operational_since': Timestamp.now(),
      'audit_trail': const [
        {'action': 'created'},
      ],
    });

    final progress = TrainingProgress.fromFirestore(
      await progressRef.get(),
      'busca_captura',
    );
    final offers = service.bonusOffersFor(
      program: program,
      progress: progress,
      completedBonuses: const [],
    );
    expect(offers.map((offer) => offer.milestone.id), ['marco_bonus']);

    await service.completeBonusMilestone(
      dogId: 'bono',
      program: program,
      module: program.activeModules.single,
      milestone: program.activeModules.single.activeMilestones.last,
    );

    final bonus = await progressRef
        .collection('bonus_milestones')
        .doc('modulo_1__marco_bonus')
        .get();
    expect(bonus.exists, true);
    expect(bonus.data()!['label'], 'Marco bonus');

    final unchangedProgress = await progressRef.get();
    final completed =
        unchangedProgress.data()!['completed_modules'] as List<dynamic>;
    final milestones = completed.single['milestones'] as List<dynamic>;
    expect(milestones, hasLength(1));
    expect(milestones.single['milestone_id'], 'marco_original');
  });
}

TrainingProgram _programWithTwoModules() {
  return TrainingProgram(
    id: 'busca_captura',
    name: 'Busca & Captura',
    modality: 'busca_captura',
    version: 1,
    active: true,
    modules: [_module('modulo_1', 1), _module('modulo_2', 2)],
  );
}

TrainingProgram _programWithOneModule() {
  return TrainingProgram(
    id: 'busca_captura',
    name: 'Busca & Captura',
    modality: 'busca_captura',
    version: 1,
    active: true,
    modules: [_module('modulo_1', 1)],
  );
}

TrainingModule _module(String id, int order) {
  return TrainingModule(
    id: id,
    order: order,
    name: 'Modulo $order',
    description: 'Modulo de teste',
    active: true,
    milestones: [
      TrainingMilestone(
        id: 'marco_$order',
        order: 1,
        label: 'Marco obrigatorio',
        isRequired: true,
        active: true,
      ),
    ],
  );
}
