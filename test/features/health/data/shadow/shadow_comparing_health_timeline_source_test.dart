// Copyright 2024 GCM Health. All rights reserved.
//
// HEALTH TIMELINE SHADOW DECORATOR TESTS — 6 tests.

import 'package:canil_gcm/features/health/data/shadow/health_timeline_shadow_models.dart';
import 'package:canil_gcm/features/health/data/shadow/shadow_comparing_health_timeline_source.dart';
import 'package:canil_gcm/features/health/domain/health_v1_enums_ext.dart';
import 'package:canil_gcm/features/health/presentation/timeline/health_timeline_cursor.dart';
import 'package:canil_gcm/features/health/presentation/timeline/health_timeline_entry_view.dart';
import 'package:canil_gcm/features/health/presentation/timeline/health_timeline_page.dart';
import 'package:canil_gcm/features/health/presentation/timeline/health_timeline_query.dart';
import 'package:canil_gcm/features/health/presentation/timeline/health_timeline_source.dart';
import 'package:flutter_test/flutter_test.dart';

/// Minimal fake entry for testing.
HealthTimelineEntryView _makeEntry({String id = 'entry-1'}) {
  return HealthTimelineEntryView(
    id: id,
    dogId: 'dog-test',
    type: HealthTimelineTypeView.known(HealthTimelineType.meal),
    occurredAt: DateTime(2024, 1, 1),
    recordedAt: DateTime(2024, 1, 1),
    title: 'Test Entry',
    status: HealthTimelineEntryStatus.finalised,
  );
}

/// Fake primary source that tracks call count and respects delay.
class _FakePrimarySource implements HealthTimelineSource {
  _FakePrimarySource({this.delay = Duration.zero});

  final Duration delay;
  int callCount = 0;

  @override
  Future<HealthTimelinePage> loadPage(HealthTimelineQuery query) async {
    callCount++;
    await Future.delayed(delay);
    return HealthTimelinePage(
      items: [_makeEntry(id: 'primary-$callCount')],
      nextCursor: HealthTimelineCursor('cursor-primary-$callCount'),
      hasMore: true,
    );
  }
}

/// Fake shadow source that tracks call count and respects delay/throwing.
class _FakeShadowSource implements HealthTimelineSource {
  _FakeShadowSource({this.delay = Duration.zero, this.shouldThrow = false});

  final Duration delay;
  final bool shouldThrow;
  int callCount = 0;

  @override
  Future<HealthTimelinePage> loadPage(HealthTimelineQuery query) async {
    callCount++;
    await Future.delayed(delay);
    if (shouldThrow) throw Exception('shadow_error');
    return HealthTimelinePage(
      items: [_makeEntry(id: 'shadow-$callCount')],
      nextCursor: null,
      hasMore: false,
    );
  }
}

/// Observer that tracks all invocations.
class _SpyObserver implements HealthTimelineShadowObserver {
  final List<HealthTimelineShadowOutcome> outcomes = [];

  @override
  Object? onComparison(HealthTimelineShadowComparison value) {
    outcomes.add(value);
    return null;
  }

  @override
  Object? onSkipped(HealthTimelineShadowSkipped value) {
    outcomes.add(value);
    return null;
  }

  @override
  Object? onFailure(HealthTimelineShadowFailure value) {
    outcomes.add(value);
    return null;
  }
}

/// Observer that throws synchronously.
class _ThrowingObserver implements HealthTimelineShadowObserver {
  @override
  Object? onComparison(HealthTimelineShadowComparison value) {
    throw Exception('observer_sync_throw');
  }

  @override
  Object? onSkipped(HealthTimelineShadowSkipped value) {
    throw Exception('observer_sync_throw');
  }

  @override
  Object? onFailure(HealthTimelineShadowFailure value) {
    throw Exception('observer_sync_throw');
  }
}

/// Observer that returns a failing Future.
class _AsyncThrowingObserver implements HealthTimelineShadowObserver {
  @override
  Future<void> onComparison(HealthTimelineShadowComparison value) async {
    throw Exception('observer_async_throw');
  }

  @override
  Future<void> onSkipped(HealthTimelineShadowSkipped value) async {
    throw Exception('observer_async_throw');
  }

  @override
  Future<void> onFailure(HealthTimelineShadowFailure value) async {
    throw Exception('observer_async_throw');
  }
}

/// Primary source that throws.
class _PrimaryFailingSource implements HealthTimelineSource {
  @override
  Future<HealthTimelinePage> loadPage(HealthTimelineQuery query) async {
    throw Exception('primary_error');
  }
}

