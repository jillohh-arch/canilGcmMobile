import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:canil_gcm/features/health/data/coexistence/timeline/coexistence_health_timeline_source.dart';
import 'package:canil_gcm/features/health/data/coexistence/timeline/memory_timeline_source_reader.dart';
import 'package:canil_gcm/features/health/domain/health_schedule_mutation_commands.dart';
import 'package:canil_gcm/features/health/domain/health_schedule_mutation_errors.dart';
import 'package:canil_gcm/features/health/domain/health_schedule_mutation_gateway.dart';
import 'package:canil_gcm/features/health/domain/health_v1_enums_ext.dart';
import 'package:canil_gcm/features/health/presentation/schedule/health_schedule_controller.dart';
import 'package:canil_gcm/features/health/presentation/schedule/health_schedule_page.dart';
import 'package:canil_gcm/features/health/presentation/schedule/health_schedule_query.dart';
import 'package:canil_gcm/features/health/presentation/screens/health_v1_entry_screen.dart';
import 'package:canil_gcm/features/health/presentation/summary/health_summary_dog_context_view.dart';
import 'package:canil_gcm/features/health/presentation/summary/health_summary_source.dart';
import 'package:canil_gcm/features/health/presentation/summary/health_summary_view_data.dart';
import 'package:canil_gcm/features/health/presentation/timeline/health_timeline_source.dart';

import 'fake_health_schedule_source.dart';
import 'schedule_test_helpers.dart';

/// Spy: conta invocações de mutação sem I/O.
final class SpyHealthScheduleMutationGateway
    implements HealthScheduleMutationGateway {
  int createCalls = 0;
  int updateCalls = 0;
  int completeCalls = 0;
  int cancelCalls = 0;

  @override
  Future<HealthScheduleMutationResult> createManual(
    CreateManualScheduleItemCommand command,
  ) async {
    createCalls++;
    return const HealthScheduleMutationErrorResult(
      HealthScheduleMutationWritesNotEnabled(),
    );
  }

  @override
  Future<HealthScheduleMutationResult> updateOpen(
    UpdateOpenScheduleItemCommand command,
  ) async {
    updateCalls++;
    return const HealthScheduleMutationErrorResult(
      HealthScheduleMutationWritesNotEnabled(),
    );
  }

  @override
  Future<HealthScheduleMutationResult> complete(
    CompleteScheduleItemCommand command,
  ) async {
    completeCalls++;
    return const HealthScheduleMutationErrorResult(
      HealthScheduleMutationWritesNotEnabled(),
    );
  }

  @override
  Future<HealthScheduleMutationResult> cancel(
    CancelScheduleItemCommand command,
  ) async {
    cancelCalls++;
    return const HealthScheduleMutationErrorResult(
      HealthScheduleMutationWritesNotEnabled(),
    );
  }

  void expectZero() {
    expect(createCalls, 0);
    expect(updateCalls, 0);
    expect(completeCalls, 0);
    expect(cancelCalls, 0);
  }
}

class _FixedSummarySource implements HealthSummarySource {
  _FixedSummarySource(this.payload);
  final HealthSummaryViewData payload;

  @override
  Stream<HealthSummaryViewData?> watchSummary(String dogId) async* {
    yield payload;
  }
}

HealthTimelineSource _emptyTimeline() {
  return CoexistenceHealthTimelineSourceFactory.forReaders([
    MemoryTimelineSourceReader(sourceKey: 'empty', items: const []),
  ]);
}

HealthSchedulePage _page() {
  return schedulePage([
    scheduleItem(scheduledFor: scheduleTestNow.add(const Duration(days: 2))),
  ]);
}

void main() {
  setUpAll(() {
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  test('controller: abrir/refresh/trocar K9/filtro não muta', () async {
    final spy = SpyHealthScheduleMutationGateway();
    final source = FakeHealthScheduleSource();
    // 5 loads: selectDog, refresh, selectDog B, applyFilters, setQuery
    for (var i = 0; i < 5; i++) {
      source.enqueuePage(_page());
    }

    final controller = HealthScheduleController(
      source: source,
      temporalPolicy: testSchedulePolicy(),
      clock: () => scheduleTestNow,
    );

    await controller.selectDog('dog-a');
    await controller.refresh();
    await controller.selectDog('dog-b');
    await controller.applyFilters(types: {ScheduleType.vaccination});
    await controller.setQuery(
      HealthScheduleQuery(dogId: 'dog-b', pageSize: 10),
    );

    // Controller de leitura não possui gateway; spy só prova contagens.
    spy.expectZero();
    controller.dispose();
  });

  testWidgets('entry: abrir Saúde/Agenda/refresh/filtro não chama mutação', (
    tester,
  ) async {
    final spy = SpyHealthScheduleMutationGateway();
    final scheduleSource = FakeHealthScheduleSource();
    for (var i = 0; i < 4; i++) {
      scheduleSource.enqueuePage(_page());
    }

    final view = tester.view;
    view.physicalSize = const Size(400, 900);
    view.devicePixelRatio = 1.0;
    addTearDown(view.resetPhysicalSize);
    addTearDown(view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: HealthV1EntryScreen(
            dogId: 'dog-a',
            source: _FixedSummarySource(HealthSummaryViewData(dogId: 'dog-a')),
            timelineSource: _emptyTimeline(),
            scheduleSource: scheduleSource,
            scheduleMutationGateway: spy,
            dogContextOverride: HealthSummaryDogContextView(
              dogId: 'dog-a',
              name: 'Bono',
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    // Abrir Agenda (lazy prime + leitura)
    await tester.tap(find.text('Agenda'));
    await tester.pumpAndSettle();

    final entryState =
        tester.state(find.byType(HealthV1EntryScreen))
            as HealthV1EntryScreenState;
    expect(entryState.schedulePrimedForTest, isTrue);
    expect(entryState.scheduleMutationGatewayForTest, same(spy));

    await entryState.scheduleControllerForTest.refresh();
    await entryState.scheduleControllerForTest.applyFilters(
      types: {ScheduleType.general},
    );
    await tester.pumpAndSettle();

    spy.expectZero();
  });
}
