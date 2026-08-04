import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:canil_gcm/core/services/authoritative_time/authoritative_time_gateway.dart';
import 'package:canil_gcm/core/services/authoritative_time/authoritative_time_models.dart';
import 'package:canil_gcm/core/services/authoritative_time/authoritative_time_provider.dart';
import 'package:canil_gcm/features/dogs/domain/dog.dart';
import 'package:canil_gcm/features/health/domain/health_weight_mutation_gateway.dart';
import 'package:canil_gcm/features/health/presentation/weight/health_weight_controller.dart';
import 'package:canil_gcm/features/health/presentation/weight/health_weight_form_sheet.dart';

final class _TimeGateway implements AuthoritativeTimeGateway {
  @override
  Future<AuthoritativeTimeRemoteResponse> fetchAuthoritativeTime() async {
    final now = DateTime.utc(2026, 8, 4);
    return AuthoritativeTimeRemoteResponse(
      protocolVersion: 1,
      requestId: '00000000-0000-4000-8000-000000000001',
      requestReceivedAtUtc: now,
      serverSentAtUtc: now,
      maxAge: const Duration(minutes: 15),
    );
  }
}

final class _Gateway implements HealthWeightMutationGateway {
  final calls = <CreateHealthWeightCommand>[];

  @override
  Future<HealthWeightMutationReceipt> createRecord(
    CreateHealthWeightCommand command,
  ) async {
    calls.add(command);
    return HealthWeightMutationReceipt(
      dogId: command.dogId,
      entityId: 'weight-1',
      weightKg: command.weightKg,
      revision: 1,
      wasNoOp: false,
    );
  }
}

void main() {
  late _Gateway gateway;
  late HealthWeightController controller;
  final dog = Dog(
    id: 'dog-1',
    name: 'Kira',
    breed: 'Pastor',
    dateOfBirth: DateTime.utc(2020),
  );

  setUp(() {
    gateway = _Gateway();
    controller = HealthWeightController(
      gateway: gateway,
      authoritativeTimeProvider: AuthoritativeTimeProvider(
        gateway: _TimeGateway(),
      ),
      operationIdFactory: () => 'operation-1',
    );
  });

  test('both active entry points use the unified form and no legacy form', () {
    final history = File(
      'lib/features/dogs/presentation/screens/weight_history_screen.dart',
    ).readAsStringSync();
    final prontuario = File(
      'lib/features/health/presentation/screens/dog_health_prontuario_screen.dart',
    ).readAsStringSync();
    for (final source in [history, prontuario]) {
      expect(source, contains('showHealthWeightFormSheet('));
      expect(source, isNot(contains('class _WeightRegistrationSheet')));
      expect(source, isNot(contains('class _WeighFormSheet')));
    }
  });

  test(
    'active weight flow contains no legacy direct-write API or attachment',
    () {
      final sources = [
        'lib/features/dogs/data/weight_history_service.dart',
        'lib/features/dogs/presentation/screens/weight_history_screen.dart',
        'lib/features/health/presentation/weight/health_weight_form_sheet.dart',
        'lib/features/health/presentation/weight/health_weight_controller.dart',
      ].map((path) => File(path).readAsStringSync()).join('\n');
      for (final forbidden in [
        'WeightHistoryService.addRecord',
        'addHealthLog(',
        'scale_photo_comprovante_balanca.jpg',
        "collection('weight_history')",
        "collection('health_events')",
        "'attachmentUrl'",
        "'photo_url'",
      ]) {
        expect(sources, isNot(contains(forbidden)), reason: forbidden);
      }

      final legacySources = [
        'lib/features/health/presentation/screens/health_event_form_screen.dart',
        'lib/features/health/presentation/viewmodels/health_viewmodel.dart',
      ].map((path) => File(path).readAsStringSync()).join('\n');
      for (final forbidden in [
        'addWeightRecord(',
        '_buildWeightField(',
        'weight: _weightController',
        'weight: log.weight',
      ]) {
        expect(legacySources, isNot(contains(forbidden)), reason: forbidden);
      }
    },
  );

  testWidgets('shows one focused form without fabricated clinical fields', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: HealthWeightFormSheet(dog: dog, controller: controller),
        ),
      ),
    );

    expect(find.text('Registrar pesagem'), findsOneWidget);
    expect(find.text('Kira'), findsOneWidget);
    expect(find.text('Contexto opcional'), findsOneWidget);
    await tester.tap(find.byKey(const Key('health-weight-context')));
    await tester.pumpAndSettle();
    for (final label in [
      'Não informado',
      'Rotina',
      'Clínica',
      'Pré-operacional',
      'Pós-operacional',
    ]) {
      expect(find.text(label), findsWidgets);
    }
    expect(find.textContaining('foto'), findsNothing);
    expect(find.textContaining('BCS'), findsNothing);
    expect(find.textContaining('Estável'), findsNothing);
  });

  testWidgets('validates input and increments exactly 0.1kg', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: HealthWeightFormSheet(dog: dog, controller: controller),
        ),
      ),
    );
    await tester.tap(find.byKey(const Key('health-weight-save')));
    await tester.pump();
    expect(find.byKey(const Key('health-weight-error')), findsOneWidget);

    await tester.enterText(
      find.byKey(const Key('health-weight-input')),
      '100.1',
    );
    await tester.tap(find.byKey(const Key('health-weight-save')));
    await tester.pump();
    expect(find.byKey(const Key('health-weight-error')), findsOneWidget);

    await tester.enterText(
      find.byKey(const Key('health-weight-input')),
      '20.0',
    );
    await tester.tap(find.byKey(const Key('health-weight-increment')));
    await tester.pump();
    expect(find.text('20.1'), findsOneWidget);
  });

  testWidgets('submits canonical values and closes on success', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () => showHealthWeightFormSheet(
              context: context,
              dog: dog,
              controller: controller,
            ),
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('health-weight-input')),
      '24,6',
    );
    await tester.tap(find.byKey(const Key('health-weight-context')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Clínica').last);
    await tester.enterText(
      find.byKey(const Key('health-weight-notes')),
      'retorno',
    );
    await tester.tap(find.byKey(const Key('health-weight-save')));
    await tester.pumpAndSettle();

    expect(gateway.calls.single.weightKg, 24.6);
    expect(gateway.calls.single.context, HealthWeightContext.clinical);
    expect(gateway.calls.single.notes, 'retorno');
    expect(find.text('Registrar pesagem'), findsNothing);
  });
}
