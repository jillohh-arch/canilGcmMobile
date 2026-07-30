import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:canil_gcm/features/dogs/domain/dog.dart';
import 'package:canil_gcm/features/health/data/coexistence/summary/coexistence_health_summary_source.dart';
import 'package:canil_gcm/features/health/data/coexistence/summary/health_summary_date_parse.dart';
import 'package:canil_gcm/features/health/data/coexistence/summary/health_summary_dog_context_mapper.dart';
import 'package:canil_gcm/features/health/data/coexistence/summary/health_summary_nutrition_reader.dart';
import 'package:canil_gcm/features/health/data/coexistence/summary/health_summary_recent_records_reader.dart';
import 'package:canil_gcm/features/health/data/coexistence/summary/health_summary_unsafe_sections.dart';
import 'package:canil_gcm/features/health/data/coexistence/summary/health_summary_vaccination_reader.dart';
import 'package:canil_gcm/features/health/data/coexistence/summary/health_summary_weight_reader.dart';
import 'package:canil_gcm/features/health/presentation/summary/health_summary_controller.dart';
import 'package:canil_gcm/features/health/presentation/summary/health_summary_source.dart';
import 'package:canil_gcm/features/health/presentation/summary/health_summary_state.dart';
import 'package:canil_gcm/features/nutrition/domain/feeding.dart';
import 'package:canil_gcm/features/nutrition/domain/nutrition_prescription.dart';