void main() {
  group('ShadowComparingHealthTimelineSource', () {
    test(
      'returns the identical primary page with its cursor and hasMore',
      () async {
        final primary = _FakePrimarySource();
        final shadow = _FakeShadowSource();
        final observer = _SpyObserver();

        final source = ShadowComparingHealthTimelineSource(
          primarySource: primary,
          shadowSource: shadow,
          observer: observer,
          shadowTimeout: const Duration(seconds: 5),
        );

        final page = await source.loadPage(HealthTimelineQuery(dogId: 'dog-1'));

        // Page carries primary's cursor and items
        expect(page.items.length, equals(1));
        expect(page.nextCursor?.token, equals('cursor-primary-1'));
        expect(page.hasMore, isTrue);

        await Future.delayed(const Duration(milliseconds: 100));
        expect(observer.outcomes.length, equals(1));
        expect(observer.outcomes.first, isA<HealthTimelineShadowComparison>());
      },
    );

    test('slow shadow below timeout does not block primary', () async {
      final primary = _FakePrimarySource(
        delay: const Duration(milliseconds: 50),
      );
      final shadow = _FakeShadowSource(
        delay: const Duration(milliseconds: 3000),
      );
      final observer = _SpyObserver();

      final source = ShadowComparingHealthTimelineSource(
        primarySource: primary,
        shadowSource: shadow,
        observer: observer,
        shadowTimeout: const Duration(seconds: 5),
      );

      // Primary is slow (50ms), shadow is 3s but below 5s timeout
      final stopwatch = Stopwatch()..start();
      final page = await source.loadPage(HealthTimelineQuery(dogId: 'dog-1'));
      stopwatch.stop();

      // Should complete in ~50ms (primary time), not 3s (shadow time)
      expect(stopwatch.elapsedMilliseconds, lessThan(500));
      expect(page.items.first.id, equals('primary-1'));
    });

    test(
      'preserves primary failure for caller and observes primaryFailure',
      () async {
        final shadow = _FakeShadowSource(
          delay: const Duration(milliseconds: 50),
        );
        final observer = _SpyObserver();

        final source = ShadowComparingHealthTimelineSource(
          primarySource: _PrimaryFailingSource(),
          shadowSource: shadow,
          observer: observer,
          shadowTimeout: const Duration(seconds: 5),
        );

        // Caller must receive the exception
        expect(
          () => source.loadPage(HealthTimelineQuery(dogId: 'dog-1')),
          throwsException,
        );

        // Observer must receive primaryFailure
        await Future.delayed(const Duration(milliseconds: 200));
        expect(observer.outcomes.length, equals(1));
        expect(
          observer.outcomes.first,
          isA<HealthTimelineShadowFailure>().having(
            (f) => f.failureKind,
            'failureKind',
            HealthTimelineShadowFailureKind.primaryFailure,
          ),
        );
      },
    );

    test(
      'classifies common shadow failure timeout and comparator failure separately',
      () async {
        final observer = _SpyObserver();

        // 1. Shadow throws → shadowFailure
        final shadowThrowing = _FakeShadowSource(shouldThrow: true);
        final source1 = ShadowComparingHealthTimelineSource(
          primarySource: _FakePrimarySource(),
          shadowSource: shadowThrowing,
          observer: observer,
          shadowTimeout: const Duration(seconds: 5),
        );

        await source1.loadPage(HealthTimelineQuery(dogId: 'dog-1'));
        await Future.delayed(const Duration(milliseconds: 100));
        expect(
          observer.outcomes.last,
          isA<HealthTimelineShadowFailure>().having(
            (f) => f.failureKind,
            'failureKind',
            HealthTimelineShadowFailureKind.shadowFailure,
          ),
        );

        observer.outcomes.clear();

        // 2. Shadow times out → shadowTimeout
        final shadowSlow = _FakeShadowSource(
          delay: const Duration(seconds: 10),
        );
        final source2 = ShadowComparingHealthTimelineSource(
          primarySource: _FakePrimarySource(),
          shadowSource: shadowSlow,
          observer: observer,
          shadowTimeout: const Duration(milliseconds: 50),
        );

        await source2.loadPage(HealthTimelineQuery(dogId: 'dog-1'));
        await Future.delayed(const Duration(milliseconds: 200));
        expect(
          observer.outcomes.last,
          isA<HealthTimelineShadowFailure>().having(
            (f) => f.failureKind,
            'failureKind',
            HealthTimelineShadowFailureKind.shadowTimeout,
          ),
        );

        observer.outcomes.clear();

        // 3. Comparator throws → comparatorFailure
        final source3 = ShadowComparingHealthTimelineSource(
          primarySource: _FakePrimarySource(),
          shadowSource: _FakeShadowSource(),
          observer: observer,
          shadowTimeout: const Duration(seconds: 5),
          correlate: ({required primaryItems, required shadowItems}) {
            throw Exception('comparator_boom');
          },
        );

        await source3.loadPage(HealthTimelineQuery(dogId: 'dog-1'));
        await Future.delayed(const Duration(milliseconds: 100));
        expect(
          observer.outcomes.last,
          isA<HealthTimelineShadowFailure>().having(
            (f) => f.failureKind,
            'failureKind',
            HealthTimelineShadowFailureKind.comparatorFailure,
          ),
        );
      },
    );

    test('contains synchronous and asynchronous observer failures', () async {
      // Sync throwing observer — should not crash
      final source1 = ShadowComparingHealthTimelineSource(
        primarySource: _FakePrimarySource(),
        shadowSource: _FakeShadowSource(),
        observer: _ThrowingObserver(),
        shadowTimeout: const Duration(seconds: 5),
      );

      // Must not throw
      final page1 = await source1.loadPage(HealthTimelineQuery(dogId: 'dog-1'));
      expect(page1.items.first.id, equals('primary-1'));

      // Async throwing observer — should not crash
      final source2 = ShadowComparingHealthTimelineSource(
        primarySource: _FakePrimarySource(),
        shadowSource: _FakeShadowSource(),
        observer: _AsyncThrowingObserver(),
        shadowTimeout: const Duration(seconds: 5),
      );

      final page2 = await source2.loadPage(HealthTimelineQuery(dogId: 'dog-1'));
      expect(page2.items.first.id, equals('primary-1'));
    });

    test('skips ineligible query without calling shadow', () async {
      final primary = _FakePrimarySource();
      final shadow = _FakeShadowSource();
      final observer = _SpyObserver();

      final source = ShadowComparingHealthTimelineSource(
        primarySource: primary,
        shadowSource: shadow,
        observer: observer,
        shadowTimeout: const Duration(seconds: 5),
      );

      // Query with cursor = notFirstPage
      await source.loadPage(
        HealthTimelineQuery(
          dogId: 'dog-1',
          cursor: HealthTimelineCursor('some-cursor'),
        ),
      );
      await Future.delayed(const Duration(milliseconds: 50));

      expect(shadow.callCount, equals(0));
      expect(
        observer.outcomes.single,
        isA<HealthTimelineShadowSkipped>().having(
          (s) => s.skipKind,
          'skipKind',
          HealthTimelineShadowSkipKind.notFirstPage,
        ),
      );

      // Query with types = unsupportedTypes
      observer.outcomes.clear();
      await source.loadPage(
        HealthTimelineQuery(dogId: 'dog-1', types: {HealthTimelineType.meal}),
      );
      await Future.delayed(const Duration(milliseconds: 50));

      expect(shadow.callCount, equals(0));
      expect(
        observer.outcomes.single,
        isA<HealthTimelineShadowSkipped>().having(
          (s) => s.skipKind,
          'skipKind',
          HealthTimelineShadowSkipKind.unsupportedTypes,
        ),
      );

      // Query with caseId = unsupportedCaseId
      observer.outcomes.clear();
      await source.loadPage(
        HealthTimelineQuery(dogId: 'dog-1', caseId: 'case-1'),
      );
      await Future.delayed(const Duration(milliseconds: 50));

      expect(shadow.callCount, equals(0));
      expect(
        observer.outcomes.single,
        isA<HealthTimelineShadowSkipped>().having(
          (s) => s.skipKind,
          'skipKind',
          HealthTimelineShadowSkipKind.unsupportedCaseId,
        ),
      );

      // Query with professional = unsupportedProfessional
      observer.outcomes.clear();
      await source.loadPage(
        HealthTimelineQuery(
          dogId: 'dog-1',
          professional: HealthTimelineProfessionalFilter(name: 'Dr. Smith'),
        ),
      );
      await Future.delayed(const Duration(milliseconds: 50));

      expect(shadow.callCount, equals(0));
      expect(
        observer.outcomes.single,
        isA<HealthTimelineShadowSkipped>().having(
          (s) => s.skipKind,
          'skipKind',
          HealthTimelineShadowSkipKind.unsupportedProfessional,
        ),
      );
    });
  });
}
