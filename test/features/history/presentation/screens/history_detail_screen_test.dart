import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:canil_gcm/features/dogs/domain/weight_record.dart';
import 'package:canil_gcm/features/history/presentation/screens/history_detail_screen.dart';
import 'package:canil_gcm/features/history/presentation/screens/history_screen.dart';
import 'package:canil_gcm/features/nutrition/domain/feeding.dart';

void main() {
  setUpAll(() {
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  Widget buildSubject({Feeding? feeding, Map<String, dynamic>? details}) {
    final source = HistoryEntry(
      id: 'nutrition-1',
      type: HistoryEntryType.nutrition,
      title: 'Alimentação registrada',
      subtitle: '',
      time: DateTime(2026, 7, 30, 12),
      author: 'GCM Teste',
      tag: 'NUTRIÇÃO',
      icon: Icons.rice_bowl,
      color: Colors.amber,
      originalModel: feeding,
      details: details ?? const {},
    );
    final detail = RecordDetail(
      id: source.id,
      type: source.type,
      category: 'Nutrição',
      title: source.title,
      subtitle: source.subtitle,
      location: '',
      dateTime: source.time,
      author: source.author,
      dogName: 'K9 Teste',
      handlerName: 'GCM Teste',
      status: 'Finalizado',
      syncStatus: 'Sincronizado',
      duration: 'Não informado',
      team: '',
      notes: '',
      icon: source.icon,
      color: source.color,
      internalEvents: const [],
      auditEvents: const [],
      source: source,
    );

    return MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(child: HistoryNutricaoBody(detail: detail)),
      ),
    );
  }

  Feeding feeding({
    required int amount,
    required int prescription,
    required double divergence,
  }) {
    return Feeding(
      id: 'feeding-1',
      period: 'almoco',
      amountGrams: amount,
      prescriptionAtTime: prescription,
      divergencePercent: divergence,
      fedAt: DateTime(2026, 7, 30, 12),
      fedBy: 'uid-test',
    );
  }

  testWidgets(
    'exibe somente valores reais quando originalModel está presente',
    (tester) async {
      await tester.pumpWidget(
        buildSubject(
          feeding: feeding(amount: 420, prescription: 400, divergence: 5),
          details: const {'Ração': 'Ração Operacional Real'},
        ),
      );

      expect(find.text('420g'), findsOneWidget);
      expect(find.text('400g'), findsOneWidget);
      expect(find.text('Ração Operacional Real'), findsOneWidget);
      expect(find.text('EM CONFORMIDADE'), findsOneWidget);
      expect(find.text('350g'), findsNothing);
      expect(find.text('Ração Premium K9 Adulto'), findsNothing);
      expect(find.textContaining('Dra. Patrícia Lima'), findsNothing);
    },
  );

  testWidgets(
    'modelo ausente não fabrica quantidade alimento ou conformidade',
    (tester) async {
      await tester.pumpWidget(buildSubject());

      expect(find.text('350g'), findsNothing);
      expect(find.text('Ração Premium K9 Adulto'), findsNothing);
      expect(find.text('EM CONFORMIDADE'), findsNothing);
      expect(find.text('Não informado'), findsNWidgets(3));
      expect(find.text('NÃO INFORMADO'), findsOneWidget);
      expect(find.text('VÍNCULO CLÍNICO'), findsNothing);
      expect(find.text('FOTO DE VERIFICAÇÃO'), findsNothing);
    },
  );

  testWidgets('dado parcial preserva somente os valores realmente presentes', (
    tester,
  ) async {
    await tester.pumpWidget(
      buildSubject(
        feeding: feeding(amount: 275, prescription: 0, divergence: 0),
        details: const {'Ração': 'Ração Parcial Real'},
      ),
    );

    expect(find.text('275g'), findsOneWidget);
    expect(find.text('Ração Parcial Real'), findsOneWidget);
    expect(find.text('Não informado'), findsOneWidget);
    expect(find.text('NÃO INFORMADO'), findsOneWidget);
    expect(find.text('0g'), findsNothing);
    expect(find.text('EM CONFORMIDADE'), findsNothing);
  });

  group('autoria ausente em pesagem legada (RecordDetail.fromEntry)', () {
    HistoryEntry weightEntry({required String author}) => HistoryEntry(
      id: 'weight_1',
      type: HistoryEntryType.health,
      title: 'Pesagem operacional registrada',
      subtitle: 'Peso atual: 32.0 kg',
      time: DateTime(2026, 8, 4, 10),
      author: author,
      authorId: author,
      tag: 'PESO',
      icon: Icons.monitor_weight_rounded,
      color: Colors.purple,
      details: const {'_healthKind': 'weight', 'Peso': '32.0 kg'},
    );

    test('peso sem autoria não fabrica Ragonha nem GCM Ragonha', () {
      final detail = RecordDetail.fromEntry(weightEntry(author: ''));

      expect(detail.author, isEmpty);
      expect(detail.handlerName, isEmpty);
      expect(detail.author, isNot(contains('Ragonha')));
      expect(detail.handlerName, isNot(contains('Ragonha')));
      // O evento de criação não afirma autoria factual.
      final created = detail.auditEvents.first;
      expect(created.user, isEmpty);
      expect(created.action, 'Registro criado');
    });

    test('peso COM autoria continua normalizando o nome (sem regressão)', () {
      final detail = RecordDetail.fromEntry(weightEntry(author: 'Ana'));

      expect(detail.author, 'GCM Ana');
      expect(detail.handlerName, 'Ana');
    });

    test('outros tipos health sem autor mantêm fallback existente', () {
      final vaccine = HistoryEntry(
        id: 'vac_1',
        type: HistoryEntryType.health,
        title: 'Vacinação',
        subtitle: '',
        time: DateTime(2026, 8, 4, 10),
        author: '',
        tag: 'SAÚDE',
        icon: Icons.vaccines,
        color: Colors.teal,
        details: const {'_healthKind': 'vaccine'},
      );

      final detail = RecordDetail.fromEntry(vaccine);

      // Comportamento legado preservado para tipos que não são pesagem.
      expect(detail.author, 'GCM Ragonha');
      expect(detail.handlerName, 'Ragonha');
    });
  });

  testWidgets('detalhe de pesagem sem autoria omite identidade e vet', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(430, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final detail = RecordDetail.fromEntry(
      HistoryEntry(
        id: 'weight_1',
        type: HistoryEntryType.health,
        title: 'Pesagem operacional registrada',
        subtitle: 'Peso atual: 32.0 kg',
        time: DateTime(2026, 8, 4, 10),
        author: '',
        authorId: '',
        tag: 'PESO',
        icon: Icons.monitor_weight_rounded,
        color: Colors.purple,
        details: const {'_healthKind': 'weight', 'Peso': '32.0 kg'},
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(child: HistorySaudeBody(detail: detail)),
        ),
      ),
    );

    expect(find.textContaining('Ragonha'), findsNothing);
    expect(find.textContaining('GCM Ragonha'), findsNothing);
    expect(find.textContaining('desconhecido'), findsNothing);
    expect(find.textContaining('RA-'), findsNothing);
    // Bloco de responsável técnico não é renderizado sem vet factual.
    expect(find.text('RESPONSÁVEL TÉCNICO'), findsNothing);
  });

  group('scaffold completo do detalhe (RegistroDetalhePage)', () {
    // Fluxo real: HistoryEntry → RecordDetail.fromEntry → RegistroDetalhePage,
    // incluindo o card de identificação (onde o antigo 'GCM Ragonha' surgia).
    HistoryEntry weightEntry({required String author}) => HistoryEntry(
      id: 'weight_1',
      type: HistoryEntryType.health,
      title: 'Pesagem operacional registrada',
      subtitle: 'Peso atual: 32.0 kg',
      time: DateTime(2026, 8, 4, 10),
      author: author,
      authorId: author,
      tag: 'PESO',
      icon: Icons.monitor_weight_rounded,
      color: Colors.purple,
      originalModel: WeightRecord(
        id: 'weight_1',
        weightKg: 32.0,
        measuredAt: DateTime.utc(2026, 8, 4, 10),
        recordedBy: null,
      ),
      details: const {
        '_healthKind': 'weight',
        'Cão': 'Aracnid',
        'Peso': '32.0 kg',
      },
    );

    // Viewport largo evita overflow horizontal do card no ambiente de teste;
    // o card de identificação usa RichText, portanto os finders precisam de
    // findRichText: true para realmente atravessar seus TextSpans.
    Future<void> pump(WidgetTester tester, HistoryEntry entry) async {
      tester.view.physicalSize = const Size(1400, 2200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(home: RegistroDetalhePage(entry: entry)),
      );
      await tester.pump();
    }

    testWidgets('pesagem sem autoria: card renderiza sem autor fabricado', (
      tester,
    ) async {
      await pump(tester, weightEntry(author: ''));

      // Detalhe renderiza e dado factual do K9 permanece visível no card.
      expect(find.byType(RegistroDetalhePage), findsOneWidget);
      expect(find.textContaining('Aracnid', findRichText: true), findsWidgets);

      // Nenhuma autoria fabricada em toda a árvore do scaffold (inclui o
      // card de identificação em RichText, onde o antigo 'GCM Ragonha' surgia).
      expect(find.textContaining('Ragonha', findRichText: true), findsNothing);
      expect(
        find.textContaining('desconhecido', findRichText: true),
        findsNothing,
      );
      expect(find.textContaining('RA-', findRichText: true), findsNothing);
      expect(
        find.textContaining('Criado por', findRichText: true),
        findsNothing,
      );
      // Responsável técnico ausente sem vet factual.
      expect(find.text('RESPONSÁVEL TÉCNICO'), findsNothing);
    });

    testWidgets('pesagem com autoria: card preserva o nome (sem regressão)', (
      tester,
    ) async {
      await pump(tester, weightEntry(author: 'Ana'));

      expect(find.byType(RegistroDetalhePage), findsOneWidget);
      // Normalização preservada: 'Ana' → 'GCM Ana' no card de identificação.
      expect(find.textContaining('Ana', findRichText: true), findsWidgets);
      expect(find.textContaining('Ragonha', findRichText: true), findsNothing);
    });
  });
}
