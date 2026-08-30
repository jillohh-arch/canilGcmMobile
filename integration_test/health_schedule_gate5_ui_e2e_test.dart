import 'dart:convert';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:integration_test/integration_test.dart';

import 'package:canil_gcm/core/theme/app_theme.dart';
import 'package:canil_gcm/features/health/data/coexistence/schedule/firestore_health_schedule_source.dart';
import 'package:canil_gcm/features/health/data/schedule/firebase_functions_health_schedule_mutation_gateway.dart';
import 'package:canil_gcm/features/health/domain/health_schedule_mutation_gateway.dart';
import 'package:canil_gcm/features/health/presentation/schedule/health_schedule_controller.dart';
import 'package:canil_gcm/features/health/presentation/schedule/health_schedule_mutation_controller.dart';
import 'package:canil_gcm/features/health/presentation/schedule/health_schedule_mutation_user_copy.dart';
import 'package:canil_gcm/features/health/presentation/schedule/health_schedule_presentation_policy.dart';
import 'package:canil_gcm/features/health/presentation/schedule/health_schedule_query.dart';
import 'package:canil_gcm/features/health/presentation/schedule/health_schedule_view.dart';
import 'package:canil_gcm/features/health/presentation/schedule/widgets/health_schedule_user_copy.dart';
import 'package:canil_gcm/main.dart' show globalScaffoldMessengerKey;

