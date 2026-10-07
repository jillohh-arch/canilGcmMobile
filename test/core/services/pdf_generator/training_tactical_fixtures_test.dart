import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';

import 'package:canil_gcm/core/services/pdf_generator/training_tactical_pdf.dart';
import 'package:canil_gcm/features/dogs/domain/dog.dart';
import 'package:canil_gcm/features/training/domain/training_session_model.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final thor = Dog(
    id: 'k9-thor-01',
    name: 'Thor',
    breed: 'Pastor Belga Malinois',
    dateOfBirth: DateTime(2021, 3, 14),
    microchip: '900215004712345',
    registrationNumber: 'K9-2023-017',
    cor: 'Fulvo com máscara preta',
    weight: 33.5,
    conductorRa: 'Silva (GCM)',
    specialties: ['Faro de Entorpecentes', 'Proteção e Guarda', 'Detecção'],
    idealWeightMin: 32.0,
    idealWeightMax: 35.0,
    status: 'Ativo',
  );

  final outputDir = Directory('build/visual_fixtures/training_tactical');
  Uint8List? sampleDogPhoto;
  Uint8List? sampleLogo;

  setUpAll(() async {
    if (!await outputDir.exists()) {
      await outputDir.create(recursive: true);
    }
    final photoFile = File('assets/images/k9_ops_loading_dog_static_v1.png');
    if (photoFile.existsSync()) {
      sampleDogPhoto = photoFile.readAsBytesSync();
    }
    final logoFile = File('assets/images/logo-app.png');
    if (logoFile.existsSync()) {
      sampleLogo = logoFile.readAsBytesSync();
    }
  });

  TrainingSessionModel makeSession({
    required String id,
    required DateTime date,
    required String trainingType,
    String location = 'Centro de Treinamento K9',
    String? substanceUsed,
    int? searchDuration,
    String weather = 'Ensolarado',
    String handlerNotes = 'Instrução prática concluída com conformidade técnica.',
  }) {
    return TrainingSessionModel(
      id: id,
      dogId: thor.id,
      dogName: thor.name,
      handlerId: 'GCM 1CL Silva',
      date: date,
      trainingType: trainingType,
      location: location,
      substanceUsed: substanceUsed,
      searchDuration: searchDuration,
      weather: weather,
      handlerNotes: handlerNotes,
    );
  }

  group('MOB-DOC-05 — Visual Fixtures Generation (Relatório Tático de Treinos)', () {
    test('1. Gera PDF representativo de Treino Normal', () async {
      final sessions = [
        makeSession(
          id: 'trn-01',
          date: DateTime(2026, 10, 5, 14, 30),
          trainingType: 'Faro de Entorpecentes',
          location: 'Pátio de Cargas - Área Confinada',
          substanceUsed: 'Cocaína (simulador)',
          searchDuration: 210, // 3m 30s
          handlerNotes: 'Indicação passiva precisa com foco sustentado e persistência olfativa.',
        ),
        makeSession(
          id: 'trn-02',
          date: DateTime(2026, 10, 3, 9, 0),
          trainingType: 'Proteção e Guarda',
          location: 'Campo Tático de Instrução',
          searchDuration: 600, // 10 min
          handlerNotes: 'Ataque frontal com mordida cheia e largada imediata sob comando verbal.',
        ),
        makeSession(
          id: 'trn-03',
          date: DateTime(2026, 9, 29, 8, 30),
          trainingType: 'Obediência Básica',
          location: 'Pista de Agility K9',
          searchDuration: 300, // 5 min
          handlerNotes: 'Evolução na marcha, posições ' 'junto' ' e atenção focada ao condutor.',
        ),
        makeSession(
          id: 'trn-04',
          date: DateTime(2026, 9, 24, 15, 0),
          trainingType: 'Detecção de Armas e Munições',
          location: 'Edificação Escolar Desocupada',
          substanceUsed: 'Pólvora e simulador balístico',
          searchDuration: 360, // 6 min
          handlerNotes: 'Localização em compartimento oculto sem contaminação do ambiente.',
        ),
      ];

      final bytes = await TrainingTacticalPdf.generate(
        dog: thor,
        sessions: sessions,
        conductorCallsign: 'GCM 1CL Silva',
        period: '24/09/2026 a 05/10/2026',
        dogPhotoBytes: sampleDogPhoto,
        k9LogoBytes: sampleLogo,
      );

      final file = File('${outputDir.path}/relatorio_treinos_normal.pdf');
      await file.writeAsBytes(bytes);

      expect(file.existsSync(), isTrue);
      expect(bytes.length, greaterThan(2500));
      expect(bytes.take(4), orderedEquals('%PDF'.codeUnits));
    });

    test('2. Gera PDF representativo de Treino Sem Registros (Estado Vazio)', () async {
      final bytes = await TrainingTacticalPdf.generate(
        dog: thor,
        sessions: [],
        conductorCallsign: 'GCM 1CL Silva',
        period: '01/10/2026 a 05/10/2026',
        dogPhotoBytes: sampleDogPhoto,
        k9LogoBytes: sampleLogo,
      );

      final file = File('${outputDir.path}/relatorio_treinos_sem_registros.pdf');
      await file.writeAsBytes(bytes);

      expect(file.existsSync(), isTrue);
      expect(bytes.length, greaterThan(2000));
      expect(bytes.take(4), orderedEquals('%PDF'.codeUnits));
    });

    test('3. Gera PDF representativo de Treino Multipage (Estresse)', () async {
      final manySessions = List.generate(
        42,
        (i) => makeSession(
          id: 'multi-$i',
          date: DateTime(2026, 10, 5, 12, 0).subtract(Duration(hours: i * 16)),
          trainingType: i % 3 == 0
              ? 'Faro de Entorpecentes'
              : (i % 3 == 1 ? 'Proteção e Guarda' : 'Obediência Tática'),
          location: 'Setor de Instrução ${i % 4 + 1}',
          substanceUsed: i % 3 == 0 ? 'Odor Alvo Série $i' : null,
          searchDuration: 180 + (i * 15),
          handlerNotes: 'Registro instrucional da sessão de treinamento #$i.',
        ),
      );

      final bytes = await TrainingTacticalPdf.generate(
        dog: thor,
        sessions: manySessions,
        conductorCallsign: 'GCM 1CL Silva',
        period: '01/08/2026 a 05/10/2026',
        dogPhotoBytes: sampleDogPhoto,
        k9LogoBytes: sampleLogo,
      );

      final file = File('${outputDir.path}/relatorio_treinos_multipage.pdf');
      await file.writeAsBytes(bytes);

      expect(file.existsSync(), isTrue);
      expect(bytes.length, greaterThan(4000));
      expect(bytes.take(4), orderedEquals('%PDF'.codeUnits));
    });

    test('4. Gera PDF representativo de Treino Sem Foto do Cão', () async {
      final sessions = [
        makeSession(
          id: 'sf-1',
          date: DateTime(2026, 10, 4, 10, 0),
          trainingType: 'Faro de Odor Específico',
          location: 'Área Florestal',
          substanceUsed: 'Simulador A-1',
          searchDuration: 420,
        ),
        makeSession(
          id: 'sf-2',
          date: DateTime(2026, 10, 2, 8, 30),
          trainingType: 'Condicionamento Físico',
          location: 'Pista de Obstáculos',
          searchDuration: 600,
        ),
      ];

      final bytes = await TrainingTacticalPdf.generate(
        dog: thor,
        sessions: sessions,
        conductorCallsign: 'GCM 1CL Silva',
        period: '01/10/2026 a 04/10/2026',
        dogPhotoBytes: null, // Sem foto do cão
        k9LogoBytes: sampleLogo,
      );

      final file = File('${outputDir.path}/relatorio_treinos_sem_foto.pdf');
      await file.writeAsBytes(bytes);

      expect(file.existsSync(), isTrue);
      expect(bytes.length, greaterThan(2500));
      expect(bytes.take(4), orderedEquals('%PDF'.codeUnits));
    });
  });
}
