import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Inicializa Firebase para testes unitários.
/// Chamar em setUpAll() antes de usar qualquer serviço Firebase.
Future<void> setupFirebaseForTest() async {
  TestWidgetsFlutterBinding.ensureInitialized();
  setupFirebaseCoreMocks();
  await Firebase.initializeApp();
}

/// Configura mocks do Firebase Core platform channel.
void setupFirebaseCoreMocks() {
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
    const MethodChannel('plugins.flutter.io/firebase_core'),
    (MethodCall methodCall) async {
      if (methodCall.method == 'Firebase#initializeCore') {
        return [
          {
            'name': '[DEFAULT]',
            'options': {
              'apiKey': 'test-api-key',
              'appId': 'test-app-id',
              'messagingSenderId': 'test-sender-id',
              'projectId': 'test-project-id',
            },
            'pluginConstants': <String, dynamic>{},
          }
        ];
      }
      if (methodCall.method == 'Firebase#initializeApp') {
        return {
          'name': methodCall.arguments['appName'] ?? '[DEFAULT]',
          'options': methodCall.arguments['options'] ?? {},
          'pluginConstants': <String, dynamic>{},
        };
      }
      return null;
    },
  );
}
