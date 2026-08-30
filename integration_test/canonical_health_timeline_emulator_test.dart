import 'dart:convert';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:integration_test/integration_test.dart';

import 'package:canil_gcm/features/health/data/canonical/timeline/firestore_canonical_health_timeline_source.dart';
import 'package:canil_gcm/features/health/domain/health_v1_enums_ext.dart';
import 'package:canil_gcm/features/health/presentation/timeline/health_timeline_query.dart';
import 'package:canil_gcm/features/health/presentation/timeline/health_timeline_source.dart';

const platformGateEnabled = bool.fromEnvironment(
  'HEALTH_TIMELINE_PLATFORM_EMULATOR_GATE',
  defaultValue: false,
);

const platformTarget = String.fromEnvironment(
  'HEALTH_TIMELINE_PLATFORM_TARGET',
  defaultValue: '',
);

const emulatorHost = String.fromEnvironment(
  'HEALTH_TIMELINE_EMULATOR_HOST',
  defaultValue: '',
);

const fixtureHost = String.fromEnvironment(
  'HEALTH_TIMELINE_FIXTURE_HOST',
  defaultValue: '',
);

const fixturePort = int.fromEnvironment(
  'HEALTH_TIMELINE_FIXTURE_PORT',
  defaultValue: 0,
);

const fixtureToken = String.fromEnvironment(
  'HEALTH_TIMELINE_FIXTURE_TOKEN',
  defaultValue: '',
);

