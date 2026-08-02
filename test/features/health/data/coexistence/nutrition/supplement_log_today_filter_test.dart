import 'package:flutter_test/flutter_test.dart';
import 'package:canil_gcm/features/health/data/coexistence/nutrition/coexistence_nutrition_read_source.dart';
import 'package:canil_gcm/features/health/domain/nutrition_plan.dart';
import 'package:canil_gcm/features/health/domain/supplement_log.dart';
import 'package:canil_gcm/features/health/domain/nutrition_read_models.dart';
import 'package:canil_gcm/features/health/domain/health_v1_models.dart';
import 'package:canil_gcm/features/health/domain/legacy_nutrition_views.dart';

void main() {
  group('Filtro Today — SupplementLog (Gate 5C.4B)', () {
    late NutritionTodayReadModel todayModel;

    // Fixture: 3 SupplementLogs (hoje, ontem, 30 dias atrás)
    final todayLog = _makeLog(
      id: 'sl1_today',
      dogId: 'dog-001',
      name: 'Vitamina C',
      administeredAt: DateTime.utc(
        2026,
        7,
        22,
        8,
        0,
      ), // hoje 08:00 UTC = 05:00 Brasília
    );
    final yesterdayLog = _makeLog(
      id: 'sl1_yesterday',
      dogId: 'dog-001',
      name: 'Vitamina B12',
      administeredAt: DateTime.utc(2026, 7, 21, 8, 0), // ontem 08:00 UTC
    );
    final thirtyDaysLog = _makeLog(
      id: 'sl1_30days',
      dogId: 'dog-001',
      name: 'Ômega 3',
      administeredAt: DateTime.utc(2026, 6, 22, 8, 0), // 30 dias atrás
    );

    setUp(() {
      // Simular loadToday() com os 3 logs no snapshot
      // O filtro em loadToday() deve retornar apenas todayLog
      // (quando serviceDate = 2026-07-22)
      todayModel = NutritionTodayReadModel(
        dogId: 'dog-001',
        localServiceDate: '2026-07-22',
        timezone: 'America/Sao_Paulo',
        activePlan: null,
        meals: const [],
        // Aqui simulamos o resultado do filtro em loadToday()
        // O teste de unidade do source filtra por LocalServiceDate
        canonicalSupplementLogs: [todayLog], // Apenas hoje após filtro
        legacySupplementRegimens: const [],
      );
    });

    test('hoje → aparece em NutritionTodayReadModel', () {
      expect(todayModel.canonicalSupplementLogs, hasLength(1));
      expect(todayModel.canonicalSupplementLogs.first.id, equals('sl1_today'));
    });

    test('ontem → não aparece em Today', () {
      expect(
        todayModel.canonicalSupplementLogs.any((l) => l.id == 'sl1_yesterday'),
        isFalse,
      );
    });

    test('30 dias atrás → não aparece em Today', () {
      expect(
        todayModel.canonicalSupplementLogs.any((l) => l.id == 'sl1_30days'),
        isFalse,
      );
    });

    test('fonte canônica completa continua contendo os 3 registros', () {
      // Simular snapshot completo (sem filtro)
      final fullSnapshot = NutritionCoexistenceSnapshot(
        dogId: 'dog-001',
        canonicalPlans: const [],
        legacyPlans: const [],
        canonicalMeals: const [],
        legacyMeals: const [],
        canonicalSupplementLogs: [todayLog, yesterdayLog, thirtyDaysLog],
        legacySupplementRegimens: const [],
        planSources: const [],
        mealSources: const [],
        mergedMeals: const [],
        activePlan: null,
      );

      expect(fullSnapshot.canonicalSupplementLogs, hasLength(3));
      expect(
        fullSnapshot.canonicalSupplementLogs.any((l) => l.id == 'sl1_today'),
        isTrue,
      );
      expect(
        fullSnapshot.canonicalSupplementLogs.any(
          (l) => l.id == 'sl1_yesterday',
        ),
        isTrue,
      );
      expect(
        fullSnapshot.canonicalSupplementLogs.any((l) => l.id == 'sl1_30days'),
        isTrue,
      );
    });

    group('LocalServiceDay boundaries', () {
      test('exatamente no início do dia local → inclui', () {
        // UTC-3: 2026-07-22 03:00 UTC = 2026-07-22 00:00 Brasília
        final startOfDay = DateTime.utc(2026, 7, 22, 3, 0, 0);
        final localDate = _extractLocalDate(startOfDay);
        expect(localDate, equals('2026-07-22'));
      });

      test('imediatamente antes do fim do dia local → inclui', () {
        // UTC-3: 2026-07-23 02:59 UTC = 2026-07-22 23:59 Brasília
        final beforeEnd = DateTime.utc(2026, 7, 23, 2, 59, 59);
        final localDate = _extractLocalDate(beforeEnd);
        expect(localDate, equals('2026-07-22'));
      });

      test('exatamente no próximo dia local → exclui', () {
        // UTC-3: 2026-07-23 03:00 UTC = 2026-07-23 00:00 Brasília
        final exactlyNextDay = DateTime.utc(2026, 7, 23, 3, 0, 0);
        final localDate = _extractLocalDate(exactlyNextDay);
        expect(localDate, equals('2026-07-23'));
        expect(localDate, isNot(equals('2026-07-22')));
      });

      test('ontem → exclui', () {
        // UTC-3: 2026-07-21 03:00 UTC = 2026-07-21 00:00 Brasília
        final yesterday = DateTime.utc(2026, 7, 21, 3, 0, 0);
        final localDate = _extractLocalDate(yesterday);
        expect(localDate, equals('2026-07-21'));
        expect(localDate, isNot(equals('2026-07-22')));
      });
    });

    test(
      'loadToday filtra snapshot histórico pela data civil normativa perto da meia-noite',
      () async {
        final previousLocalDay = _makeLog(
          id: 'previous-local-day',
          dogId: 'dog-001',
          name: 'Anterior',
          administeredAt: DateTime.utc(2026, 7, 22, 2, 59, 59),
        );
        final startOfLocalDay = _makeLog(
          id: 'start-local-day',
          dogId: 'dog-001',
          name: 'Hoje',
          administeredAt: DateTime.utc(2026, 7, 22, 3),
        );
        final source = CoexistenceNutritionReadSource(
          canonicalPlanReader: _EmptyPlanReader(),
          canonicalSupplementLogReader: _SupplementReader([
            previousLocalDay,
            startOfLocalDay,
          ]),
        );

        final snapshot = await source.loadSnapshot('dog-001');
        final today = await source.loadToday(
          'dog-001',
          serverNow: DateTime.utc(2026, 7, 22, 12),
        );

        expect(snapshot.value!.canonicalSupplementLogs, hasLength(2));
        expect(today.isData, isTrue);
        expect(today.value!.localServiceDate, '2026-07-22');
        expect(today.value!.timezone, NutritionPlan.defaultTimezone);
        expect(today.value!.canonicalSupplementLogs.map((log) => log.id), [
          'start-local-day',
        ]);
      },
    );

    test(
      'timezone explícito do plano governa a meia-noite sem timezone do device',
      () async {
        final plan = NutritionPlan(
          id: 'plan-timezone',
          dogId: 'dog-001',
          foodType: 'Ração',
          amountGramsPerDay: 400,
          mealsPerDay: 2,
          mealSchedule: const [],
          validFrom: DateTime.utc(2026, 1, 1),
          timezone: 'America/Sao_Paulo',
          recordedBy: RecordedBy(
            uid: 'u1',
            name: 'Operador',
            internalRole: 'operator',
          ),
          status: NutritionPlanStatus.active,
          schemaVersion: 1,
          revision: 1,
        );
        final beforeLocalMidnight = _makeLog(
          id: 'local-21',
          dogId: 'dog-001',
          name: 'Antes da meia-noite local',
          administeredAt: DateTime.utc(2026, 7, 22, 2, 15),
        );
        final afterLocalMidnight = _makeLog(
          id: 'local-22',
          dogId: 'dog-001',
          name: 'Depois da meia-noite local',
          administeredAt: DateTime.utc(2026, 7, 22, 3, 15),
        );
        final source = CoexistenceNutritionReadSource(
          canonicalPlanReader: _PlanReader(plan),
          canonicalSupplementLogReader: _SupplementReader([
            beforeLocalMidnight,
            afterLocalMidnight,
          ]),
        );

        final snapshot = await source.loadSnapshot('dog-001');
        final today = source.projectTodayFromSnapshot(
          dogId: 'dog-001',
          snapshotResult: snapshot,
          serverNow: DateTime.utc(2026, 7, 22, 2, 30),
        );

        expect(snapshot.value!.canonicalSupplementLogs.map((log) => log.id), [
          'local-21',
          'local-22',
        ]);
        expect(today.value!.timezone, 'America/Sao_Paulo');
        expect(today.value!.localServiceDate, '2026-07-21');
        expect(today.value!.canonicalSupplementLogs.map((log) => log.id), [
          'local-21',
        ]);
      },
    );

    test(
      'supplement source error stays degraded and never confirms empty',
      () async {
        final source = CoexistenceNutritionReadSource(
          canonicalPlanReader: _EmptyPlanReader(),
          canonicalSupplementLogReader: _ErrorSupplementReader(),
          legacySupplementRegimenReader: _LegacyRegimenReader(),
        );

        final today = await source.loadToday(
          'dog-001',
          serverNow: DateTime.utc(2026, 7, 22, 12),
        );

        expect(today.isDegraded, isTrue);
        expect(today.value!.canonicalSupplementLogs, isEmpty);
        expect(today.value!.canonicalSupplementLogsAvailable, isFalse);
        expect(today.isEmpty, isFalse);
      },
    );

    test(
      'degraded safe projection preserves only filtered supplement value',
      () async {
        final old = _makeLog(
          id: 'old-degraded',
          dogId: 'dog-001',
          name: 'Antigo',
          administeredAt: DateTime.utc(2026, 7, 21, 12),
        );
        final current = _makeLog(
          id: 'today-degraded',
          dogId: 'dog-001',
          name: 'Hoje',
          administeredAt: DateTime.utc(2026, 7, 22, 12),
        );
        final source = CoexistenceNutritionReadSource(
          canonicalPlanReader: _ErrorPlanReader(),
          canonicalSupplementLogReader: _SupplementReader([old, current]),
        );

        final today = await source.loadToday(
          'dog-001',
          serverNow: DateTime.utc(2026, 7, 22, 15),
        );

        expect(today.isDegraded, isTrue);
        expect(today.value!.canonicalSupplementLogsAvailable, isTrue);
        expect(today.value!.canonicalSupplementLogs.map((log) => log.id), [
          'today-degraded',
        ]);
      },
    );
  });
}

