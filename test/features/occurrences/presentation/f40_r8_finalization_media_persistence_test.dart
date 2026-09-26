// F40 R8 — Targeted Automated Verification Suite
// Finalization Media Persistence, History Projection, and PDF Binding.
//
// 11 Targeted Scenarios:
//  1. History occurrence with one finalization photo => media count 1.
//  2. History occurrence with zero finalization photos => media count 0.
//  3. History media timestamp as Timestamp => renders safely.
//  4. History media timestamp as DateTime => renders safely.
//  5. History media timestamp null => no crash.
//  6. Stale cached occurrence + fresh sealed occurrence => PDF uses fresh finalizationPhotos.
//  7. PDF: 0 event + 1 finalization => total media count 1.
//  8. PDF: 2 event + 1 finalization => total media count 3.
//  9. PDF: 0 + 0 => proper empty state.
// 10. Finalization media appears in media page when event media is empty.
// 11. Existing active-event media PDF behavior remains unchanged.

import 'dart:typed_data';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart' as fb_auth;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:canil_gcm/core/services/pdf_generator/occurrence_pdf_generator.dart';
import 'package:canil_gcm/features/auth/presentation/viewmodels/auth_viewmodel.dart';
import 'package:canil_gcm/features/dogs/domain/dog.dart';
import 'package:canil_gcm/features/dogs/presentation/viewmodels/dog_viewmodel.dart';
import 'package:canil_gcm/features/history/presentation/screens/history_detail_screen.dart';
import 'package:canil_gcm/features/history/presentation/screens/history_screen.dart';
import 'package:canil_gcm/features/occurrences/data/occurrence_event_repository.dart';
import 'package:canil_gcm/features/occurrences/data/occurrence_repository.dart';
import 'package:canil_gcm/features/occurrences/data/signature_repository.dart';
import 'package:canil_gcm/features/occurrences/domain/occurrence.dart';
import 'package:canil_gcm/features/occurrences/domain/occurrence_event.dart';
import 'package:canil_gcm/features/occurrences/domain/occurrence_event_category.dart';
import 'package:canil_gcm/features/occurrences/domain/occurrence_result.dart';
import 'package:canil_gcm/features/occurrences/domain/occurrence_status.dart';
import 'package:canil_gcm/features/occurrences/presentation/screens/occurrence_confirmation_screen.dart';
import 'package:canil_gcm/features/occurrences/presentation/view_models/occurrence_view_model.dart';

import '../pdf/pdf_diagnostic_harness.dart';

Dog _createTestDog() => Dog(
      id: 'dog-tc1-001',
      name: 'Thor',
      breed: 'Pastor Belga Malinois',
      dateOfBirth: DateTime(2021, 3, 10),
      registrationNumber: 'K9-0001',
    );

Occurrence _createSampleOccurrence({
  required String id,
  List<String> finalizationPhotos = const [],
  OccurrenceStatus status = OccurrenceStatus.finalized,
}) {
  final now = DateTime(2026, 9, 1, 10, 0);
  return Occurrence(
    id: id,
    shiftId: 'shift-01',
    primaryHandlerId: 'handler-01',
    primaryHandlerRa: '12345',
    dogId: 'dog-tc1-001',
    typeCode: 'APOIO',
    typeName: 'Apoio Policial',
    locationAddress: 'Rua das Flores, 500 - Limeira/SP',
    gpsLat: -22.5645,
    gpsLng: -47.4017,
    status: status,
    startedAt: now.subtract(const Duration(hours: 2)),
    finalizedAt: now,
    createdAt: now.subtract(const Duration(hours: 2)),
    updatedAt: now,
    finalReport: 'Relatório de encerramento da ocorrência com mídia.',
    finalizationPhotos: finalizationPhotos,
  );
}

OccurrenceEvent _createSampleEvent(String id, List<String> photos) {
  final ts = DateTime(2026, 9, 1, 9, 0);
  return OccurrenceEvent(
    id: id,
    occurrenceId: 'occ-f40-r8',
    timestamp: ts,
    title: 'Registro de campo',
    description: 'Evento com fotos operacionais',
    category: OccurrenceEventCategory.other,
    photoUrls: photos,
    createdAt: ts,
    updatedAt: ts,
  );
}

