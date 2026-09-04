import 'dart:async';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:canil_gcm/core/services/storage_service.dart';

class MockUploadTask extends Mock implements UploadTask {}

class MockTaskSnapshot extends Mock implements TaskSnapshot {}

void main() {
  group('StorageService Progress Bridge — Layer B', () {
    test(
      'A & B: M2 killer — progress events (A,T), (B,T) forward to onProgress in order; runner without forwarding fails',
      () async {
        final streamController = StreamController<(int, int)>();
        final received = <(int, int)>[];
        final completionCompleter = Completer<String>();

        final runnerFuture = runTransferWithProgress<String>(
          completionFactory: () => completionCompleter.future,
          progressEvents: streamController.stream,
          onProgress: (transferred, total) {
            received.add((transferred, total));
          },
        );

        streamController.add((100, 1000));
        streamController.add((500, 1000));
        await Future.delayed(Duration.zero);

        completionCompleter.complete('success');
        final result = await runnerFuture;

        expect(result, 'success');
        expect(received, equals([(100, 1000), (500, 1000)]));
      },
    );

    test(
      'C: M7 killer — when onProgress is null, zero subscription is created on progressEvents',
      () async {
        var listened = false;
        final controller = StreamController<(int, int)>.broadcast(
          onListen: () => listened = true,
        );

        final result = await runTransferWithProgress<int>(
          completionFactory: () => Future.value(42),
          progressEvents: controller.stream,
          onProgress: null,
        );

        expect(result, 42);
        expect(
          listened,
          isFalse,
          reason: 'Must create zero subscription when onProgress is null',
        );
        await controller.close();
      },
    );

    test('D: subscription is cancelled on completion success', () async {
      var isCancelled = false;
      final controller = StreamController<(int, int)>(
        onCancel: () => isCancelled = true,
      );
      final completionCompleter = Completer<String>();

      final runnerFuture = runTransferWithProgress<String>(
        completionFactory: () => completionCompleter.future,
        progressEvents: controller.stream,
        onProgress: (t, total) {},
      );

      await Future.delayed(Duration.zero);
      expect(isCancelled, isFalse);

      completionCompleter.complete('done');
      await runnerFuture;

      expect(isCancelled, isTrue);
    });

    test('E: subscription is cancelled on completion failure', () async {
      var isCancelled = false;
      final controller = StreamController<(int, int)>(
        onCancel: () => isCancelled = true,
      );
      final completionCompleter = Completer<String>();

      final runnerFuture = runTransferWithProgress<String>(
        completionFactory: () => completionCompleter.future,
        progressEvents: controller.stream,
        onProgress: (t, total) {},
      );

      await Future.delayed(Duration.zero);
      expect(isCancelled, isFalse);

      final expectation = expectLater(
        runnerFuture,
        throwsA(
          isA<Exception>().having(
            (e) => e.toString(),
            'message',
            contains('Upload failed'),
          ),
        ),
      );

      completionCompleter.completeError(Exception('Upload failed'));
      await expectation;

      await Future.delayed(Duration.zero);
      expect(isCancelled, isTrue);
      await controller.close();
    });

    test(
      'F: M16 killer — stream observation error does not replace authoritative completion',
      () async {
        final controller = StreamController<(int, int)>();
        final completionCompleter = Completer<String>();

        final runnerFuture = runTransferWithProgress<String>(
          completionFactory: () => completionCompleter.future,
          progressEvents: controller.stream,
          onProgress: (t, total) {},
        );

        // Emit error on observational stream
        controller.addError(Exception('Diagnostic stream error'));
        await Future.delayed(Duration.zero);

        // Upload completes successfully
        completionCompleter.complete('upload-authority-wins');
        final result = await runnerFuture;

        expect(result, 'upload-authority-wins');
      },
    );

    test(
      'G: M10 killer — throwing onProgress callback does not abort authoritative upload',
      () async {
        final controller = StreamController<(int, int)>();
        final completionCompleter = Completer<String>();

        final runnerFuture = runTransferWithProgress<String>(
          completionFactory: () => completionCompleter.future,
          progressEvents: controller.stream,
          onProgress: (t, total) {
            throw FormatException('Malformed presentation state');
          },
        );

        controller.add((10, 100));
        await Future.delayed(Duration.zero);

        // Authoritative upload succeeds
        completionCompleter.complete('authoritative-ok');
        final result = await runnerFuture;

        expect(result, 'authoritative-ok');
      },
    );

    test(
      'H: adapter maps mocked TaskSnapshot bytesTransferred/totalBytes correctly',
      () async {
        final mockTask = MockUploadTask();
        final snap1 = MockTaskSnapshot();
        final snap2 = MockTaskSnapshot();
        when(() => snap1.bytesTransferred).thenReturn(100);
        when(() => snap1.totalBytes).thenReturn(1000);
        when(() => snap2.bytesTransferred).thenReturn(500);
        when(() => snap2.totalBytes).thenReturn(1000);

        when(
          () => mockTask.snapshotEvents,
        ).thenAnswer((_) => Stream.fromIterable([snap1, snap2]));

        final events = await uploadProgressEvents(mockTask).toList();

        expect(events, equals([(100, 1000), (500, 1000)]));
      },
    );

    test(
      'I: M18-I2 killer — progressEvents subscription attaches BEFORE completionFactory is invoked',
      () async {
        var streamSubscribed = false;
        var streamSubscribedBeforeFactory = false;

        final controller = StreamController<(int, int)>(
          onListen: () {
            streamSubscribed = true;
          },
        );
        final completionCompleter = Completer<String>();

        final runnerFuture = runTransferWithProgress<String>(
          completionFactory: () {
            // Verify that onListen has already fired before completionFactory executes
            streamSubscribedBeforeFactory = streamSubscribed;
            return completionCompleter.future;
          },
          progressEvents: controller.stream,
          onProgress: (t, total) {},
        );

        await Future.delayed(Duration.zero);
        completionCompleter.complete('done');
        await runnerFuture;

        expect(
          streamSubscribedBeforeFactory,
          isTrue,
          reason:
              'progressEvents listener must attach BEFORE completionFactory() is called',
        );
        await controller.close();
      },
    );
  });
}