/// Testes do [FirestoreCanonicalHealthTimelineSource] contra os Emulators reais
/// em plataforma Android (Emulador AVD ou Dispositivo Físico) utilizando Host Fixture Server.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('CANONICAL HEALTH TIMELINE — FLUTTER PLATFORM GATE', () {
    late _EmulatorTestEnv env;
    late FirestoreCanonicalHealthTimelineSource source;

    setUpAll(() async {
      if (!platformGateEnabled) {
        throw StateError(
          'HEALTH_TIMELINE_PLATFORM_EMULATOR_GATE must be enabled',
        );
      }

      if (!Platform.isAndroid) {
        throw StateError('Canonical Timeline platform gate requires Android');
      }

      if (platformTarget == 'android-emulator') {
        if (emulatorHost != '10.0.2.2') {
          throw StateError(
            'Canonical Timeline platform target android-emulator requires host 10.0.2.2',
          );
        }
      } else if (platformTarget == 'android-physical') {
        if (emulatorHost != '127.0.0.1') {
          throw StateError(
            'Canonical Timeline platform target android-physical requires host 127.0.0.1',
          );
        }
        if (fixtureHost != '127.0.0.1' ||
            fixturePort != 8787 ||
            fixtureToken.isEmpty) {
          throw StateError(
            'android-physical requires fixtureHost=127.0.0.1, fixturePort=8787 and non-empty token',
          );
        }
      } else {
        throw StateError(
          'Unsupported platformTarget: "$platformTarget". Expected "android-emulator" or "android-physical".',
        );
      }

      env = _EmulatorTestEnv(
        projectId: 'canil-gcm',
        authHost: emulatorHost,
        authPort: 9099,
        fsHost: emulatorHost,
        fsPort: 8080,
        fixHost: fixtureHost.isNotEmpty ? fixtureHost : emulatorHost,
        fixPort: fixturePort > 0 ? fixturePort : 8787,
        token: fixtureToken,
        ra: '691755',
        email: '691755@gcm.com.br',
        password: 'Gate5-Timeline-Emulator-Pass!',
      );
      env.assertEmulatorOnly();

      await Firebase.initializeApp();

      await FirebaseAuth.instance.useAuthEmulator(
        emulatorHost,
        9099,
        automaticHostMapping: false,
      );

      FirebaseFirestore.instance.useFirestoreEmulator(
        emulatorHost,
        8080,
        automaticHostMapping: false,
      );

      FirebaseFirestore.instance.settings = const Settings(
        persistenceEnabled: false,
        sslEnabled: false,
      );

      // 1. Reseta e garante profile/user fixtures via Host Fixture Server
      await env.invokeFixture('reset');

      // 2. Garante usuário de teste no Auth Emulator e faz login client-side
      await env.ensureAuthUserAndSignIn();

      source = FirestoreCanonicalHealthTimelineSource(
        firestore: FirebaseFirestore.instance,
      );
    });

    tearDownAll(() async {
      try {
        await FirebaseAuth.instance.signOut();
      } catch (_) {}
    });

    // ------------------------------------------------------------------------
    // E1 — Empty válido
    // ------------------------------------------------------------------------
    test('E1 — Empty válido: subcoleção inexistente ou vazia', () async {
      const dogId = 'dog-emu-e1';
      await env.invokeFixture('e1');

      final query = HealthTimelineQuery(dogId: dogId, pageSize: 10);
      final page = await source.loadPage(query);

      expect(page.items, isEmpty);
      expect(page.hasMore, isFalse);
      expect(page.nextCursor, isNull);
    });

    // ------------------------------------------------------------------------
    // E2 — Primeira página e pageSize + 1
    // ------------------------------------------------------------------------
    test(
      'E2 — Primeira página solicita pageSize + 1 e retorna apenas pageSize',
      () async {
        const dogId = 'dog-emu-e2';
        await env.invokeFixture('e2');

        final query = HealthTimelineQuery(dogId: dogId, pageSize: 2);
        final page = await source.loadPage(query);

        expect(page.items.length, equals(2));
        expect(page.hasMore, isTrue);
        expect(page.nextCursor, isNotNull);
        expect(page.items[0].title, equals('Item 5')); // DESC
        expect(page.items[1].title, equals('Item 4'));
      },
    );

    // ------------------------------------------------------------------------
    // E3 — Empate de timestamp
    // ------------------------------------------------------------------------
    test(
      'E3 — Empate de timestamp: desempate determinístico por documentId DESC',
      () async {
        const dogId = 'dog-emu-e3';
        await env.invokeFixture('e3');

        // Página 1 (pageSize = 1) -> docC
        final q1 = HealthTimelineQuery(dogId: dogId, pageSize: 1);
        final page1 = await source.loadPage(q1);

        expect(page1.items.length, equals(1));
        expect(page1.items[0].id, equals('docC'));
        expect(page1.hasMore, isTrue);
        expect(page1.nextCursor, isNotNull);

        // Página 2 -> docB
        final q2 = HealthTimelineQuery(
          dogId: dogId,
          pageSize: 1,
          cursor: page1.nextCursor,
        );
        final page2 = await source.loadPage(q2);

        expect(page2.items.length, equals(1));
        expect(page2.items[0].id, equals('docB'));
        expect(page2.hasMore, isTrue);

        // Página 3 -> docA
        final q3 = HealthTimelineQuery(
          dogId: dogId,
          pageSize: 1,
          cursor: page2.nextCursor,
        );
        final page3 = await source.loadPage(q3);

        expect(page3.items.length, equals(1));
        expect(page3.items[0].id, equals('docA'));
        expect(page3.hasMore, isFalse);
        expect(page3.nextCursor, isNull);
      },
    );

    // ------------------------------------------------------------------------
    // E4 — Documento do cursor removido
    // ------------------------------------------------------------------------
    test(
      'E4 — Documento do cursor removido: avanço continua por valores do token',
      () async {
        const dogId = 'dog-emu-e4';
        await env.invokeFixture('e4/prepare');

        // Página 1 (pageSize = 1) -> docC
        final q1 = HealthTimelineQuery(dogId: dogId, pageSize: 1);
        final page1 = await source.loadPage(q1);
        expect(page1.items[0].id, equals('docC'));

        final cursorToken = page1.nextCursor;

        // Deleta docC no Emulator via Fixture Server
        await env.invokeFixture('e4/delete-cursor');

        // Página 2 com o cursor salvo
        final q2 = HealthTimelineQuery(
          dogId: dogId,
          pageSize: 1,
          cursor: cursorToken,
        );
        final page2 = await source.loadPage(q2);

        expect(page2.items.length, equals(1));
        expect(page2.items[0].id, equals('docB'));
      },
    );

    // ------------------------------------------------------------------------
    // E5 — Documento do cursor alterado
    // ------------------------------------------------------------------------
    test(
      'E5 — Documento do cursor alterado: avanço ignora mutação posterior no DB',
      () async {
        const dogId = 'dog-emu-e5';
        await env.invokeFixture('e5/prepare');

        // Página 1 -> docC
        final q1 = HealthTimelineQuery(dogId: dogId, pageSize: 1);
        final page1 = await source.loadPage(q1);
        expect(page1.items[0].id, equals('docC'));
        final savedCursor = page1.nextCursor;

        // Altera occurred_at de docC no Emulator via Fixture Server
        await env.invokeFixture('e5/change-cursor');

        // Página 2 usando o cursor salvo
        final q2 = HealthTimelineQuery(
          dogId: dogId,
          pageSize: 1,
          cursor: savedCursor,
        );
        final page2 = await source.loadPage(q2);

        expect(page2.items.length, equals(1));
        expect(page2.items[0].id, equals('docB'));
      },
    );

    // ------------------------------------------------------------------------
    // E6 — Período
    // ------------------------------------------------------------------------
    test(
      'E6 — Período: filtro temporal server-side (occurred_at start/end)',
      () async {
        const dogId = 'dog-emu-e6';
        await env.invokeFixture('e6');

        final query = HealthTimelineQuery(
          dogId: dogId,
          pageSize: 10,
          period: HealthTimelinePeriod(
            start: DateTime.parse('2026-05-10T00:00:00Z'),
            end: DateTime.parse('2026-05-20T23:59:59Z'),
          ),
        );
        final page = await source.loadPage(query);

        expect(page.items.length, equals(1));
        expect(page.items[0].id, equals('doc_inside'));
      },
    );

    // ------------------------------------------------------------------------
    // E7 — Documento inválido (fail-closed)
    // ------------------------------------------------------------------------
    test(
      'E7 — Documento inválido: falha a página inteira (fail-closed)',
      () async {
        const dogId = 'dog-emu-e7';
        await env.invokeFixture('e7');

        final query = HealthTimelineQuery(dogId: dogId, pageSize: 10);

        expect(
          () => source.loadPage(query),
          throwsA(isA<HealthTimelineSourceException>()),
        );
      },
    );

    // ------------------------------------------------------------------------
    // E8 — Filtro não suportado
    // ------------------------------------------------------------------------
    test(
      'E8 — Filtro não suportado: falha cliente sem consultar Firestore',
      () async {
        const dogId = 'dog-emu-e8';
        await env.invokeFixture('e8');

        final qType = HealthTimelineQuery(
          dogId: dogId,
          types: {HealthTimelineType.meal},
        );
        final qCase = HealthTimelineQuery(dogId: dogId, caseId: 'case_123');
        final qProf = HealthTimelineQuery(
          dogId: dogId,
          professional: HealthTimelineProfessionalFilter(name: 'Dr. Test'),
        );

        for (final q in [qType, qCase, qProf]) {
          try {
            await source.loadPage(q);
            fail('Deveria ter lançado HealthTimelineSourceException');
          } on HealthTimelineSourceException catch (e) {
            expect(e.message, equals('unsupported_query_filter'));
          }
        }
      },
    );
  });
}

