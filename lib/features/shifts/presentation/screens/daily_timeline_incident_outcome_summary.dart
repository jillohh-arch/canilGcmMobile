part of 'daily_timeline_screen.dart';

extension _DailyTimelineIncidentOutcomeSummary on _DailyTimelineScreenState {
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
}
