import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:provider/provider.dart';

import 'package:canil_gcm/core/services/authoritative_time/authoritative_time_gateway.dart';
import 'package:canil_gcm/core/services/authoritative_time/authoritative_time_models.dart';
import 'package:canil_gcm/core/services/authoritative_time/authoritative_time_provider.dart';
import 'package:canil_gcm/core/services/authoritative_time/monotonic_elapsed_clock.dart';
import 'package:canil_gcm/features/app_shell/presentation/screens/main_root_screen.dart';
import 'package:canil_gcm/features/health/data/coexistence/nutrition/coexistence_nutrition_read_source.dart';
import 'package:canil_gcm/features/health/data/coexistence/timeline/coexistence_health_timeline_source.dart';
import 'package:canil_gcm/features/health/data/coexistence/timeline/memory_timeline_source_reader.dart';
import 'package:canil_gcm/features/health/data/config/local_health_timeline_flag_provider.dart';
import 'package:canil_gcm/features/health/presentation/nutrition/health_nutrition_pending_intent_session.dart';
import 'package:canil_gcm/features/health/presentation/screens/health_v1_entry_screen.dart';
import 'package:canil_gcm/features/health/presentation/summary/health_summary_dog_context_view.dart';
import 'package:canil_gcm/features/health/presentation/summary/health_summary_source.dart';
import 'package:canil_gcm/features/health/presentation/summary/health_summary_view_data.dart';
import 'package:canil_gcm/features/shifts/presentation/viewmodels/shift_viewmodel.dart';

final class _MockShiftViewModel extends Mock implements ShiftViewModel {}

final class _CompositionClock implements MonotonicElapsedClock {
  @override
  Duration get elapsed => Duration.zero;
}

final class _CompositionGateway implements AuthoritativeTimeGateway {
  int calls = 0;

  @override
  Future<AuthoritativeTimeRemoteResponse> fetchAuthoritativeTime() async {
    calls++;
    final now = DateTime.utc(2026, 8, 2, 12);
    return AuthoritativeTimeRemoteResponse(
      protocolVersion: 1,
      requestId: '00000000-0000-4000-8000-000000000001',
      requestReceivedAtUtc: now,
      serverSentAtUtc: now,
      maxAge: const Duration(minutes: 15),
    );
  }
}

final class _CompositionSummarySource implements HealthSummarySource {
  int calls = 0;

  @override
  Stream<HealthSummaryViewData?> watchSummary(String dogId) async* {
    calls++;
    yield HealthSummaryViewData(dogId: dogId);
  }
}

