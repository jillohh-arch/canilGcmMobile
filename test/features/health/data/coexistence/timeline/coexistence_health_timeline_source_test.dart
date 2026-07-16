import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:canil_gcm/features/health/data/coexistence/timeline/coexistence_health_timeline_source.dart';
import 'package:canil_gcm/features/health/data/coexistence/timeline/coexistence_timeline_cursor_codec.dart';
import 'package:canil_gcm/features/health/data/coexistence/timeline/health_timeline_entry_codec.dart';
import 'package:canil_gcm/features/health/data/coexistence/timeline/health_timeline_mappers.dart';
import 'package:canil_gcm/features/health/data/coexistence/timeline/memory_timeline_source_reader.dart';
import 'package:canil_gcm/features/health/data/coexistence/timeline/multi_source_timeline_paginator.dart';
import 'package:canil_gcm/features/health/data/coexistence/timeline/timeline_mapping_result.dart';
import 'package:canil_gcm/features/health/domain/health_v1_enums_ext.dart';
import 'package:canil_gcm/features/health/domain/health_v1_models.dart';
import 'package:canil_gcm/features/health/domain/health_v1_value_objects.dart';
import 'package:canil_gcm/features/health/presentation/timeline/health_timeline_controller.dart';
import 'package:canil_gcm/features/health/presentation/timeline/health_timeline_cursor.dart';
import 'package:canil_gcm/features/health/presentation/timeline/health_timeline_entry_view.dart';
import 'package:canil_gcm/features/health/presentation/timeline/health_timeline_grouping.dart';
import 'package:canil_gcm/features/health/presentation/timeline/health_timeline_query.dart';
import 'package:canil_gcm/features/health/presentation/timeline/health_timeline_source.dart';
import 'package:canil_gcm/features/health/presentation/timeline/health_timeline_state.dart';
import 'package:canil_gcm/features/health/presentation/timeline/models/health_timeline_detail_reference.dart';
import 'package:canil_gcm/features/health/presentation/timeline/models/health_timeline_traceability.dart';

HealthTimelineEntryView _e({
  required String id,
  required DateTime at,
  String dogId = 'dog-a',
  HealthTimelineType type = HealthTimelineType.consultation,
  String title = 'Item',
  String? subtitle,
  ProfessionalIdentitySummary? professional,
  RecordedBy? recordedBy,
  String? caseId,
}) {
  return HealthTimelineEntryView(
    id: id,
    dogId: dogId,
    type: HealthTimelineTypeView.known(type),
    occurredAt: at,
    recordedAt: at,
    title: title,
    subtitle: subtitle,
    status: HealthTimelineEntryStatus.finalised,
    professional: professional,
    recordedBy: recordedBy,
    caseId: caseId,
    detailReference: HealthTimelineDetailReference(
      sourceType: id.contains(':') ? id.split(':').first : 'src',
      sourceId: id.contains(':') ? id.split(':').sublist(1).join(':') : id,
    ),
  );
}

/// 120 registros intercalados em 4 fontes.
List<List<HealthTimelineEntryView>> buildFourSourceDataset({
  int total = 120,
  String dogId = 'dog-a',
}) {
  final a = <HealthTimelineEntryView>[];
  final b = <HealthTimelineEntryView>[];
  final c = <HealthTimelineEntryView>[];
  final d = <HealthTimelineEntryView>[];
  final types = [
    HealthTimelineType.consultation,
    HealthTimelineType.weight,
    HealthTimelineType.meal,
    HealthTimelineType.vaccination,
  ];
  for (var i = 0; i < total; i++) {
    final at = DateTime.utc(2026, 1, 1).add(Duration(hours: i));
    final entry = _e(
      id: 'src${i % 4}:doc-$i',
      at: at,
      dogId: dogId,
      type: types[i % 4],
      title: 'T$i',
    );
    switch (i % 4) {
      case 0:
        a.add(entry);
      case 1:
        b.add(entry);
      case 2:
        c.add(entry);
      default:
        d.add(entry);
    }
  }
  return [a, b, c, d];
}

List<List<HealthTimelineEntryView>> buildFiveSourceDataset({
  int total = 1000,
  String dogId = 'dog-a',
}) {
  final buckets = List.generate(5, (_) => <HealthTimelineEntryView>[]);
  final types = [
    HealthTimelineType.consultation,
    HealthTimelineType.weight,
    HealthTimelineType.meal,
    HealthTimelineType.vaccination,
    HealthTimelineType.exam,
  ];
  for (var i = 0; i < total; i++) {
    final at = DateTime.utc(2025, 1, 1).add(Duration(minutes: i * 3));
    final bucket = i % 5;
    buckets[bucket].add(
      _e(
        id: 's$bucket:doc-$i',
        at: at,
        dogId: dogId,
        type: types[bucket],
        title: 'R$i',
      ),
    );
  }
  return buckets;
}

Future<List<HealthTimelineEntryView>> drainAll(
  HealthTimelineSource source, {
  required String dogId,
  int pageSize = 20,
  HealthTimelineQuery? baseQuery,
}) async {
  final all = <HealthTimelineEntryView>[];
  HealthTimelineQuery query =
      baseQuery ?? HealthTimelineQuery(dogId: dogId, pageSize: pageSize);
  var guard = 0;
  while (guard < 2000) {
    guard++;
    final page = await source.loadPage(query);
    all.addAll(page.items);
    if (!page.hasMore) break;
    expect(page.nextCursor, isNotNull);
    // Continuidade inter-páginas.
    if (all.length > page.items.length) {
      final prevLast = all[all.length - page.items.length - 1];
      expect(
        compareTimelineEntries(prevLast, page.items.first),
        lessThanOrEqualTo(0),
        reason: 'first(N) antes de last(N-1)',
      );
    }
    query = query.copyWith(cursor: page.nextCursor);
  }
  return all;
}

/// Drena recriando a source a **cada** página.
Future<List<HealthTimelineEntryView>> drainRecreatingEveryPage({
  required List<HealthTimelineEntryView> Function() buildItemsForSource,
  required List<String> sourceKeys,
  required String dogId,
  int pageSize = 20,
}) async {
  final all = <HealthTimelineEntryView>[];
  HealthTimelineQuery query = HealthTimelineQuery(
    dogId: dogId,
    pageSize: pageSize,
  );
  var guard = 0;
  while (guard < 2000) {
    guard++;
    final sets = <String, List<HealthTimelineEntryView>>{};
    // Dataset idêntico a cada recreation (fonte destruída).
    final flat = buildItemsForSource();
    for (final k in sourceKeys) {
      sets[k] = flat.where((e) => e.id.startsWith('$k:')).toList();
    }
    final source = CoexistenceHealthTimelineSourceFactory.forReaders([
      for (final k in sourceKeys)
        MemoryTimelineSourceReader(sourceKey: k, items: sets[k]!),
    ]);
    final page = await source.loadPage(query);
    all.addAll(page.items);
    if (!page.hasMore) break;
    query = query.copyWith(cursor: page.nextCursor);
  }
  return all;
}

