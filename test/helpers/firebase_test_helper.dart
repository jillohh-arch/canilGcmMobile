import 'package:firebase_core/firebase_core.dart';
// ignore: depend_on_referenced_packages
import 'package:firebase_core_platform_interface/firebase_core_platform_interface.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Plataforma falsa em memória para isolar testes unitários/widget do Firebase Core.
/// Impede que chamadas caiam nos canais Pigeon não mockados do host (`FirebaseCoreHostApi`).
class FakeFirebasePlatform extends FirebasePlatform {
  FakeFirebasePlatform({FirebaseAppPlatform? app})
    : _app = app ?? FakeFirebaseAppPlatform();

  FirebaseAppPlatform _app;

  @override
  List<FirebaseAppPlatform> get apps => <FirebaseAppPlatform>[_app];

  @override
  FirebaseAppPlatform app([String name = defaultFirebaseAppName]) => _app;

  @override
  Future<FirebaseAppPlatform> initializeApp({
    String? name,
    FirebaseOptions? options,
  }) async {
    if (options != null) {
      _app = FakeFirebaseAppPlatform(
        name: name ?? defaultFirebaseAppName,
        options: options,
      );
    }
    return _app;
  }
}

/// Aplicação Firebase falsa em memória com opções de teste canônicas.
class FakeFirebaseAppPlatform extends FirebaseAppPlatform {
  FakeFirebaseAppPlatform({
    String name = defaultFirebaseAppName,
    FirebaseOptions options = const FirebaseOptions(
      apiKey: 'test-api-key',
      appId: 'test-app-id',
      messagingSenderId: 'test-sender-id',
      projectId: 'test-project-id',
    ),
  }) : super(name, options);

  @override
  Future<void> delete() async {}
}

FirebasePlatform? _originalFirebasePlatform;

/// Configura mocks do Firebase Core platform interface.
/// Registra [FakeFirebasePlatform] no `FirebasePlatform.instance` e sincroniza
/// `Firebase.delegatePackingProperty` para garantir que inicializações de teste
/// sejam 100% herméticas, rápidas e imunes a `channel-error`.
void setupFirebaseCoreMocks({
  String apiKey = 'test-api-key',
  String appId = 'test-app-id',
  String messagingSenderId = 'test-sender-id',
  String projectId = 'test-project-id',
}) {
  TestWidgetsFlutterBinding.ensureInitialized();

  // Mantém handler no MethodChannel legado para plugins legados que ainda o consultem
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
        const MethodChannel('plugins.flutter.io/firebase_core'),
        (MethodCall methodCall) async {
          if (methodCall.method == 'Firebase#initializeCore') {
            return [
              {
                'name': defaultFirebaseAppName,
                'options': {
                  'apiKey': apiKey,
                  'appId': appId,
                  'messagingSenderId': messagingSenderId,
                  'projectId': projectId,
                },
                'pluginConstants': <String, dynamic>{},
              },
            ];
          }
          if (methodCall.method == 'Firebase#initializeApp') {
            return {
              'name': methodCall.arguments['appName'] ?? defaultFirebaseAppName,
              'options': methodCall.arguments['options'] ?? {},
              'pluginConstants': <String, dynamic>{},
            };
          }
          return null;
        },
      );

  // Instala plataforma canônica hermética (Pigeon-safe)
  _originalFirebasePlatform ??= FirebasePlatform.instance;
  final fakePlatform = FakeFirebasePlatform(
    app: FakeFirebaseAppPlatform(
      options: FirebaseOptions(
        apiKey: apiKey,
        appId: appId,
        messagingSenderId: messagingSenderId,
        projectId: projectId,
      ),
    ),
  );
  FirebasePlatform.instance = fakePlatform;
  Firebase.delegatePackingProperty = fakePlatform;
}

/// Restaura o [FirebasePlatform] original e descarta apps registrados em memória.
Future<void> tearDownFirebaseCoreMocks() async {
  try {
    for (final app in List<FirebaseApp>.from(Firebase.apps)) {
      await app.delete();
    }
  } catch (_) {}

  if (_originalFirebasePlatform != null) {
    FirebasePlatform.instance = _originalFirebasePlatform!;
    Firebase.delegatePackingProperty = null;
    _originalFirebasePlatform = null;
  }
}

/// Inicializa Firebase para testes unitários com valores herméticos em memória.
/// Chamar em setUpAll() antes de usar qualquer serviço dependente do Firebase Core.
Future<void> setupFirebaseForTest({
  String apiKey = 'test-api-key',
  String appId = 'test-app-id',
  String messagingSenderId = 'test-sender-id',
  String projectId = 'test-project-id',
}) async {
  setupFirebaseCoreMocks(
    apiKey: apiKey,
    appId: appId,
    messagingSenderId: messagingSenderId,
    projectId: projectId,
  );
  await Firebase.initializeApp();
}
