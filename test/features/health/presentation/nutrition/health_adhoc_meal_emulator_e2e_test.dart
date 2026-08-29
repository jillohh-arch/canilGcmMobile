// ignore_for_file: avoid_print

import 'dart:convert';
import 'dart:io';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import 'package:canil_gcm/features/health/data/nutrition/firebase_functions_health_nutrition_mutation_gateway.dart';
import 'package:canil_gcm/features/health/presentation/nutrition/health_adhoc_meal_form_sheet.dart';
import 'package:canil_gcm/features/health/presentation/nutrition/health_nutrition_mutation_controller.dart';
import 'package:canil_gcm/features/health/presentation/nutrition/health_nutrition_mutation_outcome.dart';

void main() {
  final enabled =
      Platform.environment['HEALTH_NUTRITION_EMULATOR_INTEGRATION'] == '1';

  group(
    'Gate 5C.3B Flutter UI Integration E2E (HealthAdhocMealFormSheet -> Gateway -> Emulators)',
    () {
      if (!enabled) {
        test(
          'skipped fora do orquestrador Emulator (defina HEALTH_NUTRITION_EMULATOR_INTEGRATION=1)',
          () {},
          skip:
              'Integração Emulator: rode via flutter test com HEALTH_NUTRITION_EMULATOR_INTEGRATION=1',
        );
        return;
      }

      late _NutritionEmulatorHarness harness;
      late FirebaseFunctionsHealthNutritionMutationGateway gateway;
      late HealthNutritionMutationController controller;

      setUpAll(() async {
        HttpOverrides.global = null;
        harness = _NutritionEmulatorHarness.fromEnvironment();
        await harness.signInOperator();
        gateway = FirebaseFunctionsHealthNutritionMutationGateway(
          invoker: harness.invokeCallable,
        );
        print(
          '[Gate5C3BFlutterE2E] AUTH=${harness.authHost} '
          'FS=${harness.fsHost} FN=${harness.fnHost}:${harness.fnPort} '
          'project=${harness.projectId} region=${harness.region}',
        );
      });

      tearDownAll(() {
        harness.close();
      });

      testWidgets(
        'CADEIA INTEGRADA COMPROVADA: HealthAdhocMealFormSheet -> Controller -> Gateway -> Functions Emulator -> Firestore Emulator -> Read-after-write',
        (tester) async {
          tester.view.physicalSize = const Size(800, 1600);
          tester.view.devicePixelRatio = 1.0;
          addTearDown(tester.view.resetPhysicalSize);

          var refreshCount = 0;
          controller = HealthNutritionMutationController(
            gateway: gateway,
            onRefreshAfterSuccess: () async {
              refreshCount++;
              print(
                '[Gate5C3BFlutterE2E] Read-after-write refresh triggered count=$refreshCount',
              );
            },
          );

          HealthNutritionMutationUiOutcome? sheetOutcome;

          await tester.pumpWidget(
            MaterialApp(
              home: Scaffold(
                body: Builder(
                  builder: (context) {
                    return ElevatedButton(
                      onPressed: () async {
                        sheetOutcome =
                            await showModalBottomSheet<
                              HealthNutritionMutationUiOutcome
                            >(
                              context: context,
                              isScrollControlled: true,
                              builder: (_) => HealthAdhocMealFormSheet(
                                dogId: harness.dogId,
                                dogDisplayName: 'Rex Nutri E2E',
                                controller: controller,
                                onRefreshRequested: () async {
                                  refreshCount++;
                                },
                              ),
                            );
                      },
                      child: const Text('OPEN_ADHOC_SHEET'),
                    );
                  },
                ),
              ),
            ),
          );

          // 1. Abre a UI do Formulário Canônico Ad Hoc
          final openFinder = find.text('OPEN_ADHOC_SHEET');
          expect(openFinder, findsOneWidget);
          await tester.tap(openFinder);
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 500));

          expect(find.byType(HealthAdhocMealFormSheet), findsOneWidget);
          expect(find.text('REGISTRAR ALIMENTAÇÃO'), findsOneWidget);

          // 2. Preenche os dados de entrada na UI
          final offeredFinder = find.widgetWithText(
            TextFormField,
            'Quantidade oferecida (g)',
          );
          await tester.enterText(offeredFinder, '150');

          // Seleciona aceitação 'Full' (já default)
          final submitFinder = find.widgetWithText(
            FilledButton,
            'REGISTRAR ALIMENTAÇÃO AVULSA',
          );
          await tester.ensureVisible(submitFinder);

          // 3. Executa um único submit pela UI
          print('[Gate5C3BFlutterE2E] Submetendo formulário ad hoc via UI...');
          await tester.runAsync(() async {
            await tester.tap(submitFinder);
            await tester.pump();
            await Future<void>.delayed(const Duration(milliseconds: 1500));
          });
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 500));

          // 4. Valida retorno do FormSheet & Read-after-write
          expect(sheetOutcome, isA<HealthNutritionMutationUiSuccess>());
          final success = sheetOutcome as HealthNutritionMutationUiSuccess;
          expect(success.entityId, startsWith('ml1_'));
          expect(success.mealOccurrenceId, isNull);
          expect(success.refreshFailed, isFalse);
          expect(refreshCount, greaterThanOrEqualTo(1));

          final mealId = success.entityId;
          print(
            '[Gate5C3BFlutterE2E] UI recebeu resposta de sucesso. mealId=$mealId',
          );

          // 5. Validação direta do documento criado no Firestore Emulator via API REST
          late final Map<String, dynamic> doc;
          await tester.runAsync(() async {
            doc = await harness.getMealLogDoc(mealId);
          });

          expect(doc['period'], isNotEmpty);
          expect(doc['offered_grams'], 150);
          expect(doc['consumed_grams'], anyOf(isNull, 150));
          expect(doc['acceptance'], isNotEmpty);
          expect(doc['plan_id'], isNull);
          expect(doc['planned_meal_id'], isNull);
          expect(doc['meal_occurrence_id'], isNull);
          expect(doc['scheduled_for'], isNull);
          expect(doc['prescription_amount_at_time'], isNull);
          expect(doc['recorded_by'], isA<Map>());
          expect(doc['schema_version'], 1);
          expect(doc['revision'], 1);
          expect(doc['source'], 'mobile_callable');

          // Reconciliação do dog_id: NÃO presente no corpo do documento
          expect(doc.containsKey('dog_id'), isFalse);

          print(
            '[Gate5C3BFlutterE2E] CADEIA INTEGRADA COMPROVADA COM SUCESSO.',
          );
          controller.dispose();
        },
      );
    },
  );
}