void main() {
  setUpAll(() {
    registerFallbackValue('dog-1');
  });

  group('UX-04B3C — MainRoot Real Ownership', () {
    testWidgets(
      'MainRootScreen real mounts and transports identical provider to Health',
      (tester) async {
        final shift = _MockShiftViewModel();
        when(() => shift.hasActiveShift).thenReturn(true);
        when(() => shift.activeDogId).thenReturn('dog-1');

        final gateway = _CompositionGateway();
        final provider = AuthoritativeTimeProvider(
          gateway: gateway,
          monotonicClock: _CompositionClock(),
        );

        await tester.pumpWidget(
          ChangeNotifierProvider<ShiftViewModel>.value(
            value: shift,
            child: MaterialApp(
              home: buildMainRootHealthTabForTesting(
                authoritativeTimeProvider: provider,
                nutritionPendingSession: HealthNutritionPendingIntentSession(),
                timelineFlagProvider: const LocalHealthTimelineFlagProvider(),
                timelineSourceForResolution: (_) =>
                    CoexistenceHealthTimelineSourceFactory.forReaders([
                      MemoryTimelineSourceReader(
                        sourceKey: 'empty',
                        items: const [],
                      ),
                    ]),
                source: _CompositionSummarySource(),
                nutritionReadSource: CoexistenceNutritionReadSource(),
                dogContextOverride: HealthSummaryDogContextView(
                  dogId: 'dog-1',
                  name: 'Bono',
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        final entry = tester.widget<HealthV1EntryScreen>(
          find.byType(HealthV1EntryScreen),
        );
        final state = tester.state<HealthV1EntryScreenState>(
          find.byType(HealthV1EntryScreen),
        );

        // Assertion 1 & 6: identical provider
        expect(entry.authoritativeTimeProvider, same(provider));
        expect(state.authoritativeTimeProviderForTest, same(provider));
        expect(
          state.nutritionReadControllerForTest.authoritativeTimeProviderForTest,
          same(provider),
        );
        expect(gateway.calls, 1);
      },
    );

    testWidgets(
      'Parent rebuild and internal rebuild keep identical provider instance',
      (tester) async {
        final shift = _MockShiftViewModel();
        when(() => shift.hasActiveShift).thenReturn(true);
        when(() => shift.activeDogId).thenReturn('dog-1');

        final gateway = _CompositionGateway();
        final provider = AuthoritativeTimeProvider(
          gateway: gateway,
          monotonicClock: _CompositionClock(),
        );
        final pendingSession = HealthNutritionPendingIntentSession();

        Widget buildTree() => ChangeNotifierProvider<ShiftViewModel>.value(
              value: shift,
              child: MaterialApp(
                home: buildMainRootHealthTabForTesting(
                  authoritativeTimeProvider: provider,
                  nutritionPendingSession: pendingSession,
                  timelineFlagProvider: const LocalHealthTimelineFlagProvider(),
                  timelineSourceForResolution: (_) =>
                      CoexistenceHealthTimelineSourceFactory.forReaders([
                        MemoryTimelineSourceReader(
                          sourceKey: 'empty',
                          items: const [],
                        ),
                      ]),
                  source: _CompositionSummarySource(),
                  nutritionReadSource: CoexistenceNutritionReadSource(),
                  dogContextOverride: HealthSummaryDogContextView(
                    dogId: 'dog-1',
                    name: 'Bono',
                  ),
                ),
              ),
            );

        await tester.pumpWidget(buildTree());
        await tester.pumpAndSettle();

        final stateBefore = tester.state<HealthV1EntryScreenState>(
          find.byType(HealthV1EntryScreen),
        );

        // Parent rebuild
        await tester.pumpWidget(buildTree());
        await tester.pumpAndSettle();

        final stateAfter = tester.state<HealthV1EntryScreenState>(
          find.byType(HealthV1EntryScreen),
        );

        // Assertion 2 & 3: identical state and provider, no extra gateway call
        expect(stateAfter, same(stateBefore));
        expect(stateAfter.authoritativeTimeProviderForTest, same(provider));
        expect(gateway.calls, 1);
      },
    );

    testWidgets(
      'Dog context switch maintains identical provider instance without extra sync',
      (tester) async {
        final shift = _MockShiftViewModel();
        when(() => shift.hasActiveShift).thenReturn(true);
        when(() => shift.activeDogId).thenReturn('dog-1');

        final gateway = _CompositionGateway();
        final provider = AuthoritativeTimeProvider(
          gateway: gateway,
          monotonicClock: _CompositionClock(),
        );
        final pendingSession = HealthNutritionPendingIntentSession();

        await tester.pumpWidget(
          ChangeNotifierProvider<ShiftViewModel>.value(
            value: shift,
            child: MaterialApp(
              home: buildMainRootHealthTabForTesting(
                authoritativeTimeProvider: provider,
                nutritionPendingSession: pendingSession,
                timelineFlagProvider: const LocalHealthTimelineFlagProvider(),
                timelineSourceForResolution: (_) =>
                    CoexistenceHealthTimelineSourceFactory.forReaders([
                      MemoryTimelineSourceReader(
                        sourceKey: 'empty',
                        items: const [],
                      ),
                    ]),
                source: _CompositionSummarySource(),
                nutritionReadSource: CoexistenceNutritionReadSource(),
                dogContextOverride: HealthSummaryDogContextView(
                  dogId: 'dog-1',
                  name: 'Bono',
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(gateway.calls, 1);

        // Switch active dog to dog-2
        when(() => shift.activeDogId).thenReturn('dog-2');
        await tester.pumpWidget(
          ChangeNotifierProvider<ShiftViewModel>.value(
            value: shift,
            child: MaterialApp(
              home: buildMainRootHealthTabForTesting(
                authoritativeTimeProvider: provider,
                nutritionPendingSession: pendingSession,
                timelineFlagProvider: const LocalHealthTimelineFlagProvider(),
                timelineSourceForResolution: (_) =>
                    CoexistenceHealthTimelineSourceFactory.forReaders([
                      MemoryTimelineSourceReader(
                        sourceKey: 'empty',
                        items: const [],
                      ),
                    ]),
                source: _CompositionSummarySource(),
                nutritionReadSource: CoexistenceNutritionReadSource(),
                dogContextOverride: HealthSummaryDogContextView(
                  dogId: 'dog-2',
                  name: 'Thor',
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Assertion 4: identical provider, gateway calls unchanged
        final state = tester.state<HealthV1EntryScreenState>(
          find.byType(HealthV1EntryScreen),
        );
        expect(state.authoritativeTimeProviderForTest, same(provider));
        expect(gateway.calls, 1);
      },
    );

    testWidgets(
      'Unmount and remount creates exactly one new provider instance for new lifecycle',
      (tester) async {
        final shift = _MockShiftViewModel();
        when(() => shift.hasActiveShift).thenReturn(true);
        when(() => shift.activeDogId).thenReturn('dog-1');

        final gateway1 = _CompositionGateway();
        final provider1 = AuthoritativeTimeProvider(
          gateway: gateway1,
          monotonicClock: _CompositionClock(),
        );

        await tester.pumpWidget(
          ChangeNotifierProvider<ShiftViewModel>.value(
            value: shift,
            child: MaterialApp(
              home: buildMainRootHealthTabForTesting(
                authoritativeTimeProvider: provider1,
                nutritionPendingSession: HealthNutritionPendingIntentSession(),
                timelineFlagProvider: const LocalHealthTimelineFlagProvider(),
                timelineSourceForResolution: (_) =>
                    CoexistenceHealthTimelineSourceFactory.forReaders([
                      MemoryTimelineSourceReader(
                        sourceKey: 'empty',
                        items: const [],
                      ),
                    ]),
                source: _CompositionSummarySource(),
                nutritionReadSource: CoexistenceNutritionReadSource(),
                dogContextOverride: HealthSummaryDogContextView(
                  dogId: 'dog-1',
                  name: 'Bono',
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(gateway1.calls, 1);

        // Unmount
        await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
        await tester.pumpAndSettle();

        // Remount with new provider
        final gateway2 = _CompositionGateway();
        final provider2 = AuthoritativeTimeProvider(
          gateway: gateway2,
          monotonicClock: _CompositionClock(),
        );

        await tester.pumpWidget(
          ChangeNotifierProvider<ShiftViewModel>.value(
            value: shift,
            child: MaterialApp(
              home: buildMainRootHealthTabForTesting(
                authoritativeTimeProvider: provider2,
                nutritionPendingSession: HealthNutritionPendingIntentSession(),
                timelineFlagProvider: const LocalHealthTimelineFlagProvider(),
                timelineSourceForResolution: (_) =>
                    CoexistenceHealthTimelineSourceFactory.forReaders([
                      MemoryTimelineSourceReader(
                        sourceKey: 'empty',
                        items: const [],
                      ),
                    ]),
                source: _CompositionSummarySource(),
                nutritionReadSource: CoexistenceNutritionReadSource(),
                dogContextOverride: HealthSummaryDogContextView(
                  dogId: 'dog-1',
                  name: 'Bono',
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Assertion 5: Exactly one new call on provider2, provider1 not called again
        expect(gateway2.calls, 1);
        expect(gateway1.calls, 1);
      },
    );

    testWidgets(
      'Simultaneous requests deduplicate to exactly one gateway call',
      (tester) async {
        final gateway = _CompositionGateway();
        final provider = AuthoritativeTimeProvider(
          gateway: gateway,
          monotonicClock: _CompositionClock(),
        );

        // Assertion 7: Concurrent sync requests deduplicate
        final f1 = provider.synchronize(force: true);
        final f2 = provider.synchronize(force: true);
        final f3 = provider.synchronize(force: true);

        await Future.wait([f1, f2, f3]);
        expect(gateway.calls, 1);
      },
    );

    testWidgets(
      'buildMainRootHealthTabForTesting keeps identical provider transport',
      (tester) async {
        final shift = _MockShiftViewModel();
        when(() => shift.hasActiveShift).thenReturn(true);
        when(() => shift.activeDogId).thenReturn('dog-1');

        final gateway = _CompositionGateway();
        final provider = AuthoritativeTimeProvider(
          gateway: gateway,
          monotonicClock: _CompositionClock(),
        );
        final summarySource = _CompositionSummarySource();

        await tester.pumpWidget(
          ChangeNotifierProvider<ShiftViewModel>.value(
            value: shift,
            child: MaterialApp(
              home: buildMainRootHealthTabForTesting(
                authoritativeTimeProvider: provider,
                nutritionPendingSession: HealthNutritionPendingIntentSession(),
                timelineFlagProvider: const LocalHealthTimelineFlagProvider(),
                timelineSourceForResolution: (_) =>
                    CoexistenceHealthTimelineSourceFactory.forReaders([
                      MemoryTimelineSourceReader(
                        sourceKey: 'empty',
                        items: const [],
                      ),
                    ]),
                source: summarySource,
                nutritionReadSource: CoexistenceNutritionReadSource(),
                dogContextOverride: HealthSummaryDogContextView(
                  dogId: 'dog-1',
                  name: 'Bono',
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        final entry = tester.widget<HealthV1EntryScreen>(
          find.byType(HealthV1EntryScreen),
        );
        final state = tester.state<HealthV1EntryScreenState>(
          find.byType(HealthV1EntryScreen),
        );
        expect(entry.authoritativeTimeProvider, same(provider));
        expect(state.authoritativeTimeProviderForTest, same(provider));
        expect(gateway.calls, 1);
      },
    );
  });
}