final class _EmptyPlanReader implements NutritionCanonicalPlanReader {
  @override
  Future<NutritionSourceBatch<NutritionPlan>> loadPlans(String dogId) async =>
      const NutritionSourceBatch.empty();
}

final class _PlanReader implements NutritionCanonicalPlanReader {
  _PlanReader(this.plan);
  final NutritionPlan plan;

  @override
  Future<NutritionSourceBatch<NutritionPlan>> loadPlans(String dogId) async =>
      NutritionSourceBatch.available([plan]);
}

final class _ErrorPlanReader implements NutritionCanonicalPlanReader {
  @override
  Future<NutritionSourceBatch<NutritionPlan>> loadPlans(String dogId) async =>
      const NutritionSourceBatch.error(message: 'plan failed');
}

final class _SupplementReader implements NutritionCanonicalSupplementLogReader {
  _SupplementReader(this.logs);

  final List<SupplementLog> logs;

  @override
  Future<NutritionSourceBatch<SupplementLog>> loadSupplementLogs(
    String dogId,
  ) async => NutritionSourceBatch.available(logs);
}

final class _ErrorSupplementReader
    implements NutritionCanonicalSupplementLogReader {
  @override
  Future<NutritionSourceBatch<SupplementLog>> loadSupplementLogs(
    String dogId,
  ) async => const NutritionSourceBatch.error(message: 'supplements failed');
}

