/// Convergência causal de Prontidão — contrato de consumo do Mobile.
///
/// B4-R.C3. Autoridade documental: `docs/health/adr/ADR-009-READINESS-PROJECTION-CAUSAL-CONSISTENCY.md`.
/// Contrato executável: `functions/src/health_readiness_generation.ts` e
/// `functions/src/health_readiness_callable.ts` (baselines C1 `7af9a3b`, C2 `002009a`).
///
/// ## Duas fases distintas
///
/// ```text
/// mutation COMMITTED     → fato canônico no backend
/// projection CONVERGED   → a projeção observável já reflete essa mutation
/// ```
///
/// Falhar em provar a segunda **nunca** desfaz a primeira. Confundir as duas é
/// exatamente o defeito que este módulo existe para impedir: dizer ao operador
/// que a restrição não foi registrada quando ela foi.
///
/// ## O Mobile não calcula prontidão
///
/// Nada aqui avalia estado clínico. Este módulo apenas compara gerações para
/// decidir se o snapshot que o app acabou de ler é causalmente posterior à
/// mutation. O veredito clínico continua sendo do servidor.
library;

/// Status causal retornado pelo servidor em `result.convergence.status`.
///
/// Vocabulário fechado (ADR-009 §11). Não existe membro genérico de falha:
/// erros de autenticação, autorização, integridade e transporte continuam sendo
/// erros normais do callable, então um `failed` aqui seria ambíguo.
enum HealthReadinessServerConvergence {
  confirmed,
  notConfirmed,
  unavailable;

  /// Aceita **somente** os três literais congelados. Qualquer outro valor é
  /// contrato desconhecido, não um quarto estado tolerável.
  static HealthReadinessServerConvergence? fromWire(Object? wire) =>
      switch (wire) {
        'confirmed' => HealthReadinessServerConvergence.confirmed,
        'not_confirmed' => HealthReadinessServerConvergence.notConfirmed,
        'unavailable' => HealthReadinessServerConvergence.unavailable,
        _ => null,
      };
}

/// Resposta causal do servidor, já tipada.
///
/// Preservada mesmo quando a prova local depois discorda dela: distinguir
/// "barreira do servidor" de "prova do snapshot local" é útil para diagnóstico
/// e para a UI futura (B4-C).
final class HealthReadinessServerConvergenceReport {
  const HealthReadinessServerConvergenceReport({
    required this.status,
    required this.requiredGeneration,
    required this.observedGeneration,
  });

  final HealthReadinessServerConvergence status;

  /// Generation reservada por esta execução do refresh. Sempre presente, > 0.
  final int requiredGeneration;

  /// Generation READY observada pelo servidor, ou `null` quando não havia
  /// nenhuma observável. Nunca `0`.
  final int? observedGeneration;
}

/// Por que o contrato causal não pôde ser lido da resposta do refresh.
enum HealthReadinessConvergenceContractFailure {
  /// Resposta sem `result.convergence`. É o caso de rollout: Mobile novo contra
  /// backend anterior a C2. Não é erro do operador nem falha da mutation.
  contractAbsent,

  /// `result.convergence` presente mas inutilizável: status desconhecido,
  /// `requiredGeneration` ausente/zero/negativo/fracionário/textual, ou
  /// `observedGeneration` de tipo inválido. Falha fechada.
  contractMalformed,
}

/// Marcador causal lido de `dogs/{dogId}/health_summary/current`.
///
/// Deliberadamente separado de `ReadinessSnapshot`: legibilidade do snapshot e
/// elegibilidade causal são perguntas diferentes (ADR-009 §16). Um documento sem
/// `projection_generation` continua exibível pelas regras legadas, mas não pode
/// provar causalidade.
final class HealthReadinessCausalMarker {
  const HealthReadinessCausalMarker({
    required this.isReady,
    required this.generation,
  });

  /// `projection_status == "ready"` no documento observado.
  final bool isReady;

  /// `projection_generation` válido, ou `null` quando ausente ou malformado.
  ///
  /// `null` significa "sem prova disponível" e só pode reduzir a convergência,
  /// nunca aumentá-la. Um `0` fabricado seria um número que convida a
  /// aritmética e pode ser confundido com generation real.
  final int? generation;

  /// Lê o marcador de um documento cru, falhando fechado em qualquer anomalia.
  ///
  /// Não lança: entrada inutilizável vira `generation: null`, que a prova causal
  /// trata como ausência de prova.
  static HealthReadinessCausalMarker fromDocument(
    Map<String, Object?>? data,
  ) {
    if (data == null) {
      return const HealthReadinessCausalMarker(isReady: false, generation: null);
    }
    final rawStatus = data['projection_status'];
    final rawGeneration = data['projection_generation'];

    return HealthReadinessCausalMarker(
      isReady: rawStatus == 'ready',
      generation: _parseGeneration(rawGeneration),
    );
  }

