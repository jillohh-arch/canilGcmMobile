import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:canil_gcm/features/health/data/coexistence/timeline/coexistence_health_timeline_source.dart';
import 'package:canil_gcm/features/health/data/coexistence/timeline/memory_timeline_source_reader.dart';
import 'package:canil_gcm/features/health/presentation/timeline/health_timeline_source.dart';
import '../schedule/fake_health_schedule_global_source.dart';
import '../schedule/fake_health_schedule_source.dart';
import 'package:canil_gcm/features/health/presentation/schedule/health_schedule_experience_scope.dart';
import 'package:canil_gcm/features/health/presentation/schedule/health_schedule_global_view.dart';
import 'package:canil_gcm/features/health/presentation/schedule/health_schedule_screen.dart';
import '../schedule/schedule_test_helpers.dart';
import 'package:canil_gcm/features/health/presentation/screens/health_v1_entry_screen.dart';
import 'package:canil_gcm/features/health/presentation/summary/health_summary_dog_context_view.dart';
import 'package:canil_gcm/features/health/presentation/summary/health_summary_source.dart';
import 'package:canil_gcm/features/health/presentation/summary/health_summary_view_data.dart';

class _FixedSummarySource implements HealthSummarySource {
  _FixedSummarySource(this.payloadByDogId);
  final Map<String, HealthSummaryViewData> payloadByDogId;

  factory _FixedSummarySource.single(HealthSummaryViewData payload) {
    return _FixedSummarySource({payload.dogId: payload});
  }

  @override
  Stream<HealthSummaryViewData?> watchSummary(String dogId) async* {
    yield payloadByDogId[dogId] ?? HealthSummaryViewData(dogId: dogId);
  }
}

HealthTimelineSource _emptyTimelineSource() {
  return CoexistenceHealthTimelineSourceFactory.forReaders([
    MemoryTimelineSourceReader(sourceKey: 'empty', items: const []),
  ]);
}

class _FixedScheduleExperienceGateway
    implements HealthScheduleExperienceGateway {
  _FixedScheduleExperienceGateway(this.experience);
  final HealthScheduleExperience experience;

  @override
  Future<HealthScheduleExperience> resolve() async => experience;
}

