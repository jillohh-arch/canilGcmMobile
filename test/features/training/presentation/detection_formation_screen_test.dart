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
}