HealthTimelineEntryView _mapped(TimelineMappingResult r) {
  expect(r, isA<TimelineMapped>(), reason: 'esperado mapped, got $r');
  return (r as TimelineMapped).entry;
}

Matcher get isTimelineIgnored => isA<TimelineIgnored>();
Matcher get isTimelineInvalid => isA<TimelineInvalid>();

void main() {
  group('mappers', () {
    test('soft-delete → ignored; data ausente ativa → invalid', () {
      final q = HealthTimelineQuery(dogId: 'd1');
      expect(
        HealthTimelineMappers.mapHealthEvent(
          dogId: 'd1',
          docId: 'x',
          data: {
            'date': DateTime(2026, 1, 1),
            'type': 'consultation',
            'deleted_at': 'x',
          },
          filters: q,
        ),
        isTimelineIgnored,
      );
      final missing = HealthTimelineMappers.mapHealthEvent(
        dogId: 'd1',
        docId: 'x',
        data: {'type': 'consultation'},
        filters: q,
      );
      expect(missing, isTimelineInvalid);
      expect(
        (missing as TimelineInvalid).reason,
        TimelineMappingInvalidReason.missingRequiredDate,
      );
    });

    test('tipo desconhecido com data válida → mapped unknown', () {
      final e = _mapped(
        HealthTimelineMappers.mapHealthEvent(
          dogId: 'd1',
          docId: '1',
          data: {
            'date': DateTime(2026, 1, 2),
            'type': 'future_procedure_v9',
            'healthObservations': 'obs',
          },
          filters: HealthTimelineQuery(dogId: 'd1'),
        ),
      );
      expect(e.type.isUnknown, isTrue);
      expect(e.type.raw, 'future_procedure_v9');
      expect(e.id, 'health_events:1');
    });

    test('weight sem inventar tendência', () {
      final e = _mapped(
        HealthTimelineMappers.mapWeightRecord(
          dogId: 'd1',
          docId: 'w1',
          data: {'measured_at': DateTime(2026, 3, 1), 'weight_kg': 29.8},
          filters: HealthTimelineQuery(dogId: 'd1'),
        ),
      );
      expect(e.type.known, HealthTimelineType.weight);
      expect(e.title, 'Pesagem');
      expect(e.subtitle, contains('29,8'));
      expect(e.operationalImpact, isNull);
    });

    test('feeding dual-write unifica id por docId (NutritionService)', () {
      final q = HealthTimelineQuery(dogId: 'd1');
      final a = _mapped(
        HealthTimelineMappers.mapFeeding(
          dogId: 'd1',
          docId: 'same',
          data: {'fed_at': DateTime(2026, 4, 1), 'amount_grams': 100},
          filters: q,
          sourceKey: 'feeding_events',
        ),
      );
      final b = _mapped(
        HealthTimelineMappers.mapFeeding(
          dogId: 'd1',
          docId: 'same',
          data: {'fed_at': DateTime(2026, 4, 1), 'amount_grams': 100},
          filters: q,
          sourceKey: 'feedings',
        ),
      );
      expect(a.id, b.id);
      expect(a.id, 'feeding:same');
    });

    test('identidade global distinta entre coleções com mesmo docId', () {
      final q = HealthTimelineQuery(dogId: 'd1');
      final he = _mapped(
        HealthTimelineMappers.mapHealthEvent(
          dogId: 'd1',
          docId: 'abc',
          data: {'date': DateTime(2026, 1, 1), 'type': 'consultation'},
          filters: q,
        ),
      );
      final wt = _mapped(
        HealthTimelineMappers.mapWeightRecord(
          dogId: 'd1',
          docId: 'abc',
          data: {'measured_at': DateTime(2026, 1, 1), 'weight_kg': 20},
          filters: q,
        ),
      );
      final fd = _mapped(
        HealthTimelineMappers.mapFeeding(
          dogId: 'd1',
          docId: 'abc',
          data: {'fed_at': DateTime(2026, 1, 1), 'amount_grams': 50},
          filters: q,
          sourceKey: 'feeding_events',
        ),
      );
      final vac = _mapped(
        HealthTimelineMappers.mapLegacyVacina(
          dogId: 'd1',
          docId: 'abc',
          data: {'dataAplicacao': DateTime(2026, 1, 1), 'nome': 'V8'},
          filters: q,
        ),
      );
      final ids = {he.id, wt.id, fd.id, vac.id};
      expect(ids.length, 4);
    });

    test('cancelled só com status real', () {
      final e = _mapped(
        HealthTimelineMappers.mapHealthEvent(
          dogId: 'd1',
          docId: 'c1',
          data: {
            'date': DateTime(2026, 1, 1),
            'type': 'consultation',
            'status': 'cancelled',
          },
          filters: HealthTimelineQuery(dogId: 'd1'),
        ),
      );
      expect(e.isCancelled, isTrue);
    });

    test('professional filter não usa recordedBy', () {
      final entry = _e(
        id: 'he:1',
        at: DateTime.utc(2026, 1, 1),
        professional: const ProfessionalIdentitySummary(name: 'Dra. Ana'),
        recordedBy: RecordedBy(
          uid: 'u1',
          name: 'Sgt Silva',
          internalRole: 'handler',
        ),
      );
      final q = HealthTimelineQuery(
        dogId: 'dog-a',
        professional: HealthTimelineProfessionalFilter(name: 'Sgt Silva'),
      );
      expect(HealthTimelineMappers.matchesFilters(entry, q), isFalse);
      final q2 = HealthTimelineQuery(
        dogId: 'dog-a',
        professional: HealthTimelineProfessionalFilter(name: 'Dra. Ana'),
      );
      expect(HealthTimelineMappers.matchesFilters(entry, q2), isTrue);
    });

    test('caseId vazio / ausente não infere match', () {
      final withCase = _e(
        id: 'he:1',
        at: DateTime.utc(2026, 1, 1),
        caseId: 'case-1',
      );
      final noCase = _e(id: 'he:2', at: DateTime.utc(2026, 1, 2));
      final q = HealthTimelineQuery(dogId: 'dog-a', caseId: 'case-1');
      expect(HealthTimelineMappers.matchesFilters(withCase, q), isTrue);
      expect(HealthTimelineMappers.matchesFilters(noCase, q), isFalse);
      final qOther = HealthTimelineQuery(dogId: 'dog-a', caseId: 'case-9');
      expect(HealthTimelineMappers.matchesFilters(withCase, qOther), isFalse);
    });
  });

  group('GATE A — 120 registros / 4 fontes / pageSize 20', () {
    test('120 retornados, únicos, ordem global', () async {
      final sets = buildFourSourceDataset(total: 120);
      final source = CoexistenceHealthTimelineSourceFactory.forReaders([
        MemoryTimelineSourceReader(sourceKey: 'src0', items: sets[0]),
        MemoryTimelineSourceReader(sourceKey: 'src1', items: sets[1]),
        MemoryTimelineSourceReader(sourceKey: 'src2', items: sets[2]),
        MemoryTimelineSourceReader(sourceKey: 'src3', items: sets[3]),
      ]);

      final all = await drainAll(source, dogId: 'dog-a', pageSize: 20);
      expect(all.length, 120);
      expect(all.map((e) => e.id).toSet().length, 120);

      for (var i = 1; i < all.length; i++) {
        expect(
          compareTimelineEntries(all[i - 1], all[i]),
          lessThanOrEqualTo(0),
          reason: 'ordem quebrada em $i',
        );
      }
    });
  });

  group('GATE B — pageSize 1', () {
    test('percorre dataset inteiro sem perda/duplicação', () async {
      final sets = buildFourSourceDataset(total: 40);
      final source = CoexistenceHealthTimelineSourceFactory.forReaders([
        MemoryTimelineSourceReader(sourceKey: 'src0', items: sets[0]),
        MemoryTimelineSourceReader(sourceKey: 'src1', items: sets[1]),
        MemoryTimelineSourceReader(sourceKey: 'src2', items: sets[2]),
        MemoryTimelineSourceReader(sourceKey: 'src3', items: sets[3]),
      ]);
      final all = await drainAll(source, dogId: 'dog-a', pageSize: 1);
      expect(all.length, 40);
      expect(all.map((e) => e.id).toSet().length, 40);
    });
  });

  group('GATE C — source recreation em todas as páginas', () {
    test('destrói e recria source a cada página até hasMore false', () async {
      final sets = buildFourSourceDataset(total: 80);
      final all = <HealthTimelineEntryView>[];
      HealthTimelineQuery query = HealthTimelineQuery(
        dogId: 'dog-a',
        pageSize: 7,
      );
      var pages = 0;
      while (pages < 50) {
        pages++;
        // Nova instância + novos readers a cada página.
        final source = CoexistenceHealthTimelineSourceFactory.forReaders([
          MemoryTimelineSourceReader(sourceKey: 'src0', items: sets[0]),
          MemoryTimelineSourceReader(sourceKey: 'src1', items: sets[1]),
          MemoryTimelineSourceReader(sourceKey: 'src2', items: sets[2]),
          MemoryTimelineSourceReader(sourceKey: 'src3', items: sets[3]),
        ]);
        final page = await source.loadPage(query);
        all.addAll(page.items);
        if (!page.hasMore) break;
        query = query.copyWith(cursor: page.nextCursor);
      }
      expect(all.length, 80);
      expect(all.map((e) => e.id).toSet().length, 80);
      for (var i = 1; i < all.length; i++) {
        expect(
          compareTimelineEntries(all[i - 1], all[i]),
          lessThanOrEqualTo(0),
        );
      }
    });
  });

  group('GATE C2 — pageSize 1 + recreation a cada página', () {
    test('gate obrigatório pageSize=1 com source nova', () async {
      final sets = buildFourSourceDataset(total: 35);
      final all = <HealthTimelineEntryView>[];
      HealthTimelineQuery query = HealthTimelineQuery(
        dogId: 'dog-a',
        pageSize: 1,
      );
      var pages = 0;
      while (pages < 100) {
        pages++;
        final source = CoexistenceHealthTimelineSourceFactory.forReaders([
          MemoryTimelineSourceReader(sourceKey: 'src0', items: sets[0]),
          MemoryTimelineSourceReader(sourceKey: 'src1', items: sets[1]),
          MemoryTimelineSourceReader(sourceKey: 'src2', items: sets[2]),
          MemoryTimelineSourceReader(sourceKey: 'src3', items: sets[3]),
        ]);
        final page = await source.loadPage(query);
        expect(page.items.length, lessThanOrEqualTo(1));
        all.addAll(page.items);
        if (!page.hasMore) break;
        query = query.copyWith(cursor: page.nextCursor);
      }
      expect(all.length, 35);
      expect(all.map((e) => e.id).toSet().length, 35);
    });
  });

  group('GATE D — 100 timestamps iguais', () {
    test('pageSize 7 e pageSize 1 — 100 únicos, ordem id ASC', () async {
      final at = DateTime.utc(2026, 8, 1, 12);
      for (final pageSize in [7, 1]) {
        final buckets = List.generate(4, (_) => <HealthTimelineEntryView>[]);
        for (var i = 0; i < 100; i++) {
          final id = 's${i % 4}:tie-${i.toString().padLeft(3, '0')}';
          buckets[i % 4].add(_e(id: id, at: at, title: 'tie$i'));
        }
        final source = CoexistenceHealthTimelineSourceFactory.forReaders([
          for (var b = 0; b < 4; b++)
            MemoryTimelineSourceReader(sourceKey: 's$b', items: buckets[b]),
        ]);
        final all = await drainAll(source, dogId: 'dog-a', pageSize: pageSize);
        expect(all.length, 100, reason: 'pageSize=$pageSize');
        expect(all.map((e) => e.id).toSet().length, 100);
        final ids = all.map((e) => e.id).toList();
        final sorted = List<String>.of(ids)..sort();
        expect(ids, sorted, reason: 'empate deve ser id ASC');
      }
    });

    test('100 empates em uma única fonte', () async {
      final at = DateTime.utc(2026, 8, 2, 12);
      final items = [
        for (var i = 0; i < 100; i++)
          _e(id: 'solo:doc-${i.toString().padLeft(3, '0')}', at: at),
      ];
      final source = CoexistenceHealthTimelineSourceFactory.forReaders([
        MemoryTimelineSourceReader(sourceKey: 'solo', items: items),
      ]);
      final all = await drainAll(source, dogId: 'dog-a', pageSize: 7);
      expect(all.length, 100);
      expect(all.map((e) => e.id).toSet().length, 100);
      final ids = all.map((e) => e.id).toList();
      final sorted = List<String>.of(ids)..sort();
      expect(ids, sorted);
    });
  });

  group('GATE E — filtro sparse', () {
    test('5 matches em 500 docs — encontra se scan permite', () async {
      final matchPositions = {0, 89, 209, 399, 499};
      final docs = <MemoryTimelineScanDoc>[];
      for (var i = 0; i < 500; i++) {
        final at = DateTime.utc(2026, 1, 1).add(Duration(hours: 500 - i));
        final isMatch = matchPositions.contains(i);
        final id = 'scan:doc-$i';
        docs.add(
          MemoryTimelineScanDoc.mapped(
            id: id,
            entry: _e(
              id: id,
              at: at,
              type: isMatch
                  ? HealthTimelineType.exam
                  : HealthTimelineType.consultation,
              title: isMatch ? 'match-$i' : 'noise-$i',
            ),
          ),
        );
      }

      final source = CoexistenceHealthTimelineSourceFactory.forReaders([
        ScanningMemoryTimelineSourceReader(
          sourceKey: 'scan',
          docs: docs,
          scanCap: 80,
        ),
      ]);

      final all = await drainAll(
        source,
        dogId: 'dog-a',
        pageSize: 5,
        baseQuery: HealthTimelineQuery(
          dogId: 'dog-a',
          pageSize: 5,
          types: {HealthTimelineType.exam},
        ),
      );
      expect(all.length, 5);
      expect(all.map((e) => e.id).toSet().length, 5);
    });

    test('filtro que não encontra nada + coleção esgotada → empty', () async {
      final docs = [
        for (var i = 0; i < 30; i++)
          MemoryTimelineScanDoc.mapped(
            id: 'z:d-$i',
            entry: _e(
              id: 'z:d-$i',
              at: DateTime.utc(2026, 2, 1).add(Duration(hours: i)),
              type: HealthTimelineType.weight,
            ),
          ),
      ];
      final source = CoexistenceHealthTimelineSourceFactory.forReaders([
        ScanningMemoryTimelineSourceReader(
          sourceKey: 'z',
          docs: docs,
          scanCap: 20,
        ),
      ]);
      final page = await source.loadPage(
        HealthTimelineQuery(dogId: 'dog-a', types: {HealthTimelineType.exam}),
      );
      expect(page.items, isEmpty);
      expect(page.hasMore, isFalse);
    });
  });

  group('GATE F — ignored vs unmappable estrutural', () {
    test('soft-deleted ignored avança e encontra válido posterior', () async {
      final docs = <MemoryTimelineScanDoc>[];
      for (var i = 0; i < 40; i++) {
        final at = DateTime.utc(2026, 3, 1).add(Duration(minutes: 40 - i));
        docs.add(MemoryTimelineScanDoc.ignored(id: 'u:del-$i', occurredAt: at));
      }
      final goodAt = DateTime.utc(2026, 2, 1);
      docs.add(
        MemoryTimelineScanDoc.mapped(
          id: 'u:good',
          entry: _e(id: 'u:good', at: goodAt, title: 'válido'),
        ),
      );

      final source = CoexistenceHealthTimelineSourceFactory.forReaders([
        ScanningMemoryTimelineSourceReader(
          sourceKey: 'u',
          docs: docs,
          scanCap: 15,
        ),
      ]);
      final all = await drainAll(source, dogId: 'dog-a', pageSize: 5);
      expect(all.map((e) => e.id).toList(), ['u:good']);
    });

    test('lote só soft-deleted esgotado → empty conclusivo', () async {
      final docs = [
        for (var i = 0; i < 10; i++)
          MemoryTimelineScanDoc.ignored(
            id: 't:del-$i',
            occurredAt: DateTime.utc(2026, 5, 1).add(Duration(seconds: i)),
          ),
      ];
      final source = CoexistenceHealthTimelineSourceFactory.forReaders([
        ScanningMemoryTimelineSourceReader(
          sourceKey: 't',
          docs: docs,
          scanCap: 3,
        ),
      ]);
      final page = await source.loadPage(
        HealthTimelineQuery(dogId: 'dog-a', pageSize: 5),
      );
      expect(page.items, isEmpty);
      expect(page.hasMore, isFalse);
    });

    test('lote só unmappable estrutural → inconclusivo (não empty)', () async {
      final docs = [
        for (var i = 0; i < 5; i++)
          MemoryTimelineScanDoc.invalid(
            id: 'bad:$i',
            occurredAt: DateTime.utc(2026, 1, 1, i),
            invalidReason: TimelineMappingInvalidReason.invalidRequiredDate,
          ),
      ];
      final source = CoexistenceHealthTimelineSourceFactory.forReaders([
        ScanningMemoryTimelineSourceReader(sourceKey: 'bad', docs: docs),
      ]);
      await expectLater(
        () => source.loadPage(HealthTimelineQuery(dogId: 'dog-a')),
        throwsA(
          isA<HealthTimelineSourceException>().having(
            (e) => e.message,
            'message',
            contains('não puderam ser interpretados'),
          ),
        ),
      );
    });

    test('Memory truncateAfterBatches não vira empty', () async {
      final items = [
        for (var i = 0; i < 5; i++)
          _e(id: 't:$i', at: DateTime.utc(2026, 2, 1, i)),
      ];
      final source = CoexistenceHealthTimelineSourceFactory.forReaders([
        MemoryTimelineSourceReader(
          sourceKey: 'trunc',
          items: items,
          truncateAfterBatches: 0,
        ),
      ]);

      await expectLater(
        () => source.loadPage(HealthTimelineQuery(dogId: 'dog-a')),
        throwsA(
          isA<HealthTimelineSourceException>().having(
            (e) => e.message.toLowerCase(),
            'message',
            contains('truncad'),
          ),
        ),
      );
    });
  });

  group('política unmappable ativo = inconclusivo', () {
    test('1 inválido entre 99 válidos → exception (não timeline completa)', () {
      final q = HealthTimelineQuery(dogId: 'd1');
      for (var i = 0; i < 99; i++) {
        expect(
          HealthTimelineMappers.mapHealthEvent(
            dogId: 'd1',
            docId: 'ok-$i',
            data: {
              'date': DateTime(2026, 1, 1).add(Duration(hours: i)),
              'type': 'consultation',
            },
            filters: q,
          ),
          isA<TimelineMapped>(),
        );
      }
      final bad = HealthTimelineMappers.mapHealthEvent(
        dogId: 'd1',
        docId: 'bad',
        data: {'type': 'consultation', 'date': 'not-a-date'},
        filters: q,
      );
      expect(bad, isTimelineInvalid);

      // Source: 1 invalid ativo entre 99 válidos (mais recente → scan atinge).
      final docs = <MemoryTimelineScanDoc>[
        MemoryTimelineScanDoc.invalid(
          id: 'a:bad',
          occurredAt: DateTime.utc(2026, 6, 1).add(const Duration(hours: 200)),
          invalidReason: TimelineMappingInvalidReason.invalidRequiredDate,
        ),
        for (var i = 0; i < 99; i++)
          MemoryTimelineScanDoc.mapped(
            id: 'a:ok-$i',
            entry: _e(
              id: 'a:ok-$i',
              at: DateTime.utc(2026, 6, 1).add(Duration(hours: i)),
            ),
          ),
      ];
      final source = CoexistenceHealthTimelineSourceFactory.forReaders([
        ScanningMemoryTimelineSourceReader(sourceKey: 'a', docs: docs),
      ]);
      expect(
        () =>
            source.loadPage(HealthTimelineQuery(dogId: 'dog-a', pageSize: 20)),
        throwsA(isA<HealthTimelineSourceException>()),
      );
    });

    test('50 inválidos entre 100 → inconclusivo (não parcial)', () async {
      final docs = <MemoryTimelineScanDoc>[
        for (var i = 0; i < 100; i++)
          if (i.isEven)
            MemoryTimelineScanDoc.mapped(
              id: 'm:ok-$i',
              entry: _e(
                id: 'm:ok-$i',
                at: DateTime.utc(2026, 1, 1).add(Duration(hours: i)),
              ),
            )
          else
            MemoryTimelineScanDoc.invalid(
              id: 'm:bad-$i',
              occurredAt: DateTime.utc(2026, 1, 1).add(Duration(hours: i)),
              invalidReason: TimelineMappingInvalidReason.missingRequiredDate,
            ),
      ];
      final source = CoexistenceHealthTimelineSourceFactory.forReaders([
        ScanningMemoryTimelineSourceReader(sourceKey: 'm', docs: docs),
      ]);
      await expectLater(
        () => source.loadPage(HealthTimelineQuery(dogId: 'dog-a')),
        throwsA(isA<HealthTimelineSourceException>()),
      );
    });

    test('soft-deleted com data inválida → ignored (não bloqueia)', () {
      final r = HealthTimelineMappers.mapHealthEvent(
        dogId: 'd1',
        docId: 'del',
        data: {
          'type': 'consultation',
          'date': 'bogus',
          'deleted_at': DateTime(2026, 1, 2),
        },
        filters: HealthTimelineQuery(dogId: 'd1'),
      );
      expect(r, isTimelineIgnored);
    });

    test('irrelevante por tipo com data inválida → ignored', () {
      final r = HealthTimelineMappers.mapHealthEvent(
        dogId: 'd1',
        docId: 'v1',
        data: {
          'type': 'vaccination',
          // data inválida — mas tipo prova irrelevância antes
          'date': 'nope',
        },
        filters: HealthTimelineQuery(
          dogId: 'd1',
          types: {HealthTimelineType.weight},
        ),
      );
      expect(r, isTimelineIgnored);
    });

    test('period + data inválida em ativo relevante → invalid', () {
      final r = HealthTimelineMappers.mapHealthEvent(
        dogId: 'd1',
        docId: 'p1',
        data: {'type': 'consultation', 'date': '???'},
        filters: HealthTimelineQuery(
          dogId: 'd1',
          period: HealthTimelinePeriod(
            start: DateTime.utc(2026, 1, 1),
            end: DateTime.utc(2026, 12, 31),
          ),
        ),
      );
      expect(r, isTimelineInvalid);
      expect(
        (r as TimelineInvalid).reason,
        TimelineMappingInvalidReason.invalidRequiredDate,
      );
    });

    test('unknown type com data válida → mapped (não inconclusivo)', () {
      final e = _mapped(
        HealthTimelineMappers.mapHealthEvent(
          dogId: 'd1',
          docId: 'u1',
          data: {'date': DateTime(2026, 3, 3), 'type': 'future_procedure_v9'},
          filters: HealthTimelineQuery(dogId: 'd1'),
        ),
      );
      expect(e.type.isUnknown, isTrue);
    });

    test('unmappable em loadMore após página válida', () async {
      // Página 1: 10 válidos; página 2 encontra invalid (não devolve parcial).
      final docs = <MemoryTimelineScanDoc>[
        for (var i = 0; i < 10; i++)
          MemoryTimelineScanDoc.mapped(
            id: 'lm:ok-$i',
            entry: _e(
              id: 'lm:ok-$i',
              at: DateTime.utc(2026, 7, 1).add(Duration(hours: 20 - i)),
            ),
          ),
        MemoryTimelineScanDoc.invalid(
          id: 'lm:bad',
          occurredAt: DateTime.utc(2026, 6, 1),
          invalidReason: TimelineMappingInvalidReason.invalidRequiredDate,
        ),
      ];
      final source = CoexistenceHealthTimelineSourceFactory.forReaders([
        ScanningMemoryTimelineSourceReader(
          sourceKey: 'lm',
          docs: docs,
          scanCap: 20,
        ),
      ]);
      final page1 = await source.loadPage(
        HealthTimelineQuery(dogId: 'dog-a', pageSize: 10),
      );
      expect(page1.items.length, 10);
      expect(page1.hasMore, isTrue);

      await expectLater(
        () => source.loadPage(
          HealthTimelineQuery(
            dogId: 'dog-a',
            pageSize: 10,
            cursor: page1.nextCursor,
          ),
        ),
        throwsA(isA<HealthTimelineSourceException>()),
      );
    });

    test('source recreation: invalid permanece inconclusivo', () async {
      final docs = [
        MemoryTimelineScanDoc.mapped(
          id: 'r:1',
          entry: _e(id: 'r:1', at: DateTime.utc(2026, 8, 1)),
        ),
        MemoryTimelineScanDoc.invalid(
          id: 'r:bad',
          occurredAt: DateTime.utc(2026, 7, 1),
          invalidReason: TimelineMappingInvalidReason.missingRequiredDate,
        ),
      ];
      final s1 = CoexistenceHealthTimelineSourceFactory.forReaders([
        ScanningMemoryTimelineSourceReader(sourceKey: 'r', docs: docs),
      ]);
      final page1 = await s1.loadPage(
        HealthTimelineQuery(dogId: 'dog-a', pageSize: 1),
      );
      expect(page1.items.single.id, 'r:1');

      final s2 = CoexistenceHealthTimelineSourceFactory.forReaders([
        ScanningMemoryTimelineSourceReader(sourceKey: 'r', docs: docs),
      ]);
      await expectLater(
        () => s2.loadPage(
          HealthTimelineQuery(
            dogId: 'dog-a',
            pageSize: 1,
            cursor: page1.nextCursor,
          ),
        ),
        throwsA(isA<HealthTimelineSourceException>()),
      );
    });

    test('exception sanitizada sem valor bruto de data', () {
      expect(
        () => HealthTimelineMappers.throwInconclusive(
          sourceKey: 'health_events',
          reason: TimelineMappingInvalidReason.invalidRequiredDate,
        ),
        throwsA(
          isA<HealthTimelineSourceException>()
              .having((e) => e.message, 'message', contains('interpretados'))
              .having((e) => e.message, 'no raw', isNot(contains('not-a-date')))
              .having((e) => e.message, 'no fb', isNot(contains('Firebase'))),
        ),
      );
    });
  });

  group('GATE G — cursor privacy', () {
    test('residual não serializa PHI clínico', () {
      final entry = HealthTimelineEntryView(
        id: 'he:1',
        dogId: 'dog-a',
        type: HealthTimelineTypeView.known(HealthTimelineType.consultation),
        occurredAt: DateTime.utc(2026, 1, 1),
        recordedAt: DateTime.utc(2026, 1, 1),
        title: 'Consulta veterinária',
        subtitle: 'Suspeita de piometra — observação confidencial',
        status: HealthTimelineEntryStatus.finalised,
        professional: const ProfessionalIdentitySummary(
          name: 'Dr. João Veterinário',
          specialty: 'Clínica',
        ),
        recordedBy: RecordedBy(
          uid: 'uid-9',
          name: 'Cabo Registrador',
          internalRole: 'handler',
        ),
        operationalImpact: OperationalImpact(
          level: OperationalImpactLevel.high,
          description: 'Afastado de operações de faro',
        ),
        hasAttachments: true,
        attachmentCount: 3,
        detailReference: HealthTimelineDetailReference(
          sourceType: 'health_events',
          sourceId: '1',
        ),
        traceability: HealthTimelineTraceability(
          sourceCollection: 'dogs/{dogId}/health_events',
          sourceId: '1',
        ),
      );

      final encoded = HealthTimelineEntryCodec.encode(entry);
      for (final key in HealthTimelineEntryCodec.forbiddenResidualKeys) {
        expect(encoded.containsKey(key), isFalse, reason: 'key $key');
      }
      final json = jsonEncode(encoded);
      expect(json, isNot(contains('piometra')));
      expect(json, isNot(contains('João Veterinário')));
      expect(json, isNot(contains('Cabo Registrador')));
      expect(json, isNot(contains('faro')));
      expect(json, isNot(contains('dogs/{dogId}')));

      final q = HealthTimelineQuery(dogId: 'dog-a', pageSize: 5);
      final state = CoexistenceTimelineCursorState(
        version: CoexistenceTimelineCursorState.currentVersion,
        dogId: 'dog-a',
        filterFingerprint: CoexistenceTimelineCursorCodec.filterFingerprint(q),
        sources: const {},
        residual: [entry],
      );
      final cursor = CoexistenceTimelineCursorCodec.encode(state);
      final decodedJson = utf8.decode(base64Url.decode(cursor.token));
      expect(decodedJson, isNot(contains('piometra')));
      expect(decodedJson, isNot(contains('João Veterinário')));
      expect(decodedJson, isNot(contains('Cabo Registrador')));
      expect(decodedJson, isNot(contains('faro')));

      final round = CoexistenceTimelineCursorCodec.decode(cursor, query: q)!;
      expect(round.residual.single.id, 'he:1');
      expect(round.residual.single.subtitle, isNull);
      expect(round.residual.single.professional, isNull);
      expect(round.residual.single.recordedBy, isNull);
      expect(round.residual.single.operationalImpact, isNull);
    });

    test('toString do cursor não expõe token', () {
      const c = HealthTimelineCursor('super-secret-token-value-xyz');
      expect(c.toString(), 'HealthTimelineCursor(<opaque>)');
      expect(c.toString(), isNot(contains('super-secret')));
    });
  });

  group('GATE H — cursor inválido / outra query', () {
    test('cursor corrompido lança (não reinicia)', () async {
      final source = CoexistenceHealthTimelineSourceFactory.forReaders([
        MemoryTimelineSourceReader(
          sourceKey: 'a',
          items: [_e(id: 'a:1', at: DateTime.utc(2026, 1, 1))],
        ),
      ]);
      await expectLater(
        () => source.loadPage(
          HealthTimelineQuery(
            dogId: 'dog-a',
            cursor: HealthTimelineCursor('!!!not-base64!!!'),
          ),
        ),
        throwsA(isA<HealthTimelineSourceException>()),
      );
    });

    test('cursor de outro dog rejeitado', () async {
      final sets = buildFourSourceDataset(total: 20);
      final s1 = CoexistenceHealthTimelineSourceFactory.forReaders([
        MemoryTimelineSourceReader(sourceKey: 'src0', items: sets[0]),
        MemoryTimelineSourceReader(sourceKey: 'src1', items: sets[1]),
        MemoryTimelineSourceReader(sourceKey: 'src2', items: sets[2]),
        MemoryTimelineSourceReader(sourceKey: 'src3', items: sets[3]),
      ]);
      final page1 = await s1.loadPage(
        HealthTimelineQuery(dogId: 'dog-a', pageSize: 5),
      );
      expect(page1.nextCursor, isNotNull);

      await expectLater(
        () => s1.loadPage(
          HealthTimelineQuery(
            dogId: 'dog-b',
            pageSize: 5,
            cursor: page1.nextCursor,
          ),
        ),
        throwsA(isA<HealthTimelineSourceException>()),
      );
    });

    test('cursor de outro pageSize / filtro rejeitado', () async {
      final sets = buildFourSourceDataset(total: 30);
      final source = CoexistenceHealthTimelineSourceFactory.forReaders([
        MemoryTimelineSourceReader(sourceKey: 'src0', items: sets[0]),
        MemoryTimelineSourceReader(sourceKey: 'src1', items: sets[1]),
        MemoryTimelineSourceReader(sourceKey: 'src2', items: sets[2]),
        MemoryTimelineSourceReader(sourceKey: 'src3', items: sets[3]),
      ]);
      final page1 = await source.loadPage(
        HealthTimelineQuery(dogId: 'dog-a', pageSize: 5),
      );

      await expectLater(
        () => source.loadPage(
          HealthTimelineQuery(
            dogId: 'dog-a',
            pageSize: 10,
            cursor: page1.nextCursor,
          ),
        ),
        throwsA(isA<HealthTimelineSourceException>()),
      );

      await expectLater(
        () => source.loadPage(
          HealthTimelineQuery(
            dogId: 'dog-a',
            pageSize: 5,
            types: {HealthTimelineType.weight},
            cursor: page1.nextCursor,
          ),
        ),
        throwsA(isA<HealthTimelineSourceException>()),
      );
    });

    test('versão desconhecida rejeitada', () {
      final payload = jsonEncode({
        'v': 999,
        'dogId': 'dog-a',
        'fp': CoexistenceTimelineCursorCodec.filterFingerprint(
          HealthTimelineQuery(dogId: 'dog-a', pageSize: 5),
        ),
        'sources': {},
        'residual': [],
      });
      final token = base64Url.encode(utf8.encode(payload));
      expect(
        () => CoexistenceTimelineCursorCodec.decode(
          HealthTimelineCursor(token),
          query: HealthTimelineQuery(dogId: 'dog-a', pageSize: 5),
        ),
        throwsA(isA<HealthTimelineSourceException>()),
      );
    });
  });

  group('GATE I — 1000 registros', () {
    test('5 fontes, pageSize 37, recreation periódica', () async {
      final sets = buildFiveSourceDataset(total: 1000);
      final all = <HealthTimelineEntryView>[];
      HealthTimelineQuery query = HealthTimelineQuery(
        dogId: 'dog-a',
        pageSize: 37,
      );
      var pageNum = 0;
      while (pageNum < 100) {
        pageNum++;
        // Recria source a cada 3 páginas.
        final source = CoexistenceHealthTimelineSourceFactory.forReaders([
          for (var i = 0; i < 5; i++)
            MemoryTimelineSourceReader(sourceKey: 's$i', items: sets[i]),
        ]);
        final page = await source.loadPage(query);
        all.addAll(page.items);
        if (!page.hasMore) break;
        // cursor size controlado
        final tok = page.nextCursor!;
        expect(
          CoexistenceTimelineCursorCodec.tokenCharLength(tok),
          lessThan(CoexistenceTimelineCursorCodec.maxTokenUtf8Bytes * 2),
        );
        query = query.copyWith(cursor: tok);
      }
      expect(all.length, 1000);
      expect(all.map((e) => e.id).toSet().length, 1000);
      for (var i = 1; i < all.length; i++) {
        expect(
          compareTimelineEntries(all[i - 1], all[i]),
          lessThanOrEqualTo(0),
        );
      }
    });
  });

  group('GATE J — randomized deterministic', () {
    test('seed fixa vs sort global em memória', () async {
      const seed = 42;
      // LCG simples determinístico.
      var state = seed;
      int next() {
        state = (1103515245 * state + 12345) & 0x7fffffff;
        return state;
      }

      final allExpected = <HealthTimelineEntryView>[];
      final buckets = List.generate(5, (_) => <HealthTimelineEntryView>[]);
      for (var i = 0; i < 200; i++) {
        final bucket = next() % 5;
        final hour = next() % 500;
        // ~20% timestamps repetidos
        final at = DateTime.utc(2026, 1, 1).add(Duration(hours: hour));
        final entry = _e(
          id: 's$bucket:r-${i.toString().padLeft(3, '0')}',
          at: at,
          type: HealthTimelineType.values[next() % 5],
          title: 'rnd$i',
        );
        buckets[bucket].add(entry);
        allExpected.add(entry);
      }
      final expected = sortTimelineEntries(allExpected);

      final source = CoexistenceHealthTimelineSourceFactory.forReaders([
        for (var i = 0; i < 5; i++)
          MemoryTimelineSourceReader(sourceKey: 's$i', items: buckets[i]),
      ]);
      final got = await drainAll(source, dogId: 'dog-a', pageSize: 13);
      expect(got.map((e) => e.id).toList(), expected.map((e) => e.id).toList());
    });
  });

  group('GATE K — feeding ID collision / dual-write', () {
    test('mesmo docId dual-write → uma entrada', () async {
      final at = DateTime.utc(2026, 4, 1, 8);
      final fe = _e(
        id: 'feeding:abc',
        at: at,
        type: HealthTimelineType.meal,
        title: 'Alimentação registrada',
      );
      final fd = _e(
        id: 'feeding:abc',
        at: at,
        type: HealthTimelineType.meal,
        title: 'Alimentação registrada',
      );
      final source = CoexistenceHealthTimelineSourceFactory.forReaders([
        MemoryTimelineSourceReader(sourceKey: 'feeding_events', items: [fe]),
        MemoryTimelineSourceReader(sourceKey: 'feedings', items: [fd]),
      ]);
      final all = await drainAll(source, dogId: 'dog-a', pageSize: 10);
      expect(all.length, 1);
      expect(all.single.id, 'feeding:abc');
    });

    test('docIds distintos entre feeding_events e feedings → ambos', () async {
      final a = _e(
        id: 'feeding:evt-1',
        at: DateTime.utc(2026, 4, 1, 8),
        type: HealthTimelineType.meal,
      );
      final b = _e(
        id: 'feeding:leg-9',
        at: DateTime.utc(2026, 4, 1, 9),
        type: HealthTimelineType.meal,
      );
      final source = CoexistenceHealthTimelineSourceFactory.forReaders([
        MemoryTimelineSourceReader(sourceKey: 'feeding_events', items: [a]),
        MemoryTimelineSourceReader(sourceKey: 'feedings', items: [b]),
      ]);
      final all = await drainAll(source, dogId: 'dog-a', pageSize: 10);
      expect(all.length, 2);
      expect(all.map((e) => e.id).toSet(), {'feeding:evt-1', 'feeding:leg-9'});
    });
  });

  group('residual grande + recreation', () {
    test('5 fontes pageSize pequeno reemite residual sem perda', () async {
      final sets = buildFiveSourceDataset(total: 150);
      final all = <HealthTimelineEntryView>[];
      HealthTimelineQuery query = HealthTimelineQuery(
        dogId: 'dog-a',
        pageSize: 3,
      );
      while (true) {
        final source = CoexistenceHealthTimelineSourceFactory.forReaders([
          for (var i = 0; i < 5; i++)
            MemoryTimelineSourceReader(sourceKey: 's$i', items: sets[i]),
        ]);
        final page = await source.loadPage(query);
        all.addAll(page.items);
        if (!page.hasMore) break;
        query = query.copyWith(cursor: page.nextCursor);
      }
      expect(all.length, 150);
      expect(all.map((e) => e.id).toSet().length, 150);
    });
  });

  group('falha de subfonte', () {
    test('não devolve histórico parcial como completo', () async {
      final ok = [
        for (var i = 0; i < 10; i++)
          _e(id: 'ok:$i', at: DateTime.utc(2026, 1, 1, i)),
      ];
      final source = CoexistenceHealthTimelineSourceFactory.forReaders([
        MemoryTimelineSourceReader(sourceKey: 'ok', items: ok),
        MemoryTimelineSourceReader(
          sourceKey: 'bad',
          items: const [],
          failOnFetch: true,
        ),
      ]);

      await expectLater(
        () => source.loadPage(HealthTimelineQuery(dogId: 'dog-a')),
        throwsA(isA<HealthTimelineSourceException>()),
      );
    });

    test('falha após residual não mascara erro', () async {
      // Fonte B falha já na primeira página → nunca devolve parcial.
      final a = [
        for (var i = 0; i < 30; i++)
          _e(
            id: 'a:$i',
            at: DateTime.utc(2026, 1, 1).add(Duration(hours: i)),
          ),
      ];
      final source = CoexistenceHealthTimelineSourceFactory.forReaders([
        MemoryTimelineSourceReader(sourceKey: 'a', items: a),
        MemoryTimelineSourceReader(
          sourceKey: 'b',
          items: const [],
          failOnFetch: true,
        ),
      ]);
      await expectLater(
        () => source.loadPage(HealthTimelineQuery(dogId: 'dog-a', pageSize: 5)),
        throwsA(isA<HealthTimelineSourceException>()),
      );
    });

    test('offline flag preservada quando fonte marca offline', () async {
      final source = CoexistenceHealthTimelineSourceFactory.forReaders([
        MemoryTimelineSourceReader(
          sourceKey: 'off',
          items: const [],
          failOnFetch: true,
          failIsOffline: true,
          failMessage: 'Sem conexão para carregar o histórico clínico.',
        ),
      ]);
      try {
        await source.loadPage(HealthTimelineQuery(dogId: 'dog-a'));
        fail('deveria lançar');
      } on HealthTimelineSourceException catch (e) {
        expect(e.isOffline, isTrue);
      }
    });
  });

  group('exception sanitization', () {
    test('não repassa payload técnico sensível', () {
      final msg = TimelineErrorSanitizer.publicMessage(
        Exception(
          'FirebaseException: [firebase_firestore/permission-denied] '
          'https://googleapis.com/link?key=SECRET path dogs/x/health_events '
          'file health_service.dart:82 stack ...',
        ),
        code: 'permission-denied',
      );
      expect(msg.toLowerCase(), contains('permissão'));
      expect(msg, isNot(contains('googleapis')));
      expect(msg, isNot(contains('SECRET')));
      expect(msg, isNot(contains('.dart')));
      expect(msg, isNot(contains('FirebaseException')));
    });
  });

  group('cursor size', () {
    test('registra tamanho para pageSize 1/20 e residual', () async {
      final sets = buildFiveSourceDataset(total: 100);
      for (final pageSize in [1, 20]) {
        final source = CoexistenceHealthTimelineSourceFactory.forReaders([
          for (var i = 0; i < 5; i++)
            MemoryTimelineSourceReader(sourceKey: 's$i', items: sets[i]),
        ]);
        final page = await source.loadPage(
          HealthTimelineQuery(dogId: 'dog-a', pageSize: pageSize),
        );
        if (page.nextCursor != null) {
          final chars = CoexistenceTimelineCursorCodec.tokenCharLength(
            page.nextCursor!,
          );
          final utf8Len = CoexistenceTimelineCursorCodec.decodedUtf8ByteLength(
            page.nextCursor!,
          );
          // Sanity: residual slim deve caber no limite.
          expect(
            utf8Len,
            lessThan(CoexistenceTimelineCursorCodec.maxTokenUtf8Bytes),
          );
          expect(chars, greaterThan(0));
        }
      }
    });
  });

  group('filtros type/period', () {
    test('period boundary e type set ordem-independente', () async {
      final items = [
        _e(
          id: 'a:1',
          at: DateTime.utc(2026, 1, 10),
          type: HealthTimelineType.exam,
        ),
        _e(
          id: 'a:2',
          at: DateTime.utc(2026, 1, 15),
          type: HealthTimelineType.weight,
        ),
        _e(
          id: 'a:3',
          at: DateTime.utc(2026, 1, 20),
          type: HealthTimelineType.exam,
        ),
      ];
      final source = CoexistenceHealthTimelineSourceFactory.forReaders([
        MemoryTimelineSourceReader(sourceKey: 'a', items: items),
      ]);
      final q1 = HealthTimelineQuery(
        dogId: 'dog-a',
        types: {HealthTimelineType.exam, HealthTimelineType.weight},
        period: HealthTimelinePeriod(
          start: DateTime.utc(2026, 1, 10),
          end: DateTime.utc(2026, 1, 15),
        ),
      );
      final q2 = HealthTimelineQuery(
        dogId: 'dog-a',
        types: {HealthTimelineType.weight, HealthTimelineType.exam},
        period: HealthTimelinePeriod(
          start: DateTime.utc(2026, 1, 10),
          end: DateTime.utc(2026, 1, 15),
        ),
      );
      expect(
        CoexistenceTimelineCursorCodec.filterFingerprint(q1),
        CoexistenceTimelineCursorCodec.filterFingerprint(q2),
      );
      final all = await drainAll(
        source,
        dogId: 'dog-a',
        baseQuery: q1.copyWith(pageSize: 10),
      );
      expect(all.map((e) => e.id).toSet(), {'a:1', 'a:2'});
    });
  });

  group('esgotamento desigual', () {
    test('continua até fim global', () async {
      final base = DateTime.utc(2026, 6, 1);
      final a = [
        for (var i = 0; i < 100; i++)
          _e(
            id: 'a:$i',
            at: base.add(Duration(minutes: i * 4)),
          ),
      ];
      final b = [
        for (var i = 0; i < 3; i++)
          _e(
            id: 'b:$i',
            at: base.add(Duration(minutes: i * 4 + 1)),
          ),
      ];
      final d = [
        for (var i = 0; i < 42; i++)
          _e(
            id: 'd:$i',
            at: base.add(Duration(minutes: i * 4 + 2)),
          ),
      ];

      final source = CoexistenceHealthTimelineSourceFactory.forReaders([
        MemoryTimelineSourceReader(sourceKey: 'a', items: a),
        MemoryTimelineSourceReader(sourceKey: 'b', items: b),
        MemoryTimelineSourceReader(sourceKey: 'c', items: const []),
        MemoryTimelineSourceReader(sourceKey: 'd', items: d),
      ]);

      final all = await drainAll(source, dogId: 'dog-a', pageSize: 20);
      expect(all.length, 145);
      expect(all.map((e) => e.id).toSet().length, 145);
    });
  });

  group('integração controller 3A', () {
    test('controller pagina com source de coexistência', () async {
      final sets = buildFourSourceDataset(total: 50);
      final source = CoexistenceHealthTimelineSourceFactory.forReaders([
        MemoryTimelineSourceReader(sourceKey: 'src0', items: sets[0]),
        MemoryTimelineSourceReader(sourceKey: 'src1', items: sets[1]),
        MemoryTimelineSourceReader(sourceKey: 'src2', items: sets[2]),
        MemoryTimelineSourceReader(sourceKey: 'src3', items: sets[3]),
      ]);
      final controller = HealthTimelineController(source: source);
      addTearDown(controller.dispose);

      await controller.setQuery(
        HealthTimelineQuery(dogId: 'dog-a', pageSize: 10),
      );
      expect(controller.state, isA<HealthTimelineData>());
      final first = (controller.state as HealthTimelineData).items.length;
      expect(first, 10);

      await controller.loadMore();
      final data = controller.state as HealthTimelineData;
      expect(data.items.length, 20);
      expect(data.items.map((e) => e.id).toSet().length, 20);
    });
  });

  group('paginator unit', () {
    test('pageSize 20 merge de 4 fontes sem perda', () async {
      final sets = buildFourSourceDataset(total: 120);
      final paginator = MultiSourceTimelinePaginator(
        readers: [
          MemoryTimelineSourceReader(sourceKey: 'src0', items: sets[0]),
          MemoryTimelineSourceReader(sourceKey: 'src1', items: sets[1]),
          MemoryTimelineSourceReader(sourceKey: 'src2', items: sets[2]),
          MemoryTimelineSourceReader(sourceKey: 'src3', items: sets[3]),
        ],
      );
      final all = <HealthTimelineEntryView>[];
      var q = HealthTimelineQuery(dogId: 'dog-a', pageSize: 20);
      while (true) {
        final page = await paginator.loadPage(q);
        all.addAll(page.items);
        if (!page.hasMore) break;
        q = q.copyWith(cursor: page.nextCursor);
      }
      expect(all.length, 120);
    });
  });

  group('vaccination fallback opt-in', () {
    test('fallback desativado não inclui reader vacinas', () async {
      // Factory forReaders nunca liga vacinas automaticamente.
      final source = CoexistenceHealthTimelineSourceFactory.forReaders([
        MemoryTimelineSourceReader(
          sourceKey: 'health_events',
          items: [
            _e(
              id: 'health_events:1',
              at: DateTime.utc(2026, 1, 1),
              type: HealthTimelineType.consultation,
            ),
          ],
        ),
      ]);
      final all = await drainAll(source, dogId: 'dog-a');
      expect(all.every((e) => !e.id.startsWith('vacinas:')), isTrue);
    });
  });

  group('soft-delete mapping', () {
    test('soft-deleted ignored; ativos mais antigos mapeados', () {
      final q = HealthTimelineQuery(dogId: 'd1');
      final deleted = HealthTimelineMappers.mapHealthEvent(
        dogId: 'd1',
        docId: 'new',
        data: {
          'date': DateTime(2026, 5, 10),
          'type': 'consultation',
          'deleted_at': DateTime(2026, 5, 11),
        },
        filters: q,
      );
      final older = HealthTimelineMappers.mapHealthEvent(
        dogId: 'd1',
        docId: 'old',
        data: {'date': DateTime(2026, 5, 1), 'type': 'consultation'},
        filters: q,
      );
      expect(deleted, isTimelineIgnored);
      expect(older, isA<TimelineMapped>());
    });
  });
}