void main() {
  setUpAll(() {
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  const dogRaykaId = 'CjrcMWykXGDXGLYw8Hs6';
  const dogOtherId = 'FjanV4aIDF3qxVeoOflV';

  final ctxRayka = HealthSummaryDogContextView(
    dogId: dogRaykaId,
    name: 'Rayka',
    breed: 'Pastor Belga Malinois',
  );

  final ctxOther = HealthSummaryDogContextView(
    dogId: dogOtherId,
    name: 'Banshee',
    breed: 'Pastor Alemão',
  );

  Widget wrap(Widget child) {
    return MaterialApp(home: Scaffold(body: child));
  }

  Future<void> setPhoneSurface(WidgetTester tester) async {
    final view = tester.view;
    view.physicalSize = const Size(400, 900);
    view.devicePixelRatio = 1.0;
    addTearDown(view.resetPhysicalSize);
    addTearDown(view.resetDevicePixelRatio);
  }

  group('Agenda Dog-Scoped Isolation in HealthV1EntryScreen', () {
    late FakeHealthScheduleSource scheduleSource;
    late FakeHealthScheduleGlobalSource globalSource;

    setUp(() {
      scheduleSource = FakeHealthScheduleSource();
      globalSource = FakeHealthScheduleGlobalSource();
    });

    tearDown(() {
      scheduleSource.reset();
    });

    testWidgets(
      'Agenda tab displays dog-scoped schedule for selected dog even when user has global scope',
      (tester) async {
        await setPhoneSurface(tester);

        scheduleSource.handler = (query) async {
          if (query.dogId == dogRaykaId) {
            return schedulePage([
              scheduleItem(
                id: 'sched-rayka-1',
                dogId: dogRaykaId,
                title: 'Vacina V10 Rayka',
              ),
            ]);
          }
          return schedulePage(const []);
        };

        await tester.pumpWidget(
          wrap(
            HealthV1EntryScreen(
              dogId: dogRaykaId,
              source: _FixedSummarySource.single(
                HealthSummaryViewData(dogId: dogRaykaId),
              ),
              timelineSource: _emptyTimelineSource(),
              scheduleSource: scheduleSource,
              scheduleGlobalSource: globalSource,
              scheduleExperience: HealthScheduleExperience.global,
              dogContextOverride: ctxRayka,
            ),
          ),
        );
        await tester.pumpAndSettle();

        final state = tester.state<HealthV1EntryScreenState>(
          find.byType(HealthV1EntryScreen),
        );
        expect(
          state.scheduleExperienceForTest,
          HealthScheduleExperience.global,
          reason: 'Experiência global está configurada',
        );

        // Abrir a aba Agenda
        await tester.tap(find.text('Agenda'));
        await tester.pumpAndSettle();

        // 1. Deve renderizar HealthScheduleScreen (per-dog), NUNCA HealthScheduleGlobalView
        expect(
          find.byType(HealthScheduleScreen),
          findsOneWidget,
          reason: 'Aba Agenda do prontuário deve ser HealthScheduleScreen',
        );
        expect(
          find.byType(HealthScheduleGlobalView),
          findsNothing,
          reason: 'HealthScheduleGlobalView não deve vazar no prontuário per-dog',
        );

        // 2. Global source NUNCA deve ser chamado
        expect(
          globalSource.callCount,
          0,
          reason: 'Global schedule source não deve ser chamado no prontuário per-dog',
        );

        // 3. Schedule source per-dog deve ter recebido consulta para o cão ativo
        expect(scheduleSource.requests, hasLength(1));
        expect(scheduleSource.requests.single.dogId, dogRaykaId);

        // 4. Item de Rayka deve estar visível
        expect(find.text('Vacina V10 Rayka'), findsOneWidget);
      },
    );

    testWidgets(
      'Gateway com escopo global não vaza agenda global no Health per-dog',
      (tester) async {
        await setPhoneSurface(tester);

        scheduleSource.handler = (query) async {
          return schedulePage([
            scheduleItem(
              id: 'sched-rayka-gw',
              dogId: dogRaykaId,
              title: 'Exame Periódico Rayka',
            ),
          ]);
        };

        await tester.pumpWidget(
          wrap(
            HealthV1EntryScreen(
              dogId: dogRaykaId,
              source: _FixedSummarySource.single(
                HealthSummaryViewData(dogId: dogRaykaId),
              ),
              timelineSource: _emptyTimelineSource(),
              scheduleSource: scheduleSource,
              scheduleGlobalSource: globalSource,
              scheduleExperienceGateway: _FixedScheduleExperienceGateway(
                HealthScheduleExperience.global,
              ),
              dogContextOverride: ctxRayka,
            ),
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.text('Agenda'));
        await tester.pumpAndSettle();

        expect(find.byType(HealthScheduleScreen), findsOneWidget);
        expect(find.byType(HealthScheduleGlobalView), findsNothing);
        expect(globalSource.callCount, 0);
        expect(scheduleSource.requests.single.dogId, dogRaykaId);
        expect(find.text('Exame Periódico Rayka'), findsOneWidget);
      },
    );

    testWidgets(
      'Entries from Dog B never leak into Dog A Agenda',
      (tester) async {
        await setPhoneSurface(tester);

        scheduleSource.handler = (query) async {
          if (query.dogId == dogRaykaId) {
            return schedulePage([
              scheduleItem(
                id: 's-rayka',
                dogId: dogRaykaId,
                title: 'Item exclusivo da Rayka',
              ),
            ]);
          } else if (query.dogId == dogOtherId) {
            return schedulePage([
              scheduleItem(
                id: 's-banshee',
                dogId: dogOtherId,
                title: 'STG K9 Edit Fixture (Banshee)',
              ),
            ]);
          }
          return schedulePage(const []);
        };

        await tester.pumpWidget(
          wrap(
            HealthV1EntryScreen(
              dogId: dogRaykaId,
              source: _FixedSummarySource.single(
                HealthSummaryViewData(dogId: dogRaykaId),
              ),
              timelineSource: _emptyTimelineSource(),
              scheduleSource: scheduleSource,
              scheduleGlobalSource: globalSource,
              scheduleExperience: HealthScheduleExperience.global,
              dogContextOverride: ctxRayka,
            ),
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.text('Agenda'));
        await tester.pumpAndSettle();

        // O item de Rayka deve aparecer
        expect(find.text('Item exclusivo da Rayka'), findsOneWidget);

        // O item de Banshee (Dog B) JAMAIS deve aparecer
        expect(find.text('STG K9 Edit Fixture (Banshee)'), findsNothing);

        // Apenas uma consulta emitida, e estritamente para Rayka
        expect(scheduleSource.requests, hasLength(1));
        expect(scheduleSource.requests.single.dogId, dogRaykaId);
        expect(globalSource.callCount, 0);
      },
    );

    testWidgets(
      'Switching dogs via didUpdateWidget updates the schedule query to the new dog',
      (tester) async {
        await setPhoneSurface(tester);

        scheduleSource.handler = (query) async {
          if (query.dogId == dogRaykaId) {
            return schedulePage([
              scheduleItem(
                id: 's-rayka',
                dogId: dogRaykaId,
                title: 'Agenda Rayka',
              ),
            ]);
          } else if (query.dogId == dogOtherId) {
            return schedulePage([
              scheduleItem(
                id: 's-banshee',
                dogId: dogOtherId,
                title: 'Agenda Banshee',
              ),
            ]);
          }
          return schedulePage(const []);
        };

        final summarySource = _FixedSummarySource({
          dogRaykaId: HealthSummaryViewData(dogId: dogRaykaId),
          dogOtherId: HealthSummaryViewData(dogId: dogOtherId),
        });

        // 1. Monta tela para Rayka com key estável
        await tester.pumpWidget(
          wrap(
            HealthV1EntryScreen(
              key: const ValueKey('stable-entry'),
              dogId: dogRaykaId,
              source: summarySource,
              timelineSource: _emptyTimelineSource(),
              scheduleSource: scheduleSource,
              scheduleGlobalSource: globalSource,
              scheduleExperience: HealthScheduleExperience.global,
              dogContextOverride: ctxRayka,
            ),
          ),
        );
        await tester.pumpAndSettle();

        // 2. Abre a aba Agenda para Rayka
        await tester.tap(find.text('Agenda'));
        await tester.pumpAndSettle();

        expect(find.text('Agenda Rayka'), findsOneWidget);
        expect(find.text('Agenda Banshee'), findsNothing);
        expect(scheduleSource.requests.last.dogId, dogRaykaId);

        // 3. Atualiza widget para Banshee (dogOtherId) mantendo a mesma key
        await tester.pumpWidget(
          wrap(
            HealthV1EntryScreen(
              key: const ValueKey('stable-entry'),
              dogId: dogOtherId,
              source: summarySource,
              timelineSource: _emptyTimelineSource(),
              scheduleSource: scheduleSource,
              scheduleGlobalSource: globalSource,
              scheduleExperience: HealthScheduleExperience.global,
              dogContextOverride: ctxOther,
            ),
          ),
        );
        await tester.pumpAndSettle();

        // 4. Deve consultar e exibir a agenda de Banshee
        expect(find.text('Agenda Banshee'), findsOneWidget);
        expect(find.text('Agenda Rayka'), findsNothing);
        expect(scheduleSource.requests.last.dogId, dogOtherId);

        // Global source continua intacto (zero chamadas)
        expect(globalSource.callCount, 0);
      },
    );

    testWidgets(
      'Switching dogs via ValueKey remount isolates schedule queries and views',
      (tester) async {
        await setPhoneSurface(tester);

        scheduleSource.handler = (query) async {
          if (query.dogId == dogRaykaId) {
            return schedulePage([
              scheduleItem(
                id: 's-rayka-remount',
                dogId: dogRaykaId,
                title: 'Agenda Rayka (Remount)',
              ),
            ]);
          } else if (query.dogId == dogOtherId) {
            return schedulePage([
              scheduleItem(
                id: 's-banshee-remount',
                dogId: dogOtherId,
                title: 'Agenda Banshee (Remount)',
              ),
            ]);
          }
          return schedulePage(const []);
        };

        final summarySource = _FixedSummarySource({
          dogRaykaId: HealthSummaryViewData(dogId: dogRaykaId),
          dogOtherId: HealthSummaryViewData(dogId: dogOtherId),
        });

        // 1. Monta tela para Rayka com ValueKey('health-v1-rayka')
        await tester.pumpWidget(
          wrap(
            HealthV1EntryScreen(
              key: const ValueKey('health-v1-rayka'),
              dogId: dogRaykaId,
              source: summarySource,
              timelineSource: _emptyTimelineSource(),
              scheduleSource: scheduleSource,
              scheduleGlobalSource: globalSource,
              scheduleExperience: HealthScheduleExperience.global,
              dogContextOverride: ctxRayka,
            ),
          ),
        );
        await tester.pumpAndSettle();

        // 2. Abre a aba Agenda para Rayka
        await tester.tap(find.text('Agenda'));
        await tester.pumpAndSettle();

        expect(find.text('Agenda Rayka (Remount)'), findsOneWidget);
        expect(find.text('Agenda Banshee (Remount)'), findsNothing);
        expect(scheduleSource.requests.map((r) => r.dogId), [dogRaykaId]);

        // 3. Troca de cão via ValueKey (como no MainRoot: 'health-v1-banshee')
        await tester.pumpWidget(
          wrap(
            HealthV1EntryScreen(
              key: const ValueKey('health-v1-banshee'),
              dogId: dogOtherId,
              source: summarySource,
              timelineSource: _emptyTimelineSource(),
              scheduleSource: scheduleSource,
              scheduleGlobalSource: globalSource,
              scheduleExperience: HealthScheduleExperience.global,
              dogContextOverride: ctxOther,
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Abre a aba Agenda para Banshee
        await tester.tap(find.text('Agenda'));
        await tester.pumpAndSettle();

        expect(find.text('Agenda Banshee (Remount)'), findsOneWidget);
        expect(find.text('Agenda Rayka (Remount)'), findsNothing);
        expect(scheduleSource.requests.map((r) => r.dogId), [
          dogRaykaId,
          dogOtherId,
        ]);
        expect(globalSource.callCount, 0);
      },
    );

    testWidgets(
      'Lazy prime: schedule query is deferred until Agenda tab is opened',
      (tester) async {
        await setPhoneSurface(tester);

        scheduleSource.handler = (query) async {
          return schedulePage([
            scheduleItem(
              id: 's-rayka-lazy',
              dogId: dogRaykaId,
              title: 'Item Lazy Rayka',
            ),
          ]);
        };

        await tester.pumpWidget(
          wrap(
            HealthV1EntryScreen(
              dogId: dogRaykaId,
              source: _FixedSummarySource.single(
                HealthSummaryViewData(dogId: dogRaykaId),
              ),
              timelineSource: _emptyTimelineSource(),
              scheduleSource: scheduleSource,
              scheduleGlobalSource: globalSource,
              scheduleExperience: HealthScheduleExperience.global,
              dogContextOverride: ctxRayka,
            ),
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 50));

        final state = tester.state<HealthV1EntryScreenState>(
          find.byType(HealthV1EntryScreen),
        );

        // Na aba Resumo, agenda ainda não foi primada
        expect(state.schedulePrimedForTest, isFalse);
        expect(scheduleSource.requests, isEmpty);

        // Abre a aba Agenda
        await tester.tap(find.text('Agenda'));
        await tester.pumpAndSettle();

        // Agora foi primada e enviou requisição
        expect(state.schedulePrimedForTest, isTrue);
        expect(scheduleSource.requests, hasLength(1));
        expect(scheduleSource.requests.single.dogId, dogRaykaId);
        expect(find.text('Item Lazy Rayka'), findsOneWidget);
      },
    );
  });
}
