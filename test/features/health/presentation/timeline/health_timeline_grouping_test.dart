import 'package:canil_gcm/features/health/presentation/timeline/health_timeline_grouping.dart';
import 'package:flutter_test/flutter_test.dart';

import 'timeline_test_helpers.dart';

void main() {
  group('groupTimelineByDay', () {
    test('lista vazia', () {
      expect(groupTimelineByDay(const []), isEmpty);
    });

    test('vários itens no mesmo dia', () {
      final items = [
        entry(id: 'b', occurredAt: DateTime(2026, 7, 10, 18)),
        entry(id: 'a', occurredAt: DateTime(2026, 7, 10, 9)),
      ];
      final groups = groupTimelineByDay(items, toLocal: (d) => d);
      expect(groups, hasLength(1));
      expect(groups.first.date, DateTime(2026, 7, 10));
      expect(groups.first.entries.map((e) => e.id), ['b', 'a']);
    });

    test('dias diferentes e ordem dos grupos DESC', () {
      final items = [
        entry(id: 'd10', occurredAt: DateTime(2026, 7, 10, 12)),
        entry(id: 'd09', occurredAt: DateTime(2026, 7, 9, 12)),
        entry(id: 'd11', occurredAt: DateTime(2026, 7, 11, 12)),
      ];
      // Entrada fora de ordem de dia — grupos ainda saem DESC.
      final groups = groupTimelineByDay(items, toLocal: (d) => d);
      expect(groups.map((g) => g.date.day).toList(), [11, 10, 9]);
      expect(groups[0].entries.single.id, 'd11');
      expect(groups[1].entries.single.id, 'd10');
      expect(groups[2].entries.single.id, 'd09');
    });

    test('ordem interna preservada por dia', () {
      final items = sortTimelineEntries([
        entry(id: 'm', occurredAt: DateTime(2026, 7, 10, 8)),
        entry(id: 'n', occurredAt: DateTime(2026, 7, 10, 20)),
        entry(id: 'o', occurredAt: DateTime(2026, 7, 9, 12)),
      ]);
      final groups = groupTimelineByDay(items, toLocal: (d) => d);
      expect(groups, hasLength(2));
      expect(groups.first.entries.map((e) => e.id), ['n', 'm']);
    });

    test('meia-noite pertence ao dia correto', () {
      final midnight = DateTime(2026, 7, 10, 0, 0, 0);
      final justBefore = DateTime(2026, 7, 9, 23, 59, 59);
      final items = [
        entry(id: 'mid', occurredAt: midnight),
        entry(id: 'prev', occurredAt: justBefore),
      ];
      final groups = groupTimelineByDay(items, toLocal: (d) => d);
      expect(groups, hasLength(2));
      expect(groups.first.date, DateTime(2026, 7, 10));
      expect(groups.first.entries.single.id, 'mid');
      expect(groups.last.date, DateTime(2026, 7, 9));
    });

    test('não embute labels Hoje/Ontem', () {
      final groups = groupTimelineByDay([
        entry(id: 'a', occurredAt: DateTime(2026, 7, 10, 12)),
      ], toLocal: (d) => d);
      // Modelo só tem date + entries — sem label de UI.
      expect(groups.single.date, DateTime(2026, 7, 10));
      expect(groups.single.entries, hasLength(1));
    });
  });

  group('ordenação e merge', () {
    test('occurredAt DESC com tie-break por id ASC', () {
      final t = DateTime(2026, 7, 10, 12);
      final sorted = sortTimelineEntries([
        entry(id: 'b', occurredAt: t),
        entry(id: 'a', occurredAt: t),
        entry(id: 'c', occurredAt: t.add(const Duration(hours: 1))),
      ]);
      expect(sorted.map((e) => e.id).toList(), ['c', 'a', 'b']);
    });

    test('dedupe por id: incoming substitui existing', () {
      final t = DateTime(2026, 7, 10, 12);
      final existing = [
        entry(id: 'x', occurredAt: t, title: 'Antigo'),
        entry(id: 'y', occurredAt: t.subtract(const Duration(hours: 1))),
      ];
      final incoming = [
        entry(id: 'x', occurredAt: t, title: 'Novo payload'),
        entry(id: 'z', occurredAt: t.add(const Duration(hours: 2))),
      ];
      final merged = mergeTimelineEntries(
        existing: existing,
        incoming: incoming,
      );
      expect(merged.map((e) => e.id).toList(), ['z', 'x', 'y']);
      expect(merged.firstWhere((e) => e.id == 'x').title, 'Novo payload');
    });
  });
}
