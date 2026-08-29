/// Boundary de identidade entre a projeção de Prontidão e o detalhe canônico.
///
/// B4-C.1. Autoridade de contrato: `docs/health/adr/ADR-009-READINESS-PROJECTION-CAUSAL-CONSISTENCY.md`
/// para a separação projeção × canônico, e B4-B2 para o gateway canônico.
///
/// ## Por que esta boundary existe
///
/// A seção de Atenções expõe itens cujo `id` é um identificador de PROJEÇÃO:
///
/// ```text
/// restriction:<canonicalRestrictionId>     (health_summary_readiness_reader.dart)
/// alert:<alertCode>
/// ```
///
/// O gateway canônico (`FirestoreHealthRestrictionReadGateway`) exige o
/// `restrictionId` canônico puro e **recusa** o prefixo de projeção — de
/// propósito: aceitá-lo faria um `get()` em path errado e devolveria
/// `not-found` por acaso, mascarando o acoplamento indevido.
///
/// A tradução pertence portanto ao consumidor da projeção, e vive aqui, em UM
/// único lugar. Nenhum widget deve fazer `replaceFirst('restriction:', '')`.
///
/// ## O que este módulo NÃO faz
///
/// Não lê Firestore. Não calcula prontidão. Não interpreta nível de restrição.
/// Não decide permissão. Não navega. Trata exclusivamente de IDENTIDADE e de
/// INTENÇÃO de destino.
library;

import 'package:canil_gcm/features/health/presentation/summary/health_summary_block_models.dart';

/// Prefixo literal de projeção para restrições operacionais.
///
/// Case-sensitive e sem aliases: `restrictions:`, `operational_restriction:` e
/// variantes NÃO são aceitas. Fuzzy matching aqui produziria navegação para um
/// documento que não existe.
const String kReadinessRestrictionProjectionPrefix = 'restriction:';

/// Resultado tipado do parse de um id de projeção.
///
/// Distingue explicitamente "não é restrição" de "é restrição mas está
/// corrompida": a primeira é rotina (alertas clínicos usam `alert:`), a segunda
/// é anomalia técnica que não pode virar acesso ao Firestore nem degradar em
/// silêncio.
sealed class ReadinessRestrictionProjectionId {
  const ReadinessRestrictionProjectionId();
}

/// Restrição reconhecida; carrega o id canônico exato.
final class ReadinessRestrictionProjectionIdParsed
    extends ReadinessRestrictionProjectionId {
  const ReadinessRestrictionProjectionIdParsed(this.canonicalRestrictionId);

  /// Id canônico preservado byte a byte após remover apenas o prefixo.
  final String canonicalRestrictionId;

  @override
  bool operator ==(Object other) =>
      other is ReadinessRestrictionProjectionIdParsed &&
      other.canonicalRestrictionId == canonicalRestrictionId;

  @override
  int get hashCode => canonicalRestrictionId.hashCode;
}

/// O id não pertence ao namespace de restrição (ex.: `alert:...`).
final class ReadinessRestrictionProjectionIdNotRestriction
    extends ReadinessRestrictionProjectionId {
  const ReadinessRestrictionProjectionIdNotRestriction();

  @override
  bool operator ==(Object other) =>
      other is ReadinessRestrictionProjectionIdNotRestriction;

  @override
  int get hashCode => 0x1;
}

/// Prefixo presente, mas o restante é inutilizável como id canônico.
final class ReadinessRestrictionProjectionIdMalformed
    extends ReadinessRestrictionProjectionId {
  const ReadinessRestrictionProjectionIdMalformed();

  @override
  bool operator ==(Object other) =>
      other is ReadinessRestrictionProjectionIdMalformed;

  @override
  int get hashCode => 0x2;
}

/// Traduz um id de projeção em id canônico de restrição, falhando fechado.
///
/// Remove EXCLUSIVAMENTE a camada de identidade da projeção. Não normaliza
/// case, não faz trim do miolo, não reescreve separadores — o id canônico é
/// identidade opaca, exatamente como o gateway canônico o trata.
///
/// A validação aqui é estrutural (segurança de path segment), não semântica:
/// não existe um segundo validador de id canônico competindo com o backend.
/// Rejeitamos apenas o que jamais poderia ser um document id válido.
ReadinessRestrictionProjectionId parseReadinessRestrictionProjectionId(
  String projectionId,
) {
  if (!projectionId.startsWith(kReadinessRestrictionProjectionPrefix)) {
    // Inclui string vazia, `alert:...`, `restrictions:...`, `Restriction:...`
    // e qualquer id com whitespace à esquerda — o wire da projeção precisa
    // estar correto, e um trim silencioso mudaria a identidade observada.
    return const ReadinessRestrictionProjectionIdNotRestriction();
  }

  final canonical = projectionId.substring(
    kReadinessRestrictionProjectionPrefix.length,
  );

  if (canonical.isEmpty) {
    return const ReadinessRestrictionProjectionIdMalformed();
  }

  // Prefixo aninhado (`restriction:restriction:abc`) e `restriction::abc` são
  // corrupção do produtor, nunca um id legítimo.
  if (canonical.startsWith(kReadinessRestrictionProjectionPrefix) ||
      canonical.startsWith(':')) {
    return const ReadinessRestrictionProjectionIdMalformed();
  }

  // Segurança de path segment, mesma disciplina do backend (`assertSafeDogId`):
  // um id com `/`, whitespace, `.` ou `..` não é um document id.
  if (canonical != canonical.trim() ||
      canonical.contains('/') ||
      canonical.contains(' ') ||
      canonical == '.' ||
      canonical == '..') {
    return const ReadinessRestrictionProjectionIdMalformed();
  }

  // Caracteres de controle (NUL incluso) NÃO são removidos por `trim()` em
  // Dart, então exigem rejeição explícita: um id com NUL jamais é um document
  // id legítimo e não pode alcançar o gateway canônico.
  for (final unit in canonical.codeUnits) {
    if (unit <= 0x1F || unit == 0x7F) {
      return const ReadinessRestrictionProjectionIdMalformed();
    }
  }

  return ReadinessRestrictionProjectionIdParsed(canonical);
}

