class OccurrenceFormController {
  static const statusInProgress = 'Em andamento';
  static const statusCompleted = 'Concluída';
  static const statusCanceled = 'Cancelada';

  static const natureDetection = 'Detecção';
  static const natureSupportVehicle = 'Apoio à Viatura/Guarnição';
  static const natureMissingPerson = 'Busca de Pessoa';
  static const natureServiceOrder = 'Ordem de Serviço (O.S.)';
  static const natureEvent = 'Palestra/Evento (RP)';
  static const natureOther = 'Outros';
  static const natureNarcoticsSearch = 'Busca de Entorpecentes';

  static String normalizeStatus(String? value) {
    final raw = value?.trim() ?? '';
    final normalized = _normalizeForMatch(raw);

    if (normalized.contains('andamento')) return statusInProgress;
    if (normalized.contains('cancel')) return statusCanceled;
    if (normalized.contains('conclu')) return statusCompleted;

    return raw.isEmpty ? statusCompleted : raw;
  }

  static String normalizeNature(String? value) {
    final raw = value?.trim() ?? '';
    final normalized = _normalizeForMatch(raw);

    if (normalized.contains('entorpec')) return natureNarcoticsSearch;
    if (normalized.contains('detec')) return natureDetection;
    if (normalized.contains('apoio')) return natureSupportVehicle;
    if (normalized.contains('pessoa')) return natureMissingPerson;
    if (normalized.contains('ordem')) return natureServiceOrder;
    if (normalized.contains('palestra') || normalized.contains('evento')) {
      return natureEvent;
    }
    if (normalized.contains('outro')) return natureOther;

    return raw;
  }

  static String normalizeOutcome(String value) {
    final normalized = _normalizeForMatch(value);

    if (normalized.contains('droga')) return 'Droga apreendida';
    if (normalized.contains('objeto')) return 'Objetos apreendidos';
    if (normalized.contains('detido') &&
        (normalized.contains('veiculo') || normalized.contains('veiculos'))) {
      return 'Veículos detidos';
    }
    if (normalized.contains('detido')) return 'Indivíduo detido';
    if (normalized.contains('apoio')) return 'Apoio prestado';
    if (normalized.contains('bo')) return 'BO elaborado';
    if (normalized.contains('medico')) return 'Encaminhamento médico';
    if (normalized.contains('constata')) return 'Sem constatação';
    if (normalized.contains('localizada')) return 'Pessoa localizada';
    if (normalized.contains('educativa')) return 'Ação educativa concluída';
    if (normalized.contains('preservado')) return 'Local preservado';
    if (normalized.contains('transito')) return 'Trânsito sinalizado';
    if (normalized.contains('vitima')) return 'Vítima socorrida';

    return value;
  }

  int step = 0;
  String status = statusCompleted;
  bool? successful = true;
  final Set<String> outcomes = {};

  void startNewOccurrence() {
    status = statusInProgress;
    successful = null;
    outcomes.clear();
    step = 0;
  }

  void selectNature(String nature) {
    outcomes
      ..clear()
      ..addAll(defaultOutcomesForNature(nature));
  }

  void setStatus(String value) {
    status = value;
    if (value == statusInProgress) {
      successful = null;
    } else {
      successful ??= true;
    }
  }

  bool toggleOutcome(String option) {
    if (outcomes.contains(option)) {
      outcomes.remove(option);
      return false;
    }

    outcomes.add(option);
    return true;
  }

  bool get isFinalizing => status != statusInProgress;

  String resultSummary({required String? nature, required String fallback}) {
    if (status == statusInProgress) {
      return statusInProgress;
    }

    if (status == statusCanceled) {
      return statusCanceled;
    }

    final summary = prioritizedOutcomeSummary(outcomes, nature);
    if (summary != null) {
      return summary;
    }

    if (successful == true) {
      return 'Êxito';
    }

    if (successful == false) {
      return 'Sem êxito';
    }

    return fallback;
  }