// ============================================================================
// Helper de Ambiente e Comunicação com Host Fixture Server
// ============================================================================

class _EmulatorTestEnv {
  _EmulatorTestEnv({
    required this.projectId,
    required this.authHost,
    required this.authPort,
    required this.fsHost,
    required this.fsPort,
    required this.fixHost,
    required this.fixPort,
    required this.token,
    required this.ra,
    required this.email,
    required this.password,
  });

  final String projectId;
  final String authHost;
  final int authPort;
  final String fsHost;
  final int fsPort;
  final String fixHost;
  final int fixPort;
  final String token;
  final String ra;
  final String email;
  final String password;

  void assertEmulatorOnly() {
    final ok =
        fsHost == '10.0.2.2' || fsHost == '127.0.0.1' || fsHost == 'localhost';
    if (!ok) {
      throw StateError(
        'Recusa: host não-Emulator ($fsHost). A suíte não pode apontar para produção.',
      );
    }
  }

  /// Invoca uma operação permitida no Host Fixture Server via HTTP POST.
  Future<void> invokeFixture(String operation) async {
    final url = Uri.parse('http://$fixHost:$fixPort/fixture/$operation');
    final headers = <String, String>{
      'Content-Type': 'application/json',
      if (token.isNotEmpty) 'X-Health-Timeline-Fixture-Token': token,
    };
    final res = await http.post(url, headers: headers);
    if (res.statusCode >= 400) {
      throw StateError(
        'Host Fixture Server falhou ($operation): ${res.statusCode} ${res.body}',
      );
    }
  }

  Future<void> ensureAuthUserAndSignIn() async {
    final url = Uri.parse(
      'http://$authHost:$authPort/identitytoolkit.googleapis.com/v1/accounts:signUp?key=fake-api-key-emulator',
    );
    final body = jsonEncode({
      'email': email,
      'password': password,
      'returnSecureToken': true,
    });
    final res = await http.post(
      url,
      headers: {'Content-Type': 'application/json'},
      body: body,
    );

    // Se já existia, efetua signIn
    if (res.statusCode >= 400) {
      final loginUrl = Uri.parse(
        'http://$authHost:$authPort/identitytoolkit.googleapis.com/v1/accounts:signInWithPassword?key=fake-api-key-emulator',
      );
      await http.post(
        loginUrl,
        headers: {'Content-Type': 'application/json'},
        body: body,
      );
    }

    await FirebaseAuth.instance.signInWithEmailAndPassword(
      email: email,
      password: password,
    );
  }
}
