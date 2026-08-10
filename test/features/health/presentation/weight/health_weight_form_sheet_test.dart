import 'dart:async';
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
  final responses = <Object>[];

  @override
  Future<HealthWeightMutationReceipt> createRecord(
    CreateHealthWeightCommand command,
  ) async {
    calls.add(command);
    final response = responses.isEmpty
        ? _receipt(command)
        : responses.removeAt(0);
    if (response is Completer<HealthWeightMutationReceipt>) {
      return response.future;
    }
    if (response is HealthWeightMutationFailure) throw response;
    if (response is HealthWeightMutationReceipt) return response;
    throw StateError('Unsupported test response.');
  }
}

HealthWeightMutationReceipt _receipt(
  CreateHealthWeightCommand command, {
  bool wasNoOp = false,
}) => HealthWeightMutationReceipt(
  dogId: command.dogId,
  entityId: 'weight-1',
  weightKg: command.weightKg,
  revision: 1,
  wasNoOp: wasNoOp,
);

void main() {
  late _Gateway gateway;
  late HealthWeightController controller;
  var operation = 0;
  final dog = Dog(
    id: 'dog-1',
    name: 'Kira',
    breed: 'Pastor Belga Malinois',
    dateOfBirth: DateTime.utc(2020),
  );

  setUp(() {
    gateway = _Gateway();
    controller = HealthWeightController(
      gateway: gateway,
      authoritativeTimeProvider: AuthoritativeTimeProvider(
        gateway: _TimeGateway(),
      ),
      operationIdFactory: () => 'operation-${++operation}',
    );
  });

  Future<void> openSheet(
    WidgetTester tester, {
    Size size = const Size(430, 900),
    double textScale = 1,
    double keyboardInset = 0,
    bool disableAnimations = false,
    Dog? selectedDog,
  }) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = size;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.linear(textScale),
            viewInsets: EdgeInsets.only(bottom: keyboardInset),
            disableAnimations: disableAnimations,
          ),
          child: child!,
        ),
        home: Builder(
          builder: (context) => Scaffold(
            body: ElevatedButton(
              onPressed: () => showHealthWeightFormSheet(
                context: context,
                dog: selectedDog ?? dog,
                controller: controller,
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  Future<void> reveal(WidgetTester tester, Finder finder) async {
    await tester.ensureVisible(finder);
    await tester.pumpAndSettle();
  }

  Future<void> enterWeight(WidgetTester tester, String value) async {
    final input = find.byKey(const Key('health-weight-input'));
    await reveal(tester, input);
    await tester.enterText(input, value);
    await tester.pump();
  }

  Future<void> submit(WidgetTester tester) async {
    final save = find.byKey(const Key('health-weight-save'));
    await reveal(tester, save);
    await tester.tap(save);
    await tester.pumpAndSettle();
  }

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
    'active flow has no legacy write, fictitious clinical, or media API',
    () {
      final weightSources = [
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
        "'attachment_refs'",
        "'photo_url'",
        'health.create',
        'health.edit',
        'Circunferência',
        'Condição corporal',
        'Impacto na prontidão',
        'Peso estável',
        'Meta de peso',
      ]) {
        expect(weightSources, isNot(contains(forbidden)), reason: forbidden);
      }
    },
  );

  // WEIGHT-01E-C2B: `dog.weight` é projeção legada. Pré-preencher o campo
  // permitia abrir a sheet e confirmar sem medir, gravando cache stale como
  // pesagem factual — e o writer devolvia o valor para a própria projeção.
  testWidgets('create form does not prefill with the legacy dog.weight', (
    tester,
  ) async {
    final dogWithProjection = Dog(
      id: 'dog-1',
      name: 'Kira',
      breed: 'Pastor Belga Malinois',
      dateOfBirth: DateTime.utc(2020),
      weight: 28.4,
    );
    await openSheet(tester, selectedDog: dogWithProjection);

    final input = tester.widget<TextField>(
      find.byKey(const Key('health-weight-input')),
    );
    expect(input.controller!.text, isEmpty);
    expect(find.text('28,4'), findsNothing);
    expect(find.text('28.4'), findsNothing);
  });

  testWidgets('submit is blocked without explicit input in this interaction', (
    tester,
  ) async {
    final dogWithProjection = Dog(
      id: 'dog-1',
      name: 'Kira',
      breed: 'Pastor Belga Malinois',
      dateOfBirth: DateTime.utc(2020),
      weight: 28.4,
    );
    await openSheet(tester, selectedDog: dogWithProjection);
    await submit(tester);

    // Nada é enviado: o valor herdado não vira nova evidência.
    expect(gateway.calls, isEmpty);
  });

  testWidgets('opens with approved header and only real selected K9 data', (
    tester,
  ) async {
    await openSheet(tester);

    expect(find.byKey(const Key('health-weight-sheet')), findsOneWidget);
    expect(find.text('REGISTRAR PESAGEM'), findsOneWidget);
    expect(find.text('Avaliação física do K9'), findsOneWidget);
    expect(find.text('Kira'), findsOneWidget);
    expect(find.text('Pastor Belga Malinois'), findsOneWidget);
    expect(find.text('Bono'), findsNothing);
    expect(find.text('Trocar K9'), findsNothing);
    expect(find.textContaining('Ragonha'), findsNothing);
    expect(find.textContaining('OPERACIONAL'), findsNothing);
    expect(find.byTooltip('Fechar'), findsOneWidget);
  });

  testWidgets('weight is primary, uses kg and keeps pt-BR display in summary', (
    tester,
  ) async {
    await openSheet(tester);
    await enterWeight(tester, '29.55');

    expect(find.text('kg'), findsWidgets);
    expect(find.textContaining('Pesagem · 29,55 kg'), findsOneWidget);
    await tester.tap(find.byKey(const Key('health-weight-increment')));
    await tester.pump();
    expect(find.text('29,7'), findsOneWidget);
    await tester.tap(find.byKey(const Key('health-weight-decrement')));
    await tester.pump();
    expect(find.text('29,6'), findsOneWidget);
  });

  testWidgets('stepper has semantics and enforces 0.1 to 100 boundaries', (
    tester,
  ) async {
    await openSheet(tester);
    expect(find.bySemanticsLabel('Diminuir peso em 0,1 kg'), findsOneWidget);
    expect(find.bySemanticsLabel('Aumentar peso em 0,1 kg'), findsOneWidget);

    await enterWeight(tester, '0,1');
    expect(
      tester
          .widget<OutlinedButton>(
            find.byKey(const Key('health-weight-decrement')),
          )
          .onPressed,
      isNull,
    );
    await enterWeight(tester, '100');
    expect(
      tester
          .widget<OutlinedButton>(
            find.byKey(const Key('health-weight-increment')),
          )
          .onPressed,
      isNull,
    );
  });

  testWidgets('manual valid point and comma values submit unchanged', (
    tester,
  ) async {
    for (final entry in const {
      '29': 29.0,
      '29.5': 29.5,
      '29,55': 29.55,
      '100': 100.0,
    }.entries) {
      await openSheet(tester);
      await enterWeight(tester, entry.key);
      await submit(tester);
      expect(gateway.calls.last.weightKg, entry.value);
      expect(find.byKey(const Key('health-weight-sheet')), findsNothing);
    }
  });

  testWidgets('empty, zero, negative, above max, and text are rejected', (
    tester,
  ) async {
    await openSheet(tester);
    for (final value in ['', '0', '-1', '100,1', 'texto']) {
      await enterWeight(tester, value);
      await submit(tester);
      expect(find.byKey(const Key('health-weight-error')), findsOneWidget);
      expect(gateway.calls, isEmpty);
    }
  });

  testWidgets(
    'initial context is omitted and all canonical choices are shown',
    (tester) async {
      await openSheet(tester);
      final none = tester.widget<ChoiceChip>(
        find.byKey(const Key('health-weight-context-none')),
      );
      expect(none.selected, isTrue);
      for (final entry in const {
        'routine': 'Rotina',
        'clinical': 'Clínica',
        'pre_op': 'Pré-operacional',
        'post_op': 'Pós-operacional',
      }.entries) {
        final chip = find.byKey(Key('health-weight-context-${entry.key}'));
        expect(chip, findsOneWidget);
        expect(find.text(entry.value), findsOneWidget);
      }

      await enterWeight(tester, '25');
      await submit(tester);
      expect(gateway.calls.single.context, isNull);
    },
  );

  testWidgets('context chips map to canonical values and update summary', (
    tester,
  ) async {
    for (final context in HealthWeightContext.values) {
      await openSheet(tester);
      await enterWeight(tester, '25');
      final chip = find.byKey(
        Key('health-weight-context-${context.wireValue}'),
      );
      await reveal(tester, chip);
      await tester.tap(chip);
      await tester.pump();
      expect(find.textContaining(context.label), findsWidgets);
      await submit(tester);
      expect(gateway.calls.last.context, context);
    }
  });

  testWidgets('notes are optional, multiline, capped, and blank is omitted', (
    tester,
  ) async {
    await openSheet(tester);
    final notesFinder = find.byKey(const Key('health-weight-notes'));
    await reveal(tester, notesFinder);
    final notes = tester.widget<TextField>(notesFinder);
    expect(notes.minLines, 3);
    expect(notes.maxLines, 5);
    expect(notes.maxLength, 500);
    await enterWeight(tester, '24,6');
    await tester.enterText(notesFinder, '   ');
    await submit(tester);
    expect(gateway.calls.single.notes, isNull);
  });

  testWidgets('loading locks edits, closing and duplicate submissions', (
    tester,
  ) async {
    final pending = Completer<HealthWeightMutationReceipt>();
    gateway.responses.add(pending);
    await openSheet(tester);
    await enterWeight(tester, '24,6');
    final save = find.byKey(const Key('health-weight-save'));
    await reveal(tester, save);
    await tester.tap(save);
    await tester.pump();

    expect(gateway.calls, hasLength(1));
    expect(find.text('SALVANDO...'), findsOneWidget);
    expect(tester.widget<ElevatedButton>(save).onPressed, isNull);
    expect(
      tester
          .widget<IconButton>(find.byKey(const Key('health-weight-close')))
          .onPressed,
      isNull,
    );
    expect(
      tester
          .widget<TextField>(find.byKey(const Key('health-weight-input')))
          .enabled,
      isFalse,
    );
    await tester.tap(save, warnIfMissed: false);
    await tester.pump();
    expect(gateway.calls, hasLength(1));

    pending.complete(_receipt(gateway.calls.single));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('health-weight-sheet')), findsNothing);
  });

  testWidgets('permission denial stays explicit and has no retry action', (
    tester,
  ) async {
    gateway.responses.add(
      const HealthWeightMutationFailure(
        HealthWeightMutationErrorCode.permissionDenied,
        'Seu perfil não possui a permissão health.record_routine.',
      ),
    );
    await openSheet(tester);
    await enterWeight(tester, '24');
    await submit(tester);

    expect(
      find.text('Seu perfil não possui a permissão health.record_routine.'),
      findsOneWidget,
    );
    expect(find.byKey(const Key('health-weight-retry')), findsNothing);
    expect(find.textContaining('stack'), findsNothing);
  });

  testWidgets('transient retry remains visible and reuses frozen command', (
    tester,
  ) async {
    gateway.responses.addAll([
      const HealthWeightMutationFailure(
        HealthWeightMutationErrorCode.unavailable,
        'Serviço temporariamente indisponível. Tente novamente.',
      ),
    ]);
    await openSheet(tester);
    await enterWeight(tester, '24,6');
    final clinical = find.byKey(const Key('health-weight-context-clinical'));
    await reveal(tester, clinical);
    await tester.tap(clinical);
    await reveal(tester, find.byKey(const Key('health-weight-notes')));
    await tester.enterText(
      find.byKey(const Key('health-weight-notes')),
      'retorno',
    );
    await submit(tester);

    final retry = find.byKey(const Key('health-weight-retry'));
    expect(retry, findsOneWidget);
    final frozen = gateway.calls.single;
    await tester.tap(retry);
    await tester.pumpAndSettle();
    expect(gateway.calls, hasLength(2));
    expect(gateway.calls.last.operationId, frozen.operationId);
    expect(gateway.calls.last.measuredAt, frozen.measuredAt);
    expect(gateway.calls.last.weightKg, frozen.weightKg);
    expect(gateway.calls.last.context, frozen.context);
    expect(gateway.calls.last.notes, frozen.notes);
  });

  testWidgets('regular success and idempotent replay both close the sheet', (
    tester,
  ) async {
    await openSheet(tester);
    await enterWeight(tester, '24');
    await submit(tester);
    expect(find.byKey(const Key('health-weight-sheet')), findsNothing);

    await openSheet(tester);
    await enterWeight(tester, '24');
    gateway.responses.add(
      HealthWeightMutationReceipt(
        dogId: dog.id,
        entityId: 'weight-1',
        weightKg: 24,
        revision: 1,
        wasNoOp: true,
      ),
    );
    await submit(tester);
    expect(find.byKey(const Key('health-weight-sheet')), findsNothing);
  });

  testWidgets('close and cancel are explicit and discard pending operation', (
    tester,
  ) async {
    gateway.responses.add(
      const HealthWeightMutationFailure(
        HealthWeightMutationErrorCode.deadlineExceeded,
        'A confirmação demorou mais que o esperado. Tente novamente.',
      ),
    );
    await openSheet(tester);
    await enterWeight(tester, '24');
    await submit(tester);
    expect(controller.activeCommandForTest, isNotNull);

    final cancel = find.byKey(const Key('health-weight-cancel'));
    await reveal(tester, cancel);
    await tester.tap(cancel);
    await tester.pumpAndSettle();
    expect(controller.activeCommandForTest, isNull);
    expect(find.byKey(const Key('health-weight-sheet')), findsNothing);

    await openSheet(tester);
    await tester.tap(find.byKey(const Key('health-weight-close')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('health-weight-sheet')), findsNothing);
  });

  testWidgets(
    'small screen, enlarged text, and open keyboards do not overflow',
    (tester) async {
      await openSheet(
        tester,
        size: const Size(320, 700),
        textScale: 1.4,
        keyboardInset: 220,
      );
      expect(tester.takeException(), isNull, reason: 'initial layout');
      await enterWeight(tester, '24,6');
      expect(tester.takeException(), isNull, reason: 'weight focused');
      final notes = find.byKey(const Key('health-weight-notes'));
      await reveal(tester, notes);
      await tester.tap(notes);
      await tester.pump();
      expect(tester.takeException(), isNull, reason: 'notes focused');
      final save = find.byKey(const Key('health-weight-save'));
      await reveal(tester, save);

      expect(save, findsOneWidget);
      expect(find.byKey(const Key('health-weight-cancel')), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('reduced motion uses a static accessible loading indicator', (
    tester,
  ) async {
    final pending = Completer<HealthWeightMutationReceipt>();
    gateway.responses.add(pending);
    await openSheet(tester, disableAnimations: true);
    await enterWeight(tester, '24');
    final save = find.byKey(const Key('health-weight-save'));
    await reveal(tester, save);
    await tester.tap(save);
    await tester.pump();

    expect(find.byIcon(Icons.hourglass_top_rounded), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    pending.complete(_receipt(gateway.calls.single));
    await tester.pumpAndSettle();
  });

  testWidgets('modal cannot be dismissed silently by tapping the barrier', (
    tester,
  ) async {
    await openSheet(tester);
    await tester.tapAt(const Offset(5, 5));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('health-weight-sheet')), findsOneWidget);
  });
}
