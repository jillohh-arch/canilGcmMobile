import 'package:flutter_test/flutter_test.dart';

import 'package:canil_gcm/core/services/pdf_generator/weight_history_pdf.dart';

/// WEIGHT-01E-R-PDF — semântica canônica do documento exportado.
///
/// Dois defeitos motivaram este arquivo:
///
/// 1. o contrato era `double?`, colapsando `none`/`inconclusive`/`unavailable`
///    em um único caso. Um cão com 12 pesagens válidas + 1 documento ilegível
///    gerava PDF afirmando "Não há pesagens registradas" — objetivamente falso,
///    logo acima de uma tabela com as 12 pesagens;
/// 2. o endpoint antigo da tendência era `weights.last` sobre ordenação
///    date-only, então em empate de `measuredAt` o registro de comparação era
///    escolhido arbitrariamente por um `List.sort` instável.
///
/// Os testes exercitam o helper puro: a semântica é verificável sem inspecionar
/// bytes de PDF.
void main() {
  const idealMin = 20.0;
  const idealMax = 30.0;

  WeightPdfSummary summaryFor(
    WeightPdfAuthority authority, {
    List<double> displayed = const [],
  }) => WeightPdfSummary.from(
    authority: authority,
    displayedWeights: displayed,
    idealWeightMin: idealMin,
    idealWeightMax: idealMax,
  );

  group('T1 — CURRENT', () {
    test('exibe o peso atual canônico e classifica a faixa', () {
      final summary = summaryFor(
        const WeightPdfAuthority(
          state: WeightPdfAuthorityState.current,
          currentKg: 24.5,
          oldestKg: 24.3,
        ),
        displayed: const [24.5, 24.3],
      );

      expect(summary.currentLabel, '24.5 kg');
      expect(summary.rangeStatus, 'DENTRO DA FAIXA IDEAL');
      expect(summary.isConclusive, isTrue);
      expect(summary.totalDisplayedRecords, 2);
    });
  });

  group('T2 — NONE', () {
    test('ausência real de pesagens é afirmada como ausência', () {
      final summary = summaryFor(const WeightPdfAuthority.none());

      expect(summary.currentLabel, '—');
      expect(summary.analysisMessage, contains('Não há pesagens registradas'));
      expect(summary.rangeStatus, 'Sem Pesagem Registrada');
      expect(summary.trendText, 'Sem pesagens registradas');
      expect(summary.isConclusive, isFalse);
    });
  });

  group('T3 — INCONCLUSIVE', () {
    // O caso que a auditoria encontrou: 12 válidos + 1 malformed.
    final summary = WeightPdfSummary.from(
      authority: const WeightPdfAuthority.inconclusive(),
      displayedWeights: List<double>.filled(12, 24.0),
      idealWeightMin: idealMin,
      idealWeightMax: idealMax,
    );

    test(
      'NÃO afirma que não há pesagens quando existem registros legíveis',
      () {
        expect(
          summary.analysisMessage,
          isNot(contains('Não há pesagens registradas')),
        );
        expect(summary.analysisMessage, contains('não conclusiva'));
        // O histórico legível continua reconhecido no documento.
        expect(summary.analysisMessage, contains('12'));
        expect(summary.totalDisplayedRecords, 12);
      },
    );

    test('não emite current, tendência ou faixa conclusivos', () {
      expect(summary.currentLabel, '—');
      expect(summary.trendText, 'Tendência não conclusiva');
      expect(summary.rangeStatus, 'Análise Não Conclusiva');
      expect(summary.isConclusive, isFalse);
      // Nenhum verdict clínico de faixa.
      expect(summary.rangeStatus, isNot(contains('DENTRO')));
      expect(summary.rangeStatus, isNot(contains('ABAIXO')));
      expect(summary.rangeStatus, isNot(contains('ACIMA')));
      expect(summary.trendText, isNot(contains('Ganho')));
      expect(summary.trendText, isNot(contains('Perda')));
    });
  });

  group('T4 — UNAVAILABLE', () {
    test('falha de leitura não é ausência e não usa fallback', () {
      final summary = summaryFor(
        const WeightPdfAuthority.unavailable(),
        displayed: const [24.0, 25.0],
      );

      expect(summary.currentLabel, '—');
      expect(
        summary.analysisMessage,
        isNot(contains('Não há pesagens registradas')),
      );
      expect(summary.analysisMessage, contains('Não foi possível consultar'));
      expect(summary.rangeStatus, 'Peso Atual Indisponível');
      expect(summary.trendText, 'Tendência indisponível');
      expect(summary.isConclusive, isFalse);
    });

    test('os três estados não conclusivos produzem mensagens distintas', () {
      final none = summaryFor(const WeightPdfAuthority.none());
      final inconclusive = summaryFor(
        const WeightPdfAuthority.inconclusive(),
        displayed: const [24.0],
      );
      final unavailable = summaryFor(const WeightPdfAuthority.unavailable());

      final messages = {
        none.analysisMessage,
        inconclusive.analysisMessage,
        unavailable.analysisMessage,
      };
      expect(messages, hasLength(3));
    });
  });

  group('T5 — atual canônico vence os extremos da lista exibida', () {
    test('current não é o primeiro nem o último peso exibido', () {
      // A lista exibida começa em 39.9 e termina em 18.0; o canônico é 24.5.
      final summary = summaryFor(
        const WeightPdfAuthority(
          state: WeightPdfAuthorityState.current,
          currentKg: 24.5,
          oldestKg: 24.5,
        ),
        displayed: const [39.9, 31.0, 24.5, 18.0],
      );

      expect(summary.currentLabel, '24.5 kg');
      expect(summary.currentLabel, isNot(contains('39.9')));
      expect(summary.currentLabel, isNot(contains('18.0')));
      // 39.9 está acima da faixa; o verdict segue o canônico, não o extremo.
      expect(summary.rangeStatus, 'DENTRO DA FAIXA IDEAL');
    });
  });

  group('T6 — endpoint antigo da tendência', () {
    test('tendência usa o oldest canônico fornecido, não o extremo da lista', () {
      // `displayed` termina em 18.0 (o que `weights.last` escolheria). O oldest
      // canônico é 26.0 — desempatado por recordedAt/entityId antes do seam.
      final summary = summaryFor(
        const WeightPdfAuthority(
          state: WeightPdfAuthorityState.current,
          currentKg: 24.0,
          oldestKg: 26.0,
        ),
        displayed: const [24.0, 26.0, 18.0],
      );

      // Contra o canônico (26.0) houve PERDA de 2 kg.
      expect(summary.trendText, contains('Perda'));
      expect(summary.trendText, contains('2.0'));
      // Contra o extremo date-only (18.0) o texto seria de ganho: proibido.
      expect(summary.trendText, isNot(contains('Ganho')));
    });

    test('sem segundo registro não afirma tendência direcional', () {
      final summary = summaryFor(
        const WeightPdfAuthority(
          state: WeightPdfAuthorityState.current,
          currentKg: 24.0,
          oldestKg: null,
        ),
        displayed: const [24.0],
      );

      expect(summary.trendText, 'Estável');
      expect(summary.trendText, isNot(contains('Ganho')));
      expect(summary.trendText, isNot(contains('Perda')));
    });
  });

  group('T7 — contagem não limitada a janela', () {
    test('mais de 50 registros são contados integralmente', () {
      final summary = summaryFor(
        const WeightPdfAuthority(
          state: WeightPdfAuthorityState.current,
          currentKg: 24.0,
          oldestKg: 23.0,
        ),
        displayed: List<double>.filled(73, 24.0),
      );

      // O antigo caminho alimentava o PDF com `watchHistory(limit: 50)`.
      expect(summary.totalDisplayedRecords, 73);
      expect(summary.totalDisplayedRecords, greaterThan(50));
    });
  });
}
