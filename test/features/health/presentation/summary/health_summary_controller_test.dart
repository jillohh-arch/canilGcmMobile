import 'package:flutter_test/flutter_test.dart';

import 'package:canil_gcm/features/health/domain/health_v1_enums_ext.dart';
import 'package:canil_gcm/features/health/presentation/summary/health_summary_block_models.dart';
import 'package:canil_gcm/features/health/presentation/summary/health_summary_controller.dart';
import 'package:canil_gcm/features/health/presentation/summary/health_summary_section_status.dart';
import 'package:canil_gcm/features/health/presentation/summary/health_summary_source.dart';
import 'package:canil_gcm/features/health/presentation/summary/health_summary_source_metadata.dart';
import 'package:canil_gcm/features/health/presentation/summary/health_summary_state.dart';
import 'package:canil_gcm/features/health/presentation/summary/health_summary_view_data.dart';

import 'fake_health_summary_source.dart';

void main() {
  late FakeHealthSummarySource source;
  late HealthSummaryController controller;

  setUp(() {
    source = FakeHealthSummarySource();
    controller = HealthSummaryController(source: source);
  });

  tearDown(() async {
    controller.dispose();
    await source.disposeAll();
  });

  HealthSummaryViewData sampleData(
    String dogId, {
    ReadinessStatus readiness = ReadinessStatus.operational,
    HealthSummarySourceMetadata metadata = const HealthSummarySourceMetadata(),
  }) {
    return HealthSummaryViewData(
      dogId: dogId,
      readiness: HealthSummarySectionData.available(
        HealthSummaryReadinessView(status: readiness, reason: 'ok'),
      ),
      weight: HealthSummarySectionData.available(
        HealthSummaryWeightView(weightKg: 28.5),
      ),
      vaccination: const HealthSummarySectionData.notRecorded(
        message: 'Nenhuma vacinação registrada',
      ),
      treatments: HealthSummarySectionData.available(
        HealthSummaryTreatmentsView(activeProtocolCount: 0),
      ),
      attention: const HealthSummarySectionData.available(
        HealthSummaryAttentionView(),
      ),
      nutritionToday: const HealthSummarySectionData.loading(),
      weightTrend: const HealthSummarySectionData.unavailable(
        message: 'Não foi possível consultar evolução',
      ),
      recentRecords: const HealthSummarySectionData.notRecorded(),
      metadata: metadata,
    );
  }

  group('estado básico', () {
    test('inicia em initial', () {
      expect(controller.state, isA<HealthSummaryInitial>());
      expect(controller.activeDogId, isNull);
    });

    test('selectDog → loading → data', () async {
      controller.selectDog('dog-a');
      expect(controller.state, isA<HealthSummaryLoading>());
      expect((controller.state as HealthSummaryLoading).dogId, 'dog-a');

      source.emit('dog-a', sampleData('dog-a'));
      await Future<void>.delayed(Duration.zero);

      expect(controller.state, isA<HealthSummaryData>());
      final data = controller.state as HealthSummaryData;
      expect(data.dogId, 'dog-a');
      expect(data.data.dogId, 'dog-a');
    });

    test('selectDog → loading → empty (null)', () async {
      controller.selectDog('dog-a');
      source.emit('dog-a', null);
      await Future<void>.delayed(Duration.zero);

      expect(controller.state, isA<HealthSummaryEmpty>());
      expect((controller.state as HealthSummaryEmpty).dogId, 'dog-a');
    });

    test('selectDog → error', () async {
      controller.selectDog('dog-a');
      source.emitError(
        'dog-a',
        const HealthSummarySourceException('falha de leitura'),
      );
      await Future<void>.delayed(Duration.zero);

      expect(controller.state, isA<HealthSummaryError>());
      final err = controller.state as HealthSummaryError;
      expect(err.dogId, 'dog-a');
      expect(err.message, 'falha de leitura');
      expect(err.lastKnownData, isNull);
    });

    test('offline sem cache', () async {
      controller.selectDog('dog-a');
      source.emitError(
        'dog-a',
        const HealthSummarySourceException('sem rede', isOffline: true),
      );
      await Future<void>.delayed(Duration.zero);

      expect(controller.state, isA<HealthSummaryOffline>());
      final offline = controller.state as HealthSummaryOffline;
      expect(offline.dogId, 'dog-a');
      expect(offline.cachedData, isNull);
    });

    test('offline com dados prévios do mesmo dogId', () async {
      controller.selectDog('dog-a');
      final payload = sampleData('dog-a');
      source.emit('dog-a', payload);
      await Future<void>.delayed(Duration.zero);
      expect(controller.state, isA<HealthSummaryData>());

      source.emitError(
        'dog-a',
        const HealthSummarySourceException('offline', isOffline: true),
      );
      await Future<void>.delayed(Duration.zero);

      final offline = controller.state as HealthSummaryOffline;
      expect(offline.dogId, 'dog-a');
      expect(offline.cachedData?.dogId, 'dog-a');
      expect(
        offline.cachedData?.readiness.value?.status,
        ReadinessStatus.operational,
      );
    });

    test('dogId vazio lança ArgumentError', () {
      expect(() => controller.selectDog(''), throwsArgumentError);
      expect(() => controller.selectDog('   '), throwsArgumentError);
    });
  });

  group('erro após data e offline/metadata', () {
    test(
      'erro não-offline após data preserva lastKnownData do mesmo dog',
      () async {
        controller.selectDog('dog-a');
        source.emit('dog-a', sampleData('dog-a'));
        await Future<void>.delayed(Duration.zero);
        expect(controller.state, isA<HealthSummaryData>());

        source.emitError(
          'dog-a',
          const HealthSummarySourceException('falha transitória'),
        );
        await Future<void>.delayed(Duration.zero);

        final err = controller.state as HealthSummaryError;
        expect(err.dogId, 'dog-a');
        expect(err.lastKnownData?.dogId, 'dog-a');
        expect(err.lastKnownData?.weight.value?.weightKg, 28.5);
        expect(
          err.lastKnownData?.readiness.value?.status,
          ReadinessStatus.operational,
        );
      },
    );

    test(
      'payload com metadata.isOffline vira state offline com dados',
      () async {
        controller.selectDog('dog-a');
        source.emit(
          'dog-a',
          sampleData(
            'dog-a',
            metadata: const HealthSummarySourceMetadata(isOffline: true),
          ),
        );
        await Future<void>.delayed(Duration.zero);

        final offline = controller.state as HealthSummaryOffline;
        expect(offline.dogId, 'dog-a');
        expect(offline.cachedData?.metadata.isOffline, isTrue);
        expect(offline.cachedData?.dogId, 'dog-a');
      },
    );
  });

  group('retry / refresh / onDone', () {
    test('após error, selectDog mesmo id é no-op; refresh reconecta', () async {
      controller.selectDog('dog-a');
      source.emitError('dog-a', const HealthSummarySourceException('falha'));
      await Future<void>.delayed(Duration.zero);
      expect(controller.state, isA<HealthSummaryError>());
      expect(source.watchCalls, ['dog-a']);
      expect(controller.hasActiveSubscriptionForTest, isTrue);

      controller.selectDog('dog-a');
      expect(source.watchCalls, ['dog-a']);

      controller.refresh();
      expect(source.watchCalls, ['dog-a', 'dog-a']);
      expect(controller.state, isA<HealthSummaryLoading>());
      expect((controller.state as HealthSummaryLoading).dogId, 'dog-a');

      source.emit('dog-a', sampleData('dog-a'));
      await Future<void>.delayed(Duration.zero);
      expect(controller.state, isA<HealthSummaryData>());
    });

    test('após onDone, selectDog mesmo id reconecta', () async {
      controller.selectDog('dog-a');
      source.emit('dog-a', sampleData('dog-a'));
      await Future<void>.delayed(Duration.zero);
      expect(controller.state, isA<HealthSummaryData>());

      source.complete('dog-a');
      await Future<void>.delayed(Duration.zero);
      expect(controller.hasActiveSubscriptionForTest, isFalse);

      controller.selectDog('dog-a');
      expect(source.watchCalls, ['dog-a', 'dog-a']);
      expect(controller.state, isA<HealthSummaryLoading>());
    });

    test('refresh de A não interfere após troca para B', () async {
      controller.selectDog('dog-a');
      controller.selectDog('dog-b');
      final genB = controller.generationForTest;

      // refresh ainda aponta B (ativo).
      controller.refresh();
      expect(controller.generationForTest, greaterThan(genB));
      expect((controller.state as HealthSummaryLoading).dogId, 'dog-b');

      source.emit('dog-a', sampleData('dog-a'));
      await Future<void>.delayed(Duration.zero);
      expect((controller.state as HealthSummaryLoading).dogId, 'dog-b');

      source.emit('dog-b', sampleData('dog-b'));
      await Future<void>.delayed(Duration.zero);
      expect((controller.state as HealthSummaryData).dogId, 'dog-b');
    });

    test('refresh sem dogId ativo lança', () {
      expect(() => controller.refresh(), throwsStateError);
    });
  });

  group('troca rápida de K9 e cache', () {
    test('emissão tardia de A não contamina B', () async {
      controller.selectDog('dog-a');
      controller.selectDog('dog-b');
      expect(source.cancelledDogIds, contains('dog-a'));

      source.emit('dog-a', sampleData('dog-a'));
      await Future<void>.delayed(Duration.zero);
      expect((controller.state as HealthSummaryLoading).dogId, 'dog-b');

      source.emit('dog-b', sampleData('dog-b'));
      await Future<void>.delayed(Duration.zero);
      expect((controller.state as HealthSummaryData).dogId, 'dog-b');
    });

    test('erro tardio de A não contamina B', () async {
      controller.selectDog('dog-a');
      controller.selectDog('dog-b');
      source.emit('dog-b', sampleData('dog-b'));
      await Future<void>.delayed(Duration.zero);

      source.emitError(
        'dog-a',
        const HealthSummarySourceException('A falhou tarde'),
      );
      await Future<void>.delayed(Duration.zero);

      expect((controller.state as HealthSummaryData).dogId, 'dog-b');
    });

    test('onDone tardio de A não contamina B', () async {
      controller.selectDog('dog-a');
      controller.selectDog('dog-b');
      source.emit('dog-b', sampleData('dog-b'));
      await Future<void>.delayed(Duration.zero);

      // complete em A (stream antiga) — B permanece data.
      source.emit('dog-a', sampleData('dog-a'));
      await Future<void>.delayed(Duration.zero);
      expect((controller.state as HealthSummaryData).dogId, 'dog-b');
      expect(controller.hasActiveSubscriptionForTest, isTrue);
    });

    test('payload com dogId divergente é ignorado', () async {
      controller.selectDog('dog-b');
      source.emit('dog-b', sampleData('dog-a'));
      await Future<void>.delayed(Duration.zero);
      expect((controller.state as HealthSummaryLoading).dogId, 'dog-b');
    });

    test('mesmo dogId não cria subscription duplicada', () {
      controller.selectDog('dog-a');
      controller.selectDog('dog-a');
      expect(source.watchCalls, ['dog-a']);
    });

    test('cache de A nunca aparece quando B offline sem cache', () async {
      controller.selectDog('dog-a');
      source.emit('dog-a', sampleData('dog-a'));
      await Future<void>.delayed(Duration.zero);
      expect(controller.state, isA<HealthSummaryData>());

      controller.selectDog('dog-b');
      source.emitError(
        'dog-b',
        const HealthSummarySourceException('offline B', isOffline: true),
      );
      await Future<void>.delayed(Duration.zero);

      final offline = controller.state as HealthSummaryOffline;
      expect(offline.dogId, 'dog-b');
      expect(offline.cachedData, isNull);
    });

    test('B offline usa somente cache de B', () async {
      controller.selectDog('dog-a');
      source.emit('dog-a', sampleData('dog-a'));
      await Future<void>.delayed(Duration.zero);

      controller.selectDog('dog-b');
      source.emit('dog-b', sampleData('dog-b'));
      await Future<void>.delayed(Duration.zero);

      source.emitError(
        'dog-b',
        const HealthSummarySourceException('offline', isOffline: true),
      );
      await Future<void>.delayed(Duration.zero);

      final offline = controller.state as HealthSummaryOffline;
      expect(offline.dogId, 'dog-b');
      expect(offline.cachedData?.dogId, 'dog-b');
      expect(offline.cachedData?.dogId, isNot('dog-a'));
    });
  });

  group('dados parciais e readiness', () {
    test('blocos parciais mantêm estado geral data', () async {
      controller.selectDog('dog-a');
      source.emit('dog-a', sampleData('dog-a'));
      await Future<void>.delayed(Duration.zero);

      final state = controller.state as HealthSummaryData;
      expect(state.data.readiness.isAvailable, isTrue);
      expect(state.data.weight.isAvailable, isTrue);
      expect(state.data.vaccination.isNotRecorded, isTrue);
      expect(state.data.nutritionToday.isLoading, isTrue);
      expect(state.data.weightTrend.isUnavailable, isTrue);
      expect(state.data.recentRecords.isNotRecorded, isTrue);
    });

    test('notRecorded ≠ unavailable e factories sem value', () {
      const notRecorded = HealthSummarySectionData<String>.notRecorded(
        message: 'Nenhuma vacinação registrada',
      );
      const unavailable = HealthSummarySectionData<String>.unavailable(
        message: 'Não foi possível consultar vacinação',
      );
      const loading = HealthSummarySectionData<String>.loading();
      const available = HealthSummarySectionData.available('x');

      expect(notRecorded.value, isNull);
      expect(unavailable.value, isNull);
      expect(loading.value, isNull);
      expect(available.value, 'x');
      expect(available.valueOrNull, 'x');
      expect(notRecorded.valueOrNull, isNull);
      expect(notRecorded, isNot(unavailable));
    });

    test('aceita os cinco estados oficiais de prontidão', () async {
      expect(ReadinessStatus.values, hasLength(5));
      for (final status in ReadinessStatus.values) {
        controller.dispose();
        controller = HealthSummaryController(source: source);
        controller.selectDog('dog-$status');
        source.emit(
          'dog-$status',
          sampleData('dog-$status', readiness: status),
        );
        await Future<void>.delayed(Duration.zero);
        final data = controller.state as HealthSummaryData;
        expect(data.data.readiness.value?.status, status);
      }
    });

    test('not_evaluated não implica empty', () async {
      controller.selectDog('dog-a');
      source.emit(
        'dog-a',
        sampleData('dog-a', readiness: ReadinessStatus.notEvaluated),
      );
      await Future<void>.delayed(Duration.zero);

      expect(controller.state, isA<HealthSummaryData>());
      final data = controller.state as HealthSummaryData;
      expect(data.data.readiness.value?.status, ReadinessStatus.notEvaluated);
      expect(data.data.weight.isAvailable, isTrue);
    });

    test('peso negativo e contagem negativa são rejeitados', () {
      expect(() => HealthSummaryWeightView(weightKg: -1), throwsArgumentError);
      expect(
        () => HealthSummaryTreatmentsView(activeProtocolCount: -1),
        throwsArgumentError,
      );
    });
  });

  group('dispose', () {
    test('emissão após dispose não notifica nem lança', () async {
      var notifications = 0;
      controller.addListener(() => notifications++);

      controller.selectDog('dog-a');
      final afterSelect = notifications;

      controller.dispose();
      expect(controller.isDisposedForTest, isTrue);

      source.emit('dog-a', sampleData('dog-a'));
      source.emitError('dog-a', const HealthSummarySourceException('x'));
      await Future<void>.delayed(Duration.zero);
      expect(notifications, afterSelect);
    });

    test('dispose é idempotente', () {
      controller.dispose();
      expect(() => controller.dispose(), returnsNormally);
    });
  });
}
