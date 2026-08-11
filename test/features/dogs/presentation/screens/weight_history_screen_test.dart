import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:canil_gcm/features/dogs/data/weight_history_service.dart';
import 'package:canil_gcm/features/dogs/domain/dog.dart';
import 'package:canil_gcm/features/dogs/domain/weight_record.dart';
import 'package:canil_gcm/features/dogs/presentation/screens/weight_history_screen.dart';
import 'package:canil_gcm/features/health/presentation/weight/health_weight_form_sheet.dart';

/// Fake com DUAS rotas distintas, porque a tela tem duas fontes distintas
/// (WEIGHT-01E-R): o stream alimenta lista/gráfico e [getLatest] é a autoridade
/// canônica do headline "PESO ATUAL".
final class _HistoryService extends WeightHistoryService {
  _HistoryService(this.result, {this.latest, this.latestError})
    : super(firestore: FakeFirebaseFirestore());

  final Stream<List<WeightRecord>> result;

  /// Peso atual canônico devolvido pela policy coletiva.
  final WeightRecord? latest;

  /// Quando presente, simula bloqueador global / falha de leitura.
  final Object? latestError;

  @override
  Stream<List<WeightRecord>> watchHistory(String dogId, {int limit = 50}) =>
      result;

  @override
  Future<WeightRecord?> getLatest(String dogId) async {
    if (latestError != null) throw latestError!;
    return latest;
  }
}

WeightRecord record({
  String id = 'weight-1',
  double weight = 24.5,
  String context = '',
  String? notes,
}) => WeightRecord.fromJson({
  'id': id,
  'schema_version': 1,
  'weight_kg': weight,
  'measured_at': Timestamp.fromDate(DateTime.utc(2026, 8, 4)),
  'recorded_by': {'uid': 'user-1', 'name': 'Ana', 'internal_role': 'condutor'},
  if (context.isNotEmpty) 'context': context,
  'notes': ?notes,
});

