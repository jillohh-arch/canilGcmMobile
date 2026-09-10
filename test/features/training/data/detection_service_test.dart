import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:canil_gcm/features/training/data/detection_service.dart';
import 'package:canil_gcm/features/training/domain/detection/detection_formation_session.dart';
import 'package:canil_gcm/features/training/domain/detection/detection_phase_config.dart';

void main() {
  late FakeFirebaseFirestore firestore;
  late DetectionService service;

  setUp(() {
    firestore = FakeFirebaseFirestore();
    service = DetectionService(firestore: firestore);
  });

  group('DetectionService', () {
    test(
      'cria linhas reais de detecção quando o cão ainda não possui progresso',
      () async {
        final lines = await service.getOrCreateDefaultLines(
          dogId: 'dog-1',
          handlerId: '12345',
          handlerName: 'GCM Teste',
        );

        expect(lines.map((line) => line.normalizedType), [
          'drogas',
          'armas',
          'cadaver',
        ]);

        final snap = await firestore
            .collection('dogs')
            .doc('dog-1')
            .collection('detection_lines')
            .doc('drogas')
            .get();

        expect(snap.exists, isTrue);
        expect(snap.data()!['status'], 'not_started');
        expect(snap.data()!['started_at'], isNull);
        expect(snap.data()!['current_phase'], '1b');
        expect(snap.data()!['audit_trail'], isNotEmpty);
      },
    );

    test(
      'persiste sessão com repetições e avança fase automaticamente pelo critério',
      () async {
        final lines = await service.getOrCreateDefaultLines(
          dogId: 'dog-1',
          handlerId: '12345',
          handlerName: 'GCM Teste',
        );
        final line = lines.first;
        final phase = DetectionPhaseCatalog.byCode('1b');
        final recorder = DetectionSessionRecorder(phase: phase)
          ..record(odorBox: 1, hit: true, at: DateTime(2026, 5, 24, 10))
          ..record(odorBox: 1, hit: true, at: DateTime(2026, 5, 24, 10, 1))
          ..record(odorBox: 1, hit: true, at: DateTime(2026, 5, 24, 10, 2));

        final session = await service.saveFormationSession(
          dogId: 'dog-1',
          dogName: 'Bono',
          line: line,
          phase: phase,
          startedAt: DateTime(2026, 5, 24, 10),
          recorder: recorder,
          advancePhase: true,
          handlerId: '12345',
          handlerName: 'GCM Teste',
        );

        final sessionSnap = await firestore
            .collection('dogs')
            .doc('dog-1')
            .collection('training_sessions')
            .doc(session.id)
            .get();
        final sessionData = sessionSnap.data()!;

        expect(sessionData['type'], 'detection_formation');
        expect(
          sessionData['status'],
          DetectionFormationStatus.completedByCriterion,
        );
        expect(sessionData['phase'], '1b');
        expect(sessionData['repetitions'], hasLength(3));
        expect(sessionData['criterion_met'], isTrue);
        expect(sessionData['phase_advanced'], isTrue);
        expect(sessionData['advanced_to'], '2b');
        expect(sessionData['integrity_hash'], isNull);

        final lineSnap = await firestore
            .collection('dogs')
            .doc('dog-1')
            .collection('detection_lines')
            .doc('drogas')
            .get();
        final lineData = lineSnap.data()!;

        expect(lineData['current_phase'], '2b');
        expect(lineData['phases_completed'], contains('1b'));
        expect(lineData['phase_history'], isNotEmpty);
      },
    );

    test(
      'salva sessão em andamento repetição a repetição sem hash imutável',
      () async {
        final lines = await service.getOrCreateDefaultLines(
          dogId: 'dog-1',
          handlerId: '12345',
          handlerName: 'GCM Teste',
        );
        final line = lines.first;
        final phase = DetectionPhaseCatalog.byCode('2v');
        final session = await service.startFormationSession(
          dogId: 'dog-1',
          dogName: 'Bono',
          line: line,
          phase: phase,
          odorMaterial: DetectionOdorMaterials.real,
          handlerId: '12345',
          handlerName: 'GCM Teste',
        );
        final recorder = DetectionSessionRecorder(phase: phase)
          ..record(odorBox: 2, hit: true, at: DateTime(2026, 5, 24, 10));

        final saved = await service.autosaveFormationProgress(
          session: session,
          phase: phase,
          recorder: recorder,
          handlerId: '12345',
          handlerName: 'GCM Teste',
        );

        final snap = await firestore
            .collection('dogs')
            .doc('dog-1')
            .collection('training_sessions')
            .doc(saved.id)
            .get();
        final data = snap.data()!;

        expect(data['status'], DetectionFormationStatus.inProgress);
        expect(data['repetitions'], hasLength(1));
        expect(data['odor_material'], DetectionOdorMaterials.real);
        expect(data['integrity_hash'], isNull);
      },
    );

    test('encerra sem critério sem avançar a fase da linha', () async {
      final lines = await service.getOrCreateDefaultLines(
        dogId: 'dog-1',
        handlerId: '12345',
        handlerName: 'GCM Teste',
      );
      final line = lines.first;
      final phase = DetectionPhaseCatalog.byCode('1b');
      final session = await service.startFormationSession(
        dogId: 'dog-1',
        dogName: 'Bono',
        line: line,
        phase: phase,
        odorMaterial: DetectionOdorMaterials.noseMp,
        handlerId: '12345',
        handlerName: 'GCM Teste',
      );
      final recorder = DetectionSessionRecorder(phase: phase)
        ..record(odorBox: 1, hit: true, at: DateTime(2026, 5, 24, 10))
        ..record(odorBox: 1, hit: false, at: DateTime(2026, 5, 24, 10, 1));

      final ended = await service.endFormationWithoutCriterion(
        session: session,
        phase: phase,
        recorder: recorder,
        handlerId: '12345',
        handlerName: 'GCM Teste',
      );

      final lineSnap = await firestore
          .collection('dogs')
          .doc('dog-1')
          .collection('detection_lines')
          .doc('drogas')
          .get();

      expect(ended.status, DetectionFormationStatus.endedWithoutCriterion);
      expect(lineSnap.data()!['current_phase'], '1b');
      expect(lineSnap.data()!['phases_completed'], isEmpty);
    });

    test('conclusão de revisão não retrocede fase já avançada', () async {
      final lines = await service.getOrCreateDefaultLines(
        dogId: 'dog-1',
        handlerId: '12345',
        handlerName: 'GCM Teste',
      );
      final line = lines.first;
      final phase1 = DetectionPhaseCatalog.byCode('1b');
      final recorder1 = DetectionSessionRecorder(phase: phase1)
        ..record(odorBox: 1, hit: true, at: DateTime(2026, 5, 24, 10))
        ..record(odorBox: 1, hit: true, at: DateTime(2026, 5, 24, 10, 1))
        ..record(odorBox: 1, hit: true, at: DateTime(2026, 5, 24, 10, 2));
      await service.saveFormationSession(
        dogId: 'dog-1',
        dogName: 'Bono',
        line: line,
        phase: phase1,
        startedAt: DateTime(2026, 5, 24, 10),
        recorder: recorder1,
        advancePhase: true,
        handlerId: '12345',
        handlerName: 'GCM Teste',
      );

      final advancedLine = (await service.getLines('dog-1')).first;
      final reviewSession = await service.startFormationSession(
        dogId: 'dog-1',
        dogName: 'Bono',
        line: advancedLine,
        phase: phase1,
        odorMaterial: DetectionOdorMaterials.noseMp,
        handlerId: '12345',
        handlerName: 'GCM Teste',
      );
      final reviewRecorder = DetectionSessionRecorder(phase: phase1)
        ..record(odorBox: 1, hit: true, at: DateTime(2026, 5, 24, 11))
        ..record(odorBox: 1, hit: true, at: DateTime(2026, 5, 24, 11, 1))
        ..record(odorBox: 1, hit: true, at: DateTime(2026, 5, 24, 11, 2));

      final review = await service.completeFormationByCriterion(
        session: reviewSession,
        line: advancedLine,
        phase: phase1,
        recorder: reviewRecorder,
        handlerId: '12345',
        handlerName: 'GCM Teste',
      );

      final lineSnap = await firestore
          .collection('dogs')
          .doc('dog-1')
          .collection('detection_lines')
          .doc('drogas')
          .get();

      expect(review.phaseAdvanced, isFalse);
      expect(lineSnap.data()!['current_phase'], '2b');
      expect(lineSnap.data()!['phases_completed'], ['1b']);
    });

    group('Linhagem Curricular e Versionamento (F50)', () {
      test('Caso A — assignment v1: grava metadata e raiz v1', () async {
        // Atribui v1 ao cão
        await firestore
            .collection('dogs')
            .doc('dog-v1')
            .collection('training')
            .doc('faro_deteccao')
            .set({
          'program_id': 'ragonha-v1',
          'program_version_id': 'ragonha-v1',
          'methodology_family_id': 'ragonha',
          'methodology_display_name': 'Método Ragonha',
          'methodology_version': 1,
        });

        final lines = await service.getOrCreateDefaultLines(
          dogId: 'dog-v1',
          handlerId: '12345',
          handlerName: 'GCM Teste',
        );
        final line = lines.first;
        final phase = DetectionPhaseCatalog.byCode('1b');
        final recorder = DetectionSessionRecorder(phase: phase)
          ..record(odorBox: 1, hit: true, at: DateTime(2026, 5, 24, 10));

        final session = await service.saveFormationSession(
          dogId: 'dog-v1',
          dogName: 'Thor',
          line: line,
          phase: phase,
          startedAt: DateTime(2026, 5, 24, 10),
          recorder: recorder,
          advancePhase: false,
          handlerId: '12345',
          handlerName: 'GCM Teste',
        );

        final snap = await firestore
            .collection('dogs')
            .doc('dog-v1')
            .collection('training_sessions')
            .doc(session.id)
            .get();
        final data = snap.data()!;

        expect(data['program_id'], 'ragonha-v1');
        expect(data['methodology_version'], 1);
        expect(data['methodology_family_id'], 'ragonha');
        expect(data['methodology_display_name'], 'Método Ragonha');

        final meta = data['metadata'] as Map<String, dynamic>;
        expect(meta['program_id'], 'ragonha-v1');
        expect(meta['methodology_version'], 1);
        expect(meta['methodology_family_id'], 'ragonha');
        expect(meta['methodology_display_name'], 'Método Ragonha');
      });

      test('Caso B — assignment v3: grava metadata e raiz v3 (PROVA QUE NÃO GRAVA v1)', () async {
        // Atribui v3 ao cão
        await firestore
            .collection('dogs')
            .doc('dog-v3')
            .collection('training')
            .doc('faro_deteccao')
            .set({
          'program_id': 'ragonha-v3',
          'program_version_id': 'ragonha-v3',
          'methodology_family_id': 'ragonha',
          'methodology_display_name': 'Método Ragonha Avançado',
          'methodology_version': 3,
        });

        final lines = await service.getOrCreateDefaultLines(
          dogId: 'dog-v3',
          handlerId: '12345',
          handlerName: 'GCM Teste',
        );
        final line = lines.first;
        final phase = DetectionPhaseCatalog.byCode('1b');
        final recorder = DetectionSessionRecorder(phase: phase)
          ..record(odorBox: 1, hit: true, at: DateTime(2026, 5, 24, 10));

        final session = await service.saveFormationSession(
          dogId: 'dog-v3',
          dogName: 'Bono',
          line: line,
          phase: phase,
          startedAt: DateTime(2026, 5, 24, 10),
          recorder: recorder,
          advancePhase: false,
          handlerId: '12345',
          handlerName: 'GCM Teste',
        );

        final snap = await firestore
            .collection('dogs')
            .doc('dog-v3')
            .collection('training_sessions')
            .doc(session.id)
            .get();
        final data = snap.data()!;

        // PROVA OBJETIVA DE QUE NÃO GRAVA v1
        expect(data['program_id'], 'ragonha-v3');
        expect(data['program_id'], isNot('ragonha-v1'));
        expect(data['methodology_version'], 3);
        expect(data['methodology_version'], isNot(1));
        expect(data['methodology_family_id'], 'ragonha');
        expect(data['methodology_display_name'], 'Método Ragonha Avançado');

        final meta = data['metadata'] as Map<String, dynamic>;
        expect(meta['program_id'], 'ragonha-v3');
        expect(meta['program_id'], isNot('ragonha-v1'));
        expect(meta['methodology_version'], 3);
        expect(meta['methodology_version'], isNot(1));
        expect(meta['methodology_family_id'], 'ragonha');
        expect(meta['methodology_display_name'], 'Método Ragonha Avançado');
      });

      test('Caso C — fallback legado: sem assignment disponível grava default v1', () async {
        // Cão sem nenhum documento em dogs/{dogId}/training/faro_deteccao
        final lines = await service.getOrCreateDefaultLines(
          dogId: 'dog-legado',
          handlerId: '12345',
          handlerName: 'GCM Teste',
        );
        final line = lines.first;
        final phase = DetectionPhaseCatalog.byCode('1b');
        final recorder = DetectionSessionRecorder(phase: phase)
          ..record(odorBox: 1, hit: true, at: DateTime(2026, 5, 24, 10));

        final session = await service.saveFormationSession(
          dogId: 'dog-legado',
          dogName: 'Zeus',
          line: line,
          phase: phase,
          startedAt: DateTime(2026, 5, 24, 10),
          recorder: recorder,
          advancePhase: false,
          handlerId: '12345',
          handlerName: 'GCM Teste',
        );

        final snap = await firestore
            .collection('dogs')
            .doc('dog-legado')
            .collection('training_sessions')
            .doc(session.id)
            .get();
        final data = snap.data()!;

        // Fallback de compatibilidade
        expect(data['program_id'], 'ragonha-v1');
        expect(data['methodology_version'], 1);
        expect(data['methodology_family_id'], 'ragonha');
        expect(data['methodology_display_name'], 'Método Ragonha');

        final meta = data['metadata'] as Map<String, dynamic>;
        expect(meta['program_id'], 'ragonha-v1');
        expect(meta['methodology_version'], 1);
      });

      test('Caso D — publicação de v4: não altera sessão histórica já gravada em v3', () async {
        // 1. Cão tem atribuição em v3 e grava sessão
        await firestore
            .collection('dogs')
            .doc('dog-hist')
            .collection('training')
            .doc('faro_deteccao')
            .set({
          'program_id': 'ragonha-v3',
          'program_version_id': 'ragonha-v3',
          'methodology_family_id': 'ragonha',
          'methodology_display_name': 'Método Ragonha v3',
          'methodology_version': 3,
        });

        final lines = await service.getOrCreateDefaultLines(
          dogId: 'dog-hist',
          handlerId: '12345',
          handlerName: 'GCM Teste',
        );
        final line = lines.first;
        final phase = DetectionPhaseCatalog.byCode('1b');
        final recorder = DetectionSessionRecorder(phase: phase)
          ..record(odorBox: 1, hit: true, at: DateTime(2026, 5, 24, 10));

        final session = await service.saveFormationSession(
          dogId: 'dog-hist',
          dogName: 'Atlas',
          line: line,
          phase: phase,
          startedAt: DateTime(2026, 5, 24, 10),
          recorder: recorder,
          advancePhase: false,
          handlerId: '12345',
          handlerName: 'GCM Teste',
        );

        // 2. Simulamos a publicação de uma nova versão ragonha-v4 no catálogo
        await firestore
            .collection('training_programs')
            .doc('ragonha-v4')
            .set({
          'name': 'Método Ragonha v4',
          'version': 4,
          'status': 'published',
          'methodology_family_id': 'ragonha',
        });

        // 3. Lê novamente a sessão salva do Firestore
        final snap = await firestore
            .collection('dogs')
            .doc('dog-hist')
            .collection('training_sessions')
            .doc(session.id)
            .get();
        final data = snap.data()!;

        // A sessão pré-existente PERMANECE em v3, sem sofrer contaminação
        expect(data['program_id'], 'ragonha-v3');
        expect(data['methodology_version'], 3);
        expect(data['program_id'], isNot('ragonha-v4'));
        expect(data['methodology_version'], isNot(4));

        final reloadedSession = DetectionFormationSession.fromJson(data, docId: session.id);
        expect(reloadedSession.programId, 'ragonha-v3');
        expect(reloadedSession.methodologyVersion, 3);
      });
    });
  });
}
