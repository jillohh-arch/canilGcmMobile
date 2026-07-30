import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

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
}
