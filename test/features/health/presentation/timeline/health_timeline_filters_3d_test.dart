import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'package:canil_gcm/features/health/data/coexistence/timeline/memory_timeline_source_reader.dart';
import 'package:canil_gcm/features/health/data/coexistence/timeline/coexistence_health_timeline_source.dart';
import 'package:canil_gcm/features/health/domain/health_v1_enums_ext.dart';
import 'package:canil_gcm/features/health/presentation/timeline/filters/health_timeline_filter_labels.dart';
import 'package:canil_gcm/features/health/presentation/timeline/filters/health_timeline_filter_selection.dart';
import 'package:canil_gcm/features/health/presentation/timeline/filters/health_timeline_filter_session.dart';
import 'package:canil_gcm/features/health/presentation/timeline/filters/health_timeline_period_preset.dart';
import 'package:canil_gcm/features/health/presentation/timeline/health_timeline_controller.dart';
import 'package:canil_gcm/features/health/presentation/timeline/health_timeline_entry_view.dart';
import 'package:canil_gcm/features/health/presentation/timeline/health_timeline_page.dart';
import 'package:canil_gcm/features/health/presentation/timeline/health_timeline_query.dart';
import 'package:canil_gcm/features/health/presentation/timeline/health_timeline_source.dart';
import 'package:canil_gcm/features/health/presentation/timeline/health_timeline_state.dart';

HealthTimelineEntryView _entry({
  required String id,
  required DateTime at,
  HealthTimelineType type = HealthTimelineType.consultation,
}) {
  return HealthTimelineEntryView(
    id: id,
    dogId: 'dog-a',
    type: HealthTimelineTypeView.known(type),
    occurredAt: at,
    recordedAt: at,
    title: 'T',
    status: HealthTimelineEntryStatus.finalised,
  );
}

