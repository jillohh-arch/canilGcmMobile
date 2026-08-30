import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:canil_gcm/features/health/data/coexistence/nutrition/coexistence_nutrition_read_source.dart';
import 'package:canil_gcm/features/health/data/coexistence/nutrition/coexistence_nutrition_read_source_factory.dart';
import 'package:canil_gcm/features/health/data/coexistence/nutrition/firestore_nutrition_canonical_readers.dart';
import 'package:canil_gcm/features/health/domain/nutrition_plan.dart';
import 'package:canil_gcm/features/health/domain/nutrition_read_models.dart';
import 'package:canil_gcm/features/health/domain/nutrition_read_state.dart';
import 'package:canil_gcm/features/health/presentation/nutrition/health_nutrition_read_controller.dart';

/// Integração real: adapters canônicos → Firestore Emulator.
///
/// Só executa quando:
/// ```text
/// HEALTH_NUTRITION_READER_EMULATOR=1
/// ```
/// Orquestrado por:
/// `tools/rules_tests/health_nutrition_canonical_readers_emulator_tests.mjs`
/// sob `firebase emulators:exec --only auth,firestore`.
///
/// Zero produção: hosts Emulator obrigatórios.
void main() {
  final enabled =
      Platform.environment['HEALTH_NUTRITION_READER_EMULATOR'] == '1';

  group('Gate4 Canonical readers — Firestore Emulator real', () {
    if (!enabled) {
      test(
        'skipped fora do orquestrador Emulator '
        '(defina HEALTH_NUTRITION_READER_EMULATOR=1)',
        () {},
        skip:
            'Integração Emulator: rode via tools/rules_tests/'
            'health_nutrition_canonical_readers_emulator_tests.mjs',
      );
      return;
    }

    late _EmuEnv env;
    late FirebaseFirestore db;
    late FirestoreNutritionCanonicalPlanReader planReader;
    late FirestoreNutritionCanonicalMealReader mealReader;
    late FirestoreNutritionCanonicalSupplementLogReader supplementReader;

    setUpAll(() async {
      env = _EmuEnv.fromEnvironment();
      env.assertEmulatorOnly();

      TestWidgetsFlutterBinding.ensureInitialized();
      await Firebase.initializeApp(
        options: FirebaseOptions(
          apiKey: 'fake-api-key-emulator',
          appId: '1:418249404282:android:f1dffc921f41ea6318b0c3',
          messagingSenderId: '418249404282',
          projectId: env.projectId,
          storageBucket: 'canil-gcm.firebasestorage.app',
        ),
      );

      await FirebaseAuth.instance.useAuthEmulator(env.authHost, env.authPort);
      FirebaseFirestore.instance.useFirestoreEmulator(env.fsHost, env.fsPort);
      FirebaseFirestore.instance.settings = const Settings(
        persistenceEnabled: false,
        sslEnabled: false,
      );

      // ignore: avoid_print
      print(
        '[Gate4NutritionReaderEmu] AUTH=${env.authHost}:${env.authPort} '
        'FS=${env.fsHost}:${env.fsPort} project=${env.projectId}',
      );

      await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: env.operatorEmail,
        password: env.operatorPassword,
      );

      db = FirebaseFirestore.instance;
      planReader = FirestoreNutritionCanonicalPlanReader(firestore: db);
      mealReader = FirestoreNutritionCanonicalMealReader(firestore: db);
      supplementReader = FirestoreNutritionCanonicalSupplementLogReader(
        firestore: db,
      );
    });

    tearDownAll(() async {
      await FirebaseAuth.instance.signOut();
    });

    test(
      'canonical plan + meal + supplement visibility (seed Admin)',
      () async {
        final planBatch = await planReader.loadPlans(env.dogValid);
        expect(planBatch.availability, NutritionSourceAvailability.available);
        expect(planBatch.items.map((p) => p.id), contains('plan-valid'));
        expect(planBatch.items.single.status, NutritionPlanStatus.active);

        final mealBatch = await mealReader.loadMeals(env.dogValid);
        expect(mealBatch.availability, NutritionSourceAvailability.available);
        expect(mealBatch.items.map((m) => m.id), contains('meal-valid'));

        final suppBatch = await supplementReader.loadSupplementLogs(
          env.dogValid,
        );
        expect(suppBatch.availability, NutritionSourceAvailability.available);
        expect(suppBatch.items.map((s) => s.id), contains('supp-valid'));

        final source = CoexistenceNutritionReadSourceFactory.forFirestore(
          firestore: db,
        );
        final snap = await source.loadSnapshot(env.dogValid);
        expect(snap.hasUsableValue, isTrue);
        expect(
          snap.value!.canonicalMeals.map((m) => m.id),
          contains('meal-valid'),
        );
        expect(
          snap.value!.canonicalSupplementLogs.map((s) => s.id),
          contains('supp-valid'),
        );
        // Legacy regimen seedado no mesmo dog não se mistura com SupplementLog.
        expect(
          snap.value!.legacySupplementRegimens.map((r) => r.id),
          contains('reg-legacy'),
        );
        expect(
          snap.value!.canonicalSupplementLogs.any((s) => s.id == 'reg-legacy'),
          isFalse,
        );

        final controller = HealthNutritionReadController(source: source);
        await controller.selectDog(env.dogValid);
        expect(controller.snapshotResult.hasUsableValue, isTrue);
        expect(
          controller.snapshotOrNull!.canonicalMeals.map((m) => m.id),
          contains('meal-valid'),
        );
        controller.dispose();
      },
    );

    test('multiple active plans → integrity conflict (Emulator)', () async {
      final batch = await planReader.loadPlans(env.dogMultiActive);
      expect(batch.availability, NutritionSourceAvailability.available);
      expect(
        batch.items.where((p) => p.status == NutritionPlanStatus.active),
        hasLength(2),
      );

      final source = CoexistenceNutritionReadSource(
        canonicalPlanReader: planReader,
      );
      final result = await source.loadSnapshot(env.dogMultiActive);
      expect(result.hasUsableValue, isTrue);
      expect(
        result.value!.activePlan,
        isA<NutritionActivePlanIntegrityConflict>(),
      );
    });

    test('MealLog sem fed_at → integrity failure (não empty)', () async {
      final batch = await mealReader.loadMeals(env.dogMealBroken);
      expect(batch.availability, NutritionSourceAvailability.error);
      expect(batch.code, 'missing_fed_at');
      expect(batch.availability, isNot(NutritionSourceAvailability.empty));
    });

    test(
      'SupplementLog sem administered_at → integrity failure (não empty)',
      () async {
        final batch = await supplementReader.loadSupplementLogs(
          env.dogSuppBroken,
        );
        expect(batch.availability, NutritionSourceAvailability.error);
        expect(batch.code, 'missing_administered_at');
      },
    );

    test('plan malformed → integrity; never healthy empty', () async {
      final batch = await planReader.loadPlans(env.dogPlanBroken);
      expect(batch.availability, NutritionSourceAvailability.error);
      expect(batch.code, isNotNull);
      expect(batch.code, isNot(''));
    });

    test(
      'meal broken + legacy data → coexistence degraded (não empty)',
      () async {
        final source = CoexistenceNutritionReadSourceFactory.forFirestore(
          firestore: db,
        );
        final result = await source.loadSnapshot(env.dogMealBrokenLegacy);
        expect(result.isDegraded || result.isError, isTrue);
        expect(result.isEmpty, isFalse);
        if (result.isDegraded) {
          expect(result.value!.mergedMeals, isNotEmpty);
          expect(
            result.value!.mealSources.any(
              (s) => s.origin == NutritionDataOrigin.canonical && s.isFailure,
            ),
            isTrue,
          );
        }
      },
    );

    test(
      'orderBy fed_at no Emulator exclui doc sem campo; scan do reader não',
      () async {
        // Prova adversarial: query com orderBy (comportamento Firestore real)
        // NÃO retorna o doc broken — o reader canônico não usa essa query.
        final ordered = await db
            .collection('dogs')
            .doc(env.dogMealBroken)
            .collection('meal_logs')
            .orderBy('fed_at', descending: true)
            .get();
        expect(
          ordered.docs.map((d) => d.id),
          isNot(contains('broken-no-fed-at')),
          reason:
              'Firestore Emulator orderBy omite docs sem fed_at — '
              'esta é a armadilha que o scan corrige',
        );

        final scanned = await db
            .collection('dogs')
            .doc(env.dogMealBroken)
            .collection('meal_logs')
            .get();
        expect(scanned.docs.map((d) => d.id), contains('broken-no-fed-at'));

        final batch = await mealReader.loadMeals(env.dogMealBroken);
        expect(batch.availability, NutritionSourceAvailability.error);
        expect(batch.code, 'missing_fed_at');
      },
    );
  });
}

