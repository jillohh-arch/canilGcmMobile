// FF-OCC-04 — REGRESSION KILLERS: PDF loading UX and concurrency hardening.
//
// Killers verified:
// - LUX-1: Loading spinner remains visible while PDF generation Future is pending.
// - LUX-2: Loading does not disappear in the interval between generation and preview handoff.
// - LUX-3: Error ends loading and presents failure once.
// - LUX-4: Double-tap on action buttons does not trigger concurrent generations.
// - LUX-5: Completion after dispose does not throw setState/navigation/context exception.

import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:canil_gcm/features/occurrences/domain/occurrence_result.dart';
import 'package:canil_gcm/features/occurrences/presentation/screens/occurrence_confirmation_screen.dart';

OccurrenceConfirmationData _sampleData() => const OccurrenceConfirmationData(
  occurrenceId: 'occ-lux-12345678',
  typeName: 'Apoio Policial',
  durationLabel: '1h 30m',
  locationAddress: 'Rua das Flores, 123',
  dogName: 'Thor',
  handlerName: 'GCM Ragonha',
  eventCount: 4,
  results: [OccurrenceResult.drugSeized],
  details: {
    'drug_seized': [
      {'type': 'Maconha', 'weight_grams': '125'},
      {'type': 'Cocaína', 'weight_grams': '18'},
    ],
  },
  integrityHash: 'a1b2c3d4e5f67890abcdef1234567890',
);

