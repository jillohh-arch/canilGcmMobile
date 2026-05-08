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
}
