import 'dart:convert';
import 'dart:io';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import 'package:canil_gcm/features/health/data/schedule/firebase_functions_health_schedule_mutation_gateway.dart';
import 'package:canil_gcm/features/health/data/schedule/health_schedule_callable_names.dart';
import 'package:canil_gcm/features/health/domain/health_schedule_mutation_commands.dart';
import 'package:canil_gcm/features/health/domain/health_schedule_mutation_errors.dart';
import 'package:canil_gcm/features/health/domain/health_schedule_mutation_gateway.dart';
import 'package:canil_gcm/features/health/domain/health_schedule_revision.dart';
import 'package:canil_gcm/features/health/domain/health_v1_enums_ext.dart';

/// Integração permanente Gate 4:
/// `FirebaseFunctionsHealthScheduleMutationGateway` → Emulators.
///
/// Só executa quando:
/// ```text
/// HEALTH_SCHEDULE_EMULATOR_INTEGRATION=1
/// ```
/// (orquestrado por
/// `tools/rules_tests/health_schedule_flutter_gateway_emulator_tests.mjs`
/// sob `firebase emulators:exec`).
///
/// Transport: protocol HTTP do callable do Functions Emulator (mesmo wire
/// do SDK). O gateway permanente + codec + error mapper são o caminho real.
///
/// Zero produção: exige hosts de Emulator explícitos.
void main() {
  final enabled =
      Platform.environment['HEALTH_SCHEDULE_EMULATOR_INTEGRATION'] == '1';

  group('Gate4 Emulator happy path (gateway permanente)', () {
    if (!enabled) {
      test(
        'skipped fora do orquestrador Emulator '
        '(defina HEALTH_SCHEDULE_EMULATOR_INTEGRATION=1)',
        () {},
        skip:
            'Integração Emulator: rode via tools/rules_tests/'
            'health_schedule_flutter_gateway_emulator_tests.mjs',
      );
      return;
    }

    late _EmulatorHarness harness;
    late FirebaseFunctionsHealthScheduleMutationGateway gateway;

    setUpAll(() async {
      harness = _EmulatorHarness.fromEnvironment();
      harness.assertEmulatorOnly();
      await harness.signInOperator();
      gateway = FirebaseFunctionsHealthScheduleMutationGateway(
        invoker: harness.invokeCallable,
      );
      // ignore: avoid_print
      print(
        '[Gate4Emulator] AUTH=${harness.authHost} '
        'FS=${harness.fsHost} FN=${harness.fnHost}:${harness.fnPort} '
        'project=${harness.projectId} region=${harness.region}',
      );
    });

    test('create → replay → update → replay → complete → replay + errors',
        () async {
      final scheduledFor = DateTime.utc(2026, 9, 1, 12);
      final dueUntil = DateTime.utc(2026, 9, 2, 12);
      const createKey = 'gate4-flutter-create-1';
      const updateOp = 'gate4-flutter-upd-1';
      const completeOp = 'gate4-flutter-cmp-1';

      // --- CREATE ---
      final createCmd = CreateManualScheduleItemCommand(
        dogId: harness.dogId,
        scheduleType: ScheduleType.vaccination,
        title: 'Vacina Gate4 Flutter',
        scheduledFor: scheduledFor,
        dueUntil: dueUntil,
        timezone: 'America/Sao_Paulo',
        notes: 'obs-gate4',
        operationId: createKey,
      );

      final create1 = await gateway.createManual(createCmd);
      expect(create1, isA<HealthScheduleMutationSuccess>());
      final c1 = create1 as HealthScheduleMutationSuccess;
      expect(c1.wasNoOp, isFalse);
      expect(c1.revision, HealthScheduleRevision.numeric(1));
      expect(c1.lifecycleStatus, ScheduleLifecycleStatus.open);
      expect(c1.scheduleId, isNotEmpty);
      expect(c1.dogId, harness.dogId);
      final scheduleId = c1.scheduleId;

      final doc1 = await harness.getScheduleDoc(scheduleId);
      expect(doc1['lifecycle_status'], 'open');
      expect(doc1['source_type'], 'manual');
      expect(doc1['revision'], 1);
      expect(doc1['timezone'], 'America/Sao_Paulo');
      expect(doc1['title'], 'Vacina Gate4 Flutter');
      expect(doc1['notes'], 'obs-gate4');
      expect(doc1['schedule_type'], 'vaccination');
      expect(doc1['recorded_by'], isA<Map>());
      expect((doc1['recorded_by'] as Map)['uid'], isNotEmpty);
      // Timestamps server-side existem (formato Emulator Timestamp map ou string).
      expect(doc1.containsKey('created_at'), isTrue);
      expect(doc1.containsKey('scheduled_for'), isTrue);
      expect(doc1.containsKey('due_until'), isTrue);

      // --- CREATE REPLAY ---
      final create2 = await gateway.createManual(createCmd);
      expect(create2, isA<HealthScheduleMutationSuccess>());
      final c2 = create2 as HealthScheduleMutationSuccess;
      expect(c2.wasNoOp, isTrue);
      expect(c2.scheduleId, scheduleId);
      expect(c2.revision, HealthScheduleRevision.numeric(1));
      expect(c2.lifecycleStatus, ScheduleLifecycleStatus.open);

      // --- UPDATE ---
      final updateCmd = UpdateOpenScheduleItemCommand(
        dogId: harness.dogId,
        scheduleId: scheduleId,
        expectedRevision: HealthScheduleRevision.numeric(1),
        operationId: updateOp,
        title: 'Vacina Gate4 Flutter EDITADA',
      );
      final upd1 = await gateway.updateOpen(updateCmd);
      expect(upd1, isA<HealthScheduleMutationSuccess>());
      final u1 = upd1 as HealthScheduleMutationSuccess;
      expect(u1.wasNoOp, isFalse);
      expect(u1.revision, HealthScheduleRevision.numeric(2));
      expect(u1.lifecycleStatus, ScheduleLifecycleStatus.open);

      final doc2 = await harness.getScheduleDoc(scheduleId);
      expect(doc2['title'], 'Vacina Gate4 Flutter EDITADA');
      expect(doc2['revision'], 2);
      expect(doc2['source_type'], 'manual');
      expect(doc2['lifecycle_status'], 'open');

      // --- UPDATE REPLAY ---
      final upd2 = await gateway.updateOpen(updateCmd);
      expect(upd2, isA<HealthScheduleMutationSuccess>());
      final u2 = upd2 as HealthScheduleMutationSuccess;
      expect(u2.wasNoOp, isTrue);
      expect(u2.revision, HealthScheduleRevision.numeric(2));

      final doc2b = await harness.getScheduleDoc(scheduleId);
      expect(doc2b['revision'], 2);

      // --- STALE REVISION (backend → domain conflict) ---
      final stale = await gateway.updateOpen(
        UpdateOpenScheduleItemCommand(
          dogId: harness.dogId,
          scheduleId: scheduleId,
          expectedRevision: HealthScheduleRevision.numeric(1),
          operationId: 'gate4-flutter-stale-1',
          title: 'stale attempt',
        ),
      );
      expect(stale, isA<HealthScheduleMutationErrorResult>());
      expect(
        (stale as HealthScheduleMutationErrorResult).failure,
        isA<HealthScheduleMutationConflict>(),
      );

      // --- IDEMPOTENCY CONFLICT (same opId, different patch) ---
      final idem = await gateway.updateOpen(
        UpdateOpenScheduleItemCommand(
          dogId: harness.dogId,
          scheduleId: scheduleId,
          expectedRevision: HealthScheduleRevision.numeric(2),
          operationId: updateOp, // already used with different title
          title: 'patch diferente da original',
        ),
      );
      expect(idem, isA<HealthScheduleMutationErrorResult>());
      expect(
        (idem as HealthScheduleMutationErrorResult).failure,
        isA<HealthScheduleMutationIdempotencyConflict>(),
      );

      // --- COMPLETE ---
      final completeCmd = CompleteScheduleItemCommand(
        dogId: harness.dogId,
        scheduleId: scheduleId,
        operationId: completeOp,
      );
      final cmp1 = await gateway.complete(completeCmd);
      expect(cmp1, isA<HealthScheduleMutationSuccess>());
      final k1 = cmp1 as HealthScheduleMutationSuccess;
      expect(k1.wasNoOp, isFalse);
      expect(k1.lifecycleStatus, ScheduleLifecycleStatus.completed);
      expect(k1.revision, HealthScheduleRevision.numeric(3));

      final doc3 = await harness.getScheduleDoc(scheduleId);
      expect(doc3['lifecycle_status'], 'completed');
      expect(doc3['revision'], 3);
      expect(doc3.containsKey('completed_at'), isTrue);
      expect(doc3['completed_by'], isA<Map>());
      final completedByUid = (doc3['completed_by'] as Map)['uid'];
      final completedAt = doc3['completed_at'];

      // --- COMPLETE REPLAY ---
      final cmp2 = await gateway.complete(completeCmd);
      expect(cmp2, isA<HealthScheduleMutationSuccess>());
      final k2 = cmp2 as HealthScheduleMutationSuccess;
      expect(k2.wasNoOp, isTrue);
      expect(k2.revision, HealthScheduleRevision.numeric(3));
      expect(k2.lifecycleStatus, ScheduleLifecycleStatus.completed);

      final doc3b = await harness.getScheduleDoc(scheduleId);
      expect(doc3b['revision'], 3);
      expect(doc3b['completed_by'], isA<Map>());
      expect((doc3b['completed_by'] as Map)['uid'], completedByUid);
      expect(doc3b['completed_at'], completedAt);

      // Emitir IDs para o orquestrador Node validar receipts/audits.
      // ignore: avoid_print
      print(
        'GATE4_RESULT '
        '${jsonEncode({
          'dogId': harness.dogId,
          'scheduleIdComplete': scheduleId,
          'createKey': createKey,
          'updateOp': updateOp,
          'completeOp': completeOp,
        })}',
      );
    });

    test('cancel flow + replay (item separado)', () async {
      const createKey = 'gate4-flutter-create-cancel';
      const cancelOp = 'gate4-flutter-cancel-1';

      final create = await gateway.createManual(
        CreateManualScheduleItemCommand(
          dogId: harness.dogId,
          scheduleType: ScheduleType.general,
          title: 'Item para cancelar',
          scheduledFor: DateTime.utc(2026, 10, 1, 15),
          timezone: 'America/Sao_Paulo',
          operationId: createKey,
        ),
      );
      expect(create, isA<HealthScheduleMutationSuccess>());
      final c = create as HealthScheduleMutationSuccess;
      expect(c.wasNoOp, isFalse);
      expect(c.revision, HealthScheduleRevision.numeric(1));
      final scheduleId = c.scheduleId;

      final cancelCmd = CancelScheduleItemCommand(
        dogId: harness.dogId,
        scheduleId: scheduleId,
        cancelReason: 'motivo gate4 emulator',
        operationId: cancelOp,
      );
      final cancel1 = await gateway.cancel(cancelCmd);
      expect(cancel1, isA<HealthScheduleMutationSuccess>());
      final x1 = cancel1 as HealthScheduleMutationSuccess;
      expect(x1.wasNoOp, isFalse);
      expect(x1.lifecycleStatus, ScheduleLifecycleStatus.cancelled);
      expect(x1.revision, HealthScheduleRevision.numeric(2));

      final doc = await harness.getScheduleDoc(scheduleId);
      expect(doc['lifecycle_status'], 'cancelled');
      expect(doc['revision'], 2);
      expect(doc['cancel_reason'], 'motivo gate4 emulator');
      expect(doc.containsKey('cancelled_at'), isTrue);
      expect(doc['cancelled_by'], isA<Map>());

      final cancel2 = await gateway.cancel(cancelCmd);
      expect(cancel2, isA<HealthScheduleMutationSuccess>());
      final x2 = cancel2 as HealthScheduleMutationSuccess;
      expect(x2.wasNoOp, isTrue);
      expect(x2.revision, HealthScheduleRevision.numeric(2));

      // ignore: avoid_print
      print(
        'GATE4_RESULT_CANCEL '
        '${jsonEncode({
          'dogId': harness.dogId,
          'scheduleIdCancel': scheduleId,
          'createKeyCancel': createKey,
          'cancelOp': cancelOp,
        })}',
      );
    });
  });
}

