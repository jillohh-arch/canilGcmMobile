/// Contrato puro de sessão de ocupação de viatura.
///
/// Esta classe é imutável e não depende de Firestore, Firebase, UI ou
/// qualquer efeito colateral. Ela expressa a identidade e o estado de uma
/// ocupação, mas NÃO inicia nem libera viaturas reais.
library;

/// Estados possíveis de uma sessão de ocupação.
enum OccupancySessionState {
  /// Sessão ativa, sem solicitação de regularização pendente.
  active,

  /// Auto-regularização solicitada, aguardando validação de cobertura.
  selfRegularizationRequested,

  /// Cobertura validada com evidência autoritativa completa.
  coverageValidated,

  /// Sucessão permitida (depende de confirmação de autoridade futura).
  successionAllowed,

  /// Sucessão negada por regra de negócio ou cobertura insuficiente.
  successionDenied,

  /// Conflito detectado entre sessões ou gerações.
  conflicted,

  /// Sessão obsoleta/stale, não pode mais progredir.
  stale,
}

/// Representa uma sessão de ocupação de viatura, imutável após criação.
///
/// Cada sessão pertence a uma [vehicleId] específica e possui uma [generation]
/// monotônica crescente por viatura. A [crewId] identifica a guarnição no
/// momento da criação, mas NÃO é garantido ser globalmente única entre
/// gerações diferentes.
class OccupancySession {
  /// Identificador único da sessão.
  final String sessionId;

  /// Identificador da viatura associada.
  final String vehicleId;

  /// Identificador da guarnição no momento desta sessão.
  ///
  /// Não assuma unicidade global entre gerações.
  final String crewId;

  /// Geração monotônica da ocupação para esta viatura.
  ///
  /// Sempre > 0. Uma sucessão válida incrementa exatamente 1.
  final int generation;

  /// Referência ao predecessor imediato, se existir.
  ///
  /// Null para a primeira geração. Quando presente, deve corresponder
  /// à sessão cuja geração é exatamente [generation] - 1.
  final String? predecessorSessionId;

  /// Estado atual da sessão.
  final OccupancySessionState state;

  const OccupancySession({
    required this.sessionId,
    required this.vehicleId,
    required this.crewId,
    required this.generation,
    required this.state,
    this.predecessorSessionId,
  })  : assert(generation > 0, 'generation must be > 0'),
        assert(sessionId != '', 'sessionId must not be empty'),
        assert(vehicleId != '', 'vehicleId must not be empty'),
        assert(crewId != '', 'crewId must not be empty');

  /// Cria uma nova sessão validada, lançando [ArgumentError] se inválida.
  factory OccupancySession.validated({
    required String sessionId,
    required String vehicleId,
    required String crewId,
    required int generation,
    required OccupancySessionState state,
    String? predecessorSessionId,
  }) {
    if (sessionId.isEmpty) {
      throw ArgumentError.value(sessionId, 'sessionId', 'must not be empty');
    }
    if (vehicleId.isEmpty) {
      throw ArgumentError.value(vehicleId, 'vehicleId', 'must not be empty');
    }
    if (crewId.isEmpty) {
      throw ArgumentError.value(crewId, 'crewId', 'must not be empty');
    }
    if (generation <= 0) {
      throw ArgumentError.value(
        generation,
        'generation',
        'must be > 0',
      );
    }
    return OccupancySession(
      sessionId: sessionId,
      vehicleId: vehicleId,
      crewId: crewId,
      generation: generation,
      state: state,
      predecessorSessionId: predecessorSessionId,
    );
  }

  /// Cria uma sessão sucessora válida a partir desta sessão.
  ///
  /// A nova sessão terá [generation] + 1 e referenciará esta sessão como
  /// predecessor. Lança [StateError] se esta sessão estiver stale ou já
  /// tiver atingido um estado terminal que impede sucessão.
  OccupancySession createSuccessor({
    required String newSessionId,
    required String newCrewId,
    OccupancySessionState initialState = OccupancySessionState.active,
  }) {
    if (state == OccupancySessionState.stale) {
      throw StateError(
        'Cannot create successor from stale session $sessionId',
      );
    }
    if (state == OccupancySessionState.successionAllowed ||
        state == OccupancySessionState.successionDenied ||
        state == OccupancySessionState.conflicted) {
      throw StateError(
        'Session $sessionId is in terminal state $state and cannot produce a successor',
      );
    }
    return OccupancySession.validated(
      sessionId: newSessionId,
      vehicleId: vehicleId,
      crewId: newCrewId,
      generation: generation + 1,
      state: initialState,
      predecessorSessionId: sessionId,
    );
  }

  /// Retorna uma cópia desta sessão com o estado alterado.
  OccupancySession copyWithState(OccupancySessionState newState) {
    return OccupancySession(
      sessionId: sessionId,
      vehicleId: vehicleId,
      crewId: crewId,
      generation: generation,
      state: newState,
      predecessorSessionId: predecessorSessionId,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is OccupancySession &&
          runtimeType == other.runtimeType &&
          sessionId == other.sessionId &&
          vehicleId == other.vehicleId &&
          crewId == other.crewId &&
          generation == other.generation &&
          predecessorSessionId == other.predecessorSessionId &&
          state == other.state;

  @override
  int get hashCode => Object.hash(
        sessionId,
        vehicleId,
        crewId,
        generation,
        predecessorSessionId,
        state,
      );

  @override
  String toString() =>
      'OccupancySession(sessionId: $sessionId, vehicleId: $vehicleId, '
      'crewId: $crewId, generation: $generation, state: $state, '
      'predecessorSessionId: $predecessorSessionId)';
}