class _TestDogViewModel extends ChangeNotifier implements DogViewModel {
  final Dog _dog;
  _TestDogViewModel(this._dog);

  @override
  List<Dog> get dogs => [_dog];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _TestAuthViewModel extends ChangeNotifier implements AuthViewModel {
  @override
  fb_auth.User? get user => null;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _TestOccurrenceViewModel extends OccurrenceViewModel {
  Occurrence? capturedOccurrenceForPdf;
  final Occurrence freshOccurrence;
  final Occurrence cachedOccurrence;

  _TestOccurrenceViewModel({
    required super.repository,
    required super.eventRepository,
    required super.signatureRepository,
    required this.freshOccurrence,
    required this.cachedOccurrence,
  });

  @override
  List<Occurrence> get occurrences => [cachedOccurrence];

  @override
  Occurrence? get openOccurrence => cachedOccurrence;

  @override
  Future<Occurrence?> getById(String id) async => freshOccurrence;

  @override
  Future<List<OccurrenceEvent>> getEvents(String occurrenceId) async => [];

  @override
  Future<Uint8List> generatePdf({
    required Occurrence occurrence,
    required List<OccurrenceEvent> events,
    required Dog dog,
    required String handlerName,
    required String handlerRa,
  }) async {
    capturedOccurrenceForPdf = occurrence;
    return Uint8List.fromList([1, 2, 3, 4]);
  }

  @override
  Future<void> recordPdfAccess({
    required String occurrenceId,
    required String action,
    String? pdfUrl,
  }) async {}
}

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await installHermeticPdfHarness();
  });

  tearDownAll(() {
    uninstallHermeticPdfHarness();
  });

  group('F40 R8 — History Projection & Detail Media Counter', () {
    test(
        '1. History occurrence with one finalization photo => media count 1 in projection',
        () {
      final occ = _createSampleOccurrence(
        id: 'occ-f40-1',
        finalizationPhotos: ['https://storage.googleapis.com/final1.jpg'],
      );

      final entry = OccurrenceHistoryBuilder.buildEntry(occ);

      expect(entry.details['_mediaAttachments'], isNotNull);
      final mediaList = entry.details['_mediaAttachments'] as List;
      expect(mediaList.length, 1);
      expect(mediaList.first['url'], 'https://storage.googleapis.com/final1.jpg');
      expect(mediaList.first['category'], 'finalizacao');
    });

    test(
        '2. History occurrence with zero finalization photos => media count 0 in projection',
        () {
      final occ = _createSampleOccurrence(
        id: 'occ-f40-2',
        finalizationPhotos: [],
      );

      final entry = OccurrenceHistoryBuilder.buildEntry(occ);

      final mediaList = entry.details['_mediaAttachments'] as List? ?? [];
      expect(mediaList.length, 0);
    });

    testWidgets(
        '1b. History detail widget renders 1 MÍDIA when finalization photo is present',
        (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final occ = _createSampleOccurrence(
        id: 'occ-f40-widget-1',
        finalizationPhotos: ['https://storage.googleapis.com/final1.jpg'],
      );
      final entry = OccurrenceHistoryBuilder.buildEntry(occ);
      final detail = RecordDetail.fromEntry(entry);

      final db = FakeFirebaseFirestore();
      final occVM = OccurrenceViewModel(
        repository: OccurrenceRepository(db),
        eventRepository: OccurrenceEventRepository(db),
        signatureRepository: SignatureRepository(firestore: db),
        sendTeamNotifications: false,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ChangeNotifierProvider<OccurrenceViewModel>.value(
              value: occVM,
              child: HistoryOccurrenceBody(detail: detail),
            ),
          ),
        ),
      );
      await tester.pump();

      final statItem = find.ancestor(
        of: find.text('MÍDIAS'),
        matching: find.byType(Expanded),
      );
      expect(
        find.descendant(of: statItem, matching: find.text('1')),
        findsOneWidget,
      );
    });

    testWidgets(
        '2b. History detail widget renders 0 MÍDIAS when finalization photos are empty',
        (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final occ = _createSampleOccurrence(
        id: 'occ-f40-widget-0',
        finalizationPhotos: [],
      );
      final entry = OccurrenceHistoryBuilder.buildEntry(occ);
      final detail = RecordDetail.fromEntry(entry);

      final db = FakeFirebaseFirestore();
      final occVM = OccurrenceViewModel(
        repository: OccurrenceRepository(db),
        eventRepository: OccurrenceEventRepository(db),
        signatureRepository: SignatureRepository(firestore: db),
        sendTeamNotifications: false,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ChangeNotifierProvider<OccurrenceViewModel>.value(
              value: occVM,
              child: HistoryOccurrenceBody(detail: detail),
            ),
          ),
        ),
      );
      await tester.pump();

      final statItem = find.ancestor(
        of: find.text('MÍDIAS'),
        matching: find.byType(Expanded),
      );
      expect(
        find.descendant(of: statItem, matching: find.text('0')),
        findsOneWidget,
      );
    });
  });

  group('F40 R8 — History Media Timestamp Compatibility', () {
    testWidgets('3. History media timestamp as Timestamp => renders safely',
        (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final firestoreTimestamp =
          Timestamp.fromDate(DateTime(2026, 9, 1, 14, 25));
      final occ = _createSampleOccurrence(id: 'occ-ts-1');
      final rawEntry = OccurrenceHistoryBuilder.buildEntry(occ);
      final entry = HistoryEntry(
        id: rawEntry.id,
        type: rawEntry.type,
        title: rawEntry.title,
        subtitle: rawEntry.subtitle,
        time: rawEntry.time,
        author: rawEntry.author,
        tag: rawEntry.tag,
        icon: rawEntry.icon,
        color: rawEntry.color,
        originalModel: occ,
        details: {
          ...rawEntry.details,
          '_mediaAttachments': [
            {
              'url': 'https://storage.googleapis.com/test-ts.jpg',
              'timestamp': firestoreTimestamp,
              'category': 'finalizacao',
            },
          ],
        },
      );

      final detail = RecordDetail.fromEntry(entry);

      final db = FakeFirebaseFirestore();
      final occVM = OccurrenceViewModel(
        repository: OccurrenceRepository(db),
        eventRepository: OccurrenceEventRepository(db),
        signatureRepository: SignatureRepository(firestore: db),
        sendTeamNotifications: false,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ChangeNotifierProvider<OccurrenceViewModel>.value(
              value: occVM,
              child: HistoryOccurrenceBody(detail: detail),
            ),
          ),
        ),
      );
      await tester.pump();

      expect(tester.takeException(), isNull);
      expect(find.text('14:25'), findsOneWidget);
    });

    testWidgets('4. History media timestamp as DateTime => renders safely',
        (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final dartDateTime = DateTime(2026, 9, 1, 16, 45);
      final occ = _createSampleOccurrence(id: 'occ-dt-1');
      final rawEntry = OccurrenceHistoryBuilder.buildEntry(occ);
      final entry = HistoryEntry(
        id: rawEntry.id,
        type: rawEntry.type,
        title: rawEntry.title,
        subtitle: rawEntry.subtitle,
        time: rawEntry.time,
        author: rawEntry.author,
        tag: rawEntry.tag,
        icon: rawEntry.icon,
        color: rawEntry.color,
        originalModel: occ,
        details: {
          ...rawEntry.details,
          '_mediaAttachments': [
            {
              'url': 'https://storage.googleapis.com/test-dt.jpg',
              'timestamp': dartDateTime,
              'category': 'finalizacao',
            },
          ],
        },
      );

      final detail = RecordDetail.fromEntry(entry);

      final db = FakeFirebaseFirestore();
      final occVM = OccurrenceViewModel(
        repository: OccurrenceRepository(db),
        eventRepository: OccurrenceEventRepository(db),
        signatureRepository: SignatureRepository(firestore: db),
        sendTeamNotifications: false,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ChangeNotifierProvider<OccurrenceViewModel>.value(
              value: occVM,
              child: HistoryOccurrenceBody(detail: detail),
            ),
          ),
        ),
      );
      await tester.pump();

      expect(tester.takeException(), isNull);
      expect(find.text('16:45'), findsOneWidget);
    });

    testWidgets('5. History media timestamp null => no crash', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final occ = _createSampleOccurrence(id: 'occ-null-1');
      final rawEntry = OccurrenceHistoryBuilder.buildEntry(occ);
      final entry = HistoryEntry(
        id: rawEntry.id,
        type: rawEntry.type,
        title: rawEntry.title,
        subtitle: rawEntry.subtitle,
        time: rawEntry.time,
        author: rawEntry.author,
        tag: rawEntry.tag,
        icon: rawEntry.icon,
        color: rawEntry.color,
        originalModel: occ,
        details: {
          ...rawEntry.details,
          '_mediaAttachments': [
            {
              'url': 'https://storage.googleapis.com/test-null.jpg',
              'timestamp': null,
              'category': 'finalizacao',
            },
          ],
        },
      );

      final detail = RecordDetail.fromEntry(entry);

      final db = FakeFirebaseFirestore();
      final occVM = OccurrenceViewModel(
        repository: OccurrenceRepository(db),
        eventRepository: OccurrenceEventRepository(db),
        signatureRepository: SignatureRepository(firestore: db),
        sendTeamNotifications: false,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ChangeNotifierProvider<OccurrenceViewModel>.value(
              value: occVM,
              child: HistoryOccurrenceBody(detail: detail),
            ),
          ),
        ),
      );
      await tester.pump();

      expect(tester.takeException(), isNull);
      expect(find.byType(CachedNetworkImage), findsOneWidget);
    });
  });

  group('F40 R8 — Confirmation Fresh PDF Binding', () {
    testWidgets(
        '6. Stale cached occurrence + fresh sealed occurrence => PDF uses fresh finalizationPhotos',
        (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      const occId = 'occ-fresh-binding-001';
      final cachedOcc = _createSampleOccurrence(
        id: occId,
        finalizationPhotos: [], // Stale in-memory cached state: empty photos
      );

      final freshOcc = _createSampleOccurrence(
        id: occId,
        finalizationPhotos: [
          'https://storage.googleapis.com/fresh-finalization-photo.jpg'
        ], // Fresh repository state
      );

      final db = FakeFirebaseFirestore();
      final occVM = _TestOccurrenceViewModel(
        repository: OccurrenceRepository(db),
        eventRepository: OccurrenceEventRepository(db),
        signatureRepository: SignatureRepository(firestore: db),
        freshOccurrence: freshOcc,
        cachedOccurrence: cachedOcc,
      );

      final dog = _createTestDog();
      final dogVM = _TestDogViewModel(dog);
      final authVM = _TestAuthViewModel();

      const confirmationData = OccurrenceConfirmationData(
        occurrenceId: occId,
        typeName: 'Apoio Policial',
        durationLabel: '2h 00m',
        locationAddress: 'Rua das Flores, 500',
        dogName: 'Thor',
        handlerName: 'GCM Ragonha',
        eventCount: 2,
        results: [OccurrenceResult.drugSeized],
        integrityHash: 'hash-abc-123',
      );

      await tester.pumpWidget(
        MaterialApp(
          home: MultiProvider(
            providers: [
              ChangeNotifierProvider<OccurrenceViewModel>.value(value: occVM),
              ChangeNotifierProvider<DogViewModel>.value(value: dogVM),
              ChangeNotifierProvider<AuthViewModel>.value(value: authVM),
            ],
            child: OccurrenceConfirmationScreen(
              data: confirmationData,
              pdfPreviewLauncher: ({required bytes, required name}) async {},
            ),
          ),
        ),
      );
      await tester.pump();

      // Tap 'Gerar PDF'
      expect(find.text('Gerar PDF'), findsOneWidget);
      await tester.ensureVisible(find.text('Gerar PDF'));
      await tester.tap(find.text('Gerar PDF'));
      await tester.pumpAndSettle();

      // Verification: the occurrence captured during generatePdf MUST have the fresh finalizationPhotos
      expect(occVM.capturedOccurrenceForPdf, isNotNull);
      expect(occVM.capturedOccurrenceForPdf!.id, occId);
      expect(
        occVM.capturedOccurrenceForPdf!.finalizationPhotos,
        equals(['https://storage.googleapis.com/fresh-finalization-photo.jpg']),
      );
    });
  });

  group('F40 R8 — PDF Media Accounting and Empty State', () {
    test('7. PDF: 0 event + 1 finalization => total media count 1', () async {
      expect(
        OccurrencePdfGenerator.totalMediaCountForTest(
          eventMediaCount: 0,
          finalizationMediaCount: 1,
        ),
        1,
      );

      final occ = _createSampleOccurrence(
        id: 'occ-pdf-0-1',
        finalizationPhotos: ['https://test.local/final1.jpg'],
      );
      final generator = OccurrencePdfGenerator();
      final bytes = await generator.generate(
        occurrence: occ,
        events: [],
        dog: _createTestDog(),
        handlerName: 'GCM Ragonha',
        handlerRa: '12345',
      );

      expect(bytes, isNotEmpty);
    });

    test('8. PDF: 2 event + 1 finalization => total media count 3', () async {
      expect(
        OccurrencePdfGenerator.totalMediaCountForTest(
          eventMediaCount: 2,
          finalizationMediaCount: 1,
        ),
        3,
      );

      final occ = _createSampleOccurrence(
        id: 'occ-pdf-2-1',
        finalizationPhotos: ['https://test.local/final1.jpg'],
      );
      final event1 = _createSampleEvent('evt-1', ['https://test.local/evt1.jpg']);
      final event2 = _createSampleEvent('evt-2', ['https://test.local/evt2.jpg']);

      final generator = OccurrencePdfGenerator();
      final bytes = await generator.generate(
        occurrence: occ,
        events: [event1, event2],
        dog: _createTestDog(),
        handlerName: 'GCM Ragonha',
        handlerRa: '12345',
      );

      expect(bytes, isNotEmpty);
    });

    test('9. PDF: 0 + 0 => proper empty state', () async {
      expect(
        OccurrencePdfGenerator.isEmptyMediaStateForTest(
          visibleMediaEmpty: true,
          finalizationMediaEmpty: true,
        ),
        isTrue,
      );

      final occ = _createSampleOccurrence(
        id: 'occ-pdf-0-0',
        finalizationPhotos: [],
      );
      final generator = OccurrencePdfGenerator();
      final bytes = await generator.generate(
        occurrence: occ,
        events: [],
        dog: _createTestDog(),
        handlerName: 'GCM Ragonha',
        handlerRa: '12345',
      );

      expect(bytes, isNotEmpty);
    });

    test(
        '10. Finalization media appears in media page when event media is empty',
        () async {
      // Condition: visibleMedia empty, finalizationMedia not empty => isEmptyMediaState must be FALSE
      expect(
        OccurrencePdfGenerator.isEmptyMediaStateForTest(
          visibleMediaEmpty: true,
          finalizationMediaEmpty: false,
        ),
        isFalse,
      );

      final occ = _createSampleOccurrence(
        id: 'occ-pdf-finalization-only',
        finalizationPhotos: [
          'https://test.local/finalization_evidence.jpg',
        ],
      );
      final generator = OccurrencePdfGenerator();
      final bytes = await generator.generate(
        occurrence: occ,
        events: [],
        dog: _createTestDog(),
        handlerName: 'GCM Ragonha',
        handlerRa: '12345',
      );

      expect(bytes, isNotEmpty);
    });

    test(
        '11. Existing active-event media PDF behavior remains unchanged',
        () async {
      // Condition: event media present, finalization empty => isEmptyMediaState must be FALSE
      expect(
        OccurrencePdfGenerator.isEmptyMediaStateForTest(
          visibleMediaEmpty: false,
          finalizationMediaEmpty: true,
        ),
        isFalse,
      );

      expect(
        OccurrencePdfGenerator.totalMediaCountForTest(
          eventMediaCount: 2,
          finalizationMediaCount: 0,
        ),
        2,
      );

      final occ = _createSampleOccurrence(
        id: 'occ-pdf-events-only',
        finalizationPhotos: [],
      );
      final event1 = _createSampleEvent('evt-1', ['https://test.local/e1.jpg']);
      final event2 = _createSampleEvent('evt-2', ['https://test.local/e2.jpg']);

      final generator = OccurrencePdfGenerator();
      final bytes = await generator.generate(
        occurrence: occ,
        events: [event1, event2],
        dog: _createTestDog(),
        handlerName: 'GCM Ragonha',
        handlerRa: '12345',
      );

      expect(bytes, isNotEmpty);
    });
  });
}
