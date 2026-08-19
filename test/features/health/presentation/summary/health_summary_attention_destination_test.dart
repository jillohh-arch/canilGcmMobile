import 'package:flutter_test/flutter_test.dart';

import 'package:canil_gcm/features/health/presentation/summary/health_summary_attention_destination.dart';
import 'package:canil_gcm/features/health/presentation/summary/health_summary_block_models.dart';

/// B4-C.1 — boundary projeção → id canônico de restrição.
///
/// A boundary existe porque o gateway canônico (B4-B2) recusa
/// `restriction:<id>` de propósito. Estes testes provam que a tradução acontece
/// aqui, uma única vez, e que qualquer forma corrompida falha fechada em vez de
/// virar um `get()` em path errado.
void main() {
  // Construídos por code unit para que o ARQUIVO de teste permaneça textual —
  // um NUL literal no fonte é corrupção de source, não fixture.
  final nul = String.fromCharCode(0);
  final del = String.fromCharCode(0x7F);
  final tab = String.fromCharCode(9);

  HealthSummaryAttentionItem item(String id, {String? hint}) =>
      HealthSummaryAttentionItem(
        id: id,
        title: 'Restrição operacional',
        destinationHint: hint,
      );

  String? canonicalOf(String projectionId) {
    final parsed = parseReadinessRestrictionProjectionId(projectionId);
    return parsed is ReadinessRestrictionProjectionIdParsed
        ? parsed.canonicalRestrictionId
        : null;
  }

  group('parse — sucesso preserva identidade exata', () {
    test('remove apenas o prefixo', () {
      expect(canonicalOf('restriction:or_abc123'), 'or_abc123');
    });

    test('não altera case nem conteúdo', () {
      expect(canonicalOf('restriction:OR_AbC_123'), 'OR_AbC_123');
      expect(canonicalOf('restriction:or-abc.123_XYZ'), 'or-abc.123_XYZ');
    });

    test('id que contém a palavra restriction no meio é preservado', () {
      expect(
        canonicalOf('restriction:or_restriction_abc'),
        'or_restriction_abc',
      );
    });

    test('dois ids distintos produzem canônicos distintos', () {
      expect(canonicalOf('restriction:or_A'), 'or_A');
      expect(canonicalOf('restriction:or_B'), 'or_B');
      expect(
        canonicalOf('restriction:or_A'),
        isNot(canonicalOf('restriction:or_B')),
      );
    });
  });

  group('parse — não é restrição', () {
    test('vazio, alerta e prefixos alheios', () {
      for (final id in [
        '',
        'abc',
        'alert:vaccination_overdue',
        'restrictions:abc',
        'operational_restriction:abc',
        'operationalRestriction:abc',
        'health_restriction:abc',
        'Restriction:abc',
        'RESTRICTION:abc',
        ' restriction:abc',
      ]) {
        expect(
          parseReadinessRestrictionProjectionId(id),
          isA<ReadinessRestrictionProjectionIdNotRestriction>(),
          reason: 'id: "$id"',
        );
      }
    });
  });

  group('parse — malformado falha fechado', () {
    test('prefixo sem miolo, aninhado, duplo separador e path unsafe', () {
      for (final id in [
        'restriction:',
        'restriction:restriction:abc',
        'restriction::abc',
        'restriction:abc ',
        'restriction: abc',
        'restriction:a b',
        'restriction:a/b',
        'restriction:.',
        'restriction:..',
      ]) {
        expect(
          parseReadinessRestrictionProjectionId(id),
          isA<ReadinessRestrictionProjectionIdMalformed>(),
          reason: 'id: "$id"',
        );
      }
    });

    test('NUL e caracteres de controle são rejeitados', () {
      // `trim()` do Dart não remove NUL, então sem checagem explícita um id
      // com NUL chegaria ao gateway canônico.
      for (final id in [
        'restriction:${nul}abc',
        'restriction:abc$nul',
        'restriction:a${nul}b',
        'restriction:$nul',
        'restriction:abc$del',
        'restriction:a${tab}b',
      ]) {
        expect(
          parseReadinessRestrictionProjectionId(id),
          isA<ReadinessRestrictionProjectionIdMalformed>(),
          reason: 'id com caractere de controle',
        );
      }
    });

    test('malformado nunca produz id canônico', () {
      for (final id in [
        'restriction:',
        'restriction:restriction:abc',
        'restriction:abc ',
        'restriction:a/b',
        'restriction:abc$nul',
      ]) {
        expect(canonicalOf(id), isNull, reason: 'id malformado');
      }
    });
  });

  group('classificação de destino', () {
    test('restrição válida → destino canônico com o id do item tocado', () {
      final destination = classifyHealthSummaryAttentionDestination(
        item('restriction:or_abc123'),
      );
      expect(
        destination,
        const HealthSummaryAttentionRestrictionDestination('or_abc123'),
      );
    });

    test('restrição precede o fallback mesmo sem destinationHint', () {
      // Nenhum produtor de produção preenche destinationHint hoje; sem esta
      // precedência toda restrição cairia em histórico e o id seria descartado.
      final destination = classifyHealthSummaryAttentionDestination(
        item('restriction:or_xyz'),
      );
      expect(destination, isA<HealthSummaryAttentionRestrictionDestination>());
    });

    test('restrição malformada → unavailable, nunca histórico silencioso', () {
      expect(
        classifyHealthSummaryAttentionDestination(item('restriction:')),
        isA<HealthSummaryAttentionUnavailableDestination>(),
      );
      expect(
        classifyHealthSummaryAttentionDestination(item('restriction:a/b')),
        isA<HealthSummaryAttentionUnavailableDestination>(),
      );
      expect(
        classifyHealthSummaryAttentionDestination(
          item('restriction:abc$nul'),
        ),
        isA<HealthSummaryAttentionUnavailableDestination>(),
      );
    });

    test('agenda e nutrição preservam a semântica existente', () {
      expect(
        classifyHealthSummaryAttentionDestination(
          item('att-1', hint: 'agenda'),
        ),
        isA<HealthSummaryAttentionAgendaDestination>(),
      );
      expect(
        classifyHealthSummaryAttentionDestination(
          item('att-2', hint: 'nutricao'),
        ),
        isA<HealthSummaryAttentionNutritionDestination>(),
      );
      // Mesma tolerância de substring do callback atual.
      expect(
        classifyHealthSummaryAttentionDestination(
          item('att-3', hint: 'ver agenda de vacinas'),
        ),
        isA<HealthSummaryAttentionAgendaDestination>(),
      );
    });

    test('alerta e item desconhecido → histórico', () {
      expect(
        classifyHealthSummaryAttentionDestination(item('alert:weight_stale')),
        isA<HealthSummaryAttentionHistoryDestination>(),
      );
      expect(
        classifyHealthSummaryAttentionDestination(item('att-9')),
        isA<HealthSummaryAttentionHistoryDestination>(),
      );
      expect(
        classifyHealthSummaryAttentionDestination(
          item('att-9', hint: 'historico'),
        ),
        isA<HealthSummaryAttentionHistoryDestination>(),
      );
    });

    test('N restrições simultâneas mantêm identidades separadas', () {
      final destinations = [
        'restriction:or_1',
        'restriction:or_2',
        'restriction:or_3',
      ].map((id) => classifyHealthSummaryAttentionDestination(item(id))).toList();

      expect(destinations, [
        const HealthSummaryAttentionRestrictionDestination('or_1'),
        const HealthSummaryAttentionRestrictionDestination('or_2'),
        const HealthSummaryAttentionRestrictionDestination('or_3'),
      ]);
    });

    test('identidade não vem de título, subtítulo nem posição', () {
      // Duas restrições com título idêntico continuam distintas.
      const a = HealthSummaryAttentionItem(
        id: 'restriction:or_first',
        title: 'Lesão em membro anterior',
        subtitle: 'Ativa',
      );
      const b = HealthSummaryAttentionItem(
        id: 'restriction:or_second',
        title: 'Lesão em membro anterior',
        subtitle: 'Ativa',
      );

      expect(
        classifyHealthSummaryAttentionDestination(a),
        const HealthSummaryAttentionRestrictionDestination('or_first'),
      );
      expect(
        classifyHealthSummaryAttentionDestination(b),
        const HealthSummaryAttentionRestrictionDestination('or_second'),
      );
    });
  });

  test('prefixo exposto é o literal congelado', () {
    expect(kReadinessRestrictionProjectionPrefix, 'restriction:');
  });
}
