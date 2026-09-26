import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:mocktail/mocktail.dart';
import 'package:provider/provider.dart';

import 'package:canil_gcm/features/dogs/data/dog_service.dart';
import 'package:canil_gcm/features/health/data/canonical/restriction/firestore_health_restriction_history_reader.dart';
import 'package:canil_gcm/features/health/data/coexistence/timeline/coexistence_health_timeline_source.dart';
import 'package:canil_gcm/features/health/data/coexistence/timeline/memory_timeline_source_reader.dart';
import 'package:canil_gcm/features/health/data/health_service.dart';
import 'package:canil_gcm/features/health/domain/health_v1_enums_ext.dart';
import 'package:canil_gcm/features/health/domain/health_v1_models.dart';
import 'package:canil_gcm/features/health/domain/health_v1_value_objects.dart';
import 'package:canil_gcm/features/health/domain/operational_restriction.dart';
import 'package:canil_gcm/features/health/presentation/screens/health_v1_entry_screen.dart';
import 'package:canil_gcm/features/health/presentation/summary/health_summary_dog_context_view.dart';
import 'package:canil_gcm/features/health/presentation/summary/health_summary_source.dart';
import 'package:canil_gcm/features/health/presentation/summary/health_summary_view_data.dart';
import 'package:canil_gcm/features/health/presentation/timeline/detail/health_timeline_detail_target.dart';
import 'package:canil_gcm/features/health/presentation/timeline/health_timeline_entry_view.dart';
import 'package:canil_gcm/features/health/presentation/timeline/health_timeline_screen.dart';
import 'package:canil_gcm/features/health/presentation/timeline/models/health_timeline_detail_reference.dart';
import 'package:canil_gcm/features/health/presentation/viewmodels/health_viewmodel.dart';
import 'package:canil_gcm/features/nutrition/presentation/viewmodels/nutrition_viewmodel.dart';

class _FixedSummarySource implements HealthSummarySource {
  _FixedSummarySource.single(HealthSummaryViewData p)
    : payloadByDog = {p.dogId: p};
  final Map<String, HealthSummaryViewData> payloadByDog;

  @override
  Stream<HealthSummaryViewData?> watchSummary(String dogId) async* {
    yield payloadByDog[dogId] ?? HealthSummaryViewData(dogId: dogId);
  }
}

class _MockNutritionViewModel extends Mock implements NutritionViewModel {}

