import 'package:flutter_test/flutter_test.dart';

import 'package:canil_gcm/features/dogs/domain/weight_record.dart';
import 'package:canil_gcm/features/health/presentation/weight/prontuario_weight_facts.dart';
import 'package:canil_gcm/features/health/presentation/weight/prontuario_weight_read_state.dart';

/// WEIGHT-01E-C2B.3 — autoridade única do peso atual no prontuário.
///
/// O C2B.2 encontrou uma segunda autoridade: dois widgets ordenavam o histórico
/// só por `measuredAt` e usavam o primeiro como "último peso". Com dois
/// registros no mesmo `measuredAt` — cenário suportado pelo writer — isso
/// divergia do atual canônico, exibindo dois números como fato na mesma tela.
void main() {
  final sameInstant = DateTime.utc(2026, 8, 6, 10);

  WeightRecord record(String id, double weightKg, {DateTime? measuredAt}) =>
      WeightRecord(
        id: id,
        weightKg: weightKg,
        measuredAt: measuredAt ?? sameInstant,
        recordedBy: null,
        schemaVersion: 1,
      );

  ProntuarioWeightFacts factsFor({
    required WeightRecord? current,
    required List<WeightRecord> history,
    ProntuarioWeightReadState? blockedState,
  }) => ProntuarioWeightFacts.from(
    readState:
        blockedState ??
        (current == null
            ? const ProntuarioWeightReadState.none()
            : ProntuarioWeightReadState.current(current)),
    history: history,
  );

  group('empate de measuredAt — o caso que derrubou o C2B.2', () {
    test('atual canônico vence, mesmo com entityId menor na lista', () {
      // A e B compartilham measuredAt. O canônico (entityId DESC) é B = 33.3.
      final a = record('A', 32.0);
      final b = record('B', 33.3);

      // A lista chega em ordem que favoreceria A num sort ingênuo.
      final facts = factsFor(current: b, history: [a, b]);

      expect(facts.currentWeightKg, 33.3);
      expect(facts.current!.id, 'B');
      // O anterior é o outro registro, nunca o próprio atual.
      expect(facts.previous!.id, 'A');
    });

    test('ordem de entrada não altera o atual', () {
      final a = record('A', 32.0);
      final b = record('B', 33.3);

      for (final history in [
        [a, b],
        [b, a],
      ]) {
        final facts = factsFor(current: b, history: history);
        expect(facts.currentWeightKg, 33.3);
        expect(facts.previous!.id, 'A');
      }
    });

    test('se o canônico for A, os fatos seguem A e não o maior entityId', () {
      // Prova que os fatos não reimplementam desempate: obedecem ao resolver.
      final a = record('A', 32.0);
      final b = record('B', 33.3);

      final facts = factsFor(current: a, history: [a, b]);

      expect(facts.currentWeightKg, 32.0);
      expect(facts.current!.id, 'A');
      expect(facts.previous!.id, 'B');
    });
  });

  group('coerência peso + data', () {
    test('peso e data vêm do MESMO registro', () {
      final older = record('old', 32.0, measuredAt: DateTime.utc(2026, 6, 17));
      final current = record('new', 33.3, measuredAt: DateTime.utc(2026, 8, 6));

      final facts = factsFor(current: current, history: [older, current]);

      expect(facts.currentWeightKg, 33.3);
      expect(facts.currentMeasuredAt, DateTime.utc(2026, 8, 6));
      // Nunca peso do atual com data do anterior.
      expect(facts.currentMeasuredAt, isNot(DateTime.utc(2026, 6, 17)));
    });
  });

  group('delta usa o endpoint canônico', () {
    test('delta = atual canônico - anterior', () {
      final older = record('old', 30.0, measuredAt: DateTime.utc(2026, 6, 17));
      final current = record('new', 33.3, measuredAt: DateTime.utc(2026, 8, 6));

      final facts = factsFor(current: current, history: [older, current]);

      expect(facts.deltaKg, closeTo(3.3, 0.0001));
    });

    test(
      'empate de measuredAt: delta parte do atual canônico, não do sort',
      () {
        final a = record('A', 32.0);
        final b = record('B', 33.3);

        final facts = factsFor(current: b, history: [a, b]);

        // 33.3 - 32.0, e não 32.0 - 33.3.
        expect(facts.deltaKg, closeTo(1.3, 0.0001));
      },
    );

    test('sem anterior não fabrica tendência', () {
      final only = record('only', 33.3);
      final facts = factsFor(current: only, history: [only]);

      expect(facts.previous, isNull);
      expect(facts.deltaKg, isNull);
    });
  });

  group('estados sem atual não promovem histórico', () {
    test('inconclusive com validRecords presentes → nenhum atual', () {
      final a = record('A', 32.0);
      final b = record('B', 33.3);

      final facts = factsFor(
        current: null,
        history: [a, b],
        blockedState: const ProntuarioWeightReadState.inconclusive(),
      );

      // A existência de válidos NÃO autoriza stale rollback.
      expect(facts.hasCurrent, isFalse);
      expect(facts.currentWeightKg, isNull);
      expect(facts.currentMeasuredAt, isNull);
      expect(facts.previous, isNull);
      expect(facts.deltaKg, isNull);
      // A contagem permanece factual.
      expect(facts.recordCount, 2);
    });

    test('unavailable com histórico stale → nenhum atual', () {
      final facts = factsFor(
        current: null,
        history: [record('A', 32.0)],
        blockedState: const ProntuarioWeightReadState.unavailable(),
      );

      expect(facts.hasCurrent, isFalse);
      expect(facts.currentWeightKg, isNull);
      expect(facts.previous, isNull);
    });

    test('none com lista vazia → nenhum atual inventado', () {
      final facts = factsFor(current: null, history: const []);

      expect(facts.hasCurrent, isFalse);
      expect(facts.currentWeightKg, isNull);
      expect(facts.recordCount, 0);
    });
  });

  group('identidade documental', () {
    test('atual é excluído do anterior por entityId, não por peso/data', () {
      // Dois registros com peso e data idênticos: só o id os distingue.
      final current = record('B', 33.3);
      final twin = record('A', 33.3);

      final facts = factsFor(current: current, history: [twin, current]);

      expect(facts.previous!.id, 'A');
      expect(facts.previous!.id, isNot(facts.current!.id));
    });

    test('atual ausente do histórico ainda é o atual', () {
      // A série pode ter falhado; o atual resolvido continua válido.
      final current = record('B', 33.3);

      final facts = factsFor(current: current, history: const []);

      expect(facts.currentWeightKg, 33.3);
      expect(facts.previous, isNull);
      expect(facts.recordCount, 0);
    });
  });
}