void main() {
  group('HealthTimelineFilterSelection', () {
    test('badge conta dimensões, não cada tipo', () {
      final s = HealthTimelineFilterSelection(
        types: {
          HealthTimelineType.consultation,
          HealthTimelineType.weight,
          HealthTimelineType.exam,
        },
        period: HealthTimelinePeriod(
          start: DateTime(2026, 1, 1),
          end: DateTime(2026, 1, 31),
        ),
      );
      expect(s.activeFilterCount, 2);
    });

    test('empty types = todos; equality imutável', () {
      final a = HealthTimelineFilterSelection(
        types: {HealthTimelineType.weight},
      );
      final b = HealthTimelineFilterSelection(
        types: {HealthTimelineType.weight},
      );
      expect(a, b);
      expect(a.hasTypes, isTrue);
      expect(HealthTimelineFilterSelection.empty().isEmpty, isTrue);
    });

    test('toQuery preserva dogId/pageSize e sem cursor', () {
      final s = HealthTimelineFilterSelection(
        types: {HealthTimelineType.meal},
        caseId: 'case-1',
      );
      final q = s.toQuery(dogId: 'dog-x', pageSize: 15);
      expect(q.dogId, 'dog-x');
      expect(q.pageSize, 15);
      expect(q.cursor, isNull);
      expect(q.types, {HealthTimelineType.meal});
      expect(q.caseId, 'case-1');
    });
  });

  group('GATE A — Draft não altera query', () {
    test('alterar draft não chama setQuery / não muda activeQuery', () async {
      final source = CoexistenceHealthTimelineSourceFactory.forReaders([
        MemoryTimelineSourceReader(
          sourceKey: 'a',
          items: [_entry(id: 'a:1', at: DateTime.utc(2026, 1, 10))],
        ),
      ]);
      final controller = HealthTimelineController(source: source);
      addTearDown(controller.dispose);
      await controller.setQuery(HealthTimelineQuery(dogId: 'dog-a'));
      final before = controller.activeQuery;

      final session = HealthTimelineFilterSession(
        controller: controller,
        dogId: 'dog-a',
        now: () => DateTime(2026, 6, 15, 12),
      );
      session.openDraft();
      session.toggleDraftType(HealthTimelineType.weight);
      expect(controller.activeQuery, before);
      expect(session.applied.isEmpty, isTrue);
      expect(session.draft.hasTypes, isTrue);
    });
  });

  group('GATE B — Apply reseta cursor', () {
    test('apply atualiza applied e carrega sem cursor', () async {
      final items = [
        for (var i = 0; i < 25; i++)
          _entry(
            id: 'a:$i',
            at: DateTime.utc(2026, 1, 1).add(Duration(hours: i)),
            type: i.isEven
                ? HealthTimelineType.weight
                : HealthTimelineType.consultation,
          ),
      ];
      final source = CoexistenceHealthTimelineSourceFactory.forReaders([
        MemoryTimelineSourceReader(sourceKey: 'a', items: items),
      ]);
      final controller = HealthTimelineController(source: source);
      addTearDown(controller.dispose);
      await controller.setQuery(
        HealthTimelineQuery(dogId: 'dog-a', pageSize: 10),
      );
      await controller.loadMore();
      expect(controller.state, isA<HealthTimelineData>());
      expect(
        (controller.state as HealthTimelineData).items.length,
        greaterThan(10),
      );

      final session = HealthTimelineFilterSession(
        controller: controller,
        dogId: 'dog-a',
        pageSize: 10,
        now: () => DateTime(2026, 6, 15),
      );
      session.openDraft();
      session.setDraftTypes({HealthTimelineType.weight});
      await session.apply();

      final q = controller.activeQuery!;
      expect(q.cursor, isNull);
      expect(q.types, {HealthTimelineType.weight});
      expect(q.dogId, 'dog-a');
      expect(q.pageSize, 10);
      final data = controller.state as HealthTimelineData;
      expect(
        data.items.every((e) => e.type.known == HealthTimelineType.weight),
        isTrue,
      );
    });
  });

  group('GATE C — Clear reseta filtros', () {
    test('clearApplied remove filtros; noop se já vazio', () async {
      final source = CoexistenceHealthTimelineSourceFactory.forReaders([
        MemoryTimelineSourceReader(
          sourceKey: 'a',
          items: [_entry(id: 'a:1', at: DateTime.utc(2026, 1, 1))],
        ),
      ]);
      final controller = HealthTimelineController(source: source);
      addTearDown(controller.dispose);
      final session = HealthTimelineFilterSession(
        controller: controller,
        dogId: 'dog-a',
        now: () => DateTime(2026, 1, 1),
      );
      await session.clearApplied(); // noop
      expect(controller.activeQuery, isNull);

      session.openDraft();
      session.setDraftTypes({HealthTimelineType.exam});
      await session.apply();
      expect(session.hasActiveFilters, isTrue);

      await session.clearApplied();
      expect(session.applied.isEmpty, isTrue);
      expect(controller.activeQuery!.types, isEmpty);
    });
  });

  group('GATE D — Race query A/B', () {
    test('somente B permanece', () async {
      final source = _GatedSource(
        items: [
          _entry(id: 'a:1', at: DateTime.utc(2026, 2, 1)),
          _entry(
            id: 'a:2',
            at: DateTime.utc(2026, 2, 2),
            type: HealthTimelineType.weight,
          ),
        ],
      );
      final controller = HealthTimelineController(source: source);
      addTearDown(controller.dispose);
      final session = HealthTimelineFilterSession(
        controller: controller,
        dogId: 'dog-a',
        now: () => DateTime(2026, 2, 10),
      );

      // A: query sem filtro — bloqueada até liberar.
      final fA = session.apply();
      await source.waitUntilBlocked();

      // B: weight — responde imediatamente.
      source.blockNext = false;
      session.openDraft();
      session.setDraftTypes({HealthTimelineType.weight});
      await session.apply();

      // Libera A (generation antiga) — não pode sobrescrever B.
      source.releaseBlocked();
      await fA;

      expect(controller.activeQuery!.types, {HealthTimelineType.weight});
      final data = controller.state as HealthTimelineData;
      expect(data.items.map((e) => e.id).toSet(), {'a:2'});
    });
  });

  group('GATE E — LoadMore A + filter B', () {
    test('nenhuma mistura de páginas', () async {
      final items = [
        for (var i = 0; i < 30; i++)
          _entry(
            id: 'a:$i',
            at: DateTime.utc(2026, 3, 1).add(Duration(hours: i)),
            type: i < 15
                ? HealthTimelineType.consultation
                : HealthTimelineType.weight,
          ),
      ];
      final source = _GatedSource(items: items);
      final controller = HealthTimelineController(source: source);
      addTearDown(controller.dispose);
      source.blockNext = false;
      await controller.setQuery(
        HealthTimelineQuery(dogId: 'dog-a', pageSize: 10),
      );

      source.blockNext = true;
      final more = controller.loadMore();
      await source.waitUntilBlocked();

      final session = HealthTimelineFilterSession(
        controller: controller,
        dogId: 'dog-a',
        pageSize: 10,
        now: () => DateTime(2026, 3, 20),
      );
      source.blockNext = false;
      session.openDraft();
      session.setDraftTypes({HealthTimelineType.weight});
      await session.apply();
      source.releaseBlocked();
      await more;

      final data = controller.state as HealthTimelineData;
      expect(
        data.items.every((e) => e.type.known == HealthTimelineType.weight),
        isTrue,
      );
      expect(
        data.items.any((e) => e.type.known == HealthTimelineType.consultation),
        isFalse,
      );
    });
  });

  group('GATE F — Empty filtrado', () {
    test('filtros sem match → empty com filtros ativos', () async {
      final source = CoexistenceHealthTimelineSourceFactory.forReaders([
        MemoryTimelineSourceReader(
          sourceKey: 'a',
          items: [
            _entry(
              id: 'a:1',
              at: DateTime.utc(2026, 1, 1),
              type: HealthTimelineType.consultation,
            ),
          ],
        ),
      ]);
      final controller = HealthTimelineController(source: source);
      addTearDown(controller.dispose);
      final session = HealthTimelineFilterSession(
        controller: controller,
        dogId: 'dog-a',
        now: () => DateTime(2026, 1, 1),
      );
      session.openDraft();
      session.setDraftTypes({HealthTimelineType.exam});
      await session.apply();
      expect(controller.state, isA<HealthTimelineEmpty>());
      expect(session.hasActiveFilters, isTrue);
    });
  });

  group('period presets', () {
    final now = DateTime(2026, 6, 15, 14, 30);

    test('7 dias inclusivo termina no fim de hoje', () {
      final p = HealthTimelinePeriodPresets.resolve(
        HealthTimelinePeriodPreset.days7,
        now: now,
      );
      expect(p.start, DateTime(2026, 6, 9));
      expect(p.end!.day, 15);
      expect(p.end!.hour, 23);
    });

    test('todo histórico unbounded', () {
      final p = HealthTimelinePeriodPresets.resolve(
        HealthTimelinePeriodPreset.allHistory,
        now: now,
      );
      expect(p.isUnbounded, isTrue);
    });

    test('custom start > end inválido', () {
      expect(
        HealthTimelinePeriodPresets.validateCustom(
          start: DateTime(2026, 2, 10),
          end: DateTime(2026, 2, 1),
        ),
        isNotNull,
      );
    });

    test('custom start == end permitido', () {
      expect(
        HealthTimelinePeriodPresets.validateCustom(
          start: DateTime(2026, 2, 10),
          end: DateTime(2026, 2, 10),
        ),
        isNull,
      );
      final p = HealthTimelinePeriodPresets.customInclusive(
        start: DateTime(2026, 2, 10),
        end: DateTime(2026, 2, 10),
      );
      expect(p.start!.day, 10);
      expect(p.end!.day, 10);
    });
  });

  group('chips labels', () {
    test('3 tipos → N TIPOS', () {
      final chips = HealthTimelineFilterLabels.chipsFor(
        HealthTimelineFilterSelection(
          types: {
            HealthTimelineType.weight,
            HealthTimelineType.meal,
            HealthTimelineType.exam,
          },
        ),
      );
      expect(chips.single.label, '3 TIPOS');
    });
  });

  group('contextual filters', () {
    test('applyCaseFilter e professional sem seletor de página', () async {
      final source = CoexistenceHealthTimelineSourceFactory.forReaders([
        MemoryTimelineSourceReader(
          sourceKey: 'a',
          items: [_entry(id: 'a:1', at: DateTime.utc(2026, 1, 1))],
        ),
      ]);
      final controller = HealthTimelineController(source: source);
      addTearDown(controller.dispose);
      final session = HealthTimelineFilterSession(
        controller: controller,
        dogId: 'dog-a',
        now: () => DateTime(2026, 1, 1),
      );
      await session.applyCaseFilter('case-9');
      expect(session.applied.caseId, 'case-9');
      expect(session.activeFilterCount, 1);

      await session.applyProfessionalFilter(
        HealthTimelineProfessionalFilter(name: 'Dra. Ana'),
      );
      expect(session.applied.professional?.name, 'Dra. Ana');
      expect(session.activeFilterCount, 2);
    });
  });

  group('draft cancel / reopen', () {
    test('cancel preserva applied; reopen copia applied', () async {
      final source = CoexistenceHealthTimelineSourceFactory.forReaders([
        MemoryTimelineSourceReader(
          sourceKey: 'a',
          items: [_entry(id: 'a:1', at: DateTime.utc(2026, 1, 1))],
        ),
      ]);
      final controller = HealthTimelineController(source: source);
      addTearDown(controller.dispose);
      final session = HealthTimelineFilterSession(
        controller: controller,
        dogId: 'dog-a',
        now: () => DateTime(2026, 1, 1),
      );
      session.openDraft();
      session.setDraftTypes({HealthTimelineType.weight});
      await session.apply();

      session.openDraft();
      session.setDraftTypes({HealthTimelineType.exam});
      session.cancelDraft();
      expect(session.applied.types, {HealthTimelineType.weight});
      expect(session.draft.types, {HealthTimelineType.weight});

      session.openDraft();
      session.clearDraft();
      expect(session.applied.types, {HealthTimelineType.weight});
      expect(session.draft.isEmpty, isTrue);
    });
  });

  group('GATE B2 — Apply same selection no-op', () {
    test('apply idêntico não chama setQuery de novo', () async {
      var loads = 0;
      final inner = CoexistenceHealthTimelineSourceFactory.forReaders([
        MemoryTimelineSourceReader(
          sourceKey: 'a',
          items: [_entry(id: 'a:1', at: DateTime.utc(2026, 1, 1))],
        ),
      ]);
      final source = _CountingSource(inner, onLoad: () => loads++);
      final controller = HealthTimelineController(source: source);
      addTearDown(controller.dispose);
      final session = HealthTimelineFilterSession(
        controller: controller,
        dogId: 'dog-a',
        now: () => DateTime(2026, 1, 1),
      );
      session.openDraft();
      session.setDraftTypes({HealthTimelineType.weight});
      await session.apply();
      final afterFirst = loads;
      expect(afterFirst, greaterThan(0));

      session.openDraft();
      // mesma seleção
      await session.apply();
      expect(loads, afterFirst);
    });
  });

  group('GATE K — custom ≠ preset label', () {
    test('custom com 30 dias de duração → chip PERSONALIZADO', () {
      final now = DateTime(2026, 6, 15, 12);
      final preset30 = HealthTimelinePeriodPresets.resolve(
        HealthTimelinePeriodPreset.days30,
        now: now,
      );
      final customSame = HealthTimelineFilterSelection(
        period: preset30,
        periodOrigin: HealthTimelinePeriodPreset.custom,
      );
      final presetSel = HealthTimelineFilterSelection(
        period: preset30,
        periodOrigin: HealthTimelinePeriodPreset.days30,
      );
      // Query-igual
      expect(customSame.queryEquals(presetSel), isTrue);
      // Label diferente
      final customChip = HealthTimelineFilterLabels.chipsFor(customSame).single;
      final presetChip = HealthTimelineFilterLabels.chipsFor(presetSel).single;
      expect(customChip.label, 'PERSONALIZADO');
      expect(presetChip.label, '30 DIAS');
    });
  });

  group('immutability / set order', () {
    test('Set externo mutado não altera selection', () {
      final mutable = {HealthTimelineType.weight};
      final s = HealthTimelineFilterSelection(types: mutable);
      mutable.add(HealthTimelineType.exam);
      expect(s.types, {HealthTimelineType.weight});
    });

    test('ordem do Set irrelevante para equality/query', () {
      final a = HealthTimelineFilterSelection(
        types: {HealthTimelineType.weight, HealthTimelineType.exam},
      );
      final b = HealthTimelineFilterSelection(
        types: {HealthTimelineType.exam, HealthTimelineType.weight},
      );
      expect(a, b);
      expect(a.queryEquals(b), isTrue);
    });
  });

  group('calendar months / leap', () {
    test('6 meses calendário a partir de 31/ago', () {
      final p = HealthTimelinePeriodPresets.resolve(
        HealthTimelinePeriodPreset.months6,
        now: DateTime(2026, 8, 31, 10),
      );
      // DateTime(2026, 8-6, 31) = DateTime(2026, 2, 31) → 3 mar 2026 no Dart
      expect(p.start!.year, 2026);
      expect(p.start!.month, lessThanOrEqualTo(3));
      expect(p.end!.month, 8);
      expect(p.end!.day, 31);
    });

    test('1 ano em bissexto 29/fev', () {
      final p = HealthTimelinePeriodPresets.resolve(
        HealthTimelinePeriodPreset.year1,
        now: DateTime(2024, 2, 29, 12),
      );
      expect(p.end!.year, 2024);
      expect(p.end!.month, 2);
      expect(p.end!.day, 29);
      // start: DateTime(2024, 2-12, 29) = 2023-02-28 ou 1/mar conforme Dart
      expect(p.start!.year, 2023);
    });
  });

  group('caseId no-op', () {
    test('mesmo caseId não recarrega', () async {
      var loads = 0;
      final source = _CountingSource(
        CoexistenceHealthTimelineSourceFactory.forReaders([
          MemoryTimelineSourceReader(
            sourceKey: 'a',
            items: [_entry(id: 'a:1', at: DateTime.utc(2026, 1, 1))],
          ),
        ]),
        onLoad: () => loads++,
      );
      final controller = HealthTimelineController(source: source);
      addTearDown(controller.dispose);
      final session = HealthTimelineFilterSession(
        controller: controller,
        dogId: 'dog-a',
        now: () => DateTime(2026, 1, 1),
      );
      await session.applyCaseFilter('c1');
      final n = loads;
      await session.applyCaseFilter('c1');
      expect(loads, n);
    });
  });
}

