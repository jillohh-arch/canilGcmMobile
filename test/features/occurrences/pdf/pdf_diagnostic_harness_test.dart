// FF-OCC-10 — REGRESSION TEST: PDF Diagnostic Harness teardown and global state restoration.
//
// Verifies that:
// - HARNESS-1: installHermeticPdfHarness() properly establishes hermetic isolation.
// - HARNESS-2: uninstallHermeticPdfHarness() restores original global instances:
//              FirebasePlatform.instance, PdfBaseCache.defaultCache, HttpOverrides.global.
// - HARNESS-3: channel call registries and blocked network lists are cleared on teardown.
// - HARNESS-4: uninstallHermeticPdfHarness() is idempotent.
// - HARNESS-5: runWithHermeticPdfHarness() guarantees cleanup even on uncaught errors.

import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
// ignore: depend_on_referenced_packages
import 'package:firebase_core_platform_interface/firebase_core_platform_interface.dart';
import 'package:printing/printing.dart';

import 'pdf_diagnostic_harness.dart';

class _SentinelCache extends OfflinePdfCache {}

class _SentinelHttpOverrides extends HttpOverrides {}

class _SentinelFirebasePlatform extends FirebasePlatform {
  @override
  List<FirebaseAppPlatform> get apps => const [];
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('FF-OCC-10 — PDF Diagnostic Harness Isolation & Teardown', () {
    test(
      'HARNESS-1 & HARNESS-2: install overrides globals and uninstall cleanly restores them',
      () async {
        final sentinelCache = _SentinelCache();
        final sentinelHttp = _SentinelHttpOverrides();
        final sentinelFirebase = _SentinelFirebasePlatform();

        // Pre-set sentinel values into process globals
        PdfBaseCache.defaultCache = sentinelCache;
        HttpOverrides.global = sentinelHttp;
        FirebasePlatform.instance = sentinelFirebase;

        expect(PdfBaseCache.defaultCache, same(sentinelCache));
        expect(HttpOverrides.current, same(sentinelHttp));
        expect(FirebasePlatform.instance, same(sentinelFirebase));

        // Install harness
        await installHermeticPdfHarness();

        // Verify globals were overridden
        expect(PdfBaseCache.defaultCache, isNot(same(sentinelCache)));
        expect(HttpOverrides.current, isNot(same(sentinelHttp)));
        expect(FirebasePlatform.instance, isNot(same(sentinelFirebase)));

        // Uninstall harness
        uninstallHermeticPdfHarness();

        // Verify globals were restored
        expect(PdfBaseCache.defaultCache, same(sentinelCache));
        expect(HttpOverrides.current, same(sentinelHttp));
        expect(FirebasePlatform.instance, same(sentinelFirebase));
      },
    );

    test('HARNESS-3: registries are reset and emptied upon teardown', () async {
      await installHermeticPdfHarness();

      firestoreChannelCalls.add('synthetic-call');
      attemptedNetworkHosts.add('synthetic-host.com');
      expect(firestoreChannelCalls, isNotEmpty);
      expect(attemptedNetworkHosts, isNotEmpty);

      uninstallHermeticPdfHarness();

      expect(firestoreChannelCalls, isEmpty);
      expect(attemptedNetworkHosts, isEmpty);
    });

    test(
      'HARNESS-4: uninstallHermeticPdfHarness is safely idempotent',
      () async {
        await installHermeticPdfHarness();
        uninstallHermeticPdfHarness();
        // Second call must not throw or alter globals unexpectedly
        expect(() => uninstallHermeticPdfHarness(), returnsNormally);
        expect(() => uninstallHermeticPdfHarness(), returnsNormally);
      },
    );

    test(
      'HARNESS-5: runWithHermeticPdfHarness restores state even when body throws',
      () async {
        final sentinelCache = _SentinelCache();
        PdfBaseCache.defaultCache = sentinelCache;

        try {
          await runWithHermeticPdfHarness(() async {
            expect(PdfBaseCache.defaultCache, isNot(same(sentinelCache)));
            throw Exception('Intentional failure inside harness');
          });
        } catch (e) {
          expect(e.toString(), contains('Intentional failure inside harness'));
        }

        // Verify restoration happened despite exception
        expect(PdfBaseCache.defaultCache, same(sentinelCache));
      },
    );
  });
}