void main() {
  final dog = Dog(
    id: 'dog-1',
    name: 'Kira',
    breed: 'Pastor',
    dateOfBirth: DateTime.utc(2020),
  );

  Future<void> pumpScreen(
    WidgetTester tester,
    Stream<List<WeightRecord>> stream, {
    WeightRecord? latest,
    Object? latestError,
  }) async {
    tester.view.physicalSize = const Size(430, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        home: WeightHistoryScreen(
          dog: dog,
          historyService: _HistoryService(
            stream,
            latest: latest,
            latestError: latestError,
          ),
        ),
      ),
    );
    // Duas fontes: o pump inicial resolve o stream, o settle resolve o
    // Future do peso atual canônico.
    await tester.pumpAndSettle();
  }

  testWidgets('renders canonical empty state without dog.weight fallback', (
    tester,
  ) async {
    await pumpScreen(tester, Stream.value(const []));
    expect(find.text('Nenhuma pesagem canônica registrada.'), findsOneWidget);
    expect(find.textContaining('Estável'), findsNothing);
    expect(find.textContaining('28.0'), findsNothing);
  });

  testWidgets('renders canonical record and recorded_by name', (tester) async {
    final canonical = record(context: 'clinical', notes: 'retorno');
    await pumpScreen(tester, Stream.value([canonical]), latest: canonical);
    expect(find.textContaining('24.5'), findsWidgets);
    expect(find.textContaining('Ana'), findsWidgets);
    expect(find.textContaining('Clínica'), findsOneWidget);
  });

  testWidgets(
    'renders recorder-less legacy record without author suffix or RA leak',
    (tester) async {
      final legacy = WeightRecord(
        id: 'legacy-1',
        weightKg: 24.5,
        measuredAt: DateTime.utc(2026, 8, 4),
        // Autoria canônica ausente (legado reconhecido).
        recordedBy: null,
      );
      await pumpScreen(tester, Stream.value([legacy]), latest: legacy);

      // A pesagem permanece visível.
      expect(find.textContaining('24.5'), findsWidgets);
      // Sem autor inventado, sem rótulo substituto, sem RA / referência legada.
      expect(find.textContaining('Ana'), findsNothing);
      expect(find.textContaining('RA-'), findsNothing);
      expect(find.textContaining('Ragonha'), findsNothing);
      expect(find.textContaining('desconhecido'), findsNothing);
      // Sufixo de autoria ' · ' não deve acompanhar a data quando ausente.
      expect(find.textContaining('Medido em'), findsWidgets);
    },
  );

  // WEIGHT-01E-R — o headline "PESO ATUAL" é o canônico, não `history.last`.
  //
  // Estes testes são discriminantes por construção: o stream contém um
  // registro que a ordenação `measuredAt`-only escolheria, DIFERENTE do atual
  // canônico. Uma regressão para `.last`/`.first` os quebra.
  group('headline canônico vs ordem do stream', () {
    WeightRecord tied(String id, double weight, {DateTime? recordedAt}) =>
        WeightRecord(
          id: id,
          weightKg: weight,
          // MESMO measuredAt: sem desempate, `.last` é arbitrário.
          measuredAt: DateTime.utc(2026, 8, 4),
          recordedBy: null,
          recordedAt: recordedAt,
        );

    /// Busca restrita ao card do peso atual. A lista de histórico abaixo
    /// também renderiza números, então uma busca global não distinguiria o
    /// headline autoritativo de uma linha qualquer.
    /// `findRichText` é necessário: o número do peso é um `TextSpan` dentro de
    /// um `RichText`, que os finders ignoram por padrão.
    Finder inHeadline(String text) => find.descendant(
      of: find.byKey(WeightHistoryScreen.currentWeightCardKey),
      matching: find.textContaining(text, findRichText: true),
    );

    testWidgets('empate de measuredAt: exibe o canônico, não o último', (
      tester,
    ) async {
      final canonical = tied(
        'A',
        24.5,
        recordedAt: DateTime.utc(2026, 8, 4, 12),
      );
      final decoy = tied('Z', 39.9, recordedAt: DateTime.utc(2026, 8, 4, 10));

      // O decoy é o ÚLTIMO da lista e tem o entityId maior: venceria em
      // qualquer ordenação local ingênua.
      await pumpScreen(
        tester,
        Stream.value([canonical, decoy]),
        latest: canonical,
      );

      expect(inHeadline('24.5'), findsWidgets);
      expect(inHeadline('39.9'), findsNothing);
    });

    testWidgets('ordem do stream não altera o headline', (tester) async {
      final canonical = tied(
        'A',
        24.5,
        recordedAt: DateTime.utc(2026, 8, 4, 12),
      );
      final decoy = tied('Z', 39.9, recordedAt: DateTime.utc(2026, 8, 4, 10));

      for (final order in [
        [canonical, decoy],
        [decoy, canonical],
      ]) {
        await pumpScreen(tester, Stream.value(order), latest: canonical);
        expect(inHeadline('24.5'), findsWidgets);
        expect(inHeadline('39.9'), findsNothing);
      }
    });

    testWidgets('inconclusive não promove registro do histórico', (
      tester,
    ) async {
      // Bloqueador global: o histórico tem válidos, mas nenhum é o atual.
      await pumpScreen(
        tester,
        Stream.value([tied('A', 24.5), tied('Z', 39.9)]),
        latestError: const WeightHistoryReadException(
          'malformed_weight_record',
        ),
      );

      expect(inHeadline('não conclusivo'), findsOneWidget);
      // Nenhum valor é promovido a peso atual.
      expect(inHeadline('24.5'), findsNothing);
      expect(inHeadline('39.9'), findsNothing);
    });

    testWidgets('none com histórico presente não fabrica atual', (
      tester,
    ) async {
      // Coleção sem candidatos elegíveis: getLatest devolve null, mas o stream
      // ainda entrega linhas para lista/gráfico.
      await pumpScreen(tester, Stream.value([tied('A', 24.5)]));

      expect(
        inHeadline('Nenhuma pesagem canônica registrada.'),
        findsOneWidget,
      );
      expect(inHeadline('24.5'), findsNothing);
    });
  });

  testWidgets('renders controlled read error state', (tester) async {
    await pumpScreen(
      tester,
      Stream<List<WeightRecord>>.error(StateError('offline')),
    );
    expect(
      find.text('Não foi possível carregar o histórico de peso.'),
      findsOneWidget,
    );
    expect(find.text('TENTAR NOVAMENTE'), findsOneWidget);
  });

  testWidgets('history entry point opens HealthWeightFormSheet', (
    tester,
  ) async {
    await pumpScreen(tester, Stream.value(const []));
    await tester.tap(find.text('REGISTRAR NOVA PESAGEM'));
    await tester.pumpAndSettle();
    expect(find.byType(HealthWeightFormSheet), findsOneWidget);
  });
}