class _NutritionEmulatorHarness {
  _NutritionEmulatorHarness({
    required this.authHost,
    required this.fsHost,
    required this.fnHost,
    required this.fnPort,
    required this.projectId,
    required this.region,
    required this.dogId,
    required this.email,
    required this.password,
  });

  final String authHost;
  final String fsHost;
  final String fnHost;
  final int fnPort;
  final String projectId;
  final String region;
  final String dogId;
  final String email;
  final String password;

  String? _idToken;
  final http.Client _client = http.Client();

  void close() {
    _client.close();
  }

  factory _NutritionEmulatorHarness.fromEnvironment() {
    return _NutritionEmulatorHarness(
      authHost:
          Platform.environment['FIREBASE_AUTH_EMULATOR_HOST'] ??
          '127.0.0.1:9099',
      fsHost:
          Platform.environment['FIRESTORE_EMULATOR_HOST'] ?? '127.0.0.1:8080',
      fnHost: '127.0.0.1',
      fnPort: 5001,
      projectId: Platform.environment['GCLOUD_PROJECT'] ?? 'canil-gcm',
      region: 'southamerica-east1',
      dogId: 'dog-nutri-e2e-a',
      email: '710001@gcm.com.br',
      password: 'Gate2-Nutrition-Emulator-Only-Not-Prod!',
    );
  }

  Future<void> signInOperator() async {
    final uri = Uri.parse(
      'http://$authHost/identitytoolkit.googleapis.com/v1/accounts:signInWithPassword?key=fake-api-key-emulator',
    );
    final res = await _client.post(
      uri,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'email': email,
        'password': password,
        'returnSecureToken': true,
      }),
    );
    if (res.statusCode != 200) {
      throw StateError(
        'Auth Emulator login falhou: ${res.statusCode} ${res.body}',
      );
    }
    final data = jsonDecode(res.body) as Map<String, dynamic>;
    _idToken = data['idToken'] as String?;
    if (_idToken == null || _idToken!.isEmpty) {
      throw StateError('ID token Auth Emulator vazio');
    }
  }

  Future<Map<String, dynamic>> invokeCallable(
    String functionName,
    Map<String, dynamic> data,
  ) async {
    final token = _idToken;
    if (token == null) throw StateError('Operador não autenticado');

    final uri = Uri.parse(
      'http://$fnHost:$fnPort/$projectId/$region/$functionName',
    );
    final res = await _client.post(
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
        throw FirebaseFunctionsException(
          code: status,
          message: (err['message'] ?? 'callable error').toString(),
          details: err['details'] is Map
              ? Map<String, dynamic>.from(err['details'] as Map)
              : err['details'],
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
    );
  }

  Future<Map<String, dynamic>> getMealLogDoc(String mealId) async {
    final token = _idToken!;
    final path =
        'projects/$projectId/databases/(default)/documents/'
        'dogs/$dogId/meal_logs/$mealId';
    final uri = Uri.parse('http://$fsHost/v1/$path');
    final res = await _client.get(
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

  static Map<String, dynamic> _decodeFirestoreFields(
    Map<String, dynamic> fields,
  ) {
    final out = <String, dynamic>{};
    for (final entry in fields.entries) {
      final val = entry.value;
      if (val is Map<String, dynamic>) {
        if (val.containsKey('stringValue')) {
          out[entry.key] = val['stringValue'];
        } else if (val.containsKey('integerValue')) {
          out[entry.key] = int.parse(val['integerValue'].toString());
        } else if (val.containsKey('doubleValue')) {
          out[entry.key] = (val['doubleValue'] as num).toDouble();
        } else if (val.containsKey('booleanValue')) {
          out[entry.key] = val['booleanValue'];
        } else if (val.containsKey('nullValue')) {
          out[entry.key] = null;
        } else if (val.containsKey('mapValue')) {
          final subFields = val['mapValue']['fields'];
          if (subFields is Map<String, dynamic>) {
            out[entry.key] = _decodeFirestoreFields(subFields);
          } else {
            out[entry.key] = <String, dynamic>{};
          }
        } else if (val.containsKey('arrayValue')) {
          final values = val['arrayValue']['values'];
          if (values is List) {
            out[entry.key] = values.map((v) {
              if (v is Map<String, dynamic>) {
                if (v.containsKey('stringValue')) return v['stringValue'];
                if (v.containsKey('integerValue'))
                  return int.parse(v['integerValue'].toString());
              }
              return v;
            }).toList();
          } else {
            out[entry.key] = [];
          }
        }
      }
    }
    return out;
  }
}