/// Intenção de destino de um item de Atenções.
///
/// Puro: descreve para ONDE o item aponta, sem executar navegação. B4-C.2
/// consumirá `restriction` para abrir o detalhe canônico; até lá nenhum call
/// site de produção usa esta classificação, e o comportamento visível atual
/// permanece intacto.
sealed class HealthSummaryAttentionDestination {
  const HealthSummaryAttentionDestination();
}

/// Agenda (vacinação/dose pendente).
final class HealthSummaryAttentionAgendaDestination
    extends HealthSummaryAttentionDestination {
  const HealthSummaryAttentionAgendaDestination();

  @override
  bool operator ==(Object other) =>
      other is HealthSummaryAttentionAgendaDestination;

  @override
  int get hashCode => 0x11;
}

/// Nutrição.
final class HealthSummaryAttentionNutritionDestination
    extends HealthSummaryAttentionDestination {
  const HealthSummaryAttentionNutritionDestination();

  @override
  bool operator ==(Object other) =>
      other is HealthSummaryAttentionNutritionDestination;

  @override
  int get hashCode => 0x12;
}

/// Detalhe canônico de UMA restrição operacional específica.
///
/// A identidade vem exclusivamente do item tocado. Nunca de descrição, nível,
/// categoria, índice, posição ou contagem — dois registros com a mesma
/// descrição precisam continuar distintos.
final class HealthSummaryAttentionRestrictionDestination
    extends HealthSummaryAttentionDestination {
  const HealthSummaryAttentionRestrictionDestination(
    this.canonicalRestrictionId,
  );

  final String canonicalRestrictionId;

  @override
  bool operator ==(Object other) =>
      other is HealthSummaryAttentionRestrictionDestination &&
      other.canonicalRestrictionId == canonicalRestrictionId;

  @override
  int get hashCode => canonicalRestrictionId.hashCode;
}

/// Histórico clínico — fallback atual para itens sem destino específico.
final class HealthSummaryAttentionHistoryDestination
    extends HealthSummaryAttentionDestination {
  const HealthSummaryAttentionHistoryDestination();

  @override
  bool operator ==(Object other) =>
      other is HealthSummaryAttentionHistoryDestination;

  @override
  int get hashCode => 0x13;
}

/// Item de restrição com id de projeção corrompido.
///
/// Deliberadamente NÃO é `history`: o chamador deve poder registrar a anomalia
/// em diagnóstico em vez de degradar em silêncio, ainda que a navegação segura
/// resultante seja equivalente a um fallback.
final class HealthSummaryAttentionUnavailableDestination
    extends HealthSummaryAttentionDestination {
  const HealthSummaryAttentionUnavailableDestination();

  @override
  bool operator ==(Object other) =>
      other is HealthSummaryAttentionUnavailableDestination;

  @override
  int get hashCode => 0x14;
}

/// Classifica o destino de um item de Atenções.
///
/// Ordem deliberada: a identidade de restrição é avaliada ANTES do fallback
/// genérico, porque hoje nenhum produtor de produção preenche
/// `destinationHint` — sem essa precedência toda restrição cairia em histórico
/// e o `id` seria descartado.
///
/// `destinationHint` continua sendo consultado para agenda/nutrição, mantendo
/// a semântica existente para os itens que a usarem.
HealthSummaryAttentionDestination classifyHealthSummaryAttentionDestination(
  HealthSummaryAttentionItem item,
) {
  final parsed = parseReadinessRestrictionProjectionId(item.id);
  switch (parsed) {
    case ReadinessRestrictionProjectionIdParsed(:final canonicalRestrictionId):
      return HealthSummaryAttentionRestrictionDestination(
        canonicalRestrictionId,
      );
    case ReadinessRestrictionProjectionIdMalformed():
      return const HealthSummaryAttentionUnavailableDestination();
    case ReadinessRestrictionProjectionIdNotRestriction():
      break;
  }

  final hint = (item.destinationHint ?? '').toLowerCase();
  if (hint.contains('agenda')) {
    return const HealthSummaryAttentionAgendaDestination();
  }
  if (hint.contains('nutri')) {
    return const HealthSummaryAttentionNutritionDestination();
  }
  return const HealthSummaryAttentionHistoryDestination();
}
