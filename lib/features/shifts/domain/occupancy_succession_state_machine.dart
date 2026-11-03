/// Máquina de estados pura para sucessão de ocupação.
///
/// Define transições válidas entre estados de uma [OccupancySession] com base
/// no veredito de cobertura. Não representa transações Firestore, não produz
/// liberação automática e não cria sessões sucessoras diretamente.
///
/// Regras fundamentais:
/// - BLOCKING nunca permite sucessão.
/// - INDETERMINATE nunca permite sucessão.
/// - Somente PROVEN_CLEAR permite prosseguir.
/// - Mesmo PROVEN_CLEAR não produz liberação automática; sucessão efetiva
///   depende de confirmação de autoridade futura.
/// - Geração/sessão obsoleta (stale) não pode atingir estado sucessor.
/// - Repetição da mesma operação não cria segunda sucessora.
library;

import 'occupancy_coverage.dart';
import 'occupancy_session.dart';

/// Resultado de uma transição proposta pela máquina de estados.
class SuccessionTransition {
  /// Novo estado resultante da transição.
  final OccupancySessionState newState;

  /// Se a transição foi aceita (válida).
  final bool accepted;

  /// Razão da rejeição, quando [accepted] é false.
  final String? rejectionReason;

  const SuccessionTransition({
    required this.newState,
    required this.accepted,
    this.rejectionReason,
  });

  @override
  String toString() =>
      'SuccessionTransition(newState: $newState, accepted: $accepted, '
      'rejectionReason: $rejectionReason)';
}

/// Propõe uma transição de estado baseada na solicitação de auto-regularização.
///
/// Transição válida apenas se a sessão estiver em [OccupancySessionState.active].
SuccessionTransition proposeSelfRegularizationRequest(
  OccupancySession session,
) {
  if (session.state == OccupancySessionState.stale) {
    return const SuccessionTransition(
      newState: OccupancySessionState.stale,
      accepted: false,
      rejectionReason: 'Stale session cannot request self-regularization',
    );
  }
  if (session.state != OccupancySessionState.active) {
    return SuccessionTransition(
      newState: session.state,
      accepted: false,
      rejectionReason:
          'Self-regularization request only valid from active state, '
          'current: ${session.state}',
    );
  }
  return const SuccessionTransition(
    newState: OccupancySessionState.selfRegularizationRequested,
    accepted: true,
  );
}

/// Propõe uma transição de estado baseada no veredito de cobertura.
///
/// Regras:
/// - [CoverageVerdict.blocking] → successionDenied
/// - [CoverageVerdict.indeterminate] → permanece em selfRegularizationRequested
///   (não permite avançar)
/// - [CoverageVerdict.provenClear] → coverageValidated
SuccessionTransition proposeCoverageEvaluation(
  OccupancySession session,
  CoverageVerdict verdict,
) {
  if (session.state == OccupancySessionState.stale) {
    return const SuccessionTransition(
      newState: OccupancySessionState.stale,
      accepted: false,
      rejectionReason: 'Stale session cannot evaluate coverage',
    );
  }
  if (session.state != OccupancySessionState.selfRegularizationRequested) {
    return SuccessionTransition(
      newState: session.state,
      accepted: false,
      rejectionReason:
          'Coverage evaluation only valid from selfRegularizationRequested '
          'state, current: ${session.state}',
    );
  }

  switch (verdict) {
    case CoverageVerdict.blocking:
      return const SuccessionTransition(
        newState: OccupancySessionState.successionDenied,
        accepted: true,
      );
    case CoverageVerdict.indeterminate:
      // Indeterminate não permite avançar; mantém estado atual.
      return const SuccessionTransition(
        newState: OccupancySessionState.selfRegularizationRequested,
        accepted: false,
        rejectionReason:
            'Indeterminate coverage does not allow succession to proceed',
      );
    case CoverageVerdict.provenClear:
      return const SuccessionTransition(
        newState: OccupancySessionState.coverageValidated,
        accepted: true,
      );
  }
}