/// Harness de transporte Emulator-only (test-only; não entra em produção).
final class _EmulatorHarness {
  _EmulatorHarness({
    required this.projectId,
    required this.region,
    required this.authHost,
    required this.fsHost,
    required this.fnHost,
    required this.fnPort,
    required this.dogId,
    required this.operatorEmail,
    required this.operatorPassword,
  });

  final String projectId;
  final String region;
  final String authHost;
  final String fsHost;
  final String fnHost;
  final int fnPort;
  final String dogId;
  final String operatorEmail;
  final String operatorPassword;

  String? _idToken;

  factory _EmulatorHarness.fromEnvironment() {
    final projectId =
        Platform.environment['GCLOUD_PROJECT'] ??
        Platform.environment['GCLOUD_PROJECT_ID'] ??
        'canil-gcm';
    final auth =
        Platform.environment['FIREBASE_AUTH_EMULATOR_HOST'] ?? '127.0.0.1:9099';
    final fs =
        Platform.environment['FIRESTORE_EMULATOR_HOST'] ?? '127.0.0.1:8080';
    final fnRaw =
        Platform.environment['FIREBASE_FUNCTIONS_EMULATOR_HOST'] ??
        '127.0.0.1:5001';
    final fnParts = fnRaw.replaceFirst(RegExp(r'^https?://'), '').split(':');
    return _EmulatorHarness(
      projectId: projectId,
      region: HealthScheduleCallableNames.region,
      authHost: auth.replaceFirst(RegExp(r'^https?://'), ''),
      fsHost: fs.replaceFirst(RegExp(r'^https?://'), ''),
      fnHost: fnParts[0],
      fnPort: fnParts.length > 1 ? int.parse(fnParts[1]) : 5001,
      dogId: Platform.environment['GATE4_DOG_ID'] ?? 'dog-gate4-flutter-a',
      operatorEmail:
          Platform.environment['GATE4_OP_EMAIL'] ?? '691755@gcm.com.br',
      operatorPassword:
          Platform.environment['GATE4_OP_PASSWORD'] ??
          'Gate3-Emulator-Only-Not-Prod!',
    );
  }

