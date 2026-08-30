import 'package:flutter_test/flutter_test.dart';

import 'package:canil_gcm/features/health/presentation/schedule/health_schedule_experience_scope.dart';
import 'package:canil_gcm/features/health/presentation/schedule/health_schedule_global_controller.dart';
import 'package:canil_gcm/features/health/presentation/schedule/health_schedule_global_state.dart';
import 'package:canil_gcm/features/health/presentation/schedule/health_schedule_source.dart';

import 'fake_health_schedule_global_source.dart';
import 'schedule_test_helpers.dart';

/// HW-4C — wiring do gate de experiência.
///
/// Invariante central: `own_records` NUNCA alcança o Global Reader. O gate é de
/// experiência, não de autorização — as Rules seguem sendo a autoridade e
/// `permission-denied` continua erro, sem fallback automático para per-dog.
void main() {
  late FakeHealthScheduleGlobalSource source;

  setUp(() => source = FakeHealthScheduleGlobalSource());

  /// Simula a decisão do entry screen: só instancia/alimenta o Global Reader
  /// quando a experiência resolvida é global.
  Future<HealthScheduleGlobalController?> wire({
    required Map<String, dynamic> claims,
    required List<String> catalog,
  }) async {
    final experience = HealthScheduleExperienceClaims.fromClaims(claims);
    if (experience != HealthScheduleExperience.global) return null;

    final controller = HealthScheduleGlobalController(
      source: source,
      temporalPolicy: testSchedulePolicy(),
      clock: () => scheduleTestNow,
    );
    await controller.setCatalog(catalog);
    return controller;
  }

  test('escopo global → Global Reader é chamado com o catálogo', () async {
    source.enqueueItems([
      scheduleItem(id: 'a1', dogId: 'dog-a'),
      scheduleItem(id: 'b1', dogId: 'dog-b'),
    ]);

    final controller = await wire(
      claims: {'role': 'admin'},
      catalog: const ['dog-a', 'dog-b'],
    );
    addTearDown(() => controller?.dispose());

    expect(controller, isNotNull);
    expect(source.callCount, 1);
    expect(source.requests.single.authorizedDogIds, ['dog-a', 'dog-b']);
    expect(controller!.state, isA<HealthScheduleGlobalData>());
  });

  test('own_records → Global Reader NUNCA é chamado', () async {
    final controller = await wire(
      claims: {'access_scope': 'own_records'},
      catalog: const ['dog-a', 'dog-b'],
    );

    expect(
      controller,
      isNull,
      reason: 'own_records não instancia o controller global',
    );
    expect(
      source.callCount,
      0,
      reason: 'nenhuma query collection-group para own_records',
    );
  });

  test('own_records continua alcançando a Agenda per-dog', () async {
    // A ausência de controller global é exatamente o que mantém o fluxo
    // per-dog: a experiência per-dog é a Agenda existente, inalterada.
    final experience = HealthScheduleExperienceClaims.fromClaims({
      'access_scope': 'own_records',
    });

    expect(experience, HealthScheduleExperience.perDog);
    expect(source.callCount, 0);
  });

  test('escopo indeterminado → per-dog, sem query global', () async {
    final controller = await wire(
      claims: {'role': 'condutor'},
      catalog: const ['dog-a'],
    );

    expect(controller, isNull);
    expect(source.callCount, 0);
  });

  test('catálogo global vazio → empty legítimo sem query CG', () async {
    final controller = await wire(claims: {'role': 'admin'}, catalog: const []);
    addTearDown(() => controller?.dispose());

    expect(controller, isNotNull);
    expect(controller!.state, isA<HealthScheduleGlobalNoCatalog>());
    expect(
      source.callCount,
      0,
      reason: 'catálogo vazio não emite query nem para escopo global',
    );
  });

  test('troca de identidade/escopo invalida resposta anterior', () async {
    source.holdResponses = true;

    final controller = HealthScheduleGlobalController(
      source: source,
      temporalPolicy: testSchedulePolicy(),
      clock: () => scheduleTestNow,
    );
    addTearDown(controller.dispose);

    // Identidade 1 com catálogo amplo.
    final first = controller.setCatalog(const ['dog-a', 'dog-b']);
    // Identidade 2 (sessão trocou) com catálogo menor.
    final second = controller.setCatalog(const ['dog-c']);

    // A resposta da identidade 2 chega primeiro (index 1 na fila).
    source.completeNextItems([
      scheduleItem(id: 'c1', dogId: 'dog-c'),
    ], index: 1);
    // A resposta stale da identidade 1 chega depois.
    source.completeNextItems([
      scheduleItem(id: 'a1', dogId: 'dog-a'),
      scheduleItem(id: 'b1', dogId: 'dog-b'),
    ]);

    await first;
    await second;

    final snapshot = (controller.state as HealthScheduleGlobalData).snapshot;
    expect(
      snapshot.items.map((e) => e.id),
      ['c1'],
      reason: 'catálogo da identidade anterior não pode sobrescrever a atual',
    );
  });

  test('permission-denied do Global NÃO degrada para per-dog', () async {
    source.enqueueError(
      const HealthScheduleSourceException(
        'Sem permissão para a agenda do efetivo.',
        isPermissionDenied: true,
      ),
    );

    final controller = await wire(
      claims: {'role': 'admin'},
      catalog: const ['dog-a'],
    );
    addTearDown(() => controller?.dispose());

    // Permanece erro de autorização na Agenda Global — nunca vira empty e
    // nunca troca silenciosamente de experiência.
    expect(controller!.state, isA<HealthScheduleGlobalPermissionDenied>());
    expect(controller.state, isNot(isA<HealthScheduleGlobalEmpty>()));
    expect(controller.state, isNot(isA<HealthScheduleGlobalNoCatalog>()));
  });

  test('admin com own_records declarado permanece per-dog', () async {
    // Restrição vence: espelha authState() das Rules.
    final controller = await wire(
      claims: {'role': 'admin', 'access_scope': 'own_records'},
      catalog: const ['dog-a'],
    );

    expect(controller, isNull);
    expect(source.callCount, 0);
  });
}