/// Propõe a permissão de sucessão após cobertura validada.
///
/// Esta transição NÃO libera a viatura automaticamente. Sucessão efetiva
/// depende de confirmação de autoridade futura. Apenas marca que a sessão
/// está elegível para sucessão.
SuccessionTransition proposeSuccessionPermission(OccupancySession session) {
  if (session.state == OccupancySessionState.stale) {
    return const SuccessionTransition(
      newState: OccupancySessionState.stale,
      accepted: false,
      rejectionReason: 'Stale session cannot be granted succession',
    );
  }
  if (session.state != OccupancySessionState.coverageValidated) {
    return SuccessionTransition(
      newState: session.state,
      accepted: false,
      rejectionReason:
          'Succession permission only valid from coverageValidated state, '
          'current: ${session.state}',
    );
  }
  return const SuccessionTransition(
    newState: OccupancySessionState.successionAllowed,
    accepted: true,
  );
}

/// Propõe a negação de sucessão por conflito ou regra de negócio.
SuccessionTransition proposeSuccessionDenial(
  OccupancySession session,
  String reason,
) {
  if (session.state == OccupancySessionState.stale) {
    return const SuccessionTransition(
      newState: OccupancySessionState.stale,
      accepted: false,
      rejectionReason: 'Stale session cannot be denied succession',
    );
  }
  // Pode ser negada de selfRegularizationRequested ou coverageValidated.
  if (session.state != OccupancySessionState.selfRegularizationRequested &&
      session.state != OccupancySessionState.coverageValidated) {
    return SuccessionTransition(
      newState: session.state,
      accepted: false,
      rejectionReason:
          'Succession denial only valid from selfRegularizationRequested or '
          'coverageValidated state, current: ${session.state}',
    );
  }
  return SuccessionTransition(
    newState: OccupancySessionState.successionDenied,
    accepted: true,
    rejectionReason: reason,
  );
}

/// Marca a sessão como stale (obsoleta).
///
/// Uma sessão stale não pode mais progredir em nenhuma transição.
SuccessionTransition proposeStale(OccupancySession session) {
  if (session.state == OccupancySessionState.stale) {
    // Já é stale; repetição não muda nada.
    return const SuccessionTransition(
      newState: OccupancySessionState.stale,
      accepted: false,
      rejectionReason: 'Session is already stale',
    );
  }
  // Estados terminais não podem ser marcados stale.
  if (session.state == OccupancySessionState.successionAllowed ||
      session.state == OccupancySessionState.successionDenied ||
      session.state == OccupancySessionState.conflicted) {
    return SuccessionTransition(
      newState: session.state,
      accepted: false,
      rejectionReason:
          'Terminal state ${session.state} cannot transition to stale',
    );
  }
  return const SuccessionTransition(
    newState: OccupancySessionState.stale,
    accepted: true,
  );
}

/// Marca a sessão como conflicted.
SuccessionTransition proposeConflict(OccupancySession session) {
  if (session.state == OccupancySessionState.stale) {
    return const SuccessionTransition(
      newState: OccupancySessionState.stale,
      accepted: false,
      rejectionReason: 'Stale session cannot transition to conflicted',
    );
  }
  if (session.state == OccupancySessionState.conflicted) {
    return const SuccessionTransition(
      newState: OccupancySessionState.conflicted,
      accepted: false,
      rejectionReason: 'Session is already conflicted',
    );
  }
  // Estados terminais de sucessão não podem virar conflicted.
  if (session.state == OccupancySessionState.successionAllowed ||
      session.state == OccupancySessionState.successionDenied) {
    return SuccessionTransition(
      newState: session.state,
      accepted: false,
      rejectionReason:
          'Terminal state ${session.state} cannot transition to conflicted',
    );
  }
  return const SuccessionTransition(
    newState: OccupancySessionState.conflicted,
    accepted: true,
  );
}