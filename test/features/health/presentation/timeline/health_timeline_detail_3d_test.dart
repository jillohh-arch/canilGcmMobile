import 'package:flutter_test/flutter_test.dart';

import 'package:canil_gcm/features/health/domain/health_v1_enums_ext.dart';
import 'package:canil_gcm/features/health/presentation/timeline/detail/health_timeline_detail_resolution.dart';
import 'package:canil_gcm/features/health/presentation/timeline/detail/health_timeline_detail_resolver.dart';
import 'package:canil_gcm/features/health/presentation/timeline/detail/health_timeline_detail_target.dart';
import 'package:canil_gcm/features/health/presentation/timeline/detail/health_timeline_navigation_coordinator.dart';
import 'package:canil_gcm/features/health/presentation/timeline/health_timeline_entry_view.dart';
import 'package:canil_gcm/features/health/presentation/timeline/models/health_timeline_detail_reference.dart';

HealthTimelineEntryView _entry({
  required String id,
  HealthTimelineDetailReference? detail,
  String dogId = 'dog-a',
  HealthTimelineType type = HealthTimelineType.consultation,
}) {
  return HealthTimelineEntryView(
    id: id,
    dogId: dogId,
    type: HealthTimelineTypeView.known(type),
    occurredAt: DateTime.utc(2026, 1, 1),
    recordedAt: DateTime.utc(2026, 1, 1),
    title: 'T',
    status: HealthTimelineEntryStatus.finalised,
    detailReference: detail,
  );
}