/// Gate 5 — UI E2E real no device Android → Firebase Emulators.
///
/// Só executa com:
/// ```text
/// HEALTH_SCHEDULE_UI_E2E=1
/// ```
/// e hosts Emulator (via env / adb reverse 127.0.0.1).
///
/// Fluxo:
/// UI → MutationController → Gateway → Functions Emulator
/// → Firestore Emulator → FirestoreHealthScheduleSource.refresh → UI
void main() {
  final enabled = Platform.environment['HEALTH_SCHEDULE_UI_E2E'] == '1';
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('Gate5 UI E2E Emulator', () {
    if (!enabled) {
      // Orquestre via tools/rules_tests/health_schedule_ui_e2e_emulator_tests.mjs
      testWidgets(
        'skipped sem HEALTH_SCHEDULE_UI_E2E=1',
        (tester) async {},
        skip: true,
      );
      return;
    }

    late _Gate5Env env;
    late HealthScheduleController schedule;
    late HealthScheduleMutationController mutation;
    late HealthScheduleMutationGateway gateway;

    setUpAll(() async {
      GoogleFonts.config.allowRuntimeFetching = false;
      env = _Gate5Env.fromEnvironment();
      env.assertEmulatorOnly();

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
      FirebaseFunctions.instanceFor(
        region: 'southamerica-east1',
      ).useFunctionsEmulator(env.fnHost, env.fnPort);

      // ignore: avoid_print
      print(
        '[Gate5UiE2E] AUTH=${env.authHost}:${env.authPort} '
        'FS=${env.fsHost}:${env.fsPort} FN=${env.fnHost}:${env.fnPort} '
        'project=${env.projectId} dog=${env.dogId}',
      );

      await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: env.operatorEmail,
        password: env.operatorPassword,
      );

      final source = FirestoreHealthScheduleSource(
        firestore: FirebaseFirestore.instance,
      );
      schedule = HealthScheduleController(
        source: source,
        temporalPolicy: healthSchedulePresentationPolicy(),
      );
      gateway = FirebaseFunctionsHealthScheduleMutationGateway(
        functions: FirebaseFunctions.instanceFor(
          region: 'southamerica-east1',
        ),
      );
      mutation = HealthScheduleMutationController(
        gateway: gateway,
        scheduleController: schedule,
      );
    });

    tearDownAll(() async {
      mutation.dispose();
      schedule.dispose();
      await FirebaseAuth.instance.signOut();
    });

    testWidgets(
      'create → edit → complete → cancel + auto menu + refresh real',
      (tester) async {
        await schedule.setQuery(HealthScheduleQuery(dogId: env.dogId));

        await tester.pumpWidget(_wrapAgenda(schedule, mutation));
        await tester.pumpAndSettle(const Duration(seconds: 3));

        // --- empty or seeded list: automatic open should be visible ---
        expect(
          find.text(HealthScheduleUserCopy.title),
          findsOneWidget,
        );
        expect(find.textContaining('Dose protocolo'), findsOneWidget);
        expect(
          find.text(HealthScheduleMutationUserCopy.generatedAutomatically),
          findsWidgets,
        );

        await _screenshot(binding, '01_agenda_initial_with_auto');

        // Auto menu: only Complete
        final autoCard = find.byKey(const ValueKey('schedule-card-seed-auto-open'));
        expect(autoCard, findsOneWidget);
        await tester.tap(
          find.descendant(
            of: autoCard,
            matching: find.byKey(const ValueKey('schedule-item-actions')),
          ),
        );
        await tester.pumpAndSettle();
        expect(
          find.text(HealthScheduleMutationUserCopy.actionEdit),
          findsNothing,
        );
        expect(
          find.text(HealthScheduleMutationUserCopy.actionCancel),
          findsNothing,
        );
        expect(
          find.text(HealthScheduleMutationUserCopy.actionComplete),
          findsOneWidget,
        );
        await _screenshot(binding, '02_menu_automatic_open');
        // dismiss menu
        await tester.tapAt(const Offset(10, 10));
        await tester.pumpAndSettle();

        // ========== CREATE ==========
        await tester.tap(find.byKey(const ValueKey('schedule-add-button')).first);
        await tester.pumpAndSettle();
        expect(
          find.text(HealthScheduleMutationUserCopy.createFormTitle),
          findsOneWidget,
        );
        await _screenshot(binding, '03_form_create');

        // validation
        await tester.tap(find.text(HealthScheduleMutationUserCopy.saveLabel));
        await tester.pumpAndSettle();
        expect(
          find.text(HealthScheduleMutationUserCopy.titleRequired),
          findsOneWidget,
        );

        await tester.enterText(
          find.byKey(const ValueKey('schedule-form-title')),
          'Vacina Gate5 UI E2E',
        );
        await tester.enterText(
          find.byKey(const ValueKey('schedule-form-notes')),
          'nota e2e gate5',
        );
        await tester.pumpAndSettle();

        await tester.tap(find.text(HealthScheduleMutationUserCopy.saveLabel));
        await tester.pumpAndSettle(const Duration(seconds: 8));

        // back on agenda with new item
        expect(find.text('Vacina Gate5 UI E2E'), findsOneWidget);
        await _screenshot(binding, '04_agenda_after_create');

        final afterCreate = await _openDocs(env.dogId);
        final created = afterCreate.where(
          (d) => d['title'] == 'Vacina Gate5 UI E2E',
        );
        expect(created.length, 1);
        final createId = created.first['id'] as String;
        expect(created.first['revision'], 1);
        expect(created.first['lifecycle_status'], 'open');
        expect(created.first['source_type'], 'manual');

        // ========== EDIT ==========
        final createdCard = find.byKey(ValueKey('schedule-card-$createId'));
        expect(createdCard, findsOneWidget);
        await tester.tap(
          find.descendant(
            of: createdCard,
            matching: find.byKey(const ValueKey('schedule-item-actions')),
          ),
        );
        await tester.pumpAndSettle();
        await _screenshot(binding, '05_menu_manual_open');
        await tester.tap(find.text(HealthScheduleMutationUserCopy.actionEdit));
        await tester.pumpAndSettle();
        expect(
          find.text(HealthScheduleMutationUserCopy.editFormTitle),
          findsOneWidget,
        );
        await _screenshot(binding, '06_form_edit');

        await tester.enterText(
          find.byKey(const ValueKey('schedule-form-title')),
          'Vacina Gate5 UI E2E EDITADA',
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text(HealthScheduleMutationUserCopy.saveLabel));
        await tester.pumpAndSettle(const Duration(seconds: 8));

        expect(find.text('Vacina Gate5 UI E2E EDITADA'), findsOneWidget);
        await _screenshot(binding, '07_agenda_after_edit');

        final afterEdit = await _doc(env.dogId, createId);
        expect(afterEdit['revision'], 2);
        expect(afterEdit['title'], 'Vacina Gate5 UI E2E EDITADA');

        // ========== COMPLETE ==========
        await tester.tap(
          find.descendant(
            of: find.byKey(ValueKey('schedule-card-$createId')),
            matching: find.byKey(const ValueKey('schedule-item-actions')),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text(HealthScheduleMutationUserCopy.actionComplete));
        await tester.pumpAndSettle();
        expect(
          find.text(HealthScheduleMutationUserCopy.completeTitle),
          findsOneWidget,
        );
        await _screenshot(binding, '08_dialog_complete');
        await tester.tap(find.byKey(const ValueKey('schedule-complete-confirm')));
        await tester.pumpAndSettle(const Duration(seconds: 8));

        // open-only source: item some da lista
        expect(find.text('Vacina Gate5 UI E2E EDITADA'), findsNothing);
        await _screenshot(binding, '09_agenda_after_complete');

        final afterComplete = await _doc(env.dogId, createId);
        expect(afterComplete['lifecycle_status'], 'completed');

        // ========== CANCEL (segundo item) ==========
        await tester.tap(find.byKey(const ValueKey('schedule-add-button')).first);
        await tester.pumpAndSettle();
        await tester.enterText(
          find.byKey(const ValueKey('schedule-form-title')),
          'Item para cancelar Gate5',
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text(HealthScheduleMutationUserCopy.saveLabel));
        await tester.pumpAndSettle(const Duration(seconds: 8));
        expect(find.text('Item para cancelar Gate5'), findsOneWidget);

        final afterCancelCreate = await _openDocs(env.dogId);
        final cancelTarget = afterCancelCreate.firstWhere(
          (d) => d['title'] == 'Item para cancelar Gate5',
        );
        final cancelId = cancelTarget['id'] as String;

        await tester.tap(
          find.descendant(
            of: find.byKey(ValueKey('schedule-card-$cancelId')),
            matching: find.byKey(const ValueKey('schedule-item-actions')),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text(HealthScheduleMutationUserCopy.actionCancel));
        await tester.pumpAndSettle();
        expect(
          find.text(HealthScheduleMutationUserCopy.cancelSheetTitle),
          findsOneWidget,
        );
        await _screenshot(binding, '10_sheet_cancel');

        // spaces only rejected
        await tester.enterText(
          find.byKey(const ValueKey('schedule-cancel-reason')),
          '   ',
        );
        await tester.tap(find.byKey(const ValueKey('schedule-cancel-confirm')));
        await tester.pumpAndSettle();
        expect(
          find.text(HealthScheduleMutationUserCopy.cancelReasonRequired),
          findsOneWidget,
        );

        await tester.enterText(
          find.byKey(const ValueKey('schedule-cancel-reason')),
          'Duplicado no e2e Gate5',
        );
        await tester.tap(find.byKey(const ValueKey('schedule-cancel-confirm')));
        await tester.pumpAndSettle(const Duration(seconds: 8));

        expect(find.text('Item para cancelar Gate5'), findsNothing);
        await _screenshot(binding, '11_agenda_after_cancel');

        final afterCancel = await _doc(env.dogId, cancelId);
        expect(afterCancel['lifecycle_status'], 'cancelled');
        expect(afterCancel['cancel_reason'], 'Duplicado no e2e Gate5');

        // Terminal seed: completed doc not in open list, no mutation menu for auto remaining only
        // seed-completed / seed-cancelled are not open so not in list — OK

        // ignore: avoid_print
        print(
          'GATE5_UI_E2E '
          '${jsonEncode({
            'createId': createId,
            'cancelId': cancelId,
            'createRevision': 1,
            'editRevision': 2,
            'dogId': env.dogId,
          })}',
        );
      },
      timeout: const Timeout(Duration(minutes: 6)),
    );
  });
}