void main() {
  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized();
  });

  group('FF-OCC-04 — PDF Loading UX & Concurrency Guards', () {
    testWidgets(
      'LUX-1: loading indicator remains active while generation Future is pending',
      (tester) async {
        tester.view.physicalSize = const Size(1080, 2400);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        final completer = Completer<Uint8List>();

        await tester.pumpWidget(
          MaterialApp(
            home: OccurrenceConfirmationScreen(
              data: _sampleData(),
              pdfBytesBuilder: (_, {required auditAction}) => completer.future,
              pdfPreviewLauncher: ({required bytes, required name}) async {},
            ),
          ),
        );

        // Pre-tap: button displays idle label
        expect(find.text('Gerar PDF'), findsOneWidget);
        expect(find.text('Gerando...'), findsNothing);
        expect(find.byType(CircularProgressIndicator), findsNothing);

        // Tap 'Gerar PDF'
        await tester.ensureVisible(find.text('Gerar PDF'));
        await tester.tap(find.text('Gerar PDF'));
        await tester.pump();

        // LUX-1 property: continuous loading is active while Future is uncompleted
        expect(find.text('Gerando...'), findsOneWidget);
        expect(find.byType(CircularProgressIndicator), findsOneWidget);

        // Advance simulated time by 5 seconds (well past legacy 2s timeout)
        await tester.pump(const Duration(seconds: 5));
        expect(find.text('Gerando...'), findsOneWidget);
        expect(find.byType(CircularProgressIndicator), findsOneWidget);

        // Complete generation
        completer.complete(Uint8List.fromList([1, 2, 3]));
        await tester.pump();

        // After completion, loading state resolves
        expect(find.text('Gerar PDF'), findsOneWidget);
        expect(find.text('Gerando...'), findsNothing);
        expect(find.byType(CircularProgressIndicator), findsNothing);
      },
    );

    testWidgets(
      'LUX-2: loading does not disappear in interval between generation and preview handoff',
      (tester) async {
        tester.view.physicalSize = const Size(1080, 2400);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        final genCompleter = Completer<Uint8List>();
        final previewCompleter = Completer<void>();
        var previewInitiated = false;

        await tester.pumpWidget(
          MaterialApp(
            home: OccurrenceConfirmationScreen(
              data: _sampleData(),
              pdfBytesBuilder: (_, {required auditAction}) =>
                  genCompleter.future,
              pdfPreviewLauncher: ({required bytes, required name}) {
                previewInitiated = true;
                return previewCompleter.future;
              },
            ),
          ),
        );

        await tester.ensureVisible(find.text('Gerar PDF'));
        await tester.tap(find.text('Gerar PDF'));
        await tester.pump();
        expect(find.text('Gerando...'), findsOneWidget);

        // Complete bytes generation
        genCompleter.complete(Uint8List.fromList([1, 2, 3]));
        await tester.pump();

        // Bytes are ready, preview launcher is running: loading MUST NOT disappear
        expect(previewInitiated, isTrue);
        expect(find.text('Gerando...'), findsOneWidget);
        expect(find.byType(CircularProgressIndicator), findsOneWidget);

        // Complete preview handoff
        previewCompleter.complete();
        await tester.pump();

        expect(find.text('Gerar PDF'), findsOneWidget);
        expect(find.text('Gerando...'), findsNothing);
      },
    );

    testWidgets('LUX-3: error ends loading and presents failure once', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final completer = Completer<Uint8List>();

      await tester.pumpWidget(
        MaterialApp(
          home: OccurrenceConfirmationScreen(
            data: _sampleData(),
            pdfBytesBuilder: (_, {required auditAction}) => completer.future,
            pdfPreviewLauncher: ({required bytes, required name}) async {},
          ),
        ),
      );

      await tester.ensureVisible(find.text('Gerar PDF'));
      await tester.tap(find.text('Gerar PDF'));
      await tester.pump();
      expect(find.text('Gerando...'), findsOneWidget);

      // Complete with error
      completer.completeError(Exception('Falha no renderizador PDF'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // Loading state must be cleanly cleared
      expect(find.text('Gerar PDF'), findsOneWidget);
      expect(find.text('Gerando...'), findsNothing);
      expect(find.byType(CircularProgressIndicator), findsNothing);

      // Failure feedback presented
      expect(find.textContaining('Falha no renderizador PDF'), findsOneWidget);
    });

    testWidgets(
      'LUX-4: double-tap does not initiate two concurrent generations',
      (tester) async {
        tester.view.physicalSize = const Size(1080, 2400);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        var generationCount = 0;
        final completer = Completer<Uint8List>();

        await tester.pumpWidget(
          MaterialApp(
            home: OccurrenceConfirmationScreen(
              data: _sampleData(),
              pdfBytesBuilder: (_, {required auditAction}) {
                generationCount++;
                return completer.future;
              },
            ),
          ),
        );

        await tester.ensureVisible(find.text('Gerar PDF'));

        // Rapid double tap
        await tester.tap(find.text('Gerar PDF'));
        await tester.pump();
        expect(generationCount, equals(1));

        // Second tap while busy
        await tester.tap(find.text('Gerando...'));
        await tester.pump();

        expect(generationCount, equals(1));

        // Also tap Share button while generating
        await tester.tap(find.text('Compartilhar'));
        await tester.pump();

        expect(generationCount, equals(1));

        completer.complete(Uint8List.fromList([1, 2, 3]));
        await tester.pump();
      },
    );

    testWidgets(
      'LUX-5: completion after dispose does not throw setState error',
      (tester) async {
        tester.view.physicalSize = const Size(1080, 2400);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        final completer = Completer<Uint8List>();

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: OccurrenceConfirmationScreen(
                data: _sampleData(),
                pdfBytesBuilder: (_, {required auditAction}) =>
                    completer.future,
                pdfPreviewLauncher: ({required bytes, required name}) async {},
              ),
            ),
          ),
        );

        await tester.ensureVisible(find.text('Gerar PDF'));
        await tester.tap(find.text('Gerar PDF'));
        await tester.pump();
        expect(find.text('Gerando...'), findsOneWidget);

        // Unmount the screen completely (replace home with Container)
        await tester.pumpWidget(
          const MaterialApp(home: Scaffold(body: Text('Tela Diferente'))),
        );
        expect(find.text('Tela Diferente'), findsOneWidget);

        // Now complete the pending generation future after unmount
        completer.complete(Uint8List.fromList([1, 2, 3]));
        await tester.pump();

        // No unhandled exception should be thrown
        expect(tester.takeException(), isNull);
      },
    );
  });
}
