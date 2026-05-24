import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:canil_gcm/features/training/data/detection_service.dart';
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
        expect(snap.data()!['status'], 'in_formation');
        expect(snap.data()!['current_phase'], '1b');
        expect(snap.data()!['audit_trail'], isNotEmpty);
      },
    );

    test(
      'persiste sessão com repetições e avança fase somente quando confirmado',
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
  });
}
