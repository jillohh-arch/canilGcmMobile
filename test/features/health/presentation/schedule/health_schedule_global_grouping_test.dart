import 'package:flutter_test/flutter_test.dart';

import 'package:canil_gcm/features/health/presentation/schedule/health_schedule_global_grouping.dart';
import 'package:canil_gcm/features/health/presentation/schedule/health_schedule_item_view.dart';

import 'schedule_test_helpers.dart';

/// HW-4C — segundo nível de agrupamento (por K9) dentro da seção temporal.
void main() {
  HealthScheduleItemView view(
    String id,
    String dogId, {
    Duration offset = const Duration(hours: 2),
  }) {
    return HealthScheduleItemView.fromDomain(
      scheduleItem(
        id: id,
        dogId: dogId,
        scheduledFor: scheduleTestNow.add(offset),
      ),
      policy: testSchedulePolicy(),
      now: scheduleTestNow,
    );
  }

  HealthScheduleDogLabel labels(String dogId) => switch (dogId) {
    'dog-a' => const HealthScheduleDogLabel(name: 'Apolo'),
    'dog-b' => const HealthScheduleDogLabel(
      name: 'Bono',
      photoUrl: 'https://example.test/bono.jpg',
    ),
    _ => const HealthScheduleDogLabel(name: 'K9'),
  };

  test('agrupa por K9 preservando os itens', () {
    final blocks = groupSectionByDog([
      view('a1', 'dog-a'),
      view('b1', 'dog-b'),
      view('a2', 'dog-a', offset: const Duration(hours: 3)),
    ], resolveDog: labels);

    expect(blocks, hasLength(2));
    final byDog = {for (final b in blocks) b.dogId: b};
    expect(byDog['dog-a']!.items.map((e) => e.id), ['a1', 'a2']);
    expect(byDog['dog-b']!.items.map((e) => e.id), ['b1']);
  });

  test('resolve nome e foto pelo catálogo (sem I/O por item)', () {
    final blocks = groupSectionByDog([view('b1', 'dog-b')], resolveDog: labels);

    expect(blocks.single.dogName, 'Bono');
    expect(blocks.single.photoUrl, 'https://example.test/bono.jpg');
  });

  test('K9 fora do catálogo recebe rótulo neutro, item não é omitido', () {
    // Omitir um compromisso de saúde é pior que exibi-lo sem nome.
    final blocks = groupSectionByDog([
      view('x1', 'dog-desconhecido'),
    ], resolveDog: labels);

    expect(blocks.single.items, hasLength(1));
    expect(blocks.single.dogName, 'K9');
  });

  test('blocos ordenados pelo item mais urgente de cada K9', () {
    final blocks = groupSectionByDog([
      view('b1', 'dog-b', offset: const Duration(days: 2)),
      view('a1', 'dog-a', offset: const Duration(hours: 1)),
    ], resolveDog: labels);

    expect(
      blocks.map((e) => e.dogId),
      ['dog-a', 'dog-b'],
      reason: 'quem exige ação primeiro aparece primeiro',
    );
  });

  test('itens dentro do bloco ordenados por scheduled_for', () {
    final blocks = groupSectionByDog([
      view('late', 'dog-a', offset: const Duration(days: 1)),
      view('early', 'dog-a', offset: const Duration(hours: 1)),
    ], resolveDog: labels);

    expect(blocks.single.items.map((e) => e.id), ['early', 'late']);
  });

  test('ordem é determinística entre execuções', () {
    final items = [
      view('b1', 'dog-b'),
      view('a1', 'dog-a'),
      view('c1', 'dog-c'),
    ];

    final first = groupSectionByDog(items, resolveDog: labels);
    final second = groupSectionByDog(items, resolveDog: labels);

    expect(first.map((e) => e.dogId), second.map((e) => e.dogId));
  });

  test('empate absoluto desempata por dogId', () {
    // Mesmo scheduled_for e mesmo id base → estabilidade por dogId.
    final blocks = groupSectionByDog([
      view('s1', 'dog-z'),
      view('s1', 'dog-a'),
    ], resolveDog: labels);

    expect(blocks.map((e) => e.dogId), ['dog-a', 'dog-z']);
  });

  test('seção vazia produz zero blocos', () {
    expect(groupSectionByDog(const [], resolveDog: labels), isEmpty);
  });
}
