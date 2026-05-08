part of 'daily_timeline_screen.dart';

extension _DailyTimelineIncidentOutcomes on _DailyTimelineScreenState {
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
          'Indivíduo detido',
          'BO elaborado',
          'Sem constatação',
        ];
      default:
        return const [
          'Apoio prestado',
          'Indivíduo detido',
          'BO elaborado',
          'Sem constatação',
        ];
    }
  }

  String? _prioritizedQuickCloseOutcomeSummary(
    Set<String> outcomes,
    String? subtype,
  ) {
    if (outcomes.contains('Droga apreendida')) {
      return 'Apreensão Positiva';
    }
    if (subtype == 'missingPerson' && outcomes.contains('Pessoa localizada')) {
      return 'Sucesso';
    }
    if (outcomes.contains('Indivíduo detido')) {
      return 'Indivíduo detido';
    }
    if (outcomes.contains('Vítima socorrida')) {
      return 'Vítima socorrida';
    }
    if (outcomes.contains('Encaminhamento médico')) {
      return 'Encaminhamento médico';
    }
    if (outcomes.contains('Trânsito sinalizado')) {
      return 'Trânsito sinalizado';
    }
    if (outcomes.contains('Local preservado')) {
      return 'Local preservado';
    }
    if (outcomes.contains('Ação educativa concluída')) {
      return 'Ação educativa concluída';
    }
    if (outcomes.contains('Apoio prestado')) {
      return 'Apoio prestado';
    }
    if (outcomes.contains('BO elaborado')) {
      return 'BO elaborado';
    }
    if (outcomes.contains('Sem constatação')) {
      return 'Sem constatação';
    }

    return null;
  }

  String _buildQuickCloseResultSummary({
    required Incident incident,
    required Set<String> selectedOutcomes,
    required bool operationalSuccess,
  }) {
    final summary = _prioritizedQuickCloseOutcomeSummary(
      selectedOutcomes,
      incident.type,
    );
    if (summary != null) {
      return summary;
    }
    return operationalSuccess ? 'Êxito' : 'Sem êxito';
  }
}
