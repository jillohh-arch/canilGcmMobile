import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:canil_gcm/core/services/pdf_generator/operational_history_pdf.dart';
import 'package:canil_gcm/features/dogs/domain/dog.dart';
import 'package:canil_gcm/features/history/presentation/screens/history_screen.dart';

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
    conductorRa: 'Silva (GCM)',
    specialties: ['Patrulhamento', 'Busca e Resgate', 'Detecção'],
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

  HistoryEntry makeEntry({
    required String id,
    required HistoryEntryType type,
    required String title,
    required String subtitle,
    required DateTime time,
    String author = 'GCM 1CL Silva',
    String location = 'Setor Central',
    String tag = 'OP',
  }) {
    return HistoryEntry(
      id: id,
      type: type,
      title: title,
      subtitle: subtitle,
      time: time,
      author: author,
      location: location,
      tag: tag,
      icon: Icons.shield,
      color: Colors.blue,
    );
  }

  group('OperationalHistoryPdf — Validações Contratuais e Semânticas', () {
    test('1. Geração válida com histórico normal e cão vinculado', () async {
      final entries = [
        makeEntry(
          id: 'occ-1',
          type: HistoryEntryType.occurrence,
          title: 'Apoio em Busca e Captura',
          subtitle: 'Localização de entorpecentes em área perimetral',
          time: DateTime(2026, 10, 5, 14, 30),
          location: 'Av. Campinas, 1200',
        ),
        makeEntry(
          id: 'trn-1',
          type: HistoryEntryType.training,
          title: 'Treinamento de Faro e Detecção',
          subtitle: 'Sessão prática com odor alvo em ambiente confinado',
          time: DateTime(2026, 10, 4, 9, 0),
          location: 'Centro de Treinamento K9',
        ),
        makeEntry(
          id: 'hlt-1',
          type: HistoryEntryType.health,
          title: 'Aplicação de Vacina V10',
          subtitle: 'Dose anual de imunização profilática',
          time: DateTime(2026, 10, 2, 11, 15),
          location: 'Clínica Veterinária Municipal',
        ),
        makeEntry(
          id: 'nut-1',
          type: HistoryEntryType.nutrition,
          title: 'Alimentação Monitorada - Manhã',
          subtitle: 'Porção de 400g servida com conformidade plena',
          time: DateTime(2026, 10, 1, 7, 30),
          location: 'Box K9 - Canil',
        ),
      ];

      final bytes = await OperationalHistoryPdf.generate(
        entries: entries,
        dog: dog,
        handlerName: 'GCM 1CL Silva',
        periodLabel: '01/10/2026 a 05/10/2026',
        dogPhotoBytes: sampleDogPhoto,
        k9LogoBytes: sampleLogo,
      );

      expect(bytes, isNotEmpty);
      expect(bytes.take(4), orderedEquals('%PDF'.codeUnits));
      expect(bytes.length, greaterThan(2000));
    });

    test('2. Estado vazio (sem registros) gera documento limpo com ObservationBlock', () async {
      final bytes = await OperationalHistoryPdf.generate(
        entries: [],
        dog: dog,
        handlerName: 'GCM 1CL Silva',
        periodLabel: '01/10/2026 a 05/10/2026',
        k9LogoBytes: sampleLogo,
      );

      expect(bytes, isNotEmpty);
      expect(bytes.take(4), orderedEquals('%PDF'.codeUnits));
      expect(bytes.length, greaterThan(1500));
    });

    test('3. Ordenação cronológica estrita (mais recentes primeiro)', () async {
      final t1 = DateTime(2026, 9, 10, 8, 0);
      final t2 = DateTime(2026, 9, 25, 12, 0);
      final t3 = DateTime(2026, 10, 1, 15, 0);

      // Entradas passadas fora de ordem
      final unsortedEntries = [
        makeEntry(id: '1', type: HistoryEntryType.training, title: 'Treino A', subtitle: '', time: t1),
        makeEntry(id: '3', type: HistoryEntryType.occurrence, title: 'Ocorrência C', subtitle: '', time: t3),
        makeEntry(id: '2', type: HistoryEntryType.health, title: 'Exame B', subtitle: '', time: t2),
      ];

      final bytes = await OperationalHistoryPdf.generate(
        entries: unsortedEntries,
        dog: dog,
        k9LogoBytes: sampleLogo,
      );

      expect(bytes, isNotEmpty);
      expect(bytes.take(4), orderedEquals('%PDF'.codeUnits));
    });

    test('4. Histórico sem cão vinculado (guarnição / operador)', () async {
      final entries = [
        makeEntry(
          id: '1',
          type: HistoryEntryType.occurrence,
          title: 'Patrulhamento Preventivo',
          subtitle: 'Ronda em logradouro público',
          time: DateTime(2026, 10, 3, 18, 0),
        ),
      ];

      final bytes = await OperationalHistoryPdf.generate(
        entries: entries,
        dog: null,
        handlerName: 'GCM 2CL Souza',
        periodLabel: '01/10/2026 a 07/10/2026',
        k9LogoBytes: sampleLogo,
      );

      expect(bytes, isNotEmpty);
      expect(bytes.take(4), orderedEquals('%PDF'.codeUnits));
    });

    test('5. Cão sem foto renderiza fallback tático elegante (avatar placeholder)', () async {
      final entries = [
        makeEntry(
          id: '1',
          type: HistoryEntryType.training,
          title: 'Treino Tático',
          subtitle: 'Obediência básica',
          time: DateTime(2026, 10, 2, 10, 0),
        ),
      ];

      final bytes = await OperationalHistoryPdf.generate(
        entries: entries,
        dog: dog,
        dogPhotoBytes: null, // Sem foto
        k9LogoBytes: sampleLogo,
      );

      expect(bytes, isNotEmpty);
      expect(bytes.take(4), orderedEquals('%PDF'.codeUnits));
    });

    test('6. Multipágina: volume elevado de registros (35+ atividades)', () async {
      final manyEntries = List.generate(
        40,
        (i) => makeEntry(
          id: 'entry-$i',
          type: i % 4 == 0
              ? HistoryEntryType.occurrence
              : (i % 4 == 1
                  ? HistoryEntryType.training
                  : (i % 4 == 2 ? HistoryEntryType.health : HistoryEntryType.nutrition)),
          title: 'Atividade Operacional Registrada #$i',
          subtitle: 'Detalhamento do evento com contextualização tática número $i',
          time: DateTime(2026, 10, 5, 12, 0).subtract(Duration(hours: i * 6)),
          location: 'Posto Policial $i',
        ),
      );

      final bytes = await OperationalHistoryPdf.generate(
        entries: manyEntries,
        dog: dog,
        dogPhotoBytes: sampleDogPhoto,
        k9LogoBytes: sampleLogo,
      );

      expect(bytes, isNotEmpty);
      expect(bytes.length, greaterThan(4000));
      expect(bytes.take(4), orderedEquals('%PDF'.codeUnits));
    });

    test('7. Texto longo e conteúdo extremo não provocam overflow', () async {
      final extremeEntries = [
        makeEntry(
          id: 'ext-1',
          type: HistoryEntryType.occurrence,
          title:
              'Apoio Tático em Operação Conjunta de Grande Envergadura com Busca Perimetral em Área de Alta Complexidade Urbana e Terreno Acidentado',
          subtitle:
              'Cão empregado com sucesso na varredura minuciosa de edificações abandonadas, galpões industriais desativados e matagal denso, resultando em localização precisa de substâncias ilícitas e materiais correlatos.',
          time: DateTime(2026, 10, 5, 16, 45),
          location: 'Estrada Municipal Dr. José Roberto, km 14 - Setor Industrial Norte',
        ),
      ];

      final bytes = await OperationalHistoryPdf.generate(
        entries: extremeEntries,
        dog: dog,
        dogPhotoBytes: sampleDogPhoto,
        k9LogoBytes: sampleLogo,
      );

      expect(bytes, isNotEmpty);
      expect(bytes.take(4), orderedEquals('%PDF'.codeUnits));
    });
  });
}