void main() {
  group('GATE G — Resolver allowlist', () {
    test('raw hostil nunca navega', () {
      final r = HealthTimelineDetailResolver.resolve(
        dogId: 'dog-a',
        reference: const HealthTimelineDetailReference(
          sourceType: 'evil_collection',
          sourceId: 'x',
        ),
      );
      expect(r, isA<HealthTimelineDetailUnsupported>());
    });

    test('health_events unsupported (sem detalhe unitário)', () {
      final r = HealthTimelineDetailResolver.resolve(
        dogId: 'dog-a',
        reference: const HealthTimelineDetailReference(
          sourceType: 'health_events',
          sourceId: 'he1',
        ),
      );
      expect(r, isA<HealthTimelineDetailUnsupported>());
      expect(
        HealthTimelineDetailResolver.isNavigable(
          _entry(
            id: 'health_events:he1',
            detail: const HealthTimelineDetailReference(
              sourceType: 'health_events',
              sourceId: 'he1',
            ),
          ),
        ),
        isFalse,
      );
    });

    test('weight_records relatedHistory (não exact detail)', () {
      final r = HealthTimelineDetailResolver.resolve(
        dogId: 'dog-a',
        reference: const HealthTimelineDetailReference(
          sourceType: 'weight_records',
          sourceId: 'w1',
        ),
        entryType: HealthTimelineTypeView.known(HealthTimelineType.weight),
      );
      expect(r, isA<HealthTimelineDetailResolved>());
      final t = (r as HealthTimelineDetailResolved).target;
      expect(t, isA<WeightHistoryTarget>());
      expect(t.kind, HealthTimelineDestinationKind.relatedHistory);
      expect(t.navigationActionLabel, contains('histórico'));
      expect(t.navigationActionLabel.toLowerCase(), isNot(contains('detalhe')));
      expect(t.sourceId, 'w1');
    });

    test('feeding_events e feedings supported', () {
      for (final col in ['feeding_events', 'feedings']) {
        final r = HealthTimelineDetailResolver.resolve(
          dogId: 'dog-a',
          reference: HealthTimelineDetailReference(
            sourceType: col,
            sourceId: 'f1',
          ),
        );
        expect(r, isA<HealthTimelineDetailResolved>());
      }
    });

    test('vacinas supported', () {
      final r = HealthTimelineDetailResolver.resolve(
        dogId: 'dog-a',
        reference: const HealthTimelineDetailReference(
          sourceType: 'vacinas',
          sourceId: 'v1',
        ),
      );
      expect(r, isA<HealthTimelineDetailResolved>());
      expect(
        (r as HealthTimelineDetailResolved).target,
        isA<VaccinationHistoryTarget>(),
      );
    });
  });

  group('GATE G2 — Navigability == resolution', () {
    test('matriz allowlist: isNavigable ⇔ resolved', () {
      final cases = <(HealthTimelineEntryView, bool)>[
        (
          _entry(
            id: 'w:1',
            type: HealthTimelineType.weight,
            detail: const HealthTimelineDetailReference(
              sourceType: 'weight_records',
              sourceId: 'w1',
            ),
          ),
          true,
        ),
        (
          _entry(
            id: 'f:1',
            type: HealthTimelineType.meal,
            detail: const HealthTimelineDetailReference(
              sourceType: 'feeding_events',
              sourceId: 'f1',
            ),
          ),
          true,
        ),
        (
          _entry(
            id: 'v:1',
            type: HealthTimelineType.vaccination,
            detail: const HealthTimelineDetailReference(
              sourceType: 'vacinas',
              sourceId: 'v1',
            ),
          ),
          true,
        ),
        (
          _entry(
            id: 'he:1',
            type: HealthTimelineType.consultation,
            detail: const HealthTimelineDetailReference(
              sourceType: 'health_events',
              sourceId: 'h1',
            ),
          ),
          false,
        ),
        (_entry(id: 'x:1', detail: null), false),
        (
          _entry(
            id: 'evil:1',
            detail: const HealthTimelineDetailReference(
              sourceType: 'https://evil',
              sourceId: 'x',
            ),
          ),
          false,
        ),
        (
          // type×source mismatch
          _entry(
            id: 'm:1',
            type: HealthTimelineType.weight,
            detail: const HealthTimelineDetailReference(
              sourceType: 'vacinas',
              sourceId: 'v9',
            ),
          ),
          false,
        ),
      ];
      for (final (entry, expected) in cases) {
        final resolved =
            HealthTimelineDetailResolver.resolveEntry(entry)
                is HealthTimelineDetailResolved;
        expect(
          HealthTimelineDetailResolver.isNavigable(entry),
          expected,
          reason: entry.id,
        );
        expect(resolved, expected, reason: 'resolver ${entry.id}');
      }
    });
  });

  group('GATE H — Reference incompleta / mismatch', () {
    test('type weight + source vacinas → unavailable', () {
      final r = HealthTimelineDetailResolver.resolveEntry(
        _entry(
          id: 'bad',
          type: HealthTimelineType.weight,
          detail: const HealthTimelineDetailReference(
            sourceType: 'vacinas',
            sourceId: 'v1',
          ),
        ),
      );
      expect(r, isA<HealthTimelineDetailUnavailable>());
      expect(
        (r as HealthTimelineDetailUnavailable).reason,
        HealthTimelineDetailUnavailableReason.typeSourceMismatch,
      );
    });
    test('sourceId vazio / whitespace → unavailable sem crash', () {
      // Construtor da reference 3A rejeita empty via assert em debug;
      // resolver ainda protege trim de dogId e null reference.
      final r = HealthTimelineDetailResolver.resolve(
        dogId: '  ',
        reference: const HealthTimelineDetailReference(
          sourceType: 'weight_records',
          sourceId: 'w1',
        ),
      );
      expect(r, isA<HealthTimelineDetailUnavailable>());

      final missing = HealthTimelineDetailResolver.resolve(
        dogId: 'dog-a',
        reference: null,
      );
      expect(missing, isA<HealthTimelineDetailUnavailable>());
    });
  });

  group('GATE I — Double tap / busy recovery', () {
    test('máximo 1 navegação com future pendente', () async {
      var navCount = 0;
      final coordinator = HealthTimelineNavigationCoordinator(
        onNavigate: (target) async {
          navCount++;
          await Future<void>.delayed(const Duration(milliseconds: 40));
        },
      );
      final entry = _entry(
        id: 'weight_records:w1',
        type: HealthTimelineType.weight,
        detail: const HealthTimelineDetailReference(
          sourceType: 'weight_records',
          sourceId: 'w1',
        ),
      );
      final f1 = coordinator.onEntryTap(entry);
      final f2 = coordinator.onEntryTap(entry);
      await Future.wait([f1, f2]);
      expect(navCount, 1);
      expect(coordinator.isBusy, isFalse);
      await coordinator.onEntryTap(entry);
      expect(navCount, 2);
    });

    test('callback async failure libera busy', () async {
      final coordinator = HealthTimelineNavigationCoordinator(
        onNavigate: (_) async {
          throw StateError('nav failed');
        },
      );
      final entry = _entry(
        id: 'w:1',
        type: HealthTimelineType.weight,
        detail: const HealthTimelineDetailReference(
          sourceType: 'weight_records',
          sourceId: 'w1',
        ),
      );
      await expectLater(
        () => coordinator.onEntryTap(entry),
        throwsA(isA<StateError>()),
      );
      expect(coordinator.isBusy, isFalse);
      var ok = 0;
      final c2 = HealthTimelineNavigationCoordinator(
        onNavigate: (_) async {
          ok++;
        },
      );
      await c2.onEntryTap(entry);
      expect(ok, 1);
    });

    test('unavailable callback throw não prende busy', () async {
      final coordinator = HealthTimelineNavigationCoordinator(
        onNavigate: (_) async {},
        onUnavailable: (_) => throw StateError('ui fail'),
      );
      await coordinator.onEntryTap(_entry(id: 'x:1', detail: null));
      expect(coordinator.isBusy, isFalse);
    });

    test('unsupported → 0 callbacks', () async {
      var nav = 0;
      var unavail = 0;
      final coordinator = HealthTimelineNavigationCoordinator(
        onNavigate: (_) async => nav++,
        onUnavailable: (_) => unavail++,
      );
      await coordinator.onEntryTap(
        _entry(
          id: 'health_events:1',
          detail: const HealthTimelineDetailReference(
            sourceType: 'health_events',
            sourceId: '1',
          ),
        ),
      );
      expect(nav, 0);
      expect(unavail, 0);
      expect(coordinator.isBusy, isFalse);
    });

    test('unavailable → feedback controlado', () async {
      var unavail = 0;
      final coordinator = HealthTimelineNavigationCoordinator(
        onNavigate: (_) async {},
        onUnavailable: (m) {
          expect(m, HealthTimelineNavigationCopy.unavailable);
          expect(m.toLowerCase(), isNot(contains('weight_records')));
          unavail++;
        },
      );
      await coordinator.onEntryTap(_entry(id: 'x:1', detail: null));
      expect(unavail, 1);
    });
  });
}