  /// Aceita apenas inteiro estritamente positivo. `double`, `String`, `bool`,
  /// `null`, zero e negativos são recusados — nunca convertidos.
  static int? _parseGeneration(Object? raw) {
    if (raw is! int) return null;
    if (raw <= 0) return null;
    return raw;
  }
}

/// Resultado causal final para o Mobile.
enum HealthReadinessConvergenceOutcome {
  /// O snapshot atual É causalmente posterior à mutation. Pode renderizar.
  converged,

  /// Fluxo completo, sem prova suficiente, e sem indisponibilidade factual.
  notConfirmed,

  /// Prontidão tecnicamente indisponível no estado observado.
  unavailable,

  /// Backend não expõe o contrato causal (rollout backend-first pendente).
  contractUnavailable,

  /// Falha ao chamar o refresh ou ao reler o snapshot.
  readFailure,

  /// Contrato presente mas malformado. Falha fechada, nunca convergido.
  integrityFailure;

  bool get isConverged => this == HealthReadinessConvergenceOutcome.converged;
}

/// Resultado completo de uma tentativa de convergência.
final class HealthReadinessConvergenceResult {
  const HealthReadinessConvergenceResult({
    required this.outcome,
    this.serverReport,
    this.contractFailure,
    this.observedMarker,
  });

  final HealthReadinessConvergenceOutcome outcome;

  /// Resposta causal do servidor, quando pôde ser lida.
  final HealthReadinessServerConvergenceReport? serverReport;

  /// Motivo da indisponibilidade do contrato, quando aplicável.
  final HealthReadinessConvergenceContractFailure? contractFailure;

  /// Marcador local que produziu (ou não) a prova.
  final HealthReadinessCausalMarker? observedMarker;

  bool get isConverged => outcome.isConverged;
}

/// Decide a convergência a partir da resposta do servidor e do snapshot local.
///
/// ## Precedência: a prova LOCAL é a autoridade final
///
/// A resposta do callable fornece `requiredGeneration` e uma observação
/// server-side; ela é a **barreira**, não a fotografia que será renderizada.
/// Entre a resposta HTTP e a releitura do Mobile o estado pode ter mudado nas
/// duas direções, e o app só pode renderizar o que acabou de ler:
///
/// ```text
/// servidor unavailable  +  local READY H >= G   → converged
///     (um READY mais novo foi aplicado no intervalo; prova válida)
///
/// servidor confirmed    +  local unavailable    → unavailable
///     (não renderizar convergido com base em fotografia antiga)
/// ```
///
/// ## Por que `>=` e não `==`
///
/// Toda generation maior que `G` foi reservada depois de `G`, que por sua vez
/// foi reservada depois do commit da mutation. Por transitividade, um READY
/// superior leu estado ao menos tão novo (ADR-009 §12.1). Exigir igualdade faria
/// a convergência falhar para sempre quando outra entrada ganhasse a corrida.
///
/// ## Por que a generation sozinha não basta
///
/// Uma escrita `unavailable` preserva o marcador READY anterior como
/// last-known-good. Portanto `(unavailable, 42)` contra `required 42` significa
/// "42 não foi revalidada", não "42 está provada" (ADR-009 §13.2).
HealthReadinessConvergenceResult decideHealthReadinessConvergence({
  required HealthReadinessServerConvergenceReport serverReport,
  required HealthReadinessCausalMarker observedMarker,
}) {
  final generation = observedMarker.generation;

  // 1. Prova observada primeiro, qualquer que tenha sido o status do servidor.
  if (observedMarker.isReady &&
      generation != null &&
      generation >= serverReport.requiredGeneration) {
    return HealthReadinessConvergenceResult(
      outcome: HealthReadinessConvergenceOutcome.converged,
      serverReport: serverReport,
      observedMarker: observedMarker,
    );
  }

  // 2. Sem prova: reportar a indisponibilidade factual quando existir. O estado
  //    local observado tem precedência sobre o desfecho da execução do servidor.
  if (!observedMarker.isReady ||
      serverReport.status == HealthReadinessServerConvergence.unavailable) {
    return HealthReadinessConvergenceResult(
      outcome: HealthReadinessConvergenceOutcome.unavailable,
      serverReport: serverReport,
      observedMarker: observedMarker,
    );
  }

  // 3. Snapshot legível e ready, mas sem prova causal suficiente.
  return HealthReadinessConvergenceResult(
    outcome: HealthReadinessConvergenceOutcome.notConfirmed,
    serverReport: serverReport,
    observedMarker: observedMarker,
  );
}
