// F40 R10 — Targeted Automated Verification Suite
// Total Media Aggregation in History Occurrence Detail.
//
// Authoritative Gate: F40.TC1-HISTORY-TOTAL-MEDIA-AGGREGATION-R10-EXEC
//
// Verifies:
// 1. Physical equivalent (mandatory): 1 finalization photo + 2 event photos => 3 total MÍDIAS.
// 2. Exact thumbnail/media count: 3 rendered entries with 2 'evento' and 1 'finalizacao'.
// 3. 0 event + 0 finalization => 0.
// 4. 2 event + 0 finalization => 2.
// 5. 0 event + 1 finalization => 1.
// 6. 2 event + 1 finalization => 3.
// 7. Duplicate URL deduplication: same URL across event and finalization => not double-counted.
// 8. Event with empty photoUrls or empty strings => safely ignored.
// 9. Null or malformed timestamps => no crash.
// 10. Timestamp (Firestore) and DateTime (Dart) compatibility.
// 11. Async enrichment via OccurrenceViewModel.getEvents.

import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:canil_gcm/features/history/presentation/screens/history_detail_screen.dart';
import 'package:canil_gcm/features/history/presentation/screens/history_screen.dart';
import 'package:canil_gcm/features/occurrences/data/occurrence_event_repository.dart';
import 'package:canil_gcm/features/occurrences/data/occurrence_repository.dart';
import 'package:canil_gcm/features/occurrences/data/signature_repository.dart';
import 'package:canil_gcm/features/occurrences/domain/occurrence.dart';
import 'package:canil_gcm/features/occurrences/domain/occurrence_event.dart';
import 'package:canil_gcm/features/occurrences/domain/occurrence_event_category.dart';
import 'package:canil_gcm/features/occurrences/domain/occurrence_status.dart';
import 'package:canil_gcm/features/occurrences/presentation/view_models/occurrence_view_model.dart';

Occurrence _createSampleOccurrence({
  required String id,
  List<String> finalizationPhotos = const [],
  DateTime? finalizedAt,
}) {
  final now = DateTime(2026, 9, 1, 10, 0);
  return Occurrence(
    id: id,
    shiftId: 'shift-stg-01',
    primaryHandlerId: 'handler-01',
    primaryHandlerRa: '12345',
    dogId: 'dog-tc1-001',
    typeCode: 'APOIO',
    typeName: 'Apoio Policial',
    locationAddress: 'Rua das Flores, 500 - Limeira/SP',
    gpsLat: -22.5645,
    gpsLng: -47.4017,
    status: OccurrenceStatus.finalized,
    startedAt: now.subtract(const Duration(hours: 2)),
    finalizedAt: finalizedAt ?? now,
    createdAt: now.subtract(const Duration(hours: 2)),
    updatedAt: now,
    finalReport: 'Relatório de encerramento da ocorrência com mídia.',
    finalizationPhotos: finalizationPhotos,
  );
}

