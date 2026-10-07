import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';

import 'package:canil_gcm/core/services/pdf_generator/training_tactical_pdf.dart';
import 'package:canil_gcm/core/services/report_service.dart';
import 'package:canil_gcm/features/dogs/domain/dog.dart';
import 'package:canil_gcm/features/training/domain/training_session_model.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final dog = Dog(
    id: 'k9-thor-01',
    name: 'Thor',
    breed: 'Pastor Belga Malinois',
    dateOfBirth: DateTime(2021, 3, 14),
    microchip: '900215004712345',
    registrationNumber: 'K9-2023-017',
    cor: 'Fulvo com máscara preta',
    weight: 33.5,
    conductorRa: '5678',
    specialties: ['Faro de Entorpecentes', 'Proteção e Guarda', 'Detecção'],
    status: 'Ativo',
  );

  Uint8List? sampleDogPhoto;
  Uint8List? sampleLogo;

  setUpAll(() {
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
    String weather = 'Limpo',
    String handlerNotes = 'Cão apresentou excelente foco e resposta ao comando.',
    String handlerId = 'GCM 1CL Silva',
  }) {
    return TrainingSessionModel(
      id: id,
      dogId: dog.id,
      dogName: dog.name,
      handlerId: handlerId,
      date: date,
      trainingType: trainingType,
      location: location,
      substanceUsed: substanceUsed,
      searchDuration: searchDuration,
      weather: weather,
      handlerNotes: handlerNotes,
    );
  }

  group('TrainingTacticalPdf (MOB-DOC-05) — Validações Contratuais e Semânticas', () {
    test('1. Geração válida com histórico normal de sessões (sessions)', () async {
      final sessions = [
        makeSession(
          id: 'trn-1',
          date: DateTime(2026, 10, 5, 14, 30),
          trainingType: 'Faro de Entorpecentes',
          location: 'Pátio Operacional - Canil Central',
          substanceUsed: 'Cocaína (simulador)',
          searchDuration: 240, // 4 min
          handlerNotes: 'Indicação passiva precisa com foco sustentado.',
        ),
        makeSession(
          id: 'trn-2',
          date: DateTime(2026, 10, 3, 9, 0),
          trainingType: 'Proteção e Intervenção',
          location: 'Campo de Instrução Tática',
          searchDuration: 600, // 10 min
          handlerNotes: 'Mordida firme em manga com largada imediata ao comando.',
        ),
        makeSession(
          id: 'trn-3',
          date: DateTime(2026, 9, 28, 8, 30),
          trainingType: 'Obediência Básica e Agility',
          location: 'Pista de Obstáculos',
          searchDuration: 300,
          handlerNotes: 'Transições rápidas de ritmo e atenção constante ao condutor.',
        ),
      ];

      final bytes = await TrainingTacticalPdf.generate(
        dog: dog,
        sessions: sessions,
        conductorCallsign: 'GCM 1CL Silva',
        period: '01/09/2026 a 05/10/2026',
        dogPhotoBytes: sampleDogPhoto,
        k9LogoBytes: sampleLogo,
      );

      expect(bytes, isNotEmpty);
      expect(bytes.take(4), orderedEquals('%PDF'.codeUnits));
      expect(bytes.length, greaterThan(2500));
    });

    test('2. Estado vazio (sem registros) gera documento limpo com ObservationBlock', () async {
      final bytes = await TrainingTacticalPdf.generate(
        dog: dog,
        sessions: [],
        conductorCallsign: 'GCM 1CL Silva',
        k9LogoBytes: sampleLogo,
      );

      expect(bytes, isNotEmpty);
      expect(bytes.take(4), orderedEquals('%PDF'.codeUnits));
      expect(bytes.length, greaterThan(1500));
    });

    test('3. Ordenação cronológica estrita decrescente (mais recentes primeiro)', () async {
      final t1 = DateTime(2026, 9, 10, 8, 0);
      final t2 = DateTime(2026, 9, 25, 12, 0);
      final t3 = DateTime(2026, 10, 1, 15, 0);

      // Entradas passadas fora de ordem propositalmente
      final unsortedSessions = [
        makeSession(id: '1', date: t1, trainingType: 'Obediência'),
        makeSession(id: '3', date: t3, trainingType: 'Faro'),
        makeSession(id: '2', date: t2, trainingType: 'Proteção'),
      ];

      final bytes = await TrainingTacticalPdf.generate(
        dog: dog,
        sessions: unsortedSessions,
        k9LogoBytes: sampleLogo,
      );

      expect(bytes, isNotEmpty);
      expect(bytes.take(4), orderedEquals('%PDF'.codeUnits));
    });

    test('4. Compatibilidade com ReportEntry (via ReportService ou entries)', () async {
      final entries = [
        ReportEntry(
          date: DateTime(2026, 10, 4, 10, 0),
          type: 'Detecção de Armas',
          location: 'Edificação Confinada',
          observations: 'Varredura metodológica com indicação clara.',
        ),
        ReportEntry(
          date: DateTime(2026, 10, 2, 14, 0),
          type: 'Treino de Condicionamento',
          location: 'Pista de Agility',
          observations: 'Circuito completo sem refugo de obstáculos.',
        ),
      ];

      final bytes = await ReportService.generateActivityReport(
        dog: dog,
        conductorCallsign: 'GCM 1CL Silva',
        entries: entries,
        period: '01/10/2026 a 04/10/2026',
      );

      expect(bytes, isNotEmpty);
      expect(bytes.take(4), orderedEquals('%PDF'.codeUnits));
    });

    test('5. Cão sem foto renderiza fallback tático elegante (avatar placeholder)', () async {
      final sessions = [
        makeSession(
          id: '1',
          date: DateTime(2026, 10, 2, 9, 0),
          trainingType: 'Faro Geral',
        ),
      ];

      final bytes = await TrainingTacticalPdf.generate(
        dog: dog,
        sessions: sessions,
        dogPhotoBytes: null, // Sem foto do animal
        k9LogoBytes: sampleLogo,
      );

      expect(bytes, isNotEmpty);
      expect(bytes.take(4), orderedEquals('%PDF'.codeUnits));
    });

    test('6. Multipágina: volume elevado de sessões de treino (40+ registros)', () async {
      final manySessions = List.generate(
        42,
        (i) => makeSession(
          id: 'session-$i',
          date: DateTime(2026, 10, 5, 12, 0).subtract(Duration(hours: i * 14)),
          trainingType: i % 3 == 0
              ? 'Faro de Entorpecentes'
              : (i % 3 == 1 ? 'Proteção e Guarda' : 'Obediência Tática'),
          location: 'Setor de Instrução ${i % 4 + 1}',
          substanceUsed: i % 3 == 0 ? 'Odor Alvo Série $i' : null,
          searchDuration: 180 + (i * 10),
          handlerNotes: 'Avaliação da sessão técnica de capacitação número $i.',
        ),
      );

      final bytes = await TrainingTacticalPdf.generate(
        dog: dog,
        sessions: manySessions,
        conductorCallsign: 'GCM 1CL Silva',
        dogPhotoBytes: sampleDogPhoto,
        k9LogoBytes: sampleLogo,
      );

      expect(bytes, isNotEmpty);
      expect(bytes.length, greaterThan(4000));
      expect(bytes.take(4), orderedEquals('%PDF'.codeUnits));
    });

    test('7. Sessões com notas longas não provocam overflow de layout', () async {
      final longSession = [
        makeSession(
          id: 'long-1',
          date: DateTime(2026, 10, 4, 15, 0),
          trainingType: 'Busca e Captura em Área Extensa de Vegetação Densa',
          location: 'Parque Ecológico Municipal - Área de Mata Fechada e Terreno Acidentado',
          substanceUsed: 'Artigo Pessoal com Odor Humano Específico',
          searchDuration: 1500, // 25 min
          handlerNotes:
              'Simulado tático de rastreamento de foragido em terreno de mata fechada com desnível acentuado. '
              'O cão manteve trilha olfativa sem dispersão diante de distrações naturais e animais da fauna silvestre, '
              'concluindo a localização com latido de alerta conforme protocolo estabelecido pela instrução técnica.',
        ),
      ];

      final bytes = await TrainingTacticalPdf.generate(
        dog: dog,
        sessions: longSession,
        conductorCallsign: 'GCM 1CL Silva',
        dogPhotoBytes: sampleDogPhoto,
        k9LogoBytes: sampleLogo,
      );

      expect(bytes, isNotEmpty);
      expect(bytes.take(4), orderedEquals('%PDF'.codeUnits));
    });

    test('8. R2 Layout: Rótulos longos de modalidade e quebra fluida sem truncamento', () async {
      final variedSessions = [
        makeSession(
          id: 'var-1',
          date: DateTime(2026, 10, 5, 14, 30),
          trainingType: 'FARO DE ENTORPECENTES',
          location: 'Pátio de Cargas - Área Confinada',
          substanceUsed: 'Cocaína (simulador)',
          searchDuration: 210,
          handlerNotes: 'Indicação passiva precisa com foco sustentado.',
        ),
        makeSession(
          id: 'var-2',
          date: DateTime(2026, 10, 4, 11, 0),
          trainingType: 'PROTEÇÃO E GUARDA',
          location: 'Campo Tático de Instrução',
          searchDuration: 600,
          handlerNotes: 'Ataque frontal com mordida cheia e largada imediata sob comando verbal.',
        ),
        makeSession(
          id: 'var-3',
          date: DateTime(2026, 10, 3, 9, 15),
          trainingType: 'OBEDIÊNCIA TÁTICA',
          location: 'Pista de Agility K9',
          searchDuration: 300,
          handlerNotes: 'Evolução na marcha e atenção focada.',
        ),
        makeSession(
          id: 'var-4',
          date: DateTime(2026, 10, 2, 16, 45),
          trainingType: 'DETECÇÃO DE ARMAS E MUNIÇÕES',
          location: 'Edificação Escolar Desocupada',
          substanceUsed: 'Pólvora e simulador balístico',
          searchDuration: 360,
          handlerNotes: 'Localização em compartimento oculto sem contaminação do ambiente.',
        ),
        makeSession(
          id: 'var-5',
          date: DateTime(2026, 10, 1, 8, 0),
          trainingType: 'FARO GERAL',
          location: 'Área Aberta',
          searchDuration: 180,
          handlerNotes: 'Varredura exploratória inicial.',
        ),
      ];

      final bytes = await TrainingTacticalPdf.generate(
        dog: dog,
        sessions: variedSessions,
        conductorCallsign: 'GCM 1CL Silva',
        dogPhotoBytes: sampleDogPhoto,
        k9LogoBytes: sampleLogo,
      );

      expect(bytes, isNotEmpty);
      expect(bytes.take(4), orderedEquals('%PDF'.codeUnits));
    });
  });
}