Widget _wrapAgenda(
  HealthScheduleController schedule,
  HealthScheduleMutationController mutation,
) {
  return MaterialApp(
    scaffoldMessengerKey: globalScaffoldMessengerKey,
    theme: AppTheme.darkTheme,
    home: Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: const Text('Gate5 Emulator UI'),
        backgroundColor: AppTheme.surfacePanel,
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: HealthScheduleView(
            controller: schedule,
            mutationController: mutation,
            dogDisplayName: 'Rex Gate5 UI',
            recomputeInterval: Duration.zero,
            bottomPadding: 16,
          ),
        ),
      ),
    ),
  );
}

Future<void> _screenshot(
  IntegrationTestWidgetsFlutterBinding binding,
  String name,
) async {
  try {
    await binding.takeScreenshot(name);
  } catch (e) {
    // ignore: avoid_print
    print('[Gate5UiE2E] screenshot $name skipped: $e');
  }
}

Future<List<Map<String, dynamic>>> _openDocs(String dogId) async {
  final snap = await FirebaseFirestore.instance
      .collection('dogs')
      .doc(dogId)
      .collection('health_schedule')
      .where('lifecycle_status', isEqualTo: 'open')
      .get();
  return [
    for (final d in snap.docs) {'id': d.id, ...d.data()},
  ];
}