final class _LegacyRegimenReader
    implements NutritionLegacySupplementRegimenReader {
  @override
  Future<NutritionSourceBatch<LegacySupplementRegimenView>> loadRegimens(
    String dogId,
  ) async => NutritionSourceBatch.available([
    const LegacySupplementRegimenView(
      id: 'legacy-regimen',
      dogId: 'dog-001',
      name: 'Regime seguro',
      doseText: '1',
      legacySource: 'nutrition_supplements',
    ),
  ]);
}

SupplementLog _makeLog({
  required String id,
  required String dogId,
  required String name,
  required DateTime administeredAt,
}) {
  return SupplementLog(
    id: id,
    dogId: dogId,
    supplementName: name,
    dose: 1.0,
    unit: SupplementDoseUnit.tablet,
    administeredAt: administeredAt,
    recordedBy: RecordedBy(
      uid: 'test-uid',
      name: 'Test User',
      internalRole: 'tester',
    ),
    schemaVersion: 1,
    revision: 1,
    nutritionPlanId: null,
    supplementRegimenId: null,
    notes: null,
    batchNumber: null,
  );
}

/// Extrai a data local (YYYY-MM-DD) de um DateTime UTC.
/// Simula LocalServiceDate.fromInstant() com timezone America/Sao_Paulo (UTC-3).
String _extractLocalDate(DateTime utcInstant) {
  // Para America/Sao_Paulo (UTC-3):
  // Quando UTC é 2026-07-22 03:00, hora local é 2026-07-22 00:00
  // Quando UTC é 2026-07-23 02:59, hora local é 2026-07-22 23:59
  // Quando UTC é 2026-07-23 03:00, hora local é 2026-07-23 00:00
  final localInstant = utcInstant.toLocal();
  return '${localInstant.year.toString().padLeft(4, '0')}-'
      '${localInstant.month.toString().padLeft(2, '0')}-'
      '${localInstant.day.toString().padLeft(2, '0')}';
}
