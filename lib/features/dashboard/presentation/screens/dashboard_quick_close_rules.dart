part of 'dashboard_screen.dart';

Set<String> _quickCloseDefaultOutcomesForSubtype(String? subtype) {
  switch (subtype) {
    case 'supportVehicle':
    case 'serviceOrder':
    case 'event':
    case 'other':
      return {'Apoio prestado'};
    default:
      return <String>{};
  }
}

List<String> _quickCloseOutcomeOptionsForSubtype(String? subtype) {
  switch (subtype) {
    case 'detection':
    case 'narcoticsSearch':
      return const [
        'Droga apreendida',
        'Indivíduo detido',
        'Apoio prestado',
        'BO elaborado',
        'Encaminhamento médico',
        'Sem constatação',
      ];
    case 'supportVehicle':
      return const [
        'Apoio prestado',
        'Indivíduo detido',
        'Encaminhamento médico',
        'BO elaborado',
        'Local preservado',
        'Sem constatação',
      ];
    case 'missingPerson':
      return const [
        'Pessoa localizada',
        'Objeto localizado',
        'Apoio prestado',
        'Encaminhamento médico',
        'BO elaborado',
        'Sem constatação',
      ];
    case 'serviceOrder':
      return const [
        'Apoio prestado',
        'BO elaborado',
        'Local preservado',
        'Encaminhamento médico',
        'Sem constatação',
      ];
    case 'event':
      return const [
        'Apoio prestado',
        'Ação educativa concluída',
        'BO elaborado',
        'Sem constatação',
      ];
    case 'other':
      return const [
        'Apoio prestado',
        'Vítima socorrida',
        'Encaminhamento médico',
        'Trânsito sinalizado',
        'Local preservado',
        'BO elaborado',
        'Sem constatação',
      ];
    default:
      return const ['Apoio prestado', 'BO elaborado', 'Sem constatação'];
  }
}

String _buildQuickCloseResultSummary({
  required Set<String> selectedOutcomes,
  required bool operationalSuccess,
}) {
  if (_containsOutcome(selectedOutcomes, 'Droga apreendida')) {
    return 'Apreensão positiva';
  }
  if (_containsOutcome(selectedOutcomes, 'Pessoa localizada')) {
    return 'Sucesso';
  }
  if (_containsOutcome(selectedOutcomes, 'Indivíduo detido')) {
    return 'Indivíduo detido';
  }
  if (_containsOutcome(selectedOutcomes, 'Vítima socorrida')) {
    return 'Vítima socorrida';
  }
  if (_containsOutcome(selectedOutcomes, 'Encaminhamento médico')) {
    return 'Encaminhamento médico';
  }
  if (_containsOutcome(selectedOutcomes, 'Trânsito sinalizado')) {
    return 'Trânsito sinalizado';
  }
  if (_containsOutcome(selectedOutcomes, 'Local preservado')) {
    return 'Local preservado';
  }
  if (_containsOutcome(selectedOutcomes, 'Ação educativa concluída')) {
    return 'Ação educativa concluída';
  }
  if (_containsOutcome(selectedOutcomes, 'Apoio prestado')) {
    return 'Apoio prestado';
  }
  if (_containsOutcome(selectedOutcomes, 'BO elaborado')) {
    return 'BO elaborado';
  }
  if (_containsOutcome(selectedOutcomes, 'Sem constatação')) {
    return 'Sem constatação';
  }
  return operationalSuccess ? 'Êxito' : 'Sem êxito';
}
