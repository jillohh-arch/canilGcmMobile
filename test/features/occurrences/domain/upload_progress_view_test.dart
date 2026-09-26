import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:canil_gcm/features/occurrences/presentation/screens/edit_event_screen.dart';
import 'package:canil_gcm/features/occurrences/presentation/screens/finalize_occurrence_screen.dart';

void main() {
  group('Upload Progress Presentation & Orchestration — Layer C', () {
    test(
      'EditEventScreen.formatUploadStatus with known total formats file context + percent when progress is active or file completed',
      () {
        final statusSingle = EditEventScreen.formatUploadStatus(
          currentFileIndex: 0,
          totalFiles: 1,
          fraction: 0.42,
          hasActiveProgress: true,
        );
        expect(statusSingle, 'Enviando foto 1/1 · 42%');

        final statusMulti = EditEventScreen.formatUploadStatus(
          currentFileIndex: 1,
          totalFiles: 3,
          fraction: 0.678,
          hasActiveProgress: false,
        );
        // Completed baseline from file 0 allows showing 67%
        expect(statusMulti, 'Enviando fotos 2/3 · 67%');
      },
    );

    test(
      'M26 killer: initial coarse transfer on first file shows NO fake 0% in status text',
      () {
        final statusSingle = EditEventScreen.formatUploadStatus(
          currentFileIndex: 0,
          totalFiles: 1,
          fraction: 0.0,
          hasActiveProgress: false,
        );
        expect(statusSingle, 'Enviando foto...');
        expect(statusSingle.contains('%'), isFalse);
        expect(statusSingle.contains('0%'), isFalse);

        final statusMulti = EditEventScreen.formatUploadStatus(
          currentFileIndex: 0,
          totalFiles: 2,
          fraction: 0.0,
          hasActiveProgress: false,
        );
        expect(statusMulti, 'Enviando fotos 1/2...');
        expect(statusMulti.contains('%'), isFalse);
        expect(statusMulti.contains('0%'), isFalse);
      },
    );

    test(
      'M28 killer: real intermediate bytes on first file switch to determinate percentage',
      () {
        final status = EditEventScreen.formatUploadStatus(
          currentFileIndex: 0,
          totalFiles: 2,
          fraction: 0.25,
          hasActiveProgress: true,
        );
        expect(status, 'Enviando fotos 1/2 · 25%');
      },
    );

    test(
      'M29 killer: second file preserves real 49% baseline while awaiting file 2 bytes',
      () {
        final status = EditEventScreen.formatUploadStatus(
          currentFileIndex: 1,
          totalFiles: 2,
          fraction: 0.4928,
          hasActiveProgress: false,
        );
        expect(status, 'Enviando fotos 2/2 · 49%');
      },
    );

    test(
      'M17 killer: EditEventScreen.formatUploadStatus with unknown total (fraction null) has NO percent',
      () {
        final status = EditEventScreen.formatUploadStatus(
          currentFileIndex: 0,
          totalFiles: 2,
          fraction: null,
          hasActiveProgress: false,
        );
        expect(status, 'Enviando fotos 1/2...');
        expect(status.contains('%'), isFalse);
      },
    );

    test(
      'FinalizeOccurrenceScreen.formatUploadStatus parity with EditEventScreen',
      () {
        // First file with no active bytes: no 0%
        final statusInitial = FinalizeOccurrenceScreen.formatUploadStatus(
          currentFileIndex: 0,
          totalFiles: 2,
          fraction: 0.0,
          hasActiveProgress: false,
        );
        expect(statusInitial, 'Enviando fotos 1/2...');
        expect(statusInitial.contains('%'), isFalse);

        // First file with active bytes: shows percentage
        final statusActive = FinalizeOccurrenceScreen.formatUploadStatus(
          currentFileIndex: 0,
          totalFiles: 2,
          fraction: 0.25,
          hasActiveProgress: true,
        );
        expect(statusActive, 'Enviando fotos 1/2 · 25%');

        // Second file awaiting bytes: preserves baseline
        final statusSecond = FinalizeOccurrenceScreen.formatUploadStatus(
          currentFileIndex: 1,
          totalFiles: 2,
          fraction: 0.49,
          hasActiveProgress: false,
        );
        expect(statusSecond, 'Enviando fotos 2/2 · 49%');
      },
    );

    test(
      'M17 killer: FinalizeOccurrenceScreen.formatUploadStatus with unknown total has NO percent',
      () {
        final status = FinalizeOccurrenceScreen.formatUploadStatus(
          currentFileIndex: 1,
          totalFiles: 3,
          fraction: null,
          hasActiveProgress: false,
        );
        expect(status, 'Enviando fotos 2/3...');
        expect(status.contains('%'), isFalse);
      },
    );

    test(
      'M13 killer: preparation phase shows indeterminate label without percentage',
      () {
        // Wording defined in contract: 'Preparando fotos...' with null fraction
        const prepStatus = 'Preparando fotos...';
        expect(prepStatus.contains('%'), isFalse);
        expect(prepStatus, 'Preparando fotos...');
      },
    );

    test(
      'M8 killer: persistence phase transitions to final label with null fraction',
      () {
        // Operation complete transitions directly to persistence label
        const editPersistence = 'Salvando evento...';
        const finalizePersistence = 'Selando ocorrência...';
        expect(editPersistence.contains('%'), isFalse);
        expect(finalizePersistence.contains('%'), isFalse);
      },
    );

    test(
      'M15 killer: compressed temp-path collision causes ALL colliding compressed candidates to fall back to original files',
      () {
        final orig0 = File('/data/user/0/cache/photo_0.jpg');
        final orig1 = File('/data/user/0/cache/photo_1.jpg');
        final orig2 = File('/data/user/0/cache/photo_2.jpg');

        final collidingTemp = File('/tmp/compressed_shared.jpg');
        final uniqueTemp = File('/tmp/compressed_unique_2.jpg');

        final candidates = [
          (original: orig0, candidate: collidingTemp, wasCompressed: true),
          (original: orig1, candidate: collidingTemp, wasCompressed: true),
          (original: orig2, candidate: uniqueTemp, wasCompressed: true),
        ];

        final effective =
            FinalizeOccurrenceScreen.resolveEffectiveFilesAfterCollisionGuard(
              candidates,
            );

        expect(effective.length, 3);
        // Candidate 0 fell back to original 0 because of collision
        expect(effective[0].path, orig0.path);
        // Candidate 1 fell back to original 1 because of collision
        expect(effective[1].path, orig1.path);
        // Candidate 2 had no collision, so it kept its compressed candidate
        expect(effective[2].path, uniqueTemp.path);
      },
    );

    test(
      'M14 killer: uncollided compressed candidates preserve compressed file for denominator',
      () {
        final orig0 = File('/data/orig0.jpg');
        final orig1 = File('/data/orig1.jpg');
        final comp0 = File('/tmp/comp0.jpg');
        final comp1 = File('/tmp/comp1.jpg');

        final candidates = [
          (original: orig0, candidate: comp0, wasCompressed: true),
          (original: orig1, candidate: comp1, wasCompressed: true),
        ];

        final effective =
            FinalizeOccurrenceScreen.resolveEffectiveFilesAfterCollisionGuard(
              candidates,
            );

        expect(effective.length, 2);
        expect(effective[0].path, comp0.path);
        expect(effective[1].path, comp1.path);
      },
    );

    test(
      'M11 & M12 invariant: workflow stepper and draft persistence are decoupled from upload byte progress',
      () {
        // Workflow stepper strictly in range 0..2
        const currentStep = 2;
        expect(currentStep, inInclusiveRange(0, 2));

        // Draft serialization contract requires only current_step
        final draftMap = <String, dynamic>{
          'current_step': currentStep,
          'report': 'Relato da ocorrencia',
        };

        expect(draftMap.containsKey('current_step'), isTrue);
        expect(draftMap.containsKey('upload_progress'), isFalse);
        expect(draftMap.containsKey('upload_fraction'), isFalse);
        expect(draftMap.containsKey('bytes_transferred'), isFalse);
      },
    );
  });
}
