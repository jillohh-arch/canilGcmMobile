import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:canil_gcm/features/dogs/domain/dog.dart';
import 'package:canil_gcm/features/training/data/detection_service.dart';
import 'package:canil_gcm/features/training/presentation/screens/detection_formation_screen.dart';

void main() {
  testWidgets('abre seletor e inicia sessão ao vivo sem erro de layout', (
    tester,
  ) async {
    GoogleFonts.config.allowRuntimeFetching = false;
    await tester.binding.setSurfaceSize(const Size(390, 844));

    final dog = Dog(
      id: 'dog-visual',
      name: 'Bono',
      breed: 'Pastor Belga Malinois',
      dateOfBirth: DateTime(2020, 1, 1),
      conductorRa: '12345',
    );
    final service = DetectionService(firestore: FakeFirebaseFirestore());

    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        home: DetectionFormationScreen(dog: dog, service: service),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    expect(tester.takeException(), isNull);
    expect(find.text('Formação · Detecção'), findsOneWidget);
    expect(find.text('LINHA DE DETECÇÃO'), findsOneWidget);
    expect(find.text('INICIAR SESSÃO'), findsWidgets);

    await tester.ensureVisible(find.text('INICIAR SESSÃO').first);
    await tester.tap(find.text('INICIAR SESSÃO').first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(tester.takeException(), isNull);
    expect(find.text('ACERTOU'), findsOneWidget);
    expect(find.text('ERROU'), findsOneWidget);
  });

  testWidgets('abre fase 4c com layout em quadrado', (tester) async {
    GoogleFonts.config.allowRuntimeFetching = false;
    await tester.binding.setSurfaceSize(const Size(390, 844));

    final dog = Dog(
      id: 'dog-4c',
      name: 'Bono',
      breed: 'Pastor Belga Malinois',
      dateOfBirth: DateTime(2020, 1, 1),
      conductorRa: '12345',
    );
    final firestore = FakeFirebaseFirestore();
    await firestore
        .collection('dogs')
        .doc(dog.id)
        .collection('detection_lines')
        .doc('drogas')
        .set({
          'type': 'drogas',
          'status': 'in_formation',
          'current_phase': '4c',
          'phases_completed': ['1b', '2b', '2v', '3b', '3v', '4b', '4v'],
          'updated_at': Timestamp.fromDate(DateTime(2026, 5, 24, 10)),
        });
    final service = DetectionService(firestore: firestore);

    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        home: DetectionFormationScreen(dog: dog, service: service),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    final startButton = find.widgetWithText(FilledButton, 'INICIAR SESSÃO');
    await tester.ensureVisible(startButton);
    await tester.pumpAndSettle();
    await tester.tap(startButton);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(tester.takeException(), isNull);
    expect(find.text('CONDUTOR'), findsOneWidget);
    expect(find.textContaining('Quadrado'), findsWidgets);
    expect(find.textContaining('etapa horário'), findsWidgets);
  });
}
