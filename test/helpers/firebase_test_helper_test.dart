import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:firebase_core/firebase_core.dart';
// ignore: depend_on_referenced_packages
import 'package:firebase_core_platform_interface/firebase_core_platform_interface.dart';
import 'firebase_test_helper.dart';

void main() {
  group('FirebaseTestHelper — Pigeon & Platform Isolation Regression Suite', () {
    tearDown(() async {
      await tearDownFirebaseCoreMocks();
    });

    test(
      '1. setupFirebaseForTest inicializa Firebase hermeticamente sem channel-error',
      () async {
        await setupFirebaseForTest();

        expect(Firebase.apps, isNotEmpty);
        final defaultApp = Firebase.app();
        expect(defaultApp.name, equals(defaultFirebaseAppName));
        expect(defaultApp.options.apiKey, equals('test-api-key'));
        expect(defaultApp.options.appId, equals('test-app-id'));
        expect(defaultApp.options.messagingSenderId, equals('test-sender-id'));
        expect(defaultApp.options.projectId, equals('test-project-id'));
      },
    );

    test(
      '2. Suporta credenciais e project id customizados na inicializacao',
      () async {
        await setupFirebaseForTest(
          apiKey: 'custom-key',
          appId: 'custom-app',
          messagingSenderId: 'custom-sender',
          projectId: 'custom-project',
        );

        expect(Firebase.apps, isNotEmpty);
        final app = Firebase.app();
        expect(app.options.apiKey, equals('custom-key'));
        expect(app.options.appId, equals('custom-app'));
        expect(app.options.projectId, equals('custom-project'));
      },
    );

    test(
      '3. tearDownFirebaseCoreMocks restaura o estado de plataforma',
      () async {
        setupFirebaseCoreMocks(projectId: 'temp-project');
        expect(FirebasePlatform.instance, isA<FakeFirebasePlatform>());

        await tearDownFirebaseCoreMocks();
        expect(FirebasePlatform.instance, isNot(isA<FakeFirebasePlatform>()));
      },
    );

    test(
      '4. Compatibilidade com MethodChannel legado mantida para plugins antigos',
      () async {
        setupFirebaseCoreMocks(apiKey: 'compat-key', projectId: 'compat-proj');

        const channel = MethodChannel('plugins.flutter.io/firebase_core');
        final decoded = await channel.invokeListMethod<Map<dynamic, dynamic>>(
          'Firebase#initializeCore',
        );

        expect(decoded, isNotNull);
        expect(decoded, isNotEmpty);
        expect(decoded!.first['name'], equals(defaultFirebaseAppName));
        expect(decoded.first['options']['apiKey'], equals('compat-key'));
      },
    );
  });
}
