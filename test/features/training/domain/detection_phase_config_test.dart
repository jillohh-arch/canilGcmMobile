import 'package:flutter_test/flutter_test.dart';

import 'package:canil_gcm/features/training/domain/detection/detection_phase_config.dart';

void main() {
  group('DetectionPhaseCatalog', () {
    test('mantém critérios configuráveis do Protocolo Ragonha', () {
      expect(DetectionPhaseCatalog.byCode('2v').targetConsecutiveHits, 3);
      expect(DetectionPhaseCatalog.byCode('4v').targetConsecutiveHits, 3);
      expect(DetectionPhaseCatalog.byCode('3v').targetConsecutiveHits, 10);
    });

    test('mantém bola até 3b e remove a partir de 3v', () {
      expect(DetectionPhaseCatalog.byCode('3b').usedBall, isTrue);
      expect(DetectionPhaseCatalog.byCode('3v').usedBall, isFalse);
    });

    test('prevê 4c no modelo sem liberar UI de caixas', () {
      final phase = DetectionPhaseCatalog.byCode('4c');

      expect(phase.isImplemented, isFalse);
      expect(phase.odorPositionMode, 'square');
    });
  });

  group('DetectionSessionRecorder', () {
    test('zera contador com um erro', () {
      final recorder = DetectionSessionRecorder(
        phase: DetectionPhaseCatalog.byCode('2v'),
      );

      recorder
        ..record(odorBox: 1, hit: true, at: DateTime(2026, 5, 24, 10))
        ..record(odorBox: 2, hit: true, at: DateTime(2026, 5, 24, 10, 1))
        ..record(odorBox: 1, hit: false, at: DateTime(2026, 5, 24, 10, 2));

      expect(recorder.currentStreak, 0);
      expect(recorder.longestStreak, 2);
      expect(recorder.criterionMet, isFalse);
    });

    test('atinge critério apenas com acertos consecutivos', () {
      final recorder = DetectionSessionRecorder(
        phase: DetectionPhaseCatalog.byCode('4v'),
      );

      recorder
        ..record(odorBox: 1, hit: true, at: DateTime(2026, 5, 24, 10))
        ..record(odorBox: 2, hit: true, at: DateTime(2026, 5, 24, 10, 1))
        ..record(odorBox: 3, hit: true, at: DateTime(2026, 5, 24, 10, 2));

      expect(recorder.currentStreak, 3);
      expect(recorder.criterionMet, isTrue);
    });
  });
}
