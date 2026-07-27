// Copyright 2024 GCM Health. All rights reserved.
//
// HEALTH TIMELINE SHADOW SAMPLER AND DECORATOR — Pure synthetic foundation.
//
// NO production parity claims. NO production wiring.
//
// Coverage: PROVEN_CORRELATABLE_ORIGINS=0

import 'dart:async';

import 'package:canil_gcm/features/health/presentation/timeline/health_timeline_entry_view.dart';
import 'package:canil_gcm/features/health/presentation/timeline/health_timeline_page.dart';
import 'package:canil_gcm/features/health/presentation/timeline/health_timeline_query.dart';
import 'package:canil_gcm/features/health/presentation/timeline/health_timeline_source.dart';

import 'health_timeline_shadow_comparator.dart';
import 'health_timeline_shadow_models.dart';

/// HealthTimelineShadowSampler.
///
/// Observes primary and shadow in parallel, fire-and-forget.
/// Does NOT return a page. Does NOT throw to caller.
final class HealthTimelineShadowSampler {
  const HealthTimelineShadowSampler({
    required HealthTimelineSource shadowSource,
    required HealthTimelineShadowObserver? observer,
    Duration shadowTimeout = const Duration(seconds: 5),
    HealthTimelineCorrelationResult Function({
          required List<HealthTimelineEntryView> primaryItems,
          required List<HealthTimelineEntryView> shadowItems,
        })
        correlate =
        correlateHealthTimelineEntries,
  }) : _shadowSource = shadowSource,
       _observer = observer,
       _shadowTimeout = shadowTimeout,
       _correlate = correlate;

  final HealthTimelineSource _shadowSource;
  final HealthTimelineShadowObserver? _observer;
  final Duration _shadowTimeout;
  final HealthTimelineCorrelationResult Function({
    required List<HealthTimelineEntryView> primaryItems,
    required List<HealthTimelineEntryView> shadowItems,
  })
  _correlate;

  /// Evaluates eligibility and observes shadow if eligible.
  ///
  /// primaryFuture MUST already be in progress.
  void observe({
    required HealthTimelineQuery query,
    required Future<HealthTimelinePage> primaryFuture,
  }) {
    final skipKind = _evaluateEligibility(query);
    if (skipKind != null) {
      unawaited(
        safelyObserveHealthTimelineShadowOutcome(
          HealthTimelineShadowSkipped(skipKind: skipKind),
          _observer,
        ),
      );
      return;
    }

    unawaited(_observeAsync(query, primaryFuture));
  }

  HealthTimelineShadowSkipKind? _evaluateEligibility(
    HealthTimelineQuery query,
  ) {
    if (query.cursor != null) return HealthTimelineShadowSkipKind.notFirstPage;
    if (query.types.isNotEmpty) {
      return HealthTimelineShadowSkipKind.unsupportedTypes;
    }
    if (query.caseId != null) {
      return HealthTimelineShadowSkipKind.unsupportedCaseId;
    }
    if (query.professional != null) {
      return HealthTimelineShadowSkipKind.unsupportedProfessional;
    }
    return null;
  }