OccurrenceEvent _createSampleEvent({
  required String id,
  required String occurrenceId,
  required String title,
  required List<String> photoUrls,
  DateTime? timestamp,
}) {
  final ts = timestamp ?? DateTime(2026, 9, 1, 8, 45);
  return OccurrenceEvent(
    id: id,
    occurrenceId: occurrenceId,
    timestamp: ts,
    title: title,
    description: 'Registro de campo: $title',
    category: OccurrenceEventCategory.other,
    photoUrls: photoUrls,
    createdAt: ts,
    updatedAt: ts,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('F40 R10 — Pure Aggregation Architecture', () {
    test(
        'Physical equivalent: 1 finalization + 2 events (1 photo each) => 3 total media with sources preserved',
        () {
      final occ = _createSampleOccurrence(
        id: 'occ-phys-01',
        finalizationPhotos: ['https://storage.googleapis.com/k9-ops/fin-01.jpg'],
        finalizedAt: DateTime(2026, 9, 1, 10, 0),
      );

      final eventA = _createSampleEvent(
        id: 'ev-a',
        occurrenceId: occ.id,
        title: 'Varredura Perimetral',
        photoUrls: ['https://storage.googleapis.com/k9-ops/ev-a.jpg'],
        timestamp: DateTime(2026, 9, 1, 8, 30),
      );

      final eventB = _createSampleEvent(
        id: 'ev-b',
        occurrenceId: occ.id,
        title: 'Indicação K9',
        photoUrls: ['https://storage.googleapis.com/k9-ops/ev-b.jpg'],
        timestamp: DateTime(2026, 9, 1, 9, 15),
      );

      final aggregated = OccurrenceHistoryBuilder.aggregateMediaAttachments(
        events: [eventA, eventB],
        occurrence: occ,
      );

      expect(aggregated.length, 3);

      // Event media preserved
      final eventItems =
          aggregated.where((m) => m['category'] == 'evento').toList();
      expect(eventItems.length, 2);
      expect(eventItems[0]['url'], 'https://storage.googleapis.com/k9-ops/ev-a.jpg');
      expect(eventItems[0]['timestamp'], DateTime(2026, 9, 1, 8, 30));
      expect(eventItems[0]['source'], 'evento');
      expect(eventItems[0]['eventId'], 'ev-a');
      expect(eventItems[0]['title'], 'Varredura Perimetral');

      expect(eventItems[1]['url'], 'https://storage.googleapis.com/k9-ops/ev-b.jpg');
      expect(eventItems[1]['timestamp'], DateTime(2026, 9, 1, 9, 15));
      expect(eventItems[1]['source'], 'evento');
      expect(eventItems[1]['eventId'], 'ev-b');
      expect(eventItems[1]['title'], 'Indicação K9');

      // Finalization media preserved
      final finItems =
          aggregated.where((m) => m['category'] == 'finalizacao').toList();
      expect(finItems.length, 1);
      expect(finItems[0]['url'], 'https://storage.googleapis.com/k9-ops/fin-01.jpg');
      expect(finItems[0]['timestamp'], DateTime(2026, 9, 1, 10, 0));
      expect(finItems[0]['source'], 'finalizacao');
    });

    test('0 event + 0 finalization => 0 items', () {
      final occ = _createSampleOccurrence(
        id: 'occ-0-0',
        finalizationPhotos: [],
      );

      final aggregated = OccurrenceHistoryBuilder.aggregateMediaAttachments(
        events: [],
        occurrence: occ,
      );

      expect(aggregated.length, 0);
    });

    test('2 event + 0 finalization => 2 items', () {
      final occ = _createSampleOccurrence(
        id: 'occ-2-0',
        finalizationPhotos: [],
      );
      final ev1 = _createSampleEvent(
        id: 'ev-1',
        occurrenceId: occ.id,
        title: 'Ev 1',
        photoUrls: ['https://storage.googleapis.com/photo1.jpg'],
      );
      final ev2 = _createSampleEvent(
        id: 'ev-2',
        occurrenceId: occ.id,
        title: 'Ev 2',
        photoUrls: ['https://storage.googleapis.com/photo2.jpg'],
      );

      final aggregated = OccurrenceHistoryBuilder.aggregateMediaAttachments(
        events: [ev1, ev2],
        occurrence: occ,
      );

      expect(aggregated.length, 2);
      expect(aggregated.every((m) => m['source'] == 'evento'), isTrue);
    });

    test('0 event + 1 finalization => 1 item', () {
      final occ = _createSampleOccurrence(
        id: 'occ-0-1',
        finalizationPhotos: ['https://storage.googleapis.com/fin.jpg'],
      );

      final aggregated = OccurrenceHistoryBuilder.aggregateMediaAttachments(
        events: [],
        occurrence: occ,
      );

      expect(aggregated.length, 1);
      expect(aggregated.first['source'], 'finalizacao');
    });

    test('2 event + 1 finalization => 3 items', () {
      final occ = _createSampleOccurrence(
        id: 'occ-2-1',
        finalizationPhotos: ['https://storage.googleapis.com/fin.jpg'],
      );
      final ev1 = _createSampleEvent(
        id: 'ev-1',
        occurrenceId: occ.id,
        title: 'Ev 1',
        photoUrls: ['https://storage.googleapis.com/ev1.jpg'],
      );
      final ev2 = _createSampleEvent(
        id: 'ev-2',
        occurrenceId: occ.id,
        title: 'Ev 2',
        photoUrls: ['https://storage.googleapis.com/ev2.jpg'],
      );

      final aggregated = OccurrenceHistoryBuilder.aggregateMediaAttachments(
        events: [ev1, ev2],
        occurrence: occ,
      );

      expect(aggregated.length, 3);
    });

    test('Deduplication: duplicate URL between event and finalization => counted once', () {
      final sharedUrl = 'https://storage.googleapis.com/shared.jpg';
      final occ = _createSampleOccurrence(
        id: 'occ-dup-1',
        finalizationPhotos: [sharedUrl],
      );
      final ev = _createSampleEvent(
        id: 'ev-dup',
        occurrenceId: occ.id,
        title: 'Ev Duplicate',
        photoUrls: [sharedUrl],
      );

      final aggregated = OccurrenceHistoryBuilder.aggregateMediaAttachments(
        events: [ev],
        occurrence: occ,
      );

      expect(aggregated.length, 1);
      expect(aggregated.first['url'], sharedUrl);
    });

    test('Deduplication: duplicate URL across multiple events => counted once', () {
      final sharedUrl = 'https://storage.googleapis.com/shared-ev.jpg';
      final occ = _createSampleOccurrence(id: 'occ-dup-2');
      final ev1 = _createSampleEvent(
        id: 'ev-d1',
        occurrenceId: occ.id,
        title: 'Ev 1',
        photoUrls: [sharedUrl],
      );
      final ev2 = _createSampleEvent(
        id: 'ev-d2',
        occurrenceId: occ.id,
        title: 'Ev 2',
        photoUrls: [sharedUrl],
      );

      final aggregated = OccurrenceHistoryBuilder.aggregateMediaAttachments(
        events: [ev1, ev2],
        occurrence: occ,
      );

      expect(aggregated.length, 1);
    });

    test('Event with empty photoUrls or blank strings is ignored safely', () {
      final occ = _createSampleOccurrence(id: 'occ-empty-urls');
      final ev1 = _createSampleEvent(
        id: 'ev-e1',
        occurrenceId: occ.id,
        title: 'Ev Empty List',
        photoUrls: [],
      );
      final ev2 = _createSampleEvent(
        id: 'ev-e2',
        occurrenceId: occ.id,
        title: 'Ev Blank Strings',
        photoUrls: ['', '   '],
      );

      final aggregated = OccurrenceHistoryBuilder.aggregateMediaAttachments(
        events: [ev1, ev2],
        occurrence: occ,
      );

      expect(aggregated.length, 0);
    });

    test('enrichDetailWithEvents preserves original detail fields and updates mediaAttachments', () {
      final occ = _createSampleOccurrence(
        id: 'occ-enrich',
        finalizationPhotos: ['https://storage.googleapis.com/fin.jpg'],
      );
      final entry = OccurrenceHistoryBuilder.buildEntry(occ);
      final detail = RecordDetail.fromEntry(entry);

      final event = _createSampleEvent(
        id: 'ev-enrich',
        occurrenceId: occ.id,
        title: 'Ev Enrich',
        photoUrls: ['https://storage.googleapis.com/ev.jpg'],
      );

      final enriched = OccurrenceHistoryBuilder.enrichDetailWithEvents(
        detail,
        [event],
      );

      expect(enriched.id, detail.id);
      expect(enriched.title, detail.title);
      final enrichedMedia =
          enriched.source.details['_mediaAttachments'] as List;
      expect(enrichedMedia.length, 2);
    });
  });

  group('F40 R10 — History Detail Widget Aggregation', () {
    testWidgets(
        'Physical equivalent UI: 2 event photos + 1 finalization photo => MÍDIAS = 3, 3 thumbnails, sources preserved',
        (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final occ = _createSampleOccurrence(
        id: 'occ-pe-ui',
        finalizationPhotos: ['https://storage.googleapis.com/final-pe.jpg'],
        finalizedAt: DateTime(2026, 9, 1, 10, 0),
      );
      final eventA = _createSampleEvent(
        id: 'ev-a-ui',
        occurrenceId: occ.id,
        title: 'Varredura Perimetral',
        photoUrls: ['https://storage.googleapis.com/event-a.jpg'],
        timestamp: DateTime(2026, 9, 1, 8, 30),
      );
      final eventB = _createSampleEvent(
        id: 'ev-b-ui',
        occurrenceId: occ.id,
        title: 'Indicação K9',
        photoUrls: ['https://storage.googleapis.com/event-b.jpg'],
        timestamp: DateTime(2026, 9, 1, 9, 15),
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
              child: HistoryOccurrenceBody(
                detail: detail,
                events: [eventA, eventB],
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      // 1. MÍDIAS stat card must show 3
      final statItem = find.ancestor(
        of: find.text('MÍDIAS'),
        matching: find.byType(Expanded),
      );
      expect(
        find.descendant(of: statItem, matching: find.text('3')),
        findsOneWidget,
      );

      // 2. Exact 3 thumbnail images rendered
      expect(find.byType(CachedNetworkImage), findsNWidgets(3));

      // 3. Formatted timestamps rendered in the horizontal media strip
      final mediaListFinder = find.byWidgetPredicate(
        (w) => w is ListView && w.scrollDirection == Axis.horizontal,
      );
      expect(
        find.descendant(of: mediaListFinder, matching: find.text('08:30')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: mediaListFinder, matching: find.text('09:15')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: mediaListFinder, matching: find.text('10:00')),
        findsOneWidget,
      );
    });

    testWidgets(
        'Async enrichment via OccurrenceViewModel: fetches events and updates MÍDIAS from 1 to 3',
        (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final occ = _createSampleOccurrence(
        id: 'occ-async-01',
        finalizationPhotos: ['https://storage.googleapis.com/final-async.jpg'],
        finalizedAt: DateTime(2026, 9, 1, 10, 0),
      );

      final db = FakeFirebaseFirestore();
      final occRepo = OccurrenceRepository(db);
      final eventRepo = OccurrenceEventRepository(db);

      // Save events in repository
      final eventA = _createSampleEvent(
        id: 'ev-a-repo',
        occurrenceId: occ.id,
        title: 'Ev A',
        photoUrls: ['https://storage.googleapis.com/ev-a.jpg'],
        timestamp: DateTime(2026, 9, 1, 8, 30),
      );
      final eventB = _createSampleEvent(
        id: 'ev-b-repo',
        occurrenceId: occ.id,
        title: 'Ev B',
        photoUrls: ['https://storage.googleapis.com/ev-b.jpg'],
        timestamp: DateTime(2026, 9, 1, 9, 15),
      );
      await db
          .collection('occurrences')
          .doc(occ.id)
          .collection('events')
          .doc(eventA.id)
          .set(eventA.toMap());
      await db
          .collection('occurrences')
          .doc(occ.id)
          .collection('events')
          .doc(eventB.id)
          .set(eventB.toMap());

      final occVM = OccurrenceViewModel(
        repository: occRepo,
        eventRepository: eventRepo,
        signatureRepository: SignatureRepository(firestore: db),
        sendTeamNotifications: false,
      );

      final entry = OccurrenceHistoryBuilder.buildEntry(occ);
      final detail = RecordDetail.fromEntry(entry);

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

      // Before events resolve: initial state shows 1 finalization photo
      final statItem = find.ancestor(
        of: find.text('MÍDIAS'),
        matching: find.byType(Expanded),
      );
      expect(
        find.descendant(of: statItem, matching: find.text('1')),
        findsOneWidget,
      );

      // After events resolve: asynchronously enriches to 3
      await tester.pumpAndSettle();

      expect(
        find.descendant(of: statItem, matching: find.text('3')),
        findsOneWidget,
      );
      expect(find.byType(CachedNetworkImage), findsNWidgets(3));
    });

    testWidgets(
        'Timestamp compatibility: Firestore Timestamp, Dart DateTime, and null render safely',
        (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final occ = _createSampleOccurrence(id: 'occ-ts-compat');
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
              'url': 'https://storage.googleapis.com/item1.jpg',
              'timestamp': Timestamp.fromDate(DateTime(2026, 9, 1, 14, 25)),
              'category': 'finalizacao',
            },
            {
              'url': 'https://storage.googleapis.com/item2.jpg',
              'timestamp': DateTime(2026, 9, 1, 15, 30),
              'category': 'evento',
            },
            {
              'url': 'https://storage.googleapis.com/item3.jpg',
              'timestamp': null,
              'category': 'evento',
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
      expect(find.text('15:30'), findsOneWidget);

      final statItem = find.ancestor(
        of: find.text('MÍDIAS'),
        matching: find.byType(Expanded),
      );
      expect(
        find.descendant(of: statItem, matching: find.text('3')),
        findsOneWidget,
      );
    });
  });
}