class _CountingSource implements HealthTimelineSource {
  _CountingSource(this._inner, {required this.onLoad});
  final HealthTimelineSource _inner;
  final void Function() onLoad;

  @override
  Future<HealthTimelinePage> loadPage(HealthTimelineQuery query) async {
    onLoad();
    return _inner.loadPage(query);
  }
}

/// Source que pode bloquear a próxima leitura (races determinísticas).
class _GatedSource implements HealthTimelineSource {
  _GatedSource({required List<HealthTimelineEntryView> items})
    : _inner = CoexistenceHealthTimelineSourceFactory.forReaders([
        MemoryTimelineSourceReader(sourceKey: 'a', items: items),
      ]);

  final HealthTimelineSource _inner;
  bool blockNext = true;
  Completer<void>? _gate;
  Completer<void>? _entered;

  Future<void> waitUntilBlocked() async {
    final e = _entered;
    if (e != null) await e.future;
  }

  void releaseBlocked() {
    final g = _gate;
    if (g != null && !g.isCompleted) g.complete();
  }

  @override
  Future<HealthTimelinePage> loadPage(HealthTimelineQuery query) async {
    if (blockNext) {
      _gate = Completer<void>();
      _entered = Completer<void>();
      _entered!.complete();
      await _gate!.future;
    }
    return _inner.loadPage(query);
  }
}