  Future<void> _observeAsync(
    HealthTimelineQuery query,
    Future<HealthTimelinePage> primaryFuture,
  ) async {
    // Capture shadow with its own timing
    final shadowCapture = await _captureShadow(query);

    // Wait for primary to complete (needed to compare)
    HealthTimelinePage? primaryPage;
    try {
      primaryPage = await primaryFuture;
    } catch (_) {
      // Primary failed — shadow already executed but comparison impossible
      await safelyObserveHealthTimelineShadowOutcome(
        HealthTimelineShadowFailure(
          failureKind: HealthTimelineShadowFailureKind.primaryFailure,
          shadowLatencyMs: shadowCapture.elapsedMilliseconds,
        ),
        _observer,
      );
      return;
    }

    switch (shadowCapture) {
      case _ShadowCaptureSuccess(:final page, :final elapsedMilliseconds):
        try {
          final correlation = _correlate(
            primaryItems: primaryPage.items,
            shadowItems: page.items,
          );
          final orderingMismatch = detectHealthTimelineOrderingMismatch(
            matchedPairs: correlation.matchedPairs,
          );
          final outcome = HealthTimelineShadowComparison(
            primaryCount: primaryPage.items.length,
            shadowCount: page.items.length,
            matchedCount: correlation.matchedCount,
            missingCount: correlation.missingCount,
            extraCount: correlation.extraCount,
            uncorrelatedPrimaryCount: correlation.uncorrelatedPrimaryCount,
            uncorrelatedShadowCount: correlation.uncorrelatedShadowCount,
            ambiguousPrimaryCount: correlation.ambiguousPrimaryCount,
            ambiguousShadowCount: correlation.ambiguousShadowCount,
            orderingMismatch: orderingMismatch,
            shadowLatencyMs: elapsedMilliseconds,
          );
          await safelyObserveHealthTimelineShadowOutcome(outcome, _observer);
        } catch (_) {
          await safelyObserveHealthTimelineShadowOutcome(
            HealthTimelineShadowFailure(
              failureKind: HealthTimelineShadowFailureKind.comparatorFailure,
              shadowLatencyMs: elapsedMilliseconds,
            ),
            _observer,
          );
        }

      case _ShadowCaptureTimeout(:final elapsedMilliseconds):
        await safelyObserveHealthTimelineShadowOutcome(
          HealthTimelineShadowFailure(
            failureKind: HealthTimelineShadowFailureKind.shadowTimeout,
            shadowLatencyMs: elapsedMilliseconds,
          ),
          _observer,
        );

      case _ShadowCaptureFailure(:final elapsedMilliseconds):
        await safelyObserveHealthTimelineShadowOutcome(
          HealthTimelineShadowFailure(
            failureKind: HealthTimelineShadowFailureKind.shadowFailure,
            shadowLatencyMs: elapsedMilliseconds,
          ),
          _observer,
        );
    }
  }

  Future<_ShadowCaptureResult> _captureShadow(HealthTimelineQuery query) async {
    final stopwatch = Stopwatch()..start();

    try {
      final page = await _shadowSource.loadPage(query).timeout(_shadowTimeout);
      stopwatch.stop();
      return _ShadowCaptureSuccess(
        page: page,
        elapsedMilliseconds: stopwatch.elapsedMilliseconds,
      );
    } on TimeoutException {
      stopwatch.stop();
      return _ShadowCaptureTimeout(
        elapsedMilliseconds: stopwatch.elapsedMilliseconds,
      );
    } catch (_) {
      stopwatch.stop();
      return _ShadowCaptureFailure(
        elapsedMilliseconds: stopwatch.elapsedMilliseconds,
      );
    }
  }
}

/// Internal shadow capture result — never throws.
sealed class _ShadowCaptureResult {
  const _ShadowCaptureResult({required this.elapsedMilliseconds});
  final int elapsedMilliseconds;
}

final class _ShadowCaptureSuccess extends _ShadowCaptureResult {
  const _ShadowCaptureSuccess({
    required this.page,
    required super.elapsedMilliseconds,
  });

  final HealthTimelinePage page;
}

final class _ShadowCaptureTimeout extends _ShadowCaptureResult {
  const _ShadowCaptureTimeout({required super.elapsedMilliseconds});
}

final class _ShadowCaptureFailure extends _ShadowCaptureResult {
  const _ShadowCaptureFailure({required super.elapsedMilliseconds});
}

/// ShadowComparingHealthTimelineSource.
///
/// Decorator that observes primary and shadow in parallel without affecting
/// the primary result.
final class ShadowComparingHealthTimelineSource
    implements HealthTimelineSource {
  ShadowComparingHealthTimelineSource({
    required HealthTimelineSource primarySource,
    required HealthTimelineSource shadowSource,
    required HealthTimelineShadowObserver? observer,
    Duration shadowTimeout = const Duration(seconds: 5),
    HealthTimelineCorrelationResult Function({
          required List<HealthTimelineEntryView> primaryItems,
          required List<HealthTimelineEntryView> shadowItems,
        })
        correlate =
        correlateHealthTimelineEntries,
  }) : _primarySource = primarySource,
       _sampler = HealthTimelineShadowSampler(
         shadowSource: shadowSource,
         observer: observer,
         shadowTimeout: shadowTimeout,
         correlate: correlate,
       );

  final HealthTimelineSource _primarySource;
  final HealthTimelineShadowSampler _sampler;

  @override
  Future<HealthTimelinePage> loadPage(HealthTimelineQuery query) {
    // 1. Primary starts immediately — exactly once
    final primaryFuture = Future.sync(() => _primarySource.loadPage(query));

    // 2. Sampler observes in fire-and-forget
    _sampler.observe(query: query, primaryFuture: primaryFuture);

    // 3. Return exactly primaryFuture
    return primaryFuture;
  }
}