  List<String> outcomeOptionsForNature(String? nature) {
    switch (normalizeNature(nature)) {
      case natureDetection:
      case natureNarcoticsSearch:
        return const [
          'Droga apreendida',
          'Objetos apreendidos',
          'Veículos detidos',
          'Indivíduo detido',
          'Apoio prestado',
          'BO elaborado',
          'Encaminhamento médico',
          'Sem constatação',
        ];
      case natureSupportVehicle:
        return const [
          'Apoio prestado',
          'Droga apreendida',
          'Objetos apreendidos',
          'Veículos detidos',
          'Indivíduo detido',
          'Encaminhamento médico',
          'BO elaborado',
          'Local preservado',
          'Sem constatação',
        ];
      case natureMissingPerson:
        return const [
          'Pessoa localizada',
          'Objeto localizado',
          'Droga apreendida',
          'Objetos apreendidos',
          'Veículos detidos',
          'Apoio prestado',
          'Encaminhamento médico',
          'BO elaborado',
          'Sem constatação',
        ];
      case natureServiceOrder:
        return const [
          'Apoio prestado',
          'Droga apreendida',
          'Objetos apreendidos',
          'Veículos detidos',
          'BO elaborado',
          'Local preservado',
          'Encaminhamento médico',
          'Sem constatação',
        ];
      case natureEvent:
        return const [
          'Apoio prestado',
          'Droga apreendida',
          'Objetos apreendidos',
          'Ação educativa concluída',
          'BO elaborado',
          'Sem constatação',
        ];
      case natureOther:
        return const [
          'Apoio prestado',
          'Droga apreendida',
          'Objetos apreendidos',
          'Veículos detidos',
          'Vítima socorrida',
          'Encaminhamento médico',
          'Trânsito sinalizado',
          'Local preservado',
          'Indivíduo detido',
          'BO elaborado',
          'Sem constatação',
        ];
      default:
        return const [
          'Apoio prestado',
          'Droga apreendida',
          'Objetos apreendidos',
          'Veículos detidos',
          'Indivíduo detido',
          'BO elaborado',
          'Sem constatação',
        ];
    }
  }

  Set<String> defaultOutcomesForNature(String? nature) {
    switch (normalizeNature(nature)) {
      case natureSupportVehicle:
      case natureServiceOrder:
      case natureEvent:
      case natureOther:
        return {'Apoio prestado'};
      default:
        return <String>{};
    }
  }

  bool hasOutcomeContaining(String token) {
    final normalizedToken = _normalizeForMatch(token);
    return outcomes.any(
      (outcome) => _normalizeForMatch(outcome).contains(normalizedToken),
    );
  }

  bool hasVehicleOutcome() {
    return hasOutcomeContaining('veículo');
  }

  bool hasDetainedIndividualOutcome() {
    return hasOutcomeContaining('detido') && !hasVehicleOutcome();
  }

  bool hasObjectOutcome() {
    return hasOutcomeContaining('objeto');
  }

  bool hasDrugOutcome() {
    return hasOutcomeContaining('droga');
  }

  String? prioritizedOutcomeSummary(
    Iterable<String> selectedOutcomes,
    String? nature,
  ) {
    final outcomeSet = selectedOutcomes.map(normalizeOutcome).toSet();
    final normalizedNature = normalizeNature(nature);

    if (outcomeSet.contains('Droga apreendida')) {
      return 'Apreensão positiva';
    }
    if (normalizedNature == natureMissingPerson &&
        outcomeSet.contains('Pessoa localizada')) {
      return 'Sucesso';
    }
    if (outcomeSet.contains('Indivíduo detido')) {
      return 'Indivíduo detido';
    }
    if (outcomeSet.contains('Vítima socorrida')) {
      return 'Vítima socorrida';
    }
    if (outcomeSet.contains('Encaminhamento médico')) {
      return 'Encaminhamento médico';
    }
    if (outcomeSet.contains('Trânsito sinalizado')) {
      return 'Trânsito sinalizado';
    }
    if (outcomeSet.contains('Local preservado')) {
      return 'Local preservado';
    }
    if (outcomeSet.contains('Ação educativa concluída')) {
      return 'Ação educativa concluída';
    }
    if (outcomeSet.contains('Apoio prestado')) {
      return 'Apoio prestado';
    }
    if (outcomeSet.contains('BO elaborado')) {
      return 'BO elaborado';
    }
    if (outcomeSet.contains('Sem constatação')) {
      return 'Sem constatação';
    }

    return null;
  }

  static String _normalizeForMatch(String value) {
    return value
        .toLowerCase()
        .replaceAll(RegExp('[áàâãä]'), 'a')
        .replaceAll(RegExp('[éèêë]'), 'e')
        .replaceAll(RegExp('[íìîï]'), 'i')
        .replaceAll(RegExp('[óòôõö]'), 'o')
        .replaceAll(RegExp('[úùûü]'), 'u')
        .replaceAll('ç', 'c');
  }
}
