import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:canil_gcm/features/dogs/data/weight_history_service.dart';
import 'package:canil_gcm/features/dogs/domain/dog.dart';
import 'package:canil_gcm/features/dogs/domain/weight_record.dart';
import 'package:canil_gcm/features/dogs/presentation/screens/weight_history_screen.dart';
import 'package:canil_gcm/features/health/presentation/weight/health_weight_form_sheet.dart';

final class _HistoryService extends WeightHistoryService {
  _HistoryService(this.result) : super(firestore: FakeFirebaseFirestore());

  final Stream<List<WeightRecord>> result;

  @override
  Stream<List<WeightRecord>> watchHistory(String dogId, {int limit = 50}) =>
      result;
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
    Stream<List<WeightRecord>> stream,
  ) async {
    tester.view.physicalSize = const Size(430, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        home: WeightHistoryScreen(
          dog: dog,
          historyService: _HistoryService(stream),
        ),
      ),
    );
    await tester.pump();
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
    await pumpScreen(
      tester,
      Stream.value([record(context: 'clinical', notes: 'retorno')]),
    );
    expect(find.textContaining('24.5'), findsWidgets);
    expect(find.textContaining('Ana'), findsWidgets);
    expect(find.textContaining('Clínica'), findsOneWidget);
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