Future<Map<String, dynamic>> _doc(String dogId, String scheduleId) async {
  final snap = await FirebaseFirestore.instance
      .collection('dogs')
      .doc(dogId)
      .collection('health_schedule')
      .doc(scheduleId)
      .get();
  return {'id': snap.id, ...?snap.data()};
}

final class _Gate5Env {
  _Gate5Env({
    required this.projectId,
    required this.authHost,
    required this.authPort,
    required this.fsHost,
    required this.fsPort,
    required this.fnHost,
    required this.fnPort,
    required this.dogId,
    required this.operatorEmail,
    required this.operatorPassword,
  });

  final String projectId;
  final String authHost;
  final int authPort;
  final String fsHost;
  final int fsPort;
  final String fnHost;
  final int fnPort;
  final String dogId;
  final String operatorEmail;
  final String operatorPassword;

  factory _Gate5Env.fromEnvironment() {
    final auth = _parseHostPort(
      Platform.environment['FIREBASE_AUTH_EMULATOR_HOST'] ?? '127.0.0.1:9099',
      9099,
    );
    final fs = _parseHostPort(
      Platform.environment['FIRESTORE_EMULATOR_HOST'] ?? '127.0.0.1:8080',
      8080,
    );
    final fn = _parseHostPort(
      Platform.environment['FIREBASE_FUNCTIONS_EMULATOR_HOST'] ??
          '127.0.0.1:5001',
      5001,
    );
    return _Gate5Env(
      projectId:
          Platform.environment['GCLOUD_PROJECT'] ??
          Platform.environment['GCLOUD_PROJECT_ID'] ??
          'canil-gcm',
      authHost: auth.host,
      authPort: auth.port,
      fsHost: fs.host,
      fsPort: fs.port,
      fnHost: fn.host,
      fnPort: fn.port,
      dogId: Platform.environment['GATE5_DOG_ID'] ?? 'dog-gate5-ui-a',
      operatorEmail:
          Platform.environment['GATE5_OP_EMAIL'] ?? '691755@gcm.com.br',
      operatorPassword:
          Platform.environment['GATE5_OP_PASSWORD'] ??
          'Gate5-Emulator-Only-Not-Prod!',
    );
  }

  void assertEmulatorOnly() {
    for (final h in [authHost, fsHost, fnHost]) {
      final ok =
          h.contains('127.0.0.1') ||
          h.contains('localhost') ||
          h.startsWith('10.0.2.2');
      if (!ok) {
        throw StateError('Host não-Emulator detectado: $h');
      }
    }
  }

  static ({String host, int port}) _parseHostPort(String raw, int fallback) {
    final cleaned = raw.replaceFirst(RegExp(r'^https?://'), '');
    final parts = cleaned.split(':');
    if (parts.length >= 2) {
      return (host: parts[0], port: int.tryParse(parts[1]) ?? fallback);
    }
    return (host: cleaned, port: fallback);
  }
}