  void assertEmulatorOnly() {
    final hosts = [authHost, fsHost, fnHost];
    for (final h in hosts) {
      final ok =
          h.contains('127.0.0.1') ||
          h.contains('localhost') ||
          h.startsWith('10.0.2.2'); // Android emulator host loopback
      if (!ok) {
        throw StateError(
          'Recusa de write: host não-Emulator detectado ($h). '
          'Esta suíte não pode apontar para produção.',
        );
      }
    }
    if (projectId.isEmpty) {
      throw StateError('projectId vazio');
    }
  }

  Future<void> signInOperator() async {
    final uri = Uri.parse(
      'http://$authHost/identitytoolkit.googleapis.com/v1/accounts:signInWithPassword?key=fake-api-key',
    );
    final res = await http.post(
      uri,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'email': operatorEmail,
        'password': operatorPassword,
        'returnSecureToken': true,
      }),
    );
    if (res.statusCode >= 400) {
      throw StateError('Auth Emulator sign-in falhou: ${res.body}');
    }
    final body = jsonDecode(res.body) as Map<String, dynamic>;
    _idToken = body['idToken'] as String?;
    if (_idToken == null || _idToken!.isEmpty) {
      throw StateError('Auth Emulator não retornou idToken');
    }
  }

  Future<Map<String, dynamic>> invokeCallable(
    String functionName,
    Map<String, dynamic> data,
  ) async {
    final token = _idToken;
    if (token == null) {
      throw StateError('Sem idToken — chame signInOperator antes');
    }
    final uri = Uri.parse(
      'http://$fnHost:$fnPort/$projectId/$region/$functionName',
    );
    final res = await http.post(
      uri,
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      },
      body: jsonEncode({'data': data}),
    );

    final decoded = res.body.isEmpty
        ? <String, dynamic>{}
        : jsonDecode(res.body) as Map<String, dynamic>;

    if (res.statusCode >= 400 || decoded.containsKey('error')) {
      final err = decoded['error'];
      if (err is Map) {
        final status = (err['status'] ?? err['code'] ?? 'internal')
            .toString()
            .toLowerCase()
            .replaceAll('_', '-');
        // Firebase HTTP status → functions code
        final code = _httpStatusToFunctionsCode(res.statusCode, status);
        final message = (err['message'] ?? 'callable error').toString();
        final details = err['details'];
        throw FirebaseFunctionsException(
          code: code,
          message: message,
          details: details is Map
              ? Map<String, dynamic>.from(details)
              : details,
        );
      }
      throw FirebaseFunctionsException(
        code: 'internal',
        message: 'callable HTTP ${res.statusCode}: ${res.body}',
      );
    }

    final result = decoded['result'];
    if (result is Map) {
      return Map<String, dynamic>.from(result);
    }
    throw FirebaseFunctionsException(
      code: 'internal',
      message: 'Resposta do callable sem result map',
      details: const {'code': 'integrity'},
    );
  }

  Future<Map<String, dynamic>> getScheduleDoc(String scheduleId) async {
    final token = _idToken!;
    final path =
        'projects/$projectId/databases/(default)/documents/'
        'dogs/$dogId/health_schedule/$scheduleId';
    final uri = Uri.parse('http://$fsHost/v1/$path');
    final res = await http.get(
      uri,
      headers: {'Authorization': 'Bearer $token'},
    );
    if (res.statusCode >= 400) {
      throw StateError('Firestore read falhou: ${res.statusCode} ${res.body}');
    }
    final body = jsonDecode(res.body) as Map<String, dynamic>;
    final fields = body['fields'];
    if (fields is! Map) {
      throw StateError('Documento sem fields');
    }
    return _decodeFirestoreFields(Map<String, dynamic>.from(fields));
  }

  static String _httpStatusToFunctionsCode(int status, String fallback) {
    switch (status) {
      case 401:
        return 'unauthenticated';
      case 403:
        return 'permission-denied';
      case 404:
        return 'not-found';
      case 400:
        return fallback.contains('invalid') ? 'invalid-argument' : fallback;
      case 409:
      case 412:
        return 'failed-precondition';
      case 429:
        return 'resource-exhausted';
      case 503:
        return 'unavailable';
      default:
        if (fallback.isNotEmpty && fallback != 'internal') {
          // HttpsError may put code in status like FAILED_PRECONDITION
          if (fallback == 'failed-precondition') return 'failed-precondition';
          if (fallback == 'invalid-argument') return 'invalid-argument';
          if (fallback == 'not-found') return 'not-found';
          if (fallback == 'permission-denied') return 'permission-denied';
          if (fallback == 'unauthenticated') return 'unauthenticated';
        }
        return fallback.isEmpty ? 'internal' : fallback;
    }
  }

  static Map<String, dynamic> _decodeFirestoreFields(
    Map<String, dynamic> fields,
  ) {
    final out = <String, dynamic>{};
    fields.forEach((key, value) {
      out[key] = _decodeValue(value);
    });
    return out;
  }

  static dynamic _decodeValue(dynamic value) {
    if (value is! Map) return value;
    final m = Map<String, dynamic>.from(value);
    if (m.containsKey('stringValue')) return m['stringValue'];
    if (m.containsKey('integerValue')) {
      return int.tryParse(m['integerValue'].toString()) ?? m['integerValue'];
    }
    if (m.containsKey('doubleValue')) return m['doubleValue'];
    if (m.containsKey('booleanValue')) return m['booleanValue'];
    if (m.containsKey('timestampValue')) return m['timestampValue'];
    if (m.containsKey('nullValue')) return null;
    if (m.containsKey('mapValue')) {
      final fields = m['mapValue']?['fields'];
      if (fields is Map) {
        return _decodeFirestoreFields(Map<String, dynamic>.from(fields));
      }
      return <String, dynamic>{};
    }
    if (m.containsKey('arrayValue')) {
      final values = m['arrayValue']?['values'];
      if (values is List) {
        return values.map(_decodeValue).toList();
      }
      return <dynamic>[];
    }
    return m;
  }
}