final class _EmuEnv {
  _EmuEnv({
    required this.projectId,
    required this.authHost,
    required this.authPort,
    required this.fsHost,
    required this.fsPort,
    required this.operatorEmail,
    required this.operatorPassword,
    required this.dogValid,
    required this.dogMultiActive,
    required this.dogMealBroken,
    required this.dogSuppBroken,
    required this.dogPlanBroken,
    required this.dogMealBrokenLegacy,
  });

  final String projectId;
  final String authHost;
  final int authPort;
  final String fsHost;
  final int fsPort;
  final String operatorEmail;
  final String operatorPassword;
  final String dogValid;
  final String dogMultiActive;
  final String dogMealBroken;
  final String dogSuppBroken;
  final String dogPlanBroken;
  final String dogMealBrokenLegacy;

  factory _EmuEnv.fromEnvironment() {
    final auth =
        Platform.environment['FIREBASE_AUTH_EMULATOR_HOST'] ?? '127.0.0.1:9099';
    final fs =
        Platform.environment['FIRESTORE_EMULATOR_HOST'] ?? '127.0.0.1:8080';
    final authParts = auth.replaceFirst(RegExp(r'^https?://'), '').split(':');
    final fsParts = fs.replaceFirst(RegExp(r'^https?://'), '').split(':');
    return _EmuEnv(
      projectId:
          Platform.environment['GCLOUD_PROJECT'] ??
          Platform.environment['GCLOUD_PROJECT_ID'] ??
          'canil-gcm',
      authHost: authParts[0],
      authPort: authParts.length > 1 ? int.parse(authParts[1]) : 9099,
      fsHost: fsParts[0],
      fsPort: fsParts.length > 1 ? int.parse(fsParts[1]) : 8080,
      operatorEmail:
          Platform.environment['G4_NUTRITION_OP_EMAIL'] ?? '691755@gcm.com.br',
      operatorPassword:
          Platform.environment['G4_NUTRITION_OP_PASSWORD'] ??
          'Gate4-Reader-Emulator-Only-Not-Prod!',
      dogValid: 'dog-nutrition-reader-valid',
      dogMultiActive: 'dog-nutrition-reader-multi',
      dogMealBroken: 'dog-nutrition-reader-meal-broken',
      dogSuppBroken: 'dog-nutrition-reader-supp-broken',
      dogPlanBroken: 'dog-nutrition-reader-plan-broken',
      dogMealBrokenLegacy: 'dog-nutrition-reader-meal-legacy',
    );
  }

  void assertEmulatorOnly() {
    for (final h in [authHost, fsHost]) {
      final ok =
          h.contains('127.0.0.1') ||
          h.contains('localhost') ||
          h.startsWith('10.0.2.2');
      if (!ok) {
        throw StateError(
          'Recusa: host não-Emulator ($h). Suíte não pode apontar para produção.',
        );
      }
    }
  }
}