void main() {
  setUpAll(() {
    GoogleFonts.config.allowRuntimeFetching = false;
    registerFallbackValue('');
  });

  final actor = RecordedBy(
    uid: 'u-1',
    name: 'GCM Oliveira',
    internalRole: 'condutor',
  );

  final vet = ProfessionalIdentity(
    name: 'Dra. Beatriz Santos',
    registrationType: ProfessionalRegistrationType.crmv,
    registrationNumber: 'SP-12345',
    clinic: 'Clínica Central',
  );

  final sourceDoc = const HealthDocumentRef(healthDocumentId: 'doc-1');

  OperationalRestriction buildRestriction({
    required String id,
    required String dogId,
    required DateTime issuedAt,
    RestrictionLevel level = RestrictionLevel.absolute,
    RestrictionCategory category = RestrictionCategory.medicationEffect,
    String description = 'Repouso absoluto por efeito de sedação',
  }) {
    return OperationalRestriction(
      id: id,
      dogId: dogId,
      level: level,
      category: category,
      description: description,
      issuedAt: issuedAt,
      recordedBy: actor,
      professional: vet,
      sourceDocument: sourceDoc,
      status: RestrictionStatus.active,
      schemaVersion: 1,
      activitiesRestricted: const [],
    );
  }

  final dogContext = HealthSummaryDogContextView(
    dogId: 'dog-1',
    name: 'Thor',
    breed: 'Pastor Alemão',
  );

  final canonicalItem = HealthTimelineEntryView(
    id: 'consultation:c1',
    dogId: 'dog-1',
    type: HealthTimelineTypeView.known(HealthTimelineType.consultation),
    occurredAt: DateTime.utc(2026, 7, 10, 14),
    recordedAt: DateTime.utc(2026, 7, 10, 14),
    title: 'Consulta Semestral',
    status: HealthTimelineEntryStatus.finalised,
    detailReference: const HealthTimelineDetailReference(
      sourceType: 'health_events',
      sourceId: 'c1',
    ),
  );

  _MockNutritionViewModel buildNutritionMock() {
    final mock = _MockNutritionViewModel();
    when(() => mock.historyLoading).thenReturn(false);
    when(() => mock.totalFeedings90d).thenReturn(0);
    when(() => mock.addListener(any())).thenReturn(null);
    when(() => mock.removeListener(any())).thenReturn(null);
    when(() => mock.dispose()).thenReturn(null);
    when(
      () => mock.loadForDog(any(), forceReload: any(named: 'forceReload')),
    ).thenAnswer((_) async {});
    when(() => mock.loadFullHistory(any())).thenAnswer((_) async {});
    return mock;
  }

  Widget wrapWithNav(Widget child, {FakeFirebaseFirestore? firestore}) {
    final fake = firestore ?? FakeFirebaseFirestore();
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<HealthViewModel>(
          create: (_) => HealthViewModel.withServices(
            HealthService(firestore: fake),
            DogService(firestore: fake),
          ),
        ),
        ChangeNotifierProvider<NutritionViewModel>.value(
          value: buildNutritionMock(),
        ),
      ],
      child: MaterialApp(home: Scaffold(body: child)),
    );
  }

  Future<void> setPhoneSurface(WidgetTester tester) async {
    final view = tester.view;
    view.physicalSize = const Size(400, 1100);
    view.devicePixelRatio = 1.0;
    addTearDown(view.resetPhysicalSize);
    addTearDown(view.resetDevicePixelRatio);
  }

  testWidgets('HealthV1EntryScreen exibe evento de restrição no Histórico', (
    tester,
  ) async {
    await setPhoneSurface(tester);

    final restriction = buildRestriction(
      id: 'rst-screen-1',
      dogId: 'dog-1',
      issuedAt: DateTime.utc(2026, 7, 10, 10),
    );

    final reader = MemoryHealthRestrictionHistoryReader(
      restrictionsByDogId: {
        'dog-1': [restriction],
      },
    );

    await tester.pumpWidget(
      wrapWithNav(
        HealthV1EntryScreen(
          dogId: 'dog-1',
          source: _FixedSummarySource.single(
            HealthSummaryViewData(dogId: 'dog-1'),
          ),
          timelineSource: CoexistenceHealthTimelineSourceFactory.forReaders([
            MemoryTimelineSourceReader(
              sourceKey: 'canon',
              items: [canonicalItem],
            ),
          ]),
          restrictionHistoryReader: reader,
          dogContextOverride: dogContext,
        ),
      ),
    );

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    // Navega para a aba Histórico
    await tester.tap(find.text('Histórico'));
    await tester.pumpAndSettle();

    expect(find.byType(HealthTimelineScreen), findsOneWidget);

    // Encontra tanto a consulta quanto a restrição
    expect(find.text('Consulta Semestral'), findsOneWidget);
    expect(find.text('Restrição operacional aplicada'), findsOneWidget);
    expect(find.textContaining('Restrição absoluta'), findsOneWidget);
    expect(find.textContaining('Efeito de medicação'), findsOneWidget);
  });

  testWidgets('Tocar no card de restrição navega para HealthRestrictionDetailScreen', (
    tester,
  ) async {
    await setPhoneSurface(tester);

    final fakeFirestore = FakeFirebaseFirestore();
    // Prepara documento da restrição no fakeFirestore para leitura de detalhe
    await fakeFirestore
        .collection('dogs')
        .doc('dog-1')
        .collection('operational_restrictions')
        .doc('rst-nav-test')
        .set({
          'level': 'absolute',
          'category': 'medication_effect',
          'description': 'Repouso absoluto por efeito de sedação',
          'issued_at': '2026-07-10T10:00:00.000Z',
          'status': 'active',
          'schema_version': 1,
          'recorded_by': {
            'uid': 'u-1',
            'name': 'GCM Oliveira',
            'internal_role': 'condutor',
          },
          'professional': {
            'name': 'Dra. Beatriz Santos',
            'registration_type': 'CRMV',
            'registration_number': 'SP-12345',
            'clinic': 'Clínica Central',
          },
          'source_document': {'health_document_id': 'doc-1'},
        });

    final restriction = buildRestriction(
      id: 'rst-nav-test',
      dogId: 'dog-1',
      issuedAt: DateTime.utc(2026, 7, 10, 10),
    );

    final reader = MemoryHealthRestrictionHistoryReader(
      restrictionsByDogId: {
        'dog-1': [restriction],
      },
    );

    HealthTimelineDetailTarget? navigatedTarget;

    await tester.pumpWidget(
      wrapWithNav(
        HealthV1EntryScreen(
          dogId: 'dog-1',
          source: _FixedSummarySource.single(
            HealthSummaryViewData(dogId: 'dog-1'),
          ),
          timelineSource: CoexistenceHealthTimelineSourceFactory.forReaders([
            MemoryTimelineSourceReader(
              sourceKey: 'canon',
              items: [canonicalItem],
            ),
          ]),
          restrictionHistoryReader: reader,
          dogContextOverride: dogContext,
          onTimelineNavigate: (target) async {
            navigatedTarget = target;
          },
        ),
        firestore: fakeFirestore,
      ),
    );

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    await tester.tap(find.text('Histórico'));
    await tester.pumpAndSettle();

    final restrictionCard = find.text('Restrição operacional aplicada');
    expect(restrictionCard, findsOneWidget);

    await tester.tap(restrictionCard);
    await tester.pumpAndSettle();

    expect(navigatedTarget, isNotNull);
    expect(navigatedTarget, isA<RestrictionDetailTarget>());
    expect(navigatedTarget!.dogId, 'dog-1');
    expect(navigatedTarget!.sourceId, 'rst-nav-test');
  });

  testWidgets('Troca de cão no HealthV1EntryScreen atualiza restrições exibidas', (
    tester,
  ) async {
    await setPhoneSurface(tester);

    final rThor = buildRestriction(
      id: 'rst-thor',
      dogId: 'dog-thor',
      issuedAt: DateTime.utc(2026, 7, 10, 10),
      description: 'Restrição do Thor',
    );
    final rZeus = buildRestriction(
      id: 'rst-zeus',
      dogId: 'dog-zeus',
      issuedAt: DateTime.utc(2026, 7, 11, 10),
      description: 'Restrição do Zeus',
    );

    final reader = MemoryHealthRestrictionHistoryReader(
      restrictionsByDogId: {
        'dog-thor': [rThor],
        'dog-zeus': [rZeus],
      },
    );

    await tester.pumpWidget(
      wrapWithNav(
        HealthV1EntryScreen(
          key: const ValueKey('health-entry'),
          dogId: 'dog-thor',
          source: _FixedSummarySource.single(
            HealthSummaryViewData(dogId: 'dog-thor'),
          ),
          timelineSource: CoexistenceHealthTimelineSourceFactory.forReaders([
            MemoryTimelineSourceReader(sourceKey: 'canon', items: const []),
          ]),
          restrictionHistoryReader: reader,
          dogContextOverride: HealthSummaryDogContextView(
            dogId: 'dog-thor',
            name: 'Thor',
          ),
        ),
      ),
    );

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tap(find.text('Histórico'));
    await tester.pumpAndSettle();

    expect(find.text('Restrição operacional aplicada'), findsOneWidget);
    expect(find.textContaining('Restrição do Thor'), findsOneWidget);
    expect(find.textContaining('Restrição do Zeus'), findsNothing);

    // Atualiza widget para dog-zeus
    await tester.pumpWidget(
      wrapWithNav(
        HealthV1EntryScreen(
          key: const ValueKey('health-entry'),
          dogId: 'dog-zeus',
          source: _FixedSummarySource.single(
            HealthSummaryViewData(dogId: 'dog-zeus'),
          ),
          timelineSource: CoexistenceHealthTimelineSourceFactory.forReaders([
            MemoryTimelineSourceReader(sourceKey: 'canon', items: const []),
          ]),
          restrictionHistoryReader: reader,
          dogContextOverride: HealthSummaryDogContextView(
            dogId: 'dog-zeus',
            name: 'Zeus',
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('Restrição operacional aplicada'), findsOneWidget);
    expect(find.textContaining('Restrição do Zeus'), findsOneWidget);
    expect(find.textContaining('Restrição do Thor'), findsNothing);
  });
}