void main() {
  group('HealthSummaryDogContextMapper', () {
    test('mapeia campos cadastrais sem I/O', () {
      final dog = Dog(
        id: 'd1',
        name: 'Bono',
        breed: 'Malinois',
        sex: 'M',
        dateOfBirth: DateTime(2020, 1, 15),
        profileImageUrl: 'https://example.com/b.jpg',
      );
      final ctx = HealthSummaryDogContextMapper.fromDog(
        dog,
        now: DateTime(2026, 7, 15),
      );
      expect(ctx.dogId, 'd1');
      expect(ctx.name, 'Bono');
      expect(ctx.breed, 'Malinois');
      expect(ctx.sexLabel, 'Macho');
      expect(ctx.ageLabel, '6 anos');
      expect(ctx.photoUrl, 'https://example.com/b.jpg');
    });

    test('idade em meses quando < 1 ano', () {
      final label = HealthSummaryDogContextMapper.ageLabelFor(
        DateTime(2026, 1, 1),
        now: DateTime(2026, 7, 15),
      );
      expect(label, '6 meses');
    });

    test('aniversário exato não subtrai ano a mais', () {
      final label = HealthSummaryDogContextMapper.ageLabelFor(
        DateTime(2020, 7, 15),
        now: DateTime(2026, 7, 15),
      );
      expect(label, '6 anos');
    });

    test('DOB futura → ageLabel null', () {
      final label = HealthSummaryDogContextMapper.ageLabelFor(
        DateTime(2030, 1, 1),
        now: DateTime(2026, 7, 15),
      );
      expect(label, isNull);
    });
  });

  group('HealthSummaryDateParse', () {
    test('string ISO e map seconds; inválido → null (sem now inventado)', () {
      expect(
        HealthSummaryDateParse.tryParse('2026-07-01T12:00:00.000'),
        isNotNull,
      );
      expect(
        HealthSummaryDateParse.tryParse({
          'seconds': 1700000000,
          'nanoseconds': 0,
        }),
        isNotNull,
      );
      expect(HealthSummaryDateParse.tryParse('not-a-date'), isNull);
      expect(HealthSummaryDateParse.tryParse(null), isNull);
    });
  });

  group('HealthSummaryWeightReader', () {
    test('available com peso válido; ignora 0 e NaN', () async {
      final reader = HealthSummaryWeightReader(
        loadSamples: (_) async => [
          HealthSummaryWeightSample(
            weightKg: 0,
            measuredAt: DateTime(2026, 1, 1),
          ),
          HealthSummaryWeightSample(
            weightKg: double.nan,
            measuredAt: DateTime(2026, 2, 1),
          ),
          HealthSummaryWeightSample(
            weightKg: 28.5,
            measuredAt: DateTime(2026, 6, 1),
          ),
          HealthSummaryWeightSample(
            weightKg: 29.8,
            measuredAt: DateTime(2026, 7, 1),
          ),
        ],
      );
      final current = await reader.readCurrent('dog-1');
      expect(current.isAvailable, isTrue);
      expect(current.value!.weightKg, 29.8);

      final trend = await reader.readTrend('dog-1');
      expect(trend.isAvailable, isTrue);
      expect(trend.value!.points.length, 2);
      expect(trend.value!.points.first.weightKg, 28.5);
      expect(trend.value!.targetWeightKg, isNull);
      expect(trend.value!.bodyConditionScore, isNull);
    });

    test('notRecorded quando vazio', () async {
      final reader = HealthSummaryWeightReader(loadSamples: (_) async => []);
      expect((await reader.readCurrent('x')).isNotRecorded, isTrue);
      expect((await reader.readTrend('x')).isNotRecorded, isTrue);
    });

    test('unavailable em falha', () async {
      final reader = HealthSummaryWeightReader(
        loadSamples: (_) async => throw StateError('boom'),
      );
      final section = await reader.readCurrent('x');
      expect(section.isUnavailable, isTrue);
      expect(section.message, isNot(contains('boom')));
      expect(section.message?.toLowerCase(), isNot(contains('exception')));
    });
  });

  group('HealthSummaryVaccinationReader', () {
    test('available sem inventar summaryLabel', () async {
      final reader = HealthSummaryVaccinationReader(
        loadFacts: (_) async => [
          HealthSummaryVaccinationFact(
            occurredAt: DateTime(2026, 1, 10),
            name: 'V10',
            nextDueAt: DateTime(2027, 1, 10),
          ),
        ],
      );
      final section = await reader.read('dog-1');
      expect(section.isAvailable, isTrue);
      expect(section.value!.summaryLabel, isNull);
      expect(section.value!.lastRecordLabel, 'V10');
      expect(section.value!.nextDueAt, DateTime(2027, 1, 10));
    });

    test('notRecorded sem fatos', () async {
      final reader = HealthSummaryVaccinationReader(loadFacts: (_) async => []);
      expect((await reader.read('dog-1')).isNotRecorded, isTrue);
    });

    test(
      'unavailable sanitiza erro técnico (sem index/firebase na UI)',
      () async {
        final reader = HealthSummaryVaccinationReader(
          loadFacts: (_) async => throw Exception(
            'The query requires an index. You can create it here: '
            'https://console.firebase.google.com/project/x/indexes',
          ),
        );
        final section = await reader.read('dog-1');
        expect(section.isUnavailable, isTrue);
        final msg = section.message ?? '';
        expect(msg.toLowerCase(), isNot(contains('index')));
        expect(msg.toLowerCase(), isNot(contains('firebase')));
        expect(msg.toLowerCase(), isNot(contains('https://')));
        expect(msg, contains('vacinação'));
      },
    );
  });

  group('HealthSummaryNutritionReader', () {
    test('zero real com prescrição e sem refeições', () async {
      final reader = HealthSummaryNutritionReader(
        loadDaySnapshot: (_) async => HealthSummaryNutritionDaySnapshot(
          feedings: const [],
          prescription: NutritionPrescription(
            amountGramsPerDay: 600,
            mealsPerDay: 3,
            vigentFrom: DateTime(2026, 1, 1),
          ),
        ),
      );
      final section = await reader.readToday('dog-1');
      expect(section.isAvailable, isTrue);
      expect(section.value!.consumedAmount, 0);
      expect(section.value!.plannedAmount, 600);
      expect(section.value!.mealsRecorded, 0);
      expect(section.value!.mealsPlanned, 3);
      expect(section.value!.unitLabel, 'g');
    });

    test('soma consumido real', () async {
      final reader = HealthSummaryNutritionReader(
        loadDaySnapshot: (_) async => HealthSummaryNutritionDaySnapshot(
          feedings: [
            Feeding(
              period: 'manha',
              amountGrams: 250,
              prescriptionAtTime: 600,
              divergencePercent: 0,
              fedAt: DateTime(2026, 7, 15, 8),
              fedBy: 'u1',
            ),
            Feeding(
              period: 'almoco',
              amountGrams: 100,
              prescriptionAtTime: 600,
              divergencePercent: 0,
              fedAt: DateTime(2026, 7, 15, 12),
              fedBy: 'u1',
            ),
          ],
          prescription: NutritionPrescription(
            amountGramsPerDay: 600,
            mealsPerDay: 3,
            vigentFrom: DateTime(2026, 1, 1),
          ),
        ),
      );
      final section = await reader.readToday('dog-1');
      expect(section.value!.consumedAmount, 350);
      expect(section.value!.mealsRecorded, 2);
    });

    test('notRecorded sem plano e sem refeições', () async {
      final reader = HealthSummaryNutritionReader(
        loadDaySnapshot: (_) async => const HealthSummaryNutritionDaySnapshot(
          feedings: [],
          prescription: null,
        ),
      );
      expect((await reader.readToday('dog-1')).isNotRecorded, isTrue);
    });

    test('alimentação sem plano: available sem inventar meta', () async {
      final reader = HealthSummaryNutritionReader(
        loadDaySnapshot: (_) async => HealthSummaryNutritionDaySnapshot(
          feedings: [
            Feeding(
              period: 'manha',
              amountGrams: 200,
              prescriptionAtTime: 0,
              divergencePercent: 0,
              fedAt: DateTime(2026, 7, 15, 8),
              fedBy: 'u1',
            ),
          ],
          prescription: null,
        ),
      );
      final section = await reader.readToday('dog-1');
      expect(section.isAvailable, isTrue);
      expect(section.value!.consumedAmount, 200);
      expect(section.value!.plannedAmount, isNull);
      expect(section.value!.mealsPlanned, isNull);
      expect(section.value!.mealsRecorded, 1);
    });
  });

  group('HealthSummaryRecentRecordsReader', () {
    test('ordena e limita', () async {
      final reader = HealthSummaryRecentRecordsReader(
        limit: 2,
        loadItems: (_) async => [
          HealthSummaryRecentRawItem(
            id: 'a',
            type: 'weight',
            title: 'Pesagem',
            occurredAt: DateTime(2026, 7, 1),
          ),
          HealthSummaryRecentRawItem(
            id: 'b',
            type: 'feeding',
            title: 'Alimentação',
            occurredAt: DateTime(2026, 7, 10),
          ),
          HealthSummaryRecentRawItem(
            id: 'c',
            type: 'consultation',
            title: 'Consulta',
            occurredAt: DateTime(2026, 7, 5),
          ),
        ],
      );
      final section = await reader.read('dog-1');
      expect(section.isAvailable, isTrue);
      expect(section.value!.items.length, 2);
      expect(section.value!.items.first.id, 'b');
    });
  });

  group('HealthSummaryUnsafeSections', () {
    test(
      'prontidão/tratamentos/atenções são unavailable (não notEvaluated inventado)',
      () {
        expect(HealthSummaryUnsafeSections.readiness.isUnavailable, isTrue);
        expect(HealthSummaryUnsafeSections.treatments.isUnavailable, isTrue);
        expect(HealthSummaryUnsafeSections.attention.isUnavailable, isTrue);
        expect(HealthSummaryUnsafeSections.readiness.valueOrNull, isNull);
        // Copy operacional — sem jargão de arquitetura.
        for (final msg in [
          HealthSummaryUnsafeSections.readiness.message,
          HealthSummaryUnsafeSections.treatments.message,
          HealthSummaryUnsafeSections.attention.message,
        ]) {
          final lower = (msg ?? '').toLowerCase();
          expect(lower.contains('coexist'), isFalse);
          expect(lower.contains('legado'), isFalse);
          expect(lower.contains('health v1'), isFalse);
          expect(lower.contains('adapter'), isFalse);
          expect(lower.contains('reader'), isFalse);
        }
      },
    );
  });

  group('CoexistenceHealthSummarySource', () {
    CoexistenceHealthSummarySource buildSource({
      List<HealthSummaryWeightSample> weights = const [],
      List<HealthSummaryVaccinationFact> vaccines = const [],
      HealthSummaryNutritionDaySnapshot? nutrition,
      List<HealthSummaryRecentRawItem> recent = const [],
    }) {
      return CoexistenceHealthSummarySource(
        weightReader: HealthSummaryWeightReader(
          loadSamples: (_) async => weights,
        ),
        vaccinationReader: HealthSummaryVaccinationReader(
          loadFacts: (_) async => vaccines,
        ),
        nutritionReader: HealthSummaryNutritionReader(
          loadDaySnapshot: (_) async =>
              nutrition ??
              const HealthSummaryNutritionDaySnapshot(
                feedings: [],
                prescription: null,
              ),
        ),
        recentRecordsReader: HealthSummaryRecentRecordsReader(
          loadItems: (_) async => recent,
        ),
      );
    }

    test('emite ViewData com dogId correto e blocos parciais', () async {
      final source = buildSource(
        weights: [
          HealthSummaryWeightSample(
            weightKg: 30,
            measuredAt: DateTime(2026, 7, 1),
          ),
        ],
        vaccines: [
          HealthSummaryVaccinationFact(
            occurredAt: DateTime(2026, 1, 1),
            name: 'Antirrábica',
          ),
        ],
      );

      final payload = await source.watchSummary('dog-A').first;
      expect(payload, isNotNull);
      expect(payload!.dogId, 'dog-A');
      expect(payload.weight.isAvailable, isTrue);
      expect(payload.weight.value!.weightKg, 30);
      expect(payload.vaccination.isAvailable, isTrue);
      expect(payload.vaccination.value!.summaryLabel, isNull);
      expect(payload.readiness.isUnavailable, isTrue);
      expect(payload.treatments.isUnavailable, isTrue);
      expect(payload.attention.isUnavailable, isTrue);
      expect(payload.metadata.isFromCache, isFalse);
      expect(payload.metadata.isStale, isFalse);
    });

    test('falha parcial: peso ok, vacina falha → não derruba resumo', () async {
      final source = CoexistenceHealthSummarySource(
        weightReader: HealthSummaryWeightReader(
          loadSamples: (_) async => [
            HealthSummaryWeightSample(
              weightKg: 29,
              measuredAt: DateTime(2026, 6, 1),
            ),
          ],
        ),
        vaccinationReader: HealthSummaryVaccinationReader(
          loadFacts: (_) async => throw StateError('vac fail'),
        ),
        nutritionReader: HealthSummaryNutritionReader(
          loadDaySnapshot: (_) async => const HealthSummaryNutritionDaySnapshot(
            feedings: [],
            prescription: null,
          ),
        ),
        recentRecordsReader: HealthSummaryRecentRecordsReader(
          loadItems: (_) async => [],
        ),
      );

      final payload = await source.watchSummary('dog-1').first;
      expect(payload!.weight.isAvailable, isTrue);
      expect(payload.vaccination.isUnavailable, isTrue);
      expect(payload.readiness.isUnavailable, isTrue);
    });

    test('dogId vazio → stream error', () async {
      final source = buildSource();
      await expectLater(
        source.watchSummary('  '),
        emitsError(isA<ArgumentError>()),
      );
    });

    test(
      'integra com HealthSummaryController sem inventar readiness',
      () async {
        final source = buildSource(
          weights: [
            HealthSummaryWeightSample(
              weightKg: 28,
              measuredAt: DateTime(2026, 5, 1),
            ),
          ],
        );
        final controller = HealthSummaryController(source: source);
        addTearDown(controller.dispose);

        controller.selectDog('dog-9');
        await Future<void>.delayed(const Duration(milliseconds: 20));

        expect(controller.state, isA<HealthSummaryData>());
        final data = (controller.state as HealthSummaryData).data;
        expect(data.dogId, 'dog-9');
        expect(data.weight.isAvailable, isTrue);
        expect(data.readiness.isUnavailable, isTrue);
        // Não há ReadinessStatus inventado
        expect(data.readiness.valueOrNull, isNull);
      },
    );

    test('não confunde notRecorded de peso com 0 kg', () async {
      final source = buildSource(weights: const []);
      final payload = await source.watchSummary('dog-1').first;
      expect(payload!.weight.isNotRecorded, isTrue);
      expect(payload.weight.valueOrNull, isNull);
    });

    test(
      'todas as fontes mapeáveis unavailable → erro global (não HealthSummaryData)',
      () async {
        final source = CoexistenceHealthSummarySource(
          weightReader: HealthSummaryWeightReader(
            loadSamples: (_) async => throw StateError('peso offline'),
          ),
          vaccinationReader: HealthSummaryVaccinationReader(
            loadFacts: (_) async => throw StateError('vac offline'),
          ),
          nutritionReader: HealthSummaryNutritionReader(
            loadDaySnapshot: (_) async => throw StateError('nut offline'),
          ),
          recentRecordsReader: HealthSummaryRecentRecordsReader(
            loadItems: (_) async => throw StateError('rec offline'),
          ),
        );

        await expectLater(
          source.watchSummary('dog-1'),
          emitsError(isA<HealthSummarySourceException>()),
        );
      },
    );

    test(
      'todas networkUnavailable → SourceException isOffline (pós-sanitização)',
      () async {
        // Readers mapeiam FirebaseException code unavailable → networkUnavailable.
        final source = CoexistenceHealthSummarySource(
          weightReader: HealthSummaryWeightReader(
            loadSamples: (_) async {
              throw FirebaseException(
                plugin: 'cloud_firestore',
                code: 'unavailable',
                message: 'Failed to get document because the client is offline',
              );
            },
          ),
          vaccinationReader: HealthSummaryVaccinationReader(
            loadFacts: (_) async {
              throw FirebaseException(
                plugin: 'cloud_firestore',
                code: 'unavailable',
                message: 'offline',
              );
            },
          ),
          nutritionReader: HealthSummaryNutritionReader(
            loadDaySnapshot: (_) async {
              throw FirebaseException(
                plugin: 'cloud_firestore',
                code: 'unavailable',
                message: 'offline',
              );
            },
          ),
          recentRecordsReader: HealthSummaryRecentRecordsReader(
            loadItems: (_) async {
              throw FirebaseException(
                plugin: 'cloud_firestore',
                code: 'unavailable',
                message: 'offline',
              );
            },
          ),
        );

        try {
          await source.watchSummary('dog-1').first;
          fail('esperava SourceException');
        } on HealthSummarySourceException catch (e) {
          expect(e.isOffline, isTrue);
          expect(e.message.toLowerCase(), isNot(contains('firebase')));
        }
      },
    );

    test(
      'controller recebe error/offline e não data quando tudo falha',
      () async {
        final source = CoexistenceHealthSummarySource(
          weightReader: HealthSummaryWeightReader(
            loadSamples: (_) async => throw StateError('peso offline'),
          ),
          vaccinationReader: HealthSummaryVaccinationReader(
            loadFacts: (_) async => throw StateError('vac offline'),
          ),
          nutritionReader: HealthSummaryNutritionReader(
            loadDaySnapshot: (_) async => throw StateError('nut offline'),
          ),
          recentRecordsReader: HealthSummaryRecentRecordsReader(
            loadItems: (_) async => throw StateError('rec offline'),
          ),
        );
        final controller = HealthSummaryController(source: source);
        addTearDown(controller.dispose);
        controller.selectDog('dog-1');
        await Future<void>.delayed(const Duration(milliseconds: 30));
        // Mensagens com "offline" → isOffline no SourceException → Offline.
        expect(
          controller.state is HealthSummaryError ||
              controller.state is HealthSummaryOffline,
          isTrue,
        );
        expect(controller.state, isNot(isA<HealthSummaryData>()));
      },
    );
  });
}
