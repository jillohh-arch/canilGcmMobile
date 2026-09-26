import 'package:flutter_test/flutter_test.dart';
import 'package:canil_gcm/features/occurrences/domain/upload_progress_aggregator.dart';

void main() {
  group('UploadProgressAggregator — Layer A Pure Math', () {
    test(
      'M1 killer: 1 MB + 9 MB -> after first completes ≈ 0.10, NOT 0.50 file count',
      () {
        const oneMb = 1024 * 1024;
        const nineMb = 9 * 1024 * 1024;
        final aggregator = UploadProgressAggregator([oneMb, nineMb]);

        expect(aggregator.totalFiles, 2);
        expect(aggregator.totalBytes, 10 * 1024 * 1024);
        expect(aggregator.current.fraction, 0.0);
        expect(aggregator.current.completedFiles, 0);

        // Upload first file halfway
        final midFirst = aggregator.updateFileProgress(0, oneMb ~/ 2);
        expect(midFirst.transferredBytes, oneMb ~/ 2);
        expect(midFirst.fraction, closeTo(0.05, 0.001));

        // First file completes
        final firstDone = aggregator.completeFile(0);
        expect(firstDone.completedFiles, 1);
        expect(firstDone.transferredBytes, oneMb);
        // Byte fraction is exactly 0.10, NOT 0.50 (file count)
        expect(firstDone.fraction, closeTo(0.10, 0.001));
        expect(firstDone.fraction, isNot(closeTo(0.50, 0.01)));
      },
    );

    test('single file incremental progress', () {
      final aggregator = UploadProgressAggregator([1000]);

      final p1 = aggregator.updateFileProgress(0, 250);
      expect(p1.transferredBytes, 250);
      expect(p1.fraction, closeTo(0.25, 0.001));

      final p2 = aggregator.updateFileProgress(0, 750);
      expect(p2.transferredBytes, 750);
      expect(p2.fraction, closeTo(0.75, 0.001));

      final p3 = aggregator.completeFile(0);
      expect(p3.completedFiles, 1);
      expect(p3.transferredBytes, 1000);
      expect(p3.fraction, 1.0);
    });

    test(
      'M3 killer: completed file commits declared size even if last progress event was partial or missed',
      () {
        final aggregator = UploadProgressAggregator([1000, 2000]);

        // File 0 only reported 400 bytes before completing
        aggregator.updateFileProgress(0, 400);
        final done0 = aggregator.completeFile(0);

        // Must commit declared length 1000, not the last snapshot 400
        expect(done0.transferredBytes, 1000);
        expect(done0.fraction, closeTo(1000 / 3000, 0.001));
      },
    );

    test(
      'M4 killer: monotonicity under simulated rewind/retry event never moves backwards',
      () {
        final aggregator = UploadProgressAggregator([10000]);

        final step1 = aggregator.updateFileProgress(0, 6000);
        expect(step1.fraction, closeTo(0.60, 0.001));

        // Simulated rewind/retry event reporting 3000 bytes
        final step2 = aggregator.updateFileProgress(0, 3000);
        // Monotonicity latch maintains at least 0.60
        expect(step2.fraction, closeTo(0.60, 0.001));
      },
    );

    test(
      'M5 killer: bytesTransferred exceeding declared file size is clamped',
      () {
        final aggregator = UploadProgressAggregator([1000]);

        final over = aggregator.updateFileProgress(0, 5000);
        expect(over.transferredBytes, 1000);
        expect(over.fraction, 1.0);

        final negative = aggregator.updateFileProgress(0, -500);
        expect(negative.transferredBytes, 0);
        // Monotonic latch holds previous 1.0 fraction
        expect(negative.fraction, 1.0);
      },
    );

    test(
      'M6 & M17 killer: totalBytes <= 0 produces fraction == null, no NaN or Infinity',
      () {
        final zeroAggregator = UploadProgressAggregator([0, 0]);
        expect(zeroAggregator.totalBytes, 0);
        expect(zeroAggregator.totalFiles, 2);

        final snap = zeroAggregator.current;
        expect(snap.fraction, isNull);
        expect(snap.transferredBytes, 0);
        expect(snap.totalBytes, 0);

        final p1 = zeroAggregator.updateFileProgress(0, 100);
        expect(p1.fraction, isNull);

        final done = zeroAggregator.completeFile(0);
        expect(done.fraction, isNull);
        expect(done.completedFiles, 1);
      },
    );

    test('empty operation produces zero totals and null fraction', () {
      final aggregator = UploadProgressAggregator([]);
      expect(aggregator.totalFiles, 0);
      expect(aggregator.totalBytes, 0);
      expect(aggregator.current.fraction, isNull);
      expect(aggregator.current.completedFiles, 0);
      expect(aggregator.current.transferredBytes, 0);
    });

    test(
      'last successful completion reaches aggregate fraction 1.0 exactly',
      () {
        final aggregator = UploadProgressAggregator([500, 1500, 3000]);
        expect(aggregator.totalBytes, 5000);

        aggregator.updateFileProgress(0, 500);
        aggregator.completeFile(0);

        aggregator.updateFileProgress(1, 1500);
        aggregator.completeFile(1);

        aggregator.updateFileProgress(2, 2900);
        final almostDone = aggregator.current;
        expect(almostDone.fraction, closeTo(4900 / 5000, 0.001));

        final finalSnap = aggregator.completeFile(2);
        expect(finalSnap.completedFiles, 3);
        expect(finalSnap.transferredBytes, 5000);
        expect(finalSnap.fraction, 1.0);
      },
    );

    test('reset clears state and monotonic latch for a new operation', () {
      final aggregator = UploadProgressAggregator([1000]);
      aggregator.updateFileProgress(0, 800);
      expect(aggregator.current.fraction, closeTo(0.80, 0.001));

      final resetSnap = aggregator.reset([2000]);
      expect(resetSnap.completedFiles, 0);
      expect(resetSnap.totalFiles, 1);
      expect(resetSnap.totalBytes, 2000);
      expect(resetSnap.transferredBytes, 0);
      expect(resetSnap.fraction, 0.0);

      final newProgress = aggregator.updateFileProgress(0, 200);
      // New fraction is 0.10, not locked to the old 0.80
      expect(newProgress.fraction, closeTo(0.10, 0.001));
    });

    test(
      'M2-I2 killer: hasActiveFileProgress lifecycle resets between files without state leakage',
      () {
        final aggregator = UploadProgressAggregator([1000, 2000]);

        // Initially no active progress
        expect(aggregator.current.hasActiveFileProgress, isFalse);

        // File 0 starts
        final start0 = aggregator.startFile(0);
        expect(start0.hasActiveFileProgress, isFalse);

        // File 0 reports 0 bytes
        final zero0 = aggregator.updateFileProgress(0, 0);
        expect(zero0.hasActiveFileProgress, isFalse);

        // File 0 reports > 0 bytes
        final prog0 = aggregator.updateFileProgress(0, 300);
        expect(prog0.hasActiveFileProgress, isTrue);

        // File 0 completes -> active progress resets to false
        final done0 = aggregator.completeFile(0);
        expect(done0.hasActiveFileProgress, isFalse);
        expect(done0.fraction, closeTo(1000 / 3000, 0.001));

        // File 1 starts -> MUST NOT leak hasActiveFileProgress from File 0
        final start1 = aggregator.startFile(1);
        expect(start1.hasActiveFileProgress, isFalse);
        // Preserves completed baseline from File 0 (~0.33)
        expect(start1.fraction, closeTo(1000 / 3000, 0.001));

        // File 1 reports > 0 bytes
        final prog1 = aggregator.updateFileProgress(1, 500);
        expect(prog1.hasActiveFileProgress, isTrue);
        expect(prog1.fraction, closeTo(1500 / 3000, 0.001));

        // File 1 completes -> resets to false, final fraction 1.0
        final done1 = aggregator.completeFile(1);
        expect(done1.hasActiveFileProgress, isFalse);
        expect(done1.fraction, 1.0);
      },
    );

    test(
      'M29 killer: multi-file 49%/51% preserves real 49% baseline when file 2 begins with 0 bytes',
      () {
        // Exact measured sizes from physical H1
        const size1 = 163821;
        const size2 = 168614;
        final aggregator = UploadProgressAggregator([size1, size2]);

        // File 0 completes
        aggregator.updateFileProgress(0, size1);
        final snap1 = aggregator.completeFile(0);
        expect(snap1.fraction, closeTo(size1 / (size1 + size2), 0.0001));
        expect((snap1.fraction! * 100).floor(), 49);

        // File 1 begins with 0 bytes
        final snap2Start = aggregator.startFile(1);
        expect(snap2Start.hasActiveFileProgress, isFalse);
        // Retains 49% baseline, does NOT reset to 0%
        expect(snap2Start.fraction, closeTo(size1 / (size1 + size2), 0.0001));
        expect((snap2Start.fraction! * 100).floor(), 49);
      },
    );
  });
}
