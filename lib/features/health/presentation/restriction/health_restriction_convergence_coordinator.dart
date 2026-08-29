import 'package:flutter/foundation.dart';

import '../../data/coexistence/summary/health_readiness_convergence_gateway.dart';
import '../../domain/health_readiness_convergence.dart';

/// Fase causal de um comando de restrição já commitado.
///
/// B4-R.C3. Autoridade: `docs/health/adr/ADR-009-READINESS-PROJECTION-CAUSAL-CONSISTENCY.md`.
///
/// ```text
/// idle → converging → converged
///                  ↘ failed  (mutation CONTINUA commitada)
/// ```
enum HealthRestrictionConvergencePhase {
  /// Nenhuma mutation commitada nesta sessão, ou nada a convergir ainda.
  idle,

  /// Refresh + releitura one-shot em voo.
  converging,

  /// Projeção provada causalmente posterior à mutation.
  converged,

  /// Não foi possível provar. A mutation permanece commitada.
  failed,
}

/// Estado causal compartilhado por ISSUE, END e CANCEL.
///
/// Existe para que os três controllers não dupliquem nem a máquina de estados
/// nem o predicado `generation >= required`. O predicado vive apenas em
/// [decideHealthReadinessConvergence]; este coordenador só orquestra fases.
///
/// ## Invariante central
///
/// `mutationCommitted` nunca volta para falso porque a convergência falhou. Uma
/// falha de convergência é um fato sobre a PROJEÇÃO, não sobre o comando.
final class HealthRestrictionConvergenceCoordinator {
  HealthRestrictionConvergenceCoordinator({
    required HealthReadinessConvergenceGateway gateway,
    required VoidCallback onChanged,
  }) : _gateway = gateway,
       _onChanged = onChanged;

  /// Obrigatória: não existe caminho em que uma mutation commita e nenhuma
  /// tentativa de convergência acontece. Tornar isto opcional reintroduziria um
  /// bypass silencioso — a barreira causal existiria sem ser usada.
  final HealthReadinessConvergenceGateway _gateway;
  final VoidCallback _onChanged;

  HealthRestrictionConvergencePhase _phase =
      HealthRestrictionConvergencePhase.idle;
  bool _mutationCommitted = false;
  String? _dogId;
  HealthReadinessConvergenceResult? _result;

  HealthRestrictionConvergencePhase get phase => _phase;

  /// Fato durável da sessão: o comando canônico foi aceito pelo backend.
  bool get mutationCommitted => _mutationCommitted;

  /// Resultado da última tentativa, incluindo a resposta do servidor.
  HealthReadinessConvergenceResult? get result => _result;

  bool get isConverged => _phase == HealthRestrictionConvergencePhase.converged;

  bool get convergenceFailed =>
      _phase == HealthRestrictionConvergencePhase.failed;

  /// Verdadeiro quando há uma mutation commitada cuja projeção não foi provada.
  ///
  /// É o estado em que a UI deve dizer "comando aplicado, sincronização não
  /// confirmada" — nunca "o comando falhou".
  bool get needsConvergenceRetry =>
      _mutationCommitted &&
      _phase == HealthRestrictionConvergencePhase.failed;

  /// Registra o commit da mutation e dispara UMA tentativa de convergência.
  ///
  /// [dogId] é capturado aqui e reutilizado em todo retry: a seleção de cão pode
  /// mudar enquanto o trabalho assíncrono está em voo, e a convergência precisa
  /// permanecer ligada ao cão cuja mutation commitou.
  Future<void> onMutationCommitted(String dogId) async {
    _mutationCommitted = true;
    _dogId = dogId;
    await _attempt();
  }

  /// Retenta apenas a convergência. NUNCA repete a mutation.
  ///
  /// Não chama ISSUE/END/CANCEL, não gera novo `operationId`, não recria
  /// HealthDocument e não reenvia arquivo. Executa somente refresh + releitura
  /// one-shot + prova local.
  Future<void> retryConvergence() async {
    if (!_mutationCommitted) return;
    if (_phase == HealthRestrictionConvergencePhase.converging) return;
    if (_phase == HealthRestrictionConvergencePhase.converged) return;
    await _attempt();
  }

  Future<void> _attempt() async {
    final dogId = _dogId;
    // Só é null antes do primeiro commit, e `retryConvergence` já barra esse
    // caso via `mutationCommitted`. Não é bypass: é ordem de chamada.
    if (dogId == null) return;

    _phase = HealthRestrictionConvergencePhase.converging;
    _onChanged();

    final result = await _gateway.converge(dogId);
    _result = result;
    _phase = result.isConverged
        ? HealthRestrictionConvergencePhase.converged
        : HealthRestrictionConvergencePhase.failed;
    _onChanged();
  }
}
