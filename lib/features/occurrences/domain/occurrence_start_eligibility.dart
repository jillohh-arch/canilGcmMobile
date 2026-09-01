/// FF-OCC-03 — elegibilidade para ABRIR uma nova ocorrência.
///
/// Por que isto existe: o operador entrava no formulário sem guarnição e só
/// descobria o impedimento na submissão, com a mensagem prefixada por
/// "Erro ao criar ocorrência: StateError...". A guarda precoce move essa
/// verificação para antes da navegação.
///
/// Fronteira de autoridade — importante:
///
/// * Isto é PRÉ-CONDIÇÃO DE UX, não autoridade documental. A validação final
///   (`_buildGuarnicaoSnapshot`) permanece a autoridade: ela consulta o
///   `VehicleCrewService`, confere se a guarnição está ativa e se o condutor
///   está confirmado entre os membros. Nada disso é reproduzido aqui.
/// * `ready` NÃO é suficiente para submeter. A viatura pode ser liberada entre
///   a navegação e o envio, e nesse caso a validação final ainda recusa.
///
/// Por que `vehicleCrewId` e não `hasVehicle`:
///
/// * `ShiftViewModel.hasVehicle` é `_session?.hasVehicle ?? false`, então
///   `false` também significa "sessão ainda não carregou", "erro" e "sem
///   turno". Usá-lo como gatilho bloquearia o operador durante a janela de
///   carregamento do turno (até 8s). Por isso `loading` tem precedência.
/// * `hasVehicle` lê `vehicleId`; a validação final exige `vehicleCrewId`.
///   O `fromJson` da sessão lê esses campos de chaves Firestore independentes
///   (`vehicle_id` vs `vehicle_crew_id`/`crew_id`), logo um documento pode
///   hidratar com um e sem o outro. Exigir `vehicleCrewId` espelha exatamente
///   o mínimo que o caminho autoritativo já exige — fail-closed para criação.
library;

/// Estados possíveis antes de permitir a abertura de uma nova ocorrência.
enum OccurrenceStartEligibility {
  /// Estado do turno ainda carregando. NUNCA apresentar como "sem viatura".
  loading,

  /// Estado do turno indisponível por erro. Distinto de pré-requisito ausente.
  shiftError,

  /// Nenhum turno ativo.
  noActiveShift,

  /// Turno ativo, porém sem guarnição/viatura assumida.
  noVehicleCrew,

  /// Pré-condições de UX satisfeitas. A validação final continua valendo.
  ready;

  /// Único estado que autoriza navegar para o formulário de abertura.
  bool get canStart => this == OccurrenceStartEligibility.ready;
}

/// Avalia a elegibilidade a partir de fatos já observáveis no estado de turno.
///
/// Recebe fatos, não o `ShiftViewModel`, para permanecer pura e testável sem
/// Flutter, Provider ou Firebase. Não faz I/O e não muta nada.
///
/// `vehicleId` deliberadamente NÃO é parâmetro: ele não participa da decisão,
/// e aceitá-lo abriria espaço para reintroduzir o falso `ready` que o
/// FF-OCC-03.P1 rejeitou.
///
/// Precedência congelada: carregando → erro → sem turno → sem guarnição →
/// pronto.
OccurrenceStartEligibility evaluateOccurrenceStartEligibility({
  required bool isLoading,
  required String? shiftError,
  required bool hasActiveShift,
  required String? vehicleCrewId,
}) {
  if (isLoading) return OccurrenceStartEligibility.loading;
  if (shiftError?.trim().isNotEmpty == true) {
    return OccurrenceStartEligibility.shiftError;
  }
  if (!hasActiveShift) return OccurrenceStartEligibility.noActiveShift;
  if (vehicleCrewId?.trim().isNotEmpty != true) {
    return OccurrenceStartEligibility.noVehicleCrew;
  }
  return OccurrenceStartEligibility.ready;
}

/// Mensagem operacional para cada estado que impede a abertura.
///
/// Compartilhada pelos dois entrypoints para evitar divergência de texto entre
/// eles. `ready` não tem mensagem — o fluxo simplesmente segue.
///
/// As redações de `noActiveShift` e `noVehicleCrew` reutilizam o texto
/// operacional já estabelecido no projeto, preservando o contrato atual.
String? occurrenceStartBlockMessage(OccurrenceStartEligibility eligibility) {
  return switch (eligibility) {
    OccurrenceStartEligibility.loading =>
      'Carregando dados do turno. Aguarde um instante.',
    OccurrenceStartEligibility.shiftError =>
      'Nao foi possivel confirmar o turno ativo. Tente novamente.',
    OccurrenceStartEligibility.noActiveShift =>
      'Inicie um turno para registrar ocorrência.',
    OccurrenceStartEligibility.noVehicleCrew =>
      'Assuma uma viatura antes de abrir ocorrência operacional.',
    OccurrenceStartEligibility.ready => null,
  };
}
