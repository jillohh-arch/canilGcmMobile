import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:canil_gcm/core/services/pdf_generator/operational_history_pdf.dart';
import 'package:canil_gcm/features/dogs/domain/dog.dart';
import 'package:canil_gcm/features/history/presentation/screens/history_screen.dart';

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
    specialties: ['Patrulhamento', 'Busca e Resgate', 'Detecção', 'Apoio Operacional'],
    idealWeightMin: 32.0,
    idealWeightMax: 35.0,
    status: 'Ativo',
  );

  final outputDir = Directory('build/visual_fixtures/operational_history');
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

  HistoryEntry makeEntry({
    required String id,
    required HistoryEntryType type,
    required String title,
    required String subtitle,
    required DateTime time,
    String author = 'GCM 1CL Silva',
    String location = 'Limeira - SP',
  }) {
    return HistoryEntry(
      id: id,
      type: type,
      title: title,
      subtitle: subtitle,
      time: time,
      author: author,
      location: location,
      tag: 'OP',
      icon: Icons.shield,
      color: Colors.blue,
    );
  }

  group('MOB-DOC-06 — Visual Fixtures Generation (Histórico Operacional)', () {
    test('1. Gera PDF representativo de Histórico Operacional Normal', () async {
      final entries = [
        makeEntry(
          id: 'op-01',
          type: HistoryEntryType.occurrence,
          title: 'Apoio Tático em Operação Policial',
          subtitle: 'Varredura perimetral com indicação positiva de substância entorpecente',
          time: DateTime(2026, 10, 5, 15, 30),
          location: 'Bairro Boa Vista',
        ),
        makeEntry(
          id: 'op-02',
          type: HistoryEntryType.training,
          title: 'Treinamento de Faro e Detecção',
          subtitle: 'Aprimoramento de discriminação de odor em veículo de transporte',
          time: DateTime(2026, 10, 4, 9, 0),
          location: 'Pátio Operacional GCM',
        ),
        makeEntry(
          id: 'op-03',
          type: HistoryEntryType.health,
          title: 'Avaliação Veterinária de Rotina',
          subtitle: 'Exame físico completo e atestado de aptidão operacional sem restrições',
          time: DateTime(2026, 10, 2, 11, 0),
          author: 'MV. Ana Costa',
          location: 'Clínica Veterinária',
        ),
        makeEntry(
          id: 'op-04',
          type: HistoryEntryType.nutrition,
          title: 'Manejo Alimentar Pós-Turno',
          subtitle: 'Porção de 450g servida com conformidade nutricional atestada',
          time: DateTime(2026, 10, 1, 19, 0),
          location: 'Box K9 - Canil Central',
        ),
      ];

      final bytes = await OperationalHistoryPdf.generate(
        entries: entries,
        dog: thor,
        handlerName: 'GCM 1CL Silva',
        periodLabel: '01/10/2026 a 05/10/2026',
        dogPhotoBytes: sampleDogPhoto,
        k9LogoBytes: sampleLogo,
      );

      final file = File('${outputDir.path}/historico_operacional_normal.pdf');
      await file.writeAsBytes(bytes);

      expect(file.existsSync(), isTrue);
      expect(bytes.length, greaterThan(2500));
      expect(bytes.take(4), orderedEquals('%PDF'.codeUnits));
    });

    test('2. Gera PDF representativo de Histórico Sem Registros', () async {
      final bytes = await OperationalHistoryPdf.generate(
        entries: [],
        dog: thor,
        handlerName: 'GCM 1CL Silva',
        periodLabel: '01/10/2026 a 05/10/2026',
        dogPhotoBytes: sampleDogPhoto,
        k9LogoBytes: sampleLogo,
      );

      final file = File('${outputDir.path}/historico_operacional_sem_registros.pdf');
      await file.writeAsBytes(bytes);

      expect(file.existsSync(), isTrue);
      expect(bytes.length, greaterThan(2000));
      expect(bytes.take(4), orderedEquals('%PDF'.codeUnits));
    });

    test('3. Gera PDF representativo de Histórico Multipage (Estresse)', () async {
      final manyEntries = List.generate(
        45,
        (i) => makeEntry(
          id: 'multi-$i',
          type: i % 4 == 0
              ? HistoryEntryType.occurrence
              : (i % 4 == 1
                  ? HistoryEntryType.training
                  : (i % 4 == 2 ? HistoryEntryType.health : HistoryEntryType.nutrition)),
          title: 'Registro de Atividade Tática #$i',
          subtitle: 'Atuação registrada na escala de serviço com protocolo formal $i',
          time: DateTime(2026, 10, 5, 12, 0).subtract(Duration(hours: i * 8)),
          location: 'Setor Policial ${i % 5 + 1}',
        ),
      );

      final bytes = await OperationalHistoryPdf.generate(
        entries: manyEntries,
        dog: thor,
        handlerName: 'GCM 1CL Silva',
        periodLabel: '01/09/2026 a 05/10/2026',
        dogPhotoBytes: sampleDogPhoto,
        k9LogoBytes: sampleLogo,
      );

      final file = File('${outputDir.path}/historico_operacional_multipage.pdf');
      await file.writeAsBytes(bytes);

      expect(file.existsSync(), isTrue);
      expect(bytes.length, greaterThan(4000));
      expect(bytes.take(4), orderedEquals('%PDF'.codeUnits));
    });

    test('4. Gera PDF representativo de Histórico Sem Foto', () async {
      final entries = [
        makeEntry(
          id: 'sf-1',
          type: HistoryEntryType.occurrence,
          title: 'Patrulhamento em Evento Público',
          subtitle: 'Presença ostensiva em praça central',
          time: DateTime(2026, 10, 3, 20, 0),
          location: 'Praça Toledo Barros',
        ),
        makeEntry(
          id: 'sf-2',
          type: HistoryEntryType.training,
          title: 'Condicionamento Físico',
          subtitle: 'Treino de agilidade e pistas de obstáculos',
          time: DateTime(2026, 10, 2, 8, 30),
          location: 'Pista de Agility K9',
        ),
      ];

      final bytes = await OperationalHistoryPdf.generate(
        entries: entries,
        dog: thor,
        handlerName: 'GCM 1CL Silva',
        periodLabel: '01/10/2026 a 03/10/2026',
        dogPhotoBytes: null, // Sem foto do cão
        k9LogoBytes: sampleLogo,
      );

      final file = File('${outputDir.path}/historico_operacional_sem_foto.pdf');
      await file.writeAsBytes(bytes);

      expect(file.existsSync(), isTrue);
      expect(bytes.length, greaterThan(2500));
      expect(bytes.take(4), orderedEquals('%PDF'.codeUnits));
    });
  });
}
